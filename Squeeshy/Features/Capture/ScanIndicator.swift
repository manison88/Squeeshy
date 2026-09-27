import SwiftUI

/// What the capture screen shows while `SubjectLift` runs Vision over the photo.
///
/// Four shapes drifting around a shared centre, each on its own timing so the group
/// never repeats a pose, over a status line that cycles through what is happening.
/// Replaces a spinner and a line of text, which read as a stall rather than as work.
struct ScanIndicator: View {

    /// Pastel, drawn from `Tint.fallback`'s two hues plus two neighbours. Deliberately
    /// not the saturated palette: this sits on screen for half a second at a time,
    /// several times in a row, and has to stay easy to look at.
    private static let palette: [Color] = [
        Color(red: 1.00, green: 0.58, blue: 0.73),
        Color(red: 0.62, green: 0.86, blue: 1.00),
        Color(red: 0.76, green: 0.68, blue: 1.00),
        Color(red: 1.00, green: 0.77, blue: 0.62)
    ]

    /// Where each shape rests, and how far it swings. The four are deliberately
    /// unequal — an even arrangement reads as a spinner.
    ///
    /// Wider than they look like they need to be: the swing carries each shape through
    /// the middle, so seats close to the centre put all four in the same place at once
    /// and the group reads as a pile rather than a handful.
    private static let seats: [CGSize] = [
        CGSize(width: -40, height: -30),
        CGSize(width:  36, height: -38),
        CGSize(width: -32, height:  38),
        CGSize(width:  42, height:  32)
    ]

    private static let steps = ["looking", "reading colour", "almost"]

    @State private var phase: Double = 0
    @State private var step = 0
    @State private var driver = DisplayLinkDriver()

    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    shape(i)
                        .frame(width: size(i), height: size(i))
                        .foregroundStyle(Self.palette[i])
                        .offset(offset(i))
                        .rotationEffect(.degrees(rotation(i)))
                        .scaleEffect(scaleFactor(i))
                }
            }
            .frame(width: 150, height: 150)

            MetaLabel(text: Self.steps[step])
                .contentTransition(.opacity)
                .animation(Motion.tap, value: step)
        }
        .onAppear {
            // Hand-driven rather than repeatForever, so the four can share one clock
            // and drift out of phase with each other rather than marching together.
            driver.start { dt in
                phase += dt
                let next = min(Self.steps.count - 1, Int(phase / 1.3))
                if next != step { step = next }
            }
        }
        .onDisappear { driver.stop() }
        .accessibilityElement()
        .accessibilityLabel("Finding the squeeshy in your photo")
    }

    // MARK: Shapes

    @ViewBuilder
    private func shape(_ i: Int) -> some View {
        switch i {
        case 0: Circle()
        case 1: RoundedRectangle(cornerRadius: 9, style: .continuous)
        case 2: Triangle()
        default: Sparkle()
        }
    }

    private func size(_ i: Int) -> CGFloat { [32, 28, 26, 24][i] }

    private static let period = 2.9

    /// Each shape runs the same loop a beat behind the last, so at any moment they are
    /// at four different points in it.
    ///
    /// Spread a full quarter-period apart rather than the prototype's tighter offset:
    /// every shape's path passes near the centre, so two shapes close in phase arrive
    /// there together and the group collapses into a pile.
    private func local(_ i: Int) -> Double {
        let offset = Double(i) * Self.period / 4
        return ((phase + offset).truncatingRemainder(dividingBy: Self.period)) / Self.period
    }

    private func offset(_ i: Int) -> CGSize {
        let t = local(i)
        let seat = Self.seats[i]
        // Three-point swing, matching the prototype: out, across, back.
        let x: Double, y: Double
        if t < 0.33 {
            let k = ease(t / 0.33)
            x = mix(seat.width, seat.width * -0.55, k)
            y = mix(seat.height, seat.height * 1.25, k)
        } else if t < 0.66 {
            let k = ease((t - 0.33) / 0.33)
            x = mix(seat.width * -0.55, seat.width * 1.25, k)
            y = mix(seat.height * 1.25, seat.height * -0.60, k)
        } else {
            let k = ease((t - 0.66) / 0.34)
            x = mix(seat.width * 1.25, seat.width, k)
            y = mix(seat.height * -0.60, seat.height, k)
        }
        return CGSize(width: x, height: y)
    }

    private func rotation(_ i: Int) -> Double { local(i) * 360 }

    private func scaleFactor(_ i: Int) -> Double {
        let t = local(i)
        if t < 0.33 { return mix(1.0, 0.78, ease(t / 0.33)) }
        if t < 0.66 { return mix(0.78, 1.14, ease((t - 0.33) / 0.33)) }
        return mix(1.14, 1.0, ease((t - 0.66) / 0.34))
    }

    private func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    /// Smoothstep, so the shapes ease in and out of each leg instead of cornering.
    private func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }
}

// MARK: - Shapes the framework does not provide

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Four-point star with concave sides, the shape everyone now reads as "AI is thinking".
private struct Sparkle: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let pts: [(Double, Double)] = [
            (0.50, 0.00), (0.61, 0.39), (1.00, 0.50), (0.61, 0.61),
            (0.50, 1.00), (0.39, 0.61), (0.00, 0.50), (0.39, 0.39)
        ]
        var p = Path()
        for (i, pt) in pts.enumerated() {
            let point = CGPoint(x: rect.minX + pt.0 * w, y: rect.minY + pt.1 * h)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }
}

#if DEBUG
#Preview {
    ZStack {
        AdaptiveBackground(tint: .fallback)
        ScanIndicator()
    }
}
#endif
