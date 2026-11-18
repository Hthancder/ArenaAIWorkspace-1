//
//  Presenter+Open.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/16.
//

import ColorfulX
import Foundation
import SwiftUI
import UIKit

public extension Presenter {
    @objc(presentToolController:)
    func presentToolController(_ responder: UIResponder) {
        presentToolController(responder, slotIndex: 0)
    }

    @objc(presentToolController:slotIndex:)
    func presentToolController(_ responder: UIResponder, slotIndex: Int) {
        guard let respondingView = responder as? UIView else { return }

        let context: Context?
        if let targetView = TextProxy.lookupViewOfInterest(view: respondingView) {
            let launchAction = resolveLaunchItem(slotIndex: slotIndex, isReadOnly: targetView._isReadOnly)
            context = obtainContextFor(targetView, launchSlotAction: launchAction)
        } else {
            let launchAction = resolveLaunchItem(slotIndex: slotIndex, isReadOnly: true)
            context = buildReadOnlyFallbackContext(from: respondingView, launchSlotAction: launchAction)
        }

        guard let context else {
            Configurator.shared.refreshRuntimeConfig()
            presentUnavailable(respondingView)
            return
        }

        presentPopover(with: context)
    }

    @objc(presentFromRestrictedMenuTarget:fallbackCopyAction:slotIndex:)
    func presentFromRestrictedMenuTarget(_ targetView: UIView?, fallbackCopyAction: Any?, slotIndex: Int) {
        presentFromUniversalMenuTarget(
            targetView,
            windowPoint: .zero,
            fallbackCopyAction: fallbackCopyAction,
            slotIndex: slotIndex
        )
    }

    @objc(presentFromUniversalMenuTarget:windowPoint:fallbackCopyAction:slotIndex:)
    func presentFromUniversalMenuTarget(
        _ targetView: UIView?,
        windowPoint: CGPoint,
        fallbackCopyAction: Any?,
        slotIndex: Int
    ) {
        let resolvedTarget = targetView ?? Self.findActiveTargetFallbackView()

        if let resolvedTarget,
           let targetVOI = TextProxy.lookupViewOfInterest(view: resolvedTarget),
           let context = obtainContextFor(
               targetVOI,
               launchSlotAction: resolveLaunchItem(slotIndex: slotIndex, isReadOnly: targetVOI._isReadOnly)
           )
        {
            presentPopover(with: context)
            return
        }

        if let resolvedTarget,
           let context = buildReadOnlyFallbackContext(
               from: resolvedTarget,
               launchSlotAction: resolveLaunchItem(slotIndex: slotIndex, isReadOnly: true)
           )
        {
            presentPopover(with: context)
            return
        }

        TextProxy.extractTextNearPoint(windowPoint, in: resolvedTarget, fallbackCopyAction: fallbackCopyAction) { [weak self] result in
            guard let self else { return }
            if let result {
                self.presentExtractedText(
                    result.text,
                    fromHostView: result.targetView,
                    parentController: nil,
                    anchorRectInHost: result.rectInTarget,
                    slotIndex: slotIndex
                )
                return
            }
            self.runOCRFallbackOrUnavailable(
                anchorView: resolvedTarget,
                windowPoint: windowPoint,
                slotIndex: slotIndex
            )
        }
    }

    private func runOCRFallbackOrUnavailable(anchorView: UIView?, windowPoint: CGPoint, slotIndex: Int) {
        let targetWin = anchorView?.window ?? Self.findNormalAppWindow()
        guard let win = targetWin else {
            if let anchorView {
                presentUnavailable(anchorView)
            }
            return
        }
        TextProxy.extractTextViaOCRFallback(in: win, near: windowPoint) { [weak self] hit in
            guard let self else { return }
            if let hit {
                let host = anchorView ?? win
                let rectInHost = host.convert(hit.rectInWindow, from: win)
                self.presentExtractedText(
                    hit.text,
                    fromHostView: host,
                    parentController: nil,
                    anchorRectInHost: rectInHost.isEmpty ? host.bounds : rectInHost,
                    slotIndex: slotIndex
                )
            } else {
                ScreenPickerCoordinator.shared.presentPicker(in: win, forceFullOCR: false)
            }
        }
    }

