//
//  WorldMotion.swift
//  Dritft
//
//  Created by Arturo Ayala on 10/1/26.
//

import CoreLocation
import Foundation

/// Frame-to-frame motion state behind `WorldView` — the one piece of the
/// renderer that has to remember anything between frames.
///
/// GPS fixes arrive about once a second, and a compass reading only every
/// degree or so. Rendering them directly makes the world jump a few meters
/// (or degrees) at a time instead of moving. This turns those discrete
/// fixes into continuous motion: position is dead-reckoned forward from the
/// last fix along the user's velocity and eased toward each new fix as it
/// lands, and heading eases along the shortest way around the compass.
///
/// It also derives what the buildings' "swoosh" reacts to — how fast the
/// world is actually moving past the user, and how fast it's turning —
/// run through underdamped springs, so buildings bend as motion builds up
/// and swing back past upright (then settle) when it stops.
///
/// A plain reference type, deliberately not observable: it's advanced
/// once per frame from inside `WorldView`'s `Canvas`, and nothing should
/// re-render because it changed.
final class WorldMotion {
    struct Frame {
        /// Where to render the user standing, this frame.
        let origin: CLLocationCoordinate2D
        /// Rotation (radians) that turns raw (east, north) offsets into the
        /// view frame, where the user faces +y.
        let rotation: Double
        /// Spring-smoothed velocity of the user, view frame (x right,
        /// y forward), m/s.
        let velocity: Vector2
        /// Spring-smoothed rate of `rotation`, rad/s.
        let turnRate: Double
    }

    /// How long (seconds) dead reckoning keeps extrapolating past the last
    /// fix before giving up and holding still — long enough to bridge a
    /// normal gap between GPS updates, short enough that stopping doesn't
    /// keep sliding the world forward for long.
    private let maxExtrapolationSeconds: Double = 1.5
    /// Time constant (seconds) for easing the rendered position toward
    /// where dead reckoning says the user is.
    private let positionSmoothing: Double = 0.35
    /// Time constant (seconds) for easing heading.
    private let headingSmoothing: Double = 0.18
    /// Any correction bigger than this (meters) — a first fix, a GPS
    /// glitch, snapping onto a different street — jumps instead of gliding
    /// across half a block.
    private let snapDistanceMeters: Double = 40
    /// While the user isn't moving (zero velocity), fixes closer than this
    /// (meters) to where they're already drawn are GPS drift, not motion —
    /// ignored, so a phone sitting on a table doesn't slowly slide the
    /// street around.
    private let stationaryDriftMeters: Double = 6
    /// Turn rates slower than this (rad/s, ~11°/s) don't swoosh at all —
    /// compass noise and slow, idle looking-around stay perfectly still.
    private let turnRateDeadZone: Double = 0.2
    /// Spring constants for the swoosh. Still a little underdamped
    /// (ζ ≈ 0.6) for a soft settle when motion stops, without wobbling.
    private let springStiffness: Double = 28
    private let springDamping: Double = 6.5

    private var fixOrigin: CLLocationCoordinate2D?
    private var fixTime: TimeInterval = 0
    private var displayedOrigin: CLLocationCoordinate2D?
    private var displayedHeading: Double?
    private var lastTime: TimeInterval?

    private var velocitySpring = Spring2D()
    private var turnSpring = Spring1D()

