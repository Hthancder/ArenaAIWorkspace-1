//
//  TextReplacementAnimator.swift
//  WritingTools
//

import QuartzCore
import UIKit

enum TextReplacementAnimator {
    static func animate(
        style: String,
        targetView: UIView,
        selectionRectsInView: [CGRect],
        fallbackRectInTarget: CGRect,
        oldText: String,
        newText: String,
        attributes: [NSAttributedString.Key: Any],
        accentHex: String
    ) {
        let normalizedStyle = style.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedStyle != "none", !normalizedStyle.isEmpty else { return }

        guard let hostView = targetView.window ?? targetView.superview ?? Optional(targetView) else {
            return
        }

        let validRects = selectionRectsInView.filter { !$0.isEmpty && $0.width > 1 && $0.height > 1 }
        let rawUnion: CGRect
        if let first = validRects.first {
            rawUnion = validRects.dropFirst().reduce(first) { $0.union($1) }
        } else if !fallbackRectInTarget.isEmpty {
            rawUnion = fallbackRectInTarget
        } else {
            rawUnion = CGRect(x: 16, y: max(20, targetView.bounds.midY - 32), width: max(120, targetView.bounds.width - 32), height: 64)
        }

        var hostRect = targetView.convert(rawUnion, to: hostView)
        let safeBounds = hostView.bounds.insetBy(dx: 8, dy: 8)
        hostRect = hostRect.intersection(safeBounds)
        if hostRect.isEmpty || hostRect.width < 24 || hostRect.height < 18 {
            hostRect = CGRect(
                x: max(16, safeBounds.midX - 140),
                y: max(60, safeBounds.midY - 36),
                width: min(280, safeBounds.width - 32),
                height: 72
            )
        }
        // Keep height compact enough for smooth 60fps rendering
        if hostRect.height > 260 {
            hostRect.size.height = 260
        }

        let font = (attributes[.font] as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
        let baseTextColor = (attributes[.foregroundColor] as? UIColor)
            ?? (targetView.traitCollection.userInterfaceStyle == .dark ? UIColor.white : UIColor.label)
        let bgColor = resolveBackdropColor(from: targetView)
        let accentColor = colorFromHex(accentHex) ?? UIColor.systemBlue

        let overlay = UIView(frame: hostRect.insetBy(dx: -10, dy: -10))
        overlay.isUserInteractionEnabled = false
        overlay.clipsToBounds = false
        overlay.backgroundColor = .clear
        hostView.addSubview(overlay)

        let localArea = CGRect(origin: CGPoint(x: 10, y: 10), size: hostRect.size)

        // Soft backdrop veil so underlying replaced text doesn't visually clash during transition
        let veil = UIView(frame: localArea.insetBy(dx: -4, dy: -2))
        veil.backgroundColor = bgColor.withAlphaComponent(0.92)
        veil.layer.cornerRadius = 8
        veil.alpha = 1
        overlay.addSubview(veil)

        let oldTokens = tokenize(oldText, maxCount: 48)
        let newTokens = tokenize(newText, maxCount: 48)

        let oldFrames = layoutFrames(for: oldTokens, font: font, in: localArea)
        let newFrames = layoutFrames(for: newTokens, font: font, in: localArea)

        switch normalizedStyle {
        case "rain_drop_rise":
            runRainDropRise(
                overlay: overlay,
                veil: veil,
                oldTokens: oldTokens,
                oldFrames: oldFrames,
                newTokens: newTokens,
                newFrames: newFrames,
                font: font,
                textColor: baseTextColor
            )
        case "thanos_dust":
            runThanosDust(
                overlay: overlay,
                veil: veil,
                localArea: localArea,
                oldTokens: oldTokens,
                oldFrames: oldFrames,
                newTokens: newTokens,
                newFrames: newFrames,
                font: font,
                textColor: baseTextColor,
                accentColor: accentColor
            )
        case "typewriter_wave":
            runTypewriterWave(
                overlay: overlay,
                veil: veil,
                localArea: localArea,
                oldTokens: oldTokens,
                oldFrames: oldFrames,
                newTokens: newTokens,
                newFrames: newFrames,
                font: font,
                textColor: baseTextColor,
                accentColor: accentColor
            )
        case "flip_cascade":
            runFlipCascade(
                overlay: overlay,
                veil: veil,
                oldTokens: oldTokens,
                oldFrames: oldFrames,
                newTokens: newTokens,
                newFrames: newFrames,
                font: font,
                textColor: baseTextColor
            )
        case "glitch_matrix":
            runGlitchMatrix(
                overlay: overlay,
                veil: veil,
                localArea: localArea,
                oldText: oldText,
                newText: newText,
                font: font,
                textColor: baseTextColor,
                accentColor: accentColor
            )
        default: // "scatter_assemble"
            runScatterAssemble(
                overlay: overlay,
                veil: veil,
                oldTokens: oldTokens,
                oldFrames: oldFrames,
                newTokens: newTokens,
                newFrames: newFrames,
                font: font,
                textColor: baseTextColor
            )
        }
    }

    // MARK: - 1. Scatter & Assemble (Phân mảnh tung tóe -> Ráp vào)

    private static func runScatterAssemble(
        overlay: UIView,
        veil: UIView,
        oldTokens: [String],
        oldFrames: [CGRect],
        newTokens: [String],
        newFrames: [CGRect],
        font: UIFont,
        textColor: UIColor
    ) {
        let oldLabels = makeLabels(tokens: oldTokens, frames: oldFrames, font: font, color: textColor)
        for (idx, lbl) in oldLabels.enumerated() {
            overlay.addSubview(lbl)
            let dx = CGFloat.random(in: -115 ... 115)
            let dy = CGFloat.random(in: -85 ... 85)
            let angle = CGFloat.random(in: -CGFloat.pi ... CGFloat.pi)
            let delay = Double(idx % 12) * 0.008
            UIView.animate(withDuration: 0.36, delay: delay, options: [.curveEaseOut]) {
                lbl.transform = CGAffineTransform(translationX: dx, y: dy)
                    .rotated(by: angle)
                    .scaledBy(x: 0.3, y: 0.3)
                lbl.alpha = 0
            }
        }

        let newLabels = makeLabels(tokens: newTokens, frames: newFrames, font: font, color: textColor)
        for (idx, lbl) in newLabels.enumerated() {
            let sx = CGFloat.random(in: -110 ... 110)
            let sy = CGFloat.random(in: -75 ... 75)
            let angle = CGFloat.random(in: -0.9 ... 0.9)
            lbl.transform = CGAffineTransform(translationX: sx, y: sy)
                .rotated(by: angle)
                .scaledBy(x: 1.45, y: 1.45)
            lbl.alpha = 0
            overlay.addSubview(lbl)

            let delay = 0.18 + Double(idx % 14) * 0.012
            UIView.animate(
                withDuration: 0.48,
                delay: delay,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0.85,
                options: [.curveEaseOut]
            ) {
                lbl.transform = .identity
                lbl.alpha = 1
            }
        }

        cleanupOverlay(overlay: overlay, veil: veil, after: 0.78)
    }

    // MARK: - 2. Gravity Fall & Sprout (Chữ rụng xuống -> Chữ mới mọc lên)

    private static func runRainDropRise(
        overlay: UIView,
        veil: UIView,
        oldTokens: [String],
        oldFrames: [CGRect],
        newTokens: [String],
        newFrames: [CGRect],
        font: UIFont,
        textColor: UIColor
    ) {
        let oldLabels = makeLabels(tokens: oldTokens, frames: oldFrames, font: font, color: textColor)
        for (idx, lbl) in oldLabels.enumerated() {
            overlay.addSubview(lbl)
            let dropY = CGFloat.random(in: 55 ... 135)
            let driftX = CGFloat.random(in: -18 ... 18)
            let tilt = CGFloat.random(in: -0.55 ... 0.55)
            let delay = Double(idx) * 0.007
            UIView.animate(withDuration: 0.38, delay: delay, options: [.curveEaseIn]) {
                lbl.transform = CGAffineTransform(translationX: driftX, y: dropY)
                    .rotated(by: tilt)
                lbl.alpha = 0
            }
        }

        let newLabels = makeLabels(tokens: newTokens, frames: newFrames, font: font, color: textColor)
        for (idx, lbl) in newLabels.enumerated() {
            lbl.transform = CGAffineTransform(translationX: 0, y: 26).scaledBy(x: 0.85, y: 0.15)
            lbl.alpha = 0
            overlay.addSubview(lbl)

            let delay = 0.24 + Double(idx) * 0.009
            UIView.animate(
                withDuration: 0.46,
                delay: delay,
                usingSpringWithDamping: 0.62,
                initialSpringVelocity: 0.9,
                options: [.curveEaseOut]
            ) {
                lbl.transform = .identity
                lbl.alpha = 1
            }
        }

        cleanupOverlay(overlay: overlay, veil: veil, after: 0.82)
    }

    // MARK: - 3. Ash & Dust (Phân mảnh như tro bụi -> Mọc lên)

    private static func runThanosDust(
        overlay: UIView,
        veil: UIView,
        localArea: CGRect,
        oldTokens: [String],
        oldFrames: [CGRect],
        newTokens: [String],
        newFrames: [CGRect],
        font: UIFont,
        textColor: UIColor,
        accentColor: UIColor
    ) {
        // Ash & ember emitter layer
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: localArea.midX, y: localArea.midY)
        emitter.emitterSize = CGSize(width: localArea.width, height: localArea.height)
        emitter.emitterShape = .rectangle
        emitter.renderMode = .unordered

        let dotImage = makeDustParticleImage()
        let ashCell = CAEmitterCell()
        ashCell.contents = dotImage
        ashCell.birthRate = 110
        ashCell.lifetime = 0.75
        ashCell.velocity = 42
        ashCell.velocityRange = 28
        ashCell.emissionLongitude = -CGFloat.pi / 4
        ashCell.emissionRange = CGFloat.pi / 2
        ashCell.yAcceleration = -65
        ashCell.xAcceleration = 45
        ashCell.scale = 0.35
        ashCell.scaleRange = 0.25
        ashCell.alphaSpeed = -1.35
        ashCell.color = UIColor.lightGray.cgColor

        let emberCell = CAEmitterCell()
        emberCell.contents = dotImage
        emberCell.birthRate = 45
        emberCell.lifetime = 0.65
        emberCell.velocity = 50
        emberCell.velocityRange = 30
        emberCell.emissionLongitude = -CGFloat.pi / 3
        emberCell.emissionRange = CGFloat.pi / 2
        emberCell.yAcceleration = -80
        emberCell.xAcceleration = 55
        emberCell.scale = 0.28
        emberCell.scaleRange = 0.2
        emberCell.alphaSpeed = -1.5
        emberCell.color = accentColor.cgColor

        emitter.emitterCells = [ashCell, emberCell]
        overlay.layer.addSublayer(emitter)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            emitter.birthRate = 0
        }

