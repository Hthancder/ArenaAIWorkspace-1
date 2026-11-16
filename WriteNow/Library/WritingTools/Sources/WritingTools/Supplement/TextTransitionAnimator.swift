//
//  TextTransitionAnimator.swift
//  WritingTools
//

import QuartzCore
import UIKit

enum TextTransitionStyle: String, CaseIterable {
    case shatter
    case fallDown
    case ashDust
    case wave
    case glitch
    case typewriter
    case magicGlow
    case none
}

final class TextTransitionAnimator {
    struct PreparedCapture {
        let hostView: UIView
        let targetRectInHost: CGRect
        let lineRectsInHost: [CGRect]
        let oldSnapshot: UIImage
        let backdropColor: UIColor
        let textColor: UIColor
        let font: UIFont
        let oldText: String
    }

    static func captureBeforeReplace(context: Presenter.Context) -> PreparedCapture? {
        let styleRaw = Configurator.shared.settings.textAnimationStyle
        guard styleRaw != TextTransitionStyle.none.rawValue else { return nil }

        let targetView = context.targetView
        guard let hostView = targetView.window ?? targetView.superview else { return nil }

        var rawRects = context.textProxy.selectionRectsInView
            .filter { $0.width > 1 && $0.height > 1 }
        if rawRects.isEmpty {
            let anchor = context.anchorView.frame
            if anchor.width > 1 && anchor.height > 1 {
                rawRects = [anchor]
            } else {
                return nil
            }
        }

        let convertedRects = rawRects
            .map { targetView.convert($0, to: hostView) }
            .map { $0.intersection(hostView.bounds) }
            .filter { !$0.isNull && $0.width > 2 && $0.height > 2 }
        guard !convertedRects.isEmpty else { return nil }

        let unionInHost = convertedRects.reduce(convertedRects[0]) { $0.union($1) }.insetBy(dx: -4, dy: -4)
            .intersection(hostView.bounds)
        guard unionInHost.width > 4 && unionInHost.height > 4 else { return nil }

        let unionInTarget = hostView.convert(unionInHost, to: targetView)
        let prevHidden = context.decorationViews.map(\.isHidden)
        context.decorationViews.forEach { $0.isHidden = true }
        let snapshot = captureSnapshot(of: targetView, rect: unionInTarget)
        for (v, wasHidden) in zip(context.decorationViews, prevHidden) {
            v.isHidden = wasHidden
        }
        guard let snapshot else { return nil }

        let attrs = context.textProxy.selectedTextAttribute
        let font = (attrs[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 16)
        let textColor = (attrs[.foregroundColor] as? UIColor)
            ?? (hostView.traitCollection.userInterfaceStyle == .dark ? .white : .label)
        let backdrop = sampleBackdropColor(from: snapshot, fallbackView: targetView)

        return PreparedCapture(
            hostView: hostView,
            targetRectInHost: unionInHost,
            lineRectsInHost: convertedRects,
            oldSnapshot: snapshot,
            backdropColor: backdrop,
            textColor: textColor,
            font: font,
            oldText: context.textProxy.selectedText
        )
    }

    static func play(capture: PreparedCapture, newText: String) {
        let style = TextTransitionStyle(rawValue: Configurator.shared.settings.textAnimationStyle) ?? .shatter
        guard style != .none else { return }

        let host = capture.hostView
        let rect = capture.targetRectInHost

        let overlay = UIView(frame: rect)
        overlay.isUserInteractionEnabled = false
        overlay.clipsToBounds = false
        overlay.backgroundColor = capture.backdropColor
        host.addSubview(overlay)

        switch style {
        case .shatter:
            playShatter(overlay: overlay, capture: capture, newText: newText)
        case .fallDown:
            playFallDown(overlay: overlay, capture: capture, newText: newText)
        case .ashDust:
            playAshDust(overlay: overlay, capture: capture, newText: newText)
        case .wave:
            playWave(overlay: overlay, capture: capture, newText: newText)
        case .glitch:
            playGlitch(overlay: overlay, capture: capture, newText: newText)
        case .typewriter:
            playTypewriter(overlay: overlay, capture: capture, newText: newText)
        case .magicGlow:
            playMagicGlow(overlay: overlay, capture: capture, newText: newText)
        case .none:
            overlay.removeFromSuperview()
        }
    }

    // MARK: - 1. Shatter & Assemble

    private static func playShatter(overlay: UIView, capture: PreparedCapture, newText: String) {
        let tiles = buildSnapshotTileLayers(in: overlay, capture: capture, targetTileSize: 12, maxTiles: 110)

        for tile in tiles {
            let dx = CGFloat.random(in: -130 ... 130)
            let dy = CGFloat.random(in: -110 ... 110)
            let angle = CGFloat.random(in: -CGFloat.pi ... CGFloat.pi)
            let scale = CGFloat.random(in: 0.25 ... 0.65)
            let delay = Double.random(in: 0.0 ... 0.12)

            animateLayer(tile, duration: 0.55, delay: delay, timing: .easeOut) {
                var t = CATransform3DIdentity
                t = CATransform3DTranslate(t, dx, dy, 0)
                t = CATransform3DRotate(t, angle, 0, 0, 1)
                t = CATransform3DScale(t, scale, scale, 1)
                tile.transform = t
                tile.opacity = 0
            }
        }

        // Fly-in new text word fragments
        let wordLabels = buildNewTextWordLabels(in: overlay, capture: capture, newText: newText)
        for lbl in wordLabels {
            let startX = CGFloat.random(in: -75 ... 75)
            let startY = CGFloat.random(in: -55 ... 55)
            let startAngle = CGFloat.random(in: -0.6 ... 0.6)
            lbl.alpha = 0
            lbl.transform = CGAffineTransform(translationX: startX, y: startY)
                .rotated(by: startAngle)
                .scaledBy(x: 0.45, y: 0.45)

            let delay = 0.28 + Double.random(in: 0.0 ... 0.16)
            UIView.animate(
                withDuration: 0.52,
                delay: delay,
                usingSpringWithDamping: 0.74,
                initialSpringVelocity: 0.6,
                options: [.allowUserInteraction]
            ) {
                lbl.alpha = 1
                lbl.transform = .identity
            }
        }

        finishOverlay(overlay, after: 0.95)
    }

    // MARK: - 2. Gravity Fall & Rise

    private static func playFallDown(overlay: UIView, capture: PreparedCapture, newText: String) {
        let tiles = buildSnapshotTileLayers(in: overlay, capture: capture, targetTileSize: 14, maxTiles: 100)
        let sorted = tiles.sorted { $0.frame.minY > $1.frame.minY || ($0.frame.minY == $1.frame.minY && $0.frame.minX < $1.frame.minX) }

        for (idx, tile) in sorted.enumerated() {
            let fallDistance = CGFloat.random(in: 95 ... 175)
            let driftX = CGFloat.random(in: -22 ... 22)
            let tilt = CGFloat.random(in: -0.7 ... 0.7)
            let delay = min(0.22, Double(idx) * 0.004)

            animateLayer(tile, duration: 0.52, delay: delay, timing: .easeIn) {
                var t = CATransform3DIdentity
                t = CATransform3DTranslate(t, driftX, fallDistance, 0)
                t = CATransform3DRotate(t, tilt, 0, 0, 1)
                tile.transform = t
                tile.opacity = 0
            }
        }

        let newLabel = makeRenderedNewTextLabel(frame: overlay.bounds.insetBy(dx: 4, dy: 4), capture: capture, newText: newText)
        newLabel.alpha = 0
        newLabel.transform = CGAffineTransform(translationX: 0, y: 26).scaledBy(x: 0.92, y: 0.25)
        overlay.addSubview(newLabel)

        UIView.animate(
            withDuration: 0.55,
            delay: 0.36,
            usingSpringWithDamping: 0.68,
            initialSpringVelocity: 0.5,
            options: [.allowUserInteraction]
        ) {
            newLabel.alpha = 1
            newLabel.transform = .identity
        }

        finishOverlay(overlay, after: 0.98)
    }

    // MARK: - 3. Ash & Dust (Thanos Snap)

    private static func playAshDust(overlay: UIView, capture: PreparedCapture, newText: String) {
        let tiles = buildSnapshotTileLayers(in: overlay, capture: capture, targetTileSize: 7, maxTiles: 150)
        let minX = tiles.map(\.frame.minX).min() ?? 0
        let spanX = max(1, (tiles.map(\.frame.maxX).max() ?? overlay.bounds.width) - minX)

        // Particle ash emitter
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: overlay.bounds.midX, y: overlay.bounds.midY)
        emitter.emitterShape = .rectangle
        emitter.emitterSize = overlay.bounds.size
        emitter.renderMode = .unordered

        let cell = CAEmitterCell()
        cell.contents = makeDustParticleCGImage(color: capture.textColor.withAlphaComponent(0.75))
        cell.birthRate = 95
        cell.lifetime = 0.85
        cell.lifetimeRange = 0.25
        cell.velocity = 42
        cell.velocityRange = 28
        cell.emissionLongitude = -.pi / 4
        cell.emissionRange = .pi / 3
        cell.xAcceleration = 48
        cell.yAcceleration = -58
        cell.scale = 0.55
        cell.scaleRange = 0.35
        cell.alphaSpeed = -1.1
        cell.spin = 2.0
        emitter.emitterCells = [cell]
        overlay.layer.addSublayer(emitter)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            emitter.birthRate = 0
        }

