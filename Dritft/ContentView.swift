//
//  ContentView.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import SwiftUI

// Routes to onboarding vs the map, per claude.md's architecture — but
// onboarding doesn't exist yet, so this goes straight to MapView until it
// does.
struct ContentView: View {
    var body: some View {
        MapView()
    }
}

#Preview {
    ContentView()
}
