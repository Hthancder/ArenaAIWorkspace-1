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
        let resolvedTarget = targetView ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow && $0.windowLevel == .normal }

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
        slotIndex: Int
    ) {
        let launchAction = resolveLaunchItem(slotIndex: slotIndex, isReadOnly: true)
        guard let context = buildExtractedTextContext(
            text: text,
            hostView: hostView,
            parentController: parentController,
            anchorRectInHost: anchorRectInHost,
            launchSlotAction: launchAction
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
        toolController.popoverPresentationController?.sourceView = context.anchorView
        toolController.popoverPresentationController?.sourceRect = context.anchorView.bounds.insetBy(dx: -2, dy: -2)
        toolController.popoverPresentationController?.canOverlapSourceViewRect = true
        toolController.popoverPresentationController?.permittedArrowDirections = [.up, .down]

        let presenterVC = topMostPresenter(from: context.parentController)
        presenterVC.present(toolController, animated: true)
    }

    private func topMostPresenter(from root: UIViewController) -> UIViewController {
        var current = root
        while let presented = current.presentedViewController, !presented.isBeingDismissed {
            current = presented
        }
        return current
    }

    private func obtainContextFor(_ view: UIView, launchSlotAction: RuntimeSelectionMenuItem?) -> Context? {
        if let context = buildContext(fromResponder: view, launchSlotAction: launchSlotAction) {
            return context
        }
        if let textProxy = TextProxy(delegatingView: view), !textProxy.isReadOnly,
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