        for tile in tiles {
            let progressX = Double((tile.frame.midX - minX) / spanX)
            let delay = progressX * 0.28 + Double.random(in: 0 ... 0.05)
            let dx = CGFloat.random(in: 28 ... 105)
            let dy = CGFloat.random(in: -95 ... -18)

            animateLayer(tile, duration: 0.58, delay: delay, timing: .easeOut) {
                var t = CATransform3DIdentity
                t = CATransform3DTranslate(t, dx, dy, 0)
                t = CATransform3DRotate(t, CGFloat.random(in: -1.4 ... 1.4), 0, 0, 1)
                t = CATransform3DScale(t, 0.12, 0.12, 1)
                tile.transform = t
                tile.opacity = 0
            }
        }

        let newLabel = makeRenderedNewTextLabel(frame: overlay.bounds.insetBy(dx: 4, dy: 4), capture: capture, newText: newText)
        newLabel.alpha = 0
        newLabel.transform = CGAffineTransform(translationX: 0, y: 18).scaledBy(x: 0.90, y: 0.85)
        overlay.addSubview(newLabel)

        UIView.animate(
            withDuration: 0.52,
            delay: 0.45,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.3,
            options: [.allowUserInteraction]
        ) {
            newLabel.alpha = 1
            newLabel.transform = .identity
        }

