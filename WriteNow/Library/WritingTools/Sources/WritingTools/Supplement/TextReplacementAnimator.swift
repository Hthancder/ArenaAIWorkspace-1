//
//  TextReplacementAnimator.swift
//  WritingTools
//

import ColorfulX
import ColorVector
import QuartzCore
import UIKit

enum TextReplacementAnimator {
    struct PreparedSnapshot {
        let beforeImage: UIImage?
        let oldRectsInTarget: [CGRect]
        let targetBoundsAtCapture: CGRect
        let backdropColor: UIColor
    }

    struct Tile {
        let image: UIImage
        let frameInOverlay: CGRect
        let lineIndex: Int
    }

    static func prepareSnapshot(
        targetView: UIView,
        oldRectsInTarget: [CGRect],
        decorationViews: [UIView]
    ) -> PreparedSnapshot {
        let wasHidden = decorationViews.map(\.isHidden)
        decorationViews.forEach { $0.isHidden = true }
        let beforeImage = captureImage(of: targetView, afterScreenUpdates: false)
        for (view, hidden) in zip(decorationViews, wasHidden) {
            view.isHidden = hidden
        }

        let backdrop = sampleBackdropColor(
            from: beforeImage,
            targetView: targetView,
            avoidRects: oldRectsInTarget
        )

        return PreparedSnapshot(
            beforeImage: beforeImage,
            oldRectsInTarget: oldRectsInTarget,
            targetBoundsAtCapture: targetView.bounds,
            backdropColor: backdrop
        )
    }

