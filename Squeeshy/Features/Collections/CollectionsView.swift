import SwiftUI
import SwiftData

/// The front door. Smart shelves generated from traits, then any shelves made by hand.
struct CollectionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Squishy.addedAt, order: .reverse) private var squishies: [Squishy]
    @Query(sort: \Shelf.createdAt) private var shelves: [Shelf]

    /// Owned by RootView so the stack survives anything that replaces this view.
    ///
    /// NavigationPath rather than [ShelfRef]: a typed path can only ever hold its own
    /// element type, and FieldView pushes a squeeshy's UUID onto this same stack via
    /// `navigationDestination(item:)`. A UUID cannot go into a [ShelfRef], so that push
    /// silently did nothing and tapping a squeeshy in the field never opened anything.
    @Binding var path: NavigationPath
    /// The raw AppTheme value, owned by RootView because that is where it is applied.
    @Binding var theme: String
    /// The namespace the capture sheet zooms out of; owned by RootView, which presents it.
    var captureTransition: Namespace.ID
    var onCapture: () -> Void

    enum Route: Identifiable {
        case newShelf
        case contents(Shelf)

        var id: String {
            switch self {
            case .newShelf:          return "newShelf"
            case .contents(let s):   return "contents-\(s.id)"
            }
        }
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Smart shelves are enum cases, not model objects, so their pinned state cannot
    /// live on the model the way `Shelf.isPinned` does. Stored as raw values.
    @AppStorage("pinnedSmartShelves") private var pinnedSmartRaw = ""

    @State private var search = ""
    @State private var appeared = false
    @State private var route: Route?
    @State private var renaming: Shelf?
    @State private var renameText = ""
    /// Split-view only: which shelf the detail column is showing, and its own stack for
    /// pushing a squeeshy on top of it.
    @State private var selection: ShelfRef?
    @State private var detailPath = NavigationPath()

    private var tint: Tint { Tint.sampled(from: squishies.map(\.hue)) }

    var body: some View {
        Group {
            if isWide { splitLayout } else { stackLayout }
        }
        .tint(.white)
        // One sheet, one route. Declared separately, the contents picker never opened,
        // because SwiftUI keeps only the first `.sheet` on a view.
        .sheet(item: $route) { which in
            switch which {
            case .newShelf:
                NewShelfSheet { shelf in
                    // Straight from naming into filling it, so a new shelf is never
                    // empty. Re-routing rather than setting a second flag, and deferred
                    // a beat so the first sheet has finished dismissing.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        route = .contents(shelf)
                    }
                }
                .presentationDetents([.height(360)])
            case .contents(let shelf):
                ShelfContentsPicker(shelf: shelf)
            }
        }
        .alert("Rename shelf", isPresented: Binding(get: { renaming != nil },
                                                    set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let shelf = renaming, !renameText.isEmpty {
                    shelf.name = renameText
                    try? context.save()
                }
                renaming = nil
            }
        }
        .onAppear {
            withAnimation(Motion.arrive) { appeared = true }
            #if DEBUG
            if let shelf = DebugLaunch.openShelf {
                // The two layouts navigate differently, so the deep link has to as well.
                if isWide {
                    selection = .smart(shelf)
                } else if path.isEmpty {
                    path.append(ShelfRef.smart(shelf))
                }
            }
            #endif
        }
    }

    /// True on iPad, and on an iPad app given enough room in Split View. False on the
    /// phone and in a narrow Stage Manager column, where a sidebar would leave nothing
    /// for the field.
    private var isWide: Bool { sizeClass == .regular }

    // MARK: Layouts

    /// The phone: one column, shelves push onto a stack.
    private var stackLayout: some View {
        NavigationStack(path: $path) {
            ZStack {
                // The background lives inside the stack: pushed underneath it, a
                // NavigationStack paints its own opaque ground over anything behind.
                AdaptiveBackground(tint: tint)
                scroll
            }
            .navigationDestination(for: ShelfRef.self) { ref in
                destination(for: ref)
            }
        }
    }

    /// The iPad: shelves stay on screen in a sidebar and the field fills the rest, so
    /// the space is used rather than a phone column being stretched across it.
    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            ZStack {
                AdaptiveBackground(tint: tint)
                scroll
            }
            .navigationBarHidden(true)
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        } detail: {
            // Its own stack, so opening a squeeshy pushes inside the detail column
            // instead of replacing the whole window.
            NavigationStack(path: $detailPath) {
                ZStack {
                    AdaptiveBackground(tint: tint)
                    if let selection {
                        destination(for: selection, isRoot: true)
                    } else {
                        nothingSelected
                    }
                }
                .navigationDestination(for: ShelfRef.self) { ref in
                    destination(for: ref)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// The detail column before anything is picked. An iPad opens on this, so it is the
    /// first thing a new iPad user sees.
    private var nothingSelected: some View {
        VStack(spacing: 14) {
            Image(systemName: squishies.isEmpty ? "camera.viewfinder" : "hand.tap")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(Color.ink2)
            Text(squishies.isEmpty ? "No squeeshies yet" : "Pick a shelf")
                .font(.display(26, .heavy))
                .foregroundStyle(Color.ink)
            Text(squishies.isEmpty
                 ? "Photograph one and it lands here, sorted by colour, size and squeeshiness on its own."
                 : "Choose a shelf on the left and it opens here.")
                .font(.system(size: 15))
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
    }

    /// Shelves build themselves out of what you photograph, so the only thing to say
    /// here is what the camera button does. No illustration: the screen fills with the
    /// real thing soon enough.
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color.ink2)
                .padding(.top, 70)

            Text("No squeeshies yet")
                .font(.display(24, .heavy))
                .foregroundStyle(Color.ink)

            Text("Photograph one and it lands here, sorted by colour, size and squeeshiness on its own.")
                .font(.system(size: 14))
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)

            MetaLabel(text: "tap the camera, top right", color: .ink3)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    /// A shelf row. On the phone it pushes onto the stack; with a sidebar it sets the
    /// detail column instead, because pushing would slide the field over the very list
    /// the sidebar exists to keep visible.
    @ViewBuilder
    private func shelfLink<Content: View>(_ ref: ShelfRef,
                                          @ViewBuilder content: () -> Content) -> some View {
        if isWide {
            Button {
                // Reset the pushed squeeshy, or the new shelf opens under the old one's
                // detail view.
                detailPath = NavigationPath()
                selection = ref
            } label: { content() }
            .buttonStyle(.tap)
        } else {
            NavigationLink(value: ref) { content() }
                .buttonStyle(.tap)
        }
    }

    private var scroll: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    searchField

                    if !search.isEmpty {
                        sectionLabel("Matches")
                        ForEach(Array(searchResults.enumerated()), id: \.element.id) { i, s in
                            shelfLink(.single(s.id)) { SquishyRow(squishy: s) }
                            .rowEntrance(index: i, appeared: appeared)
                        }
                    } else if squishies.isEmpty {
                        // Nothing is seeded any more, so this is a real first run. A
                        // lone "Smart shelves" heading over empty space reads as a bug.
                        emptyState
                    } else {
                        if !pinnedSmart.isEmpty || !pinnedShelves.isEmpty {
                            sectionLabel("Pinned")
                            ForEach(Array(pinnedSmart.enumerated()), id: \.element.id) { i, shelf in
                                shelfLink(.smart(shelf)) {
                                    ShelfRow(title: shelf.title, items: items(in: shelf))
                                }
                                .rowEntrance(index: i, appeared: appeared)
                                .contextMenu { pinButton(for: shelf) }
                            }
                            ForEach(Array(pinnedShelves.enumerated()), id: \.element.id) { i, shelf in
                                shelfLink(.manual(shelf.id)) {
                                    ShelfRow(title: shelf.name, items: shelf.items ?? [])
                                }
                                .rowEntrance(index: i + pinnedSmart.count, appeared: appeared)
                                .contextMenu { shelfMenu(for: shelf) }
                            }
                        }

                        sectionLabel("Smart shelves")
                        ForEach(Array(unpinnedSmartShelves.enumerated()), id: \.element.id) { i, shelf in
                            shelfLink(.smart(shelf)) {
                                ShelfRow(title: shelf.title, items: items(in: shelf))
                            }
                            .rowEntrance(index: i, appeared: appeared)
                            .contextMenu { pinButton(for: shelf) }
                        }

                        if !unpinnedShelves.isEmpty {
                            sectionLabel("Yours")
                            ForEach(Array(unpinnedShelves.enumerated()), id: \.element.id) { i, shelf in
                                shelfLink(.manual(shelf.id)) {
                                    ShelfRow(title: shelf.name, items: shelf.items ?? [])
                                }
                                .rowEntrance(index: i + unpinnedSmartShelves.count, appeared: appeared)
                                .contextMenu { shelfMenu(for: shelf) }
                            }
                        }
                        MetaLabel(text: "hold a shelf to pin or edit it", color: .ink3)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        .scrollIndicators(.hidden)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Collections")
                    .font(.display(31, .heavy))
                    .foregroundStyle(Color.ink)
                MetaLabel(text: "\(squishies.count) squeeshies · \(populatedSmartShelves.count + shelves.count) shelves")
            }
            Spacer()
            ThemeToggle(theme: Binding(
                get: { AppTheme(rawValue: theme) ?? .dark },
                set: { theme = $0.rawValue }))
            Button { route = .newShelf } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.tap)
            .accessibilityIdentifier("newShelf")

            Button(action: onCapture) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.06, green: 0.04, blue: 0.09))
                    .frame(width: 38, height: 38)
                    .background(
                        LinearGradient(colors: [Tint.fallback.primary, Tint.fallback.secondary],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .circle
                    )
            }
            .buttonStyle(.tap)
            .accessibilityIdentifier("capture")
            .matchedTransitionSource(id: "capture", in: captureTransition)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.ink2)
            TextField("", text: $search, prompt: Text("Search your shelf").foregroundStyle(Color.ink3))
                .font(.system(size: 15))
                .foregroundStyle(Color.ink)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.ink3)
                }
                .buttonStyle(.tap)
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 44)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 6)
    }

    private func sectionLabel(_ text: String) -> some View {
        MetaLabel(text: text)
            .padding(.top, 14)
            .padding(.bottom, 2)
    }

    /// `isRoot` is true only for the thing sitting at the bottom of the iPad's detail
    /// column, which has nothing behind it — so it must not draw a back button that
    /// would do nothing when tapped.
    @ViewBuilder
    private func destination(for ref: ShelfRef, isRoot: Bool = false) -> some View {
        switch ref {
        case let .smart(shelf):
            FieldView(title: shelf.title, items: items(in: shelf),
                      trait: shelf.preferredTrait, smart: shelf, showsBack: !isRoot)
        case let .manual(id):
            let shelf = shelves.first { $0.id == id }
            FieldView(title: shelf?.name ?? "Shelf",
                      items: shelf?.items ?? [],
                      trait: .colour,
                      shelf: shelf,
                      showsBack: !isRoot)
        case let .single(id):
            if let s = squishies.first(where: { $0.id == id }) {
                ItemDetailView(items: squishies, startID: s.id,
                               shelfTitle: "Search", showsBack: !isRoot)
            }
        }
    }

    // MARK: Pinning

    /// Raw values of the pinned smart shelves. Kept as a comma-joined string because
    /// `@AppStorage` cannot hold a Set directly.
    private var pinnedSmartKeys: Set<String> {
        Set(pinnedSmartRaw.split(separator: ",").map(String.init))
    }

    private var pinnedSmart: [SmartShelf] {
        populatedSmartShelves.filter { pinnedSmartKeys.contains($0.rawValue) }
    }

    private var unpinnedSmartShelves: [SmartShelf] {
        populatedSmartShelves.filter { !pinnedSmartKeys.contains($0.rawValue) }
    }

    private var pinnedShelves: [Shelf] { shelves.filter(\.isPinned) }
    private var unpinnedShelves: [Shelf] { shelves.filter { !$0.isPinned } }

    private func togglePin(_ shelf: SmartShelf) {
        var keys = pinnedSmartKeys
        if keys.contains(shelf.rawValue) { keys.remove(shelf.rawValue) } else { keys.insert(shelf.rawValue) }
        pinnedSmartRaw = keys.sorted().joined(separator: ",")
    }

    private func togglePin(_ shelf: Shelf) {
        shelf.isPinned.toggle()
        try? context.save()
    }

    @ViewBuilder
    private func pinButton(for shelf: SmartShelf) -> some View {
        let pinned = pinnedSmartKeys.contains(shelf.rawValue)
        Button { togglePin(shelf) } label: {
            Label(pinned ? "Unpin" : "Pin to top",
                  systemImage: pinned ? "pin.slash" : "pin")
        }
    }

    /// Everything a hand-made shelf can do from a long press.
    @ViewBuilder
    private func shelfMenu(for shelf: Shelf) -> some View {
        Button { togglePin(shelf) } label: {
            Label(shelf.isPinned ? "Unpin" : "Pin to top",
                  systemImage: shelf.isPinned ? "pin.slash" : "pin")
        }
        Button { route = .contents(shelf) } label: {
            Label("Choose squeeshies", systemImage: "square.grid.2x2")
        }
        Button { renaming = shelf; renameText = shelf.name } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button(role: .destructive) { delete(shelf) } label: {
            Label("Delete shelf", systemImage: "trash")
        }
    }

    // MARK: Data

    private var populatedSmartShelves: [SmartShelf] {
        SmartShelf.allCases.filter { shelf in
            squishies.contains { shelf.matches($0) }
        }
    }

    private func items(in shelf: SmartShelf) -> [Squishy] {
        squishies.filter { shelf.matches($0) }
    }

    private var searchResults: [Squishy] {
        let q = search.lowercased()
        return squishies.filter {
            $0.name.lowercased().contains(q)
            || $0.typeName.lowercased().contains(q)
            || $0.colorName.lowercased().contains(q)
        }
    }

    private func delete(_ shelf: Shelf) {
        // Only the shelf goes; the squeeshies on it live in the collection, not here.
        context.delete(shelf)
        try? context.save()
    }
}

