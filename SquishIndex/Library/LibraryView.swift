import SwiftData
import SwiftUI

enum LibraryTab: String, CaseIterable, Hashable {
    case grid, shelf, stats

    var title: String {
        switch self {
        case .grid: "Grid"
        case .shelf: "Shelf"
        case .stats: "Stats"
        }
    }
}

/// Screens 1, 2, 7 and 8 — everything behind the Grid · Shelf · Stats control.
///
/// The band holding the control and the chip row lives in a `safeAreaInset`
/// rather than a `toolbar`: system bars adopt Liquid Glass on iOS 26 and would
/// fight the locked flat direction. UX-SPEC §8.
@MainActor
struct LibraryView: View {
    /// On iPad the sidebar carries Friends, so the Grid header doesn't.
    var showsFriendsButton = true

    @Query(sort: \Squishy.addedAt, order: .reverse) private var allSpecimens: [Squishy]
    @Environment(FriendsStore.self) private var friendsStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tab: LibraryTab = .grid
    @State private var sort: SortOption = .recent
    @State private var filter = LibraryFilter.none
    @State private var showSortOptions = false
    @State private var showFilterSheet = false
    @State private var scrollOffset: CGFloat = 0

    @State private var flow = CaptureFlow()
    @State private var isCapturing = false
    @State private var renaming: Squishy?
    @State private var adjustingSquish: Squishy?
    @State private var pendingDeletion: Squishy?
    @State private var showFriends = false

    /// Traded-away specimens stay in the store as an archive (Trades → Traded
    /// away) but leave the catalogue, its counts and its stats.
    private var specimens: [Squishy] { allSpecimens.filter { !$0.isTraded } }

    private var organised: [Squishy] {
        LibraryOrganiser.organise(specimens, sort: sort, filter: filter)
    }

