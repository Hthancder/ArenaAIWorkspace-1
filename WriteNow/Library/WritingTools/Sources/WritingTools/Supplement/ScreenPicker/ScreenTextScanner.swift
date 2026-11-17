//
//  ScreenTextScanner.swift
//  WritingTools
//

import UIKit
import Vision
import WebKit

struct DetectedScreenTextBlock: Identifiable {
    enum SourceKind {
        case uiKit
        case webKit
        case accessibility
        case ocr
    }

    let id = UUID()
    let text: String
    let rectInWindow: CGRect
    weak var sourceView: UIView?
    let sourceKind: SourceKind
}

enum ScreenTextScanner {
    static func captureSnapshot(of window: UIWindow) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    static func scanVisibleText(in window: UIWindow, completion: @escaping ([DetectedScreenTextBlock]) -> Void) {
        var collected: [DetectedScreenTextBlock] = []
        var webViews: [WKWebView] = []

        traverse(view: window, in: window, blocks: &collected, webViews: &webViews)

        guard !webViews.isEmpty else {
            completion(deduplicateAndSort(collected))
            return
        }

        let group = DispatchGroup()
        var webBlocks: [DetectedScreenTextBlock] = []
        let lock = NSLock()

        for webView in webViews.prefix(4) {
            group.enter()
            scanWebView(webView, in: window) { blocks in
                lock.lock()
                webBlocks.append(contentsOf: blocks)
                lock.unlock()
                group.leave()
            }
        }

        var finished = false
        let timeoutWork = DispatchWorkItem {
            guard !finished else { return }
            finished = true
            lock.lock()
            let merged = collected + webBlocks
            lock.unlock()
            completion(deduplicateAndSort(merged))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: timeoutWork)

        group.notify(queue: .main) {
            guard !finished else { return }
            finished = true
            timeoutWork.cancel()
            lock.lock()
            let merged = collected + webBlocks
            lock.unlock()
            completion(deduplicateAndSort(merged))
        }
    }

