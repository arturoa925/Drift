//
//  ThemeModel.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import SwiftUI

/// The output of ThemeEngine: a full-height gradient plus whatever else
/// the UI needs to adapt to it. One theme drives the whole screen.
struct MapTheme: Equatable {
    let gradientStops: [Gradient.Stop]
    /// True only for Snow, whose pale bottom stop forces dark text/icons
    /// instead of the usual white.
    let usesDarkText: Bool

    var gradient: Gradient {
        Gradient(stops: gradientStops)
    }
}