    private var stats: LibraryStats { LibraryStats(specimens: specimens) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                SquishTheme.putty.ignoresSafeArea()
                GeometryReader { proxy in
                    content(width: proxy.size.width)
                }
                if !specimens.isEmpty {
                    FloatingCTA(title: "Capture",
                                systemImage: "camera",
                                isCollapsed: !reduceMotion && scrollOffset > 60) {
                        beginCapture()
                    }
                    .padding(.trailing, SquishTheme.Space.margin)
                    .padding(.bottom, SquishTheme.Space.margin)
                    .animation(SquishTheme.Motion.select, value: scrollOffset > 60)
                }
            }
            .navigationDestination(for: Squishy.self) { specimen in
                SpecimenDetailView(specimen: specimen)
            }
            .navigationDestination(isPresented: $showFriends) {
                FriendsView()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(SquishTheme.ink)
        .fullScreenCover(isPresented: $isCapturing) { captureCover }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheet(filter: $filter, specimens: specimens)
        }
        .confirmationDialog("Sort by", isPresented: $showSortOptions, titleVisibility: .visible) {
            ForEach(SortOption.allCases) { option in
                Button(option.title) { sort = option }
                    .disabled(!option.isEnabled(for: specimens))
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove this specimen?",
                            isPresented: Binding(get: { pendingDeletion != nil },
                                                 set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible) {
            Button("Delete from index", role: .destructive) {
                if let pendingDeletion {
                    modelContext.delete(pendingDeletion)
                    try? modelContext.save()
                }
                pendingDeletion = nil
            }
            Button("Keep it", role: .cancel) { pendingDeletion = nil }
        }
        .sheet(item: $renaming) { specimen in
            RenameSheet(specimen: specimen)
        }
        .sheet(item: $adjustingSquish) { specimen in
            AdjustSquishSheet(specimen: specimen)
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            header
            band
            Group {
                switch tab {
                case .grid:
                    if specimens.isEmpty {
                        EmptyStateView { beginCapture() }
                            .transition(.opacity)
                    } else if organised.isEmpty {
                        noMatches.transition(.opacity)
                    } else {
                        gridScroll(width: width).transition(.opacity)
                    }
                case .shelf:
                    TrueScaleShelfView(specimens: organised)
                case .stats:
                    StatsView(stats: stats)
                }
            }
            .animation(reduceMotion ? nil : SquishTheme.Motion.select, value: tab)
            .animation(SquishTheme.Motion.reveal, value: specimens.isEmpty)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: SquishTheme.Space.gutter) {
            IndexHeader(title: "Squish Index",
                        specimenCount: specimens.count,
                        averageSquish: stats.averageSquish,
                        filteredCount: filter.isActive ? organised.count : nil)
            if showsFriendsButton {
                friendsButton
            }
        }
        .padding(.horizontal, SquishTheme.Space.margin)
        .padding(.top, SquishTheme.Space.gutter)
    }

    /// One icon button, with a count badge for things waiting on this user —
    /// the badge carries the state, not a colour. Design/FRIENDS-AND-TRADING.md.
    private var friendsButton: some View {
        Button { showFriends = true } label: {
            Image(systemName: "person.2")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(SquishTheme.ink)
                .frame(width: 44, height: 44)
                .background(SquishTheme.chalk, in: Circle())
                .overlay(Circle().strokeBorder(SquishTheme.line, lineWidth: SquishTheme.hairline))
                .overlay(alignment: .topTrailing) {
                    if friendsStore.badgeCount > 0 {
                        CountBadge(count: friendsStore.badgeCount)
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Friends")
        .accessibilityValue(friendsStore.badgeCount > 0 ? "\(friendsStore.badgeCount) waiting" : "")
    }

    /// Shelf and Stats are disabled, not hidden, on an empty library: the empty
    /// state's job is to teach the app's shape, and hiding two thirds of the
    /// navigation defeats that.
    private var segments: [SegmentedControl<LibraryTab>.Option] {
        LibraryTab.allCases.map {
            SegmentedControl<LibraryTab>.Option(value: $0,
                                                title: $0.title,
                                                isEnabled: $0 == .grid || !specimens.isEmpty)
        }
    }

    private var band: some View {
        VStack(spacing: SquishTheme.Space.gutter) {
            SegmentedControl(selection: $tab, options: segments)
            .padding(.horizontal, SquishTheme.Space.margin)

            ScrollView(.horizontal) {
                HStack(spacing: SquishTheme.Space.sm) {
                    Chip(title: sort.chipTitle,
                         trailingCaret: true,
                         isCaretUp: showSortOptions,
                         isEnabled: !specimens.isEmpty,
                         accessibilityLabelText: "Sort",
                         accessibilityValueText: sort.title) {
                        showSortOptions = true
                    }
                    Chip(title: "Filter",
                         count: filter.isActive ? filter.activeCount : nil,
                         isActive: filter.isActive,
                         isEnabled: !specimens.isEmpty,
                         accessibilityLabelText: "Filter",
                         accessibilityValueText: filter.isActive ? "\(filter.activeCount) active" : "Off") {
                        showFilterSheet = true
                    }
                    if filter.isActive {
                        Chip(title: "Clear", isEnabled: true) {
                            withAnimation(SquishTheme.Motion.select) { filter = .none }
                        }
                    }
                }
                .padding(.horizontal, SquishTheme.Space.margin)
            }
            .scrollIndicators(.hidden)

            HairlineRule()
                .opacity(min(1, max(0, scrollOffset / 8)))
        }
        .padding(.top, SquishTheme.Space.margin)
        .background(SquishTheme.putty)
    }

    private func gridScroll(width: CGFloat) -> some View {
        ScrollView {
            ScrollOffsetReader { scrollOffset = $0 }

            if typeSize.isAccessibilitySize {
                LazyVStack(spacing: SquishTheme.Space.margin) {
                    ForEach(organised) { specimen in
                        cardLink(specimen) { SpecimenRow(specimen: specimen) }
                    }
                }
                .padding(.horizontal, SquishTheme.Space.margin)
                .padding(.top, SquishTheme.Space.gutter)
            } else {
                // Two-up on a phone; more columns on an iPad, so cards stay
                // specimen-sized rather than stretching to half a 13-inch screen.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SquishTheme.Space.gutter),
                                         count: AdaptiveGrid.columns(for: width)),
                          spacing: SquishTheme.Space.margin) {
                    ForEach(organised) { specimen in
                        cardLink(specimen) {
                            SpecimenCard(specimen: specimen, width: cardWidth(in: width))
                        }
                    }
                }
                .padding(.horizontal, SquishTheme.Space.margin)
                .padding(.top, SquishTheme.Space.gutter)
            }

            Color.clear.frame(height: 96)
        }
        .scrollIndicators(.hidden)
        .coordinateSpace(name: LibraryView.scrollSpace)
    }

    static let scrollSpace = "libraryScroll"

    private func cardWidth(in width: CGFloat) -> CGFloat {
        AdaptiveGrid.cardWidth(for: width, columns: AdaptiveGrid.columns(for: width))
    }

    private func cardLink<Content: View>(_ specimen: Squishy,
                                         @ViewBuilder content: () -> Content) -> some View {
        NavigationLink(value: specimen) {
            content()
                .scrollTransition(.interactive, axis: .vertical) { view, phase in
                    // Asymmetric on purpose: cards settle in as they arrive and
                    // do nothing as they leave, so scrolling back up never
                    // looks like a rendering bug. UX-SPEC §4.1.
                    view
                        .opacity(reduceMotion || phase.value <= 0 ? 1 : 1 - phase.value * 0.40)
                        .scaleEffect(reduceMotion || phase.value <= 0 ? 1 : 1 - phase.value * 0.02)
                }
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .contextMenu {
            Button("Rename") { renaming = specimen }
            Button("Change squish") { adjustingSquish = specimen }
            Button(specimen.isKeeping ? "Open to trade" : "Keep — don't trade") {
                specimen.isKeeping.toggle()
                try? modelContext.save()
            }
            Button("Delete…", role: .destructive) { pendingDeletion = specimen }
        }
    }

    private var noMatches: some View {
        VStack(spacing: 0) {
            Spacer()
            Eyebrow("No matches")
            Text("No specimen matches these filters.")
                .typeStyle(.b1)
                .foregroundStyle(SquishTheme.ink)
                .padding(.top, SquishTheme.Space.gutter)
            Button {
                withAnimation(SquishTheme.Motion.select) { filter = .none }
            } label: {
                Text("Clear filters")
                    .typeStyle(.b2)
                    .foregroundStyle(SquishTheme.chalk)
                    .padding(.horizontal, SquishTheme.Space.margin)
                    .frame(height: 44)
                    .background(SquishTheme.ink, in: Capsule())
            }
            .padding(.top, SquishTheme.Space.margin)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Capture

    private var captureCover: some View {
        Group {
            switch flow.step {
            case .viewfinder:
                CaptureView(flow: flow) { endCapture() }
            case .naming, .measuring:
                NameSpecimenView(flow: flow,
                                 library: specimens,
                                 onCancel: { endCapture() },
                                 onFiled: { _ in endCapture() })
            }
        }
        .animation(reduceMotion ? nil : SquishTheme.Motion.reveal, value: flow.step)
    }

    private func beginCapture() {
        flow.reset()
        flow.libraryPrints = specimens.map { (id: $0.id, print: $0.featurePrint) }
        isCapturing = true
    }

    private func endCapture() {
        isCapturing = false
        flow.reset()
    }
}

// MARK: - Scroll offset

private struct OffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A zero-height probe at the top of a scroll view. Cheaper and more portable
/// than a scroll-geometry observer, and the only consumer is a hairline's
/// opacity and the CTA's collapse.
private struct ScrollOffsetReader: View {
    let onChange: @MainActor (CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: OffsetKey.self,
                                   value: -proxy.frame(in: .named(LibraryView.scrollSpace)).minY)
        }
        .frame(height: 0)
        .onPreferenceChange(OffsetKey.self) { value in
            Task { @MainActor in onChange(value) }
        }
    }
}
