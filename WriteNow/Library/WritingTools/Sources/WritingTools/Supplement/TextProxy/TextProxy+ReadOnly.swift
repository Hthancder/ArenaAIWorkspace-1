//
//  TextProxy+ReadOnly.swift
//  WritingTools
//

import UIKit
import WebKit

extension TextProxy {
    static func makeReadOnlyWithText(_ text: String, view: UIView, selectionRect: CGRect? = nil, allowEmpty: Bool = false) -> TextProxy? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowEmpty || !trimmed.isEmpty else { return nil }
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

        // 4. Safe native copy action when direct view inspection couldn't find text (supports async pasteboard updates)
        if let fallbackCopyAction {
            extractViaCopyMenuElementAsync(fallbackCopyAction, targetView: anchorView) { copied in
                if let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let rect = anchorRectForPoint(windowPoint, in: anchorView)
                    completion((copied, anchorView, rect))
                    return
                }
                finishTemporaryCopyOrNil(anchorView: anchorView, windowPoint: windowPoint, completion: completion)
            }
            return
        }

        finishTemporaryCopyOrNil(anchorView: anchorView, windowPoint: windowPoint, completion: completion)
    }

    private static func finishTemporaryCopyOrNil(
        anchorView: UIView,
        windowPoint: CGPoint,
        completion: @escaping ((text: String, targetView: UIView, rectInTarget: CGRect)?) -> Void
    ) {
        if let target = anchorView.target(forAction: #selector(UIResponderStandardEditActions.copy(_:)), withSender: nil) as? UIResponder,
           let copied = extractViaTemporaryCopy(from: anchorView, resolvedTarget: target),
           !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            completion((copied, anchorView, anchorRectForPoint(windowPoint, in: anchorView)))
            return
        }
        completion(nil)
    }

    static func extractTextViaOCRFallback(
        in window: UIWindow,
        near windowPoint: CGPoint,
        completion: @escaping ((text: String, rectInWindow: CGRect)?) -> Void
    ) {
        guard let snapshot = ScreenTextScanner.captureSnapshot(of: window) else {
            completion(nil)
            return
        }
        let region: CGRect?
        if windowPoint.x > 1 || windowPoint.y > 1 {
            let yStart = max(0, windowPoint.y - 240)
            let yEnd = min(window.bounds.height, windowPoint.y + 240)
            region = CGRect(x: 0, y: yStart, width: window.bounds.width, height: max(60, yEnd - yStart))
        } else {
            region = nil
        }

        ScreenTextScanner.recognizeText(
            in: snapshot,
            windowBounds: window.bounds,
            regionInWindow: region,
            preferredLanguages: Locale.preferredLanguages
        ) { blocks in
            let meaningful = blocks.filter {
                let t = $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.count >= 3 && t.rangeOfCharacter(from: .alphanumerics) != nil
            }
            guard !meaningful.isEmpty else {
                completion(nil)
                return
            }
            if windowPoint.x > 1 || windowPoint.y > 1 {
                if let direct = meaningful
                    .filter({ $0.rectInWindow.insetBy(dx: -16, dy: -16).contains(windowPoint) })
                    .sorted(by: { $0.text.count > $1.text.count })
                    .first
                {
                    completion((direct.text, direct.rectInWindow))
                    return
                }
                // Pick nearest substantial block to touch point
                let best = meaningful.min { lhs, rhs in
                    let dl = hypot(lhs.rectInWindow.midX - windowPoint.x, (lhs.rectInWindow.midY - windowPoint.y) * 1.4) - min(30, Double(lhs.text.count) * 0.25)
                    let dr = hypot(rhs.rectInWindow.midX - windowPoint.x, (rhs.rectInWindow.midY - windowPoint.y) * 1.4) - min(30, Double(rhs.text.count) * 0.25)
                    return dl < dr
                }
                if let best {
                    completion((best.text, best.rectInWindow))
                    return
                }
            }
            if let longest = meaningful.sorted(by: { $0.text.count > $1.text.count }).first {
                completion((longest.text, longest.rectInWindow))
            } else {
                completion(nil)
            }
        }
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

        // Look at subviews and accessibilityElements of view (or enclosing cell/container) containing windowPoint
        let container = enclosingCellOrContainer(for: view) ?? view
        var candidates: [(text: String, view: UIView, rectInWindow: CGRect)] = []
        collectReadableTextViews(in: container, depth: 0, maxDepth: 6, into: &candidates)

        if windowPoint.x > 1 || windowPoint.y > 1 {
            // Prefer a subview or accessibility element directly under windowPoint
            let hitDirect = candidates.filter { cand in
                !cand.rectInWindow.isEmpty && cand.rectInWindow.insetBy(dx: -14, dy: -14).contains(windowPoint)
            }
            if let best = hitDirect.sorted(by: { $0.text.count > $1.text.count }).first {
                let rectInTarget = container.window.map { best.view.convert(best.rectInWindow, from: $0) } ?? best.view.bounds
                return (best.text, best.view, rectInTarget.isEmpty ? best.view.bounds : rectInTarget)
            }
        }

        if let longest = candidates.sorted(by: { $0.text.count > $1.text.count }).first {
            let rectInTarget = container.window.map { longest.view.convert(longest.rectInWindow, from: $0) } ?? longest.view.bounds
            return (longest.text, longest.view, rectInTarget.isEmpty ? longest.view.bounds : rectInTarget)
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
        into list: inout [(text: String, view: UIView, rectInWindow: CGRect)]
    ) {
        guard depth <= maxDepth, !view.isHidden, view.alpha > 0.05 else { return }
        if isSecureTextView(view) { return }

        let rectInWin = view.window.map { view.convert(view.bounds, to: $0) } ?? view.bounds

        if let direct = extractSafeTextProperty(from: view) {
            list.append((direct, view, rectInWin))
        } else {
            let axCount = view.accessibilityElementCount()
            if axCount != NSNotFound && axCount > 0 {
                let cap = min(axCount, 40)
                for idx in 0 ..< cap {
                    guard let elem = view.accessibilityElement(at: idx) as? NSObject else { continue }
                    let val = elem.accessibilityValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let lbl = elem.accessibilityLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let chosen = val.count >= 3 ? val : (lbl.count >= 3 ? lbl : "")
                    guard !chosen.isEmpty else { continue }
                    let elemRect: CGRect
                    let axFrame = elem.accessibilityFrame
                    if !axFrame.isEmpty, let winScene = view.window?.windowScene, let win = view.window {
                        let converted = winScene.coordinateSpace.convert(axFrame, from: UIScreen.main.coordinateSpace)
                        let c = converted.intersection(win.bounds)
                        elemRect = c.isEmpty ? rectInWin : c
                    } else {
                        elemRect = rectInWin
                    }
                    list.append((chosen, view, elemRect))
                }
            }
            if let ax = extractAccessibilityText(from: view), (view.subviews.isEmpty || ax.count >= 12) {
                list.append((ax, view, rectInWin))
            }
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

        triggerCopyElement(element, targetView: targetView)

        if pasteboard.changeCount != previousChangeCount {
            let copied = pasteboard.string
            pasteboard.items = savedItems
            return copied
        }
        return nil
    }

    static func extractViaCopyMenuElementAsync(
        _ element: Any,
        targetView: UIView,
        completion: @escaping (String?) -> Void
    ) {
        let pasteboard = UIPasteboard.general
        let savedItems = pasteboard.items
        let previousChangeCount = pasteboard.changeCount

        triggerCopyElement(element, targetView: targetView)

        if pasteboard.changeCount != previousChangeCount {
            let copied = pasteboard.string
            pasteboard.items = savedItems
            completion(copied)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            if pasteboard.changeCount != previousChangeCount {
                let copied = pasteboard.string
                pasteboard.items = savedItems
                completion(copied)
            } else {
                completion(nil)
            }
        }
    }

    private static func triggerCopyElement(_ element: Any, targetView: UIView) {
        if let action = element as? UIAction {
            let performSel = NSSelectorFromString("performWithSender:target:")
            if action.responds(to: performSel) {
                _ = action.perform(performSel, with: nil, with: targetView)
            }
        } else if let cmd = element as? UICommand {
            let resolved = targetView.target(forAction: cmd.action, withSender: nil)
            if !UIApplication.shared.sendAction(cmd.action, to: resolved, from: targetView, for: nil) {
                UIApplication.shared.sendAction(cmd.action, to: nil, from: targetView, for: nil)
            }
        } else if let menuItem = element as? UIMenuItem {
            let resolved = targetView.target(forAction: menuItem.action, withSender: nil)
            if !UIApplication.shared.sendAction(menuItem.action, to: resolved, from: targetView, for: nil) {
                UIApplication.shared.sendAction(menuItem.action, to: nil, from: targetView, for: nil)
            }
        } else if let alertAction = element as? UIAlertAction {
            if let ivar = class_getInstanceVariable(UIAlertAction.self, "_handler"),
               let rawBlock = object_getIvar(alertAction, ivar)
            {
                typealias AlertHandler = @convention(block) (UIAlertAction) -> Void
                let block = unsafeBitCast(rawBlock as AnyObject, to: AlertHandler.self)
                block(alertAction)
            }
        } else if let control = element as? UIControl {
            control.sendActions(for: .touchUpInside)
        }
    }

    private static func extractViaTemporaryCopy(from view: UIView, resolvedTarget: UIResponder? = nil) -> String? {
        let pasteboard = UIPasteboard.general
        let savedItems = pasteboard.items
        let previousChangeCount = pasteboard.changeCount

        let target = resolvedTarget ?? view
        if !UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.copy(_:)), to: target, from: view, for: nil) {
            UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.copy(_:)), to: nil, from: view, for: nil)
        }

        var copied: String?
        if pasteboard.changeCount != previousChangeCount {
            copied = pasteboard.string
            pasteboard.items = savedItems
        }
        return copied
    }
}