        let oldLabels = makeLabels(tokens: oldTokens, frames: oldFrames, font: font, color: textColor)
        for (idx, lbl) in oldLabels.enumerated() {
            overlay.addSubview(lbl)
            let progressDelay = Double(idx) / Double(max(1, oldLabels.count)) * 0.24
            let driftX = CGFloat.random(in: 18 ... 64)
            let driftY = CGFloat.random(in: -48 ... -12)
            UIView.animate(withDuration: 0.38, delay: progressDelay, options: [.curveEaseOut]) {
                lbl.transform = CGAffineTransform(translationX: driftX, y: driftY)
                    .scaledBy(x: 0.25, y: 0.25)
                lbl.alpha = 0
            }
        }

        let newLabels = makeLabels(tokens: newTokens, frames: newFrames, font: font, color: textColor)
        for (idx, lbl) in newLabels.enumerated() {
            lbl.transform = CGAffineTransform(translationX: 0, y: 14).scaledBy(x: 0.72, y: 0.72)
            lbl.alpha = 0
            overlay.addSubview(lbl)
            let delay = 0.26 + Double(idx) * 0.008
            UIView.animate(withDuration: 0.42, delay: delay, options: [.curveEaseOut]) {
                lbl.transform = .identity
                lbl.alpha = 1
            }
        }