    private static func findNormalAppWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden && $0.windowLevel == .normal }
            .sorted { lhs, rhs in lhs.isKeyWindow && !rhs.isKeyWindow }
            .first { !NSStringFromClass(type(of: $0)).contains("WriteNow") }
    }

    private static func findActiveTargetFallbackView() -> UIView? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden }
            .sorted { lhs, rhs in
                if lhs.windowLevel != rhs.windowLevel {
                    return lhs.windowLevel.rawValue > rhs.windowLevel.rawValue
                }
                return lhs.isKeyWindow && !rhs.isKeyWindow
            }
        for win in windows {
            let cls = NSStringFromClass(type(of: win))
            if cls.contains("WriteNow") { continue }
            if let fr = findFirstResponderView(in: win) {
                return fr
            }
        }
        return windows.first { !NSStringFromClass(type(of: $0)).contains("WriteNow") }
    }

    private static func findFirstResponderView(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for sub in view.subviews {
            if let hit = findFirstResponderView(in: sub) { return hit }
        }
        return nil
    }

    @objc(presentFromContextMenuView:windowPoint:slotIndex:fallbackCopyAction:)
    func presentFromContextMenuView(_ view: UIView?, windowPoint: CGPoint, slotIndex: Int, fallbackCopyAction: Any?) {
        TextProxy.extractTextNearPoint(windowPoint, in: view, fallbackCopyAction: fallbackCopyAction) { [weak self] result in
            guard let self else { return }
            if let result {
                self.presentExtractedText(
                    result.text,
                    fromHostView: result.targetView,
                    parentController: nil,
                    anchorRectInHost: result.rectInTarget,
                    slotIndex: slotIndex
                )
            } else {
                self.runOCRFallbackOrUnavailable(anchorView: view, windowPoint: windowPoint, slotIndex: slotIndex)
            }
        }
    }

    @objc(attachCopySheetAccessoryToPresentedVC:targetView:windowPoint:copyView:)
    func attachCopySheetAccessory(
        toPresentedVC presentedVC: UIViewController,
        targetView: UIView?,
        windowPoint: CGPoint,
        copyView: UIView?
    ) {
        guard let container = presentedVC.view, let win = container.window else { return }
        attachCopySheetPill(
            in: container,
            hostWindow: win,
            associatedOwner: presentedVC,
            targetView: targetView,
            windowPoint: windowPoint,
            copyView: copyView,
            dismissSheet: { [weak presentedVC] completion in
                guard let presentedVC, !presentedVC.isBeingDismissed else {
                    completion()
                    return
                }
                presentedVC.dismiss(animated: true, completion: completion)
            }
        )
    }

    @objc(attachCopySheetAccessoryToWindow:targetView:windowPoint:copyView:)
    func attachCopySheetAccessory(
        toWindow window: UIWindow,
        targetView: UIView?,
        windowPoint: CGPoint,
        copyView: UIView?
    ) {
        attachCopySheetPill(
            in: window,
            hostWindow: window,
            associatedOwner: window,
            targetView: targetView,
            windowPoint: windowPoint,
            copyView: copyView,
            dismissSheet: { completion in
                completion()
            }
        )
    }

    private func attachCopySheetPill(
        in container: UIView,
        hostWindow: UIWindow,
        associatedOwner: AnyObject,
        targetView: UIView?,
        windowPoint: CGPoint,
        copyView: UIView?,
        dismissSheet: @escaping (@escaping () -> Void) -> Void
    ) {
        let existing = objc_getAssociatedObject(associatedOwner, &CopySheetPillAssocKey.key) as? UIButton
        if let existing, existing.superview != nil {
            return
        }

        let btn = CopySheetWriteNowButton(type: .system)
        let title = writingToolMenuName()
        btn.setTitle("  \(title)", for: .normal)
        btn.setImage(UIImage(systemName: "sparkles"), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .semibold)
        btn.tintColor = .systemCyan
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.84)
        btn.layer.cornerRadius = 18
        btn.layer.borderWidth = 1
        btn.layer.borderColor = UIColor.systemCyan.withAlphaComponent(0.7).cgColor
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOpacity = 0.35
        btn.layer.shadowRadius = 8
        btn.layer.shadowOffset = CGSize(width: 0, height: 3)
        btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 14)
        btn.sizeToFit()

        let copyFrameInContainer: CGRect
        if let copyView {
            copyFrameInContainer = copyView.convert(copyView.bounds, to: container)
        } else {
            copyFrameInContainer = CGRect(x: 0, y: container.bounds.height * 0.65, width: container.bounds.width, height: 44)
        }

        let pillWidth = max(124, btn.bounds.width)
        let pillHeight: CGFloat = 36
        let safeTop = container.safeAreaInsets.top + 16
        let preferredY = max(safeTop, min(container.bounds.height - 90, copyFrameInContainer.minY - pillHeight - 14))
        let pillX = max(16, container.bounds.width - pillWidth - 16)
        btn.frame = CGRect(x: pillX, y: preferredY, width: pillWidth, height: pillHeight)
        btn.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin]
        btn.alpha = 0

        btn.onTap = { [weak self, weak btn, weak targetView, weak copyView] in
            guard let self else { return }
            btn?.isEnabled = false
            btn?.removeFromSuperview()
            let normalWin = Self.findNormalAppWindow() ?? hostWindow
            let resolvedTarget = targetView ?? Self.findActiveTargetFallbackView() ?? normalWin

            // 1. Try direct view/accessibility extraction first without disturbing pasteboard
            TextProxy.extractTextNearPoint(windowPoint, in: resolvedTarget, fallbackCopyAction: nil) { direct in
                if let direct {
                    dismissSheet {
                        self.presentExtractedText(
                            direct.text,
                            fromHostView: direct.targetView,
                            parentController: nil,
                            anchorRectInHost: direct.rectInTarget,
                            slotIndex: 0
                        )
                    }
                    return
                }

                // 2. Try triggering the sheet's Copy button/control while snapshotting pasteboard
                let pasteboard = UIPasteboard.general
                let savedItems = pasteboard.items
                let prevCount = pasteboard.changeCount
                var triggeredCopy = false
                if let copyView {
                    var cursor: UIView? = copyView
                    while let v = cursor {
                        if let ctrl = v as? UIControl {
                            ctrl.sendActions(for: .touchUpInside)
                            triggeredCopy = true
                            break
                        }
                        cursor = v.superview
                    }
                }

                let waitDelay: TimeInterval = triggeredCopy ? 0.28 : 0.05
                DispatchQueue.main.asyncAfter(deadline: .now() + waitDelay) {
                    if triggeredCopy, pasteboard.changeCount != prevCount,
                       let copied = pasteboard.string,
                       !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    {
                        pasteboard.items = savedItems
                        let host = resolvedTarget ?? normalWin
                        self.presentExtractedText(
                            copied,
                            fromHostView: host,
                            parentController: nil,
                            anchorRectInHost: host.bounds,
                            slotIndex: 0
                        )
                        return
                    }

                    // 3. Dismiss sheet cleanly and run OCR at touch point on the underlying post
                    dismissSheet {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                            self.runOCRFallbackOrUnavailable(
                                anchorView: resolvedTarget,
                                windowPoint: windowPoint,
                                slotIndex: 0
                            )
                        }
                    }
                }
            }
        }

        container.addSubview(btn)
        objc_setAssociatedObject(associatedOwner, &CopySheetPillAssocKey.key, btn, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        UIView.animate(withDuration: 0.2) {
            btn.alpha = 1
        }
    }

    func presentExtractedText(
        _ text: String,
        fromHostView hostView: UIView,
        parentController: UIViewController?,
        anchorRectInHost: CGRect,
        slotIndex: Int,
        initialAttachedImages: [AttachedImageItem] = [],
        onCompleteAndClose: (() -> Void)? = nil
    ) {
        let launchAction = resolveLaunchItem(slotIndex: slotIndex, isReadOnly: true)
        guard let context = buildExtractedTextContext(
            text: text,
            hostView: hostView,
            parentController: parentController,
            anchorRectInHost: anchorRectInHost,
            launchSlotAction: launchAction,
            initialAttachedImages: initialAttachedImages,
            onCompleteAndClose: onCompleteAndClose
        ) else {
            presentUnavailable(hostView)
            return
        }
        presentPopover(with: context)
    }

    private func presentPopover(with context: Context) {

        Configurator.shared.refreshRuntimeConfig { [weak context] _ in
            guard let context else { return }
            let vectors = Presenter.themeColorVectors()
            let animatedBg = Configurator.shared.settings.animatedBackground
            for dec in context.decorationViews {
                if let grad = dec as? AnimatedMulticolorGradientView {
                    grad.setColors(vectors, animated: true)
                    grad.speed = animatedBg ? 1.0 : 0.0
                }
            }
        }

        let targetView = context.targetView
        let anchorView = context.anchorView
        targetView.addSubview(anchorView)
        anchorView.frame = anchorView.frame.intersection(targetView.bounds)
        if anchorView.frame.width <= 0 || anchorView.frame.height <= 0 {
            anchorView.frame = targetView.bounds
        }

        let toolController = WritingToolController(context: context)
        let screenBounds = UIScreen.main.bounds
        let maxWidth = max(280, min(400, screenBounds.width - 18))
        let targetHeight: CGFloat
        switch Configurator.shared.settings.popoverSizePreset {
        case "compact":
            targetHeight = min(320, screenBounds.height * 0.52)
        case "large":
            targetHeight = min(460, screenBounds.height * 0.72)
        default:
            targetHeight = min(390, screenBounds.height * 0.62)
        }
        let fittingSize = toolController.view.systemLayoutSizeFitting(.init(
            width: maxWidth,
            height: UIView.layoutFittingCompressedSize.height
        ))
        let contentSize = CGSize(
            width: maxWidth,
            height: max(targetHeight, min(fittingSize.height, targetHeight))
        )

        toolController.basePreferredSize = contentSize
        toolController.view.backgroundColor = .black.withAlphaComponent(0.88)
        toolController.modalPresentationStyle = .popover
        toolController.preferredContentSize = contentSize
        toolController.popoverPresentationController?.delegate = context
        toolController.popoverPresentationController?.canOverlapSourceViewRect = true
        toolController.popoverPresentationController?.permittedArrowDirections = [.up, .down]

        let targetWindow = targetView.window
        let candidatePresenter = topMostPresenter(from: context.parentController)
        let needsDedicatedWindow = Self.requiresDedicatedOverlayWindow(
            for: targetWindow,
            presenterVC: candidatePresenter
        )

        if needsDedicatedWindow {
            let hostWindow: UIWindow
            if let scene = targetWindow?.windowScene {
                hostWindow = WriteNowPopoverHostWindow(windowScene: scene)
            } else {
                hostWindow = WriteNowPopoverHostWindow(frame: screenBounds)
            }
            hostWindow.frame = targetWindow?.bounds ?? screenBounds
            hostWindow.backgroundColor = .clear
            hostWindow.windowLevel = UIWindow.Level(
                rawValue: max((targetWindow?.windowLevel.rawValue ?? 0) + 5, UIWindow.Level.statusBar.rawValue + 100)
            )
            let hostRoot = UIViewController()
            hostRoot.view.backgroundColor = .clear
            hostWindow.rootViewController = hostRoot
            hostWindow.isHidden = false
            hostRoot.view.layoutIfNeeded()

            let rectInTargetWin = targetWindow?.convert(anchorView.frame, from: targetView) ?? anchorView.frame
            var rectInHost = hostWindow.convert(rectInTargetWin, from: targetWindow)
            if rectInHost.width <= 0 || rectInHost.height <= 0 || !rectInHost.intersects(hostRoot.view.bounds) {
                rectInHost = CGRect(
                    x: max(16, hostRoot.view.bounds.midX - 60),
                    y: max(60, hostRoot.view.bounds.midY - 24),
                    width: 120,
                    height: 36
                )
            }

            toolController.hostedOverlayWindow = hostWindow
            toolController.popoverPresentationController?.sourceView = hostRoot.view
            toolController.popoverPresentationController?.sourceRect = rectInHost.insetBy(dx: -2, dy: -2)
            hostRoot.present(toolController, animated: true)
        } else {
            toolController.popoverPresentationController?.sourceView = context.anchorView
            toolController.popoverPresentationController?.sourceRect = context.anchorView.bounds.insetBy(dx: -2, dy: -2)
            candidatePresenter.present(toolController, animated: true)
        }
    }

    private static func requiresDedicatedOverlayWindow(
        for targetWindow: UIWindow?,
        presenterVC: UIViewController
    ) -> Bool {
        guard let targetWindow else { return true }
        if presenterVC.view.window !== targetWindow { return true }
        if targetWindow.rootViewController == nil { return true }
        if targetWindow.windowLevel != .normal { return true }
        if Bundle.main.bundleIdentifier == "com.apple.springboard" { return true }
        return false
    }

    private func topMostPresenter(from root: UIViewController) -> UIViewController {
        var current = root
        while let presented = current.presentedViewController, !presented.isBeingDismissed {
            current = presented
        }
        return current
    }

    private func obtainContextFor(_ view: UIView, launchSlotAction: RuntimeSelectionMenuItem?) -> Context? {
        if let textProxy = TextProxy(delegatingView: view),
           !textProxy.isReadOnly,
           textProxy.selectedText.isEmpty,
           Configurator.shared.settings.autoSelectAllIfEmpty
        {
            textProxy.selectAll()
        }
        if let context = buildContext(fromResponder: view, launchSlotAction: launchSlotAction) {
            return context
        }
        return nil
    }

    @objc(presentUnavailable:)
    func presentUnavailable(_ responder: UIResponder) {
        guard let responder = responder as? UIView else { return }

        let shake = CABasicAnimation(keyPath: "position")
        shake.timingFunction = CAMediaTimingFunction(
            name: CAMediaTimingFunctionName.easeInEaseOut
        )
        shake.duration = 0.05
        shake.repeatCount = 2
        shake.autoreverses = true
        shake.isRemovedOnCompletion = true
        shake.fromValue = NSValue(cgPoint: CGPoint(
            x: responder.center.x - 2,
            y: responder.center.y
        ))
        shake.toValue = NSValue(cgPoint: CGPoint(
            x: responder.center.x + 2,
            y: responder.center.y
        ))
        responder.layer.add(shake, forKey: "position")

        let background = UIView()
        background.backgroundColor = .gray.withAlphaComponent(0.1)
        background.layer.cornerRadius = responder.layer.cornerRadius
        background.clipsToBounds = true
        responder.addSubview(background)
        background.frame = responder.bounds

        UIView.animate(withDuration: 0.25, delay: 0.1) {
            background.alpha = 0
        } completion: { _ in
            background.removeFromSuperview()
        }
    }
}

final class WriteNowPopoverHostWindow: UIWindow {}

private enum CopySheetPillAssocKey {
    static var key: UInt8 = 0
}

private final class CopySheetWriteNowButton: UIButton {
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleTap() {
        onTap?()
    }
}

