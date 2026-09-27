import SwiftData
import SwiftUI

/// iPhone: the library, with Friends pushed from its header.
/// iPad (regular width): a split view — library, friends and trades in a
/// sidebar, the selection beside it. Compact-width iPad multitasking falls
/// back to the iPhone layout automatically.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(FriendsStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Query private var allSpecimens: [Squishy]

    /// Changes whenever anything a friend could see changes.
    private var shelfSignature: [String] {
        allSpecimens.map { "\($0.lineageID)|\($0.isTraded)|\($0.shelfRevision)" }
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                SplitRootView()
            } else {
                LibraryView(showsFriendsButton: true)
            }
        }
        .task { await store.start() }
        .onChange(of: shelfSignature) { store.schedulePublish() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
        .alert(shareBackTitle,
               isPresented: Binding(get: { store.pendingShareBack != nil },
                                    set: { if !$0 { store.pendingShareBack = nil } })) {
            Button("Share mine") {
                store.pendingShareBack = nil
                Task {
                    if let share = try? await store.shareForInvite() {
                        CloudSharing.present(share: share, container: store.container,
                                             title: "\(store.displayName)'s squishies")
                    }
                }
            }
            Button("Not now", role: .cancel) { store.pendingShareBack = nil }
        } message: {
            Text("Friends see each other's shelves. Share yours back so \(store.pendingShareBack?.name ?? "they") can see what you have.")
        }
    }

    private var shareBackTitle: String {
        "You can see \(store.pendingShareBack?.name ?? "your friend")'s shelf"
    }
}

// MARK: - iPad

enum SidebarItem: Hashable {
    case library
    case friends
    case friend(String)
    case trades
    case table
}

struct SplitRootView: View {
    @Environment(FriendsStore.self) private var store
    @State private var selection: SidebarItem? = .library
    @State private var askingForName = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .tint(SquishTheme.ink)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                row(.library, title: "Index", systemImage: "square.grid.2x2")
            } header: {
                Text("Squish Index")
                    .typeStyle(.d2)
                    .foregroundStyle(SquishTheme.ink)
                    .textCase(nil)
                    .padding(.bottom, SquishTheme.Space.sm)
            }

            Section {
                row(.friends, title: "All friends", systemImage: "person.2")
                ForEach(store.friends) { friend in
                    HStack(spacing: 11) {
                        FriendMonogram(hexes: friend.monogram, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(friend.name)
                                .typeStyle(.b1)
                                .foregroundStyle(SquishTheme.ink)
                            if let updated = friend.updatedAt {
                                MonoLabel(text: updated.formatted(.relative(presentation: .named)))
                            }
                        }
                        Spacer()
                        MonoLabel(text: String(format: "%02d", friend.items.count), style: .value)
                    }
                    .tag(SidebarItem.friend(friend.id))
                    .accessibilityElement(children: .combine)
                }
                row(.table, title: "Trade in person", systemImage: "person.2.wave.2")
            } header: {
                Eyebrow("Friends")
            }

            Section {
                HStack {
                    Label("Trades", systemImage: "arrow.left.arrow.right")
                        .typeStyle(.b1)
                        .foregroundStyle(SquishTheme.ink)
                    Spacer()
                    if store.badgeCount > 0 { CountBadge(count: store.badgeCount) }
                }
                .tag(SidebarItem.trades)
            } header: {
                Eyebrow("Trades")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(SquishTheme.putty)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: SquishTheme.Space.sm) {
                AddFriendButton(askingForName: $askingForName)
                MonoLabel(text: "Shared through iCloud")
            }
            .padding(SquishTheme.Space.gutter)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func row(_ item: SidebarItem, title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .typeStyle(.b1)
            .foregroundStyle(SquishTheme.ink)
            .tag(item)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .library {
        case .library:
            LibraryView(showsFriendsButton: false)
        case .friends:
            NavigationStack { FriendsView(showsBack: false) }
        case .friend(let id):
            NavigationStack {
                FriendShelfView(friendID: id, showsBack: false)
                    .friendsDestinations()
            }
            .id(id)
        case .trades:
            NavigationStack {
                TradesView(showsBack: false)
                    .friendsDestinations()
            }
        case .table:
            NavigationStack {
                TradeTableView(showsBack: false)
                    .friendsDestinations()
            }
        }
    }
}
