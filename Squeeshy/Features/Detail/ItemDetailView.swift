import SwiftUI
import SwiftData

/// What a squeeshy opens into. A hero you can grab and squash, and a fan of the rest
/// of the shelf you can throw. Whatever lands at centre becomes the hero.
struct ItemDetailView: View {
    var items: [Squishy]
    var startID: UUID
    var shelfTitle: String
    /// False when this is the root of the iPad's detail column.
    var showsBack: Bool = true

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var fan = FanSimulation()
    @State private var driver = DisplayLinkDriver()
    @State private var heroSquish = SquishSpring()
    /// Every sheet this screen can show, as one value.
    ///
    /// SwiftUI honours a single `.sheet` per view and silently drops the rest, so four
    /// separate ones meant only the first ever opened — the rating sheet, the trait
    /// chips and Add to collection were all dead behind the share sheet. One route,
    /// one presentation.
    enum Route: Identifiable {
        case rating
        case trait(EditableTrait)
        case addToShelf
        case share(URL)

        var id: String {
            switch self {
            case .rating:            return "rating"
            case .trait(let t):      return "trait-\(t.rawValue)"
            case .addToShelf:        return "addToShelf"
            case .share(let url):    return "share-\(url.lastPathComponent)"
            }
        }
    }

    @State private var route: Route?
    @State private var confirmingDelete = false
    /// A cover rather than another sheet: play mode is meant to be the whole screen with
    /// nothing else on it, and the root already owns the one `.sheet` this view gets.
    @State private var playing = false
    /// Furthest the finger moved during the current press, so a release can tell a tap
    /// from a squeeze.
    @State private var travelled: Double = 0
    @State private var editingName = false
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The iPad's detail column is several times the width of a phone, so the phone's
    /// fixed sizes leave the squeeshy marooned in the middle of it. One multiplier
    /// rather than a second set of numbers, so the two stay in proportion.
    private var scale: CGFloat { sizeClass == .regular ? 1.55 : 1 }

    private var hero: Squishy? {
        guard fan.index < items.count else { return items.first }
        return items[fan.index]
    }

