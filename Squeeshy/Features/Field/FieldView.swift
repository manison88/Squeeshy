import SwiftUI

/// What a shelf opens into. The trait control across the top is scoped to this
/// shelf's own range, and drives the field underneath it live.
struct FieldView: View {
    var title: String
    var items: [Squishy]
    var trait: Trait
    /// Set only for hand-made collections. Smart shelves are derived from traits, so
    /// there is nothing to edit or delete on one.
    var shelf: Shelf? = nil
    /// Set only for smart shelves, so this screen can pin one. Smart shelves are enum
    /// cases rather than model objects, so their pinned state lives in AppStorage.
    var smart: SmartShelf? = nil
    /// False when this is the root of the iPad's detail column, where there is nothing
    /// to go back to.
    var showsBack: Bool = true

    @AppStorage("pinnedSmartShelves") private var pinnedSmartRaw = ""

    @State private var activeTrait: Trait
    @State private var sliderPosition: Double = 0.5
    @State private var sim = FieldSimulation()
    @State private var driver = DisplayLinkDriver()
    @State private var selected: UUID?
    /// One route, one `.sheet`. Two sheets on the same view means the second never
    /// opens, which is what made "Choose squeeshies" do nothing behind the share sheet.
    enum Route: Identifiable {
        case contents
        case share(URL)

        var id: String {
            switch self {
            case .contents:       return "contents"
            case .share(let url): return "share-\(url.lastPathComponent)"
            }
        }
    }

    @State private var route: Route?
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    init(title: String, items: [Squishy], trait: Trait,
         shelf: Shelf? = nil, smart: SmartShelf? = nil, showsBack: Bool = true) {
        self.title = title
        self.items = items
        self.trait = trait
        self.shelf = shelf
        self.smart = smart
        self.showsBack = showsBack
        _activeTrait = State(initialValue: trait)
    }

    /// How strongly each squeeshy's halo burns. It carries the match signal — a bubble
    /// that matches the slider glows harder — so it earns its place, but at full
    /// strength it lit the whole field and the cut-outs read as blurry.
    private static let defaultGlow = 0.30

    private var glowStrength: Double {
        #if DEBUG
        // Dial it on a device without rebuilding: -glowStrength 0.4
        let d = UserDefaults.standard
        if d.object(forKey: "glowStrength") != nil { return d.double(forKey: "glowStrength") }
        #endif
        return Self.defaultGlow
    }

    private var domain: TraitDomain {
        TraitDomain.compute(activeTrait, items: items)
    }

