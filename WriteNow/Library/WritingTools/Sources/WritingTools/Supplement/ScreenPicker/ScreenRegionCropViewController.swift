//
//  ScreenRegionCropViewController.swift
//  WritingTools
//

import UIKit

final class ScreenRegionCropViewController: UIViewController {
    enum ActionMode {
        case attachImage
        case ocrText
    }

    private let sourceWindow: UIWindow
    private let snapshot: UIImage?
    private let initialMode: ActionMode
    private let onComplete: (AttachedImageItem?, String?, CGRect) -> Void

    var ownedOverlayWindow: UIWindow?

    private let dimLayer = CAShapeLayer()
    private let selectionBorder = UIView()
    private let topHintPill = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let hintLabel = UILabel()
    private let actionBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let askAIButton = UIButton(type: .system)
    private let ocrButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)

    private var dragStart: CGPoint = .zero
    private var selectedRect: CGRect = .zero {
        didSet { updateSelectionMask() }
    }

    init(
        sourceWindow: UIWindow,
        snapshot: UIImage?,
        initialMode: ActionMode = .attachImage,
        onComplete: @escaping (AttachedImageItem?, String?, CGRect) -> Void
    ) {
        self.sourceWindow = sourceWindow
        self.snapshot = snapshot
        self.initialMode = initialMode
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = UIColor.black.withAlphaComponent(0.32).cgColor
        view.layer.addSublayer(dimLayer)

        selectionBorder.isHidden = true
        selectionBorder.isUserInteractionEnabled = false
        selectionBorder.backgroundColor = .clear
        selectionBorder.layer.borderWidth = 2
        selectionBorder.layer.borderColor = UIColor.systemCyan.cgColor
        selectionBorder.layer.cornerRadius = 6
        view.addSubview(selectionBorder)

        setupBars()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        view.addGestureRecognizer(pan)
        updateSelectionMask()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        dimLayer.frame = view.bounds
        updateSelectionMask()
    }

    private func setupBars() {
        topHintPill.layer.cornerRadius = 15
        topHintPill.clipsToBounds = true
        topHintPill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topHintPill)

        hintLabel.text = "Drag across any area on screen"
        hintLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        hintLabel.textColor = .white
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        topHintPill.contentView.addSubview(hintLabel)

        actionBar.layer.cornerRadius = 18
        actionBar.clipsToBounds = true
        actionBar.layer.borderWidth = 0.6
        actionBar.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionBar)

        askAIButton.setImage(UIImage(systemName: "photo.badge.plus"), for: .normal)
        askAIButton.setTitle(" Ask AI", for: .normal)
        askAIButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .bold)
        askAIButton.tintColor = .systemGreen
        askAIButton.isEnabled = false
        askAIButton.addTarget(self, action: #selector(didTapAskAI), for: .touchUpInside)

        ocrButton.setImage(UIImage(systemName: "text.viewfinder"), for: .normal)
        ocrButton.setTitle(" OCR", for: .normal)
        ocrButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        ocrButton.tintColor = .systemCyan
        ocrButton.isEnabled = false
        ocrButton.addTarget(self, action: #selector(didTapOCR), for: .touchUpInside)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        cancelButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [askAIButton, ocrButton, cancelButton])
        stack.axis = .horizontal
        stack.spacing = 14
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        actionBar.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            topHintPill.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            topHintPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: topHintPill.contentView.topAnchor, constant: 7),
            hintLabel.bottomAnchor.constraint(equalTo: topHintPill.contentView.bottomAnchor, constant: -7),
            hintLabel.leadingAnchor.constraint(equalTo: topHintPill.contentView.leadingAnchor, constant: 14),
            hintLabel.trailingAnchor.constraint(equalTo: topHintPill.contentView.trailingAnchor, constant: -14),

            actionBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            actionBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.topAnchor.constraint(equalTo: actionBar.contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: actionBar.contentView.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: actionBar.contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: actionBar.contentView.trailingAnchor, constant: -16),
        ])
    }

    private func updateSelectionMask() {
        let outer = UIBezierPath(rect: view.bounds)
        if selectedRect.width > 12, selectedRect.height > 12 {
            outer.append(UIBezierPath(roundedRect: selectedRect, cornerRadius: 6))
            selectionBorder.isHidden = false
            selectionBorder.frame = selectedRect
            askAIButton.isEnabled = true
            ocrButton.isEnabled = true
            hintLabel.text = "\(Int(selectedRect.width)) × \(Int(selectedRect.height))"
        } else {
            selectionBorder.isHidden = true
            askAIButton.isEnabled = false
            ocrButton.isEnabled = false
            hintLabel.text = "Drag across any area on screen"
        }
        dimLayer.path = outer.cgPath
    }

    @objc private func handleDrag(_ gesture: UIPanGestureRecognizer) {
        let pt = gesture.location(in: view)
        switch gesture.state {
        case .began:
            dragStart = pt
            selectedRect = CGRect(origin: pt, size: .zero)
        case .changed:
            selectedRect = CGRect(
                x: min(dragStart.x, pt.x),
                y: min(dragStart.y, pt.y),
                width: abs(pt.x - dragStart.x),
                height: abs(pt.y - dragStart.y)
            )
        case .ended, .cancelled:
            if selectedRect.width > 28, selectedRect.height > 28 {
                if initialMode == .ocrText {
                    didTapOCR()
                }
            }
        default:
            break
        }
    }

    @objc private func didTapAskAI() {
        guard let cropped = cropRegionImage() else {
            close(image: nil, text: nil, rect: selectedRect)
            return
        }
        let item = AttachedImageItem.fromUIImage(cropped, label: "Region")
        close(image: item, text: nil, rect: selectedRect)
    }

    @objc private func didTapOCR() {
        guard let img = snapshot ?? ScreenTextScanner.captureSnapshot(of: sourceWindow) else {
            close(image: nil, text: nil, rect: selectedRect)
            return
        }
        let langs = Configurator.shared.settings.ocrPreferredLanguages
        let rect = selectedRect
        ScreenTextScanner.recognizeText(
            in: img,
            windowBounds: sourceWindow.bounds,
            regionInWindow: rect,
            preferredLanguages: langs
        ) { [weak self] blocks in
            let text = blocks.map(\.text).joined(separator: "\n\n")
            self?.close(image: nil, text: text, rect: rect)
        }
    }

    @objc private func didTapCancel() {
        close(image: nil, text: nil, rect: .zero)
    }

    private func cropRegionImage() -> UIImage? {
        guard selectedRect.width > 12, selectedRect.height > 12 else { return nil }
        let full = snapshot ?? ScreenTextScanner.captureSnapshot(of: sourceWindow)
        guard let full, let cg = full.cgImage else { return nil }
        let winBounds = sourceWindow.bounds
        guard winBounds.width > 0, winBounds.height > 0 else { return nil }
        let scaleX = CGFloat(cg.width) / winBounds.width
        let scaleY = CGFloat(cg.height) / winBounds.height
        let cropRect = CGRect(
            x: max(0, selectedRect.origin.x * scaleX),
            y: max(0, selectedRect.origin.y * scaleY),
            width: min(CGFloat(cg.width) - max(0, selectedRect.origin.x * scaleX), selectedRect.width * scaleX),
            height: min(CGFloat(cg.height) - max(0, selectedRect.origin.y * scaleY), selectedRect.height * scaleY)
        )
        guard cropRect.width >= 8, cropRect.height >= 8,
              let subCG = cg.cropping(to: cropRect)
        else { return nil }
        return UIImage(cgImage: subCG, scale: full.scale, orientation: full.imageOrientation)
    }

    private func close(image: AttachedImageItem?, text: String?, rect: CGRect) {
        if let win = ownedOverlayWindow {
            win.isHidden = true
            win.rootViewController = nil
            ownedOverlayWindow = nil
        } else if presentingViewController != nil {
            dismiss(animated: false)
        }
        onComplete(image, text, rect)
    }
}