    private var tint: Tint {
        guard let hero else { return .fallback }
        return Tint.single(hero.hue)
    }

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: tint)

            VStack(spacing: 0) {
                header
                heroBlock
                fanStrip
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            begin()
            #if DEBUG
            if DebugLaunch.openRating {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { route = .rating }
            }
            if DebugLaunch.openPlay {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { playing = true }
            }
            #endif
        }
        .onDisappear { driver.stop() }
        // The fan handing over a new squeeshy, and re-rating the current one, both
        // change how this should feel under the finger.
        .onChange(of: fan.index) { _, _ in
            heroSquish.softness = (hero?.squeeshiness ?? 7) / 10
            heroSquish.bump()
            wake()
        }
        .onChange(of: hero?.squeeshiness) { _, new in
            heroSquish.softness = (new ?? 7) / 10
        }
        .sheet(item: $route) { which in
            switch which {
            case .rating:
                if let hero {
                    RatingSheet(squishy: hero, tint: tint.primary)
                        .presentationDetents([.height(430)])
                        .presentationBackground(.clear)
                }
            case .trait(let t):
                TraitEditor(trait: t, squishy: hero)
                    .presentationDetents([.height(340)])
            case .addToShelf:
                if let hero { AddToShelfSheet(squishy: hero) }
            case .share(let url):
                ShareSheet(url: url)
            }
        }
        .fullScreenCover(isPresented: $playing) {
            if let hero { SqueeshyPlayView(squishy: hero) }
        }
    }

    /// Removes the squeeshy, its cut-out on disk, and its place on any hand-made
    /// shelves. Leaving the file behind would quietly grow the app's storage for
    /// something nothing can reach any more.
    private func deleteHero() {
        guard let hero else { return }

        for shelf in (try? context.fetch(FetchDescriptor<Shelf>())) ?? [] {
            if var contents = shelf.items, contents.contains(where: { $0.id == hero.id }) {
                contents.removeAll { $0.id == hero.id }
                shelf.items = contents
            }
        }
        PhotoStore.delete(hero.photoFilename)
        context.delete(hero)
        try? context.save()

        // `items` is a snapshot taken when this view was pushed, so the fan would keep
        // showing the deleted squeeshy. Stepping back to the shelf rebuilds it, and is
        // what you want anyway after deleting the thing you were looking at.
        dismiss()
    }

    /// Starts the clock, and stops it again the moment everything has settled. Left
    /// running it woke sixty times a second for as long as this screen was open.
    private func wake() {
        driver.start { dt in
            fan.step(dt: dt)
            heroSquish.step(dt: dt)
            if fan.isResting && heroSquish.isResting { driver.stop() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            if showsBack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 38, height: 38)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.tap)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(shelfTitle)
                    .font(.display(20, .bold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                MetaLabel(text: "card \(fan.index + 1) of \(items.count)")
            }
            Spacer()

            Button {
                if let hero, let url = ShareRenderer.png(for: .single(hero)) {
                    route = .share(url)
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.tap)
            .accessibilityIdentifier("share")

            Menu {
                Button { route = .addToShelf } label: {
                    Label("Add to collection", systemImage: "plus.rectangle.on.folder")
                }
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete squeeshy", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.interactive(), in: .circle)
                    // Not reached by TapStyle: see the shelf menu in FieldView.
                    .contentShape(.circle)
            }
            .accessibilityIdentifier("itemMenu")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        // Deliberately on the header rather than the root view: the root already owns
        // the one sheet, and a second presentation declared beside it is dropped.
        .confirmationDialog("Delete this squeeshy?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete \(hero?.name ?? "it")", role: .destructive) { deleteHero() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Its photo goes too. This cannot be undone.")
        }
    }

    // MARK: Hero

    private var heroBlock: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            if let hero {
                // A Button, not a bare `.onTapGesture`. Raw tap gestures on this view
                // never received a touch at all — not from a tap, a press, or a
                // synthesised tap on its exact centre — while every Button on the same
                // screen did. The squeeze rides along as a simultaneous drag.
                Button { playing = true } label: {
                    SquishyImage(squishy: hero)
                        .frame(width: 190 * scale, height: 190 * scale)
                        .squish(heroSquish.amount)
                        .shadow(color: hero.color.opacity(0.4), radius: 30, y: 12)
                        .contentShape(.rect)
                }
                .buttonStyle(.tap)
                .accessibilityIdentifier("hero")
                .accessibilityLabel("\(hero.name), tap to play with it")
                .simultaneousGesture(squishOrTap)
                .id(hero.id)
                .transition(.scale(scale: 0.8).combined(with: .opacity))

                nameField(for: hero)
                    .padding(.top, 14)

                traitChips(for: hero)
                    .padding(.top, 10)

                ratingButton(for: hero)
                    .padding(.top, 16)

                MetaLabel(text: "tap to play · swipe through your squeeshies", color: .ink3)
                    .padding(.top, 14)
            }

            Spacer(minLength: 8)
        }
        .animation(Motion.arrive, value: fan.index)
    }

    /// Tap the name to rename it. A `Button` rather than a tap gesture on the `Text`:
    /// bare tap gestures on this screen have not proved reliable, and the hero above had
    /// to become a Button for the same reason.
    @ViewBuilder
    private func nameField(for hero: Squishy) -> some View {
        if editingName {
            TextField("Name", text: $nameDraft)
                .font(.display(30, .heavy))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($nameFocused)
                .onSubmit { commitName(for: hero) }
                // Tapping away is a commit, not a cancel: losing a typed name because
                // you tapped the background is the more annoying outcome.
                .onChange(of: nameFocused) { _, focused in
                    if !focused { commitName(for: hero) }
                }
                .frame(maxWidth: 260)
        } else {
            Button {
                nameDraft = hero.name
                editingName = true
                nameFocused = true
            } label: {
                Text(hero.name)
                    .font(.display(30, .heavy))
                    .foregroundStyle(Color.ink)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.tap)
            .accessibilityIdentifier("heroName")
            .accessibilityLabel("\(hero.name), tap to rename")
        }
    }

    private func commitName(for hero: Squishy) {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty name would leave the squeeshy unfindable, so blank means unchanged.
        if !trimmed.isEmpty, trimmed != hero.name {
            hero.name = trimmed
            try? context.save()
        }
        editingName = false
        nameFocused = false
    }

    /// Every trait is a chip you can tap. No edit mode, no form.
    private func traitChips(for hero: Squishy) -> some View {
        HStack(spacing: 6) {
            chip(hero.shapeName, .shape)
            chip(hero.size.label, .size)
            chip(hero.colorName, .colour)
        }
    }

    private func chip(_ label: String, _ trait: EditableTrait) -> some View {
        Button { route = .trait(trait) } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.5)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.tap)
    }

    private func ratingButton(for hero: Squishy) -> some View {
        Button { route = .rating } label: {
            HStack(spacing: 10) {
                Text("Squeeshiness")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text(String(format: "%.1f", hero.squeeshiness))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.05, green: 0.04, blue: 0.08))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(tint.primary, in: .capsule)
                    .contentTransition(.numericText())
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .frame(height: 48)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.tap)
    }

    /// Squeeze on a drag, open play mode on a tap. Distinguished by how far the finger
    /// actually moved rather than by gesture priority.
    private var squishOrTap: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                wake()
                travelled = max(travelled, hypot(g.translation.width, g.translation.height))
                heroSquish.grab(Double(g.translation.height) / 190)
            }
            .onEnded { _ in
                heroSquish.release()
                travelled = 0
            }
    }

    // MARK: Fan

    private var fanStrip: some View {
        ZStack(alignment: .bottom) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let near = fan.nearness(for: i)
                if near > 0.02 {
                    FanCard(item: item, scale: scale)
                        .scaleEffect(0.9 + near * 0.2)
                        .offset(y: -near * near * 26)
                        // Anchored well below the cards so the arc stays shallow;
                        // a nearer anchor swings the outer cards across the screen.
                        .rotationEffect(.degrees(fan.angle(for: i)),
                                        anchor: UnitPoint(x: 0.5, y: 2.5))
                        .opacity(near * near)
                        .zIndex(near)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 168 * scale)
        // Keeps the outer cards from bleeding up into the hero or down over the dock.
        .clipShape(.rect)
        .contentShape(.rect)
        .gesture(fanGesture)
        // The dock is gone, so this only needs to clear the home indicator.
        .padding(.bottom, 26)
    }

    private var fanGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { g in wake(); fan.drag(translation: Double(g.translation.width)) }
            .onEnded { g in fan.release(velocity: Double(g.velocity.width)) }
    }

    // MARK: Lifecycle

    private func begin() {
        fan.count = items.count
        fan.snap(to: items.firstIndex { $0.id == startID } ?? 0)
        heroSquish.softness = (hero?.squeeshiness ?? 7) / 10
        wake()
    }
}

