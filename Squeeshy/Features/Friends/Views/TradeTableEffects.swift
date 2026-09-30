import SwiftUI

// The trade table's moving parts: seats that hold several squeeshies, the view a
// seat expands into, the portals that swap them after two yeses (and glitch and
// throw them back after a no), and the celebration. Timing lives in
// TradeTableView; these only draw.

enum TableSide: Hashable {
    case mine, theirs
}

// MARK: - A seat

/// What the portal under a seat is doing, as the table stages it.
struct SeatPortal: Equatable {
    /// 0 closed, 1 fully open.
    var open: CGFloat = 0
    var hue: Double = 330
    /// Flickering grey after a no, just before it throws the squeeshies back.
    var glitching = false
    /// When the squeeshies came up through it, for the sparks.
    var sparksAt: Date?
}

/// One side of the table. Holds every squeeshy put in on that side: one fills the
/// seat, several sit together as a cluster with a count, and tapping opens the
/// full list. During a trade a portal opens under the seat and the squeeshies
/// sink into it (`sink`), or are thrown back up out of it (`lift`).
struct TableSeat: View {
    var title: String
    var items: [TradeTableSession.TableItem]
    var vote: Bool?
    var emptyText: String
    /// Hidden once they've dissolved after a no.
    var isWiped: Bool = false
    /// Names belong to the seat, not the squeeshies, so they fade while the
    /// squeeshies go through the portals.
    var hidesCaption: Bool = false
    var portal = SeatPortal()
    /// 0 sitting on the seat, 1 all the way through the portal.
    var sink: CGFloat = 0
    /// Points above the seat, when a refused squeeshy is thrown back out.
    var lift: CGFloat = 0
    /// Sideways shudder while the portal glitches.
    var jitter: CGFloat = 0
    var onOpen: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                MetaLabel(text: title, color: .ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                VoteMark(vote: vote)
            }
            Button(action: onOpen) {
                GeometryReader { proxy in
                    let side = proxy.size.width
                    let plane = side * PortalRing.plane
                    let active = portal.open > 0.001 || sink > 0.001
                    ZStack {
                        PortalRing(open: portal.open, hue: portal.hue,
                                   glitching: portal.glitching, sparksAt: portal.sparksAt)
                            .frame(width: side * 1.4, height: side * 1.4)
                            .position(x: side / 2, y: side / 2)
                        if items.isEmpty {
                            RoundedRectangle(cornerRadius: 24)
                                .strokeBorder(Color.ink3, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .overlay(MetaLabel(text: emptyText, color: .ink3).multilineTextAlignment(.center))
                                .transition(.opacity)
                        } else {
                            SeatCluster(items: items)
                                .padding(items.count == 1 ? 14 : 10)
                                .opacity(isWiped ? 0 : 1)
                                .scaleEffect(isWiped ? 0.6 : 1)
                                .blur(radius: isWiped ? 6 : 0)
                                .offset(x: jitter, y: sink * side * 0.9 - lift)
                                // The portal's surface: whatever has sunk below it is gone.
                                .mask(alignment: .top) {
                                    Rectangle()
                                        .frame(height: (active ? plane : side * 2) + side * 3)
                                        .offset(y: -side * 3)
                                }
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                    }
                    .frame(width: side, height: side)
                }
                .aspectRatio(1, contentMode: .fit)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
                .overlay(alignment: .topTrailing) {
                    if items.count > 1 && !isWiped {
                        CountBadge(count: items.count)
                            .padding(8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(.tap(24))
            .disabled(items.isEmpty)
            .accessibilityHint(items.isEmpty ? "" : "Shows everything on this side")

            Text(caption)
                .font(.display(15, .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(minHeight: 20)
                .opacity(isWiped || hidesCaption ? 0 : 1)
                .animation(.easeOut(duration: 0.2), value: hidesCaption)
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.arrive, value: items)
        .animation(Motion.tap, value: isWiped)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(items.isEmpty ? "Empty" : items.map(\.name).joined(separator: ", "))
    }

    private var caption: String {
        switch items.count {
        case 0: return ""
        case 1: return items[0].name
        // The count badge and the tappable seat say the rest; a longer caption
        // wraps in a half-width seat.
        default: return "\(items.count) squeeshies"
        }
    }
}

/// Up to four squeeshies arranged to fill a square seat. More than four shows the
/// first three and a "+N" tile, because a fifth squeezed in would be too small to
/// recognise — the expanded view is where all of them are.
struct SeatCluster: View {
    var items: [TradeTableSession.TableItem]

    var body: some View {
        switch items.count {
        case 0:
            EmptyView()
        case 1:
            picture(items[0])
        case 2:
            HStack(spacing: 4) {
                picture(items[0])
                picture(items[1])
            }
        case 3:
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    picture(items[0])
                    picture(items[1])
                }
                picture(items[2])
            }
        default:
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    picture(items[0])
                    picture(items[1])
                }
                HStack(spacing: 4) {
                    picture(items[2])
                    if items.count == 4 {
                        picture(items[3])
                    } else {
                        Text("+\(items.count - 3)")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.white.opacity(0.08), in: .rect(cornerRadius: 14))
                    }
                }
            }
        }
    }

    private func picture(_ item: TradeTableSession.TableItem) -> some View {
        LooseSquishyImage(image: item.image, species: item.species, color: item.color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
    }
}

// MARK: - Expanded seat

/// Everything on one side of the table, big enough to recognise. Opened by tapping
/// a seat; on your own side each squeeshy can be taken off from here.
struct SeatExpanded: View {
    var title: String
    var items: [TradeTableSession.TableItem]
    var canRemove: Bool
    var onRemove: (String) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.display(22, .heavy))
                        .foregroundStyle(Color.ink)
                    MetaLabel(text: items.count == 1 ? "1 squeeshy" : "\(items.count) squeeshies")
                }
                Spacer()
                GlassCircleButton(systemImage: "xmark", label: "Close", action: onClose)
            }
            if items.isEmpty {
                Text("Nothing here now.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ink2)
                    .padding(.vertical, 30)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            tile(item, index: index)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(18)
        .frame(maxWidth: 560, maxHeight: 520)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .padding(20)
    }

    private func tile(_ item: TradeTableSession.TableItem, index: Int) -> some View {
        VStack(spacing: 6) {
            LooseSquishyImage(image: item.image, species: item.species, color: item.color)
                .frame(width: 84, height: 84)
            Text(item.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
            MetaLabel(text: String(format: "squeesh %.1f", item.squeeshiness))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .overlay(alignment: .topTrailing) {
            if canRemove {
                Button { onRemove(item.id) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.ink, Color.ink.opacity(0.12))
                        .padding(6)
                }
                .buttonStyle(.tap)
                .accessibilityLabel("Take \(item.name) off the table")
            }
        }
        .modifier(Arrival(index: index))
        .accessibilityElement(children: .combine)
    }
}

/// Tiles drop in on a stagger, the way shelf rows do.
private struct Arrival: ViewModifier {
    var index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(Motion.arrive.delay(Motion.stagger(index, step: 0.05))) { shown = true }
            }
    }
}

