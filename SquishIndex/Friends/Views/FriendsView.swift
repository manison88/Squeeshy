import CloudKit
import SwiftUI

/// F1 — friends, requests waiting for you, and the way into a trade table.
/// Pushed from the Grid header on iPhone; on iPad the sidebar does this job.
struct FriendsView: View {
    var showsBack = true

    @Environment(FriendsStore.self) private var store
    @State private var askingForName = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FriendsHeader(title: "Friends", showsBack: showsBack)

                VStack(alignment: .leading, spacing: 0) {
                    #if DEBUG
                    FriendsDebugPanel()
                    #endif
                    FriendsStatusNotices(askingForName: $askingForName)

                    if !store.waitingForMe.isEmpty {
                        SectionHeading(title: "Waiting for you", detail: "\(store.waitingForMe.count)")
                        VStack(spacing: SquishTheme.Space.sm) {
                            ForEach(store.waitingForMe) { trade in
                                NavigationLink(value: FriendsRoute.trade(trade.id)) {
                                    TradeRow(trade: trade)
                                }
                                .buttonStyle(PressStyle(scale: 0.98))
                            }
                        }
                    }

                    NavigationLink(value: FriendsRoute.table) {
                        TableEntryCard()
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                    .padding(.top, SquishTheme.Space.margin)

                    SectionHeading(title: "Friends", detail: "\(store.friends.count)")
                    if store.friends.isEmpty && store.pendingInvites.isEmpty {
                        Text("Add a friend and you'll see each other's shelves here. Only people you invite, who say yes, can see yours.")
                            .typeStyle(.b1)
                            .foregroundStyle(SquishTheme.soft)
                            .padding(.vertical, SquishTheme.Space.sm)
                    }
                    ForEach(store.friends) { friend in
                        HairlineRule()
                        NavigationLink(value: FriendsRoute.shelf(friendID: friend.id)) {
                            FriendRow(friend: friend)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(store.pendingInvites, id: \.self) { name in
                        HairlineRule()
                        PendingInviteRow(name: name)
                    }

                    if !store.trades.isEmpty {
                        HairlineRule().padding(.top, SquishTheme.Space.margin)
                        NavigationLink(value: FriendsRoute.trades) {
                            HStack {
                                Eyebrow("All trades", tint: SquishTheme.ink)
                                Spacer()
                                if store.badgeCount > 0 {
                                    CountBadge(count: store.badgeCount)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(SquishTheme.soft)
                            }
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, SquishTheme.Space.margin)
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .background(SquishTheme.putty.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            AddFriendButton(askingForName: $askingForName)
                .padding(.horizontal, SquishTheme.Space.margin)
                .padding(.bottom, SquishTheme.Space.sm)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.refresh() }
    }
}

// MARK: - Pieces

/// Signed out, offline, or no display name yet.
struct FriendsStatusNotices: View {
    @Binding var askingForName: Bool
    @Environment(FriendsStore.self) private var store

    var body: some View {
        VStack(spacing: SquishTheme.Space.sm) {
            switch store.availability {
            case .noAccount:
                FriendsNotice(title: "iCloud needed",
                              message: "Friends and trading use iCloud. Sign in to iCloud in Settings — your own collection works either way.")
            case .restricted:
                FriendsNotice(title: "Turned off",
                              message: "iCloud is restricted on this device, so friends aren't available. A parent can change this in Screen Time.")
            case .unavailable:
                FriendsNotice(title: "iCloud unavailable",
                              message: "iCloud can't be reached right now. Try again in a minute.",
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
        .padding(.top, SquishTheme.Space.gutter)
    }
}

struct AddFriendButton: View {
    @Binding var askingForName: Bool
    @Environment(FriendsStore.self) private var store
    @State private var isPreparing = false
    @State private var inviteAfterNaming = false

    var body: some View {
        Button {
            guard store.hasDisplayName else {
                inviteAfterNaming = true
                askingForName = true
                return
            }
            invite()
        } label: {
            HStack(spacing: SquishTheme.Space.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                Text(isPreparing ? "Opening…" : "Add a friend")
                    .typeStyle(.b2)
            }
            .foregroundStyle(SquishTheme.chalk)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(SquishTheme.ink, in: Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .shadow(color: SquishTheme.Shadow.ambient.color, radius: SquishTheme.Shadow.ambient.radius,
                y: SquishTheme.Shadow.ambient.y)
        .disabled(store.availability != .available || isPreparing)
        .opacity(store.availability == .available ? 1 : 0.4)
        .sheet(isPresented: $askingForName, onDismiss: {
            if inviteAfterNaming && store.hasDisplayName { invite() }
            inviteAfterNaming = false
        }) {
            DisplayNameSheet()
        }
    }

    private func invite() {
        #if DEBUG
        // No share sheet to send: the simulated friend "accepts" at once.
        if store.isSimulating {
            store.debugPairFriend()
            return
        }
        #endif
        isPreparing = true
        Task {
            defer { isPreparing = false }
            do {
                let share = try await store.shareForInvite()
                CloudSharing.present(share: share, container: store.container, title: "\(store.displayName)'s squishies")
            } catch {
                // Surfaced by the store's notice.
            }
        }
    }
}

private struct PendingInviteRow: View {
    let name: String

    var body: some View {
        HStack(spacing: SquishTheme.Space.gutter) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SquishTheme.chalk)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(SquishTheme.line, lineWidth: SquishTheme.hairline))
                .overlay(Image(systemName: "clock").foregroundStyle(SquishTheme.soft))
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .typeStyle(.d4)
                    .foregroundStyle(SquishTheme.soft)
                MonoLabel(text: "Invite sent · waiting")
            }
            Spacer()
        }
        .frame(minHeight: 68)
        .accessibilityElement(children: .combine)
    }
}

private struct TableEntryCard: View {
    var body: some View {
        HStack(spacing: SquishTheme.Space.gutter) {
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(SquishTheme.ink)
                .frame(width: 44, height: 44)
                .background(SquishTheme.putty, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Trade in person")
                    .typeStyle(.d4)
                    .foregroundStyle(SquishTheme.ink)
                Text("Open a trade table with a friend who's right here.")
                    .typeStyle(.b3)
                    .foregroundStyle(SquishTheme.soft)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SquishTheme.soft)
        }
        .padding(SquishTheme.Space.gutter)
        .background(SquishTheme.chalk, in: RoundedRectangle(cornerRadius: SquishTheme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SquishTheme.Radius.card, style: .continuous)
            .strokeBorder(SquishTheme.line, lineWidth: SquishTheme.hairline))
        .accessibilityElement(children: .combine)
    }
}

struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .typeStyle(.m2)
            .foregroundStyle(SquishTheme.chalk)
            .padding(.horizontal, SquishTheme.Space.xs)
            .frame(minWidth: 18, minHeight: 18)
            .background(SquishTheme.ink, in: Capsule())
            .accessibilityLabel("\(count) waiting")
    }
}

// MARK: - Display name

struct DisplayNameSheet: View {
    @Environment(FriendsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SquishTheme.Space.margin) {
            Eyebrow("Your name")
            Text("What should friends call you?")
                .typeStyle(.d3)
                .foregroundStyle(SquishTheme.ink)
            Text("Friends see this on your shelf and on trade requests. A first name is plenty.")
                .typeStyle(.b1)
                .foregroundStyle(SquishTheme.soft)
            TextField("", text: $name, prompt: Text("First name").foregroundColor(SquishTheme.soft))
                .typeStyle(.d3)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(save)
                .frame(minHeight: 44)
            Rectangle().fill(SquishTheme.ink).frame(height: 1.5)
            Spacer()
            PrimaryPill(title: "Save", action: save)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        }
        .padding(SquishTheme.Space.margin)
        .background(SquishTheme.putty.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationCornerRadius(SquishTheme.Radius.sheet)
        .onAppear {
            name = store.displayName
            focused = true
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.setDisplayName(name)
        dismiss()
    }
}
