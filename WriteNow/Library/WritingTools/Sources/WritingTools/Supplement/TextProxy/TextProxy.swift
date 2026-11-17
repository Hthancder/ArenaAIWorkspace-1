//
//  TextProxy.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/8.
//

import Combine
import UIKit

typealias TextAttribute = [NSAttributedString.Key: Any]

class TextProxy: ObservableObject {
    let delegatingView: TextProxyObject?
    let fallbackTargetView: UIView?
    let isReadOnly: Bool

    var isEligibleForWritingTool: Bool {
        if let delegatingView {
            if delegatingView._isReadOnly {
                return Configurator.shared.settings.readOnlyEnabled
                    && delegatingView._eligibleForWritingTool
                    && (!selectedRange.isEmpty || !selectedText.isEmpty || isFetchingSelectedText)
            }
            return delegatingView._eligibleForWritingTool
        }
        return Configurator.shared.settings.readOnlyEnabled
            && !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var appearanceForWritingTool: WTAppearance {
        delegatingView?._appearanceForWritingTool ?? .init(magicColorBehavior: .overText)
    }

    @Published private(set) var selectedText: String = ""
    @Published private(set) var isFetchingSelectedText: Bool = false

    private(set) var selectedTextAttribute: TextAttribute = [:]
    private(set) var selectedRange: UITextRange = .init()
    private(set) var selectionRectsInView: [CGRect] = []
    private(set) var replacedRange: UITextRange = .init()

    init?(delegatingView: UIView) {
        guard let delegatingView = delegatingView as? TextProxyObject else {
            return nil
        }
        self.delegatingView = delegatingView
        self.fallbackTargetView = nil
        self.isReadOnly = delegatingView._isReadOnly
        frozenCurrentParameters()
        prepareSelectedTextAsynconously()
    }

    init(readOnlyFallbackView: UIView, initialText: String, selectionRects: [CGRect]) {
        self.delegatingView = nil
        self.fallbackTargetView = readOnlyFallbackView
        self.isReadOnly = true
        self.selectedText = initialText
        self.selectionRectsInView = selectionRects.isEmpty ? [readOnlyFallbackView.bounds] : selectionRects
    }

    func selectAll() {
        delegatingView?._selectAll()
        frozenCurrentParameters()
    }

    func frozenCurrentParameters() {
        guard let delegatingView else { return }
        selectedText = delegatingView._selectedText()
        selectedTextAttribute = delegatingView._selectedTextAttribute()
        selectedRange = delegatingView._selectedRange()
        selectionRectsInView = delegatingView._selectionRectsInView()
        replacedRange = selectedRange
    }

    func selectionRectsInView(for range: UITextRange) -> [CGRect] {
        delegatingView?._selectionRectsInView(for: range) ?? selectionRectsInView
    }

    var replacedSelectionRectsInView: [CGRect] {
        guard let delegatingView else { return selectionRectsInView }
        let rects = delegatingView._selectionRectsInView(for: replacedRange)
        return rects.isEmpty ? selectionRectsInView : rects
    }

    func replaceText(with text: String, atRange range: UITextRange, attribute: TextAttribute) {
        guard !isReadOnly, let delegatingView else { return }
        if let range = delegatingView._replaceText(with: text, atRange: range, attribute: attribute) {
            replacedRange = range
        }
    }

    func replaceText(with text: String) {
        replaceText(with: text, atRange: selectedRange, attribute: selectedTextAttribute)
    }

    func appendText(with text: String) {
        guard !isReadOnly else { return }
        let combined: String
        if selectedText.isEmpty {
            combined = text
        } else if selectedText.hasSuffix("\n") {
            combined = "\(selectedText)\(text)"
        } else {
            combined = "\(selectedText)\n\n\(text)"
        }
        replaceText(with: combined, atRange: selectedRange, attribute: selectedTextAttribute)
    }
}

extension TextProxy {
    struct WTAppearance {
        enum MagicColorBehavior {
            case behindText
            case overText
        }

        var magicColorBehavior: MagicColorBehavior

        init(magicColorBehavior: MagicColorBehavior) {
            self.magicColorBehavior = magicColorBehavior
        }
    }
}

extension TextProxy {
    private func prepareSelectedTextAsynconously() {
        guard let delegatingView else { return }
        if delegatingView._requiresAsynconousSelectedTextFetching {
            isFetchingSelectedText = true
            _prepareSelectedTextAsynconously()
        }
    }

    private func _prepareSelectedTextAsynconously() {
        delegatingView?._fetchSelectedText { [weak self] content in
            self?.__prepareSelectedTextAsynconously(content)
        }
    }

    private func __prepareSelectedTextAsynconously(_ content: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !content.isEmpty {
                self.selectedText = content
            }
            self.isFetchingSelectedText = false
        }
    }
}

protocol TextProxyObject: UIView, UITextInput {
    var _eligibleForWritingTool: Bool { get }
    var _isReadOnly: Bool { get }
    var _appearanceForWritingTool: TextProxy.WTAppearance { get }
    var _requiresAsynconousSelectedTextFetching: Bool { get }
    func _selectedText() -> String
    func _fetchSelectedText(_ onCompletion: @escaping (String) -> Void)
    func _selectedTextAttribute() -> TextAttribute
    func _selectedRange() -> UITextRange
    func _selectionRectsInView() -> [CGRect]
    func _selectionRectsInView(for range: UITextRange) -> [CGRect]
    func _replaceText(with text: String, atRange range: UITextRange, attribute: TextAttribute) -> UITextRange?
    func _selectAll()
}
