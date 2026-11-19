//
//  Presenter+Context.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/19.
//

import ColorfulX
import ColorVector
import SwiftUI

extension Presenter {
    class Context: NSObject, Identifiable, ObservableObject {
        let id: UUID = .init()

        let parentView: UIView
        let parentController: UIViewController
        let targetView: UIView

        let anchorView: UIView
        let anchorRects: [CGRect]
        let anchorRectsInWindow: [CGRect]

        let decorationViews: [UIView]

        let textProxy: TextProxy
        let launchSlotAction: RuntimeSelectionMenuItem?
        let prefetchedExternalContext: String?
        let initialAttachedImages: [AttachedImageItem]
        let onCompleteAndClose: (() -> Void)?
        @Published var scenePhase: ScenePhase = .active

        init(
            parentView: UIView,
            parentController: UIViewController,
            targetView: UIView,
            anchorView: UIView,
            anchorRects: [CGRect],
            decorationViews: [UIView],
            textProxy: TextProxy,
            launchSlotAction: RuntimeSelectionMenuItem? = nil,
            prefetchedExternalContext: String? = nil,
            initialAttachedImages: [AttachedImageItem] = [],
            onCompleteAndClose: (() -> Void)? = nil
        ) {
            self.parentView = parentView
            self.parentController = parentController
            self.targetView = targetView
            self.anchorView = anchorView
            self.anchorRects = anchorRects
            if let win = targetView.window {
                self.anchorRectsInWindow = anchorRects.map { targetView.convert($0, to: win) }
            } else {
                self.anchorRectsInWindow = anchorRects
            }
            self.decorationViews = decorationViews
            self.textProxy = textProxy
            self.launchSlotAction = launchSlotAction
            self.prefetchedExternalContext = prefetchedExternalContext
            self.initialAttachedImages = initialAttachedImages
            self.onCompleteAndClose = onCompleteAndClose

            super.init()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(sceneWillResignActive),
                name: UIApplication.willResignActiveNotification,
                object: nil
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(sceneDidBecomeActive),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(sceneWillEnterForeground),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(sceneDidEnterBackground),
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
        }

        @objc func sceneWillResignActive() {
            scenePhase = .inactive
        }

        @objc func sceneDidBecomeActive() {
            scenePhase = .active
        }

        @objc func sceneWillEnterForeground() {
            scenePhase = .active
        }

        @objc func sceneDidEnterBackground() {
            scenePhase = .background
        }
    }
}

extension Presenter {
    private static func resolveFallbackParentController(for view: UIView) -> UIViewController {
        if let vc = view.parentViewController {
            return vc
        }
        if let rootVC = view.window?.rootViewController {
            return rootVC
        }
        return UIViewController()
    }

