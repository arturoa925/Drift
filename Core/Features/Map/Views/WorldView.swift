//
//  WorldView.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import CoreLocation
import SwiftUI

/// Renders `buildings` as custom-drawn, individually animated polygons —
/// this is the replacement for MapKit's `Map` as the map screen's visual
/// surface. Every building's screen position is recomputed from its
/// real-world offset to `origin` on every single frame, never from a
/// discrete camera/region. That's the whole mechanism behind "the user
/// stands still and the world moves around them": there's no camera to
/// pan, because nothing here is drawn in a fixed frame to begin with.
///
/// Sway (per-building rotation) and proximity-scale both pivot around each
/// building's own centroid, not the scene as a whole, so a field of
/// buildings reads as independently alive — like grass in wind — rather
/// than one uniform effect applied to everything at once.
struct WorldView: View {
    let origin: CLLocationCoordinate2D?
    let buildings: [BuildingShape]

    /// Screen points per meter. Tuned for "buildings up close" — a ~15m
    /// footprint renders roughly 45pt wide, matching the street-level feel
    /// MapView's old MapKit zoom was aiming for.
    private let pixelsPerMeter: CGFloat = 3.0
    private let swayAmplitude: Double = .pi / 36 // ~5°
    private let proximityBoost: Double = 0.6
    private let maxScaleDistance: Double = 150

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard let origin else { return }
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let time = timeline.date.timeIntervalSinceReferenceDate

                for building in buildings {
                    draw(building, origin: origin, center: center, time: time, in: &context)
                }
            }
        }
    }

    private func draw(
        _ building: BuildingShape,
        origin: CLLocationCoordinate2D,
        center: CGPoint,
        time: TimeInterval,
        in context: inout GraphicsContext
    ) {
        let offsets = building.footprint.map { WorldProjection.offset(from: origin, to: $0) }
        guard let centroid = centroid(of: offsets) else { return }

        // Closer to the user (in real meters, not screen distance) reads as
        // bigger — an intentional exaggeration, not real perspective.
        let distance = hypot(centroid.dx, centroid.dy)
        let proximity = 1 - min(distance / maxScaleDistance, 1)
        let scale = 1 + proximity * proximityBoost

        // Each building's own phase/speed offsets its sway from every other
        // building's, so the field doesn't move in lockstep.
        let swaySpeed = 0.6 + building.swayPhase * 0.4
        let swayAngle = sin(time * swaySpeed + building.swayPhase * 2 * .pi) * swayAmplitude

        var path = Path()
        for (index, offset) in offsets.enumerated() {
            let relative = Vector2(dx: offset.dx - centroid.dx, dy: offset.dy - centroid.dy)
            let rotated = rotate(relative, by: swayAngle)
            let scaled = Vector2(dx: rotated.dx * scale, dy: rotated.dy * scale)
            let final = Vector2(dx: scaled.dx + centroid.dx, dy: scaled.dy + centroid.dy)

            // Screen y grows downward, so "north" (positive dy in meters)
            // has to flip sign here to point up.
            let point = CGPoint(
                x: center.x + CGFloat(final.dx) * pixelsPerMeter,
                y: center.y - CGFloat(final.dy) * pixelsPerMeter
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()

        context.fill(path, with: .color(.white.opacity(0.16)))
        context.stroke(path, with: .color(.white.opacity(0.28)), lineWidth: 1)
    }

    private func rotate(_ vector: Vector2, by angle: Double) -> Vector2 {
        let cosA = cos(angle)
        let sinA = sin(angle)
        return Vector2(
            dx: vector.dx * cosA - vector.dy * sinA,
            dy: vector.dx * sinA + vector.dy * cosA
        )
    }

    private func centroid(of offsets: [Vector2]) -> Vector2? {
        guard !offsets.isEmpty else { return nil }
        let dx = offsets.reduce(0) { $0 + $1.dx } / Double(offsets.count)
        let dy = offsets.reduce(0) { $0 + $1.dy } / Double(offsets.count)
        return Vector2(dx: dx, dy: dy)
    }
}

#Preview {
    let origin = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    WorldView(origin: origin, buildings: PlaceholderCityGenerator.buildings(near: origin, radiusMeters: 220))
        .background(Color.black)
}
