//
//  InPlaceTextReplacementManager.swift
//  WritingTools
//

import UIKit
import WebKit

struct InPlaceReplacementRequest {
    let frameInWindow: CGRect
    let originalText: String
    let replacedText: String
    weak var targetView: UIView?
    let selectedNSRange: NSRange?

    init(
        frameInWindow: CGRect,
        originalText: String,
        replacedText: String,
        targetView: UIView? = nil,
        selectedNSRange: NSRange? = nil
    ) {
        self.frameInWindow = frameInWindow
        self.originalText = originalText
        self.replacedText = replacedText
        self.targetView = targetView
        self.selectedNSRange = selectedNSRange
    }
}

struct InPlaceReplacementEntry {
    let id = UUID()
    let frameInWindow: CGRect
    let originalText: String
    var replacedText: String
    let backgroundColor: UIColor
    let textColor: UIColor
    var showingOriginal: Bool = false
}

private protocol NativeReplacedRecord: AnyObject {
    var recordID: String { get }
    var originalText: String { get }
    var replacedText: String { get }
    func setShowingOriginal(_ showOriginal: Bool)
    func revert()
}

private final class NativeLabelRecord: NativeReplacedRecord {
    let recordID = UUID().uuidString
    weak var label: UILabel?
    let originalText: String
    let replacedText: String
    private let origText: String?
    private let origAttr: NSAttributedString?
    private let origLines: Int
    private let origLineBreak: NSLineBreakMode
    private let newAttr: NSAttributedString?

    init?(label: UILabel, originalText: String, replacedText: String) {
        self.label = label
        self.originalText = originalText
        self.replacedText = replacedText
        self.origText = label.text
        self.origAttr = label.attributedText?.copy() as? NSAttributedString
        self.origLines = label.numberOfLines
        self.origLineBreak = label.lineBreakMode

        if let origAttr, origAttr.length > 0 {
            let attrs = origAttr.attributes(at: 0, effectiveRange: nil)
            self.newAttr = NSAttributedString(string: replacedText, attributes: attrs)
        } else {
            self.newAttr = nil
        }

        applyReplaced()
    }

    private func applyReplaced() {
        guard let label else { return }
        if origLines == 1, replacedText.count > max(24, (origText?.count ?? 0) + 8) {
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
        }
        if let newAttr {
            label.attributedText = newAttr
        } else {
            label.text = replacedText
        }
        refreshLayout(for: label)
        pulseHighlight(on: label)
    }

    func setShowingOriginal(_ showOriginal: Bool) {
        guard let label else { return }
        if showOriginal {
            label.numberOfLines = origLines
            label.lineBreakMode = origLineBreak
            if let origAttr {
                label.attributedText = origAttr
            } else {
                label.text = origText
            }
        } else {
            if origLines == 1, replacedText.count > max(24, (origText?.count ?? 0) + 8) {
                label.numberOfLines = 0
                label.lineBreakMode = .byWordWrapping
            }
            if let newAttr {
                label.attributedText = newAttr
            } else {
                label.text = replacedText
            }
        }
        refreshLayout(for: label)
    }

    func revert() {
        setShowingOriginal(true)
    }

    private func refreshLayout(for label: UILabel) {
        label.invalidateIntrinsicContentSize()
        label.setNeedsLayout()
        label.superview?.setNeedsLayout()
        label.superview?.superview?.setNeedsLayout()
    }

    private func pulseHighlight(on view: UIView) {
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = UIColor.systemCyan.withAlphaComponent(0.22)
        flash.layer.cornerRadius = 6
        flash.isUserInteractionEnabled = false
        flash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(flash)
        UIView.animate(withDuration: 0.55, delay: 0.08, options: [.curveEaseOut]) {
            flash.alpha = 0
        } completion: { _ in
            flash.removeFromSuperview()
        }
    }
}

private final class NativeTextViewRecord: NativeReplacedRecord {
    let recordID = UUID().uuidString
    weak var textView: UITextView?
    let originalText: String
    let replacedText: String
    private let origAttr: NSAttributedString
    private let origText: String
    private let targetRange: NSRange
    private let replacedAttr: NSAttributedString

