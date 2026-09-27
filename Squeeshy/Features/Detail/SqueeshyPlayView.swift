import SwiftUI

/// Just the squeeshy, full screen, and nothing to do but pull it about.
///
/// Deliberately the *same* deformation and the *same* spring as the hero on the detail
/// screen — `.squish()` driven by `SquishSpring` — with one difference: the hero only
/// works vertically, and this works along whichever axis you grabbed. Grab the left side
/// and pull left and it stretches leftward, anchored on the right. Push inward instead
/// and it squashes. Let go and it wobbles back exactly as the hero does.
///
/// Two earlier mistakes are worth not repeating. Clamping the spring to positive values
/// threw away its overshoot, which is the entire bounce — the spring was working and half
/// of it was being discarded. And steering the deformation from the *current* finger
/// position rather than from a fixed grab axis made it slew around as the finger wandered,
/// which reads as sliding rather than stretching.
struct SqueeshyPlayView: View {
    var squishy: Squishy

    @Environment(\.dismiss) private var dismiss
    @State private var driver = DisplayLinkDriver()

    /// The same spring the hero uses, so the two feel identical.
    @State private var spring = SquishSpring()

    /// Rotation that carries the grabbed axis onto the vertical, so `.squish()` — which
    /// only ever compresses along y — can act along any direction. Captured once when the
    /// finger lands and held for the whole drag.
    @State private var axisRotation: Double = 0
    /// Unit vector from the centre out to the grab point, in view space.
    @State private var axis: CGSize = CGSize(width: 0, height: -1)
    @State private var dragging = false
    @State private var everTouched = false

    private var softness: Double { squishy.squeeshiness / 10 }
    private var side: CGFloat { 300 }

    /// Amplifies the *visual* deformation without touching the physics. The spring, its
    /// stiffness, damping and bounce are the hero's exactly; only how far the picture
    /// is pushed differs, because the hero is 190pt on a page full of other things and
    /// this is 300pt with nothing else on screen. At the hero's own factors the squeeze
    /// was there but almost invisible at this size.
    private static let defaultGain = 1.9

    private var gain: Double {
        #if DEBUG
        let d = UserDefaults.standard
        if d.object(forKey: "playGain") != nil { return d.double(forKey: "playGain") }
        #endif
        return Self.defaultGain
    }

    /// How far the squeeshy is deformed right now.
    ///
    /// `driver.frame` is read on purpose. `SquishSpring`'s own mutations do not
    /// invalidate this view: on the detail screen the hero only *appears* to animate
    /// because the fan strip re-reads its simulation sixty times a second and drags the
    /// spring along with it. There is no fan here, so without the frame counter the view
    /// renders once at rest and never again — which is exactly what
    /// `DisplayLinkDriver.frame` exists for.
    private var deformation: Double {
        _ = driver.frame
        return spring.amount * gain
    }

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: Tint.single(squishy.hue))

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                squeeshy
                Spacer(minLength: 0)
                MetaLabel(text: everTouched ? hint : "grab it anywhere and pull", color: .ink3)
                    .padding(.bottom, 46)
                    .animation(Motion.tap, value: everTouched)
            }
        }
        .onAppear {
            spring.softness = softness
            #if DEBUG
            if let held = DebugLaunch.playHold {
                // Frozen mid-gesture so the deformation can be screenshotted.
                switch DebugLaunch.playAxis {
                case "left":   axis = CGSize(width: -1, height: 0)
                case "corner": axis = CGSize(width: -0.71, height: -0.71)
                default:       axis = CGSize(width: 0, height: -1)
                }
                axisRotation = -.pi / 2 - atan2(Double(axis.height), Double(axis.width))
                driver.start { _ in spring.grab(held == "squash" ? 1 : -1) }
                return
            }
            #endif
            startIfNeeded()
        }
        .onDisappear { driver.stop() }
    }

    private var hint: String {
        switch squishy.squeeshiness {
        case ..<3.5:  return "firm one, that"
        case ..<7:    return "gives a little"
        default:      return "stretches for miles"
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.tap)
            .accessibilityLabel("Done")
            Spacer()
            Text(squishy.name)
                .font(.display(19, .bold))
                .foregroundStyle(Color.ink)
            Spacer()
            // Balances the close button so the name sits dead centre.
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var squeeshy: some View {
        SquishyImage(squishy: squishy)
            .frame(width: side, height: side)
            // Rotate the grabbed axis onto the vertical, apply the hero's own squish
            // anchored at the far end, rotate back. Nothing else — no extra offset, no
            // second scale. The bounce belongs to the spring, not to the transform.
            .rotationEffect(.radians(axisRotation), anchor: .center)
            .squish(deformation)
            .rotationEffect(.radians(-axisRotation), anchor: .center)
            .shadow(color: squishy.color.opacity(0.35), radius: 34, y: 14)
            .contentShape(.rect)
            .accessibilityElement()
            .accessibilityIdentifier("playToy")
            .accessibilityLabel("Squeeze \(squishy.name)")
            .gesture(pull)
    }

    /// Runs the clock only while there is something to animate. This view reads
    /// `driver.frame`, so a driver left ticking re-renders it sixty times a second even
    /// with the squeeshy sitting perfectly still.
    private func startIfNeeded() {
        driver.start { dt in
            spring.step(dt: dt)
            if spring.isResting { driver.stop() }
        }
    }

    private var pull: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if !dragging {
                    dragging = true
                    startIfNeeded()
                    everTouched = true
                    grabAxis(at: g.startLocation)
                }
                // Only the component along the grabbed axis counts. Dragging sideways
                // across the axis does nothing, which is what stops it slewing about.
                let along = Double(g.translation.width) * Double(axis.width)
                          + Double(g.translation.height) * Double(axis.height)
                // Pull outward stretches, push inward squashes. Negative is stretch in
                // `.squish()`, the same convention the hero's vertical drag uses.
                spring.grab(-along / Double(side * 0.63))
            }
            .onEnded { _ in
                dragging = false
                spring.release()
            }
    }

    /// Fixes the stretch axis to the line from the centre through wherever the finger
    /// landed, so grabbing a corner pulls along that diagonal.
    private func grabAxis(at point: CGPoint) {
        let dx = Double(point.x - side / 2)
        let dy = Double(point.y - side / 2)
        let length = max(1, (dx * dx + dy * dy).squareRoot())
        axis = CGSize(width: dx / length, height: dy / length)
        axisRotation = -.pi / 2 - atan2(dy, dx)
    }
}
