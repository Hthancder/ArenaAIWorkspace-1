//
//  TextProxy+ReadOnly.swift
//  WritingTools
//

import UIKit
import WebKit

extension TextProxy {
    static func makeReadOnlyWithText(_ text: String, view: UIView, selectionRect: CGRect? = nil) -> TextProxy? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let rect = selectionRect ?? view.bounds
        return TextProxy(
            readOnlyFallbackView: view,
            initialText: text,
            selectionRects: [rect.isEmpty ? view.bounds : rect]
        )
    }

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

        // 3. Direct safe text selectors (selectedText, text, attributedText)
        if extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            extractedText = extractSafeTextProperty(from: respondingView) ?? ""
        }

        // 4. Child UILabel or accessibility text if view is a container
        if extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let label = respondingView as? UILabel {
                extractedText = label.text ?? label.attributedText?.string ?? ""
            } else if let subLabel = findFirstLabel(in: respondingView, maxDepth: 2) {
                extractedText = subLabel.text ?? subLabel.attributedText?.string ?? ""
            } else if let ax = extractAccessibilityText(from: respondingView) {
                extractedText = ax
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
            let inset = respondingView.bounds.insetBy(
                dx: min(12, respondingView.bounds.width * 0.15),
                dy: min(12, respondingView.bounds.height * 0.15)
            )
            rects = [inset.isEmpty ? respondingView.bounds : inset]
        }

        return TextProxy(
            readOnlyFallbackView: respondingView,
            initialText: extractedText,
            selectionRects: rects
        )
    }

    static func hasExtractableTextNearView(_ view: UIView?, windowPoint: CGPoint) -> Bool {
        guard let view else { return false }
        if extractFastTextNearView(view, windowPoint: windowPoint) != nil {
            return true
        }
        return false
    }

    static func extractTextNearPoint(
        _ windowPoint: CGPoint,
        in view: UIView?,
        fallbackCopyAction: Any?,
        completion: @escaping ((text: String, targetView: UIView, rectInTarget: CGRect)?) -> Void
    ) {
        guard let anchorView = view ?? keyNormalWindow() else {
            completion(nil)
            return
        }

        // 1. If anchorView itself is a standard text view with an active selection, prefer that
        if let proxy = TextProxy(delegatingView: anchorView),
           !proxy.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !proxy.isFetchingSelectedText
        {
            let rect = proxy.selectionRectsInView.first ?? anchorView.bounds
            completion((proxy.selectedText, anchorView, rect))
            return
        }

        // 2. Check WKWebView at point if touch is inside a WKWebView
        if let webView = findAncestorWebView(of: anchorView) {
            let ptInWeb = webView.convert(windowPoint, from: webView.window)
            let js = """
            (function(){
              var sel = window.getSelection ? window.getSelection().toString() : '';
              if (sel && sel.trim().length > 0) return sel;
              var el = document.elementFromPoint(\(ptInWeb.x), \(ptInWeb.y));
              while (el && (!el.innerText || el.innerText.trim().length === 0)) { el = el.parentElement; }
              return el ? (el.innerText || '') : '';
            })();
            """
            webView.evaluateJavaScript(js) { res, _ in
                if let str = res as? String, !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let box = CGRect(x: max(0, ptInWeb.x - 40), y: max(0, ptInWeb.y - 18), width: 80, height: 36)
                    completion((str, webView, box.intersection(webView.bounds)))
                    return
                }
                finishNativeOrCopyExtraction(anchorView: anchorView, windowPoint: windowPoint, fallbackCopyAction: fallbackCopyAction, completion: completion)
            }
            return
        }

        finishNativeOrCopyExtraction(
            anchorView: anchorView,
            windowPoint: windowPoint,
            fallbackCopyAction: fallbackCopyAction,
            completion: completion
        )
    }

    private static func finishNativeOrCopyExtraction(
        anchorView: UIView,
        windowPoint: CGPoint,
        fallbackCopyAction: Any?,
        completion: @escaping ((text: String, targetView: UIView, rectInTarget: CGRect)?) -> Void
    ) {
        // 3. Direct view-tree & accessibility inspection near touch point FIRST (avoids touching UIPasteboard on iOS 16+)
        if let hit = extractFastTextNearView(anchorView, windowPoint: windowPoint) {
            completion(hit)
            return
        }

        // 4. Safe native copy action when direct view inspection couldn't find text
        if let fallbackCopyAction,
           let copied = extractViaCopyMenuElement(fallbackCopyAction, targetView: anchorView),
           !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            let rect = anchorRectForPoint(windowPoint, in: anchorView)
            completion((copied, anchorView, rect))
            return
        }

        // 5. Fallback via standard copy: on anchorView
        if anchorView.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil),
           let copied = extractViaTemporaryCopy(from: anchorView),
           !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            completion((copied, anchorView, anchorRectForPoint(windowPoint, in: anchorView)))
            return
        }

        completion(nil)
    }

    private static func extractFastTextNearView(_ view: UIView, windowPoint: CGPoint) -> (text: String, targetView: UIView, rectInTarget: CGRect)? {
        if let pdf = extractPDFSelectionText(near: view) {
            return (pdf, view, view.bounds)
        }

        if let direct = extractSafeTextProperty(from: view),
           !isSecureTextView(view)
        {
            return (direct, view, view.bounds)
        }

        // Look at subviews of view (or enclosing cell/container) containing windowPoint
        let container = enclosingCellOrContainer(for: view) ?? view
        var candidates: [(text: String, view: UIView, area: CGFloat)] = []
        collectReadableTextViews(in: container, depth: 0, maxDepth: 5, into: &candidates)

        if let window = container.window {
            // Prefer a subview directly under windowPoint
            let hitDirect = candidates.filter { cand in
                let rectInWin = cand.view.convert(cand.view.bounds, to: window)
                return rectInWin.insetBy(dx: -12, dy: -12).contains(windowPoint)
            }
            if let best = hitDirect.sorted(by: { $0.text.count > $1.text.count }).first {
                return (best.text, best.view, best.view.bounds)
            }
        }

        if let longest = candidates.sorted(by: { $0.text.count > $1.text.count }).first {
            return (longest.text, longest.view, longest.view.bounds)
        }

        if let ax = extractAccessibilityText(from: container) {
            return (ax, container, container.bounds)
        }

        return nil
    }

    private static func collectReadableTextViews(
        in view: UIView,
        depth: Int,
        maxDepth: Int,
        into list: inout [(text: String, view: UIView, area: CGFloat)]
    ) {
        guard depth <= maxDepth, !view.isHidden, view.alpha > 0.05 else { return }
        if isSecureTextView(view) { return }

        if let direct = extractSafeTextProperty(from: view) {
            let area = view.bounds.width * view.bounds.height
            list.append((direct, view, area))
        } else if let ax = extractAccessibilityText(from: view), view.subviews.isEmpty {
            let area = view.bounds.width * view.bounds.height
            list.append((ax, view, area))
        }

        for sub in view.subviews {
            collectReadableTextViews(in: sub, depth: depth + 1, maxDepth: maxDepth, into: &list)
        }
    }

    private static func enclosingCellOrContainer(for view: UIView) -> UIView? {
        var cursor: UIView? = view
        for _ in 0 ..< 5 {
            guard let cur = cursor else { break }
            if cur is UITableViewCell || cur is UICollectionViewCell {
                return cur
            }
            let cls = NSStringFromClass(type(of: cur))
            if cls.contains("Cell") || cls.contains("Bubble") || cls.contains("Message") {
                return cur
            }
            cursor = cur.superview
        }
        return view.superview ?? view
    }

    private static func anchorRectForPoint(_ windowPoint: CGPoint, in view: UIView) -> CGRect {
        guard let window = view.window else { return view.bounds }
        let pt = view.convert(windowPoint, from: window)
        let candidate = CGRect(x: pt.x - 40, y: pt.y - 20, width: 80, height: 40).intersection(view.bounds)
        return candidate.isEmpty ? view.bounds : candidate
    }

    private static func findAncestorWebView(of view: UIView) -> WKWebView? {
        var cursor: UIView? = view
        for _ in 0 ..< 6 {
            if let web = cursor as? WKWebView { return web }
            cursor = cursor?.superview
        }
        return nil
    }

    private static func keyNormalWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow && $0.windowLevel == .normal }
    }

    private static func isSecureTextView(_ view: UIView) -> Bool {
        if let tf = view as? UITextField, tf.isSecureTextEntry { return true }
        if let tv = view as? UITextView, tv.isSecureTextEntry { return true }
        return false
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

    private static func extractAccessibilityText(from view: UIView) -> String? {
        if let val = view.accessibilityValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           val.count >= 2
        {
            return val
        }
        if let lbl = view.accessibilityLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           lbl.count >= 2
        {
            return lbl
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

    static func extractViaCopyMenuElement(_ element: Any, targetView: UIView) -> String? {
        let pasteboard = UIPasteboard.general
        let savedItems = pasteboard.items
        let previousChangeCount = pasteboard.changeCount

        if let action = element as? UIAction {
            let performSel = NSSelectorFromString("performWithSender:target:")
            if action.responds(to: performSel) {
                _ = action.perform(performSel, with: nil, with: targetView)
            }
        } else if let cmd = element as? UICommand {
            UIApplication.shared.sendAction(cmd.action, to: targetView, from: nil, for: nil)
        }

        if pasteboard.changeCount != previousChangeCount {
            let copied = pasteboard.string
            pasteboard.items = savedItems
            return copied
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
