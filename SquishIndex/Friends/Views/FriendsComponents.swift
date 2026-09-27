import SwiftUI

/// Navigation inside the friends area. One enum so iPhone (pushed from the
/// Grid) and iPad (the split view's detail column) share every destination.
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
            switch route {
            case .friends:
                FriendsView()
            case .shelf(let friendID):
                FriendShelfView(friendID: friendID)
            case .item(let friendID, let itemID):
                FriendItemView(friendID: friendID, itemID: itemID)
            case .trades:
                TradesView()
            case .trade(let id):
                TradeDetailView(tradeID: id)
            case .table:
                TradeTableView()
            }
        }
    }
}

// MARK: - Header

/// The top of every friends screen: an optional back control, a mono context
/// label, and a display title. Custom rather than a navigation bar, for the
/// same Liquid Glass reason as the library (UX-SPEC §8).
struct FriendsHeader<Trailing: View>: View {
    let title: String
    var eyebrow: String?
    var subtitle: String?
    var showsBack = true
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: SquishTheme.Space.xs) {
            HStack {
                if showsBack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SquishTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(SquishTheme.chalk, in: Circle())
                            .overlay(Circle().strokeBorder(SquishTheme.line, lineWidth: SquishTheme.hairline))
                    }
                    .accessibilityLabel("Back")
                }
                if let eyebrow {
                    Eyebrow(eyebrow)
                }
                Spacer(minLength: 0)
                trailing()
            }
            .frame(minHeight: 44)
            Text(title)
                .typeStyle(.d2)
                .foregroundStyle(SquishTheme.ink)
                .padding(.top, SquishTheme.Space.sm)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                MonoLabel(text: subtitle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SquishTheme.Space.margin)
        .padding(.top, SquishTheme.Space.gutter)
    }
}

extension FriendsHeader where Trailing == EmptyView {
    init(title: String, eyebrow: String? = nil, subtitle: String? = nil, showsBack: Bool = true) {
        self.init(title: title, eyebrow: eyebrow, subtitle: subtitle, showsBack: showsBack) { EmptyView() }
    }
}

// MARK: - Monogram

/// A friend is shown as four colours from their own shelf — no avatars and no
/// faces. An empty shelf shows a plain plate.
struct FriendMonogram: View {
    let hexes: [String]
    var size: CGFloat = 44

    var body: some View {
        let colors = hexes.prefix(4).compactMap { Color(hexString: $0) }
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(SquishTheme.chalk)
            .overlay {
                if !colors.isEmpty {
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            cell(colors, 0)
                            cell(colors, 1)
                        }
                        GridRow {
                            cell(colors, 2)
                            cell(colors, 3)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(SquishTheme.line, lineWidth: SquishTheme.hairline))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private func cell(_ colors: [Color], _ index: Int) -> some View {
        (index < colors.count ? colors[index] : colors[index % colors.count])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Cards

/// A friend's squishy in their shelf grid. Mirrors `SpecimenCard`, plus the
/// *Keeping* tag — a status in words, never colour alone (SPEC.md §3).
struct FriendItemCard: View {
    let item: FriendItem
    let width: CGFloat

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PhotoPlate(image: item.image) {
                if item.isKeeping {
                    VStack {
                        HStack {
                            StatusTag(text: "Keeping")
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(SquishTheme.Space.sm)
                }
            }
            .opacity(item.isKeeping ? 0.6 : 1)
            .frame(width: width, height: width)

            Text(item.name)
                .typeStyle(.d4)
                .foregroundStyle(SquishTheme.ink)
                .lineLimit(2)
                .frame(width: width, alignment: .topLeading)
                .frame(height: typeSize.lineHeight(for: .d4) * 2, alignment: .topLeading)
                .padding(.top, SquishTheme.Space.sm)

            HStack(spacing: 0) {
                PaletteStrip(hexes: item.paletteHex)
                Spacer(minLength: SquishTheme.Space.sm)
                MonoLabel(text: item.squish.padded, style: .value, tint: SquishTheme.ink)
            }
            .frame(height: 15)
            .padding(.top, SquishTheme.Space.xs)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.spokenSummary)
        .accessibilityAddTraits(.isButton)
    }
}

struct StatusTag: View {
    let text: String

    var body: some View {
        Text(text)
            .typeStyle(.m1)
            .foregroundStyle(SquishTheme.quietInk)
            .padding(.horizontal, SquishTheme.Space.sm)
            .frame(height: 22)
            .background(SquishTheme.chalk.opacity(0.92), in: Capsule())
            .overlay(Capsule().strokeBorder(SquishTheme.line, lineWidth: SquishTheme.hairline))
    }
}

/// A selectable plate for choosing what to offer. Selection is an ink ring, a
/// filled box and a VoiceOver trait — not colour alone.
struct PickablePlate: View {
    let image: UIImage?
    let name: String
    let squish: Int
    let isSelected: Bool
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SquishTheme.Space.xs) {
                PhotoPlate(image: image, cornerRadius: SquishTheme.Radius.card) {
                    VStack {
                        HStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? SquishTheme.ink : SquishTheme.chalk.opacity(0.92))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(isSelected ? SquishTheme.ink : SquishTheme.soft, lineWidth: 1.5))
                                .overlay {
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(SquishTheme.chalk)
                                    }
                                }
                                .frame(width: 22, height: 22)
                        }
                        Spacer()
                    }
                    .padding(SquishTheme.Space.sm)
                }
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: SquishTheme.Radius.card, style: .continuous)
                        .strokeBorder(SquishTheme.ink, lineWidth: isSelected ? 2 : 0)
                )
                Text(name)
                    .typeStyle(.b3)
                    .foregroundStyle(SquishTheme.ink)
                    .lineLimit(2)
                MonoLabel(text: SquishLevel(squish).padded, style: .value, tint: SquishTheme.ink)
            }
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), squish \(squish)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Rows and notices

