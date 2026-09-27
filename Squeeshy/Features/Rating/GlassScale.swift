import SwiftUI

// MARK: - Glass scale
//
// The signature control. A liquid glass track with a bead that chases your finger
// on a spring rather than sticking to it: it lags going out, overshoots coming to
// rest, and stretches along its direction of travel. A droplet trails behind and
// merges back into the bead through an alpha-threshold metaball filter.
//
// The same control does two jobs. On a squeeshy it runs 0...10 with the score riding
// inside the bead. On a shelf it runs whatever domain that shelf actually occupies,
// with a hue band or a ramp behind it.

enum GlassScaleStyle {
    /// Solid tint fill, value shown inside the bead, detents at whole numbers.
    case score
    /// Hue band across the shelf's own arc, legend floated above.
    case hueBand(lower: Double, upper: Double)
    /// Neutral-to-tint ramp for size and squeeshiness sweeps.
    case ramp
}

struct GlassScale: View {
    var domain: TraitDomain
    var style: GlassScaleStyle
    /// Live position 0...1 along the domain. Written every frame while dragging.
    @Binding var position: Double
    var tint: Color
    /// What the scale measures, shown opposite the readout. Optional because in the
    /// field the trait picker sitting above it already says; anywhere the scale stands
    /// on its own it needs to name itself, or it is just a bead and two numbers.
    var label: String? = nil
    /// Called with the settled position when the finger lifts.
    var onCommit: ((Double) -> Void)? = nil

    @State private var sim = ScaleSim()
    @State private var driver = DisplayLinkDriver()
    @State private var isDragging = false
    @State private var detent: Int = 0

    private let trackHeight: CGFloat = 62
    private let beadRadius: CGFloat = 24
    private let inset: CGFloat = 8

