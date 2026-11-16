//
//  TextProxy+UITextField.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/20.
//

import UIKit

extension UITextField: TextProxyObject {
    var _eligibleForWritingTool: Bool { isUserInteractionEnabled }
    var _appearanceForWritingTool: TextProxy.WTAppearance {
        .init(magicColorBehavior: .behindText)
    }

    func _selectAll() { selectedTextRange = textRange(from: beginningOfDocument, to: endOfDocument) }
    func _selectedText() -> String { text(in: _selectedRange()) ?? "" }
    func _selectedTextAttribute() -> TextAttribute { textStyling(at: _selectedRange().start, in: .forward) ?? [:] }
    func _selectedRange() -> UITextRange { selectedTextRange ?? .init() }

    var _requiresAsynconousSelectedTextFetching: Bool { false }
    func _fetchSelectedText(_: @escaping (String) -> Void) {
        fatalError("Should not be called on UITextField.")
    }

    private func findTextLayoutCanvasView(fromView view: UIView) -> UIView? {
        guard let classObject = NSClassFromString("_UITextLayoutCanvasView") else {
            return nil
        }
        if view.isKind(of: classObject) {
            return view
        }
        for subview in view.subviews {
            if let result = findTextLayoutCanvasView(fromView: subview) {
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
        if let canvasView = findTextLayoutCanvasView(fromView: self) {
            ans = ans.map { canvasView.convert($0, to: self) }
        }
        return ans
    }

    func _replaceText(with text: String, atRange range: UITextRange, attribute: TextAttribute) -> UITextRange? {
        defer { selectedTextRange = nil }
        let utf16Length = text.utf16.count
        let startLocation = offset(from: beginningOfDocument, to: range.start)
        replace(range, withText: text)
        if let attributedText {
            let attributedString = NSMutableAttributedString(attributedString: attributedText)
            let nsRange = NSRange(
                location: startLocation,
                length: utf16Length
            )
            if nsRange.length > 0, nsRange.location >= 0, nsRange.location + nsRange.length <= attributedString.length {
                attributedString.addAttributes(attribute, range: nsRange)
                self.attributedText = attributedString
            }
        }
        guard let startPos = position(from: beginningOfDocument, offset: startLocation),
              let endPos = position(from: startPos, offset: utf16Length)
        else {
            return nil
        }
        return textRange(from: startPos, to: endPos)
    }
}