    static func animate(
        style: String,
        targetView: UIView,
        prepared: PreparedSnapshot,
        newRectsInTarget: [CGRect],
        themeColors: [UIColor],
        accentHex: String
    ) {
        let normalizedStyle = style.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedStyle != "none", !normalizedStyle.isEmpty else { return }

        guard let hostView = targetView.window ?? targetView.superview ?? Optional(targetView) else {
            return
        }

        let afterImage = captureImage(of: targetView, afterScreenUpdates: true)
        let currentBounds = targetView.bounds

        let oldLines = mergeLineRects(prepared.oldRectsInTarget, visibleBounds: prepared.targetBoundsAtCapture)
        let resolvedNewSource = newRectsInTarget.isEmpty ? prepared.oldRectsInTarget : newRectsInTarget
        let newLines = mergeLineRects(resolvedNewSource, visibleBounds: currentBounds)

        guard !oldLines.isEmpty || !newLines.isEmpty else { return }

        let targetFrameInHost = targetView.convert(currentBounds, to: hostView)
        let overlayFrame = targetFrameInHost.intersection(hostView.bounds)
        guard !overlayFrame.isEmpty, overlayFrame.width > 12, overlayFrame.height > 12 else { return }

        let overlay = UIView(frame: overlayFrame)
        overlay.isUserInteractionEnabled = false
        overlay.clipsToBounds = !(targetView is UITextField)
        overlay.backgroundColor = .clear
        hostView.addSubview(overlay)

        func toOverlay(_ rectInTarget: CGRect, referenceBounds: CGRect) -> CGRect {
            let inHost = CGRect(
                x: targetFrameInHost.minX + (rectInTarget.minX - referenceBounds.minX),
                y: targetFrameInHost.minY + (rectInTarget.minY - referenceBounds.minY),
                width: rectInTarget.width,
                height: rectInTarget.height
            )
            return CGRect(
                x: inHost.minX - overlayFrame.minX,
                y: inHost.minY - overlayFrame.minY,
                width: inHost.width,
                height: inHost.height
            )
        }

        let oldOverlayLines = oldLines.map { toOverlay($0, referenceBounds: prepared.targetBoundsAtCapture) }
        let newOverlayLines = newLines.map { toOverlay($0, referenceBounds: currentBounds) }
        let allOverlayLines = oldOverlayLines + newOverlayLines

        // Build exact line-by-line veil covering 100% of old and new text lines
        let veilContainer = UIView(frame: overlay.bounds)
        veilContainer.backgroundColor = prepared.backdropColor
        veilContainer.alpha = 1

        let maskPath = UIBezierPath()
        for line in allOverlayLines {
            let padded = line.insetBy(dx: -3, dy: -2)
            maskPath.append(UIBezierPath(roundedRect: padded, cornerRadius: 5))
        }
        let maskLayer = CAShapeLayer()
        maskLayer.frame = veilContainer.bounds
        maskLayer.path = maskPath.cgPath
        veilContainer.layer.mask = maskLayer

        let resolvedTheme = themeColors.isEmpty
            ? [colorFromHex(accentHex) ?? .systemBlue, .systemPurple]
            : themeColors
        let accentColor = colorFromHex(accentHex) ?? resolvedTheme.first ?? .systemBlue

        let glowView = AnimatedMulticolorGradientView()
        glowView.frame = veilContainer.bounds
        glowView.speed = 1.35
        glowView.transitionSpeed = 5.0
        glowView.alpha = 0.24
        glowView.setColors(resolvedTheme.map { ColorVector($0) }, animated: false)
        veilContainer.addSubview(glowView)

        overlay.addSubview(veilContainer)

        let totalLinesCount = max(oldLines.count, newLines.count)
        let targetChunkWidth: CGFloat = totalLinesCount > 16 ? 76 : (totalLinesCount > 8 ? 52 : 36)

        let oldTiles = sliceLinesIntoTiles(
            image: prepared.beforeImage,
            linesInTarget: oldLines,
            linesInOverlay: oldOverlayLines,
            targetBounds: prepared.targetBoundsAtCapture,
            backdropColor: prepared.backdropColor,
            preferredChunkWidth: targetChunkWidth
        )
        let newTiles = sliceLinesIntoTiles(
            image: afterImage,
            linesInTarget: newLines,
            linesInOverlay: newOverlayLines,
            targetBounds: currentBounds,
            backdropColor: prepared.backdropColor,
            preferredChunkWidth: targetChunkWidth
        )

        // If snapshots produced no slices (e.g. offscreen/empty), fade glow gracefully
        guard !oldTiles.isEmpty || !newTiles.isEmpty else {
            cleanupOverlay(overlay: overlay, veil: veilContainer, after: 0.35)
            return
        }

        switch normalizedStyle {
        case "rain_drop_rise":
            runRainDropRise(
                overlay: overlay,
                veil: veilContainer,
                oldTiles: oldTiles,
                newTiles: newTiles
            )
        case "thanos_dust":
            runThanosDust(
                overlay: overlay,
                veil: veilContainer,
                oldLines: oldOverlayLines,
                oldTiles: oldTiles,
                newTiles: newTiles,
                accentColor: accentColor
            )
        case "typewriter_wave":
            runTypewriterWave(
                overlay: overlay,
                veil: veilContainer,
                oldLines: oldOverlayLines,
                newLines: newOverlayLines,
                oldTiles: oldTiles,
                newTiles: newTiles,
                accentColor: accentColor
            )
        case "flip_cascade":
            runFlipCascade(
                overlay: overlay,
                veil: veilContainer,
                oldTiles: oldTiles,
                newTiles: newTiles
            )
        case "glitch_matrix":
            runGlitchMatrix(
                overlay: overlay,
                veil: veilContainer,
                oldTiles: oldTiles,
                newTiles: newTiles,
                accentColor: accentColor
            )
        default: // "scatter_assemble"
            runScatterAssemble(
                overlay: overlay,
                veil: veilContainer,
                oldTiles: oldTiles,
                newTiles: newTiles
            )
        }
    }

    // MARK: - 1. Scatter & Assemble

