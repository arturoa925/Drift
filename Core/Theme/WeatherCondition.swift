//
//  WeatherCondition.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import Foundation

/// Current weather at the user's location, as reported by `WeatherService`.
/// Per the theme priority stack, only `rain`, `snow`, `storm`, and `fog` are
/// "strong" enough to override the time-of-day gradient — `sunny` yields the
/// baseline to `TimeOfDayCondition`.
enum WeatherCondition: String, Codable, Equatable, CaseIterable {
    case sunny
    case rain
    case snow
    case storm
    case fog

    /// True for every condition except `sunny`.
    var overridesTimeOfDay: Bool {
        self != .sunny
    }
}
