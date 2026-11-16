//
//  WritingToolsView+Background.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/8.
//

import ColorfulX
import Foundation
import SwiftUI
import UIKit

extension WritingToolsView {
    var themeColors: [Color] {
        switch cfg.settings.menuThemePreset {
        case "midnightBlue":
            return [
                Color(wtHex: "#0F172A"),
                Color(wtHex: "#1E3A8A"),
                Color(wtHex: "#0284C7"),
                Color(wtHex: "#0EA5E9"),
            ]
        case "emeraldForest":
            return [
                Color(wtHex: "#022C22"),
                Color(wtHex: "#065F46"),
                Color(wtHex: "#10B981"),
                Color(wtHex: "#0D9488"),
            ]
        case "sunsetAmber":
            return [
                Color(wtHex: "#451A03"),
                Color(wtHex: "#C2410C"),
                Color(wtHex: "#F59E0B"),
                Color(wtHex: "#EA580C"),
            ]
        case "obsidianMono":
            return [
                Color(wtHex: "#09090B"),
                Color(wtHex: "#18181B"),
                Color(wtHex: "#27272A"),
                Color(wtHex: "#3F3F46"),
            ]
        case "sakuraBlossom":
            return [
                Color(wtHex: "#4C0519"),
                Color(wtHex: "#BE185D"),
                Color(wtHex: "#EC4899"),
                Color(wtHex: "#9333EA"),
            ]
        case "cyberNeon":
            return [
                Color(wtHex: "#1E1B4B"),
                Color(wtHex: "#4338CA"),
                Color(wtHex: "#06B6D4"),
                Color(wtHex: "#22C55E"),
            ]
        case "customColor":
            let c1 = Color(wtHex: cfg.settings.menuCustomColorHex1, fallback: Color(wtHex: "#1E3A8A"))
            let c2 = Color(wtHex: cfg.settings.menuCustomColorHex2, fallback: Color(wtHex: "#0F172A"))
            return [c1, c2, c1.opacity(0.85), c2.opacity(0.95)]
        default:
            return ColorfulPreset.appleIntelligence
                .colors
                .map { $0.withAlphaComponent(1.0) }
                .map { Color($0) }
        }
    }

    @ViewBuilder
    var background: some View {
        if cfg.settings.menuThemePreset == "customImage", let bgImage = cfg.customBackgroundImage {
            ZStack {
                Color.black
                GeometryReader { geo in
                    Image(uiImage: bgImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: CGFloat(max(0, cfg.settings.menuBgImageBlur)))
                }
                Color.black.opacity(min(max(cfg.settings.menuBgImageDim, 0.05), 0.90))
            }
            .ignoresSafeArea()
            .padding(-64)
        } else if cfg.settings.animatedBackground {
            ColorfulView(
                color: .constant(themeColors),
                speed: .constant(0.25),
                bias: .constant(0.01),
                noise: .constant(0),
                transitionSpeed: .constant(1.3),
                frameLimit: .constant(30),
                renderScale: .constant(0.5)
            )
            .opacity(0.82)
            .ignoresSafeArea()
            .background(.black)
            .padding(-64)
        } else {
            LinearGradient(
                colors: Array(themeColors.prefix(3)),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.92)
            .ignoresSafeArea()
            .background(.black)
            .padding(-64)
        }
    }
}

private extension Color {
    init(wtHex: String, fallback: Color = .blue) {
        var hex = wtHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else {
            self = fallback
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