    private static func runScatterAssemble(
        overlay: UIView,
        veil: UIView,
        oldTiles: [Tile],
        newTiles: [Tile]
    ) {
        for (idx, tile) in oldTiles.enumerated() {
            let iv = makeTileView(tile)
            overlay.addSubview(iv)
            let dx = CGFloat.random(in: -80 ... 80)
            let dy = CGFloat.random(in: -55 ... 55)
            let angle = CGFloat.random(in: -0.75 ... 0.75)
            let delay = min(0.18, Double(idx) * 0.004)
            UIView.animate(withDuration: 0.34, delay: delay, options: [.curveEaseOut]) {
                iv.transform = CGAffineTransform(translationX: dx, y: dy)
                    .rotated(by: angle)
                    .scaledBy(x: 0.45, y: 0.45)
                iv.alpha = 0
            }
        }

        for (idx, tile) in newTiles.enumerated() {
            let iv = makeTileView(tile)
            let sx = CGFloat.random(in: -75 ... 75)
            let sy = CGFloat.random(in: -50 ... 50)
            let angle = CGFloat.random(in: -0.55 ... 0.55)
            iv.transform = CGAffineTransform(translationX: sx, y: sy)
                .rotated(by: angle)
                .scaledBy(x: 1.25, y: 1.25)
            iv.alpha = 0
            overlay.addSubview(iv)

            let delay = 0.14 + min(0.24, Double(idx) * 0.005)
            UIView.animate(
                withDuration: 0.46,
                delay: delay,
                usingSpringWithDamping: 0.78,
                initialSpringVelocity: 0.75,
                options: [.curveEaseOut]
            ) {
                iv.transform = .identity
                iv.alpha = 1
            }
        }

        cleanupOverlay(overlay: overlay, veil: veil, after: 0.80)
    }

    // MARK: - 2. Gravity Fall & Sprout

    private static func runRainDropRise(
        overlay: UIView,
        veil: UIView,
        oldTiles: [Tile],
        newTiles: [Tile]
    ) {
        for (idx, tile) in oldTiles.enumerated() {
            let iv = makeTileView(tile)
            overlay.addSubview(iv)
            let dropY = CGFloat.random(in: 36 ... 86)
            let driftX = CGFloat.random(in: -14 ... 14)
            let tilt = CGFloat.random(in: -0.35 ... 0.35)
            let delay = min(0.22, Double(tile.lineIndex) * 0.028 + Double(idx % 6) * 0.005)
            UIView.animate(withDuration: 0.34, delay: delay, options: [.curveEaseIn]) {
                iv.transform = CGAffineTransform(translationX: driftX, y: dropY)
                    .rotated(by: tilt)
                iv.alpha = 0
            }
        }

        for (idx, tile) in newTiles.enumerated() {
            let iv = makeTileView(tile)
            iv.transform = CGAffineTransform(translationX: 0, y: 20).scaledBy(x: 0.92, y: 0.35)
            iv.alpha = 0
            overlay.addSubview(iv)

            let delay = 0.18 + min(0.26, Double(tile.lineIndex) * 0.03 + Double(idx % 6) * 0.006)
            UIView.animate(
                withDuration: 0.44,
                delay: delay,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0.85,
                options: [.curveEaseOut]
            ) {
                iv.transform = .identity
                iv.alpha = 1
            }
        }

        cleanupOverlay(overlay: overlay, veil: veil, after: 0.84)
    }

    // MARK: - 3. Ash & Dust

    private static func runThanosDust(
        overlay: UIView,
        veil: UIView,
        oldLines: [CGRect],
        oldTiles: [Tile],
        newTiles: [Tile],
        accentColor: UIColor
    ) {
        let dustBounds = oldLines.reduce(oldLines.first ?? overlay.bounds) { $0.union($1) }
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: dustBounds.midX, y: dustBounds.midY)
        emitter.emitterSize = CGSize(width: max(40, dustBounds.width), height: max(20, dustBounds.height))
        emitter.emitterShape = .rectangle
        emitter.renderMode = .unordered

        let dotImage = makeDustParticleImage()
        let ashCell = CAEmitterCell()
        ashCell.contents = dotImage
        ashCell.birthRate = min(240, Float(max(80, oldLines.count * 26)))
        ashCell.lifetime = 0.72
        ashCell.velocity = 44
        ashCell.velocityRange = 28
        ashCell.emissionLongitude = -CGFloat.pi / 4
        ashCell.emissionRange = CGFloat.pi / 2
        ashCell.yAcceleration = -60
        ashCell.xAcceleration = 48
        ashCell.scale = 0.32
        ashCell.scaleRange = 0.22
        ashCell.alphaSpeed = -1.4
        ashCell.color = UIColor.lightGray.cgColor

