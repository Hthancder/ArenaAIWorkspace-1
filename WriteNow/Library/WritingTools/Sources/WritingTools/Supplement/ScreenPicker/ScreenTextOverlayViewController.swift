//
//  ScreenTextOverlayViewController.swift
//  WritingTools
//

import OpenAI
import UIKit

final class ScreenTextOverlayViewController: UIViewController {
    enum Mode: Int {
        case tap = 0
        case multiSelect = 1
        case drawOCR = 2
    }

    private let sourceWindow: UIWindow
    private let snapshot: UIImage?
    private var blocks: [DetectedScreenTextBlock]
    private var selectedIndices: [Int] = []
    private var currentMode: Mode = .tap {
        didSet { updateModeUI() }
    }

    var ownedOverlayWindow: UIWindow?
    var onOverlayDismissed: (() -> Void)?

    private let scrimView = UIView()
    private let blocksContainer = UIView()
    private var blockButtons: [UIButton] = []

    private let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let modeControl = UISegmentedControl(items: ["Tap", "Multi", "OCR Box"])
    private let fullOCRButton = UIButton(type: .system)
    private let askImageButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    private let bottomActionBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let hintLabel = UILabel()
    private let selectAllMultiButton = UIButton(type: .system)
    private let copyMultiButton = UIButton(type: .system)
    private let translateHereButton = UIButton(type: .system)
    private let askMultiButton = UIButton(type: .system)
    private let ocrSpinner = UIActivityIndicatorView(style: .medium)

    private let selectionBoxView = UIView()
    private var dragStartPoint: CGPoint?
    private var isProcessingOCR = false
    private weak var activeAnchorHostView: UIView?

    init(sourceWindow: UIWindow, snapshot: UIImage?, initialBlocks: [DetectedScreenTextBlock]) {
        self.sourceWindow = sourceWindow
        self.snapshot = snapshot
        self.blocks = initialBlocks
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        setupBackdrop()
        setupTopBar()
        setupBottomBar()
        setupDragOCR()
        rebuildBlockButtons()
        updateModeUI()

        if blocks.isEmpty {
            runFullScreenOCR()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cleanupOverlayIfNeeded()
    }

    private func cleanupOverlayIfNeeded() {
        if let win = ownedOverlayWindow {
            win.isHidden = true
            ownedOverlayWindow = nil
        }
        let cb = onOverlayDismissed
        onOverlayDismissed = nil
        cb?()
    }

    private func setupBackdrop() {
        scrimView.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        scrimView.frame = view.bounds
        scrimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrimView)

        blocksContainer.frame = view.bounds
        blocksContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(blocksContainer)
    }

