//
//  TextProxy+ReadOnly.swift
//  WritingTools
//

import UIKit

extension TextProxy {
    static func makeReadOnlyFallback(from respondingView: UIView) -> TextProxy? {
        guard Configurator.shared.settings.readOnlyEnabled else { return nil }

        var extractedText = ""
        var rects: [CGRect] = []

        // 1. Any UITextInput conforming view (custom editors / PDF text containers)
        if let textInput = respondingView as? UITextInput,
           let range = textInput.selectedTextRange,
           !range.isEmpty
        {
            extractedText = textInput.text(in: range) ?? ""
            rects = textInput.selectionRects(for: range).map(\.rect).filter { $0.width > 0 && $0.height > 0 }
        }

        // 2. PDFView (check responder and up to 4 ancestors)
        if extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let pdfText = extractPDFSelectionText(near: respondingView) {
                extractedText = pdfText
            }
        }

        // 3. Direct safe text selectors (selectedText, text, attributedText, accessibilityValue)
        if extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            extractedText = extractSafeTextProperty(from: respondingView) ?? ""
        }

        // 4. Child UILabel if view is a label container
        if extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let label = respondingView as? UILabel {
                extractedText = label.text ?? label.attributedText?.string ?? ""
            } else if let subLabel = findFirstLabel(in: respondingView, maxDepth: 2) {
                extractedText = subLabel.text ?? subLabel.attributedText?.string ?? ""
            }
        }

        // 5. Last-resort safe copy: snapshot/restore pasteboard when view explicitly supports copy:
        if extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           respondingView.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil)
        {
            extractedText = extractViaTemporaryCopy(from: respondingView) ?? ""
        }

        let clean = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        if rects.isEmpty {
            let inset = respondingView.bounds.insetBy(dx: min(12, respondingView.bounds.width * 0.15), dy: min(12, respondingView.bounds.height * 0.15))
            rects = [inset.isEmpty ? respondingView.bounds : inset]
        }

        return TextProxy(
            readOnlyFallbackView: respondingView,
            initialText: extractedText,
            selectionRects: rects
        )
    }

    private static func extractPDFSelectionText(near view: UIView) -> String? {
        guard let pdfViewCls = NSClassFromString("PDFView") else { return nil }
        var cursor: UIView? = view
        for _ in 0 ..< 5 {
            guard let current = cursor else { break }
            if current.isKind(of: pdfViewCls) {
                let selSelector = NSSelectorFromString("currentSelection")
                if current.responds(to: selSelector),
                   let selection = current.perform(selSelector)?.takeUnretainedValue() as? NSObject
                {
                    let strSel = NSSelectorFromString("string")
                    if selection.responds(to: strSel),
                       let text = selection.perform(strSel)?.takeUnretainedValue() as? String,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    {
                        return text
                    }
                }
            }
            cursor = current.superview
        }
        return nil
    }

    private static func extractSafeTextProperty(from object: NSObject) -> String? {
        for key in ["selectedText", "text"] {
            let sel = NSSelectorFromString(key)
            if object.responds(to: sel),
               let str = object.perform(sel)?.takeUnretainedValue() as? String,
               !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return str
            }
        }
        let attrSel = NSSelectorFromString("attributedText")
        if object.responds(to: attrSel),
           let attr = object.perform(attrSel)?.takeUnretainedValue() as? NSAttributedString,
           !attr.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return attr.string
        }
        return nil
    }

    private static func findFirstLabel(in view: UIView, maxDepth: Int) -> UILabel? {
        guard maxDepth >= 0 else { return nil }
        if let label = view as? UILabel,
           !(label.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return label
        }
        guard maxDepth > 0 else { return nil }
        for sub in view.subviews {
            if let hit = findFirstLabel(in: sub, maxDepth: maxDepth - 1) {
                return hit
            }
        }
        return nil
    }

    private static func extractViaTemporaryCopy(from view: UIView) -> String? {
        let pasteboard = UIPasteboard.general
        let savedItems = pasteboard.items
        let previousChangeCount = pasteboard.changeCount

        UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.copy(_:)), to: view, from: nil, for: nil)

        var copied: String?
        if pasteboard.changeCount != previousChangeCount {
            copied = pasteboard.string
            pasteboard.items = savedItems
        }
        return copied
    }
}
