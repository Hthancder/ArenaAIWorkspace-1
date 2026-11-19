//
//  InPlaceTextReplacementManager.swift
//  WritingTools
//

import UIKit

struct InPlaceReplacementEntry {
    let id = UUID()
    let frameInWindow: CGRect
    let originalText: String
    var replacedText: String
    let backgroundColor: UIColor
    let textColor: UIColor
    var showingOriginal: Bool = false
}

final class InPlaceTextReplacementManager: NSObject {
    static let shared = InPlaceTextReplacementManager()

    private var overlayWindow: InPlaceReplacementWindow?
    private weak var rootController: InPlaceReplacementViewController?

    override private init() {
        super.init()
    }

    var isShowingOverlay: Bool {
        overlayWindow != nil && !(overlayWindow?.isHidden ?? true)
    }

    func showReplacements(
        entries: [(frameInWindow: CGRect, originalText: String, replacedText: String)],
        in sourceWindow: UIWindow,
        snapshot: UIImage? = nil
    ) {
        let resolvedSnap = snapshot ?? ScreenTextScanner.captureSnapshot(of: sourceWindow)
        let built: [InPlaceReplacementEntry] = entries.compactMap { item in
            let trimmed = item.replacedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let clampedFrame = clampFrame(item.frameInWindow, in: sourceWindow.bounds)
            let colors = Self.sampleColors(in: resolvedSnap, rect: clampedFrame, windowBounds: sourceWindow.bounds)
            return InPlaceReplacementEntry(
                frameInWindow: clampedFrame,
                originalText: item.originalText,
                replacedText: trimmed,
                backgroundColor: colors.bg,
                textColor: colors.fg,
                showingOriginal: false
            )
        }
        guard !built.isEmpty else { return }

        if let existingVC = rootController, let win = overlayWindow, !win.isHidden {
            existingVC.appendOrUpdate(entries: built)
            return
        }

        let vc = InPlaceReplacementViewController(sourceWindow: sourceWindow, entries: built)
        vc.onDismissAll = { [weak self] in
            self?.clearAll()
        }

        let win: InPlaceReplacementWindow
        if let scene = sourceWindow.windowScene {
            win = InPlaceReplacementWindow(windowScene: scene)
        } else {
            win = InPlaceReplacementWindow(frame: sourceWindow.bounds)
        }
        win.frame = sourceWindow.bounds
        win.backgroundColor = .clear
        win.isOpaque = false
        win.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 25)
        win.rootViewController = vc
        win.isHidden = false

        overlayWindow = win
        rootController = vc
    }

    func clearAll() {
        overlayWindow?.isHidden = true
        overlayWindow?.rootViewController = nil
        overlayWindow = nil
        rootController = nil
    }

    private func clampFrame(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        let validW = max(84, min(bounds.width - 16, rect.width > 12 ? rect.width : bounds.width * 0.72))
        let validH = max(28, min(bounds.height * 0.55, rect.height > 12 ? rect.height : 68))
        let x = max(8, min(bounds.width - validW - 8, rect.origin.x))
        let y = max(44, min(bounds.height - validH - 44, rect.origin.y))
        return CGRect(x: x, y: y, width: validW, height: validH)
    }

    static func sampleColors(in image: UIImage?, rect: CGRect, windowBounds: CGRect) -> (bg: UIColor, fg: UIColor) {
        guard let image, let cg = image.cgImage, windowBounds.width > 0, windowBounds.height > 0 else {
            return (UIColor.black.withAlphaComponent(0.90), .white)
        }
        let scaleX = CGFloat(cg.width) / windowBounds.width
        let scaleY = CGFloat(cg.height) / windowBounds.height

        let points: [CGPoint] = [
            CGPoint(x: rect.minX + 4, y: rect.minY + 3),
            CGPoint(x: rect.midX, y: rect.minY + 3),
            CGPoint(x: rect.maxX - 4, y: rect.minY + 3),
            CGPoint(x: rect.minX + 4, y: rect.maxY - 3),
            CGPoint(x: rect.maxX - 4, y: rect.maxY - 3),
            CGPoint(x: rect.minX + 3, y: rect.midY),
            CGPoint(x: rect.maxX - 3, y: rect.midY),
        ]

        var totalR: CGFloat = 0
        var totalG: CGFloat = 0
        var totalB: CGFloat = 0
        var count: CGFloat = 0

        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (UIColor.black.withAlphaComponent(0.90), .white)
        }

        for pt in points {
            let px = max(0, min(cg.width - 1, Int(pt.x * scaleX)))
            let py = max(0, min(cg.height - 1, Int(pt.y * scaleY)))
            let crop = CGRect(x: px, y: py, width: 1, height: 1)
            guard let sub = cg.cropping(to: crop) else { continue }
            ctx.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
            ctx.draw(sub, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            totalR += CGFloat(pixel[0]) / 255.0
            totalG += CGFloat(pixel[1]) / 255.0
            totalB += CGFloat(pixel[2]) / 255.0
            count += 1
        }

        guard count > 0 else {
            return (UIColor.black.withAlphaComponent(0.90), .white)
        }
        let r = totalR / count
        let g = totalG / count
        let b = totalB / count
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b

        let bg = UIColor(red: r, green: g, blue: b, alpha: 0.96)
        let fg: UIColor = luminance > 0.54 ? UIColor(white: 0.08, alpha: 1.0) : .white
        return (bg, fg)
    }
}

