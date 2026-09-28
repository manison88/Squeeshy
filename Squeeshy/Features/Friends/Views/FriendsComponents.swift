import SwiftUI
import SwiftData

// MARK: - Navigation

/// Every screen in the friends area. One enum, so the phone (pushed onto the
/// Collections stack) and the iPad (the split view's detail column) share every
/// destination.
enum FriendsRoute: Hashable {
    case friends
    case shelf(friendID: String)
    case item(friendID: String, itemID: String)
    case trades
    case trade(UUID)
    case table
}

extension View {
    /// Registers every friends destination on the enclosing stack.
    func friendsDestinations() -> some View {
        navigationDestination(for: FriendsRoute.self) { route in
            FriendsDestination(route: route)
        }
    }
}

/// `isRoot` is true only at the bottom of the iPad's detail column, where there
/// is nothing behind the screen and a back chevron would do nothing.
struct FriendsDestination: View {
    var route: FriendsRoute
    var isRoot = false

    var body: some View {
        switch route {
        case .friends:
            FriendsView(showsBack: !isRoot)
        case .shelf(let friendID):
            FriendShelfView(friendID: friendID, showsBack: !isRoot)
        case .item(let friendID, let itemID):
            FriendItemView(friendID: friendID, itemID: itemID)
        case .trades:
            TradesView(showsBack: !isRoot)
        case .trade(let id):
            TradeDetailView(tradeID: id)
        case .table:
            TradeTableView(showsBack: !isRoot)
        }
    }
}

// MARK: - Filing finished trades

/// Marks a screen as one where finished trades may be filed. See
/// `FriendsStore.beginFiling()`.
private struct FilesReadyTrades: ViewModifier {
    @Environment(FriendsStore.self) private var store

    func body(content: Content) -> some View {
        content
            .onAppear { store.beginFiling() }
            .onDisappear { store.endFiling() }
    }
}

extension View {
    func filesReadyTrades() -> some View { modifier(FilesReadyTrades()) }
}

// MARK: - Header

/// The top of every friends screen, matching FieldView and ItemDetailView: a glass
/// back chevron, a display title, a mono caption, and trailing glass buttons.
struct FriendsHeader<Trailing: View>: View {
    var title: String
    var caption: String?
    var showsBack: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.dismiss) private var dismiss

    var body: some View {
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
                .accessibilityLabel("Back")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.display(24, .heavy))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let caption {
                    MetaLabel(text: caption)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

extension FriendsHeader where Trailing == EmptyView {
    init(title: String, caption: String? = nil, showsBack: Bool = true) {
        self.init(title: title, caption: caption, showsBack: showsBack) { EmptyView() }
    }
}

/// A 38pt glass circle, the app's standard header control.
struct GlassCircleButton: View {
    var systemImage: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 38, height: 38)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.tap)
        .accessibilityLabel(label)
    }
}

// MARK: - Pictures

/// A squeeshy that isn't a `Squishy` in this collection — on a friend's shelf,
/// on a trade table, or already traded away. The cut-out when there is one, the
/// drawn character when there isn't, exactly like `SquishyImage`.
struct LooseSquishyImage: View {
    var image: UIImage?
    var species: Species
    var color: Color
    var showsFace = true

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            SquishyArt(species: species, color: color, showsFace: showsFace)
        }
    }
}

extension FriendItem {
    var picture: LooseSquishyImage { LooseSquishyImage(image: image, species: species, color: color) }
}

/// A trade line's picture: this user's own squeeshy if it is still here, the
/// friend's shelf copy if not, and the drawn character as a last resort.
struct TradeLineImage: View {
    var line: TradeLine
    var friendID: String

    @Environment(FriendsStore.self) private var store
    @Query private var squishies: [Squishy]

    var body: some View {
        if let own = squishies.first(where: { $0.lineageID.uuidString == line.id }) {
            SquishyImage(squishy: own)
        } else if let item = store.friend(friendID)?.items.first(where: { $0.id == line.id }) {
            item.picture
        } else {
            SquishyArt(species: line.species, color: line.color)
        }
    }
}

/// The four-up preview on a friend's row, like `MiniStack` on a shelf row.
struct FriendStack: View {
    var items: [FriendItem]

    var body: some View {
        LazyVGrid(columns: [GridItem(.fixed(22), spacing: 3), GridItem(.fixed(22), spacing: 3)], spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                if i < items.count {
                    LooseSquishyImage(image: items[i].image, species: items[i].species,
                                      color: items[i].color, showsFace: false)
                        .frame(width: 22, height: 22)
                } else {
                    Circle().fill(.white.opacity(0.06)).frame(width: 22, height: 22)
                }
            }
        }
        .frame(width: 56, height: 56)
        .padding(5)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 17))
        .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// The primary action on a friends screen. Filled with the screen's own tint, the