// MARK: - Fan card

/// Just the squeeshy. It used to be a glass card with a gradient behind it and its
/// name underneath, which turned the fan into a row of containers you looked at
/// instead of a row of squeeshies.
struct FanCard: View {
    var item: Squishy
    var scale: CGFloat = 1

    var body: some View {
        SquishyImage(squishy: item)
            .frame(width: 74 * scale, height: 74 * scale)
            // Keeps each one legible against the ones behind it now that there is no
            // card edge separating them.
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            .frame(width: 86 * scale, height: 118 * scale)
    }
}

// MARK: - Fan physics

/// Momentum then a spring into the nearest detent. The hero above tracks whatever is
/// closest to centre, even mid-throw.
@Observable
final class FanSimulation {
    var count: Int = 0
    private(set) var index: Int = 0
    private(set) var offset: Double = 0

    @ObservationIgnored private var velocity: Double = 0
    @ObservationIgnored private var dragging = false
    @ObservationIgnored private let step: Double = 11

    func snap(to i: Int) {
        index = i
        offset = -Double(i) * step
        velocity = 0
    }

    func drag(translation: Double) {
        dragging = true
        offset = base + translation * 0.34
    }

    @ObservationIgnored private var base: Double = 0

    func release(velocity v: Double) {
        dragging = false
        base = offset
        velocity = max(-420, min(420, v * 0.34))
    }

    func angle(for i: Int) -> Double { Double(i) * step + offset }

    /// 1 at dead centre, falling to 0 by three and a half cards out.
    func nearness(for i: Int) -> Double {
        max(0, 1 - abs(angle(for: i)) / (step * 2.8))
    }

