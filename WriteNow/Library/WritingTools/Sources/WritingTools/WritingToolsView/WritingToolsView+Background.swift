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
    private static let themeHexMap: [String: [String]] = [
        "midnight_ocean": ["#0EA5E9", "#2563EB", "#1E1B4B", "#0F172A"],
        "aurora_borealis": ["#10B981", "#06B6D4", "#6366F1", "#0B1120"],
        "sunset_amber": ["#F97316", "#EF4444", "#DB2777", "#1F1024"],
        "cyberpunk_neon": ["#06B6D4", "#D946EF", "#7C3AED", "#09091A"],
        "obsidian_minimal": ["#475569", "#334155", "#1E293B", "#09090B"],
        "apple_intelligence": ["#F86594", "#A855F7", "#3B82F6", "#181029"],
    ]

    var themeColors: [Color] {
        let s = cfg.settings
        if s.menuThemePreset == "custom_colors" {
            let parsed = s.customThemeColorsHex.compactMap { Self.color(fromHex: $0) }
            if parsed.count >= 2 { return parsed }
        }
        let hexes = Self.themeHexMap[s.menuThemePreset] ?? Self.themeHexMap["midnight_ocean"]!
        let parsed = hexes.compactMap { Self.color(fromHex: $0) }
        if !parsed.isEmpty { return parsed }
        return ColorfulPreset.appleIntelligence
            .colors
            .map { $0.withAlphaComponent(1.0) }
            .map { Color($0) }
    }

    @ViewBuilder
    var background: some View {
        let s = cfg.settings
        if s.backgroundMode == "image",
           let imgData = cfg.customBackgroundImageData,
           let uiImage = UIImage(data: imgData)
        {
            GeometryReader { geo in
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width + 128, height: geo.size.height + 128)
                    .clipped()
                    .blur(radius: CGFloat(s.backgroundImageBlur))
                    .overlay(Color.black.opacity(min(max(s.backgroundImageDim, 0.0), 0.90)))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .ignoresSafeArea()
            .background(Color.black)
            .padding(-64)
        } else if s.backgroundMode == "solid" {
            (Self.color(fromHex: s.solidBackgroundHex) ?? Color(red: 0.07, green: 0.09, blue: 0.14))
                .ignoresSafeArea()
                .padding(-64)
        } else if s.backgroundMode == "mesh" && s.animatedBackground {
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
                colors: themeColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.92)
            .ignoresSafeArea()
            .background(Color.black)
            .padding(-64)
        }
    }

    private static func color(fromHex hexString: String) -> Color? {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
