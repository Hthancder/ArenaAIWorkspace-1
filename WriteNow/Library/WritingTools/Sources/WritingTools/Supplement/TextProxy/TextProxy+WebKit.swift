//
//  TextProxy+WebKit.swift
//  WritingTools
//
//  Created by Lessica on 2024/8/22.
//

import WebKit

import WritingToolsInjector

extension WKContentView: TextProxyObject {
    var _isReadOnly: Bool { !isFocusingElement() }
    var _eligibleForWritingTool: Bool {
        if isFocusingElement() && isUserInteractionEnabled {
            return true
        }
        guard Configurator.shared.settings.readOnlyEnabled, isUserInteractionEnabled else {
            return false
        }
        return !(selectedTextRange?.isEmpty ?? true) || !_selectedText().isEmpty
    }
    var _appearanceForWritingTool: TextProxy.WTAppearance {
        .init(magicColorBehavior: .overText)
    }

    func _selectAll() { selectAll(nil) }
    func _selectedText() -> String { text(in: _selectedRange()) ?? "" }
    func _selectedTextAttribute() -> TextAttribute { textStyling(at: _selectedRange().start, in: .forward) ?? [:] }
    func _selectedRange() -> UITextRange { selectedTextRange ?? .init() }

    var _requiresAsynconousSelectedTextFetching: Bool { true }

    private func findAncestorWKWebView() -> WKWebView? {
        var cursor: UIView? = superview
        while let view = cursor {
            if let webView = view as? WKWebView {
                return webView
            }
            cursor = view.superview
        }
        return nil
    }

    // WebKit trims synchronous text(in:) to 200 chars and may require async JS / SpeakSelection
    func _fetchSelectedText(_ onCompletion: @escaping (String) -> Void) {
        let syncSelectedText = _selectedText()
        if !isFocusingElement(), let webView = findAncestorWKWebView() {
            webView.evaluateJavaScript("window.getSelection ? String(window.getSelection().toString()) : ''") { [weak self] result, _ in
                if let jsText = result as? String, !jsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onCompletion(jsText)
                    return
                }
                self?.fallbackSpeakSelectionFetch(syncSelectedText: syncSelectedText, onCompletion: onCompletion)
            }
            return
        }

        if syncSelectedText.count < 200, !syncSelectedText.isEmpty {
            onCompletion(syncSelectedText)
            return
        }
        fallbackSpeakSelectionFetch(syncSelectedText: syncSelectedText, onCompletion: onCompletion)
    }

    private func fallbackSpeakSelectionFetch(syncSelectedText: String, onCompletion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            if responds(to: #selector(accessibilityRetrieveSpeakSelectionContent)),
               responds(to: #selector(accessibilitySpeakSelectionSetContent(_:)))
            {
                wn_isGettingSelectedTextSemaphore = DispatchSemaphore(value: 0)
                accessibilityRetrieveSpeakSelectionContent()
                let waited = wn_isGettingSelectedTextSemaphore?.wait(timeout: .now() + 1.0)
                wn_isGettingSelectedTextSemaphore = nil

                if waited == .timedOut {
                    onCompletion(syncSelectedText)
                } else {
                    let resolved = wn_selectedText ?? syncSelectedText
                    onCompletion(resolved.isEmpty ? syncSelectedText : resolved)
                }
            } else {
                onCompletion(syncSelectedText)
            }
        }
    }

    private func findCompositingView(fromView view: UIView) -> UIView? {
        guard let classObject = NSClassFromString("WKCompositingView") else {
            return nil
        }
        if view.isKind(of: classObject) {
            return view
        }
        for subview in view.subviews {
            if let result = findCompositingView(fromView: subview) {
                return result
            }
        }
        return nil
    }

    func _selectionRectsInView() -> [CGRect] {
        guard let selectedTextRange else { return [] }
        return _selectionRectsInView(for: selectedTextRange)
    }

    func _selectionRectsInView(for range: UITextRange) -> [CGRect] {
        var ans = selectionRects(for: range).map(\.rect)
        if let compositingView = findCompositingView(fromView: self) {
            ans = ans.map { compositingView.convert($0, to: self) }
        }
        return ans
    }

    func _replaceText(with text: String, atRange range: UITextRange, attribute _: TextAttribute) -> UITextRange? {
        guard !_isReadOnly else { return nil }
        if !isFirstResponder {
            _ = becomeFirstResponder()
        }
        selectedTextRange = range
        insertText(text)
        let utf16Length = text.utf16.count
        guard let endPos = position(from: range.start, offset: utf16Length) else {
            return nil
        }
        return textRange(from: range.start, to: endPos)
    }
}
