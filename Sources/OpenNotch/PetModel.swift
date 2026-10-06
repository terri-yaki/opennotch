import Foundation

/// A critically-ish damped spring for one value.
private struct Spring {
    var value: CGFloat = 0
    var velocity: CGFloat = 0

    mutating func step(toward target: CGFloat, dt: CGFloat, stiffness: CGFloat = 140, damping: CGFloat = 13) {
        velocity += ((target - value) * stiffness - velocity * damping) * dt
        value += velocity * dt
    }
}

/// One frame of the pet, ready to draw.
struct PetPose {
    var time: Double
    var look: CGVector      // -1...1, where the eyes point (y down)
    var lean: CGFloat       // -1...1, body shifts toward the cursor
    var energy: CGFloat     // 0...1, how agitated the liquid is
    var phase: Double       // drives the slow lava-lamp churn
    var blink: CGFloat      // 0 open ... 1 closed
    var hue: Double
    var hop: CGFloat        // vertical bounce, points
    var asleep: Bool
    var happy: Bool
}

/// Simulation for the liquid pet in the notch. Deliberately not observable: the view
/// redraws from a TimelineView every frame and pulls a fresh pose with `step(at:)`,
/// so mouse events never trigger SwiftUI invalidation.
@MainActor
final class PetModel {
    /// Pet center in screen coordinates (y up). Set by NotchController.
    var anchor: CGPoint = .zero
    /// True while the cursor is over the collapsed notch (it's about to open).
    var happy = false
    /// True while music plays: the pet bobs along.
    var dancing = false

    private var cursor: CGPoint = .zero
    private var lastMove = Date()
    private var lastStep: Double?

    private var lookX = Spring(), lookY = Spring(), lean = Spring()
    private var energy: CGFloat = 0.3
    private var phase: Double = 0
    private var hue = Double.random(in: 0..<1)
    private var nextBlink: Double = 0
    private var blinkStart: Double = -10
    private var hopStart: Double = -10

    private let sleepAfter: TimeInterval = 30

    func cursorMoved(to point: CGPoint) {
        let distance = hypot(point.x - cursor.x, point.y - cursor.y)
        cursor = point
        if Date().timeIntervalSince(lastMove) > sleepAfter {
            // Woken up: startle.
            energy = 1
            hop()
        }
        lastMove = Date()
        // Fast swipes stir the liquid up; nearby motion counts more.
        let near = max(0, 1 - hypot(point.x - anchor.x, point.y - anchor.y) / 500)
        energy = min(1, energy + min(distance, 60) * (0.002 + 0.006 * near))
    }

    /// Something was dropped on the shelf.
    func feed() {
        energy = 1
        hop()
        hue += 0.25
    }

    private func hop() {
        hopStart = Date().timeIntervalSinceReferenceDate
    }

    func step(at date: Date) -> PetPose {
        let t = date.timeIntervalSinceReferenceDate
        let dt = CGFloat(min(max(t - (lastStep ?? t), 0), 1.0 / 20))
        lastStep = t

        let asleep = date.timeIntervalSince(lastMove) > sleepAfter && !dancing

        // Eyes and body follow the cursor.
        let dx = cursor.x - anchor.x
        let dy = anchor.y - cursor.y // flip to view coordinates (y down)
        let dist = max(hypot(dx, dy), 0.001)
        let reach = min(1, dist / 80)
        let targetLook = asleep ? CGVector.zero : CGVector(dx: dx / dist * reach, dy: dy / dist * reach)
        let targetLean = asleep ? 0 : max(-1, min(1, dx / 260)) * (dist < 600 ? 1 : 0.3)

        lookX.step(toward: targetLook.dx, dt: dt)
        lookY.step(toward: targetLook.dy, dt: dt)
        lean.step(toward: targetLean, dt: dt, stiffness: 50, damping: 6) // looser, so it sloshes

        let restEnergy: CGFloat = asleep ? 0.05 : (happy ? 0.6 : 0.2)
        energy += (restEnergy - energy) * min(1, dt * 1.8)
        phase += Double(dt) * (asleep ? 0.6 : 1.4 + Double(energy) * 5)
        hue += Double(dt) * (asleep ? 0.005 : 0.03 + Double(energy) * 0.12)

        // Blinking.
        if !asleep, t > nextBlink {
            blinkStart = t
            nextBlink = t + Double.random(in: 2.5...6)
        }
        let blinkT = (t - blinkStart) / 0.16
        let blink = blinkT < 1 ? CGFloat(sin(.pi * blinkT)) : 0

        // Hop: one damped bounce after a drop or a wake-up, small bounces while happy.
        let hopT = t - hopStart
        var hop = hopT < 0.9 ? CGFloat(abs(sin(hopT * 11)) * exp(-hopT * 4.5)) * 6 : 0
        if happy && !asleep { hop += CGFloat(abs(sin(t * 8))) * 1.5 }
        if dancing && !happy { hop += CGFloat(abs(sin(t * .pi * 2))) * 1.2 } // ~120 bpm bob

        return PetPose(
            time: t,
            look: CGVector(dx: lookX.value, dy: lookY.value),
            lean: lean.value,
            energy: energy,
            phase: phase,
            blink: blink,
            hue: hue,
            hop: hop,
            asleep: asleep,
            happy: happy && !asleep
        )
    }
}