        cleanupOverlay(overlay: overlay, veil: veil, after: 0.85)
    }

    // MARK: - 4. Cyber Typewriter & Wave

    private static func runTypewriterWave(
        overlay: UIView,
        veil: UIView,
        localArea: CGRect,
        oldTokens: [String],
        oldFrames: [CGRect],
        newTokens: [String],
        newFrames: [CGRect],
        font: UIFont,
        textColor: UIColor,
        accentColor: UIColor
    ) {
        let oldLabels = makeLabels(tokens: oldTokens, frames: oldFrames, font: font, color: textColor)
        for (idx, lbl) in oldLabels.enumerated() {
            overlay.addSubview(lbl)
            let delay = Double(idx) * 0.004
            UIView.animate(withDuration: 0.18, delay: delay, options: [.curveEaseIn]) {
                lbl.alpha = 0
                lbl.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            }
        }

        let scanLine = UIView(frame: CGRect(x: localArea.minX, y: localArea.minY, width: 3, height: localArea.height))
        scanLine.backgroundColor = accentColor
        scanLine.layer.cornerRadius = 1.5
        scanLine.layer.shadowColor = accentColor.cgColor
        scanLine.layer.shadowRadius = 6
        scanLine.layer.shadowOpacity = 0.9
        scanLine.layer.shadowOffset = .zero
        overlay.addSubview(scanLine)

        UIView.animate(withDuration: 0.48, delay: 0.08, options: [.curveEaseInOut]) {
            scanLine.frame.origin.x = localArea.maxX - 3
        } completion: { _ in
            UIView.animate(withDuration: 0.14) { scanLine.alpha = 0 }
        }

        let newLabels = makeLabels(tokens: newTokens, frames: newFrames, font: font, color: textColor)
        for (idx, lbl) in newLabels.enumerated() {
            lbl.transform = CGAffineTransform(translationX: 0, y: -9).scaledBy(x: 0.8, y: 0.8)
            lbl.alpha = 0
            overlay.addSubview(lbl)
            let delay = 0.12 + Double(idx) * 0.010
            UIView.animate(
                withDuration: 0.34,
                delay: delay,
                usingSpringWithDamping: 0.58,
                initialSpringVelocity: 0.8,
                options: [.curveEaseOut]
            ) {
                lbl.transform = .identity
                lbl.alpha = 1
            }
        }

        cleanupOverlay(overlay: overlay, veil: veil, after: 0.72)
    }

    // MARK: - 5. 3D Flip Cascade

    private static func runFlipCascade(
        overlay: UIView,
        veil: UIView,
        oldTokens: [String],
        oldFrames: [CGRect],
        newTokens: [String],
        newFrames: [CGRect],
        font: UIFont,
        textColor: UIColor
    ) {
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 450.0

        let oldLabels = makeLabels(tokens: oldTokens, frames: oldFrames, font: font, color: textColor)
        for (idx, lbl) in oldLabels.enumerated() {
            lbl.layer.transform = perspective
            overlay.addSubview(lbl)
            let delay = Double(idx) * 0.007
            UIView.animate(withDuration: 0.22, delay: delay, options: [.curveEaseIn]) {
                lbl.layer.transform = CATransform3DRotate(perspective, .pi / 2.0, 1, 0, 0)
                lbl.alpha = 0
            }
        }

        let newLabels = makeLabels(tokens: newTokens, frames: newFrames, font: font, color: textColor)
        for (idx, lbl) in newLabels.enumerated() {
            lbl.layer.transform = CATransform3DRotate(perspective, -.pi / 2.0, 1, 0, 0)
            lbl.alpha = 0
            overlay.addSubview(lbl)
            let delay = 0.16 + Double(idx) * 0.008
            UIView.animate(
                withDuration: 0.34,
                delay: delay,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0.6,
                options: [.curveEaseOut]
            ) {
                lbl.layer.transform = perspective
                lbl.alpha = 1
            }
        }

        cleanupOverlay(overlay: overlay, veil: veil, after: 0.72)
    }

    // MARK: - 6. Glitch Matrix

    private static func runGlitchMatrix(
        overlay: UIView,
        veil: UIView,
        localArea: CGRect,
        oldText: String,
        newText: String,
        font: UIFont,
        textColor: UIColor,
        accentColor: UIColor
    ) {
        let cyanLabel = UILabel(frame: localArea.offsetBy(dx: -4, dy: -1))
        cyanLabel.font = font
        cyanLabel.numberOfLines = 0
        cyanLabel.textColor = UIColor.cyan.withAlphaComponent(0.85)
        cyanLabel.text = scrambleString(oldText, limit: 120)

        let magentaLabel = UILabel(frame: localArea.offsetBy(dx: 4, dy: 1))
        magentaLabel.font = font
        magentaLabel.numberOfLines = 0
        magentaLabel.textColor = accentColor.withAlphaComponent(0.85)
        magentaLabel.text = scrambleString(newText, limit: 120)

        let mainLabel = UILabel(frame: localArea)
        mainLabel.font = font
        mainLabel.numberOfLines = 0
        mainLabel.textColor = textColor
        mainLabel.text = oldText

        overlay.addSubview(cyanLabel)
        overlay.addSubview(magentaLabel)
        overlay.addSubview(mainLabel)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            cyanLabel.frame = localArea.offsetBy(dx: 5, dy: 0)
            magentaLabel.frame = localArea.offsetBy(dx: -5, dy: 0)
            mainLabel.text = scrambleString(newText, limit: 140)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            cyanLabel.frame = localArea.offsetBy(dx: -2, dy: 1)
            magentaLabel.frame = localArea.offsetBy(dx: 2, dy: -1)
            mainLabel.text = newText
            UIView.animate(withDuration: 0.22) {
                cyanLabel.alpha = 0
                magentaLabel.alpha = 0
                cyanLabel.frame = localArea
                magentaLabel.frame = localArea
            }
        }

        cleanupOverlay(overlay: overlay, veil: veil, after: 0.56)
    }

    // MARK: - Helpers

    private static func cleanupOverlay(overlay: UIView, veil: UIView, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            UIView.animate(withDuration: 0.18) {
                veil.alpha = 0
                overlay.alpha = 0
            } completion: { _ in
                overlay.removeFromSuperview()
            }
        }
    }

    private static func tokenize(_ text: String, maxCount: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let sample = String(trimmed.prefix(180))
        if sample.count <= maxCount {
            return sample.map { String($0) }
        }
        let words = sample.split(separator: " ", omittingEmptySubsequences: false).map { String($0) + " " }
        if words.count <= maxCount {
            return words
        }
        return Array(words.prefix(maxCount))
    }

    private static func layoutFrames(for tokens: [String], font: UIFont, in area: CGRect) -> [CGRect] {
        var frames: [CGRect] = []
        var cursorX = area.minX
        var cursorY = area.minY
        let lineHeight = ceil(font.lineHeight)

        for token in tokens {
            if token == "\n" {
                frames.append(CGRect(x: cursorX, y: cursorY, width: 4, height: lineHeight))
                cursorX = area.minX
                cursorY += lineHeight
                if cursorY + lineHeight > area.maxY { cursorY = area.maxY - lineHeight }
                continue
            }
            let size = (token as NSString).size(withAttributes: [.font: font])
            let w = max(4, ceil(size.width))
            if cursorX + w > area.maxX, cursorX > area.minX {
                cursorX = area.minX
                cursorY += lineHeight
                if cursorY + lineHeight > area.maxY { cursorY = area.minY }
            }
            frames.append(CGRect(x: cursorX, y: cursorY, width: w, height: lineHeight))
            cursorX += w
        }
        return frames
    }

    private static func makeLabels(tokens: [String], frames: [CGRect], font: UIFont, color: UIColor) -> [UILabel] {
        zip(tokens, frames).map { token, frame in
            let lbl = UILabel(frame: frame)
            lbl.text = token
            lbl.font = font
            lbl.textColor = color
            lbl.textAlignment = .left
            return lbl
        }
    }

    private static func makeDustParticleImage() -> CGImage? {
        let size = CGSize(width: 8, height: 8)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
        return img.cgImage
    }

    private static func scrambleString(_ source: String, limit: Int) -> String {
        let glyphs = Array("!@#$%^&*01<>?/~")
        return String(source.prefix(limit).map { ch in
            if ch.isWhitespace || ch.isNewline { return ch }
            return glyphs.randomElement() ?? "#"
        })
    }

    private static func resolveBackdropColor(from view: UIView) -> UIColor {
        var current: UIView? = view
        for _ in 0 ..< 5 {
            if let bg = current?.backgroundColor, bg != .clear, bg.cgColor.alpha > 0.25 {
                return bg
            }
            current = current?.superview
        }
        return view.traitCollection.userInterfaceStyle == .dark ? .black : .systemBackground
    }

    private static func colorFromHex(_ hexString: String) -> UIColor? {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let val = UInt64(hex, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((val >> 16) & 0xFF) / 255.0,
            green: CGFloat((val >> 8) & 0xFF) / 255.0,
            blue: CGFloat(val & 0xFF) / 255.0,
            alpha: 1
        )
    }
}
