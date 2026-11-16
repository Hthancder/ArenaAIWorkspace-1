//
//  Color+Accent.swift
//  AIGate
//
//  Created by Lessica on 2024/8/20.
//

import SwiftUI
import UIKit

extension UIColor {
    static var accent: UIColor {
        UIColor(hexString: Configuration.cachedAccentHex)
            ?? UIColor(red: 59.0 / 255, green: 130.0 / 255, blue: 246.0 / 255, alpha: 1)
    }
}

extension Color {
    static var accent: Color {
        Color(uiColor: UIColor.accent)
    }
}