/// way Create and the capture button are.
struct TintedCTA: View {
    var title: String
    var systemImage: String? = nil
    var tint: Tint = .fallback
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 14, weight: .bold))
                }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.05, green: 0.04, blue: 0.08))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                isEnabled
                    ? AnyShapeStyle(LinearGradient(colors: [tint.primary, tint.secondary],
                                                   startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color.ink3),
                in: .capsule)
        }
        .buttonStyle(.tap(26))
        .disabled(!isEnabled)
    }
}

/// The secondary action: a glass capsule.
struct GlassCTA: View {
    var title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 14, weight: .bold))
                }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.tap(26))
    }
}

/// A count of things waiting on this user. The number carries the state, not
/// the colour.
struct CountBadge: View {
    var count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.onInk)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color.ink, in: .capsule)
            .accessibilityLabel("\(count) waiting")
    }
}

// MARK: - Rows

struct FriendRow: View {
    var friend: Friend

    var body: some View {
        HStack(spacing: 13) {
            FriendStack(items: friend.items)
            VStack(alignment: .leading, spacing: 3) {
                Text(friend.name)
                    .font(.display(16, .semibold))
                    .foregroundStyle(Color.ink)
                MetaLabel(text: caption)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink3)
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .rebuildsOnSchemeChange()
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        var parts = ["\(friend.items.count) squeeshies"]
        if let updated = friend.updatedAt {
            parts.append(updated.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }
}

/// A row that leads somewhere in the friends area: an icon, a title, a caption.
struct FriendsLinkRow: View {
    var systemImage: String
    var title: String
    var caption: String
    var badge: Int = 0

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.ink)
                .frame(width: 56, height: 56)
                .padding(5)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.display(16, .semibold))
                    .foregroundStyle(Color.ink)
                MetaLabel(text: caption)
            }
            Spacer(minLength: 8)
            if badge > 0 { CountBadge(count: badge) }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink3)
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .rebuildsOnSchemeChange()
        .accessibilityElement(children: .combine)
    }
}

struct TradeRow: View {
    var trade: Trade

    var body: some View {
        HStack(spacing: 10) {
            TradeLineImage(line: trade.getting.first ?? placeholder, friendID: trade.friendID)
                .frame(width: 40, height: 40)
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.ink3)
            TradeLineImage(line: trade.giving.first ?? placeholder, friendID: trade.friendID)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(trade.friendName)
                    .font(.display(16, .semibold))
                    .foregroundStyle(Color.ink)
                MetaLabel(text: summary)
                    .lineLimit(2)
            }
            .padding(.leading, 4)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink3)
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .rebuildsOnSchemeChange()
        .accessibilityElement(children: .combine)
    }

    private var placeholder: TradeLine {
        TradeLine(id: "", name: "", hue: 0, speciesRaw: Species.round.rawValue)
    }

    private var summary: String {
        let getting = trade.getting.map(\.name).joined(separator: " + ")
        let giving = trade.giving.map(\.name).joined(separator: " + ")
        switch trade.state {
        case .needsMyReply: return "wants your \(giving)"
        case .waitingForReply: return "you asked for \(getting)"
        case .inProgress:
            return trade.iHandedOver ? "waiting for \(trade.friendName) to hand over" : "hand over \(giving)"
        case .completed: return "traded · \(getting) is yours"
        case .declined: return "said no this time"
        case .cancelled: return "cancelled"
        case .expired: return "expired"
        }
    }
}

/// A selectable squeeshy in a grid, like the shelf contents picker.
struct PickTile<Picture: View>: View {
    var name: String
    var tint: Color
    var isOn: Bool
    var isEnabled = true
    @ViewBuilder var picture: () -> Picture
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                picture()
                    .frame(width: 54, height: 54)
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: 20).fill(tint.opacity(0.30))
                }
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            .rebuildsOnSchemeChange()
            .overlay(alignment: .topTrailing) {
                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.ink)
                        .padding(7)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(isOn ? 1 : 0.97)
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.tap(20))
        .disabled(!isEnabled)
        .animation(Motion.tap, value: isOn)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Notices

/// Plain-language status in the friends area: signed out, offline, an error.
/// Never blocks anything, never a spinner.
struct FriendsNotice: View {
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MetaLabel(text: title, color: .ink)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(minHeight: 36)
                    .buttonStyle(.tap)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

func friendsSectionLabel(_ text: String, detail: String? = nil) -> some View {
    HStack {
        MetaLabel(text: text)
        Spacer()
        if let detail { MetaLabel(text: detail, color: .ink3) }
    }
    .padding(.top, 14)
    .padding(.bottom, 2)
    .accessibilityAddTraits(.isHeader)
}
