import SwiftUI

/// The eight body plans the vision pass can recognise. Real photos replace these
/// once capture is wired up; until then they stand in for the cut-out.
enum Species: String, CaseIterable, Codable, Sendable {
    case round, cat, bun, axo, dino, star, loaf, wide

    var shapeName: String {
        switch self {
        case .round, .cat, .bun, .axo: return "Round"
        case .dino:                    return "Long"
        case .star:                    return "Star"
        case .loaf:                    return "Tall"
        case .wide:                    return "Wide"
        }
    }
}

/// Draws a squeeshy in a 100x100 space, scaled to fit. Everything is one Canvas
/// pass so a field of twenty of them stays cheap enough to animate every frame.
struct SquishyArt: View {
    var species: Species
    var color: Color
    /// Fraction of the body length the face sits over; kept constant so the
    /// character reads the same at 24pt and 240pt.
    var showsFace: Bool = true

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            SquishyArt.draw(&ctx, in: CGRect(origin: .zero, size: size),
                            species: species, color: color, showsFace: showsFace)
        }
        .aspectRatio(1, contentMode: .fit)
        .allowsHitTesting(false)
    }

    /// Shared by the standalone view and by the bubble field, which draws every
    /// squeeshy into one Canvas so twenty of them can animate on one pass.
    static func draw(_ ctx: inout GraphicsContext, in rect: CGRect,
                     species: Species, color: Color, showsFace: Bool = true,
                     opacity: Double = 1) {
        var ctx = ctx
        ctx.opacity = opacity
        let side = min(rect.width, rect.height)
        let s = side / 100
        ctx.translateBy(x: rect.midX - side / 2, y: rect.midY - side / 2)
        ctx.scaleBy(x: s, y: s)

        let shading = GraphicsContext.Shading.color(color)
        for path in bodyPaths(species) {
            ctx.fill(path, with: shading)
        }
        if case .star = species {
            // Rounded joins fatten the star into something plush rather than sharp.
            ctx.stroke(starPath(), with: shading,
                       style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
        }

        // Two highlights give the body volume. They fade radially rather than sitting
        // as flat ellipses, which at large sizes read as bald patches.
        let hlCentre = CGPoint(x: 33, y: 37)
        let tilt = CGAffineTransform(translationX: hlCentre.x, y: hlCentre.y)
            .rotated(by: -0.45)
            .translatedBy(x: -hlCentre.x, y: -hlCentre.y)
        ctx.fill(Path(ellipseIn: CGRect(x: 15, y: 25, width: 36, height: 24)).applying(tilt),
                 with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.34), .white.opacity(0)]),
                    center: hlCentre, startRadius: 0, endRadius: 19))
        let bellyCentre = CGPoint(x: 50, y: 76)
        ctx.fill(Path(ellipseIn: CGRect(x: 25, y: 60, width: 50, height: 32)),
                 with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.17), .white.opacity(0)]),
                    center: bellyCentre, startRadius: 0, endRadius: 26))

        if showsFace { drawFace(&ctx) }
    }

    // MARK: - Faces

    private static func drawFace(_ ctx: inout GraphicsContext) {
        let blush = GraphicsContext.Shading.color(Color(red: 1, green: 0.30, blue: 0.49).opacity(0.34))
        ctx.fill(Path(ellipseIn: CGRect(x: 19, y: 60, width: 16, height: 10)), with: blush)
        ctx.fill(Path(ellipseIn: CGRect(x: 65, y: 60, width: 16, height: 10)), with: blush)

        let eye = GraphicsContext.Shading.color(Color(red: 0.13, green: 0.11, blue: 0.17).opacity(0.86))
        ctx.fill(Path(ellipseIn: CGRect(x: 33.8, y: 49.8, width: 8.4, height: 10.4)), with: eye)
        ctx.fill(Path(ellipseIn: CGRect(x: 57.8, y: 49.8, width: 8.4, height: 10.4)), with: eye)

        let glint = GraphicsContext.Shading.color(.white.opacity(0.85))
        ctx.fill(Path(ellipseIn: CGRect(x: 37.9, y: 51.5, width: 3.0, height: 3.4)), with: glint)
        ctx.fill(Path(ellipseIn: CGRect(x: 61.9, y: 51.5, width: 3.0, height: 3.4)), with: glint)

        var mouth = Path()
        mouth.move(to: CGPoint(x: 44, y: 64))
        mouth.addQuadCurve(to: CGPoint(x: 56, y: 64), control: CGPoint(x: 50, y: 69.5))
        ctx.stroke(mouth, with: .color(Color(red: 0.13, green: 0.11, blue: 0.17).opacity(0.62)),
                   style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
    }

    // MARK: - Bodies

    private static func bodyPaths(_ species: Species) -> [Path] {
        switch species {
        case .round:
            return [circle(23, 29, 12), circle(77, 29, 12),
                    ellipse(9, 21, 82, 74)]
        case .cat:
            return [triangle((18, 42), (25, 6), (49, 29)),
                    triangle((82, 42), (75, 6), (51, 29)),
                    ellipse(10, 23, 80, 72)]
        case .bun:
            return [rotatedEllipse(24.5, -2, 17, 44, -0.21, around: CGPoint(x: 33, y: 20)),
                    rotatedEllipse(58.5, -2, 17, 44, 0.21, around: CGPoint(x: 67, y: 20)),
                    ellipse(12, 27, 76, 68)]
        case .axo:
            return [circle(11, 40, 8.5), circle(6, 55, 7.5), circle(12, 69, 6.5),
                    circle(89, 40, 8.5), circle(94, 55, 7.5), circle(88, 69, 6.5),
                    ellipse(12, 23, 76, 70)]
        case .dino:
            return [triangle((26, 30), (32, 13), (42, 27)),
                    triangle((44, 22), (52, 5), (61, 20)),
                    triangle((63, 27), (74, 15), (79, 32)),
                    tail(), ellipse(10, 27, 80, 68)]
        case .star:
            return [starPath()]
        case .loaf:
            return [circle(27, 20, 9.5), circle(73, 20, 9.5),
                    roundedRect(16, 16, 68, 79, 34)]
        case .wide:
            return [circle(24, 34, 9), circle(76, 34, 9),
                    roundedRect(4, 29, 92, 61, 30.5)]
        }
    }

    // MARK: - Primitives

    private static func circle(_ cx: Double, _ cy: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    private static func ellipse(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path {
        Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h))
    }

    private static func roundedRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
    }

    private static func rotatedEllipse(_ x: Double, _ y: Double, _ w: Double, _ h: Double,
                                       _ angle: Double, around pivot: CGPoint) -> Path {
        let t = CGAffineTransform(translationX: pivot.x, y: pivot.y)
            .rotated(by: angle)
            .translatedBy(x: -pivot.x, y: -pivot.y)
        return Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)).applying(t)
    }

    private static func triangle(_ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double)) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: a.0, y: a.1))
        p.addLine(to: CGPoint(x: b.0, y: b.1))
        p.addLine(to: CGPoint(x: c.0, y: c.1))
        p.closeSubpath()
        return p
    }

    private static func tail() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 86, y: 66))
        p.addQuadCurve(to: CGPoint(x: 95, y: 87), control: CGPoint(x: 102, y: 72))
        p.addQuadCurve(to: CGPoint(x: 79, y: 74), control: CGPoint(x: 83, y: 84))
        p.closeSubpath()
        return p
    }

    fileprivate static func starPath() -> Path {
        let pts: [(Double, Double)] = [
            (50, 14), (61.4, 40.6), (90.2, 43), (68.4, 62), (74.9, 89.6),
            (50, 75), (25.1, 89.6), (31.6, 62), (9.8, 43), (38.6, 40.6)
        ]
        var p = Path()
        p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for pt in pts.dropFirst() { p.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
        p.closeSubpath()
        return p
    }
}

// MARK: - Squish

/// Volume-preserving squash: pushing down widens, pulling up narrows. `amount` is
/// positive when compressed. Anchored at the base so it reads as sitting on a surface.
extension View {
    func squish(_ amount: Double, anchor: UnitPoint = .bottom) -> some View {
        scaleEffect(x: 1 + amount * 0.34, y: 1 - amount * 0.38, anchor: anchor)
    }
}

#Preview {
    ZStack {
        AdaptiveBackground(tint: .fallback)
        LazyVGrid(columns: [.init(.adaptive(minimum: 80))], spacing: 16) {
            ForEach(Species.allCases, id: \.self) { s in
                SquishyArt(species: s, color: Hue.color(Double(Species.allCases.firstIndex(of: s)!) * 44))
                    .frame(width: 80, height: 80)
            }
        }
        .padding()
    }
}
