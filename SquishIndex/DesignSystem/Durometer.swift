import SwiftUI

/// The product's signature control. SPEC.md §2, geometry from UX-SPEC §5.
///
/// Ten vertical bars on a shared baseline. As the value rises the filled bars
/// *compress* — shorter, wider, more rounded — conserving area exactly, so the
/// control behaves like an elastic solid rather than a widget with a bounce
/// bolted on. There is no thumb and no track fill: the boundary between the
/// short/fat run and the tall/thin run *is* the value indicator.
struct Durometer: View {
    @Binding var level: Int
    var isInteractive: Bool = true
    /// Tint for the filled bars. `nil` → ink. Set on the specimen sheet.
    var tint: Color?
    var trackWidth: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FocusState private var isFocused: Bool
    @State private var isDragging = false
    @State private var dragState = DragState()
    @State private var hapticsArmed = false

    static let trackHeight: CGFloat = 88
    static let maxTrackWidth: CGFloat = 340
    private static let hitHeight: CGFloat = 112
    private static let coordinateSpace = "durometer"

    private var fill: Color { tint ?? SquishTheme.ink }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = proxy.size.width
            let track = min(trackWidth ?? Self.maxTrackWidth, contentWidth)
            let leading = (contentWidth - track) / 2

            bars(track: track)
                .frame(width: track, height: Self.trackHeight, alignment: .bottom)
                .padding(.leading, leading)
                .frame(width: contentWidth, height: Self.hitHeight, alignment: .bottom)
                .contentShape(Rectangle())
                .coordinateSpace(name: Self.coordinateSpace)
                .gesture(drag(track: track, leading: leading),
                         including: isInteractive ? .all : .none)
                .overlay(alignment: .bottom) { focusRing(track: track) }
        }
        .frame(height: Self.hitHeight)
        .animation(animation, value: level)
        .focusable(isInteractive)
        .focused($isFocused)
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.downArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .onKeyPress(.upArrow) { step(1) }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard isInteractive, let digit = press.characters.first?.wholeNumberValue else { return .ignored }
            set(digit == 0 ? 10 : digit)
            return .handled
        }
        .sensoryFeedback(.selection, trigger: level) { _, _ in hapticsArmed }
        .sensoryFeedback(trigger: level) { _, new in
            hapticsArmed && new == 10 ? .impact(flexibility: .soft, intensity: 0.7) : nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Squish level")
        .accessibilityValue(SquishLevel(level).spokenValue)
        // An adjustable trait on a frozen control is a lie, so the read-only
        // durometer drops the action entirely. UX-SPEC §5.6.
        .modifier(AdjustableWhen(isInteractive: isInteractive, adjust: adjust))
    }

    // MARK: Bars

    private func bars(track: CGFloat) -> some View {
        let slot = track / 10
        let k = SquishLevel(level).k
        return HStack(spacing: 0) {
            ForEach(1...10, id: \.self) { index in
                DurometerBar(index: index, isFilled: index <= level, k: k, fill: fill)
                    .frame(width: slot, height: Self.trackHeight, alignment: .bottom)
            }
        }
    }

    @ViewBuilder
    private func focusRing(track: CGFloat) -> some View {
        // Ink rather than the system tint: the UI has no colour of its own.
        if isFocused, isInteractive {
            RoundedRectangle(cornerRadius: SquishTheme.Radius.pill, style: .continuous)
                .stroke(SquishTheme.ink, lineWidth: 2)
                .frame(width: track + 10, height: Self.trackHeight + 10)
                .allowsHitTesting(false)
        }
    }

    // MARK: Value mapping — UX-SPEC §5.3

    private func levelIndex(atX x: CGFloat, track: CGFloat) -> Int {
        let slot = track / 10
        guard slot > 0 else { return level }
        return min(10, max(1, Int((x / slot).rounded(.down)) + 1))
    }

    // MARK: Drag — positional, not relative. UX-SPEC §5.4

    private struct DragState {
        var startLevel: Int = 1
        var startedAt: Date = .distantPast
        var abandoned = false
        var began = false
    }

    private func drag(track: CGFloat, leading: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                if !dragState.began {
                    dragState = DragState(startLevel: level, startedAt: Date(), abandoned: false, began: true)
                    isDragging = true
                }
                guard !dragState.abandoned else { return }

                // Scroll-conflict guard: a mostly-vertical gesture in the first
                // 150 ms is a scroll, not a value change. Revert, silently.
                let elapsed = Date().timeIntervalSince(dragState.startedAt)
                let dy = abs(value.translation.height)
                if elapsed < 0.15, dy > 22, dy > 2 * abs(value.translation.width) {
                    dragState.abandoned = true
                    let wasArmed = hapticsArmed
                    hapticsArmed = false
                    level = dragState.startLevel
                    hapticsArmed = wasArmed
                    return
                }

                hapticsArmed = true
                let new = levelIndex(atX: value.location.x - leading, track: track)
                if new != level { level = new }
            }
            .onEnded { _ in
                isDragging = false
                dragState = DragState()
            }
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        guard isInteractive else { return .ignored }
        set(level + delta)
        return .handled
    }

    private func set(_ new: Int) {
        hapticsArmed = true
        level = min(10, max(1, new))
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment: set(level + 1)
        case .decrement: set(level - 1)
        @unknown default: break
        }
    }

    /// Two curves: a live drag wants a tighter response than a discrete set.
    /// This is the only bounce anywhere in the app — the durometer is the only
    /// thing modelling an elastic solid. UX-SPEC §5.7.
    private var animation: Animation? {
        guard !reduceMotion else { return nil }
        return isDragging
            ? .spring(duration: 0.16, bounce: 0.10)
            : .spring(duration: 0.26, bounce: 0.22)
    }
}

