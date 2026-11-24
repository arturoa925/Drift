//
//  SimLighting.swift
//  Dritft
//
//  A tiny lighting model so the world reads like a sim instead of a
//  diagram: the sun sits where it really would for the time of day (east
//  at sunrise, south at midday, west at sunset), faces turn lighter or
//  darker depending on which way they point, shadows fall away from the
//  sun, and overcast weather flattens everything. It only affects how
//  geometry is shaded — the sky gradient and its themes come from
//  `ThemeEngine` and are untouched.
//

import SwiftUI

struct SimLighting {
    /// Unit vector (east, north) pointing from the world toward the sun.
    let sunDirection: Vector2
    /// How high the sun is, 0...1 — scales how bright roofs and the ground get.
    let sunElevation: Double
    /// Light that reaches every surface regardless of facing.
    let ambient: Double
    /// Extra light on surfaces facing the sun.
    let intensity: Double
    /// Color cast of the light (warm at sunrise/sunset, cool at night).
    let tint: (r: Double, g: Double, b: Double)
    /// Shadow length per meter of building height; 0 means no shadows.
    let shadowRatio: Double
    let shadowOpacity: Double
    /// Fraction of windows that glow, and how strongly.
    let litWindowProbability: Double
    let litWindowOpacity: Double

    init(timeOfDay: TimeOfDayCondition, weather: WeatherCondition) {
        // Strong weather overrides time of day, same as the theme does.
        if weather != .sunny {
            let storm = weather == .storm
            sunDirection = Self.unit(0, -1)
            sunElevation = 0.6
            ambient = storm ? 0.46 : 0.60
            intensity = 0.10
            tint = (0.86, 0.90, 0.95)
            shadowRatio = 0
            shadowOpacity = 0
            litWindowProbability = storm ? 0.35 : 0.18
            litWindowOpacity = 0.75
            return
        }
        switch timeOfDay {
        case .sunrise:
            sunDirection = Self.unit(0.97, 0.24)
            sunElevation = 0.55
            ambient = 0.42
            intensity = 0.75
            tint = (1.0, 0.80, 0.64)
            shadowRatio = 1.8
            shadowOpacity = 0.26
            litWindowProbability = 0.22
            litWindowOpacity = 0.8
        case .midday:
            sunDirection = Self.unit(0, -1)
            sunElevation = 1.0
            ambient = 0.52
            intensity = 0.55
            tint = (1.0, 0.98, 0.95)
            shadowRatio = 0.5
            shadowOpacity = 0.30
            litWindowProbability = 0.05
            litWindowOpacity = 0.6
        case .sunset:
            sunDirection = Self.unit(-0.97, 0.24)
            sunElevation = 0.5
            ambient = 0.40
            intensity = 0.72
            tint = (1.0, 0.66, 0.48)
            shadowRatio = 2.0
            shadowOpacity = 0.30
            litWindowProbability = 0.32
            litWindowOpacity = 0.85
        case .night:
            sunDirection = Self.unit(-0.5, -0.85)
            sunElevation = 0.4
            ambient = 0.26
            intensity = 0.12
            tint = (0.64, 0.74, 1.0)
            shadowRatio = 0
            shadowOpacity = 0
            litWindowProbability = 0.5
            litWindowOpacity = 0.95
        }
    }

    private static func unit(_ dx: Double, _ dy: Double) -> Vector2 {
        let length = max((dx * dx + dy * dy).squareRoot(), 0.0001)
        return Vector2(dx: dx / length, dy: dy / length)
    }

    // MARK: Brightness

    /// Brightness of a vertical face with the given outward normal. `sun`
    /// is `sunDirection` already rotated into the same frame as `normal`.
    func faceBrightness(normal: Vector2, sun: Vector2) -> Double {
        ambient + intensity * max(0, normal.dx * sun.dx + normal.dy * sun.dy)
    }

    /// Roofs face the sky, so they catch the sun in proportion to its height.
    var roofBrightness: Double { ambient + intensity * sunElevation }

    /// Flat ground (roads, sidewalks).
    var groundBrightness: Double { ambient * 0.9 + intensity * sunElevation * 0.7 }

    // MARK: Color

    static func rgb(_ hex: String) -> (Double, Double, Double) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&value)
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    /// A base surface color lit at `brightness`, with the light's color
    /// cast applied.
    func color(_ hex: String, brightness: Double) -> Color {
        let base = Self.rgb(hex)
        func channel(_ value: Double, _ cast: Double) -> Double {
            min(max(value * cast * brightness * 1.25, 0), 1)
        }
        return Color(
            red: channel(base.0, tint.r),
            green: channel(base.1, tint.g),
            blue: channel(base.2, tint.b)
        )
    }
}
