//
//  TimeOfDayCondition.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import Foundation

/// The baseline gradient driver, computed from `SunCalculator`'s sunrise/
/// sunset times for the user's location and the current time. Always
/// available — unlike `WeatherCondition`, there's no "unknown" case, since
/// sun position can be calculated locally without a network call.
enum TimeOfDayCondition: String, Codable, Equatable, CaseIterable {
    case sunrise
    case midday
    case sunset
    case night
}