private struct AdjustableWhen: ViewModifier {
    let isInteractive: Bool
    let adjust: (AccessibilityAdjustmentDirection) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isInteractive {
            content.accessibilityAdjustableAction(adjust)
        } else {
            content
        }
    }
}

/// Pure geometry, no state. Factored out because screen 8's squish histogram is
/// the same object seen twice — same slot, same base heights, same lean.
/// UX-SPEC §3.2, §4.5.
struct DurometerBar: View {
    let index: Int
    let isFilled: Bool
    /// Compression, 0…1.
    let k: Double
    let fill: Color

    /// The lean: bar 1 is tallest, bar 10 shortest, total lean exactly one
    /// margin unit.
    static func baseHeight(_ index: Int) -> CGFloat {
        Durometer.trackHeight - CGFloat(index - 1) * (SquishTheme.Space.margin / 9)
    }

    static func width(k: Double) -> CGFloat { 12 + 14 * k }

    /// Reciprocal of the width factor — every bar's area is constant at every
    /// level. The material changes shape, not mass.
    static func height(index: Int, k: Double) -> CGFloat {
        baseHeight(index) * (12 / width(k: k))
    }

    static func radius(index: Int, k: Double) -> CGFloat {
        min(3 + 10 * k, width(k: k) / 2, height(index: index, k: k) / 2)
    }

    var body: some View {
        // An unfilled bar always renders at k = 0: it shows the scale's
        // ceiling, and the run of tall thin bars is what makes the value
        // boundary legible.
        let effectiveK = isFilled ? k : 0
        let w = Self.width(k: effectiveK)
        let h = Self.height(index: index, k: effectiveK)
        let r = Self.radius(index: index, k: effectiveK)

        RoundedRectangle(cornerRadius: r, style: .continuous)
            // Unfilled bars are `soft`, never `line` — they are meaningful
            // graphics and `line` measures 1.22:1 on putty. UX-SPEC §5.1.
            .fill(isFilled ? fill : SquishTheme.soft)
            .frame(width: w, height: h)
    }
}

#Preview {
    struct Harness: View {
        @State private var level = 5
        var body: some View {
            VStack(spacing: SquishTheme.Space.margin) {
                Durometer(level: $level)
                Text(SquishLevel(level).sentence).typeStyle(.b1)
                Durometer(level: .constant(9), isInteractive: false, tint: .orange)
            }
            .padding(SquishTheme.Space.margin)
            .background(SquishTheme.putty)
        }
    }
    return Harness()
}