    init?(textView: UITextView, selectedNSRange: NSRange?, originalText: String, replacedText: String) {
        self.textView = textView
        self.originalText = originalText
        self.replacedText = replacedText
        let currentText = textView.text ?? ""
        self.origText = currentText
        self.origAttr = (textView.attributedText?.copy() as? NSAttributedString) ?? NSAttributedString(string: currentText)

        let fullLen = origAttr.length
        let resolvedRange: NSRange
        if let sel = selectedNSRange,
           sel.location != NSNotFound,
           sel.length > 0,
           sel.location + sel.length <= fullLen
        {
            resolvedRange = sel
        } else if let nsRange = (currentText as NSString).range(of: originalText) as NSRange?,
                  nsRange.location != NSNotFound,
                  nsRange.length > 0,
                  nsRange.location + nsRange.length <= fullLen
        {
            resolvedRange = nsRange
        } else {
            resolvedRange = NSRange(location: 0, length: fullLen)
        }
        self.targetRange = resolvedRange

        let mutable = NSMutableAttributedString(attributedString: origAttr)
        let attrs: [NSAttributedString.Key: Any]
        if resolvedRange.location < origAttr.length {
            attrs = origAttr.attributes(at: resolvedRange.location, effectiveRange: nil)
        } else if let font = textView.font {
            var base: [NSAttributedString.Key: Any] = [.font: font]
            if let col = textView.textColor { base[.foregroundColor] = col }
            attrs = base
        } else {
            attrs = [:]
        }
        mutable.replaceCharacters(in: resolvedRange, with: NSAttributedString(string: replacedText, attributes: attrs))
        self.replacedAttr = mutable

        applyReplaced()
    }

    private func applyReplaced() {
        guard let textView else { return }
        textView.attributedText = replacedAttr
        textView.invalidateIntrinsicContentSize()
        textView.setNeedsLayout()
        let flash = UIView(frame: textView.bounds)
        flash.backgroundColor = UIColor.systemCyan.withAlphaComponent(0.18)
        flash.layer.cornerRadius = 6
        flash.isUserInteractionEnabled = false
        flash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textView.addSubview(flash)
        UIView.animate(withDuration: 0.55, delay: 0.08, options: [.curveEaseOut]) {
            flash.alpha = 0
        } completion: { _ in
            flash.removeFromSuperview()
        }
    }

    func setShowingOriginal(_ showOriginal: Bool) {
        guard let textView else { return }
        textView.attributedText = showOriginal ? origAttr : replacedAttr
        textView.invalidateIntrinsicContentSize()
        textView.setNeedsLayout()
    }

    func revert() {
        setShowingOriginal(true)
    }
}

private final class NativeWebViewRecord: NativeReplacedRecord {
    let recordID: String
    weak var webView: WKWebView?
    let originalText: String
    let replacedText: String

    init(recordID: String, webView: WKWebView, originalText: String, replacedText: String) {
        self.recordID = recordID
        self.webView = webView
        self.originalText = originalText
        self.replacedText = replacedText
    }