    static func recognizeText(
        in image: UIImage,
        windowBounds: CGRect,
        regionInWindow: CGRect?,
        preferredLanguages: [String],
        completion: @escaping ([DetectedScreenTextBlock]) -> Void
    ) {
        guard let cgImage = image.cgImage else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let targetWindowRect: CGRect
        let cropCGImage: CGImage

        if let region = regionInWindow?.standardized,
           region.width >= 12,
           region.height >= 12
        {
            let clamped = region.intersection(windowBounds)
            guard !clamped.isEmpty else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            targetWindowRect = clamped
            let scaleX = CGFloat(cgImage.width) / max(1, windowBounds.width)
            let scaleY = CGFloat(cgImage.height) / max(1, windowBounds.height)
            let pixelRect = CGRect(
                x: clamped.minX * scaleX,
                y: clamped.minY * scaleY,
                width: clamped.width * scaleX,
                height: clamped.height * scaleY
            ).integral
            if let cropped = cgImage.cropping(to: pixelRect) {
                cropCGImage = cropped
            } else {
                cropCGImage = cgImage
            }
        } else {
            targetWindowRect = windowBounds
            cropCGImage = cgImage
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            if let supported = try? request.supportedRecognitionLanguages(), !supported.isEmpty {
                let filtered = preferredLanguages.filter { supported.contains($0) }
                if !filtered.isEmpty {
                    request.recognitionLanguages = filtered
                }
            }

            let handler = VNImageRequestHandler(cgImage: cropCGImage, options: [:])
            do {
                try handler.perform([request])
                let observations = request.results ?? []
                let blocks: [DetectedScreenTextBlock] = observations.compactMap { obs in
                    guard let top = obs.topCandidates(1).first else { return nil }
                    let text = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }
                    let bb = obs.boundingBox
                    // Vision normalized coords: origin bottom-left -> convert to top-left UIKit coords inside targetWindowRect
                    let rect = CGRect(
                        x: targetWindowRect.minX + bb.minX * targetWindowRect.width,
                        y: targetWindowRect.minY + (1.0 - bb.maxY) * targetWindowRect.height,
                        width: max(18, bb.width * targetWindowRect.width),
                        height: max(16, bb.height * targetWindowRect.height)
                    )
                    return DetectedScreenTextBlock(
                        text: text,
                        rectInWindow: rect,
                        sourceView: nil,
                        sourceKind: .ocr
                    )
                }
                DispatchQueue.main.async {
                    completion(blocks)
                }
            } catch {
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }

    // MARK: - Private Traversal

    private static func traverse(
        view: UIView,
        in window: UIWindow,
        blocks: inout [DetectedScreenTextBlock],
        webViews: inout [WKWebView]
    ) {
        if view.isHidden || view.alpha < 0.05 { return }
        let clsName = NSStringFromClass(type(of: view))
        if clsName.contains("WriteNow") || clsName.contains("ScreenTextOverlay") { return }

        if let tf = view as? UITextField, tf.isSecureTextEntry { return }
        if let tv = view as? UITextView, tv.isSecureTextEntry { return }

        let rectInWin = view.convert(view.bounds, to: window)
        let clipped = rectInWin.intersection(window.bounds)
        if clipped.isEmpty || clipped.width < 10 || clipped.height < 10 { return }

        if let webView = view as? WKWebView {
            webViews.append(webView)
            return
        }

        if let label = view as? UILabel {
            let text = (label.text ?? label.attributedText?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if isMeaningfulText(text) {
                blocks.append(DetectedScreenTextBlock(text: text, rectInWindow: clipped, sourceView: view, sourceKind: .uiKit))
                return
            }
        } else if let tv = view as? UITextView {
            let text = (tv.text ?? tv.attributedText?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if isMeaningfulText(text) {
                blocks.append(DetectedScreenTextBlock(text: text, rectInWindow: clipped, sourceView: view, sourceKind: .uiKit))
                return
            }
        } else if let tf = view as? UITextField {
            let text = (tf.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if isMeaningfulText(text) {
                blocks.append(DetectedScreenTextBlock(text: text, rectInWindow: clipped, sourceView: view, sourceKind: .uiKit))
                return
            }
        } else if let direct = extractCustomTextSelector(from: view), isMeaningfulText(direct) {
            blocks.append(DetectedScreenTextBlock(text: direct, rectInWindow: clipped, sourceView: view, sourceKind: .uiKit))
            return
        }

        let beforeCount = blocks.count
        for sub in view.subviews {
            traverse(view: sub, in: window, blocks: &blocks, webViews: &webViews)
        }

        // Only capture accessibility text if no child already produced a text block inside this container
        if blocks.count == beforeCount {
            if let ax = (view.accessibilityValue ?? view.accessibilityLabel)?.trimmingCharacters(in: .whitespacesAndNewlines),
               isMeaningfulText(ax),
               ax.count >= 3
            {
                blocks.append(DetectedScreenTextBlock(text: ax, rectInWindow: clipped, sourceView: view, sourceKind: .accessibility))
            }
        }
    }

    private static func scanWebView(
        _ webView: WKWebView,
        in window: UIWindow,
        completion: @escaping ([DetectedScreenTextBlock]) -> Void
    ) {
        let js = """
        (function(){
          var tags = 'h1,h2,h3,h4,h5,h6,p,li,blockquote,pre,code,td,th,a,span,div';
          var nodes = document.querySelectorAll(tags);
          var out = [];
          var vh = window.innerHeight || document.documentElement.clientHeight;
          var vw = window.innerWidth || document.documentElement.clientWidth;
          for (var i = 0; i < nodes.length && out.length < 120; i++) {
            var el = nodes[i];
            if (el.children && el.children.length > 0) {
              var hasDirectText = false;
              for (var c = 0; c < el.childNodes.length; c++) {
                if (el.childNodes[c].nodeType === 3 && el.childNodes[c].nodeValue.trim().length > 1) {
                  hasDirectText = true; break;
                }
              }
              if (!hasDirectText) continue;
            }
            var txt = (el.innerText || el.textContent || '').trim();
            if (txt.length < 2) continue;
            var r = el.getBoundingClientRect();
            if (r.width < 12 || r.height < 10) continue;
            if (r.bottom <= 0 || r.top >= vh || r.right <= 0 || r.left >= vw) continue;
            out.push({ t: txt.slice(0, 1200), x: r.left, y: r.top, w: r.width, h: r.height });
          }
          return out;
        })();
        """
        webView.evaluateJavaScript(js) { res, _ in
            guard let arr = res as? [[String: Any]] else {
                completion([])
                return
            }
            let webFrameInWin = webView.convert(webView.bounds, to: window)
            let blocks: [DetectedScreenTextBlock] = arr.compactMap { item in
                guard let txt = item["t"] as? String,
                      let x = item["x"] as? CGFloat,
                      let y = item["y"] as? CGFloat,
                      let w = item["w"] as? CGFloat,
                      let h = item["h"] as? CGFloat
                else { return nil }
                let rect = CGRect(
                    x: webFrameInWin.minX + x,
                    y: webFrameInWin.minY + y,
                    width: w,
                    height: h
                ).intersection(window.bounds)
                guard !rect.isEmpty else { return nil }
                return DetectedScreenTextBlock(
                    text: txt,
                    rectInWindow: rect,
                    sourceView: webView,
                    sourceKind: .webKit
                )
            }
            completion(blocks)
        }
    }

    private static func extractCustomTextSelector(from view: UIView) -> String? {
        for key in ["text", "attributedText"] {
            let sel = NSSelectorFromString(key)
            if view.responds(to: sel), let obj = view.perform(sel)?.takeUnretainedValue() {
                if let s = obj as? String {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { return t }
                } else if let a = obj as? NSAttributedString {
                    let t = a.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { return t }
                }
            }
        }
        return nil
    }

    private static func isMeaningfulText(_ text: String) -> Bool {
        guard text.count >= 2 else { return false }
        // Ignore pure whitespace or single punctuation
        return text.rangeOfCharacter(from: .alphanumerics) != nil
    }

    private static func deduplicateAndSort(_ raw: [DetectedScreenTextBlock]) -> [DetectedScreenTextBlock] {
        var result: [DetectedScreenTextBlock] = []
        for candidate in raw {
            let dup = result.contains { existing in
                let inter = existing.rectInWindow.intersection(candidate.rectInWindow)
                let minArea = min(
                    existing.rectInWindow.width * existing.rectInWindow.height,
                    candidate.rectInWindow.width * candidate.rectInWindow.height
                )
                let overlapRatio = minArea > 0 ? (inter.width * inter.height) / minArea : 0
                return overlapRatio > 0.78 && (existing.text == candidate.text || existing.text.contains(candidate.text))
            }
            if !dup {
                result.append(candidate)
            }
        }
        return result.sorted {
            if abs($0.rectInWindow.minY - $1.rectInWindow.minY) > 12 {
                return $0.rectInWindow.minY < $1.rectInWindow.minY
            }
            return $0.rectInWindow.minX < $1.rectInWindow.minX
        }
    }
}