    var body: some View {
        VStack(spacing: 14) {
            legend
            GeometryReader { geo in
                let travel = max(1, geo.size.width - (inset + beadRadius) * 2)
                let originX = inset + beadRadius

                ZStack(alignment: .leading) {
                    track
                    goo(travel: travel, originX: originX)
                    beadValue(travel: travel, originX: originX)
                }
                .frame(height: trackHeight)
                .contentShape(.rect)
                .gesture(drag(travel: travel, originX: originX))
                .onAppear { start(travel: travel) }
                .onDisappear { driver.stop() }
            }
            .frame(height: trackHeight)
            ticks
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.55), trigger: detent)
    }

    // MARK: Track

    private var track: some View {
        Capsule()
            .fill(.clear)
            .frame(height: trackHeight)
            .glassEffect(.regular, in: .capsule)
            .overlay {
                Capsule()
                    .fill(bandFill)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 5)
                    .opacity(bandOpacity)
                    .clipShape(.capsule)
            }
            .overlay {
                Capsule().stroke(.white.opacity(0.16), lineWidth: 1)
            }
    }

    /// Over a hue band the bead takes the colour it is currently sitting on, so
    /// dragging it reads as picking a colour rather than moving a control.
    private var beadColor: Color {
        if case let .hueBand(lower, upper) = style {
            return Hue.color(lower + (upper - lower) * sim.position, saturation: 0.62)
        }
        return tint
    }

    private var isHueBand: Bool {
        if case .hueBand = style { return true }
        return false
    }

    private var bandOpacity: Double {
        switch style {
        case .score: return 0
        case .hueBand: return 0.85
        case .ramp: return 0.5
        }
    }

    private var bandFill: LinearGradient {
        switch style {
        case .score:
            return LinearGradient(colors: [.clear], startPoint: .leading, endPoint: .trailing)
        case let .hueBand(lower, upper):
            // Only the arc this shelf occupies, sampled across it.
            let steps = 12
            let colors = (0...steps).map { i -> Color in
                Hue.color(lower + (upper - lower) * Double(i) / Double(steps), saturation: 0.5)
            }
            return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
        case .ramp:
            return LinearGradient(colors: [.white.opacity(0.10), tint],
                                  startPoint: .leading, endPoint: .trailing)
        }
    }

    // MARK: Metaball layer

    /// Fill, droplet and bead drawn into one layer, blurred then alpha-thresholded so
    /// they read as a single body of liquid that necks and separates as it moves.
    private func goo(travel: CGFloat, originX: CGFloat) -> some View {
        Canvas { ctx, size in
            // A wider blur before thresholding makes the neck between bead and
            // droplets stretch further before it snaps.
            ctx.addFilter(.alphaThreshold(min: 0.5, color: beadColor))
            ctx.addFilter(.blur(radius: 12))
            ctx.drawLayer { layer in
                let x = originX + travel * sim.position
                let dripX = originX + travel * sim.dripPosition
                let midY = size.height / 2

                // Fill from the left cap up to the bead. Skipped over a hue band,
                // where a solid fill would paint out the colours you are choosing from.
                if !isHueBand {
                    let fillRect = CGRect(x: inset, y: midY - 10,
                                          width: max(0, x - inset), height: 20)
                    layer.fill(Path(roundedRect: fillRect, cornerRadius: 10), with: .color(.white))
                }

                // Two trailing droplets at different lags. As the bead accelerates
                // away they shrink and fall behind, so the tail necks and breaks
                // instead of dragging one blob along.
                let drip2X = originX + travel * sim.dripPosition2
                let dr1 = max(3.5, 13.0 - abs(sim.stretch) * 5.5)
                let dr2 = max(2.5, 9.0 - abs(sim.stretch) * 4.5)
                layer.fill(Path(ellipseIn: CGRect(x: drip2X - dr2, y: midY - dr2,
                                                  width: dr2 * 2, height: dr2 * 2)),
                           with: .color(.white))
                layer.fill(Path(ellipseIn: CGRect(x: dripX - dr1, y: midY - dr1,
                                                  width: dr1 * 2, height: dr1 * 2)),
                           with: .color(.white))

                // The bead: stretched along travel, thinned across it, and squashed
                // flat for a beat whenever it slams into an end cap.
                let squash = min(0.55, abs(sim.impact))
                let rx = beadRadius * (1 + sim.stretch + squash * 0.5)
                let ry = beadRadius * (1 - sim.stretch * 0.60 - squash * 0.45)
                layer.fill(Path(ellipseIn: CGRect(x: x - rx, y: midY - max(3, ry),
                                                  width: rx * 2, height: max(6, ry * 2))),
                           with: .color(.white))
            }
        }
        .frame(height: trackHeight)
        .allowsHitTesting(false)
    }

    /// The number rides on top of the bead, outside the filter so it stays crisp.
    @ViewBuilder
    private func beadValue(travel: CGFloat, originX: CGFloat) -> some View {
        if case .score = style {
            Text(String(format: "%.1f", domain.value(at: sim.position)))
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.06, green: 0.04, blue: 0.08))
                .frame(width: beadRadius * 2)
                .offset(x: originX + travel * sim.position - beadRadius)
                .allowsHitTesting(false)
        }
    }

    // MARK: Legend and ticks

    private var legend: some View {
        HStack {
            MetaLabel(text: domain.legend(at: sim.position), color: .ink)
                .contentTransition(.numericText())
            Spacer()
            // The name gives way to the physics readout mid-drag: once your finger is
            // on the bead you know what you are setting, and the stretch state is the
            // more interesting thing to be told.
            if isDragging {
                MetaLabel(text: abs(sim.stretch) > 0.06 ? "stretching" : "settled")
                    .transition(.opacity)
            } else if let label {
                MetaLabel(text: label)
                    .transition(.opacity)
            }
        }
        .animation(Motion.tap, value: isDragging)
    }

    private var ticks: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - (inset + beadRadius) * 2)
            ZStack(alignment: .topLeading) {
                ForEach(Array(domain.ticks.enumerated()), id: \.offset) { _, t in
                    let major = t == 0 || t == 1
                    Rectangle()
                        .fill(major ? Color.ink2 : Color.ink3)
                        .frame(width: 1, height: major ? 9 : 5)
                        .offset(x: inset + beadRadius + travel * t)
                }
                HStack {
                    MetaLabel(text: domain.endLabels.0, color: .ink3)
                    Spacer()
                    MetaLabel(text: domain.endLabels.1, color: .ink3)
                }
                .offset(y: 13)
            }
        }
        .frame(height: 30)
    }

    // MARK: Gesture and loop

    private func drag(travel: CGFloat, originX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                isDragging = true
                sim.target = Double((g.location.x - originX) / travel).clamped(to: 0...1)
            }
            .onEnded { _ in
                isDragging = false
                onCommit?(sim.position)
            }
    }

    private func start(travel: CGFloat) {
        sim.reset(to: position)
        driver.start { dt in
            // On a score the value drives its own drama: the higher it reads, the
            // more liquid the bead behaves. On a shelf axis there is no softness
            // being described, so it stays middling.
            if case .score = style {
                sim.softness = sim.position
            } else {
                sim.softness = 0.42
            }
            sim.step(dt: dt)
            position = sim.position
            if case .score = style {
                let d = Int((domain.value(at: sim.position)).rounded(.down))
                if d != detent { detent = d }
            }
        }
    }
}