// MARK: - Portals

/// A glowing portal lying flat under a seat: a dark hole ringed with arcs of
/// colour that spin. Drawn in a canvas sized 1.4× the seat and centred on it, so
/// the glow and the sparks can spill past the seat's edges.
struct PortalRing: View, Animatable {
    /// Where the portal's surface sits, as a fraction of the seat's height.
    static let plane: CGFloat = 0.82

    var open: CGFloat
    var hue: Double
    var glitching: Bool
    var sparksAt: Date?

    /// Animatable, so opening and closing re-run the canvas with every in-between size.
    var animatableData: CGFloat {
        get { open }
        set { open = newValue }
    }

    var body: some View {
        let sparking = sparksAt.map { Date.now.timeIntervalSince($0) < 1 } ?? false
        TimelineView(.animation(minimumInterval: nil, paused: open <= 0.001 && !sparking)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let seat = size.width / 1.4
                let centre = CGPoint(x: size.width / 2, y: size.height / 2 + seat * (Self.plane - 0.5))
                if open > 0.001 { drawRing(in: context, centre: centre, seat: seat, now: now) }
                if let sparksAt { drawSparks(in: context, centre: centre, seat: seat, age: timeline.date.timeIntervalSince(sparksAt)) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawRing(in context: GraphicsContext, centre: CGPoint, seat: CGFloat, now: TimeInterval) {
        var ctx = context
        ctx.translateBy(x: centre.x, y: centre.y)
        ctx.scaleBy(x: 1, y: 0.28)
        let r = seat * 0.44 * open
        let saturation = glitching ? 0.15 : 0.75
        let flicker = glitching ? 0.45 + 0.55 * abs(sin(now * 40)) : 1
        let rim = Color(hue: Hue.wrap(hue) / 360, saturation: saturation, brightness: 1)

        let glow = Path(ellipseIn: CGRect(x: -r * 1.4, y: -r * 1.4, width: r * 2.8, height: r * 2.8))
        ctx.fill(glow, with: .radialGradient(
            Gradient(stops: [.init(color: .black, location: 0),
                             .init(color: .black, location: 0.58),
                             .init(color: rim.opacity(0.8 * flicker), location: 0.7),
                             .init(color: rim.opacity(0), location: 1)]),
            center: .zero, startRadius: 0, endRadius: r * 1.4))

        for k in 0..<4 {
            let spin = now * 5 * (k.isMultiple(of: 2) ? 1 : -1.3) + Double(k) * 1.6
            var arc = Path()
            arc.addArc(center: .zero, radius: r * (0.78 + CGFloat(k) * 0.07),
                       startAngle: .radians(spin), endAngle: .radians(spin + 2.2), clockwise: false)
            let colour = Color(hue: Hue.wrap(hue + Double(k) * 22) / 360, saturation: saturation * 0.7, brightness: 1)
            ctx.stroke(arc, with: .color(colour.opacity(0.9 * flicker)),
                       style: StrokeStyle(lineWidth: CGFloat(7 - k), lineCap: .round))
        }
    }

    /// Little stars that rise off the rim as the squeeshies come up through it.
    private func drawSparks(in context: GraphicsContext, centre: CGPoint, seat: CGFloat, age: TimeInterval) {
        guard age >= 0, age < 1 else { return }
        let fade = 1 - age
        for i in 0..<16 {
            // Fixed per-spark randomness, so nothing needs storing between frames.
            let a = sin(Double(i) * 12.9898) * 43758.5453, b = sin(Double(i) * 78.233) * 12345.678
            let dx = (a - a.rounded(.down)) * 2 - 1, rise = 90 + (b - b.rounded(.down)) * 110
            let x = centre.x + dx * seat * 0.4
            let y = centre.y - rise * age
            let s = 2.4 * fade + 1
            var star = Path()
            star.move(to: CGPoint(x: x, y: y - s * 2))
            star.addQuadCurve(to: CGPoint(x: x + s * 2, y: y), control: CGPoint(x: x, y: y))
            star.addQuadCurve(to: CGPoint(x: x, y: y + s * 2), control: CGPoint(x: x, y: y))
            star.addQuadCurve(to: CGPoint(x: x - s * 2, y: y), control: CGPoint(x: x, y: y))
            star.addQuadCurve(to: CGPoint(x: x, y: y - s * 2), control: CGPoint(x: x, y: y))
            let colour = Color(hue: Hue.wrap(hue + Double(i % 3) * 30) / 360, saturation: 0.5, brightness: 1)
            context.fill(star, with: .color(colour.opacity(fade)))
        }
    }
}

/// Two arcs of light between the portals while the squeeshies are through them,
/// each with comets running along it. `progress` runs 0 → 1; the arcs swell in
/// and fade out over that span. Drawn over the board's seat row.
struct PortalBeams: View, Animatable {
    var progress: Double
    var hues: (mine: Double, theirs: Double)

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            guard progress > 0, progress < 1 else { return }
            // The seat row: label (24) + spacing (8), then two square seats either
            // side of a 20pt arrow with 10pt gaps.
            let seat = (size.width - 40) / 2
            let y = 32 + seat * PortalRing.plane
            let left = CGPoint(x: seat / 2, y: y), right = CGPoint(x: size.width - seat / 2, y: y)
            let strength = sin(.pi * progress)
            var ctx = context
            ctx.blendMode = .plusLighter
            for (from, to, lift, hue) in [(left, right, 170.0, hues.mine), (right, left, 110.0, hues.theirs)] {
                let control = CGPoint(x: (from.x + to.x) / 2, y: y - lift)
                var path = Path()
                path.move(to: from)
                path.addQuadCurve(to: to, control: control)
                let colour = Color(hue: Hue.wrap(hue) / 360, saturation: 0.55, brightness: 1)
                for (width, alpha) in [(14.0, 0.12), (5.0, 0.5), (1.5, 0.95)] {
                    ctx.stroke(path, with: .color(colour.opacity(alpha * strength)),
                               style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
                for k in 0..<3 {
                    let u = (progress * 1.4 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                    let p = CGPoint(x: (1 - u) * (1 - u) * from.x + 2 * (1 - u) * u * control.x + u * u * to.x,
                                    y: (1 - u) * (1 - u) * from.y + 2 * (1 - u) * u * control.y + u * u * to.y)
                    let comet = Path(ellipseIn: CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28))
                    ctx.fill(comet, with: .radialGradient(
                        Gradient(colors: [.white.opacity(strength), colour.opacity(0)]),
                        center: p, startRadius: 0, endRadius: 14))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - A no

/// What the board says once a no has cleared it. Stays until something new goes on.
struct NoTradeNotice: View {
    var reason: TradeTableSession.Rejection.Reason
    var partner: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color.ink)
                .frame(width: 34, height: 34)
                .background(Color.ink.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.display(16, .semibold))
                    .foregroundStyle(Color.ink)
                MetaLabel(text: "table cleared · put in something new")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch reason {
        case .me: return "You said no"
        case .partner: return "\(partner) said no"
        case .itemLeft: return "One of yours isn't in your collection any more"
        }
    }
}

// MARK: - Two yeses

/// Confetti in the traded squeeshies' own colours. Drawn in one Canvas pass and
/// stopped once it has fallen, so it costs nothing afterwards.
struct ConfettiBurst: View {
    var hues: [Double]

    private struct Piece {
        var angle: Double
        var speed: Double
        var spin: Double
        var size: CGSize
        var hue: Double
        var isRound: Bool
    }

    @State private var pieces: [Piece] = []
    @State private var start = Date.now
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: finished)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.34)
                let fade = max(0, 1 - max(0, t - 1.5) / 1.0)
                guard fade > 0 else { return }
                for piece in pieces {
                    let x = origin.x + cos(piece.angle) * piece.speed * t
                    let y = origin.y + sin(piece.angle) * piece.speed * t + 0.5 * 1100 * t * t
                    var ctx = context
                    ctx.opacity = fade
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .radians(piece.spin * t))
                    let rect = CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2,
                                      width: piece.size.width, height: piece.size.height)
                    let path = piece.isRound ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 2)
                    ctx.fill(path, with: .color(Color(hue: Hue.wrap(piece.hue) / 360,
                                                      saturation: 0.55, brightness: 1)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            let palette = hues.isEmpty ? [330.0, 200.0] : hues
            pieces = (0..<110).map { i in
                let isRound = i % 4 == 0
                let w = isRound ? Double.random(in: 7...11) : Double.random(in: 6...10)
                return Piece(angle: Double.random(in: (-Double.pi + 0.25)...(-0.25)),
                             speed: Double.random(in: 420...980),
                             spin: Double.random(in: -9...9),
                             size: CGSize(width: w, height: isRound ? w : w * Double.random(in: 1.6...2.4)),
                             hue: palette[i % palette.count] + Double.random(in: -12...12),
                             isRound: isRound)
            }
            start = .now
            Task {
                try? await Task.sleep(for: .seconds(2.7))
                finished = true
            }
        }
    }
}

/// What both phones show once a table trade is filed: a stamp that slams down,
/// confetti, and the squeeshies that just changed hands arriving.
struct TradedCelebration: View {
    var received: [TradeTableSession.TableItem]
    var given: [TradeTableSession.TableItem]
    var tint: Tint
    var onDone: () -> Void
    var onAgain: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamped = false
    @State private var arrived = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                ConfettiBurst(hues: (received + given).map(\.hue))
                    .ignoresSafeArea()
            }
            VStack(spacing: 18) {
                Spacer()
                Text("TRADED")
                    .font(.mono(18, .bold))
                    .tracking(6)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ink, lineWidth: 2.5))
                    .rotationEffect(.degrees(stamped ? -5 : -18))
                    .scaleEffect(stamped ? 1 : 2.6)
                    .opacity(stamped ? 1 : 0)
                    .accessibilityHidden(true)

