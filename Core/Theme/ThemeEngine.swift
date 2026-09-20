//
//  ThemeEngine.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import SwiftUI

/// Computes the active `MapTheme` from weather and time of day. This is the
/// one place the gradient tables from claude.md live — everything else
/// (SunCalculator, WeatherService) only produces the *inputs*; ThemeEngine
/// is solely responsible for turning those inputs into a theme.
enum ThemeEngine {
    static func theme(weather: WeatherCondition, timeOfDay: TimeOfDayCondition) -> MapTheme {
        weather.overridesTimeOfDay ? theme(for: weather) : theme(for: timeOfDay)
    }

    // weather condition
    private static func theme(for weather: WeatherCondition) -> MapTheme {
        switch weather {
        case .sunny:
            preconditionFailure("sunny never overrides time of day — see WeatherCondition.overridesTimeOfDay")
        case .rain:
            return MapTheme(
                gradientStops: stops([
                    ("#6B7A8D", 0.00),
                    ("#8D9DAD", 0.30),
                    ("#A8B8C4", 0.55),
                    ("#D4DDE5", 0.80),
                    ("#E8EEF3", 1.00),
                ]),
                usesDarkText: false
            )
        case .snow:
            return MapTheme(
                gradientStops: stops([
                    ("#93C5FD", 0.00),
                    ("#BFDBFE", 0.30),
                    ("#DBEAFE", 0.55),
                    ("#EFF6FF", 0.80),
                    ("#FFFFFF", 1.00),
                ]),
                usesDarkText: true
            )
        case .storm:
            return MapTheme(
                gradientStops: stops([
                    ("#5B4E7E", 0.00),
                    ("#7C6A9E", 0.30),
                    ("#9B82B5", 0.55),
                    ("#C8B8D8", 0.80),
                    ("#E8DFF4", 1.00),
                ]),
                usesDarkText: false
            )
        case .fog:
            return MapTheme(
                gradientStops: stops([
                    ("#94A3B8", 0.00),
                    ("#B0BEC5", 0.30),
                    ("#CBD5DC", 0.55),
                    ("#DFE6EC", 0.80),
                    ("#EEF2F5", 1.00),
                ]),
                usesDarkText: false
            )
        }
    }

    // time of day
    private static func theme(for timeOfDay: TimeOfDayCondition) -> MapTheme {
        switch timeOfDay {
        case .sunrise:
            return MapTheme(
                gradientStops: stops([
                    ("#6D28D9", 0.00),
                    ("#C026D3", 0.30),
                    ("#F97316", 0.55),
                    ("#FDE68A", 0.80),
                ]),
                usesDarkText: false
            )
        case .midday:
            return MapTheme(
                gradientStops: stops([
                    ("#FDE68A", 0.00),
                    ("#FBBF24", 0.30),
                    ("#FB923C", 0.55),
                    ("#BAE6FD", 0.80),
                    ("#E0F2FE", 1.00),
                ]),
                usesDarkText: false
            )
        case .sunset:
            return MapTheme(
                gradientStops: stops([
                    ("#1E1B4B", 0.00),
                    ("#4C1D95", 0.30),
                    ("#BE185D", 0.55),
                    ("#F97316", 0.80),
                    ("#FECACA", 1.00),
                ]),
                usesDarkText: false
            )
        case .night:
            return MapTheme(
                gradientStops: stops([
                    ("#1E3A5F", 0.00),
                    ("#2D5282", 0.30),
                    ("#3B6FA0", 0.55),
                    ("#C7DCF5", 0.80),
                    ("#E8F2FC", 1.00),
                ]),
                usesDarkText: false
            )
        }
    }

    private static func stops(_ hexes: [(String, Double)]) -> [Gradient.Stop] {
        hexes.map { Gradient.Stop(color: Color(hex: $0.0), location: $0.1) }
    }
}

#Preview("Themes") {
    ScrollView {
        VStack(spacing: 0) {
            ForEach(TimeOfDayCondition.allCases, id: \.self) { time in
                ThemeSwatch(title: time.rawValue, theme: ThemeEngine.theme(weather: .sunny, timeOfDay: time))
            }
            ForEach(WeatherCondition.allCases.filter(\.overridesTimeOfDay), id: \.self) { weather in
                ThemeSwatch(title: weather.rawValue, theme: ThemeEngine.theme(weather: weather, timeOfDay: .midday))
            }
        }
    }
}

private struct ThemeSwatch: View {
    let title: String
    let theme: MapTheme

    var body: some View {
        ZStack {
            LinearGradient(gradient: theme.gradient, startPoint: .top, endPoint: .bottom)
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.usesDarkText ? .black : .white)
        }
        .frame(height: 120)
    }
}
