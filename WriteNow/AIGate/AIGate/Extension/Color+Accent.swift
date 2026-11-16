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
        UIColor(hexString: Configuration.shared.appSettings.accentColorHex)
            ?? UIColor(red: 59.0 / 255.0, green: 130.0 / 255.0, blue: 246.0 / 255.0, alpha: 1.0)
    }

    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else {
            return nil
        }
        if hex.count == 6 {
            let r = CGFloat((value >> 16) & 0xFF) / 255.0
            let g = CGFloat((value >> 8) & 0xFF) / 255.0
            let b = CGFloat(value & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b, alpha: 1.0)
        } else {
            let r = CGFloat((value >> 24) & 0xFF) / 255.0
            let g = CGFloat((value >> 16) & 0xFF) / 255.0
            let b = CGFloat((value >> 8) & 0xFF) / 255.0
            let a = CGFloat(value & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b, alpha: a)
        }
    }

    var hexRGBString: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int(round(min(max(r, 0), 1) * 255)),
            Int(round(min(max(g, 0), 1) * 255)),
            Int(round(min(max(b, 0), 1) * 255))
        )
    }
}

extension Color {
    static var accent: Color {
        Color(uiColor: UIColor.accent)
    }

    init(hexString: String, fallback: Color = .blue) {
        if let ui = UIColor(hexString: hexString) {
            self.init(uiColor: ui)
        } else {
            self = fallback
        }
    }

    var hexRGBString: String {
        UIColor(self).hexRGBString
    }
}
