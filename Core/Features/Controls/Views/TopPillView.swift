//
//  TopPillView.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import SwiftUI

/// Tesla-style top status strip: clock on the left, weather on the right,
/// no chrome — just quiet type over the map.
struct TopPillView: View {
    let weather: WeatherCondition
    let timeOfDay: TimeOfDayCondition

    private var weatherSymbol: String {
        switch weather {
        case .sunny:
            switch timeOfDay {
            case .night: return "moon.stars"
            case .sunrise, .sunset: return "sun.horizon"
            case .midday: return "sun.max"
            }
        case .rain: return "cloud.rain"
        case .snow: return "snowflake"
        case .storm: return "cloud.bolt"
        case .fog: return "cloud.fog"
        }
    }

    var body: some View {
        HStack(spacing: 18) {
            TimelineView(.everyMinute) { timeline in
                Text(timeline.date, format: .dateTime.hour().minute())
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(TeslaStyle.textPrimary)
            }

            Capsule()
                .fill(TeslaStyle.glassStroke)
                .frame(width: 1, height: 14)

            HStack(spacing: 7) {
                Image(systemName: weatherSymbol)
                    .font(.system(size: 14, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                Text(weather.rawValue.capitalized)
                    .font(.system(size: 13, weight: .regular))
                    .tracking(0.3)
            }
            .foregroundStyle(TeslaStyle.textSecondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .teslaGlass(cornerRadius: 22)
    }
}

#Preview {
    ZStack {
        Color.black
        TopPillView(weather: .rain, timeOfDay: .night)
    }
}
