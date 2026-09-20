//
//  ColorAndTheme.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import SwiftUI

extension Color {
    /// Builds a `Color` from a 6-digit hex string, with or without a
    /// leading `#` (e.g. `"#6D28D9"` or `"6D28D9"`). Used by `ThemeEngine`
    /// to turn the hex values from the gradient tables in claude.md into
    /// actual gradient stops.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)

        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255

        self.init(red: r, green: g, blue: b)
    }
}