// MARK: - Shelf reference

enum ShelfRef: Hashable {
    case smart(SmartShelf)
    case manual(UUID)
    case single(UUID)
}

// MARK: - Rows

struct ShelfRow: View {
    var title: String
    var items: [Squishy]

    private var average: Double {
        guard !items.isEmpty else { return 0 }
        return items.map(\.squeeshiness).reduce(0, +) / Double(items.count)
    }

    var body: some View {
        HStack(spacing: 13) {
            MiniStack(items: items)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.display(16, .semibold))
                    .foregroundStyle(Color.ink)
                MetaLabel(text: items.isEmpty
                          ? "empty"
                          : "\(items.count) items · avg \(String(format: "%.1f", average))")
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink3)
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .rebuildsOnSchemeChange()
    }
}

struct SquishyRow: View {
    var squishy: Squishy

    var body: some View {
        HStack(spacing: 13) {
            SquishyImage(squishy: squishy)
                .frame(width: 44, height: 44)
                .padding(8)
                .glassEffect(.regular, in: .rect(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 3) {
                Text(squishy.name)
                    .font(.display(16, .semibold))
                    .foregroundStyle(Color.ink)
                MetaLabel(text: squishy.traitLine)
            }
            Spacer(minLength: 8)
            Text(String(format: "%.1f", squishy.squeeshiness))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.ink)
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .rebuildsOnSchemeChange()
    }
}

/// The four-up preview on every shelf row.
struct MiniStack: View {
    var items: [Squishy]

    var body: some View {
        LazyVGrid(columns: [GridItem(.fixed(22), spacing: 3), GridItem(.fixed(22), spacing: 3)], spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                if i < items.count {
                    SquishyImage(squishy: items[i], showsFace: false)
                        .frame(width: 22, height: 22)
                } else {
                    Circle().fill(.white.opacity(0.06)).frame(width: 22, height: 22)
                }
            }
        }
        .frame(width: 56, height: 56)
        .padding(5)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 17))
    }
}

// MARK: - Entrance

private extension View {
    /// Rows drop in on a stagger the first time the list appears.
    func rowEntrance(index: Int, appeared: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(Motion.arrive.delay(Motion.stagger(index)), value: appeared)
    }
}
