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
/// low-opacity road/building treatment, `HeatmapOverlayView`,
/// `TrailOverlay`, `UserPulseView`, and the floating pill controls — is
/// still unbuilt. The plain `.opacity` below is a provisional stand-in for
/// that "whispers on the canvas" treatment until `MapOverlayView` exists to
/// do it properly.
struct MapView: View {
    @StateObject private var model = MapModel()
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        ZStack {
            MapGradientLayer(model: model)

            // No UserAnnotation content here on purpose — Drift draws its
            // own UserPulseView instead of Apple's default blue dot.
            Map(position: $cameraPosition)
                .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
                .opacity(0.4)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.currentLocation) { _, newLocation in
            guard let newLocation else { return }
            withAnimation {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: newLocation.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                )
            }
        }
    }
}

#Preview {
    MapView()
}
