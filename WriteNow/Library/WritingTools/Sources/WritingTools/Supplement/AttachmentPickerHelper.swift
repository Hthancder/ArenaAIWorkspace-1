//
//  AttachmentPickerHelper.swift
//  WritingTools
//

import PhotosUI
import UIKit
import UniformTypeIdentifiers

final class AttachmentPickerHelper: NSObject, PHPickerViewControllerDelegate, UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private static var activeInstance: AttachmentPickerHelper?

    private var onImagesPicked: (([AttachedImageItem]) -> Void)?
    private var onOCRTextPicked: ((String) -> Void)?
    private var onCameraImagePicked: ((AttachedImageItem?, String?) -> Void)?
    private var onFilesPicked: (([AttachedImageItem], [AttachedFileItem], [String]) -> Void)?

    static func presentCameraPicker(
        from context: Presenter.Context,
        completion: @escaping (AttachedImageItem?, String?) -> Void
    ) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            completion(nil, "Camera is not available on this device.")
            return
        }
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
            completion(nil, "This host app does not declare camera permission. Use OmniAI app or Photo Library.")
            return
        }
        guard let presenterVC = findPresenterController(from: context) else {
            completion(nil, "Unable to open camera.")
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        let helper = AttachmentPickerHelper()
        helper.onCameraImagePicked = { item, err in
            Self.activeInstance = nil
            completion(item, err)
        }
        picker.delegate = helper
        Self.activeInstance = helper
        presenterVC.present(picker, animated: true)
    }

    static func presentPhotoOCRPicker(
        from context: Presenter.Context,
        preferredLanguages: [String],
        completion: @escaping (String) -> Void
    ) {
        guard let presenterVC = findPresenterController(from: context) else {
            completion("")
            return
        }
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        let helper = AttachmentPickerHelper()
        helper.onOCRTextPicked = { text in
            Self.activeInstance = nil
            completion(text)
        }
        helper.preferredOCRLanguages = preferredLanguages
        picker.delegate = helper
        Self.activeInstance = helper
        presenterVC.present(picker, animated: true)
    }

    private var preferredOCRLanguages: [String] = ["vi-VN", "en-US"]

    static func presentPhotoPicker(
        from context: Presenter.Context,
        remainingSlots: Int = 4,
        completion: @escaping ([AttachedImageItem]) -> Void
    ) {
        guard let presenterVC = findPresenterController(from: context) else {
            completion([])
            return
        }
        var config = PHPickerConfiguration()
        config.selectionLimit = max(1, min(4, remainingSlots))
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        let helper = AttachmentPickerHelper()
        helper.onImagesPicked = { items in
            Self.activeInstance = nil
            completion(items)
        }
        picker.delegate = helper
        Self.activeInstance = helper
        presenterVC.present(picker, animated: true)
    }

    static func presentDocumentPicker(
        from context: Presenter.Context,
        completion: @escaping ([AttachedImageItem], [AttachedFileItem], [String]) -> Void
    ) {
        guard let presenterVC = findPresenterController(from: context) else {
            completion([], [], [])
            return
        }
        let types: [UTType] = [
            .text,
            .plainText,
            .sourceCode,
            .json,
            .pdf,
            .commaSeparatedText,
            .xml,
            .html,
            .rtf,
            .image,
            .data,
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true

        let helper = AttachmentPickerHelper()
        helper.onFilesPicked = { images, files, errors in
            Self.activeInstance = nil
            completion(images, files, errors)
        }
        picker.delegate = helper
        Self.activeInstance = helper
        presenterVC.present(picker, animated: true)
    }

    static func captureScreenSnapshot(
        from context: Presenter.Context,
        completion: @escaping (AttachedImageItem?) -> Void
    ) {
        let hostWin: UIWindow? = {
            if let w = context.targetView.window, !(w is WriteNowPopoverHostWindow) {
                return w
            }
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .filter { !$0.isHidden && !($0 is WriteNowPopoverHostWindow) && $0.windowLevel == .normal }
                .sorted { $0.isKeyWindow && !$1.isKeyWindow }
                .first { !NSStringFromClass(type(of: $0)).contains("WriteNow") }
        }()

        guard let window = hostWin else {
            completion(nil)
            return
        }

        let popoverVC = findPresenterController(from: context)
        let sameWindow = (popoverVC?.view.window === window)
        let prevAlpha = popoverVC?.view.superview?.alpha ?? 1.0
        if sameWindow {
            popoverVC?.view.superview?.alpha = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (sameWindow ? 0.04 : 0.0)) {
            let snapshot = ScreenTextScanner.captureSnapshot(of: window)
            if sameWindow {
                popoverVC?.view.superview?.alpha = prevAlpha
            }
            guard let snapshot,
                  let item = AttachedImageItem.fromUIImage(snapshot, label: "Screen")
            else {
                completion(nil)
                return
            }
            completion(item)
        }
    }

    private static func findPresenterController(from context: Presenter.Context) -> UIViewController? {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for win in ws.windows where !win.isHidden {
                var cur = win.rootViewController
                while let next = cur?.presentedViewController, !next.isBeingDismissed {
                    cur = next
                }
                if cur is WritingToolController {
                    return cur
                }
            }
        }
        var cur: UIViewController? = context.parentController
        while let next = cur?.presentedViewController, !next.isBeingDismissed {
            cur = next
        }
        return cur
    }

    // MARK: - PHPickerViewControllerDelegate

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        if let ocrCallback = onOCRTextPicked {
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self)
            else {
                ocrCallback("")
                return
            }
            let langs = preferredOCRLanguages
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else {
                    DispatchQueue.main.async { ocrCallback("") }
                    return
                }
                ScreenTextScanner.recognizePlainText(in: image, preferredLanguages: langs) { text in
                    ocrCallback(text)
                }
            }
            return
        }

        guard !results.isEmpty else {
            onImagesPicked?([])
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var loaded: [(Int, AttachedImageItem)] = []

        for (idx, result) in results.prefix(4).enumerated() {
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
            group.enter()
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                defer { group.leave() }
                guard let image = object as? UIImage else { return }
                let label = provider.suggestedName?.isEmpty == false ? (provider.suggestedName ?? "Photo") : "Photo \(idx + 1)"
                if let item = AttachedImageItem.fromUIImage(image, label: label) {
                    lock.lock()
                    loaded.append((idx, item))
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            let sorted = loaded.sorted { $0.0 < $1.0 }.map(\.1)
            self?.onImagesPicked?(sorted)
        }
    }

    // MARK: - UIDocumentPickerDelegate

    func documentPickerWasCancelled(_: UIDocumentPickerViewController) {
        onFilesPicked?([], [], [])
    }

    func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty else {
            onFilesPicked?([], [], [])
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var images: [AttachedImageItem] = []
            var files: [AttachedFileItem] = []
            var errors: [String] = []
            for url in urls.prefix(4) {
                switch AttachmentFileParser.parse(url: url) {
                case let .image(img):
                    images.append(img)
                case let .file(file):
                    files.append(file)
                case let .failure(msg):
                    errors.append(msg)
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.onFilesPicked?(images, files, errors)
            }
        }
    }

    // MARK: - UIImagePickerControllerDelegate

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        onCameraImagePicked?(nil, nil)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        guard let image, let item = AttachedImageItem.fromUIImage(image, label: "Camera") else {
            onCameraImagePicked?(nil, "Failed to process captured photo.")
            return
        }
        onCameraImagePicked?(item, nil)
    }
}
