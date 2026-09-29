import CloudKit
import SwiftUI
import SwiftData

/// Friends, requests waiting for you, and the way into a trade table.
struct FriendsView: View {
    var showsBack = true

    @Environment(FriendsStore.self) private var store
    @Query private var squishies: [Squishy]
    @State private var askingForName = false
    @State private var inviteAfterNaming = false
    @State private var isPreparingInvite = false

    private var tint: Tint {
        Tint.sampled(from: store.friends.flatMap { $0.items.map(\.hue) } + squishies.map(\.hue))
    }

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: tint)
            VStack(spacing: 0) {
                FriendsHeader(title: "Friends",
                              caption: caption,
                              showsBack: showsBack)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        #if DEBUG
                        FriendsDebugPanel()
                        #endif
                        notices

                        if !store.waitingForMe.isEmpty {
                            friendsSectionLabel("Waiting for you", detail: "\(store.waitingForMe.count)")
                            ForEach(store.waitingForMe) { trade in
                                NavigationLink(value: FriendsRoute.trade(trade.id)) {
                                    TradeRow(trade: trade)
                                }
                                .buttonStyle(.tap(22))
                            }
                        }

                        friendsSectionLabel("Together")
                        NavigationLink(value: FriendsRoute.table) {
                            FriendsLinkRow(systemImage: "person.2.wave.2",
                                           title: "Trade in person",
                                           caption: "open a trade table with someone right here")
                        }
                        .buttonStyle(.tap(22))

                        friendsSectionLabel("Friends", detail: "\(store.friends.count)")
                        if store.friends.isEmpty && store.pendingInvites.isEmpty {
                            Text("Add a friend and you'll see each other's squeeshies here. Only people you invite, who say yes, can see yours.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.ink2)
                                .padding(.vertical, 4)
                        }
                        ForEach(store.friends) { friend in
                            NavigationLink(value: FriendsRoute.shelf(friendID: friend.id)) {
                                FriendRow(friend: friend)
                            }
                            .buttonStyle(.tap(22))
                        }
                        // By position: two invitees without shared names are both
                        // "Invited friend".
                        ForEach(Array(store.pendingInvites.enumerated()), id: \.offset) { _, name in
                            pendingRow(name)
                        }

                        if !store.trades.isEmpty || !store.tradedAway.isEmpty {
                            friendsSectionLabel("Trades")
                            NavigationLink(value: FriendsRoute.trades) {
                                FriendsLinkRow(systemImage: "arrow.left.arrow.right",
                                               title: "All trades",
                                               caption: "\(store.trades.count) trades · \(store.tradedAway.count) traded away",
                                               badge: store.badgeCount)
                            }
                            .buttonStyle(.tap(22))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
                .refreshable { await store.refresh() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            TintedCTA(title: isPreparingInvite ? "Opening…" : "Add a friend",
                      systemImage: "plus",
                      tint: tint,
                      isEnabled: store.availability == .available && !isPreparingInvite,
                      action: addFriend)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .filesReadyTrades()
        .task { await store.refresh() }
        .sheet(isPresented: $askingForName, onDismiss: {
            if inviteAfterNaming && store.hasDisplayName { invite() }
            inviteAfterNaming = false
        }) {
            DisplayNameSheet()
                .presentationDetents([.height(360)])
        }
    }

    private var caption: String {
        let friends = store.friends.count == 1 ? "1 friend" : "\(store.friends.count) friends"
        return store.hasDisplayName ? "\(store.displayName) · \(friends)" : friends
    }

    @ViewBuilder
    private var notices: some View {
        switch store.availability {
        case .noAccount:
            FriendsNotice(title: "iCloud needed",
                          message: "Friends and trading use iCloud. Sign in to iCloud in Settings — your own collection works either way.")
        case .restricted:
            FriendsNotice(title: "Turned off",
                          message: "iCloud is restricted on this device, so friends aren't available. A parent can change this in Screen Time.")
        case .unavailable:
            FriendsNotice(title: "iCloud unavailable",
                          message: "iCloud can't be reached right now.",
                          actionTitle: "Try again") { Task { await store.start() } }
        case .checking, .available:
            EmptyView()
        }
        if let problem = store.problem {
            FriendsNotice(title: "Heads up", message: problem)
        }
        if store.availability == .available && !store.hasDisplayName {
            FriendsNotice(title: "Your name",
                          message: "Pick the name friends will see on your shelf.",
                          actionTitle: "Choose a name") { askingForName = true }
        }
    }

    private func pendingRow(_ name: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "clock")
                .font(.system(size: 18))
                .foregroundStyle(Color.ink2)
                .frame(width: 56, height: 56)
                .padding(5)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.display(16, .semibold))
                    .foregroundStyle(Color.ink2)
                MetaLabel(text: "invite sent · waiting")
            }
            Spacer()
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }

    private func addFriend() {
        #if DEBUG
        // No share sheet to send: the simulated friend "accepts" at once.
        if store.isSimulating {
            store.debugPairFriend()
            return
        }
        #endif
        guard store.hasDisplayName else {
            inviteAfterNaming = true
            askingForName = true
            return
        }
        invite()
    }

    private func invite() {
        isPreparingInvite = true
        Task {
            defer { isPreparingInvite = false }
            await CloudSharing.invite(store: store)
        }
    }
}

// MARK: - Display name

struct DisplayNameSheet: View {
    @Environment(FriendsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: .fallback)
            VStack(alignment: .leading, spacing: 16) {
                MetaLabel(text: "your name")
                    .padding(.top, 20)
                TextField("", text: $name,
                          prompt: Text("What should friends call you?").foregroundStyle(Color.ink3))
                    .focused($focused)
                    .font(.display(26, .heavy))
                    .foregroundStyle(Color.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(save)
                Text("Friends see this on your shelf and on trade requests. A first name is plenty.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ink2)
                Spacer()
                TintedCTA(title: "Save", isEnabled: !trimmed.isEmpty, action: save)
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 22)
        }
        .onAppear {
            name = store.displayName
            focused = true
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    private func save() {
        guard !trimmed.isEmpty else { return }
        store.setDisplayName(name)
        dismiss()
    }
}