    static func extractNotificationContext(around targetView: UIView) -> String? {
        guard let win = targetView.window else { return nil }
        let winClass = NSStringFromClass(type(of: win))
        let isSpringBoard = Bundle.main.bundleIdentifier == "com.apple.springboard"

        // Find platter container if inside NCNotification / PLPlatter hierarchy
        var platterRoot: UIView?
        var cursor: UIView? = targetView
        while let current = cursor {
            let cls = NSStringFromClass(type(of: current))
            if cls.contains("NCNotificationLongLook")
                || cls.contains("PLPlatter")
                || cls.contains("NCNotificationView")
                || cls.contains("Notification")
            {
                platterRoot = current
            }
            cursor = current.superview
        }

        let isNotificationContext = platterRoot != nil
            || winClass.contains("Notification")
            || winClass.contains("Banner")
            || (isSpringBoard && win.windowLevel != .normal)
        guard isNotificationContext else { return nil }

        let searchRoot = platterRoot ?? win
        let targetOriginY = targetView.convert(CGPoint.zero, to: searchRoot).y

        var pieces: [(y: CGFloat, text: String)] = []
        var seen = Set<String>()

        func walk(_ node: UIView) {
            guard node !== targetView, !node.isDescendant(of: targetView) else { return }
            guard !node.isHidden, node.alpha > 0.05 else { return }
            let cls = NSStringFromClass(type(of: node))
            if cls.contains("Keyboard") || cls.contains("UIKB") || cls.contains("WriteNow") { return }

            var rawText: String?
            if let label = node as? UILabel {
                rawText = label.text
            } else if let tv = node as? UITextView, !tv.isEditable {
                rawText = tv.text
            }

            if let raw = rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
               raw.count >= 2
            {
                let lower = raw.lowercased()
                let isTimestampOrChrome = lower == "reply"
                    || lower == "send"
                    || lower == "clear"
                    || lower == "now"
                    || lower == "open"
                    || lower == "vừa xong"
                    || lower == "bây giờ"
                    || lower.hasSuffix(" ago")
                    || lower.hasSuffix(" trước")
                    || lower.contains("more notification")
                    || lower.contains("thông báo nữa")
                    || (raw.count <= 6 && raw.contains(":") && raw.rangeOfCharacter(from: .decimalDigits) != nil)
                if !isTimestampOrChrome {
                    let frameInRoot = node.convert(node.bounds, to: searchRoot)
                    if frameInRoot.height >= 8,
                       frameInRoot.maxY <= targetOriginY + 24,
                       seen.insert(raw).inserted
                    {
                        pieces.append((frameInRoot.minY, raw))
                    }
                }
            }
            for sub in node.subviews {
                walk(sub)
            }
        }

        walk(searchRoot)
        let ordered = pieces.sorted { $0.y < $1.y }.map(\.text)
        let joined = ordered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return nil }
        if joined.count <= 1500 { return joined }
        return String(joined.suffix(1500))
    }

    func buildContext(fromResponder responder: UIResponder, launchSlotAction: RuntimeSelectionMenuItem? = nil) -> Context? {
        guard let fatherView = responder as? UIView else { return nil }
        guard let parentView = fatherView.superview ?? fatherView.window else { return nil }
        let parentController = Self.resolveFallbackParentController(for: fatherView)
        guard let textProxy = TextProxy(delegatingView: fatherView) else { return nil }
        let appearance = textProxy.appearanceForWritingTool
        guard textProxy.isEligibleForWritingTool else { return nil }

        return assembleContext(
            fatherView: fatherView,
            parentView: parentView,
            parentController: parentController,
            textProxy: textProxy,
            appearance: appearance,
            launchSlotAction: launchSlotAction,
            prefetchedExternalContext: Self.extractNotificationContext(around: fatherView)
        )
    }

    func buildReadOnlyFallbackContext(from respondingView: UIView, launchSlotAction: RuntimeSelectionMenuItem? = nil) -> Context? {
        guard let textProxy = TextProxy.makeReadOnlyFallback(from: respondingView) else { return nil }
        guard let parentView = respondingView.superview ?? respondingView.window else { return nil }
        let parentController = Self.resolveFallbackParentController(for: respondingView)
        return assembleContext(
            fatherView: respondingView,
            parentView: parentView,
            parentController: parentController,
            textProxy: textProxy,
            appearance: textProxy.appearanceForWritingTool,
            launchSlotAction: launchSlotAction,
            prefetchedExternalContext: Self.extractNotificationContext(around: respondingView)
        )
    }

    func buildExtractedTextContext(
        text: String,
        hostView: UIView,
        parentController: UIViewController?,
        anchorRectInHost: CGRect,
        launchSlotAction: RuntimeSelectionMenuItem? = nil,
        initialAttachedImages: [AttachedImageItem] = [],
        onCompleteAndClose: (() -> Void)? = nil
    ) -> Context? {
        guard let textProxy = TextProxy.makeReadOnlyWithText(
            text,
            view: hostView,
            selectionRect: anchorRectInHost,
            allowEmpty: !initialAttachedImages.isEmpty
        ) else {
            return nil
        }
        guard let parentView = hostView.superview ?? hostView.window ?? hostView as UIView? else { return nil }
        let resolvedVC = parentController ?? Self.resolveFallbackParentController(for: hostView)
        return assembleContext(
            fatherView: hostView,
            parentView: parentView,
            parentController: resolvedVC,
            textProxy: textProxy,
            appearance: textProxy.appearanceForWritingTool,
            launchSlotAction: launchSlotAction,
            prefetchedExternalContext: Self.extractNotificationContext(around: hostView),
            initialAttachedImages: initialAttachedImages,
            onCompleteAndClose: onCompleteAndClose
        )
    }

    private func assembleContext(
        fatherView: UIView,
        parentView: UIView,
        parentController: UIViewController,
        textProxy: TextProxy,
        appearance: TextProxy.WTAppearance,
        launchSlotAction: RuntimeSelectionMenuItem?,
        prefetchedExternalContext: String? = nil,
        initialAttachedImages: [AttachedImageItem] = [],
        onCompleteAndClose: (() -> Void)? = nil
    ) -> Context {
        let hasSelectedContent = !textProxy.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var selectedRects = textProxy.selectionRectsInView.filter { $0.width > 0 && $0.height > 0 }
        if selectedRects.isEmpty {
            let fallbackRect = CGRect(
                x: max(4, min(fatherView.bounds.midX - 24, fatherView.bounds.width - 48)),
                y: 4,
                width: max(40, min(fatherView.bounds.width - 8, 200)),
                height: max(24, min(fatherView.bounds.height - 8, 36))
            )
            selectedRects = [fallbackRect]
        }
        let selectionUnionRect = selectedRects.reduce(selectedRects[0]) { $0.union($1) }

        let anchorView = UIView()
        anchorView.frame = CGRect(
            x: selectionUnionRect.origin.x,
            y: selectionUnionRect.origin.y,
            width: max(24, selectionUnionRect.width),
            height: max(24, selectionUnionRect.height)
        )

        var decorationViews: [UIView] = []
        var preparedRects = selectedRects

        if hasSelectedContent {
            let textMaskView = UIView()
            fatherView.addSubview(textMaskView)
            textMaskView.frame = fatherView.bounds

            let maskShapeLayer = prepareUnionRectLayerMaskWithCornerRadius(
                withRects: &preparedRects,
                usingCoordinateFromView: fatherView,
                convertingToSubviewForMask: textMaskView,
                withCornerRadius: 4
            )
            if !preparedRects.isEmpty {
                textMaskView.layer.addSublayer(maskShapeLayer)

                let backgroundView = magicColorBackground()
                fatherView.addSubview(backgroundView)
                backgroundView.frame = fatherView.bounds
                backgroundView.layer.mask = maskShapeLayer

                switch appearance.magicColorBehavior {
                case .behindText:
                    fatherView.sendSubviewToBack(backgroundView)
                case .overText:
                    fatherView.bringSubviewToFront(backgroundView)
                }

                decorationViews = [backgroundView, textMaskView]
            } else {
                textMaskView.removeFromSuperview()
            }
        }

        return .init(
            parentView: parentView,
            parentController: parentController,
            targetView: fatherView,
            anchorView: anchorView,
            anchorRects: preparedRects,
            decorationViews: decorationViews,
            textProxy: textProxy,
            launchSlotAction: launchSlotAction,
            prefetchedExternalContext: prefetchedExternalContext,
            initialAttachedImages: initialAttachedImages,
            onCompleteAndClose: onCompleteAndClose
        )
    }

    func magicColorBackground() -> UIView {
        if !Configurator.shared.settings.animatedBackground {
            let staticView = StaticGradientHighlightView(colors: Self.themeUIColors())
            staticView.clipsToBounds = true
            return staticView
        }
        let colors: [ColorVector] = Self.themeColorVectors()
        let magicColorView = AnimatedMulticolorGradientView()
        magicColorView.speed = 1.0
        magicColorView.transitionSpeed = 5.0
        magicColorView.clipsToBounds = true
        magicColorView.setColors(colors, animated: false)
        return magicColorView
    }

    static func themeUIColors() -> [UIColor] {
        let s = Configurator.shared.settings
        let presetHexMap: [String: [String]] = [
            "midnight_ocean": ["#0EA5E9", "#2563EB", "#1E1B4B", "#0F172A"],
            "aurora_borealis": ["#10B981", "#06B6D4", "#6366F1", "#0B1120"],
            "sunset_amber": ["#F97316", "#EF4444", "#DB2777", "#1F1024"],
            "cyberpunk_neon": ["#06B6D4", "#D946EF", "#7C3AED", "#09091A"],
            "obsidian_minimal": ["#475569", "#334155", "#1E293B", "#09090B"],
            "apple_intelligence": ["#F86594", "#A855F7", "#3B82F6", "#181029"],
        ]

        if s.backgroundMode == "solid" {
            let accent = uiColor(fromHex: s.accentColorHex) ?? UIColor.systemBlue
            let solid = uiColor(fromHex: s.solidBackgroundHex) ?? accent
            return [accent, solid, accent.withAlphaComponent(0.75), solid]
        }

        if s.menuThemePreset == "custom_colors" {
            let custom = s.customThemeColorsHex.compactMap { uiColor(fromHex: $0) }
            if custom.count >= 2 { return custom }
        }

        if s.backgroundMode == "image" {
            let accent = uiColor(fromHex: s.accentColorHex) ?? UIColor.systemBlue
            let base = (presetHexMap[s.menuThemePreset] ?? presetHexMap["midnight_ocean"]!)
                .compactMap { uiColor(fromHex: $0) }
            if !base.isEmpty {
                return [accent] + Array(base.prefix(3))
            }
        }

        let hexes = presetHexMap[s.menuThemePreset] ?? presetHexMap["midnight_ocean"]!
        let resolved = hexes.compactMap { uiColor(fromHex: $0) }
        if !resolved.isEmpty { return resolved }
        return ColorfulPreset.appleIntelligence.colors
    }

    static func themeColorVectors() -> [ColorVector] {
        themeUIColors().map { ColorVector($0) }
    }

    private static func uiColor(fromHex hexString: String) -> UIColor? {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        if hex.count == 6 {
            let r = CGFloat((value >> 16) & 0xFF) / 255.0
            let g = CGFloat((value >> 8) & 0xFF) / 255.0
            let b = CGFloat(value & 0xFF) / 255.0
            return UIColor(red: r, green: g, blue: b, alpha: 1.0)
        } else {
            let r = CGFloat((value >> 24) & 0xFF) / 255.0
            let g = CGFloat((value >> 16) & 0xFF) / 255.0
            let b = CGFloat((value >> 8) & 0xFF) / 255.0
            let a = CGFloat(value & 0xFF) / 255.0
            return UIColor(red: r, green: g, blue: b, alpha: a)
        }
    }

    private func prepareRects(_ rects: [CGRect], radius: CGFloat) -> [CGRect] {
        var processRects = [CGRect]()
        var lastMinY: CGFloat?
        for rect in rects {
            if let lastMinY, abs(rect.minY - lastMinY) < radius {
                let lastRect = processRects.removeLast()
                let unionRect = lastRect.union(rect)
                processRects.append(unionRect)
                continue
            }
            processRects.append(rect)
            lastMinY = rect.minY
        }
        return processRects
    }

    func prepareUnionRectLayerMaskWithCornerRadius(
        withRects rects: inout [CGRect],
        usingCoordinateFromView targetView: UIView,
        convertingToSubviewForMask maskView: UIView,
        withCornerRadius cornerRadius: CGFloat
    ) -> CAShapeLayer {
        let convertedRects = rects
            .map { targetView.convert($0, to: maskView) }
            .filter { $0.size.width > 0 && $0.size.height > 0 }
            .sorted { $0.minY < $1.minY }

        rects = prepareRects(convertedRects, radius: cornerRadius)
        let cornerRadii = CGSize(width: cornerRadius, height: cornerRadius)

        var allCorners = [UIRectCorner]()
        var firstMinX: CGFloat = 0
        var allMaxX: CGFloat = 0
        for i in 0 ..< rects.count {
            let convertedRect = rects[i]

            if convertedRect.width <= 0 || convertedRect.height <= 0 {
                assertionFailure()
                continue
            }

            var corners: UIRectCorner = []
            if i == 0 {
                firstMinX = convertedRect.minX
                corners.formUnion([.topLeft, .topRight])
            }
            if i == rects.count - 1 {
                if i > 0, abs(convertedRect.maxX - allMaxX) > cornerRadii.width {
                    var lastCorners = allCorners.removeLast()
                    lastCorners.formUnion([.bottomRight])
                    allCorners.append(lastCorners)
                }
                corners.formUnion([.bottomLeft, .bottomRight])
            }
            if i == 1, abs(convertedRect.minX - firstMinX) > cornerRadii.width {
                corners.formUnion([.topLeft])
            }
            if i == 1, convertedRect.maxX < firstMinX, rects.count == 2 {
                var lastCorners = allCorners.removeLast()
                lastCorners.formUnion([.bottomLeft])
                allCorners.append(lastCorners)
                corners.formUnion([.topRight])
            }
            allCorners.append(corners)
            allMaxX = max(allMaxX, convertedRect.maxX)
        }

        let path = UIBezierPath()
        for zip in zip(rects, allCorners) {
            let convertedRect = zip.0
            let corners = zip.1
            path.append(UIBezierPath(
                roundedRect: convertedRect,
                byRoundingCorners: corners,
                cornerRadii: cornerRadii
            ))
        }

        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        shapeLayer.fillColor = UIColor.white.cgColor
        return shapeLayer
    }
}

private final class StaticGradientHighlightView: UIView {
    private let gradientLayer = CAGradientLayer()

    init(colors: [UIColor]) {
        super.init(frame: .zero)
        gradientLayer.colors = colors.map(\.cgColor)
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradientLayer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
}
