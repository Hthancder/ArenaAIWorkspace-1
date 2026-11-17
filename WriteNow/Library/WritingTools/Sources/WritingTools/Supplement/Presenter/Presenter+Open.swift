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

        if let resolvedTarget,
           let fallbackCopyAction,
           let copied = TextProxy.extractViaCopyMenuElement(fallbackCopyAction, targetView: resolvedTarget),
           !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            presentExtractedText(
                copied,
                fromHostView: resolvedTarget,
                parentController: nil,
                anchorRectInHost: resolvedTarget.bounds,
                slotIndex: slotIndex
            )
            return
        }

        if let resolvedTarget {
            presentUnavailable(resolvedTarget)
        }
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
            } else if let view {
                self.presentUnavailable(view)
            }
        }
    }

    func presentExtractedText(
        _ text: String,
        fromHostView hostView: UIView,
        parentController: UIViewController?,
        anchorRectInHost: CGRect,
        slotIndex: Int,
        onCompleteAndClose: (() -> Void)? = nil
    ) {
        let launchAction = resolveLaunchItem(slotIndex: slotIndex, isReadOnly: true)
        guard let context = buildExtractedTextContext(
            text: text,
            hostView: hostView,
            parentController: parentController,
            anchorRectInHost: anchorRectInHost,
            launchSlotAction: launchAction,
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

private final class WriteNowPopoverHostWindow: UIWindow {}

