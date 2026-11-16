//
//  WritingToolsView+Background.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/8.
//

import ColorfulX
import Foundation
import SwiftUI

extension WritingToolsView {
    var color: [Color] {
        ColorfulPreset.appleIntelligence
            .colors
            .map { $0.withAlphaComponent(1.0) }
            .map { Color($0) }
    }

    @ViewBuilder
    var background: some View {
        if cfg.settings.animatedBackground {
            ColorfulView(
                color: .constant(color),
                speed: .constant(0.25),
                bias: .constant(0.01),
                noise: .constant(0),
                transitionSpeed: .constant(1.3),
                frameLimit: .constant(30),
                renderScale: .constant(0.5)
            )
            .opacity(0.75)
            .ignoresSafeArea()
            .background(.black)
            .padding(-64)
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.10, blue: 0.22),
                    Color(red: 0.06, green: 0.06, blue: 0.11),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .padding(-64)
        }
    }
}
