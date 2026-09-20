//
//  AnimationAndDrift.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import SwiftUI

extension Animation {
    /// Slow, continuous sway for the background gradient — eases back and
    /// forth forever with no scroll, seam, or reset, just a gentle breathing
    /// motion in the gradient's stop positions.
    static let gradientDrift = Animation.easeInOut(duration: 20).repeatForever(autoreverses: true)

    /// Cross-fade used when the active `MapTheme` itself changes, e.g. a
    /// new weather reading or a time-of-day boundary crossed.
    static let themeTransition = Animation.easeInOut(duration: 2.5)
}
