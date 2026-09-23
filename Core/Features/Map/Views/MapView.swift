//
//  MapView.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import MapKit
import SwiftUI

/// The map screen's root container — stacks every visual layer per
/// claude.md's order (gradient → map overlay → heatmap → trail → pulse dot
/// → floating controls) and owns the `MapModel` that drives all of them.
///
/// Only the bottom two layers exist so far: `MapGradientLayer` and a real,
/// interactive MapKit `Map`. Everything above them — `MapOverlayView`'s
/// proper per-layer road/building treatment, `HeatmapOverlayView`,
/// `TrailOverlay`, `UserPulseView`, and the floating pill controls — is
/// still unbuilt. The flat `.opacity` below approximates claude.md's "~15–18%,
/// low opacity means the gradient bleeds through" spec with one single
/// value, since a raw MapKit `Map` doesn't expose separate opacity for
/// roads vs. buildings the way a custom-drawn overlay could.
struct MapView: View {
    @StateObject private var model = MapModel()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasCenteredOnUser = false

    var body: some View {
        ZStack {
            MapGradientLayer(model: model)

            // No UserAnnotation content here on purpose — Drift draws its
            // own UserPulseView instead of Apple's default blue dot.
            Map(position: $cameraPosition)
                .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
                .opacity(0.16)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.currentLocation) { _, newLocation in
            // Only ever auto-center once, on the first fix — recentering on
            // every update would yank the camera back if the user pans away
            // to look at somewhere else.
            guard !hasCenteredOnUser, let newLocation else { return }
            hasCenteredOnUser = true
            withAnimation {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: newLocation.coordinate,
                        // ~2 blocks in view either side of center — close
                        // enough that individual building footprints read.
                        span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
                    )
                )
            }
        }
    }
}

#Preview {
    MapView()
}