                HStack(spacing: -18) {
                    ForEach(Array(received.prefix(4).enumerated()), id: \.element.id) { index, item in
                        LooseSquishyImage(image: item.image, species: item.species, color: item.color)
                            .frame(width: 120, height: 120)
                            .shadow(color: item.color.opacity(0.45), radius: 24, y: 10)
                            .scaleEffect(arrived ? 1 : 0.2)
                            .offset(y: arrived ? 0 : 60)
                            .opacity(arrived ? 1 : 0)
                            .animation(Motion.rebound.delay(0.25 + Double(index) * 0.1), value: arrived)
                            .zIndex(Double(4 - index))
                    }
                }
                .padding(.top, 6)

                Text(title)
                    .font(.display(28, .heavy))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                Text("Swap the real squeeshies now. What you got is in your collection with its cut-out and traits, and what you gave is under Trades → Traded away.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Spacer()
                VStack(spacing: 10) {
                    TintedCTA(title: "Done", tint: tint, action: onDone)
                    GlassCTA(title: "Trade again", action: onAgain)
                }
                .frame(maxWidth: 420)
                .opacity(arrived ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.7), value: arrived)
            }
            .padding(22)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.34, dampingFraction: 0.5)) {
                stamped = true
            }
            arrived = true
        }
    }

    private var title: String {
        let names = received.map(\.name)
        guard !names.isEmpty else { return "Traded" }
        return "\(names.joined(separator: " and ")) \(names.count == 1 ? "is" : "are") yours"
    }
}

// MARK: - Vote mark

/// ✓ / ✗ / thinking — a shape and a word, never colour alone.
struct VoteMark: View {
    var vote: Bool?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: vote == true ? "checkmark.circle.fill"
                  : vote == false ? "xmark.circle" : "circle.dashed")
                .font(.system(size: 14, weight: .semibold))
            Text(vote == true ? "YES" : vote == false ? "NO" : "THINKING")
                .font(.mono(9, .semibold))
                .tracking(1)
        }
        .foregroundStyle(vote == nil ? Color.ink3 : Color.ink)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .glassEffect(.regular, in: .capsule)
        .contentTransition(.symbolEffect(.replace))
        .animation(Motion.tap, value: vote)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(vote == true ? "Voted yes" : vote == false ? "Voted no" : "Not voted yet")
    }
}
