import SwiftUI

/// A friend's collection, read-only, tinted from their own squeeshies. Kept ones
/// show but can't be asked for.
struct FriendShelfView: View {
    var friendID: String
    var showsBack = true

    @Environment(FriendsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var openOnly = false
    @State private var confirmingRemoval = false

    private var friend: Friend? { store.friend(friendID) }

    private var items: [FriendItem] {
        let all = friend?.items ?? []
        return openOnly ? all.filter { !$0.isKeeping } : all
    }

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: friend?.tint ?? .fallback)
            VStack(spacing: 0) {
                FriendsHeader(title: friend.map { "\($0.name)'s squeeshies" } ?? "Shelf",
                              caption: caption,
                              showsBack: showsBack) {
                    Menu {
                        Button(role: .destructive) { confirmingRemoval = true } label: {
                            Label("Remove friend", systemImage: "person.badge.minus")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .frame(width: 38, height: 38)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .contentShape(.circle)
                    }
                    .accessibilityLabel("More")
                }

                HStack {
                    Button {
                        withAnimation(Motion.tap) { openOnly.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: openOnly ? "checkmark.circle.fill" : "circle")
                            Text("Open to trade")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.tap(17))
                    .accessibilityAddTraits(openOnly ? .isSelected : [])
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                if friend == nil {
                    FriendsNotice(title: "Not shared",
                                  message: "This collection isn't shared with you any more.")
                        .padding(20)
                    Spacer()
                } else if items.isEmpty {
                    Text(openOnly ? "Nothing open to trade right now." : "Nothing here yet.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.ink2)
                        .padding(20)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 150 : 104),
                                                     spacing: 12)],
                                  spacing: 12) {
                            ForEach(items) { item in
                                NavigationLink(value: FriendsRoute.item(friendID: friendID, itemID: item.id)) {
                                    FriendItemTile(item: item)
                                }
                                .buttonStyle(.tap(22))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable { await store.refresh() }
                }
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .filesReadyTrades()
        .confirmationDialog("Remove \(friend?.name ?? "this friend")?",
                            isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove friend", role: .destructive) {
                guard let friend else { return }
                Task {
                    await store.remove(friend)
                    if showsBack { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stop seeing each other's squeeshies. Trades already agreed aren't affected.")
        }
    }

    private var caption: String? {
        guard let friend else { return nil }
        var parts = ["\(friend.items.count) squeeshies", "\(friend.openCount) open to trade"]
        if let updated = friend.updatedAt {
            parts.append(updated.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }
}

private struct FriendItemTile: View {
    var item: FriendItem

    var body: some View {
        VStack(spacing: 8) {
            item.picture
                .frame(width: 72, height: 72)
                .opacity(item.isKeeping ? 0.5 : 1)
            VStack(spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                MetaLabel(text: item.isKeeping ? "keeping" : String(format: "%.1f", item.squeeshiness),
                          color: item.isKeeping ? .ink3 : .ink2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .rebuildsOnSchemeChange()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), squeeshiness \(String(format: "%.1f", item.squeeshiness))\(item.isKeeping ? ", keeping" : "")")
    }
}

/// One of a friend's squeeshies up close: the hero, its traits, whose it is, and
/// the one action — Request trade.
struct FriendItemView: View {
    var friendID: String
    var itemID: String

    @Environment(FriendsStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var composing = false

    private var friend: Friend? { store.friend(friendID) }
    private var item: FriendItem? { friend?.items.first { $0.id == itemID } }
    private var scale: CGFloat { sizeClass == .regular ? 1.55 : 1 }

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: item.map { Tint.single($0.hue) } ?? .fallback)
            VStack(spacing: 0) {
                FriendsHeader(title: friend.map { "\($0.name)'s" } ?? "Shelf",
                              caption: item.map { $0.isKeeping ? "keeping" : "open to trade" })
                if let item, let friend {
                    Spacer(minLength: 8)
                    item.picture
                        .frame(width: 190 * scale, height: 190 * scale)
                        .accessibilityLabel(item.name)
                    Spacer(minLength: 8)
                    details(item, friend: friend)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                } else {
                    FriendsNotice(title: "Gone", message: "This squeeshy isn't in their collection any more.")
                        .padding(20)
                    Spacer()
                }
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if let item, let friend, !item.isKeeping {
                TintedCTA(title: "Request trade", systemImage: "arrow.left.arrow.right",
                          tint: Tint.single(item.hue)) { composing = true }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .sheet(isPresented: $composing) {
                        TradeComposerView(friend: friend, wanted: item)
                    }
            }
        }
    }

    private func details(_ item: FriendItem, friend: Friend) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(item.name)
                    .font(.display(30, .heavy))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                MetaLabel(text: item.traitLine)
            }
            HStack(spacing: 10) {
                chip("squeesh", String(format: "%.1f", item.squeeshiness))
                chip("colour", Hue.name(item.hue))
                chip("size", item.size.label)
            }
            MetaLabel(text: "in \(friend.name)'s collection since \(item.addedAt.formatted(.dateTime.month(.abbreviated).year()))",
                      color: .ink3)
        }
        .frame(maxWidth: 520)
    }

    private func chip(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            MetaLabel(text: label, color: .ink3)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}