struct FriendRow: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: SquishTheme.Space.gutter) {
            FriendMonogram(hexes: friend.monogram)
            VStack(alignment: .leading, spacing: 3) {
                Text(friend.name)
                    .typeStyle(.d4)
                    .foregroundStyle(SquishTheme.ink)
                MonoLabel(text: detail)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SquishTheme.soft)
        }
        .frame(minHeight: 68)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let count = String(format: "%02d specimens", friend.items.count)
        guard let updated = friend.updatedAt else { return count }
        return count + " · " + updated.formatted(.relative(presentation: .named))
    }
}

/// A plain-language note in the friends area — offline, signed out, or an
/// error. Never blocks anything; never a spinner.
struct FriendsNotice: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SquishTheme.Space.sm) {
            Eyebrow(title, tint: SquishTheme.ink)
            Text(message)
                .typeStyle(.b1)
                .foregroundStyle(SquishTheme.soft)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .typeStyle(.b2)
                    .foregroundStyle(SquishTheme.ink)
                    .frame(minHeight: 44)
            }
        }
        .padding(SquishTheme.Space.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SquishTheme.chalk, in: RoundedRectangle(cornerRadius: SquishTheme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SquishTheme.Radius.card, style: .continuous)
            .strokeBorder(SquishTheme.line, lineWidth: SquishTheme.hairline))
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow(title, tint: SquishTheme.ink)
            Spacer()
            if let detail { MonoLabel(text: detail) }
        }
        .padding(.top, SquishTheme.Space.margin)
        .padding(.bottom, SquishTheme.Space.sm)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A secondary pill — outline, ink text.
struct SecondaryPill: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SquishTheme.Space.sm) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).typeStyle(.b2)
            }
            .foregroundStyle(SquishTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(SquishTheme.chalk, in: Capsule())
            .overlay(Capsule().strokeBorder(SquishTheme.ink, lineWidth: 1.5))
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }
}

// MARK: - Grid sizing

enum AdaptiveGrid {
    /// Two columns on a phone, more on an iPad — cards never grow past ~220 pt.
    static func columns(for width: CGFloat) -> Int {
        let usable = width - SquishTheme.Space.margin * 2
        return max(2, Int((usable + SquishTheme.Space.gutter) / (200 + SquishTheme.Space.gutter)))
    }

    static func cardWidth(for width: CGFloat, columns: Int) -> CGFloat {
        let usable = width - SquishTheme.Space.margin * 2 - SquishTheme.Space.gutter * CGFloat(columns - 1)
        return max(100, usable / CGFloat(columns))
    }
}

extension PhotoPlate {
    /// An image plate with an overlay — the Keeping tag, a selection box.
    init(image: UIImage?,
         cornerRadius: CGFloat = SquishTheme.Radius.plate,
         showsBorder: Bool = true,
         @ViewBuilder overlay: @escaping () -> Overlay) {
        self.init(state: image.map { PlateState.filled($0) } ?? .pending,
                  cornerRadius: cornerRadius,
                  showsBorder: showsBorder,
                  overlay: overlay)
    }
}
