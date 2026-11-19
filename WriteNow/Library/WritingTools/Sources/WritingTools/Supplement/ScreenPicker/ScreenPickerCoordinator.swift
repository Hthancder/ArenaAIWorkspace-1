//
//  ScreenPickerCoordinator.swift
//  WritingTools
//

import UIKit

final class ScreenPickerCoordinator: NSObject, UIGestureRecognizerDelegate {
    static let shared = ScreenPickerCoordinator()

    private static let bubbleIsLeftKey = "WriteNowPickerBubbleIsLeft"
    private static let bubbleYRatioKey = "WriteNowPickerBubbleYRatio"
    private static let bubbleViewTag = 0x574E4255
    private static let ownerPointerKey: UnsafeRawPointer = UnsafeRawPointer(
        sel_getName(NSSelectorFromString("___WriteNowScreenPickerOwnerKey___"))
    )

    private let attachedWindows = NSHashTable<UIWindow>.weakObjects()
    private weak var bubbleWindow: UIWindow?
    private var bubbleButton: UIButton?
    private var bubbleDimTimer: Timer?
    private var isOverlayPresented = false
    private var isKeyboardVisible = false
    private var hiddenForCurrentSession = false
    private var lastShakeTriggerAt: Date = .distantPast

    private var isPrimaryOwner: Bool {
        guard let existing = objc_getAssociatedObject(UIApplication.shared, Self.ownerPointerKey) as AnyObject? else {
            objc_setAssociatedObject(UIApplication.shared, Self.ownerPointerKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return true
        }
        return existing === self
    }

    override private init() {
        super.init()
        guard isPrimaryOwner else { return }
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(handleSettingsUpdate),
            name: Notification.Name("WriteNowRuntimeSettingsDidUpdate"),
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleKeyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleKeyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    private var isNormalAppProcess: Bool {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return false }
        let bid = Bundle.main.bundleIdentifier ?? ""
        return bid != "com.apple.springboard"
    }

    func attachIfNeeded(to window: UIWindow) {
        guard isPrimaryOwner, isNormalAppProcess else { return }
        guard window.windowLevel == .normal else { return }
        let clsName = NSStringFromClass(type(of: window))
        guard !clsName.contains("TextEffects"),
              !clsName.contains("WriteNow"),
              !clsName.contains("InteractiveHighlight")
        else { return }

        if !attachedWindows.contains(window) {
            attachedWindows.add(window)
            syncGestures(on: window, settings: Configurator.shared.settings)
        }
        syncFloatingBubble(in: window)
    }

    func handleShake(in window: UIWindow) {
        guard isPrimaryOwner, isNormalAppProcess else { return }
        let settings = Configurator.shared.settings
        guard settings.readOnlyEnabled, settings.pickerShakeEnabled, !isOverlayPresented else { return }
        let now = Date()
        guard now.timeIntervalSince(lastShakeTriggerAt) > 2.0 else { return }
        lastShakeTriggerAt = now
        presentPicker(in: window, forceFullOCR: true)
    }

    @objc private func handleSettingsUpdate() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPrimaryOwner else { return }
            let settings = Configurator.shared.settings
            if settings.floatingPickerBubbleEnabled {
                self.hiddenForCurrentSession = false
            }
            for win in self.attachedWindows.allObjects {
                self.syncGestures(on: win, settings: settings)
            }
            if let keyWin = self.attachedWindows.allObjects.first(where: { $0.isKeyWindow }) ?? self.attachedWindows.allObjects.first {
                self.syncFloatingBubble(in: keyWin)
            } else if !settings.floatingPickerBubbleEnabled {
                self.removeBubble()
            }
        }
    }

    @objc private func handleKeyboardWillShow() {
        isKeyboardVisible = true
        bubbleButton?.isHidden = true
    }

    @objc private func handleKeyboardWillHide() {
        isKeyboardVisible = false
        if let btn = bubbleButton,
           Configurator.shared.settings.readOnlyEnabled,
           Configurator.shared.settings.floatingPickerBubbleEnabled,
           !isOverlayPresented,
           !hiddenForCurrentSession
        {
            btn.isHidden = false
            scheduleBubbleDim()
        }
    }

    private func syncGestures(on window: UIWindow, settings: RuntimeSettings) {
        let wantTwoFinger = settings.readOnlyEnabled && settings.pickerTwoFingerLongPressEnabled
        let wantThreeFinger = settings.readOnlyEnabled && settings.pickerThreeFingerTapEnabled
        let wantStatusTap = settings.readOnlyEnabled && settings.pickerStatusBarDoubleTapEnabled

        let existingTwoFinger = (window.gestureRecognizers ?? []).filter { $0.name == "WriteNowTwoFingerHold" }
        let existingThreeFinger = (window.gestureRecognizers ?? []).filter { $0.name == "WriteNowThreeFingerTap" }
        let existingStatusTap = (window.gestureRecognizers ?? []).filter { $0.name == "WriteNowStatusBarTap" }

        if wantTwoFinger && existingTwoFinger.isEmpty {
            let twoFingerHold = UILongPressGestureRecognizer(target: self, action: #selector(handleTwoFingerLongPress(_:)))
            twoFingerHold.numberOfTouchesRequired = 2
            twoFingerHold.minimumPressDuration = 0.55
            twoFingerHold.allowableMovement = 14
            twoFingerHold.cancelsTouchesInView = false
            twoFingerHold.delaysTouchesBegan = false
            twoFingerHold.name = "WriteNowTwoFingerHold"
            twoFingerHold.delegate = self
            window.addGestureRecognizer(twoFingerHold)
        } else if !wantTwoFinger {
            existingTwoFinger.forEach { window.removeGestureRecognizer($0) }
        }

        if wantThreeFinger && existingThreeFinger.isEmpty {
            let threeFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleThreeFingerTap(_:)))
            threeFingerTap.numberOfTouchesRequired = 3
            threeFingerTap.numberOfTapsRequired = 1
            threeFingerTap.cancelsTouchesInView = false
            threeFingerTap.delaysTouchesBegan = false
            threeFingerTap.name = "WriteNowThreeFingerTap"
            threeFingerTap.delegate = self
            window.addGestureRecognizer(threeFingerTap)
        } else if !wantThreeFinger {
            existingThreeFinger.forEach { window.removeGestureRecognizer($0) }
        }

        if wantStatusTap && existingStatusTap.isEmpty {
            let statusBarTap = UITapGestureRecognizer(target: self, action: #selector(handleStatusBarDoubleTap(_:)))
            statusBarTap.numberOfTapsRequired = 2
            statusBarTap.cancelsTouchesInView = false
            statusBarTap.delaysTouchesBegan = false
            statusBarTap.name = "WriteNowStatusBarTap"
            statusBarTap.delegate = self
            window.addGestureRecognizer(statusBarTap)
        } else if !wantStatusTap {
            existingStatusTap.forEach { window.removeGestureRecognizer($0) }
        }
    }

    private static func isInteractiveView(_ view: UIView?) -> Bool {
        var cur = view
        while let v = cur {
            if v is UIControl || v is UITextField || v is UITextView || v is UINavigationBar || v is UITabBar || v is UIToolbar {
                return true
            }
            cur = v.superview
        }
        return false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard Configurator.shared.settings.readOnlyEnabled, !isOverlayPresented else {
            return false
        }
        if gestureRecognizer.name == "WriteNowThreeFingerTap" {
            return Configurator.shared.settings.pickerThreeFingerTapEnabled
        }
        guard !isKeyboardVisible else { return false }
        if gestureRecognizer.name == "WriteNowStatusBarTap" {
            guard Configurator.shared.settings.pickerStatusBarDoubleTapEnabled,
                  let win = gestureRecognizer.view as? UIWindow
            else { return false }
            let loc = gestureRecognizer.location(in: win)
            let barHeight = win.windowScene?.statusBarManager?.statusBarFrame.height ?? win.safeAreaInsets.top
            let strictTop = max(16.0, min(barHeight, 32.0))
            guard loc.y <= strictTop else { return false }
            if Self.isInteractiveView(win.hitTest(loc, with: nil)) {
                return false
            }
            return true
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
        presentPicker(in: window, forceFullOCR: false)
    }

    @objc private func handleThreeFingerTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .recognized,
              let window = gesture.view as? UIWindow
        else { return }
        presentPicker(in: window, forceFullOCR: false)
    }

    @objc private func handleStatusBarDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .recognized,
              let window = gesture.view as? UIWindow
        else { return }
        presentPicker(in: window, forceFullOCR: false)
    }

    // MARK: - Floating Bubble

    private func cleanupDuplicateBubbleViews(except keeper: UIButton?) {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for win in ws.windows {
                for sub in win.subviews where sub.tag == Self.bubbleViewTag && sub !== keeper {
                    sub.removeFromSuperview()
                }
            }
        }
    }

    private func syncFloatingBubble(in window: UIWindow) {
        let settings = Configurator.shared.settings
        guard settings.readOnlyEnabled, settings.floatingPickerBubbleEnabled, !hiddenForCurrentSession else {
            removeBubble()
            return
        }

        if let existing = bubbleButton {
            cleanupDuplicateBubbleViews(except: existing)
            if existing.superview !== window {
                existing.removeFromSuperview()
                window.addSubview(existing)
                bubbleWindow = window
            }
            window.bringSubviewToFront(existing)
            existing.isHidden = isOverlayPresented || isKeyboardVisible
            return
        }

        cleanupDuplicateBubbleViews(except: nil)

        let isLeft = UserDefaults.standard.bool(forKey: Self.bubbleIsLeftKey)
        let savedRatio = UserDefaults.standard.double(forKey: Self.bubbleYRatioKey)
        let yRatio = (savedRatio > 0.08 && savedRatio < 0.92) ? savedRatio : 0.42
        let centerX: CGFloat = isLeft ? 28 : (window.bounds.width - 28)
        let minY = window.safeAreaInsets.top + 32
        let maxY = max(minY + 20, window.bounds.height - window.safeAreaInsets.bottom - 32)
        let centerY = max(minY, min(maxY, window.bounds.height * yRatio))

        let btn = UIButton(type: .system)
        btn.tag = Self.bubbleViewTag
        btn.frame = CGRect(x: 0, y: 0, width: 42, height: 42)
        btn.center = CGPoint(x: centerX, y: centerY)
        btn.layer.cornerRadius = 21
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.76)
        btn.layer.borderWidth = 1
        btn.layer.borderColor = UIColor.systemCyan.withAlphaComponent(0.65).cgColor
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOpacity = 0.28
        btn.layer.shadowRadius = 6
        btn.layer.shadowOffset = CGSize(width: 0, height: 2)
        btn.setImage(UIImage(systemName: "text.viewfinder"), for: .normal)
        btn.tintColor = .systemCyan
        btn.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin, .flexibleBottomMargin]
        btn.isHidden = isOverlayPresented || isKeyboardVisible

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(didDoubleTapFloatingBubble))
        doubleTap.numberOfTapsRequired = 2
        btn.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(didTapFloatingBubble))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        btn.addGestureRecognizer(singleTap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleBubblePan(_:)))
        btn.addGestureRecognizer(pan)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleBubbleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        btn.addGestureRecognizer(longPress)

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
        cleanupDuplicateBubbleViews(except: nil)
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
        presentPicker(in: window, forceFullOCR: false)
    }

    @objc private func didDoubleTapFloatingBubble() {
        guard let window = bubbleWindow ?? attachedWindows.allObjects.first(where: { $0.isKeyWindow }) else { return }
        scheduleBubbleDim()
        presentPicker(in: window, forceFullOCR: true)
    }

    @objc private func handleBubbleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let window = bubbleWindow ?? attachedWindows.allObjects.first(where: { $0.isKeyWindow }),
              let rootVC = window.rootViewController
        else { return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController, !presented.isBeingDismissed {
            topVC = presented
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let sheet = UIAlertController(title: "OmniAI Screen Tools", message: nil, preferredStyle: .actionSheet)
        if InPlaceTextReplacementManager.shared.isShowingOverlay {
            sheet.addAction(UIAlertAction(title: "Revert Screen Text Overlay", style: .destructive) { _ in
                InPlaceTextReplacementManager.shared.clearAll()
            })
        }
        sheet.addAction(UIAlertAction(title: "Scan Screen Text", style: .default) { [weak self] _ in
            self?.presentPicker(in: window, forceFullOCR: false)
        })
        sheet.addAction(UIAlertAction(title: "Full-Screen OCR", style: .default) { [weak self] _ in
            self?.presentPicker(in: window, forceFullOCR: true)
        })
        sheet.addAction(UIAlertAction(title: "Capture Screen Region (AI / OCR)", style: .default) { [weak self] _ in
            self?.presentRegionCapture(in: window)
        })
        sheet.addAction(UIAlertAction(title: "Ask AI with Screenshot", style: .default) { [weak self] _ in
            self?.bubbleButton?.isHidden = true
            DispatchQueue.main.async {
                let snap = ScreenTextScanner.captureSnapshot(of: window)
                if let btn = self?.bubbleButton,
                   Configurator.shared.settings.floatingPickerBubbleEnabled,
                   !(self?.hiddenForCurrentSession ?? false),
                   !(self?.isKeyboardVisible ?? false)
                {
                    btn.isHidden = false
                }
                guard let snap, let attached = AttachedImageItem.fromUIImage(snap, label: "Screen") else { return }
                let host = UIView(frame: CGRect(x: window.bounds.midX - 40, y: window.bounds.midY - 20, width: 80, height: 40))
                host.backgroundColor = .clear
                host.isUserInteractionEnabled = false
                window.addSubview(host)
                Presenter.shared.presentExtractedText(
                    "",
                    fromHostView: host,
                    parentController: topVC,
                    anchorRectInHost: host.bounds,
                    slotIndex: 0,
                    initialAttachedImages: [attached],
                    onCompleteAndClose: { [weak host] in host?.removeFromSuperview() }
                )
            }
        })
        if let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !clip.isEmpty
        {
            sheet.addAction(UIAlertAction(title: "Process Clipboard Text", style: .default) { _ in
                let host = UIView(frame: CGRect(x: window.bounds.midX - 40, y: window.bounds.midY - 20, width: 80, height: 40))
                host.backgroundColor = .clear
                host.isUserInteractionEnabled = false
                window.addSubview(host)
                Presenter.shared.presentExtractedText(
                    clip,
                    fromHostView: host,
                    parentController: topVC,
                    anchorRectInHost: host.bounds,
                    slotIndex: 0,
                    onCompleteAndClose: { [weak host] in host?.removeFromSuperview() }
                )
            })
        }
        sheet.addAction(UIAlertAction(title: "Hide Button Until App Relaunch", style: .destructive) { [weak self] _ in
            self?.hiddenForCurrentSession = true
            self?.removeBubble()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let pop = sheet.popoverPresentationController, let btn = bubbleButton {
            pop.sourceView = btn
            pop.sourceRect = btn.bounds
        }
        topVC.present(sheet, animated: true)
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
            let isLeft = center.x < win.bounds.midX
            let snapX: CGFloat = isLeft ? 28 : (win.bounds.width - 28)
            let yRatio = Double(center.y / max(1, win.bounds.height))
            UserDefaults.standard.set(isLeft, forKey: Self.bubbleIsLeftKey)
            UserDefaults.standard.set(yRatio, forKey: Self.bubbleYRatioKey)
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
                btn.center.x = snapX
            }
            scheduleBubbleDim()
        }
    }

    func presentRegionCapture(
        in window: UIWindow,
        existingText: String = "",
        existingImages: [AttachedImageItem] = [],
        mode: ScreenRegionCropViewController.ActionMode = .attachImage
    ) {
        guard isPrimaryOwner, !isOverlayPresented else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isOverlayPresented = true
        bubbleButton?.isHidden = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let snapshot = ScreenTextScanner.captureSnapshot(of: window)
            let cropVC = ScreenRegionCropViewController(
                sourceWindow: window,
                snapshot: snapshot,
                initialMode: mode
            ) { [weak self] imageItem, ocrText, rect in
                guard let self else { return }
                self.isOverlayPresented = false
                if let btn = self.bubbleButton,
                   Configurator.shared.settings.floatingPickerBubbleEnabled,
                   !self.hiddenForCurrentSession,
                   !self.isKeyboardVisible
                {
                    btn.isHidden = false
                    self.scheduleBubbleDim()
                }

                var mergedImages = existingImages
                if let imageItem, mergedImages.count < 4 {
                    mergedImages.append(imageItem)
                }
                let finalText: String
                if let ocrText, !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    finalText = existingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? ocrText
                        : "\(existingText)\n\n\(ocrText)"
                } else {
                    finalText = existingText
                }

                guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !mergedImages.isEmpty else {
                    return
                }
                let host = UIView(frame: rect.isEmpty ? CGRect(x: window.bounds.midX - 40, y: window.bounds.midY - 20, width: 80, height: 40) : rect)
                host.backgroundColor = .clear
                host.isUserInteractionEnabled = false
                window.addSubview(host)
                Presenter.shared.presentExtractedText(
                    finalText,
                    fromHostView: host,
                    parentController: nil,
                    anchorRectInHost: host.bounds,
                    slotIndex: 0,
                    initialAttachedImages: mergedImages,
                    onCompleteAndClose: { [weak host] in host?.removeFromSuperview() }
                )
            }

            let overlayWindow: UIWindow
            if let scene = window.windowScene {
                overlayWindow = WriteNowScreenOverlayWindow(windowScene: scene)
            } else {
                overlayWindow = WriteNowScreenOverlayWindow(frame: window.bounds)
            }
            overlayWindow.frame = window.bounds
            overlayWindow.backgroundColor = .clear
            overlayWindow.isOpaque = false
            overlayWindow.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.statusBar.rawValue + 50)
            overlayWindow.rootViewController = cropVC
            overlayWindow.makeKeyAndVisible()
            cropVC.ownedOverlayWindow = overlayWindow
        }
    }

    // MARK: - Present Picker

    func presentPicker(in window: UIWindow, forceFullOCR: Bool = false) {
        guard isPrimaryOwner, !isOverlayPresented else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isOverlayPresented = true
        bubbleButton?.isHidden = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let snapshot = ScreenTextScanner.captureSnapshot(of: window)
            if forceFullOCR {
                self.showOverlayWindow(for: window, snapshot: snapshot, initialBlocks: [])
                return
            }

            ScreenTextScanner.scanVisibleText(in: window) { [weak self] blocks in
                self?.showOverlayWindow(for: window, snapshot: snapshot, initialBlocks: blocks)
            }
        }
    }

    private func showOverlayWindow(
        for sourceWindow: UIWindow,
        snapshot: UIImage?,
        initialBlocks: [DetectedScreenTextBlock]
    ) {
        let overlay = ScreenTextOverlayViewController(
            sourceWindow: sourceWindow,
            snapshot: snapshot,
            initialBlocks: initialBlocks
        )

        let overlayWindow: UIWindow
        if let scene = sourceWindow.windowScene {
            overlayWindow = WriteNowScreenOverlayWindow(windowScene: scene)
        } else {
            overlayWindow = WriteNowScreenOverlayWindow(frame: sourceWindow.bounds)
        }
        overlayWindow.frame = sourceWindow.bounds
        overlayWindow.backgroundColor = .clear
        overlayWindow.isOpaque = false
        overlayWindow.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.statusBar.rawValue + 50)
        overlayWindow.rootViewController = overlay
        overlayWindow.makeKeyAndVisible()

        overlay.ownedOverlayWindow = overlayWindow
        overlay.onOverlayDismissed = { [weak self] in
            guard let self else { return }
            self.isOverlayPresented = false
            if let btn = self.bubbleButton,
               Configurator.shared.settings.floatingPickerBubbleEnabled,
               !self.hiddenForCurrentSession,
               !self.isKeyboardVisible
            {
                btn.isHidden = false
                self.scheduleBubbleDim()
            }
        }
    }
}

private final class WriteNowScreenOverlayWindow: UIWindow {}