        finishOverlay(overlay, after: 1.08)
    }

    // MARK: - 4. Wave Flip

    private static func playWave(overlay: UIView, capture: PreparedCapture, newText: String) {
        let tiles = buildSnapshotTileLayers(in: overlay, capture: capture, targetTileSize: 16, maxTiles: 80)
        let sorted = tiles.sorted { $0.frame.minX < $1.frame.minX }

        for (idx, tile) in sorted.enumerated() {
            let delay = min(0.28, Double(idx) * 0.008)
            animateLayer(tile, duration: 0.42, delay: delay, timing: .easeInOut) {
                var t = CATransform3DIdentity
                t.m34 = -1.0 / 400.0
                t = CATransform3DRotate(t, .pi / 2, 0, 1, 0)
                t = CATransform3DTranslate(t, 0, -10, 0)
                tile.transform = t
                tile.opacity = 0
            }
        }

        let wordLabels = buildNewTextWordLabels(in: overlay, capture: capture, newText: newText)
        for (idx, lbl) in wordLabels.enumerated() {
            lbl.alpha = 0
            lbl.transform = CGAffineTransform(translationX: 0, y: -12).scaledBy(x: 0.85, y: 0.85)
            let delay = 0.28 + min(0.32, Double(idx) * 0.015)
            UIView.animate(
                withDuration: 0.42,
                delay: delay,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0.5,
                options: [.allowUserInteraction]
            ) {
                lbl.alpha = 1
                lbl.transform = .identity
            }
        }

        finishOverlay(overlay, after: 0.95)
    }

    // MARK: - 5. Cyber Glitch

    private static func playGlitch(overlay: UIView, capture: PreparedCapture, newText: String) {
        let baseImgView = UIImageView(frame: overlay.bounds)
        baseImgView.image = capture.oldSnapshot
        baseImgView.contentMode = .scaleToFill
        overlay.addSubview(baseImgView)

        let cyanLayer = CALayer()
        cyanLayer.frame = overlay.bounds
        cyanLayer.contents = capture.oldSnapshot.cgImage
        cyanLayer.opacity = 0.55
        overlay.layer.addSublayer(cyanLayer)

        let magentaLayer = CALayer()
        magentaLayer.frame = overlay.bounds
        magentaLayer.contents = capture.oldSnapshot.cgImage
        magentaLayer.opacity = 0.55
        overlay.layer.addSublayer(magentaLayer)

        let keyCyan = CAKeyframeAnimation(keyPath: "transform.translation.x")
        keyCyan.values = [0, -9, 7, -12, 5, -4, 0]
        keyCyan.duration = 0.38
        cyanLayer.add(keyCyan, forKey: "glitchX")

        let keyMag = CAKeyframeAnimation(keyPath: "transform.translation.x")
        keyMag.values = [0, 10, -8, 13, -6, 3, 0]
        keyMag.duration = 0.38
        magentaLayer.add(keyMag, forKey: "glitchX")

        let newLabel = makeRenderedNewTextLabel(frame: overlay.bounds.insetBy(dx: 4, dy: 4), capture: capture, newText: newText)
        newLabel.alpha = 0
        overlay.addSubview(newLabel)

        UIView.animate(withDuration: 0.16, delay: 0.30) {
            baseImgView.alpha = 0
            cyanLayer.opacity = 0
            magentaLayer.opacity = 0
            newLabel.alpha = 1
        }

        finishOverlay(overlay, after: 0.78)
    }

    // MARK: - 6. Laser Typewriter

    private static func playTypewriter(overlay: UIView, capture: PreparedCapture, newText: String) {
        let oldImgView = UIImageView(frame: overlay.bounds)
        oldImgView.image = capture.oldSnapshot
        oldImgView.contentMode = .scaleToFill
        overlay.addSubview(oldImgView)

        let newLabel = makeRenderedNewTextLabel(frame: overlay.bounds.insetBy(dx: 4, dy: 4), capture: capture, newText: newText)
        overlay.addSubview(newLabel)

        let newMask = CALayer()
        newMask.backgroundColor = UIColor.white.cgColor
        newMask.frame = CGRect(x: 0, y: 0, width: 0, height: overlay.bounds.height)
        newLabel.layer.mask = newMask

        let laserBar = CAGradientLayer()
        laserBar.frame = CGRect(x: -6, y: 0, width: 10, height: overlay.bounds.height)
        laserBar.colors = [
            UIColor.clear.cgColor,
            UIColor.systemCyan.cgColor,
            UIColor.white.cgColor,
            UIColor.clear.cgColor,
        ]
        laserBar.startPoint = CGPoint(x: 0, y: 0.5)
        laserBar.endPoint = CGPoint(x: 1, y: 0.5)
        overlay.layer.addSublayer(laserBar)

        UIView.animate(withDuration: 0.32, delay: 0.0, options: [.curveEaseOut]) {
            oldImgView.alpha = 0
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.62)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        newMask.frame = overlay.bounds
        laserBar.frame = CGRect(x: overlay.bounds.width, y: 0, width: 10, height: overlay.bounds.height)
        CATransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
            laserBar.opacity = 0
        }

        finishOverlay(overlay, after: 0.85)
    }

    // MARK: - 7. Apple Magic Glow

    private static func playMagicGlow(overlay: UIView, capture: PreparedCapture, newText: String) {
        let oldImgView = UIImageView(frame: overlay.bounds)
        oldImgView.image = capture.oldSnapshot
        oldImgView.contentMode = .scaleToFill
        overlay.addSubview(oldImgView)

        let newLabel = makeRenderedNewTextLabel(frame: overlay.bounds.insetBy(dx: 4, dy: 4), capture: capture, newText: newText)
        newLabel.alpha = 0
        overlay.addSubview(newLabel)

        let glow = CAGradientLayer()
        glow.frame = CGRect(x: -overlay.bounds.width * 0.5, y: 0, width: overlay.bounds.width * 0.55, height: overlay.bounds.height)
        glow.colors = [
            UIColor.clear.cgColor,
            UIColor.systemPurple.withAlphaComponent(0.45).cgColor,
            UIColor.systemCyan.withAlphaComponent(0.45).cgColor,
            UIColor.clear.cgColor,
        ]
        glow.startPoint = CGPoint(x: 0, y: 0.2)
        glow.endPoint = CGPoint(x: 1, y: 0.8)
        overlay.layer.addSublayer(glow)

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.65)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        glow.frame = CGRect(x: overlay.bounds.width * 1.1, y: 0, width: overlay.bounds.width * 0.55, height: overlay.bounds.height)
        CATransaction.commit()

        UIView.animate(withDuration: 0.42, delay: 0.18) {
            oldImgView.alpha = 0
            newLabel.alpha = 1
        }

        finishOverlay(overlay, after: 0.80)
    }

    // MARK: - Helpers

    private static func finishOverlay(_ overlay: UIView, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            UIView.animate(withDuration: 0.20, animations: {
                overlay.alpha = 0
            }, completion: { _ in
                overlay.removeFromSuperview()
            })
        }
    }

    private enum Timing {
        case easeIn, easeOut, easeInOut

        var mediaTiming: CAMediaTimingFunction {
            switch self {
            case .easeIn: return CAMediaTimingFunction(name: .easeIn)
            case .easeOut: return CAMediaTimingFunction(name: .easeOut)
            case .easeInOut: return CAMediaTimingFunction(name: .easeInEaseOut)
            }
        }
    }

    private static func animateLayer(_ layer: CALayer, duration: TimeInterval, delay: TimeInterval, timing: Timing, changes: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            CATransaction.begin()
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(timing.mediaTiming)
            changes()
            CATransaction.commit()
        }
    }

    private static func buildSnapshotTileLayers(
        in overlay: UIView,
        capture: PreparedCapture,
        targetTileSize: CGFloat,
        maxTiles: Int
    ) -> [CALayer] {
        guard let cgImage = capture.oldSnapshot.cgImage else { return [] }
        let width = overlay.bounds.width
        let height = overlay.bounds.height
        guard width > 2, height > 2 else { return [] }

        var cols = max(3, Int(ceil(width / targetTileSize)))
        var rows = max(1, Int(ceil(height / targetTileSize)))
        while cols * rows > maxTiles {
            if cols >= rows, cols > 2 {
                cols -= 1
            } else if rows > 1 {
                rows -= 1
            } else {
                break
            }
        }

        let tileW = width / CGFloat(cols)
        let tileH = height / CGFloat(rows)
        var layers: [CALayer] = []
        layers.reserveCapacity(cols * rows)

        for r in 0 ..< rows {
            for c in 0 ..< cols {
                let layer = CALayer()
                layer.frame = CGRect(x: CGFloat(c) * tileW, y: CGFloat(r) * tileH, width: tileW, height: tileH)
                layer.contents = cgImage
                layer.contentsRect = CGRect(
                    x: CGFloat(c) / CGFloat(cols),
                    y: CGFloat(r) / CGFloat(rows),
                    width: 1.0 / CGFloat(cols),
                    height: 1.0 / CGFloat(rows)
                )
                layer.contentsGravity = .resize
                overlay.layer.addSublayer(layer)
                layers.append(layer)
            }
        }
        return layers
    }

    private static func makeRenderedNewTextLabel(frame: CGRect, capture: PreparedCapture, newText: String) -> UILabel {
        let label = UILabel(frame: frame)
        label.text = newText
        label.font = capture.font
        label.textColor = capture.textColor
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private static func buildNewTextWordLabels(in overlay: UIView, capture: PreparedCapture, newText: String) -> [UILabel] {
        let contentRect = overlay.bounds.insetBy(dx: 4, dy: 4)
        let words = newText.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard !words.isEmpty, words.count <= 36 else {
            let single = makeRenderedNewTextLabel(frame: contentRect, capture: capture, newText: newText)
            overlay.addSubview(single)
            return [single]
        }

        let font = capture.font
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        let lineHeight = font.lineHeight

        var cursorX: CGFloat = contentRect.minX
        var cursorY: CGFloat = contentRect.minY
        var labels: [UILabel] = []

        for word in words {
            let segments = word.components(separatedBy: "\n")
            for (segIdx, seg) in segments.enumerated() {
                if segIdx > 0 {
                    cursorX = contentRect.minX
                    cursorY += lineHeight
                }
                if !seg.isEmpty {
                    let size = (seg as NSString).size(withAttributes: [.font: font])
                    if cursorX > contentRect.minX, cursorX + size.width > contentRect.maxX {
                        cursorX = contentRect.minX
                        cursorY += lineHeight
                    }
                    if cursorY < contentRect.maxY {
                        let lbl = UILabel(frame: CGRect(x: cursorX, y: cursorY, width: min(size.width + 2, contentRect.width), height: lineHeight))
                        lbl.text = seg
                        lbl.font = font
                        lbl.textColor = capture.textColor
                        overlay.addSubview(lbl)
                        labels.append(lbl)
                    }
                    cursorX += size.width
                }
            }
            cursorX += spaceWidth
        }

        if labels.isEmpty {
            let single = makeRenderedNewTextLabel(frame: contentRect, capture: capture, newText: newText)
            overlay.addSubview(single)
            return [single]
        }
        return labels
    }

    private static func captureSnapshot(of view: UIView, rect: CGRect) -> UIImage? {
        let clamped = rect.intersection(view.bounds)
        guard !clamped.isNull, clamped.width > 1, clamped.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: clamped.size, format: format)
        return renderer.image { ctx in
            ctx.cgContext.translateBy(x: -clamped.origin.x, y: -clamped.origin.y)
            if !view.drawHierarchy(in: view.bounds, afterScreenUpdates: false) {
                view.layer.render(in: ctx.cgContext)
            }
        }
    }

    private static func sampleBackdropColor(from image: UIImage, fallbackView: UIView) -> UIColor {
        if let cg = image.cgImage,
           let data = cg.dataProvider?.data,
           let ptr = CFDataGetBytePtr(data)
        {
            let bpp = cg.bitsPerPixel / 8
            let bpr = cg.bytesPerRow
            if bpp >= 4, cg.width >= 2, cg.height >= 2 {
                let offsets = [0, (cg.height - 1) * bpr + (cg.width - 1) * bpp]
                for offset in offsets where offset + 3 < CFDataGetLength(data) {
                    let c0 = CGFloat(ptr[offset]) / 255.0
                    let c1 = CGFloat(ptr[offset + 1]) / 255.0
                    let c2 = CGFloat(ptr[offset + 2]) / 255.0
                    let c3 = CGFloat(ptr[offset + 3]) / 255.0
                    let alpha = cg.alphaInfo == .noneSkipFirst || cg.alphaInfo == .noneSkipLast ? 1.0 : c3
                    if alpha > 0.85 {
                        let isBGRA = cg.bitmapInfo.contains(.byteOrder32Little)
                        if isBGRA {
                            return UIColor(red: c2, green: c1, blue: c0, alpha: 1.0)
                        }
                        return UIColor(red: c0, green: c1, blue: c2, alpha: 1.0)
                    }
                }
            }
        }
        var current: UIView? = fallbackView
        while let v = current {
            if let bg = v.backgroundColor, bg != .clear {
                return bg
            }
            current = v.superview
        }
        return fallbackView.traitCollection.userInterfaceStyle == .dark ? .black : .systemBackground
    }

    private static func makeDustParticleCGImage(color: UIColor) -> CGImage? {
        let size = CGSize(width: 10, height: 10)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            color.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
        return img.cgImage
    }
}