private final class InPlaceReplacementWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        if hit === self || hit === rootViewController?.view {
            return nil
        }
        return hit
    }
}

private final class InPlaceReplacementViewController: UIViewController {
    private let sourceWindow: UIWindow
    private var entries: [InPlaceReplacementEntry]
    private var cardViews: [UUID: InPlaceCardView] = [:]
    private var globalShowingOriginal = false

    private let toolbar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let toggleAllButton = UIButton(type: .system)
    private let copyAllButton = UIButton(type: .system)
    private let closeAllButton = UIButton(type: .system)

    var onDismissAll: (() -> Void)?

    init(sourceWindow: UIWindow, entries: [InPlaceReplacementEntry]) {
        self.sourceWindow = sourceWindow
        self.entries = entries
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupToolbar()
        rebuildCards()
    }

    func appendOrUpdate(entries newEntries: [InPlaceReplacementEntry]) {
        for item in newEntries {
            if let idx = entries.firstIndex(where: { $0.frameInWindow.intersects(item.frameInWindow) && $0.originalText == item.originalText }) {
                entries[idx].replacedText = item.replacedText
                entries[idx].showingOriginal = false
            } else {
                entries.append(item)
            }
        }
        globalShowingOriginal = false
        updateToggleButtonTitle()
        rebuildCards()
    }

    private func setupToolbar() {
        toolbar.layer.cornerRadius = 18
        toolbar.clipsToBounds = true
        toolbar.layer.borderWidth = 0.7
        toolbar.layer.borderColor = UIColor.systemCyan.withAlphaComponent(0.55).cgColor
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        toggleAllButton.setImage(UIImage(systemName: "eye"), for: .normal)
        toggleAllButton.setTitle(" Original", for: .normal)
        toggleAllButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        toggleAllButton.tintColor = .systemCyan
        toggleAllButton.addTarget(self, action: #selector(didTapToggleAll), for: .touchUpInside)

        copyAllButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copyAllButton.setTitle(" Copy", for: .normal)
        copyAllButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        copyAllButton.tintColor = .white
        copyAllButton.addTarget(self, action: #selector(didTapCopyAll), for: .touchUpInside)

        closeAllButton.setImage(UIImage(systemName: "arrow.uturn.backward.circle.fill"), for: .normal)
        closeAllButton.setTitle(" Revert", for: .normal)
        closeAllButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        closeAllButton.tintColor = .systemOrange
        closeAllButton.addTarget(self, action: #selector(didTapCloseAll), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [toggleAllButton, copyAllButton, closeAllButton])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            toolbar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.topAnchor.constraint(equalTo: toolbar.contentView.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: toolbar.contentView.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: toolbar.contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: toolbar.contentView.trailingAnchor, constant: -12),
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleToolbarPan(_:)))
        toolbar.addGestureRecognizer(pan)
    }

    private func updateToggleButtonTitle() {
        toggleAllButton.setImage(UIImage(systemName: globalShowingOriginal ? "sparkles" : "eye"), for: .normal)
        toggleAllButton.setTitle(globalShowingOriginal ? " Replaced" : " Original", for: .normal)
        toggleAllButton.tintColor = globalShowingOriginal ? .systemGreen : .systemCyan
    }

    private func rebuildCards() {
        cardViews.values.forEach { $0.removeFromSuperview() }
        cardViews.removeAll()

        let bounds = view.bounds
        for entry in entries {
            let card = InPlaceCardView(entry: entry, maxBounds: bounds)
            card.onTapToggle = { [weak self] id in
                self?.toggleEntry(id: id)
            }
            card.onLongPress = { [weak self] id, anchorView in
                self?.showCardMenu(id: id, from: anchorView)
            }
            view.insertSubview(card, belowSubview: toolbar)
            cardViews[entry.id] = card
        }
    }

    private func toggleEntry(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].showingOriginal.toggle()
        cardViews[id]?.update(entry: entries[idx])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func showCardMenu(id: UUID, from anchor: UIView) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[idx]
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(
            title: entry.showingOriginal ? "Show AI Result" : "Peek Original Text",
            style: .default
        ) { [weak self] _ in
            self?.toggleEntry(id: id)
        })
        sheet.addAction(UIAlertAction(title: "Copy Result", style: .default) { _ in
            UIPasteboard.general.string = entry.replacedText
        })
        sheet.addAction(UIAlertAction(title: "Open in OmniAI", style: .default) { [weak self] _ in
            guard let self else { return }
            self.onDismissAll?()
            Presenter.shared.presentExtractedText(
                entry.originalText,
                fromHostView: self.sourceWindow,
                parentController: nil,
                anchorRectInHost: entry.frameInWindow,
                slotIndex: 0
            )
        })
        sheet.addAction(UIAlertAction(title: "Revert This Region", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.entries.removeAll { $0.id == id }
            self.cardViews[id]?.removeFromSuperview()
            self.cardViews.removeValue(forKey: id)
            if self.entries.isEmpty {
                self.onDismissAll?()
            }
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = anchor
            pop.sourceRect = anchor.bounds
        }
        present(sheet, animated: true)
    }