        let emberCell = CAEmitterCell()
        emberCell.contents = dotImage
        emberCell.birthRate = min(110, Float(max(35, oldLines.count * 12)))
        emberCell.lifetime = 0.62
        emberCell.velocity = 50
        emberCell.velocityRange = 26
        emberCell.emissionLongitude = -CGFloat.pi / 3
        emberCell.emissionRange = CGFloat.pi / 2
        emberCell.yAcceleration = -75
        emberCell.xAcceleration = 56
        emberCell.scale = 0.26
        emberCell.scaleRange = 0.18
        emberCell.alphaSpeed = -1.55
        emberCell.color = accentColor.cgColor

        emitter.emitterCells = [ashCell, emberCell]
        overlay.layer.addSublayer(emitter)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            emitter.birthRate = 0
        }

        let oldCount = max(1, oldTiles.count)
        for (idx, tile) in oldTiles.enumerated() {
            let iv = makeTileView(tile)
            overlay.addSubview(iv)
            let progressDelay = Double(idx) / Double(oldCount) * 0.26
            let driftX = CGFloat.random(in: 16 ... 58)
            let driftY = CGFloat.random(in: -38 ... -8)
            UIView.animate(withDuration: 0.36, delay: progressDelay, options: [.curveEaseOut]) {
                iv.transform = CGAffineTransform(translationX: driftX, y: driftY)
                    .scaledBy(x: 0.35, y: 0.35)
                iv.alpha = 0
            }
        }

        let newCount = max(1, newTiles.count)
        for (idx, tile) in newTiles.enumerated() {
            let iv = makeTileView(tile)
            iv.transform = CGAffineTransform(translationX: -8, y: 10).scaledBy(x: 0.84, y: 0.84)
            iv.alpha = 0
            overlay.addSubview(iv)
            let delay = 0.24 + (Double(idx) / Double(newCount)) * 0.24
            UIView.animate(withDuration: 0.38, delay: delay, options: [.curveEaseOut]) {
                iv.transform = .identity
                iv.alpha = 1
            }
        }

        cleanupOverlay(overlay: overlay, veil: veil, after: 0.88)
    }

    // MARK: - 4. Apple Intelligence / Luminous Wave

    private static func runTypewriterWave(
        overlay: UIView,
        veil: UIView,
        oldLines: [CGRect],
        newLines: [CGRect],
        oldTiles: [Tile],
        newTiles: [Tile],
        accentColor: UIColor
    ) {
        let unionBounds = (oldLines + newLines).reduce(overlay.bounds) { acc, r in
            acc == overlay.bounds ? r : acc.union(r)
        }

        let oldCount = max(1, oldTiles.count)
        for (idx, tile) in oldTiles.enumerated() {
            let iv = makeTileView(tile)
            overlay.addSubview(iv)
            let delay = (Double(idx) / Double(oldCount)) * 0.22
            UIView.animate(withDuration: 0.20, delay: delay, options: [.curveEaseIn]) {
                iv.alpha = 0
                iv.transform = CGAffineTransform(translationX: 0, y: -4).scaledBy(x: 0.96, y: 0.96)
            }
        }

        // Luminous horizontal sweep bar moving top-to-bottom across ALL lines
        let beamHeight: CGFloat = 28
        let beam = UIView(frame: CGRect(
            x: unionBounds.minX - 6,
            y: unionBounds.minY - beamHeight * 0.5,
            width: unionBounds.width + 12,
            height: beamHeight
        ))
        let beamGrad = CAGradientLayer()
        beamGrad.frame = beam.bounds
        beamGrad.colors = [
            accentColor.withAlphaComponent(0).cgColor,
            accentColor.withAlphaComponent(0.55).cgColor,
            UIColor.white.withAlphaComponent(0.65).cgColor,
            accentColor.withAlphaComponent(0).cgColor,
        ]
        beamGrad.startPoint = CGPoint(x: 0.5, y: 0)
        beamGrad.endPoint = CGPoint(x: 0.5, y: 1)
        beam.layer.addSublayer(beamGrad)
        overlay.addSubview(beam)

        UIView.animate(withDuration: 0.52, delay: 0.04, options: [.curveEaseInOut]) {
            beam.frame.origin.y = unionBounds.maxY - beamHeight * 0.5
        } completion: { _ in
            UIView.animate(withDuration: 0.14) { beam.alpha = 0 }
        }

        let newCount = max(1, newTiles.count)
        for (idx, tile) in newTiles.enumerated() {
            let iv = makeTileView(tile)
            iv.transform = CGAffineTransform(translationX: 0, y: 8).scaledBy(x: 0.96, y: 0.96)
            iv.alpha = 0
            overlay.addSubview(iv)
            let delay = 0.10 + (Double(idx) / Double(newCount)) * 0.34
            UIView.animate(
                withDuration: 0.32,
                delay: delay,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0.5,
                options: [.curveEaseOut]
            ) {
                iv.transform = .identity
                iv.alpha = 1
            }
        }

        cleanupOverlay(overlay: overlay, veil: veil, after: 0.78)
    }

    // MARK: - 5. 3D Flip Cascade

    private static func runFlipCascade(
        overlay: UIView,
        veil: UIView,
        oldTiles: [Tile],
        newTiles: [Tile]
    ) {
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 450.0

        let oldCount = max(1, oldTiles.count)
        for (idx, tile) in oldTiles.enumerated() {
            let iv = makeTileView(tile)
            iv.layer.transform = perspective
            overlay.addSubview(iv)
            let delay = (Double(idx) / Double(oldCount)) * 0.18
            UIView.animate(withDuration: 0.20, delay: delay, options: [.curveEaseIn]) {
                iv.layer.transform = CATransform3DRotate(perspective, .pi / 2.0, 1, 0, 0)
                iv.alpha = 0
            }
        }

        let newCount = max(1, newTiles.count)
        for (idx, tile) in newTiles.enumerated() {
            let iv = makeTileView(tile)
            iv.layer.transform = CATransform3DRotate(perspective, -.pi / 2.0, 1, 0, 0)
            iv.alpha = 0
            overlay.addSubview(iv)
            let delay = 0.16 + (Double(idx) / Double(newCount)) * 0.22
            UIView.animate(
                withDuration: 0.32,
                delay: delay,
                usingSpringWithDamping: 0.76,
                initialSpringVelocity: 0.6,
                options: [.curveEaseOut]
            ) {
                iv.layer.transform = perspective
                iv.alpha = 1
            }
        }

        cleanupOverlay(overlay: overlay, veil: veil, after: 0.74)
    }

    // MARK: - 6. Glitch Matrix (Real Chromatic Slice Split)

    private static func runGlitchMatrix(
        overlay: UIView,
        veil: UIView,
        oldTiles: [Tile],
        newTiles: [Tile],
        accentColor: UIColor
    ) {
        var oldViews: [UIImageView] = []
        var cyanViews: [UIImageView] = []
        var accentViews: [UIImageView] = []

        for tile in oldTiles {
            let main = makeTileView(tile)
            let cyan = UIImageView(image: tile.image.withRenderingMode(.alwaysTemplate))
            cyan.tintColor = UIColor.cyan.withAlphaComponent(0.75)
            cyan.frame = tile.frameInOverlay.offsetBy(dx: -3, dy: 0)
            cyan.contentMode = .scaleToFill

            let acc = UIImageView(image: tile.image.withRenderingMode(.alwaysTemplate))
            acc.tintColor = accentColor.withAlphaComponent(0.75)
            acc.frame = tile.frameInOverlay.offsetBy(dx: 3, dy: 0)
            acc.contentMode = .scaleToFill

            overlay.addSubview(cyan)
            overlay.addSubview(acc)
            overlay.addSubview(main)
            oldViews.append(main)
            cyanViews.append(cyan)
            accentViews.append(acc)
        }

        var newViews: [UIImageView] = []
        for tile in newTiles {
            let iv = makeTileView(tile)
            iv.alpha = 0
            overlay.addSubview(iv)
            newViews.append(iv)
        }

        UIView.animate(withDuration: 0.09) {
            for (idx, v) in oldViews.enumerated() {
                let shift = (idx % 2 == 0) ? 5.0 : -5.0
                v.transform = CGAffineTransform(translationX: shift, y: 0)
            }
            for (idx, v) in cyanViews.enumerated() {
                v.transform = CGAffineTransform(translationX: (idx % 2 == 0) ? -7 : 6, y: -1)
            }
            for (idx, v) in accentViews.enumerated() {
                v.transform = CGAffineTransform(translationX: (idx % 2 == 0) ? 7 : -6, y: 1)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            UIView.animate(withDuration: 0.12) {
                oldViews.forEach { $0.alpha = 0 }
                cyanViews.forEach { $0.alpha = 0 }
                accentViews.forEach { $0.alpha = 0 }
            }
            for (idx, iv) in newViews.enumerated() {
                let jitterX: CGFloat = (idx % 2 == 0) ? -4 : 4
                iv.transform = CGAffineTransform(translationX: jitterX, y: 0)
                UIView.animate(withDuration: 0.22, delay: Double(idx % 5) * 0.015, options: [.curveEaseOut]) {
                    iv.transform = .identity
                    iv.alpha = 1
                }
            }
        }

        cleanupOverlay(overlay: overlay, veil: veil, after: 0.58)
    }

    // MARK: - Snapshot & Pixel Slicing Helpers

    private static func captureImage(of view: UIView, afterScreenUpdates: Bool) -> UIImage? {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = view.window?.screen.scale ?? UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        return renderer.image { ctx in
            if !view.drawHierarchy(in: bounds, afterScreenUpdates: afterScreenUpdates) {
                view.layer.render(in: ctx.cgContext)
            }
        }
    }

    private static func mergeLineRects(_ rects: [CGRect], visibleBounds: CGRect) -> [CGRect] {
        let expandedVisible = visibleBounds.insetBy(dx: -4, dy: -4)
        let valid = rects
            .map { $0.intersection(expandedVisible) }
            .filter { !$0.isEmpty && $0.width > 1.5 && $0.height > 2 }
            .sorted { $0.minY < $1.minY }

        var lines: [CGRect] = []
        for rect in valid {
            if let lastIdx = lines.indices.last {
                let last = lines[lastIdx]
                let overlapY = min(last.maxY, rect.maxY) - max(last.minY, rect.minY)
                let minH = min(last.height, rect.height)
                if overlapY > minH * 0.45 || abs(last.midY - rect.midY) < max(6, minH * 0.4) {
                    lines[lastIdx] = last.union(rect)
                    continue
                }
            }
            lines.append(rect)
        }

        return lines.map { $0.insetBy(dx: -2, dy: -1.5).intersection(visibleBounds) }
            .filter { !$0.isEmpty && $0.width > 2 && $0.height > 2 }
    }

    private static func sliceLinesIntoTiles(
        image: UIImage?,
        linesInTarget: [CGRect],
        linesInOverlay: [CGRect],
        targetBounds: CGRect,
        backdropColor: UIColor,
        preferredChunkWidth: CGFloat
    ) -> [Tile] {
        guard let image, let cgImage = image.cgImage else { return [] }
        let scale = image.scale
        let imgW = cgImage.width
        let imgH = cgImage.height

        var bgR: CGFloat = 0
        var bgG: CGFloat = 0
        var bgB: CGFloat = 0
        var bgA: CGFloat = 1
        backdropColor.getRed(&bgR, green: &bgG, blue: &bgB, alpha: &bgA)
        let bgRGB = (UInt8(clamping: Int(bgR * 255)), UInt8(clamping: Int(bgG * 255)), UInt8(clamping: Int(bgB * 255)))

        var tiles: [Tile] = []

        for (lineIdx, (rectTarget, rectOverlay)) in zip(linesInTarget, linesInOverlay).enumerated() {
            let localX = rectTarget.minX - targetBounds.minX
            let localY = rectTarget.minY - targetBounds.minY
            let pixelRect = CGRect(
                x: max(0, floor(localX * scale)),
                y: max(0, floor(localY * scale)),
                width: min(CGFloat(imgW) - max(0, floor(localX * scale)), ceil(rectTarget.width * scale)),
                height: min(CGFloat(imgH) - max(0, floor(localY * scale)), ceil(rectTarget.height * scale))
            )
            guard pixelRect.width >= 2, pixelRect.height >= 2,
                  let lineCG = cgImage.cropping(to: pixelRect)
            else { continue }

            let keyed = extractGlyphsAndFindGaps(
                from: lineCG,
                bgRGB: bgRGB,
                scale: scale,
                preferredChunkWidthPt: preferredChunkWidth
            )

            if keyed.splitPointsPt.isEmpty {
                let tileImg = UIImage(cgImage: keyed.image, scale: scale, orientation: .up)
                tiles.append(Tile(image: tileImg, frameInOverlay: rectOverlay, lineIndex: lineIdx))
                continue
            }

            let boundariesPt = [CGFloat(0)] + keyed.splitPointsPt + [rectTarget.width]
            for i in 0 ..< (boundariesPt.count - 1) {
                let startPt = boundariesPt[i]
                let endPt = boundariesPt[i + 1]
                let chunkWidthPt = endPt - startPt
                guard chunkWidthPt >= 2 else { continue }

                let pxX = max(0, Int(floor(startPt * scale)))
                let pxW = min(keyed.image.width - pxX, Int(ceil(chunkWidthPt * scale)))
                guard pxW >= 2,
                      let chunkCG = keyed.image.cropping(to: CGRect(x: pxX, y: 0, width: pxW, height: keyed.image.height))
                else { continue }

                let tileFrame = CGRect(
                    x: rectOverlay.minX + startPt,
                    y: rectOverlay.minY,
                    width: chunkWidthPt,
                    height: rectOverlay.height
                )
                let tileImg = UIImage(cgImage: chunkCG, scale: scale, orientation: .up)
                tiles.append(Tile(image: tileImg, frameInOverlay: tileFrame, lineIndex: lineIdx))
            }
        }

        return tiles
    }

    private static func extractGlyphsAndFindGaps(
        from cgImage: CGImage,
        bgRGB: (UInt8, UInt8, UInt8),
        scale: CGFloat,
        preferredChunkWidthPt: CGFloat
    ) -> (image: CGImage, splitPointsPt: [CGFloat]) {
        let w = cgImage.width
        let h = cgImage.height
        let bytesPerRow = w * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * h)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: &buffer,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return (cgImage, uniformSplits(widthPt: CGFloat(w) / scale, chunkPt: preferredChunkWidthPt))
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var nonBgPixels = 0
        var columnHasInk = [Bool](repeating: false, count: w)

        for y in 0 ..< h {
            let rowOffset = y * bytesPerRow
            for x in 0 ..< w {
                let idx = rowOffset + x * 4
                let r = buffer[idx]
                let g = buffer[idx + 1]
                let b = buffer[idx + 2]
                let a = buffer[idx + 3]

                guard a > 4 else { continue }
                let dr = abs(Int(r) - Int(bgRGB.0))
                let dg = abs(Int(g) - Int(bgRGB.1))
                let db = abs(Int(b) - Int(bgRGB.2))
                let diff = max(dr, max(dg, db))

                if diff > 14 {
                    nonBgPixels += 1
                    columnHasInk[x] = true
                }
            }
        }

        let totalPixels = max(1, w * h)
        let inkRatio = Double(nonBgPixels) / Double(totalPixels)

        // Only alpha-key when background is reasonably uniform (< 78% non-background pixels)
        if inkRatio < 0.78 {
            for y in 0 ..< h {
                let rowOffset = y * bytesPerRow
                for x in 0 ..< w {
                    let idx = rowOffset + x * 4
                    let r = Int(buffer[idx])
                    let g = Int(buffer[idx + 1])
                    let b = Int(buffer[idx + 2])
                    let a = Int(buffer[idx + 3])
                    guard a > 0 else { continue }

                    let diff = max(abs(r - Int(bgRGB.0)), max(abs(g - Int(bgRGB.1)), abs(b - Int(bgRGB.2))))
                    if diff <= 10 {
                        buffer[idx] = 0
                        buffer[idx + 1] = 0
                        buffer[idx + 2] = 0
                        buffer[idx + 3] = 0
                    } else if diff < 42 {
                        let newAlpha = (diff - 10) * 255 / 32
                        let clamped = max(0, min(255, newAlpha))
                        buffer[idx] = UInt8((r * clamped) / 255)
                        buffer[idx + 1] = UInt8((g * clamped) / 255)
                        buffer[idx + 2] = UInt8((b * clamped) / 255)
                        buffer[idx + 3] = UInt8(clamped)
                    }
                }
            }
        }

        let outImage = ctx.makeImage() ?? cgImage

        // Find clean word-gap split points near preferred chunk width
        let widthPt = CGFloat(w) / scale
        var splits: [CGFloat] = []
        let chunkPx = max(16, Int(preferredChunkWidthPt * scale))
        let searchRadiusPx = max(8, Int(12 * scale))
        var cursorPx = chunkPx
        let minTrailingPx = max(12, Int(14 * scale))

        while cursorPx < w - minTrailingPx {
            var chosenPx = cursorPx
            let lo = max(10, cursorPx - searchRadiusPx)
            let hi = min(w - 10, cursorPx + searchRadiusPx)
            var bestDist = Int.max
            for x in lo ... hi where !columnHasInk[x] {
                let dist = abs(x - cursorPx)
                if dist < bestDist {
                    bestDist = dist
                    chosenPx = x
                }
            }
            let pt = CGFloat(chosenPx) / scale
            if let last = splits.last {
                if pt - last >= 10 {
                    splits.append(pt)
                }
            } else if pt >= 10, widthPt - pt >= 10 {
                splits.append(pt)
            }
            cursorPx = chosenPx + chunkPx
        }

        return (outImage, splits)
    }

    private static func uniformSplits(widthPt: CGFloat, chunkPt: CGFloat) -> [CGFloat] {
        var splits: [CGFloat] = []
        var x = chunkPt
        while x < widthPt - 12 {
            splits.append(x)
            x += chunkPt
        }
        return splits
    }

    private static func makeTileView(_ tile: Tile) -> UIImageView {
        let iv = UIImageView(frame: tile.frameInOverlay)
        iv.image = tile.image
        iv.contentMode = .scaleToFill
        return iv
    }

    private static func cleanupOverlay(overlay: UIView, veil: UIView, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            UIView.animate(withDuration: 0.16) {
                veil.alpha = 0
                overlay.alpha = 0
            } completion: { _ in
                overlay.removeFromSuperview()
            }
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

    private static func sampleBackdropColor(
        from image: UIImage?,
        targetView: UIView,
        avoidRects: [CGRect]
    ) -> UIColor {
        if let cg = image?.cgImage {
            let w = cg.width
            let h = cg.height
            if w > 8, h > 8 {
                let scale = image?.scale ?? 1
                let candidatePts: [CGPoint] = [
                    CGPoint(x: 4, y: 4),
                    CGPoint(x: targetView.bounds.width - 6, y: 4),
                    CGPoint(x: 4, y: targetView.bounds.height - 6),
                    CGPoint(x: targetView.bounds.width - 6, y: targetView.bounds.height - 6),
                    CGPoint(x: 4, y: targetView.bounds.height * 0.5),
                ]
                var rgba = [UInt8](repeating: 0, count: 4)
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

                for pt in candidatePts {
                    if avoidRects.contains(where: { $0.insetBy(dx: -2, dy: -2).contains(pt) }) {
                        continue
                    }
                    let px = min(w - 1, max(0, Int(pt.x * scale)))
                    let py = min(h - 1, max(0, Int(pt.y * scale)))
                    guard let pixelCG = cg.cropping(to: CGRect(x: px, y: py, width: 1, height: 1)),
                          let ctx = CGContext(
                              data: &rgba,
                              width: 1,
                              height: 1,
                              bitsPerComponent: 8,
                              bytesPerRow: 4,
                              space: colorSpace,
                              bitmapInfo: bitmapInfo
                          )
                    else { continue }
                    ctx.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
                    ctx.draw(pixelCG, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                    if rgba[3] > 200 {
                        return UIColor(
                            red: CGFloat(rgba[0]) / 255.0,
                            green: CGFloat(rgba[1]) / 255.0,
                            blue: CGFloat(rgba[2]) / 255.0,
                            alpha: 1.0
                        )
                    }
                }
            }
        }
        return resolveBackdropColor(from: targetView)
    }

    private static func resolveBackdropColor(from view: UIView) -> UIColor {
        var current: UIView? = view
        for _ in 0 ..< 6 {
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
