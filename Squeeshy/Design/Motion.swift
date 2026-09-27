import SwiftUI

/// Every animation in Squeeshy comes from here. Nothing eases; everything springs,
/// because everything on screen is meant to read as a soft physical object.
enum Motion {
    /// Default for anything a finger caused. Fast, with a touch of overshoot.
    static let tap = Animation.spring(response: 0.34, dampingFraction: 0.62)

    /// Screen-to-screen pushes. Slower, still springy, no wobble at the end.
    static let nav = Animation.spring(response: 0.52, dampingFraction: 0.86)

    /// Things arriving: cards, bubbles, shelf rows. Deliberately bouncy.
    static let arrive = Animation.spring(response: 0.55, dampingFraction: 0.58)

    /// A squish releasing. Very underdamped: this is the wobble.
    static let rebound = Animation.spring(response: 0.42, dampingFraction: 0.34)

    /// Background colour crossfades between shelves.
    static let tintShift = Animation.easeInOut(duration: 0.65)

    /// Sheet presentation.
    static let sheet = Animation.spring(response: 0.46, dampingFraction: 0.84)

    /// Staggered delay for lists and grids, capped so long lists don't crawl.
    static func stagger(_ index: Int, step: Double = 0.035, cap: Double = 0.42) -> Double {
        min(Double(index) * step, cap)
    }
}

// MARK: - Spring solved by hand
//
// SwiftUI's animations interpolate between two values; they can't tell you how fast
// something is travelling right now. The glass slider needs that velocity to stretch
// the bead along its direction of travel, and the bubble field needs it to resolve
// collisions, so those two run their own integrator on a display link instead.

struct Spring1D {
    var value: Double
    var velocity: Double = 0
    var stiffness: Double
    var dampingRatio: Double

    init(_ value: Double, stiffness: Double = 460, dampingRatio: Double = 0.52) {
        self.value = value
        self.stiffness = stiffness
        self.dampingRatio = dampingRatio
    }

    /// Semi-implicit Euler. Stable at the step sizes a display link produces.
    mutating func step(toward target: Double, dt: Double) {
        let c = 2 * (stiffness).squareRoot() * dampingRatio
        velocity += (-(value - target) * stiffness - velocity * c) * dt
        value += velocity * dt
    }

    mutating func clamp(to range: ClosedRange<Double>, restitution: Double = 0.3) {
        if value < range.lowerBound {
            value = range.lowerBound
            velocity *= -restitution
        } else if value > range.upperBound {
            value = range.upperBound
            velocity *= -restitution
        }
    }

    var isAtRest: Bool { abs(velocity) < 0.001 }
}

// MARK: - Display link

/// Drives the hand-solved simulations. SwiftUI's TimelineView would also work, but a
/// display link keeps the physics out of the view body and lets it stop cleanly.
@Observable
final class DisplayLinkDriver {
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastStamp: CFTimeInterval = 0
    @ObservationIgnored private var onStep: ((Double) -> Void)?

    /// Bumped every frame so SwiftUI re-reads whatever the simulation wrote.
    var frame: Int = 0

    func start(_ step: @escaping (Double) -> Void) {
        stop()
        onStep = step
        lastStamp = 0
        let l = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
        onStep = nil
    }

    fileprivate func tick(_ link: CADisplayLink) {
        if lastStamp == 0 { lastStamp = link.timestamp; return }
        // Clamped so a stalled frame can't blow the integrator up.
        let dt = min(1.0 / 30.0, link.timestamp - lastStamp)
        lastStamp = link.timestamp
        onStep?(dt)
        frame &+= 1
    }

    deinit { link?.invalidate() }
}

/// CADisplayLink retains its target, so the proxy keeps the driver weak.
private final class DisplayLinkProxy {
    weak var owner: DisplayLinkDriver?
    init(_ owner: DisplayLinkDriver) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}