    @objc private func didTapToggleAll() {
        globalShowingOriginal.toggle()
        for idx in entries.indices {
            entries[idx].showingOriginal = globalShowingOriginal
            cardViews[entries[idx].id]?.update(entry: entries[idx])
        }
        updateToggleButtonTitle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func didTapCopyAll() {
        let joined = entries.map { $0.showingOriginal ? $0.originalText : $0.replacedText }.joined(separator: "\n\n")
        UIPasteboard.general.string = joined
        copyAllButton.setTitle(" Copied", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyAllButton.setTitle(" Copy", for: .normal)
        }
    }

    @objc private func didTapCloseAll() {
        onDismissAll?()
    }

    @objc private func handleToolbarPan(_ gesture: UIPanGestureRecognizer) {
        let delta = gesture.translation(in: view)
        toolbar.center = CGPoint(
            x: max(110, min(view.bounds.width - 110, toolbar.center.x + delta.x)),
            y: max(view.safeAreaInsets.top + 24, min(view.bounds.height - view.safeAreaInsets.bottom - 24, toolbar.center.y + delta.y))
        )
        gesture.setTranslation(.zero, in: view)
    }
}

private final class InPlaceCardView: UIView {
    private var entry: InPlaceReplacementEntry
    private let textView = UITextView()
    private let badgeLabel = UILabel()

    var onTapToggle: ((UUID) -> Void)?
    var onLongPress: ((UUID, UIView) -> Void)?

    init(entry: InPlaceReplacementEntry, maxBounds: CGRect) {
        self.entry = entry
        super.init(frame: .zero)

        let minWidth = max(entry.frameInWindow.width, 110)
        let targetWidth = min(maxBounds.width - 16, minWidth)
        let originX = max(8, min(maxBounds.width - targetWidth - 8, entry.frameInWindow.origin.x))

        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = false
        textView.textContainerInset = UIEdgeInsets(top: 5, left: 6, bottom: 5, right: 6)
        textView.textContainer.lineFragmentPadding = 0
        textView.font = Self.pickBestFont(for: entry.replacedText, fitting: CGSize(width: targetWidth, height: entry.frameInWindow.height))

        let measure = textView.sizeThatFits(CGSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude))
        let maxHeight = max(entry.frameInWindow.height, min(maxBounds.height * 0.48, ceil(measure.height) + 4))
        let originY = max(44, min(maxBounds.height - maxHeight - 40, entry.frameInWindow.origin.y))

        frame = CGRect(x: originX, y: originY, width: targetWidth, height: maxHeight)

        layer.cornerRadius = 8
        layer.borderWidth = 1
        clipsToBounds = true

        textView.frame = bounds
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textView.isScrollEnabled = measure.height > maxHeight + 2
        addSubview(textView)

        badgeLabel.font = .systemFont(ofSize: 8.5, weight: .bold)
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 4
        badgeLabel.clipsToBounds = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeLabel)
        NSLayoutConstraint.activate([
            badgeLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            badgeLabel.heightAnchor.constraint(equalToConstant: 13),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
        hold.minimumPressDuration = 0.42
        addGestureRecognizer(hold)

        update(entry: entry)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(entry: InPlaceReplacementEntry) {
        self.entry = entry
        if entry.showingOriginal {
            backgroundColor = UIColor.black.withAlphaComponent(0.05)
            layer.borderColor = UIColor.systemGray.withAlphaComponent(0.45).cgColor
            textView.isHidden = true
            badgeLabel.text = " ORIG "
            badgeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
            badgeLabel.textColor = .white
        } else {
            backgroundColor = entry.backgroundColor
            layer.borderColor = UIColor.systemCyan.withAlphaComponent(0.45).cgColor
            textView.isHidden = false
            textView.text = entry.replacedText
            textView.textColor = entry.textColor
            badgeLabel.text = " AI "
            badgeLabel.backgroundColor = UIColor.systemCyan.withAlphaComponent(0.26)
            badgeLabel.textColor = entry.textColor.withAlphaComponent(0.85)
        }
    }

    private static func pickBestFont(for text: String, fitting size: CGSize) -> UIFont {
        for fontSize in stride(from: 14.5, through: 11.0, by: -1.0) {
            let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
            let rect = (text as NSString).boundingRect(
                with: CGSize(width: max(40, size.width - 12), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            )
            if rect.height <= max(28, size.height * 1.35) {
                return font
            }
        }
        return UIFont.systemFont(ofSize: 11.5, weight: .medium)
    }

    @objc private func handleTap() {
        onTapToggle?(entry.id)
    }

    @objc private func handleHold(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onLongPress?(entry.id, self)
    }
}
