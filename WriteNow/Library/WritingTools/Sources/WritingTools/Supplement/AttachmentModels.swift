//
//  AttachmentModels.swift
//  WritingTools
//

import Foundation
import PDFKit
import UIKit

public struct AttachedImageItem: Identifiable, Equatable {
    public let id: UUID
    public let jpegData: Data
    public let thumbnail: UIImage
    public let label: String

    public init(id: UUID = UUID(), jpegData: Data, thumbnail: UIImage, label: String) {
        self.id = id
        self.jpegData = jpegData
        self.thumbnail = thumbnail
        self.label = label
    }

    public static func == (lhs: AttachedImageItem, rhs: AttachedImageItem) -> Bool {
        lhs.id == rhs.id
    }

    public var sizeSummary: String {
        let kb = max(1, jpegData.count / 1024)
        return "\(kb)KB"
    }

    public static func fromUIImage(
        _ image: UIImage,
        label: String,
        maxDimension: CGFloat = 1280,
        quality: CGFloat = 0.78
    ) -> AttachedImageItem? {
        let origSize = image.size
        guard origSize.width > 1, origSize.height > 1 else { return nil }

        let longest = max(origSize.width, origSize.height)
        let ratio = longest > maxDimension ? (maxDimension / longest) : 1.0
        let targetSize = CGSize(
            width: max(1, floor(origSize.width * ratio)),
            height: max(1, floor(origSize.height * ratio))
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let scaledImage = UIGraphicsImageRenderer(size: targetSize, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpegData = scaledImage.jpegData(compressionQuality: quality) else {
            return nil
        }

        let thumbScale = min(96.0 / max(targetSize.width, targetSize.height), 1.0)
        let thumbSize = CGSize(
            width: max(20, floor(targetSize.width * thumbScale)),
            height: max(20, floor(targetSize.height * thumbScale))
        )
        let thumbFormat = UIGraphicsImageRendererFormat()
        thumbFormat.scale = UIScreen.main.scale
        thumbFormat.opaque = true
        let thumbnail = UIGraphicsImageRenderer(size: thumbSize, format: thumbFormat).image { _ in
            scaledImage.draw(in: CGRect(origin: .zero, size: thumbSize))
        }

        return AttachedImageItem(jpegData: jpegData, thumbnail: thumbnail, label: label)
    }
}

public struct AttachedFileItem: Identifiable, Equatable {
    public let id: UUID
    public let fileName: String
    public let fileExtension: String
    public let byteCount: Int
    public let extractedText: String
    public let isTruncated: Bool

    public init(
        id: UUID = UUID(),
        fileName: String,
        fileExtension: String,
        byteCount: Int,
        extractedText: String,
        isTruncated: Bool
    ) {
        self.id = id
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.byteCount = byteCount
        self.extractedText = extractedText
        self.isTruncated = isTruncated
    }

    public var charCountSummary: String {
        if extractedText.count >= 1000 {
            return String(format: "%.1fk", Double(extractedText.count) / 1000.0)
        }
        return "\(extractedText.count)c"
    }
}

enum AttachmentFileParser {
    enum ParsedResult {
        case image(AttachedImageItem)
        case file(AttachedFileItem)
        case failure(String)
    }

    private static let maxCharsPerFile = 36_000
    private static let maxBytesToRead = 16 * 1024 * 1024
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "bmp", "tiff", "tif",
    ]

    static func parse(url: URL) -> ParsedResult {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = url.lastPathComponent.isEmpty ? "file" : url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let fileSize = values.fileSize,
           fileSize > maxBytesToRead
        {
            return .failure("\(fileName) is too large (>16 MB).")
        }

        if imageExtensions.contains(ext) {
            if let data = try? Data(contentsOf: url),
               let img = UIImage(data: data),
               let item = AttachedImageItem.fromUIImage(img, label: fileName)
            {
                return .image(item)
            }
            return .failure("Could not decode image \(fileName).")
        }

        if ext == "pdf" {
            guard let doc = PDFDocument(url: url) else {
                return .failure("Could not open PDF \(fileName).")
            }
            let pageLimit = min(doc.pageCount, 40)
            var sections: [String] = []
            for idx in 0 ..< pageLimit {
                guard let pageText = doc.page(at: idx)?.string?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !pageText.isEmpty
                else { continue }
                sections.append("--- Page \(idx + 1) ---\n\(pageText)")
            }
            let joined = sections.joined(separator: "\n\n")
            guard !joined.isEmpty else {
                return .failure("PDF \(fileName) has no selectable text (try attaching a screenshot).")
            }
            let truncated = joined.count > maxCharsPerFile || doc.pageCount > pageLimit
            let final = truncated ? String(joined.prefix(maxCharsPerFile)) : joined
            let sizeBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? joined.utf8.count
            return .file(AttachedFileItem(
                fileName: fileName,
                fileExtension: ext,
                byteCount: sizeBytes,
                extractedText: final,
                isTruncated: truncated
            ))
        }

        if ext == "rtf",
           let attr = try? NSAttributedString(
               url: url,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           )
        {
            let text = attr.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let truncated = text.count > maxCharsPerFile
                let final = truncated ? String(text.prefix(maxCharsPerFile)) : text
                return .file(AttachedFileItem(
                    fileName: fileName,
                    fileExtension: ext,
                    byteCount: text.utf8.count,
                    extractedText: final,
                    isTruncated: truncated
                ))
            }
        }

        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return .failure("Could not read \(fileName).")
        }

        let decoded: String?
        if let utf8 = String(data: data, encoding: .utf8) {
            decoded = utf8
        } else if let utf16 = String(data: data, encoding: .utf16) {
            decoded = utf16
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            decoded = latin1
        } else {
            decoded = nil
        }

        guard let rawText = decoded else {
            return .failure("\(fileName) cannot be read as text.")
        }

        // Guard against binary files disguised with generic extensions
        let sample = rawText.prefix(2048)
        let nullOrControlCount = sample.unicodeScalars.filter { scalar in
            scalar.value == 0 || (scalar.value < 0x09) || (scalar.value > 0x0D && scalar.value < 0x20)
        }.count
        if !sample.isEmpty && Double(nullOrControlCount) / Double(sample.count) > 0.04 {
            return .failure("\(fileName) appears to be a binary file.")
        }

        let cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return .failure("\(fileName) is empty.")
        }

        let truncated = cleaned.count > maxCharsPerFile
        let final = truncated ? String(cleaned.prefix(maxCharsPerFile)) : cleaned
        return .file(AttachedFileItem(
            fileName: fileName,
            fileExtension: ext,
            byteCount: data.count,
            extractedText: final,
            isTruncated: truncated
        ))
    }
}