    /// Advances one frame.
    /// - Parameters:
    ///   - origin: The latest fix (already snapped onto a street).
    ///   - velocity: The user's velocity at that fix, (east, north) m/s.
    ///   - heading: Compass heading in degrees; `nil` faces north.
    ///   - now: This frame's timestamp.
    func advance(origin: CLLocationCoordinate2D, velocity: Vector2, heading: CLLocationDirection?, now: TimeInterval) -> Frame {
        // Clamped so a hitch (or the first frame) can't fling the springs.
        let dt = min(max(now - (lastTime ?? now), 0), 1.0 / 20)
        lastTime = now

        if fixOrigin.map({ $0.latitude != origin.latitude || $0.longitude != origin.longitude }) ?? true {
            fixOrigin = origin
            fixTime = now
        }

        // Dead reckoning: where the user probably is by now, given where
        // they last were and how fast they were going.
        let elapsed = min(now - fixTime, maxExtrapolationSeconds)
        let predicted = WorldProjection.coordinate(
            from: origin,
            offset: Vector2(dx: velocity.dx * elapsed, dy: velocity.dy * elapsed)
        )

        var newOrigin = predicted
        let isStationary = velocity.dx == 0 && velocity.dy == 0
        if let displayedOrigin {
            let error = WorldProjection.offset(from: displayedOrigin, to: predicted)
            let errorMeters = hypot(error.dx, error.dy)
            if isStationary, errorMeters < stationaryDriftMeters {
                newOrigin = displayedOrigin
            } else if errorMeters <= snapDistanceMeters {
                let blend = ease(dt, positionSmoothing)
                newOrigin = WorldProjection.coordinate(
                    from: displayedOrigin,
                    offset: Vector2(dx: error.dx * blend, dy: error.dy * blend)
                )
            }
        }
        displayedOrigin = newOrigin

        let targetHeading = heading ?? 0
        let previousHeading = displayedHeading ?? targetHeading
        let headingError = shortestAngle(from: previousHeading, to: targetHeading)
        let newHeading = previousHeading + headingError * ease(dt, headingSmoothing)
        displayedHeading = newHeading

        let rotation = newHeading * .pi / 180
        if dt > 0 {
            // Buildings react to the user's actual (speed-gated) velocity,
            // not the frame-to-frame motion of the rendered origin — that
            // also includes GPS corrections easing in, which would swoosh
            // buildings around while the user is sitting still.
            let viewVelocity = rotate(velocity, by: rotation)
            velocitySpring.step(toward: viewVelocity, dt: dt, stiffness: springStiffness, damping: springDamping)

            let rawTurnRate = (newHeading - previousHeading) * .pi / 180 / dt
            let turnRate = abs(rawTurnRate) < turnRateDeadZone ? 0 : min(max(rawTurnRate, -3), 3)
            turnSpring.step(toward: turnRate, dt: dt, stiffness: springStiffness, damping: springDamping)
        }

        return Frame(
            origin: newOrigin,
            rotation: rotation,
            velocity: velocitySpring.value,
            turnRate: turnSpring.value
        )
    }

    /// Fraction of the remaining distance to close this frame, for an
    /// exponential ease with time constant `tau` — frame-rate independent.
    private func ease(_ dt: Double, _ tau: Double) -> Double {
        1 - exp(-dt / tau)
    }

    /// Signed difference in degrees, the short way around (-180...180).
    private func shortestAngle(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    private func rotate(_ vector: Vector2, by angle: Double) -> Vector2 {
        Vector2(
            dx: vector.dx * cos(angle) - vector.dy * sin(angle),
            dy: vector.dx * sin(angle) + vector.dy * cos(angle)
        )
    }
}

/// Damped spring chasing a target (semi-implicit Euler).
private struct Spring1D {
    private(set) var value: Double = 0
    private var speed: Double = 0

    mutating func step(toward target: Double, dt: Double, stiffness: Double, damping: Double) {
        let acceleration = stiffness * (target - value) - damping * speed
        speed += acceleration * dt
        value += speed * dt
    }
}

private struct Spring2D {
    private var x = Spring1D()
    private var y = Spring1D()

    var value: Vector2 { Vector2(dx: x.value, dy: y.value) }

    mutating func step(toward target: Vector2, dt: Double, stiffness: Double, damping: Double) {
        x.step(toward: target.dx, dt: dt, stiffness: stiffness, damping: damping)
        y.step(toward: target.dy, dt: dt, stiffness: stiffness, damping: damping)
    }
}
