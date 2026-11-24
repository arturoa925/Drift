//
//  TeslaStyle.swift
//  Dritft
//
//  Visual tokens for Drift's "instrument cluster" look, inspired by Tesla's
//  FSD visualization and UI: a near-black graphite canvas, crisp thin
//  lines, restrained greys, and one electric-blue accent for "this is you /
//  this is where you're going." The weather/time gradient is kept, but as
//  a horizon glow (see `TeslaBackdrop`) rather than the whole canvas.
//

import SwiftUI

enum TeslaStyle {
    // MARK: Canvas
    /// Deepest background, the "ground" the world sits on.
    static let canvasTop = Color(hex: "0A0B0D")
    static let canvasBottom = Color(hex: "14171B")

    // MARK: Geometry
    /// Asphalt fill, drawn at per-class opacity over the canvas.
    static let asphalt = Color(hex: "2A2E35")
    /// Lane lines and road edges.
    static let laneLine = Color(hex: "E8EBF0")
    /// Buildings: neutral cool grey, like FSD's rendered structures.
    static let structure = Color(hex: "C9CFD8")
    static let structureCommercial = Color(hex: "D9D3C4")
    static let structureOther = Color(hex: "B9C6D6")
    /// Dim window glow (used sparingly).
    static let windowLit = Color(hex: "E9ECF2")

    // MARK: Accent
    /// Tesla-style electric blue — the path ribbon and ego marker.
    static let accent = Color(hex: "3E6AE1")
    static let accentGlow = Color(hex: "6C9BFF")

    // MARK: Text
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.52)
    static let textTertiary = Color.white.opacity(0.32)

    // MARK: Glass
    static let glassFill = Color.white.opacity(0.07)
    static let glassStroke = Color.white.opacity(0.10)
}

/// Dark frosted-glass container used for every floating control —
/// replaces the old light "pill" with Tesla's flat, low-contrast tile.
struct TeslaGlass: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(TeslaStyle.glassFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(TeslaStyle.glassStroke, lineWidth: 0.5)
                    )
            )
    }
}

extension View {
    func teslaGlass(cornerRadius: CGFloat = 18) -> some View {
        modifier(TeslaGlass(cornerRadius: cornerRadius))
    }
}