    private func setupTopBar() {
        topBar.layer.cornerRadius = 16
        topBar.clipsToBounds = true
        topBar.layer.borderWidth = 0.5
        topBar.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        modeControl.selectedSegmentIndex = 0
        modeControl.selectedSegmentTintColor = UIColor.systemCyan.withAlphaComponent(0.35)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 11.5, weight: .semibold)], for: .normal)
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        fullOCRButton.setImage(UIImage(systemName: "text.viewfinder"), for: .normal)
        fullOCRButton.setTitle(" OCR", for: .normal)
        fullOCRButton.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
        fullOCRButton.tintColor = .systemCyan
        fullOCRButton.addTarget(self, action: #selector(didTapFullOCR), for: .touchUpInside)

        askImageButton.setImage(UIImage(systemName: "photo.badge.plus"), for: .normal)
        askImageButton.tintColor = .systemGreen
        askImageButton.addTarget(self, action: #selector(didTapAskWithScreenshot), for: .touchUpInside)

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        closeButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [modeControl, fullOCRButton, askImageButton, closeButton])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        topBar.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            topBar.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 10),
            topBar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -10),
            topBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            stack.topAnchor.constraint(equalTo: topBar.contentView.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: topBar.contentView.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: topBar.contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: topBar.contentView.trailingAnchor, constant: -10),

            modeControl.widthAnchor.constraint(greaterThanOrEqualToConstant: 156),
            askImageButton.widthAnchor.constraint(equalToConstant: 26),
            askImageButton.heightAnchor.constraint(equalToConstant: 26),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private func setupBottomBar() {
        bottomActionBar.layer.cornerRadius = 16
        bottomActionBar.clipsToBounds = true
        bottomActionBar.layer.borderWidth = 0.5
        bottomActionBar.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        bottomActionBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomActionBar)

        hintLabel.font = .systemFont(ofSize: 12, weight: .medium)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        hintLabel.numberOfLines = 2
        hintLabel.textAlignment = .center

        ocrSpinner.color = .systemCyan
        ocrSpinner.hidesWhenStopped = true

        selectAllMultiButton.setTitle("All", for: .normal)
        selectAllMultiButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        selectAllMultiButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        selectAllMultiButton.setTitleColor(.white, for: .normal)
        selectAllMultiButton.layer.cornerRadius = 10
        selectAllMultiButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 9, bottom: 6, right: 9)
        selectAllMultiButton.isHidden = true
        selectAllMultiButton.addTarget(self, action: #selector(didTapSelectAllMulti), for: .touchUpInside)

        copyMultiButton.setTitle("Copy", for: .normal)
        copyMultiButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        copyMultiButton.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        copyMultiButton.setTitleColor(.white, for: .normal)
        copyMultiButton.layer.cornerRadius = 10
        copyMultiButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 9, bottom: 6, right: 9)
        copyMultiButton.isHidden = true
        copyMultiButton.addTarget(self, action: #selector(didTapCopyMulti), for: .touchUpInside)

        translateHereButton.setImage(UIImage(systemName: "rectangle.on.rectangle.angled"), for: .normal)
        translateHereButton.setTitle(" On Screen", for: .normal)
        translateHereButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .bold)
        translateHereButton.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.85)
        translateHereButton.setTitleColor(.black, for: .normal)
        translateHereButton.tintColor = .black
        translateHereButton.layer.cornerRadius = 10
        translateHereButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 9, bottom: 6, right: 10)
        translateHereButton.isHidden = true
        translateHereButton.addTarget(self, action: #selector(didTapTranslateOnScreen), for: .touchUpInside)

        askMultiButton.setTitle("OmniAI", for: .normal)
        askMultiButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .bold)
        askMultiButton.backgroundColor = UIColor.systemCyan.withAlphaComponent(0.85)
        askMultiButton.setTitleColor(.black, for: .normal)
        askMultiButton.layer.cornerRadius = 10
        askMultiButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        askMultiButton.isHidden = true
        askMultiButton.addTarget(self, action: #selector(didTapAskMulti), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [ocrSpinner, hintLabel, selectAllMultiButton, copyMultiButton, translateHereButton, askMultiButton])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        bottomActionBar.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            bottomActionBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            bottomActionBar.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 14),
            bottomActionBar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -14),
            bottomActionBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            stack.topAnchor.constraint(equalTo: bottomActionBar.contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomActionBar.contentView.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: bottomActionBar.contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: bottomActionBar.contentView.trailingAnchor, constant: -12),
        ])
    }

    private func setupDragOCR() {
        selectionBoxView.isHidden = true
        selectionBoxView.backgroundColor = UIColor.systemCyan.withAlphaComponent(0.18)
        selectionBoxView.layer.borderColor = UIColor.systemCyan.cgColor
        selectionBoxView.layer.borderWidth = 2
        selectionBoxView.layer.cornerRadius = 8
        view.addSubview(selectionBoxView)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        pan.cancelsTouchesInView = false
        view.addGestureRecognizer(pan)
    }

    private func rebuildBlockButtons() {
        blockButtons.forEach { $0.removeFromSuperview() }
        blockButtons.removeAll()

        for (idx, block) in blocks.enumerated() {
            let btn = UIButton(type: .custom)
            btn.tag = idx
            btn.frame = block.rectInWindow.insetBy(dx: -2, dy: -2)
            btn.layer.cornerRadius = 6
            btn.layer.borderWidth = 1.4
            styleBlockButton(btn, selectedOrder: selectedIndices.firstIndex(of: idx), kind: block.sourceKind)
            btn.addTarget(self, action: #selector(didTapBlock(_:)), for: .touchUpInside)
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(didLongPressBlock(_:)))
            lp.minimumPressDuration = 0.4
            btn.addGestureRecognizer(lp)
            blocksContainer.addSubview(btn)
            blockButtons.append(btn)
        }
    }

    private func styleBlockButton(_ btn: UIButton, selectedOrder: Int?, kind: DetectedScreenTextBlock.SourceKind) {
        if let order = selectedOrder {
            btn.backgroundColor = UIColor.systemCyan.withAlphaComponent(0.32)
            btn.layer.borderColor = UIColor.white.cgColor
            btn.layer.borderWidth = 2.0
            btn.setTitle("\(order + 1)", for: .normal)
            btn.setTitleColor(.white, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 11, weight: .heavy)
        } else {
            let baseColor: UIColor = (kind == .ocr) ? .systemYellow : .systemCyan
            btn.backgroundColor = baseColor.withAlphaComponent(0.14)
            btn.layer.borderColor = baseColor.withAlphaComponent(0.78).cgColor
            btn.layer.borderWidth = 1.3
            btn.setTitle(nil, for: .normal)
        }
    }

    private func updateModeUI() {
        blocksContainer.isUserInteractionEnabled = (currentMode != .drawOCR)
        switch currentMode {
        case .tap:
            hintLabel.text = blocks.isEmpty
                ? "Drag a box over any text to scan with OCR"
                : "Tap box • Hold to copy • Drag for OCR"
            selectAllMultiButton.isHidden = true
            copyMultiButton.isHidden = true
            translateHereButton.isHidden = blocks.isEmpty
            translateHereButton.setTitle(" Translate Screen", for: .normal)
            askMultiButton.isHidden = true
        case .multiSelect:
            hintLabel.text = selectedIndices.isEmpty
                ? "Tap blocks in order"
                : "\(selectedIndices.count) selected"
            selectAllMultiButton.isHidden = blocks.isEmpty
            selectAllMultiButton.setTitle(selectedIndices.count == blocks.count && !blocks.isEmpty ? "None" : "All", for: .normal)
            copyMultiButton.isHidden = selectedIndices.isEmpty
            translateHereButton.isHidden = selectedIndices.isEmpty
            translateHereButton.setTitle(" On Screen", for: .normal)
            askMultiButton.isHidden = selectedIndices.isEmpty
            askMultiButton.setTitle("OmniAI (\(selectedIndices.count))", for: .normal)
        case .drawOCR:
            hintLabel.text = "Drag a rectangle over any text, image, or video"
            selectAllMultiButton.isHidden = true
            copyMultiButton.isHidden = true
            translateHereButton.isHidden = true
            askMultiButton.isHidden = true
        }
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        currentMode = Mode(rawValue: modeControl.selectedSegmentIndex) ?? .tap
        if currentMode != .multiSelect && !selectedIndices.isEmpty {
            selectedIndices.removeAll()
            refreshSelectionStyles()
        }
    }

    @objc private func didTapClose() {
        cleanupOverlayIfNeeded()
        if presentingViewController != nil {
            dismiss(animated: true)
        }
    }

    @objc private func didTapFullOCR() {
        runFullScreenOCR()
    }

    @objc private func didTapAskWithScreenshot() {
        let img = snapshot ?? ScreenTextScanner.captureSnapshot(of: sourceWindow)
        guard let img, let attached = AttachedImageItem.fromUIImage(img, label: "Screen") else {
            hintLabel.text = "Could not capture screen image."
            return
        }
        let combinedText = selectedIndices
            .compactMap { blocks.indices.contains($0) ? blocks[$0].text : nil }
            .joined(separator: "\n\n")
        let anchorRect = CGRect(
            x: max(16, view.bounds.midX - 60),
            y: max(80, view.bounds.midY - 30),
            width: 120,
            height: 60
        )
        presentWriteNow(
            withText: combinedText,
            anchorRect: anchorRect,
            sourceView: nil,
            attachedImages: [attached]
        )
    }

    @objc private func didTapBlock(_ sender: UIButton) {
        let idx = sender.tag
        guard blocks.indices.contains(idx) else { return }

        if currentMode == .multiSelect {
            if let existing = selectedIndices.firstIndex(of: idx) {
                selectedIndices.remove(at: existing)
            } else {
                selectedIndices.append(idx)
            }
            refreshSelectionStyles()
            updateModeUI()
            return
        }

        let block = blocks[idx]
        presentWriteNow(withText: block.text, anchorRect: block.rectInWindow, sourceView: block.sourceView)
    }

    @objc private func didLongPressBlock(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let btn = gesture.view as? UIButton,
              blocks.indices.contains(btn.tag)
        else { return }
        let text = blocks[btn.tag].text
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        hintLabel.text = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.updateModeUI()
        }
    }

    @objc private func didTapSelectAllMulti() {
        guard !blocks.isEmpty else { return }
        if selectedIndices.count == blocks.count {
            selectedIndices.removeAll()
        } else {
            selectedIndices = Array(blocks.indices)
        }
        refreshSelectionStyles()
        updateModeUI()
    }

    @objc private func didTapCopyMulti() {
        let texts = selectedIndices.compactMap { idx -> String? in
            guard blocks.indices.contains(idx) else { return nil }
            return blocks[idx].text
        }
        guard !texts.isEmpty else { return }
        UIPasteboard.general.string = texts.joined(separator: "\n\n")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        hintLabel.text = "Copied \(texts.count) block(s)!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.updateModeUI()
        }
    }

    @objc private func didTapAskMulti() {
        let texts = selectedIndices.compactMap { idx -> String? in
            guard blocks.indices.contains(idx) else { return nil }
            return blocks[idx].text
        }
        guard !texts.isEmpty else { return }
        let combined = texts.joined(separator: "\n\n")
        let unionRect = selectedIndices
            .compactMap { blocks.indices.contains($0) ? blocks[$0].rectInWindow : nil }
            .reduce(CGRect.null) { $0.isNull ? $1 : $0.union($1) }
        presentWriteNow(withText: combined, anchorRect: unionRect.isNull ? view.bounds : unionRect, sourceView: nil)
    }

    @objc private func didTapTranslateOnScreen() {
        let targetBlocks: [DetectedScreenTextBlock]
        if currentMode == .multiSelect && !selectedIndices.isEmpty {
            targetBlocks = selectedIndices.compactMap { blocks.indices.contains($0) ? blocks[$0] : nil }
        } else {
            targetBlocks = blocks
        }
        guard !targetBlocks.isEmpty, !isProcessingOCR else { return }
        translateBlocksOnScreen(targetBlocks)
    }

    private func translateBlocksOnScreen(_ targetBlocks: [DetectedScreenTextBlock]) {
        isProcessingOCR = true
        ocrSpinner.startAnimating()
        translateHereButton.isEnabled = false
        hintLabel.text = "Translating \(targetBlocks.count) block(s)..."

        let limited = Array(targetBlocks.prefix(24))
        let numberedInput = limited.enumerated().map { idx, blk in
            "[\(idx + 1)] \(blk.text.replacingOccurrences(of: "\n", with: " "))"
        }.joined(separator: "\n")

        let preferredLang = Locale.preferredLanguages.first?.lowercased() ?? "vi"
        let defaultTarget = preferredLang.hasPrefix("vi") ? "natural Vietnamese" : "natural English (or Vietnamese if already English)"
        let sysPrompt = """
        Translate each numbered line below into \(defaultTarget) (if a line is already in that language, keep or lightly refine it naturally).
        CRITICAL OUTPUT FORMAT:
        Return ONLY the translated lines using the EXACT same [1], [2], ... numbering on separate lines, with no extra commentary.
        """

        let query = ChatQuery(
            messages: [
                .system(.init(content: sysPrompt)),
                .user(.init(content: .string(numberedInput))),
            ],
            model: Configurator.shared.mid,
            temperature: 0.2
        )

        Configurator.shared.openAI.chats(query: query) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isProcessingOCR = false
                self.ocrSpinner.stopAnimating()
                self.translateHereButton.isEnabled = true

                switch result {
                case let .success(res):
                    let rawJoined = res.choices.compactMap { $0.message.content?.string }.joined()
                    let raw = Configurator.shared.settings.stripThinkingTags
                        ? PromptComposer.stripThinkingTags(from: rawJoined)
                        : rawJoined
                    let parsed = Self.parseNumberedTranslations(raw, expectedCount: limited.count)
                    var requests: [InPlaceReplacementRequest] = []
                    for (idx, blk) in limited.enumerated() {
                        if let translated = parsed[idx], !translated.isEmpty {
                            requests.append(
                                InPlaceReplacementRequest(
                                    frameInWindow: blk.rectInWindow,
                                    originalText: blk.text,
                                    replacedText: translated,
                                    targetView: blk.sourceView,
                                    selectedNSRange: nil
                                )
                            )
                        }
                    }
                    if requests.isEmpty {
                        let fallback = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !fallback.isEmpty, let first = limited.first {
                            let union = limited.map(\.rectInWindow).reduce(first.rectInWindow) { $0.union($1) }
                            requests.append(
                                InPlaceReplacementRequest(
                                    frameInWindow: union,
                                    originalText: limited.map(\.text).joined(separator: "\n"),
                                    replacedText: fallback,
                                    targetView: limited.count == 1 ? first.sourceView : nil,
                                    selectedNSRange: nil
                                )
                            )
                        }
                    }
                    guard !requests.isEmpty else {
                        self.hintLabel.text = "Translation returned empty."
                        return
                    }
                    let win = self.sourceWindow
                    let snap = self.snapshot
                    self.didTapClose()
                    InPlaceTextReplacementManager.shared.applyReplacements(requests: requests, in: win, snapshot: snap)

                case let .failure(err):
                    self.hintLabel.text = err.localizedDescription
                }
            }
        }
    }

    private static func parseNumberedTranslations(_ raw: String, expectedCount: Int) -> [Int: String] {
        var result: [Int: String] = [:]
        let lines = raw.components(separatedBy: .newlines)
        var currentIdx: Int?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("["),
               let closeIdx = trimmed.firstIndex(of: "]"),
               let num = Int(trimmed[trimmed.index(after: trimmed.startIndex) ..< closeIdx]),
               num >= 1, num <= expectedCount
            {
                let after = trimmed[trimmed.index(after: closeIdx)...].trimmingCharacters(in: .whitespaces)
                currentIdx = num - 1
                if !after.isEmpty {
                    result[num - 1] = after
                }
            } else if let idx = currentIdx {
                result[idx] = (result[idx].map { $0 + " " } ?? "") + trimmed
            }
        }
        return result
    }

    @objc private func handleDrag(_ gesture: UIPanGestureRecognizer) {
        let pt = gesture.location(in: view)
        switch gesture.state {
        case .began:
            dragStartPoint = pt
            selectionBoxView.frame = CGRect(origin: pt, size: .zero)
            selectionBoxView.isHidden = false
        case .changed:
            guard let start = dragStartPoint else { return }
            selectionBoxView.frame = CGRect(
                x: min(start.x, pt.x),
                y: min(start.y, pt.y),
                width: abs(pt.x - start.x),
                height: abs(pt.y - start.y)
            )
        case .ended, .cancelled:
            let box = selectionBoxView.frame
            selectionBoxView.isHidden = true
            dragStartPoint = nil
            guard box.width >= 24, box.height >= 24 else { return }
            runRegionOCR(rect: box)
        default:
            break
        }
    }

    private func refreshSelectionStyles() {
        for (idx, btn) in blockButtons.enumerated() where blocks.indices.contains(idx) {
            styleBlockButton(btn, selectedOrder: selectedIndices.firstIndex(of: idx), kind: blocks[idx].sourceKind)
        }
    }

    private func runFullScreenOCR() {
        guard !isProcessingOCR, let snapshot else { return }
        isProcessingOCR = true
        ocrSpinner.startAnimating()
        hintLabel.text = "Scanning text on screen (OCR)..."

        ScreenTextScanner.recognizeText(
            in: snapshot,
            windowBounds: view.bounds,
            regionInWindow: nil,
            preferredLanguages: Configurator.shared.settings.ocrPreferredLanguages
        ) { [weak self] ocrBlocks in
            guard let self else { return }
            self.isProcessingOCR = false
            self.ocrSpinner.stopAnimating()
            if !ocrBlocks.isEmpty {
                self.blocks = ocrBlocks
                self.selectedIndices.removeAll()
                self.rebuildBlockButtons()
                self.updateModeUI()
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                self.hintLabel.text = "No text detected — drag a box to scan"
            }
        }
    }

    private func runRegionOCR(rect: CGRect) {
        guard !isProcessingOCR, let snapshot else { return }
        isProcessingOCR = true
        ocrSpinner.startAnimating()
        hintLabel.text = "Recognizing selected area..."

        ScreenTextScanner.recognizeText(
            in: snapshot,
            windowBounds: view.bounds,
            regionInWindow: rect,
            preferredLanguages: Configurator.shared.settings.ocrPreferredLanguages
        ) { [weak self] ocrBlocks in
            guard let self else { return }
            self.isProcessingOCR = false
            self.ocrSpinner.stopAnimating()

            let combined = ocrBlocks.map(\.text).joined(separator: "\n")
            if !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.presentWriteNow(withText: combined, anchorRect: rect, sourceView: nil)
            } else {
                self.hintLabel.text = "No text found in that region."
            }
        }
    }

    private func presentWriteNow(
        withText text: String,
        anchorRect: CGRect,
        sourceView: UIView?,
        attachedImages: [AttachedImageItem] = []
    ) {
        activeAnchorHostView?.removeFromSuperview()
        let hostView = UIView(frame: anchorRect)
        hostView.backgroundColor = .clear
        hostView.isUserInteractionEnabled = false
        view.addSubview(hostView)
        activeAnchorHostView = hostView

        Presenter.shared.presentExtractedText(
            text,
            fromHostView: hostView,
            nativeSourceView: sourceView,
            parentController: self,
            anchorRectInHost: hostView.bounds,
            slotIndex: 0,
            initialAttachedImages: attachedImages,
            onCompleteAndClose: { [weak self] in
                self?.didTapClose()
            }
        )
    }
}
