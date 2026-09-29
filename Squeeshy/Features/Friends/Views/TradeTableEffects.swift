import SwiftUI

// The trade table's moving parts: seats that hold several squeeshies, the view a
// seat expands into, the swap and the celebration after two yeses, and the stamp
// and sweep after a no. Timing lives in TradeTableView; these only draw.

enum TableSide: Hashable {
    case mine, theirs
}

// MARK: - A seat

/// One side of the table. Holds every squeeshy put in on that side: one fills the
/// seat, several sit together as a cluster with a count, and tapping opens the
/// full list. `swap` moves the squeeshies (not the label) during the exchange.
struct TableSeat: View {
    var title: String
    var items: [TradeTableSession.TableItem]
    var vote: Bool?
    var emptyText: String
    /// Hidden once the sweep has passed over them after a no.
    var isWiped: Bool = false
    /// Names belong to the seat, not the squeeshies, so they fade while the
    /// squeeshies cross to the other side.
    var hidesCaption: Bool = false
    var swapOffset: CGSize = .zero
    var swapRotation: Angle = .zero
    var swapScale: CGFloat = 1
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
                ZStack {
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
                            .offset(swapOffset)
                            .rotationEffect(swapRotation)
                            .scaleEffect(swapScale)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
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

// MARK: - A no

/// Slammed onto the board when someone says no.
struct NoTradeStamp: View {
    var reason: TradeTableSession.Rejection.Reason
    var partner: String
    @State private var landed = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .black))
                Text("NO TRADE")
                    .font(.mono(20, .bold))
                    .tracking(4)
            }
            MetaLabel(text: caption, color: .ink2)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.ink, lineWidth: 2.5))
        .rotationEffect(.degrees(landed ? -6 : -14))
        .scaleEffect(landed ? 1 : 2.2)
        .opacity(landed ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { landed = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No trade. \(caption).")
    }

    private var caption: String {
        switch reason {
        case .me: return "you said no"
        case .partner: return "\(partner) said no"
        case .itemLeft: return "one of yours isn't in your collection any more"
        }
    }
}

/// The squeegee that wipes the board clean after a no: a soft bright band that
/// crosses the table left to right. `progress` runs 0 → 1.
struct SweepBar: View, Animatable {
    var progress: Double

    /// Animatable, so the body is re-run with every in-between value. Otherwise an
    /// animated change to `progress` only interpolates the resolved modifiers, and
    /// the band would fade from invisible to invisible.
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { proxy in
            let band: CGFloat = 90
            let x = -band + (proxy.size.width + band * 2) * progress
            LinearGradient(colors: [.clear, .white.opacity(0.55), .white.opacity(0.85), .white.opacity(0.55), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: band)
                .blur(radius: 6)
                .rotationEffect(.degrees(8))
                .frame(maxHeight: .infinity)
                .offset(x: x - band / 2)
                .opacity(progress > 0 && progress < 1 ? 1 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Two yeses

/// A soft burst of the table's colours where the two squeeshies cross.
struct SwapGlow: View {
    var tint: Tint
    var isActive: Bool

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [tint.primary.opacity(0.9), tint.secondary.opacity(0.4), .clear],
                                 center: .center, startRadius: 0, endRadius: 90))
            .frame(width: 180, height: 180)
            .scaleEffect(isActive ? 1.5 : 0.2)
            .opacity(isActive ? 1 : 0)
            .blur(radius: 10)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

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