// MARK: - Simulation

/// Hand-solved because SwiftUI animations can't report how fast the bead is
/// currently travelling, and the stretch is a function of exactly that.
///
/// The drama is deliberately extreme, and it scales with the value: at 1 the bead is
/// tight and snappy and barely deforms, at 10 it lags half a track behind your finger,
/// smears to two and a half times its length, tears into droplets and wobbles for a
/// second after you stop. How liquid it behaves *is* the reading.
@Observable
final class ScaleSim {
    var target: Double = 0
    private(set) var position: Double = 0
    /// Two followers at different lags, so the tail necks and breaks rather than
    /// trailing a single blob.
    private(set) var dripPosition: Double = 0
    private(set) var dripPosition2: Double = 0
    private(set) var stretch: Double = 0
    /// Vertical squash, kicked when the bead slams into either end cap.
    private(set) var impact: Double = 0

    /// 0...1. Drives every constant below; set from the live value each frame.
    var softness: Double = 0.5

    @ObservationIgnored private var spring = Spring1D(0, stiffness: 520, dampingRatio: 0.60)
    @ObservationIgnored private var impactSpring = Spring1D(0, stiffness: 320, dampingRatio: 0.26)

    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    func step(dt: Double) {
        let s = softness.clamped(to: 0...1)

        // Softer settings are looser and far less damped, so they overshoot the
        // target and keep ringing instead of arriving.
        spring.stiffness = Self.mix(560, 165, s)
        spring.dampingRatio = Self.mix(0.62, 0.20, s)

        let before = spring.value
        spring.step(toward: target, dt: dt)

        // Slamming into an end cap splats the bead rather than stopping it dead.
        if (spring.value <= 0 && before > 0) || (spring.value >= 1 && before < 1) {
            impactSpring.velocity += min(3.4, abs(spring.velocity) * 1.1)
        }
        spring.clamp(to: 0...1, restitution: Self.mix(0.18, 0.46, s))
        position = spring.value

        // Followers at two different lags. The gap between them is what makes the
        // tail neck and separate through the metaball filter.
        dripPosition  += (position - dripPosition)  * min(1, dt * Self.mix(13, 3.4, s))
        dripPosition2 += (dripPosition - dripPosition2) * min(1, dt * Self.mix(11, 2.4, s))

        // Stretch tracks live velocity. Capped high enough to genuinely smear.
        stretch = min(1.55, abs(spring.velocity) * Self.mix(0.16, 0.42, s))

        impactSpring.step(toward: 0, dt: dt)
        impact = impactSpring.value
    }

    /// Seeds the spring before the first frame, without animating into place.
    func reset(to value: Double) {
        spring = Spring1D(value, stiffness: 520, dampingRatio: 0.60)
        impactSpring = Spring1D(0, stiffness: 320, dampingRatio: 0.26)
        position = value
        dripPosition = value
        dripPosition2 = value
        target = value
        stretch = 0
        impact = 0
    }
}
