//
//  ScreenPickerCoordinator.swift
//  WritingTools
//

import UIKit

final class ScreenPickerCoordinator: NSObject, UIGestureRecognizerDelegate {
    static let shared = ScreenPickerCoordinator()

    private let attachedWindows = NSHashTable<UIWindow>.weakObjects()
    private weak var bubbleWindow: UIWindow?
    private var bubbleButton: UIButton?
    private var bubbleDimTimer: Timer?
    private var isOverlayPresented = false

    override private init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsUpdate),
            name: Notification.Name("WriteNowRuntimeSettingsDidUpdate"),
            object: nil
        )
    }

    private var isNormalAppProcess: Bool {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return false }
        let bid = Bundle.main.bundleIdentifier ?? ""
        return bid != "com.apple.springboard"
    }

    func attachIfNeeded(to window: UIWindow) {
        guard isNormalAppProcess else { return }
        guard window.windowLevel == .normal else { return }
        let clsName = NSStringFromClass(type(of: window))
        guard !clsName.contains("TextEffects"),
              !clsName.contains("WriteNow"),
              !clsName.contains("InteractiveHighlight")
        else { return }

        if !attachedWindows.contains(window) {
            attachedWindows.add(window)
            installGestures(on: window)
        }
        syncFloatingBubble(in: window)
    }

    @objc private func handleSettingsUpdate() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let keyWin = self.attachedWindows.allObjects.first(where: { $0.isKeyWindow }) ?? self.attachedWindows.allObjects.first {
                self.syncFloatingBubble(in: keyWin)
            } else if !Configurator.shared.settings.floatingPickerBubbleEnabled {
                self.removeBubble()
            }
        }
    }

    private func installGestures(on window: UIWindow) {
        let twoFingerHold = UILongPressGestureRecognizer(target: self, action: #selector(handleTwoFingerLongPress(_:)))
        twoFingerHold.numberOfTouchesRequired = 2
        twoFingerHold.minimumPressDuration = 0.42
        twoFingerHold.cancelsTouchesInView = false
        twoFingerHold.delaysTouchesBegan = false
        twoFingerHold.delegate = self
        window.addGestureRecognizer(twoFingerHold)

        let statusBarTap = UITapGestureRecognizer(target: self, action: #selector(handleStatusBarDoubleTap(_:)))
        statusBarTap.numberOfTapsRequired = 2
        statusBarTap.cancelsTouchesInView = false
        statusBarTap.delaysTouchesBegan = false
        statusBarTap.name = "WriteNowStatusBarTap"
        statusBarTap.delegate = self
        window.addGestureRecognizer(statusBarTap)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard Configurator.shared.settings.readOnlyEnabled, !isOverlayPresented else {
            return false
        }
        if gestureRecognizer.name == "WriteNowStatusBarTap" {
            guard Configurator.shared.settings.pickerStatusBarDoubleTapEnabled,
                  let win = gestureRecognizer.view as? UIWindow
            else { return false }
            let loc = gestureRecognizer.location(in: win)
            let topZone = max(44.0, win.safeAreaInsets.top + 8.0)
            return loc.y <= topZone
        }
        return Configurator.shared.settings.pickerTwoFingerLongPressEnabled
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func handleTwoFingerLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let window = gesture.view as? UIWindow
        else { return }
        presentPicker(in: window)
    }

    @objc private func handleStatusBarDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .recognized,
              let window = gesture.view as? UIWindow
        else { return }
        presentPicker(in: window)
    }

    // MARK: - Floating Bubble

    private func syncFloatingBubble(in window: UIWindow) {
        let settings = Configurator.shared.settings
        guard settings.readOnlyEnabled, settings.floatingPickerBubbleEnabled else {
            removeBubble()
            return
        }

        if let existing = bubbleButton {
            if existing.superview !== window {
                existing.removeFromSuperview()
                window.addSubview(existing)
                bubbleWindow = window
            }
            window.bringSubviewToFront(existing)
            existing.isHidden = isOverlayPresented
            return
        }

        let btn = UIButton(type: .system)
        btn.frame = CGRect(x: window.bounds.width - 52, y: window.bounds.height * 0.42, width: 42, height: 42)
        btn.layer.cornerRadius = 21
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        btn.layer.borderWidth = 1
        btn.layer.borderColor = UIColor.systemCyan.withAlphaComponent(0.65).cgColor
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOpacity = 0.28
        btn.layer.shadowRadius = 6
        btn.layer.shadowOffset = CGSize(width: 0, height: 2)
        btn.setImage(UIImage(systemName: "text.viewfinder"), for: .normal)
        btn.tintColor = .systemCyan
        btn.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin, .flexibleBottomMargin]
        btn.addTarget(self, action: #selector(didTapFloatingBubble), for: .touchUpInside)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleBubblePan(_:)))
        btn.addGestureRecognizer(pan)

        window.addSubview(btn)
        bubbleButton = btn
        bubbleWindow = window
        scheduleBubbleDim()
    }

    private func removeBubble() {
        bubbleDimTimer?.invalidate()
        bubbleDimTimer = nil
        bubbleButton?.removeFromSuperview()
        bubbleButton = nil
        bubbleWindow = nil
    }

    private func scheduleBubbleDim() {
        bubbleDimTimer?.invalidate()
        bubbleButton?.alpha = 0.96
        bubbleDimTimer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.35) {
                self?.bubbleButton?.alpha = 0.42
            }
        }
    }

    @objc private func didTapFloatingBubble() {
        guard let window = bubbleWindow ?? attachedWindows.allObjects.first(where: { $0.isKeyWindow }) else { return }
        scheduleBubbleDim()
        presentPicker(in: window)
    }

    @objc private func handleBubblePan(_ gesture: UIPanGestureRecognizer) {
        guard let btn = bubbleButton, let win = btn.superview else { return }
        let translation = gesture.translation(in: win)
        if gesture.state == .began {
            bubbleDimTimer?.invalidate()
            btn.alpha = 0.96
        }
        var center = CGPoint(x: btn.center.x + translation.x, y: btn.center.y + translation.y)
        let minY = win.safeAreaInsets.top + 32
        let maxY = win.bounds.height - win.safeAreaInsets.bottom - 32
        center.x = max(26, min(win.bounds.width - 26, center.x))
        center.y = max(minY, min(maxY, center.y))
        btn.center = center
        gesture.setTranslation(.zero, in: win)

        if gesture.state == .ended || gesture.state == .cancelled {
            let snapX: CGFloat = center.x < win.bounds.midX ? 28 : (win.bounds.width - 28)
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
                btn.center.x = snapX
            }
            scheduleBubbleDim()
        }
    }

    // MARK: - Present Picker

    func presentPicker(in window: UIWindow) {
        guard !isOverlayPresented,
              let rootVC = window.rootViewController
        else { return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController, !presented.isBeingDismissed {
            topVC = presented
        }
        if topVC is ScreenTextOverlayViewController { return }

        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()

        isOverlayPresented = true
        bubbleButton?.isHidden = true

        let snapshot = ScreenTextScanner.captureSnapshot(of: window)
        ScreenTextScanner.scanVisibleText(in: window) { [weak self] blocks in
            guard let self else { return }
            let overlay = ScreenTextOverlayViewController(
                sourceWindow: window,
                snapshot: snapshot,
                initialBlocks: blocks
            )
            // Keep track of dismissal cleanly
            let watcher = OverlayDismissObserver { [weak self] in
                self?.isOverlayPresented = false
                if let btn = self?.bubbleButton, Configurator.shared.settings.floatingPickerBubbleEnabled {
                    btn.isHidden = false
                    self?.scheduleBubbleDim()
                }
            }
            objc_setAssociatedObject(overlay, &OverlayDismissObserver.assocKey, watcher, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            topVC.present(overlay, animated: true)
        }
    }
}

private final class OverlayDismissObserver: NSObject {
    static var assocKey: UInt8 = 0
    let onDeinit: () -> Void
    init(onDeinit: @escaping () -> Void) { self.onDeinit = onDeinit }
    deinit { DispatchQueue.main.async(execute: onDeinit) }
}
