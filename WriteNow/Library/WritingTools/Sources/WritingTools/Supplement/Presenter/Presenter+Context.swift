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

        let decorationViews: [UIView]

        let textProxy: TextProxy
        let launchSlotAction: RuntimeSelectionMenuItem?
        @Published var scenePhase: ScenePhase = .active

        init(
            parentView: UIView,
            parentController: UIViewController,
            targetView: UIView,
            anchorView: UIView,
            anchorRects: [CGRect],
            decorationViews: [UIView],
            textProxy: TextProxy,
            launchSlotAction: RuntimeSelectionMenuItem? = nil
        ) {
            self.parentView = parentView
            self.parentController = parentController
            self.targetView = targetView
            self.anchorView = anchorView
            self.anchorRects = anchorRects
            self.decorationViews = decorationViews
            self.textProxy = textProxy
            self.launchSlotAction = launchSlotAction

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
    func buildContext(fromResponder responder: UIResponder, launchSlotAction: RuntimeSelectionMenuItem? = nil) -> Context? {
        guard let fatherView = responder as? UIView else { return nil }
        guard let parentView = fatherView.superview ?? fatherView.window else { return nil }
        guard let parentController = fatherView.parentViewController ?? fatherView.window?.rootViewController else { return nil }
        guard let textProxy = TextProxy(delegatingView: fatherView) else { return nil }
        let appearance = textProxy.appearanceForWritingTool
        guard textProxy.isEligibleForWritingTool else { return nil }

        return assembleContext(
            fatherView: fatherView,
            parentView: parentView,
            parentController: parentController,
            textProxy: textProxy,
            appearance: appearance,
            launchSlotAction: launchSlotAction
        )
    }

    func buildReadOnlyFallbackContext(from respondingView: UIView, launchSlotAction: RuntimeSelectionMenuItem? = nil) -> Context? {
        guard let textProxy = TextProxy.makeReadOnlyFallback(from: respondingView) else { return nil }
        guard let parentView = respondingView.superview ?? respondingView.window else { return nil }
        guard let parentController = respondingView.parentViewController ?? respondingView.window?.rootViewController else { return nil }
        return assembleContext(
            fatherView: respondingView,
            parentView: parentView,
            parentController: parentController,
            textProxy: textProxy,
            appearance: textProxy.appearanceForWritingTool,
            launchSlotAction: launchSlotAction
        )
    }

    private func assembleContext(
        fatherView: UIView,
        parentView: UIView,
        parentController: UIViewController,
        textProxy: TextProxy,
        appearance: TextProxy.WTAppearance,
        launchSlotAction: RuntimeSelectionMenuItem?
    ) -> Context {
        var selectedRects = textProxy.selectionRectsInView
        if selectedRects.isEmpty { selectedRects = [fatherView.bounds] }
        let selectionUnionRect = selectedRects.reduce(selectedRects[0]) { $0.union($1) }

        let anchorView = UIView()
        anchorView.frame = selectionUnionRect

        let textMaskView = UIView()
        fatherView.addSubview(textMaskView)
        textMaskView.frame = fatherView.bounds

        var preparedRects = selectedRects
        let maskShapeLayer = prepareUnionRectLayerMaskWithCornerRadius(
            withRects: &preparedRects,
            usingCoordinateFromView: fatherView,
            convertingToSubviewForMask: textMaskView,
            withCornerRadius: 4
        )
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

        let decorationViews = [backgroundView, textMaskView]

        return .init(
            parentView: parentView,
            parentController: parentController,
            targetView: fatherView,
            anchorView: anchorView,
            anchorRects: preparedRects,
            decorationViews: decorationViews,
            textProxy: textProxy,
            launchSlotAction: launchSlotAction
        )
    }

    func magicColorBackground() -> AnimatedMulticolorGradientView {
        let colors: [ColorVector] = Self.themeColorVectors()
        let magicColorView = AnimatedMulticolorGradientView()
        magicColorView.speed = Configurator.shared.settings.animatedBackground ? 1.0 : 0.0
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