    private var tint: Tint {
        Tint.sampled(from: items.map(\.hue))
    }

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: tint)

            VStack(spacing: 0) {
                header
                controls
                field
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selected) { id in
            ItemDetailView(items: items, startID: id, shelfTitle: title)
        }
        .sheet(item: $route) { which in
            switch which {
            case .contents:
                if let shelf { ShelfContentsPicker(shelf: shelf) }
            case .share(let url):
                ShareSheet(url: url)
            }
        }
        .onAppear {
            begin()
            #if DEBUG
            if let i = DebugLaunch.openItem, i < items.count {
                // Long enough that the stack has finished pushing this view first. At
                // 0.4s the write landed mid-push and was dropped about half the time,
                // which reads as "the deep link is broken" when it is only early.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { selected = items[i].id }
            }
            #endif
        }
        .onDisappear { driver.stop() }
        .onChange(of: activeTrait) { _, newTrait in
            sim.updateTraitValues(items, trait: newTrait)
            // Re-centre the slider when the axis changes so it always starts
            // somewhere meaningful in the new range.
            sliderPosition = 0.5
            sim.score(domain: domain, sliderValue: domain.value(at: 0.5))
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
                Text(title)
                    .font(.display(24, .heavy))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                MetaLabel(text: "\(items.count) squeeshies")
            }
            Spacer()

            Button {
                if let url = ShareRenderer.png(for: .shelf(title: title, items: items)) {
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

            // Reachable from inside the collection rather than by long-pressing the row
            // on the previous screen: a long press on a NavigationLink activates the
            // link instead of opening the menu, and it is not a gesture anyone finds.
            if shelf != nil || smart != nil {
                Menu {
                    Button { togglePin() } label: {
                        Label(isPinned ? "Unpin" : "Pin to top",
                              systemImage: isPinned ? "pin.slash" : "pin")
                    }
                    if shelf != nil {
                        Button { route = .contents } label: {
                            Label("Choose squeeshies", systemImage: "square.grid.2x2")
                        }
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Label("Delete collection", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 38, height: 38)
                        .glassEffect(.regular.interactive(), in: .circle)
                        // A Menu's label never sees `TapStyle`, so the whole 38pt
                        // circle has to be claimed here or only the glyph is tappable.
                        .contentShape(.circle)
                }
                .accessibilityIdentifier("shelfMenu")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 14)
        // On the header, not the root: the root owns the sheet, and a second
        // presentation declared alongside it is dropped.
        .confirmationDialog("Delete this collection?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete \(title)", role: .destructive) {
                if let shelf {
                    // Only the shelf goes. The squeeshies on it belong to the
                    // collection, not to this grouping of it.
                    context.delete(shelf)
                    try? context.save()
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The squeeshies on it are kept.")
        }
    }

    // MARK: Pinning

    private var isPinned: Bool {
        if let shelf { return shelf.isPinned }
        if let smart { return pinnedSmartRaw.split(separator: ",").contains(Substring(smart.rawValue)) }
        return false
    }

    private func togglePin() {
        if let shelf {
            shelf.isPinned.toggle()
            try? context.save()
            return
        }
        guard let smart else { return }
        var keys = Set(pinnedSmartRaw.split(separator: ",").map(String.init))
        if keys.contains(smart.rawValue) { keys.remove(smart.rawValue) } else { keys.insert(smart.rawValue) }
        pinnedSmartRaw = keys.sorted().joined(separator: ",")
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 16) {
            traitPicker

            GlassScale(domain: domain,
                       style: scaleStyle,
                       position: $sliderPosition,
                       tint: tint.primary)
                .onChange(of: sliderPosition) { _, p in
                    sim.score(domain: domain, sliderValue: domain.value(at: p))
                }
                .opacity(domain.isSingleValued ? 0.4 : 1)
                .allowsHitTesting(!domain.isSingleValued)
                .animation(Motion.tap, value: domain.isSingleValued)

            HStack {
                if domain.isSingleValued {
                    Text("all \(items.count) are the same")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.ink2)
                } else {
                    Text("\(sim.matchCount)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.ink)
                    + Text(" of \(items.count) match")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.ink2)
                }
                Spacer()
                MetaLabel(text: domain.isSingleValued ? "try another axis" : "drag to stir")
            }
        }
        .padding(.horizontal, 20)
    }

    private var scaleStyle: GlassScaleStyle {
        switch activeTrait {
        case .colour: return .hueBand(lower: domain.lower, upper: domain.upper)
        default:      return .ramp
        }
    }

    private var traitPicker: some View {
        HStack(spacing: 3) {
            ForEach(Trait.allCases) { t in
                Button {
                    withAnimation(Motion.tap) { activeTrait = t }
                } label: {
                    Text(t.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(activeTrait == t ? Color.onInk : Color.ink2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if activeTrait == t {
                                Capsule().fill(Color.ink)
                            }
                        }
                }
                .buttonStyle(.tap)
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: Field

    private var field: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                for b in sim.bubbles {
                    let d = b.diameter
                    let rect = CGRect(x: b.x * size.width - d / 2,
                                      y: b.y * size.height - d / 2,
                                      width: d, height: d)

                    // Halo in the squeeshy's own colour, brighter the better it matches.
                    // It is the only thing drawn behind the squeeshy now — the disc and
                    // its ring read as a container the squeeshy was sitting in, and the
                    // name under every bubble made a shelf of a dozen look like a list.
                    if glowStrength > 0 {
                        ctx.fill(Path(ellipseIn: rect.insetBy(dx: -d * 0.16, dy: -d * 0.16)),
                                 with: .radialGradient(
                                    Gradient(colors: [b.color.opacity(glowStrength * (0.35 + b.match * 0.65)), .clear]),
                                    center: CGPoint(x: rect.midX, y: rect.midY),
                                    // Tighter than it was: a wide soft halo at low
                                    // opacity just fogs the ground around the squeeshy.
                                    startRadius: 0, endRadius: d * 0.60))
                    }

                    // Full rect, not inset: with no ring to sit inside, the inset only
                    // shrank the squeeshy away from the size its match earned it.
                    ctx.drawSquishy(b.squishy, in: rect,
                                    showsFace: d > 54,
                                    opacity: 0.46 + b.match * 0.54)
                }
            }
            .contentShape(.rect)
            .onTapGesture { point in
                if let id = sim.bubble(at: point) {
                    selected = id
                }
            }
            .onAppear {
                sim.size = geo.size
                sim.score(domain: domain, sliderValue: domain.value(at: sliderPosition))
            }
            .onChange(of: geo.size) { _, new in
                sim.size = new
                // Bubble sizes are derived from the field, so a rotation or a Split
                // View resize has to re-score or they keep the old device's scale.
                sim.score(domain: domain, sliderValue: domain.value(at: sliderPosition))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        // The dock is gone; the field can run nearly to the bottom edge now.
        .padding(.bottom, 24)
    }

    // MARK: Lifecycle

    private func begin() {
        sim.load(items, trait: activeTrait)
        // Must follow load: the field's own onAppear fires first as a child, so
        // scoring there alone would run against an empty bubble array.
        sim.score(domain: domain, sliderValue: domain.value(at: sliderPosition))
        driver.start { dt in sim.step(dt: dt) }
    }
}
