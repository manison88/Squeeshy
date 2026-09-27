import SwiftUI

/// F2 — a friend's shelf, read-only. The ordinary grid, with kept squishies
/// faded and labelled. No Stats view: a friend's shelf is for browsing, not
/// for comparing collections.
struct FriendShelfView: View {
    let friendID: String
    var showsBack = true

    @Environment(FriendsStore.self) private var store
    @State private var openOnly = false
    @State private var confirmingRemoval = false
    @Environment(\.dismiss) private var dismiss

    private var friend: Friend? { store.friend(friendID) }

    private var items: [FriendItem] {
        let all = friend?.items ?? []
        return openOnly ? all.filter { !$0.isKeeping } : all
    }

    var body: some View {
        GeometryReader { proxy in
            let columns = AdaptiveGrid.columns(for: proxy.size.width)
            let cardWidth = AdaptiveGrid.cardWidth(for: proxy.size.width, columns: columns)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FriendsHeader(title: friend.map { "\($0.name)'s shelf" } ?? "Shelf",
                                  subtitle: subtitle,
                                  showsBack: showsBack) {
                        Button("Remove") { confirmingRemoval = true }
                            .typeStyle(.m1)
                            .foregroundStyle(SquishTheme.quietInk)
                            .frame(minHeight: 44)
                            .disabled(friend == nil)
                    }

                    HStack(spacing: SquishTheme.Space.sm) {
                        Chip(title: "Open to trade",
                             count: openOnly ? friend?.openCount : nil,
                             isActive: openOnly,
                             accessibilityLabelText: "Only show open to trade",
                             accessibilityValueText: openOnly ? "On" : "Off") {
                            withAnimation(SquishTheme.Motion.select) { openOnly.toggle() }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, SquishTheme.Space.margin)
                    .padding(.top, SquishTheme.Space.gutter)

                    if friend == nil {
                        FriendsNotice(title: "Not shared",
                                      message: "This shelf isn't shared with you any more.")
                            .padding(SquishTheme.Space.margin)
                    } else if items.isEmpty {
                        Text(openOnly ? "Nothing open to trade right now." : "Nothing on this shelf yet.")
                            .typeStyle(.b1)
                            .foregroundStyle(SquishTheme.soft)
                            .padding(SquishTheme.Space.margin)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: SquishTheme.Space.gutter),
                                                 count: columns),
                                  alignment: .leading,
                                  spacing: SquishTheme.Space.margin) {
                            ForEach(items) { item in
                                NavigationLink(value: FriendsRoute.item(friendID: friendID, itemID: item.id)) {
                                    FriendItemCard(item: item, width: cardWidth)
                                }
                                .buttonStyle(PressStyle(scale: 0.98))
                            }
                        }
                        .padding(.horizontal, SquishTheme.Space.margin)
                        .padding(.top, SquishTheme.Space.gutter)
                    }
                    Color.clear.frame(height: 56)
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.refresh() }
        }
        .background(SquishTheme.putty.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Remove \(friend?.name ?? "this friend")?",
                            isPresented: $confirmingRemoval,
                            titleVisibility: .visible) {
            Button("Remove friend", role: .destructive) {
                guard let friend else { return }
                Task {
                    await store.remove(friend)
                    dismiss()
                }
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("You'll stop seeing each other's shelves. Trades already agreed aren't affected.")
        }
    }

    private var subtitle: String? {
        guard let friend else { return nil }
        var parts = [String(format: "%02d specimens", friend.items.count),
                     String(format: "%02d open to trade", friend.openCount)]
        if let updated = friend.updatedAt {
            parts.append("updated " + updated.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }
}

/// F2b — one of a friend's squishies, as a specimen sheet: real measurements,
/// whose shelf it's on, and the only new action, *Request trade*.
struct FriendItemView: View {
    let friendID: String
    let itemID: String

    @Environment(FriendsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var composing = false

    private var friend: Friend? { store.friend(friendID) }
    private var item: FriendItem? { friend?.items.first { $0.id == itemID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    PhotoPlate(image: item?.image, cornerRadius: 0, showsBorder: false)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                        .background(SquishTheme.chalk)
                        .accessibilityLabel("Photograph of \(item?.name ?? "a squishy")")
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SquishTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(SquishTheme.chalk.opacity(0.9), in: Circle())
                    }
                    .padding(SquishTheme.Space.margin)
                    .accessibilityLabel("Back to \(friend?.name ?? "the") shelf")
                }

                if let item, let friend {
                    specs(item, friend: friend)
                        .padding(SquishTheme.Space.margin)
                        .background(SquishTheme.putty)
                } else {
                    FriendsNotice(title: "Gone", message: "This squishy isn't on the shelf any more.")
                        .padding(SquishTheme.Space.margin)
                }
                Color.clear.frame(height: 96)
            }
        }
        .scrollIndicators(.hidden)
        .background(SquishTheme.putty.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if let item, !item.isKeeping, friend != nil {
                PrimaryPill(title: "Request trade") { composing = true }
                    .shadow(color: SquishTheme.Shadow.ambient.color, radius: SquishTheme.Shadow.ambient.radius,
                            y: SquishTheme.Shadow.ambient.y)
                    .padding(.horizontal, SquishTheme.Space.margin)
                    .padding(.bottom, SquishTheme.Space.sm)
            }
        }
        .sheet(isPresented: $composing) {
            if let friend, let item {
                TradeComposerView(friend: friend, wanted: item)
            }
        }
    }

    private func specs(_ item: FriendItem, friend: Friend) -> some View {
        VStack(alignment: .leading, spacing: SquishTheme.Space.margin) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: SquishTheme.Space.xs) {
                    Text(item.name)
                        .typeStyle(.d3)
                        .foregroundStyle(SquishTheme.ink)
                    MonoLabel(text: "On \(friend.name)'s shelf · " + (item.isKeeping ? "keeping" : "open to trade"))
                }
                Spacer()
                HeroNumeral(value: item.squishLevel)
            }
            Durometer(level: .constant(item.squishLevel),
                      isInteractive: false,
                      tint: item.dominantColor.darkenedForContrast(against: .white, ratio: 3),
                      trackWidth: 260)
            Text(item.squish.sentence)
                .typeStyle(.b1)
                .foregroundStyle(SquishTheme.soft)

            VStack(spacing: 0) {
                row("Size", sizeLine(item))
                HairlineRule()
                row("Measured", measuredLine(item, friend: friend))
                HairlineRule()
                row("Form", item.silhouette.display)
                HairlineRule()
                row("Since", item.addedAt.formatted(.dateTime.month(.abbreviated).year()))
            }

            if !item.paletteHex.isEmpty {
                VStack(alignment: .leading, spacing: SquishTheme.Space.sm) {
                    Eyebrow("Palette")
                    PaletteStrip(hexes: item.paletteHex,
                                 proportions: item.paletteProportions.count == item.paletteHex.count
                                    ? item.paletteProportions : nil)
                }
            }
        }
    }

    private func sizeLine(_ item: FriendItem) -> String {
        guard let width = item.widthMM, let height = item.heightMM else { return "Not captured" }
        return String(format: "%.0f × %.0f mm", width, height)
    }

    private func measuredLine(_ item: FriendItem, friend: Friend) -> String {
        item.method.capturesSize ? "\(item.method.badgeText) · on \(friend.name)'s phone" : item.method.explanation
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: SquishTheme.Space.gutter) {
            MonoLabel(text: label)
                .frame(width: 88, alignment: .leading)
                .padding(.top, 3)
            Text(value)
                .typeStyle(.b1)
                .foregroundStyle(SquishTheme.ink)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }
}