    func setShowingOriginal(_ showOriginal: Bool) {
        guard let webView else { return }
        let safeID = Self.jsEscape(recordID)
        let flag = showOriginal ? "true" : "false"
        let js = "window.__omniaiSetRecordState && window.__omniaiSetRecordState('\(safeID)', \(flag));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func revert() {
        guard let webView else { return }
        let safeID = Self.jsEscape(recordID)
        let js = "window.__omniaiRevertRecord && window.__omniaiRevertRecord('\(safeID)');"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    static func jsEscape(_ str: String) -> String {
        str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

final class InPlaceTextReplacementManager: NSObject {
    static let shared = InPlaceTextReplacementManager()

    private var overlayWindow: InPlaceReplacementWindow?
    private weak var rootController: InPlaceReplacementViewController?
    private var nativeRecords: [NativeReplacedRecord] = []

    override private init() {
        super.init()
    }

    var isShowingOverlay: Bool {
        !nativeRecords.isEmpty || (overlayWindow != nil && !(overlayWindow?.isHidden ?? true))
    }

    func showReplacements(
        entries: [(frameInWindow: CGRect, originalText: String, replacedText: String)],
        in sourceWindow: UIWindow,
        snapshot: UIImage? = nil
    ) {
        let requests = entries.map {
            InPlaceReplacementRequest(
                frameInWindow: $0.frameInWindow,
                originalText: $0.originalText,
                replacedText: $0.replacedText,
                targetView: nil,
                selectedNSRange: nil
            )
        }
        applyReplacements(requests: requests, in: sourceWindow, snapshot: snapshot)
    }

    func applyReplacements(
        requests: [InPlaceReplacementRequest],
        in sourceWindow: UIWindow,
        snapshot: UIImage? = nil
    ) {
        let nonEmpty = requests.filter { !$0.replacedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmpty.isEmpty else { return }

        var remainingForWebOrOverlay: [InPlaceReplacementRequest] = []
        var newNativeRecords: [NativeReplacedRecord] = []

        for req in nonEmpty {
            let trimmedNew = req.replacedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let tv = req.targetView {
                if let label = resolveMatchingLabel(from: tv, originalText: req.originalText),
                   let rec = NativeLabelRecord(label: label, originalText: req.originalText, replacedText: trimmedNew)
                {
                    newNativeRecords.append(rec)
                    continue
                }
                if let textView = tv as? UITextView, !textView.isEditable,
                   let rec = NativeTextViewRecord(
                       textView: textView,
                       selectedNSRange: req.selectedNSRange,
                       originalText: req.originalText,
                       replacedText: trimmedNew
                   )
                {
                    newNativeRecords.append(rec)
                    continue
                }
            }
            remainingForWebOrOverlay.append(req)
        }

        if remainingForWebOrOverlay.isEmpty {
            nativeRecords.append(contentsOf: newNativeRecords)
            presentOrUpdateHostController(entries: [], nativeRecords: nativeRecords, in: sourceWindow)
            return
        }

        // Try WKWebView DOM replacement for any items originating from or matching a visible WKWebView
        let candidateWebViews = findWebViews(in: sourceWindow, preferring: remainingForWebOrOverlay.compactMap(\.targetView))
        if !candidateWebViews.isEmpty {
            attemptWebViewNativeReplacements(
                requests: remainingForWebOrOverlay,
                webViews: candidateWebViews
            ) { [weak self] webRecords, fallbackOverlayRequests in
                guard let self else { return }
                newNativeRecords.append(contentsOf: webRecords)
                self.nativeRecords.append(contentsOf: newNativeRecords)
                let overlayEntries = self.buildOverlayEntries(
                    from: fallbackOverlayRequests,
                    in: sourceWindow,
                    snapshot: snapshot
                )
                guard !overlayEntries.isEmpty || !self.nativeRecords.isEmpty else { return }
                self.presentOrUpdateHostController(
                    entries: overlayEntries,
                    nativeRecords: self.nativeRecords,
                    in: sourceWindow
                )
            }
            return
        }

        // Try matching visible UILabels / UITextViews by text+frame even when request came from OCR/ReadOnly without direct UILabel targetView
        var stillUnresolved: [InPlaceReplacementRequest] = []
        for req in remainingForWebOrOverlay {
            let trimmedNew = req.replacedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let matchedLabel = findLabelInWindow(sourceWindow, matchingText: req.originalText, near: req.frameInWindow),
               let rec = NativeLabelRecord(label: matchedLabel, originalText: req.originalText, replacedText: trimmedNew)
            {
                newNativeRecords.append(rec)
            } else if let matchedTV = findReadOnlyTextViewInWindow(sourceWindow, matchingText: req.originalText, near: req.frameInWindow),
                      let rec = NativeTextViewRecord(textView: matchedTV, selectedNSRange: nil, originalText: req.originalText, replacedText: trimmedNew)
            {
                newNativeRecords.append(rec)
            } else {
                stillUnresolved.append(req)
            }
        }

        nativeRecords.append(contentsOf: newNativeRecords)
        let overlayEntries = buildOverlayEntries(from: stillUnresolved, in: sourceWindow, snapshot: snapshot)
        guard !overlayEntries.isEmpty || !nativeRecords.isEmpty else { return }
        presentOrUpdateHostController(entries: overlayEntries, nativeRecords: nativeRecords, in: sourceWindow)
    }

    func clearAll() {
        for rec in nativeRecords {
            rec.revert()
        }
        nativeRecords.removeAll()
        overlayWindow?.isHidden = true
        overlayWindow?.rootViewController = nil
        overlayWindow = nil
        rootController = nil
    }

    fileprivate func setNativeRecordsShowingOriginal(_ showOriginal: Bool) {
        for rec in nativeRecords {
            rec.setShowingOriginal(showOriginal)
        }
    }

    fileprivate func collectAllDisplayTexts(showingOriginal: Bool) -> [String] {
        nativeRecords.map { showingOriginal ? $0.originalText : $0.replacedText }
    }

    private func presentOrUpdateHostController(
        entries: [InPlaceReplacementEntry],
        nativeRecords: [NativeReplacedRecord],
        in sourceWindow: UIWindow
    ) {
        if let existingVC = rootController, let win = overlayWindow, !win.isHidden {
            existingVC.appendOrUpdate(entries: entries, hasNativeRecords: !nativeRecords.isEmpty)
            return
        }

        let vc = InPlaceReplacementViewController(
            sourceWindow: sourceWindow,
            entries: entries,
            hasNativeRecords: !nativeRecords.isEmpty
        )
        vc.onToggleNativeOriginal = { [weak self] showOriginal in
            self?.setNativeRecordsShowingOriginal(showOriginal)
        }
        vc.onCollectNativeTexts = { [weak self] showOriginal in
            self?.collectAllDisplayTexts(showingOriginal: showOriginal) ?? []
        }
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

    private func buildOverlayEntries(
        from requests: [InPlaceReplacementRequest],
        in sourceWindow: UIWindow,
        snapshot: UIImage?
    ) -> [InPlaceReplacementEntry] {
        guard !requests.isEmpty else { return [] }
        let resolvedSnap = snapshot ?? ScreenTextScanner.captureSnapshot(of: sourceWindow)
        return requests.compactMap { item in
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
    }

    // MARK: - Native UILabel / UITextView Helpers

    private func resolveMatchingLabel(from view: UIView, originalText: String) -> UILabel? {
        if let label = view as? UILabel {
            let txt = (label.text ?? label.attributedText?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.textsMatchLoosely(txt, originalText) {
                return label
            }
        }
        // Check direct subviews up to depth 3 in case targetView was a cell/bubble wrapper
        let normTarget = Self.normalizeText(originalText)
        guard !normTarget.isEmpty else { return nil }
        var hits: [UILabel] = []
        collectLabels(in: view, depth: 0, maxDepth: 3, into: &hits)
        return hits.first { label in
            let txt = (label.text ?? label.attributedText?.string ?? "")
            return Self.textsMatchLoosely(txt, normTarget)
        }
    }

    private func findLabelInWindow(_ window: UIWindow, matchingText originalText: String, near rect: CGRect) -> UILabel? {
        let normTarget = Self.normalizeText(originalText)
        guard normTarget.count >= 2 else { return nil }
        var labels: [UILabel] = []
        collectLabels(in: window, depth: 0, maxDepth: 14, into: &labels)
        return labels.first { label in
            guard !label.isHidden, label.alpha > 0.05 else { return false }
            let txt = (label.text ?? label.attributedText?.string ?? "")
            guard Self.textsMatchLoosely(txt, normTarget) else { return false }
            let winRect = label.convert(label.bounds, to: window)
            if rect.width <= 4 || rect.height <= 4 { return true }
            return winRect.insetBy(dx: -24, dy: -24).intersects(rect)
        }
    }

    private func findReadOnlyTextViewInWindow(_ window: UIWindow, matchingText originalText: String, near rect: CGRect) -> UITextView? {
        let normTarget = Self.normalizeText(originalText)
        guard normTarget.count >= 2 else { return nil }
        var tvs: [UITextView] = []
        collectReadOnlyTextViews(in: window, depth: 0, maxDepth: 14, into: &tvs)
        return tvs.first { tv in
            let txt = tv.text ?? tv.attributedText?.string ?? ""
            let normTV = Self.normalizeText(txt)
            guard !normTV.isEmpty else { return false }
            let matches = Self.textsMatchLoosely(normTV, normTarget) || normTV.contains(normTarget)
            guard matches else { return false }
            let winRect = tv.convert(tv.bounds, to: window)
            if rect.width <= 4 || rect.height <= 4 { return true }
            return winRect.insetBy(dx: -24, dy: -24).intersects(rect)
        }
    }

    private func collectLabels(in view: UIView, depth: Int, maxDepth: Int, into list: inout [UILabel]) {
        guard depth <= maxDepth, !view.isHidden, view.alpha > 0.05 else { return }
        let cls = NSStringFromClass(type(of: view))
        if cls.contains("WriteNow") || cls.contains("InPlaceReplacement") { return }
        if let label = view as? UILabel {
            list.append(label)
        }
        for sub in view.subviews {
            collectLabels(in: sub, depth: depth + 1, maxDepth: maxDepth, into: &list)
        }
    }

    private func collectReadOnlyTextViews(in view: UIView, depth: Int, maxDepth: Int, into list: inout [UITextView]) {
        guard depth <= maxDepth, !view.isHidden, view.alpha > 0.05 else { return }
        let cls = NSStringFromClass(type(of: view))
        if cls.contains("WriteNow") || cls.contains("InPlaceReplacement") { return }
        if let tv = view as? UITextView, !tv.isEditable, !tv.isSecureTextEntry {
            list.append(tv)
        }
        for sub in view.subviews {
            collectReadOnlyTextViews(in: sub, depth: depth + 1, maxDepth: maxDepth, into: &list)
        }
    }

    // MARK: - Native WKWebView DOM Helpers

    private func findWebViews(in window: UIWindow, preferring targetViews: [UIView]) -> [WKWebView] {
        var found: [WKWebView] = []
        for view in targetViews {
            var cursor: UIView? = view
            while let cur = cursor {
                if let web = cur as? WKWebView, !found.contains(where: { $0 === web }) {
                    found.append(web)
                    break
                }
                cursor = cur.superview
            }
        }
        collectWebViews(in: window, into: &found)
        return found
    }

    private func collectWebViews(in view: UIView, into list: inout [WKWebView]) {
        guard !view.isHidden, view.alpha > 0.05 else { return }
        if let web = view as? WKWebView {
            if !list.contains(where: { $0 === web }) { list.append(web) }
            return
        }
        for sub in view.subviews {
            collectWebViews(in: sub, into: &list)
        }
    }

    private func attemptWebViewNativeReplacements(
        requests: [InPlaceReplacementRequest],
        webViews: [WKWebView],
        completion: @escaping ([NativeReplacedRecord], [InPlaceReplacementRequest]) -> Void
    ) {
        guard let primaryWebView = webViews.first else {
            completion([], requests)
            return
        }

        let indexedPayloads: [(idx: Int, id: String, orig: String, rep: String)] = requests.enumerated().map { idx, req in
            (idx, UUID().uuidString, req.originalText, req.replacedText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let jsonItems: [[String: String]] = indexedPayloads.map {
            ["id": $0.id, "orig": $0.orig, "rep": $0.rep]
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonItems, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            completion([], requests)
            return
        }

        let js = """
        (function(){
          window.__omniaiRecords = window.__omniaiRecords || {};
          window.__omniaiSetRecordState = function(id, showOriginal) {
            var rec = window.__omniaiRecords[id];
            if (!rec) return;
            var el = document.querySelector('[data-omniai-id="' + id + '"]');
            if (!el) return;
            if (showOriginal) {
              el.innerText = rec.orig;
              el.style.outline = '1px dashed rgba(140,140,140,0.45)';
            } else {
              el.innerText = rec.rep;
              el.style.outline = '';
            }
          };
          window.__omniaiRevertRecord = function(id) {
            var rec = window.__omniaiRecords[id];
            if (!rec) return;
            var el = document.querySelector('[data-omniai-id="' + id + '"]');
            if (el) {
              if (rec.wrapped && el.parentNode) {
                var frag = document.createRange().createContextualFragment(rec.origHTML);
                el.parentNode.replaceChild(frag, el);
              } else {
                el.innerHTML = rec.origHTML;
                el.removeAttribute('data-omniai-id');
                el.style.outline = '';
              }
            }
            delete window.__omniaiRecords[id];
          };
          function norm(s) {
            return (s || '').replace(/\\s+/g, ' ').trim();
          }
          function findBestElement(origText) {
            var target = norm(origText);
            if (!target || target.length < 2) return null;
            var candidates = document.querySelectorAll('p,h1,h2,h3,h4,h5,h6,li,blockquote,pre,td,th,a,span,div');
            var bestEl = null;
            var bestScore = 1e9;
            for (var i = 0; i < candidates.length; i++) {
              var el = candidates[i];
              if (el.hasAttribute('data-omniai-id')) continue;
              var t = norm(el.innerText || el.textContent || '');
              if (!t) continue;
              if (t === target) {
                if (el.children.length === 0) return el;
                if (t.length < bestScore) { bestScore = t.length; bestEl = el; }
              }
            }
            if (bestEl) return bestEl;
            for (var j = 0; j < candidates.length; j++) {
              var el2 = candidates[j];
              if (el2.hasAttribute('data-omniai-id')) continue;
              var t2 = norm(el2.innerText || el2.textContent || '');
              if (t2.length >= target.length && t2.indexOf(target) !== -1) {
                if (t2.length <= target.length * 1.65 && t2.length < bestScore) {
                  bestScore = t2.length;
                  bestEl = el2;
                }
              }
            }
            return bestEl;
          }
          var items = \(jsonString);
          var matchedIDs = [];
          for (var k = 0; k < items.length; k++) {
            var item = items[k];
            var targetNorm = norm(item.orig);
            var replaced = false;
            var sel = window.getSelection ? window.getSelection() : null;
            if (items.length === 1 && sel && sel.rangeCount > 0 && !sel.isCollapsed) {
              var selStr = norm(sel.toString());
              if (selStr && (selStr === targetNorm || selStr.indexOf(targetNorm) !== -1 || targetNorm.indexOf(selStr) !== -1)) {
                try {
                  var range = sel.getRangeAt(0);
                  var span = document.createElement('span');
                  span.setAttribute('data-omniai-id', item.id);
                  var extracted = range.extractContents();
                  var tmp = document.createElement('div');
                  tmp.appendChild(extracted);
                  window.__omniaiRecords[item.id] = { orig: item.orig, rep: item.rep, origHTML: tmp.innerHTML, wrapped: true };
                  span.innerText = item.rep;
                  range.insertNode(span);
                  sel.removeAllRanges();
                  matchedIDs.push(item.id);
                  replaced = true;
                } catch (e) {}
              }
            }
            if (!replaced) {
              var el = findBestElement(item.orig);
              if (el) {
                window.__omniaiRecords[item.id] = { orig: (el.innerText || item.orig), rep: item.rep, origHTML: el.innerHTML, wrapped: false };
                el.setAttribute('data-omniai-id', item.id);
                el.innerText = item.rep;
                matchedIDs.push(item.id);
              }
            }
          }
          return matchedIDs;
        })();
        """

        primaryWebView.evaluateJavaScript(js) { res, _ in
            let matchedSet = Set((res as? [String]) ?? [])
            var webRecords: [NativeReplacedRecord] = []
            var fallback: [InPlaceReplacementRequest] = []
            for item in indexedPayloads {
                if matchedSet.contains(item.id) {
                    webRecords.append(
                        NativeWebViewRecord(
                            recordID: item.id,
                            webView: primaryWebView,
                            originalText: item.orig,
                            replacedText: item.rep
                        )
                    )
                } else {
                    fallback.append(requests[item.idx])
                }
            }
            completion(webRecords, fallback)
        }
    }

    private static func normalizeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func textsMatchLoosely(_ a: String, _ b: String) -> Bool {
        let na = normalizeText(a)
        let nb = normalizeText(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        return na == nb
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
            CGPoint(x: rect.minX + 2, y: rect.minY + 2),
            CGPoint(x: rect.midX, y: rect.minY + 2),
            CGPoint(x: rect.maxX - 2, y: rect.minY + 2),
            CGPoint(x: rect.minX + 2, y: rect.maxY - 2),
            CGPoint(x: rect.midX, y: rect.maxY - 2),
            CGPoint(x: rect.maxX - 2, y: rect.maxY - 2),
            CGPoint(x: rect.minX + 2, y: rect.midY),
            CGPoint(x: rect.maxX - 2, y: rect.midY),
            CGPoint(x: max(1, rect.minX - 2), y: rect.midY),
            CGPoint(x: min(windowBounds.width - 1, rect.maxX + 2), y: rect.midY),
            CGPoint(x: rect.midX, y: max(1, rect.minY - 2)),
            CGPoint(x: rect.midX, y: min(windowBounds.height - 1, rect.maxY + 2)),
        ]

        var rs: [CGFloat] = []
        var gs: [CGFloat] = []
        var bs: [CGFloat] = []

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
            rs.append(CGFloat(pixel[0]) / 255.0)
            gs.append(CGFloat(pixel[1]) / 255.0)
            bs.append(CGFloat(pixel[2]) / 255.0)
        }

        guard !rs.isEmpty else {
            return (UIColor.black.withAlphaComponent(0.90), .white)
        }
        rs.sort()
        gs.sort()
        bs.sort()
        let mid = rs.count / 2
        let r = rs[mid]
        let g = gs[mid]
        let b = bs[mid]
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b

        let bg = UIColor(red: r, green: g, blue: b, alpha: 0.98)
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
    private var hasNativeRecords: Bool
    private var cardViews: [UUID: InPlaceCardView] = [:]
    private var globalShowingOriginal = false

    private let toolbar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let modeBadge = UILabel()
    private let toggleAllButton = UIButton(type: .system)
    private let copyAllButton = UIButton(type: .system)
    private let closeAllButton = UIButton(type: .system)

    var onToggleNativeOriginal: ((Bool) -> Void)?
    var onCollectNativeTexts: ((Bool) -> [String])?
    var onDismissAll: (() -> Void)?

    init(sourceWindow: UIWindow, entries: [InPlaceReplacementEntry], hasNativeRecords: Bool) {
        self.sourceWindow = sourceWindow
        self.entries = entries
        self.hasNativeRecords = hasNativeRecords
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
        updateModeBadge()
    }

    func appendOrUpdate(entries newEntries: [InPlaceReplacementEntry], hasNativeRecords: Bool) {
        self.hasNativeRecords = self.hasNativeRecords || hasNativeRecords
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
        updateModeBadge()
        rebuildCards()
    }

    private func setupToolbar() {
        toolbar.layer.cornerRadius = 18
        toolbar.clipsToBounds = true
        toolbar.layer.borderWidth = 0.7
        toolbar.layer.borderColor = UIColor.systemCyan.withAlphaComponent(0.55).cgColor
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        modeBadge.font = .systemFont(ofSize: 9.5, weight: .bold)
        modeBadge.textColor = .systemCyan
        modeBadge.backgroundColor = UIColor.systemCyan.withAlphaComponent(0.16)
        modeBadge.layer.cornerRadius = 6
        modeBadge.clipsToBounds = true
        modeBadge.textAlignment = .center

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

        let stack = UIStackView(arrangedSubviews: [modeBadge, toggleAllButton, copyAllButton, closeAllButton])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            toolbar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            modeBadge.heightAnchor.constraint(equalToConstant: 18),
            stack.topAnchor.constraint(equalTo: toolbar.contentView.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: toolbar.contentView.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: toolbar.contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: toolbar.contentView.trailingAnchor, constant: -12),
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleToolbarPan(_:)))
        toolbar.addGestureRecognizer(pan)
    }

    private func updateModeBadge() {
        if hasNativeRecords && entries.isEmpty {
            modeBadge.text = " NATIVE "
            modeBadge.textColor = .systemGreen
            modeBadge.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.18)
        } else if hasNativeRecords {
            modeBadge.text = " MIXED "
            modeBadge.textColor = .systemCyan
            modeBadge.backgroundColor = UIColor.systemCyan.withAlphaComponent(0.18)
        } else {
            modeBadge.text = " OVERLAY "
            modeBadge.textColor = .systemCyan
            modeBadge.backgroundColor = UIColor.systemCyan.withAlphaComponent(0.16)
        }
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
            if self.entries.isEmpty && !self.hasNativeRecords {
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
        onToggleNativeOriginal?(globalShowingOriginal)
        updateToggleButtonTitle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func didTapCopyAll() {
        let nativeTexts = onCollectNativeTexts?(globalShowingOriginal) ?? []
        let overlayTexts = entries.map { $0.showingOriginal ? $0.originalText : $0.replacedText }
        let joined = (nativeTexts + overlayTexts).joined(separator: "\n\n")
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

        let minWidth = max(entry.frameInWindow.width, 100)
        let targetWidth = min(maxBounds.width - 16, minWidth)
        let originX = max(8, min(maxBounds.width - targetWidth - 8, entry.frameInWindow.origin.x))

        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = false
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 5, bottom: 4, right: 5)
        textView.textContainer.lineFragmentPadding = 0
        textView.font = Self.pickBestFont(for: entry.replacedText, fitting: CGSize(width: targetWidth, height: entry.frameInWindow.height))

        let measure = textView.sizeThatFits(CGSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude))
        let maxHeight = max(entry.frameInWindow.height, min(maxBounds.height * 0.48, ceil(measure.height) + 4))
        let originY = max(44, min(maxBounds.height - maxHeight - 40, entry.frameInWindow.origin.y))

        frame = CGRect(x: originX, y: originY, width: targetWidth, height: maxHeight)

        layer.cornerRadius = 6
        layer.borderWidth = 0.6
        clipsToBounds = true

        textView.frame = bounds
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textView.isScrollEnabled = measure.height > maxHeight + 2
        addSubview(textView)

        badgeLabel.font = .systemFont(ofSize: 8, weight: .bold)
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 3.5
        badgeLabel.clipsToBounds = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeLabel)
        NSLayoutConstraint.activate([
            badgeLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            badgeLabel.heightAnchor.constraint(equalToConstant: 12),
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
            backgroundColor = UIColor.black.withAlphaComponent(0.04)
            layer.borderColor = UIColor.systemGray.withAlphaComponent(0.42).cgColor
            textView.isHidden = true
            badgeLabel.text = " ORIG "
            badgeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
            badgeLabel.textColor = .white
        } else {
            backgroundColor = entry.backgroundColor
            layer.borderColor = entry.textColor.withAlphaComponent(0.18).cgColor
            textView.isHidden = false
            textView.text = entry.replacedText
            textView.textColor = entry.textColor
            badgeLabel.text = " AI "
            badgeLabel.backgroundColor = UIColor.systemCyan.withAlphaComponent(0.22)
            badgeLabel.textColor = entry.textColor.withAlphaComponent(0.75)
        }
    }

    private static func pickBestFont(for text: String, fitting size: CGSize) -> UIFont {
        for fontSize in stride(from: 14.5, through: 11.0, by: -1.0) {
            let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
            let rect = (text as NSString).boundingRect(
                with: CGSize(width: max(40, size.width - 10), height: .greatestFiniteMagnitude),
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