    func step(dt: Double) {
        guard count > 0 else { return }
        if !dragging {
            // Once it has settled there is nothing to integrate, and writing an
            // unchanged value to an observed property still invalidates every view
            // reading it — which kept the whole detail screen re-rendering sixty times
            // a second with nothing moving, at around 38% CPU.
            let resting = -Double(nearestIndex) * step
            if abs(velocity) < 0.5, abs(offset - resting) < 0.01 {
                if offset != resting { offset = resting; base = resting }
                if nearestIndex != index { index = nearestIndex }
                return
            }
            if abs(velocity) > 6 {
                offset += velocity * dt
                velocity *= pow(0.06, dt)
            } else {
                let target = -Double(nearestIndex) * step
                let k = 150.0, c = 2 * 150.0.squareRoot() * 0.82
                velocity += (-(offset - target) * k - velocity * c) * dt
                offset += velocity * dt
            }
            let limit = step * 0.6
            let maxOffset = limit
            let minOffset = -Double(count - 1) * step - limit
            if offset > maxOffset { offset = maxOffset; velocity *= -0.3 }
            if offset < minOffset { offset = minOffset; velocity *= -0.3 }
            base = offset
        }
        if nearestIndex != index { index = nearestIndex }
    }

    /// True once the fan has stopped moving and snapped to a detent.
    var isResting: Bool {
        !dragging && abs(velocity) < 0.5 && abs(offset - (-Double(nearestIndex) * step)) < 0.01
    }

    private var nearestIndex: Int {
        min(max(0, Int((-offset / step).rounded())), max(0, count - 1))
    }
}

// MARK: - Hero squish

/// Deforms under the finger, then springs back — how far and for how long depends on
/// the squeeshy's own rating, so squeezing a 9 feels nothing like squeezing a 2. Every
/// constant below used to be fixed, which meant the rating was a number on a capsule
/// and nothing else.
@Observable
final class SquishSpring {
    private(set) var amount: Double = 0

    /// 0 is a stress ball you can barely dent, 1 the softest thing on the shelf.
    @ObservationIgnored var softness: Double = 0.7

    @ObservationIgnored private var spring = Spring1D(0, stiffness: 320, dampingRatio: 0.45)
    @ObservationIgnored private var held = false

    /// How far it deforms at all: a 1 dents, a 10 folds nearly in half.
    private var travel: Double { Self.mix(0.11, 0.52, softness) }
    /// Firm things snap straight back; soft things take their time getting there.
    private var stiffness: Double { Self.mix(620, 148, softness) }
    /// And once there, soft things keep wobbling.
    private var damping: Double { Self.mix(0.74, 0.15, softness) }

    func grab(_ value: Double) {
        held = true
        // Soft squeeshies also give way faster for the same drag distance, so the
        // difference is felt on the way down as well as on the way back.
        let gain = Self.mix(0.55, 1.5, softness)
        // Asymmetric: pulling up stretches less readily than pressing down squashes.
        amount = (value * gain).clamped(to: -travel * 0.78 ... travel)
    }

    func release() {
        held = false
        spring = Spring1D(amount, stiffness: stiffness, dampingRatio: damping)
        spring.velocity = -amount * Self.mix(9, 22, softness)
    }

    /// Nudges the hero when the fan hands it a new squeeshy, so arrivals bounce — by
    /// an amount that already tells you how soft the new one is.
    func bump() {
        held = false
        let start = travel * 0.42
        spring = Spring1D(start, stiffness: stiffness, dampingRatio: damping)
        spring.velocity = Self.mix(3, 8, softness)
        amount = start
    }

    func step(dt: Double) {
        guard !held else { return }
        // Same reasoning as FanSimulation: settled means stop writing.
        if amount == 0, spring.isAtRest { return }
        spring.step(toward: 0, dt: dt)
        amount = spring.value
        if abs(amount) < 0.001 && spring.isAtRest { amount = 0 }
    }

    /// Whether anything is still moving, so a screen with nothing else animating can
    /// park its display link instead of waking sixty times a second forever.
    var isResting: Bool { !held && amount == 0 && spring.isAtRest }

    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * min(1, max(0, t))
    }
}
