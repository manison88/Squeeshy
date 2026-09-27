import SwiftData
import SwiftUI

/// Every trade, grouped by who needs to act.
struct TradesView: View {
    var showsBack = true

    @Environment(FriendsStore.self) private var store
    @Query private var allSpecimens: [Squishy]

    private var traded: [Squishy] {
        allSpecimens.filter(\.isTraded)
            .sorted { ($0.tradedAt ?? .distantPast) > ($1.tradedAt ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FriendsHeader(title: "Trades", showsBack: showsBack)
                VStack(alignment: .leading, spacing: 0) {
                    group("Waiting for you", store.waitingForMe)
                    group("In progress", store.inProgress)
                    group("Sent", store.trades.filter { $0.state == .waitingForReply })
                    group("Finished", store.trades.filter {
                        [.completed, .declined, .cancelled, .expired].contains($0.state)
                    })

                    if !traded.isEmpty {
                        SectionHeading(title: "Traded away", detail: "\(traded.count)")
                        ForEach(traded) { specimen in
                            HairlineRule()
                            HStack(spacing: SquishTheme.Space.gutter) {
                                PhotoPlate(image: specimen.image, cornerRadius: 12)
                                    .frame(width: 52, height: 52)
                                    .opacity(0.7)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(specimen.name)
                                        .typeStyle(.d4)
                                        .foregroundStyle(SquishTheme.ink)
                                    MonoLabel(text: tradedLine(specimen))
                                }
                                Spacer()
                            }
                            .frame(minHeight: 68)
                            .accessibilityElement(children: .combine)
                        }
                    }

                    if store.trades.isEmpty && traded.isEmpty {
                        Text("No trades yet. Open a friend's shelf and tap a squishy to ask for it.")
                            .typeStyle(.b1)
                            .foregroundStyle(SquishTheme.soft)
                            .padding(.top, SquishTheme.Space.margin)
                    }
                    Color.clear.frame(height: 56)
                }
                .padding(.horizontal, SquishTheme.Space.margin)
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .background(SquishTheme.putty.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func group(_ title: String, _ trades: [Trade]) -> some View {
        if !trades.isEmpty {
            SectionHeading(title: title, detail: "\(trades.count)")
            VStack(spacing: SquishTheme.Space.sm) {
                ForEach(trades) { trade in
                    NavigationLink(value: FriendsRoute.trade(trade.id)) {
                        TradeRow(trade: trade)
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
            }
        }
    }

    private func tradedLine(_ specimen: Squishy) -> String {
        var line = "Traded to \(specimen.tradedTo ?? "a friend")"
        if let date = specimen.tradedAt {
            line += " · " + date.formatted(date: .abbreviated, time: .omitted)
        }
        return line
    }
}

// MARK: - Row

struct TradeRow: View {
    let trade: Trade

    @Environment(FriendsStore.self) private var store
    @Query private var allSpecimens: [Squishy]

    var body: some View {
        HStack(spacing: SquishTheme.Space.gutter) {
            TradeImages.plate(for: trade.getting.first, trade: trade, store: store, mine: allSpecimens)
                .frame(width: 52, height: 52)
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 13))
                .foregroundStyle(SquishTheme.soft)
            TradeImages.plate(for: trade.giving.first, trade: trade, store: store, mine: allSpecimens)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(trade.friendName)
                    .typeStyle(.d4)
                    .foregroundStyle(SquishTheme.ink)
                MonoLabel(text: summary)
                    .lineLimit(2)
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

    private var summary: String {
        let getting = trade.getting.map(\.name).joined(separator: " + ")
        let giving = trade.giving.map(\.name).joined(separator: " + ")
        switch trade.state {
        case .needsMyReply: return "Wants your \(giving)"
        case .waitingForReply: return "You asked for \(getting)"
        case .inProgress:
            return trade.iHandedOver ? "Waiting for \(trade.friendName) to hand over" : "Hand over \(giving)"
        case .completed: return "Traded · \(getting) is yours"
        case .declined: return "Said no this time"
        case .cancelled: return "Cancelled"
        case .expired: return "Expired"
        }
    }
}

/// Finds a picture for a trade line: a friend's shelf thumbnail, or this
/// user's own photograph.
enum TradeImages {
    @MainActor
    static func image(for line: TradeLine?, trade: Trade, store: FriendsStore, mine: [Squishy]) -> UIImage? {
        guard let line else { return nil }
        if let own = mine.first(where: { $0.lineageID.uuidString == line.id }) {
            return own.image
        }
        return store.friend(trade.friendID)?.items.first { $0.id == line.id }?.image
    }

    @MainActor
    static func plate(for line: TradeLine?, trade: Trade, store: FriendsStore, mine: [Squishy]) -> some View {
        PhotoPlate(image: image(for: line, trade: trade, store: store, mine: mine), cornerRadius: 12)
    }
}

// MARK: - Detail

/// F4 / F5 — one trade. What each side gives, and the one action that moves
/// it forward for this user.
struct TradeDetailView: View {
    let tradeID: UUID

    @Environment(FriendsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query private var allSpecimens: [Squishy]
    @State private var isWorking = false
    @State private var error: String?
    @State private var confirmingCancel = false

    private var trade: Trade? { store.trades.first { $0.id == tradeID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FriendsHeader(title: title, subtitle: subtitle)
                if let trade {
                    VStack(alignment: .leading, spacing: SquishTheme.Space.margin) {
                        swap(trade)
                        if let line = trade.request.line {
                            Text("“\(line)”")
                                .typeStyle(.b1)
                                .foregroundStyle(SquishTheme.ink)
                                .padding(.horizontal, SquishTheme.Space.gutter)
                                .padding(.vertical, SquishTheme.Space.sm)
                                .background(SquishTheme.chalk, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        if trade.state == .inProgress || trade.state == .completed {
                            handover(trade)
                        }
                        Text(explanation(trade))
                            .typeStyle(.b3)
                            .foregroundStyle(SquishTheme.soft)
                        if let error {
                            FriendsNotice(title: "Didn't go through", message: error)
                        }
                    }
                    .padding(.horizontal, SquishTheme.Space.margin)
                    .padding(.top, SquishTheme.Space.margin)
                } else {
                    FriendsNotice(title: "Gone", message: "This trade isn't available any more.")
                        .padding(SquishTheme.Space.margin)
                }
                Color.clear.frame(height: 120)
            }
        }
        .scrollIndicators(.hidden)
        .background(SquishTheme.putty.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if let trade { actions(trade) }
        }
        .confirmationDialog("Cancel this request?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Cancel request", role: .destructive) { run { try await store.cancel($0) } }
            Button("Keep it", role: .cancel) {}
        }
    }

    private var title: String {
        guard let trade else { return "Trade" }
        switch trade.state {
        case .needsMyReply: return "\(trade.friendName) wants to trade"
        case .waitingForReply: return "Waiting for \(trade.friendName)"
        case .inProgress: return "Time to swap"
        case .completed: return "Traded"
        case .declined: return "Not this time"
        case .cancelled: return "Cancelled"
        case .expired: return "Expired"
        }
    }

    private var subtitle: String? {
        guard let trade else { return nil }
        var parts = ["Sent " + trade.request.createdAt.formatted(date: .abbreviated, time: .omitted),
                     "\(trade.request.offered.count) for \(trade.request.wanted.count)"]
        if trade.state == .needsMyReply || trade.state == .waitingForReply {
            let left = max(0, Int((TradeRequest.lifetime - Date.now.timeIntervalSince(trade.request.createdAt)) / 86_400))
            parts.append("expires in \(left) days")
        }
        return parts.joined(separator: " · ")
    }

    private func swap(_ trade: Trade) -> some View {
        HStack(alignment: .top, spacing: SquishTheme.Space.sm) {
            side(trade.direction == .incoming ? "\(trade.friendName) gives" : "You'd get", lines: trade.getting, trade: trade)
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(SquishTheme.soft)
                .padding(.top, 90)
                .accessibilityHidden(true)
            side(trade.direction == .incoming ? "You give" : "You'd give", lines: trade.giving, trade: trade)
        }
        .frame(maxWidth: 640)
    }

    private func side(_ label: String, lines: [TradeLine], trade: Trade) -> some View {
        VStack(alignment: .leading, spacing: SquishTheme.Space.sm) {
            Eyebrow(label)
            ForEach(lines) { line in
                TradeImages.plate(for: line, trade: trade, store: store, mine: allSpecimens)
                    .aspectRatio(1, contentMode: .fit)
                Text(line.name)
                    .typeStyle(.d4)
                    .foregroundStyle(SquishTheme.ink)
                MonoLabel(text: "Squish \(SquishLevel(line.squishLevel).padded)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Reuses the Measuring checklist's box states (UX-SPEC §4.5).
    private func handover(_ trade: Trade) -> some View {
        VStack(spacing: 0) {
            checkRow(done: trade.theyHandedOver || trade.state == .completed,
                     text: "\(trade.friendName) hands over \(trade.getting.map(\.name).joined(separator: " + "))")
            HairlineRule()
            checkRow(done: trade.iHandedOver || trade.state == .completed,
                     text: "You hand over \(trade.giving.map(\.name).joined(separator: " + "))")
        }
        .padding(.horizontal, SquishTheme.Space.gutter)
        .background(SquishTheme.chalk, in: RoundedRectangle(cornerRadius: SquishTheme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SquishTheme.Radius.card, style: .continuous)
            .strokeBorder(SquishTheme.line, lineWidth: SquishTheme.hairline))
    }

    private func checkRow(done: Bool, text: String) -> some View {
        HStack(spacing: SquishTheme.Space.gutter) {
            RoundedRectangle(cornerRadius: 2)
                .fill(done ? SquishTheme.ink : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(done ? SquishTheme.ink : SquishTheme.soft))
                .frame(width: 13, height: 13)
            Text(text)
                .typeStyle(.b1)
                .foregroundStyle(SquishTheme.ink)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Not yet")
    }

    private func explanation(_ trade: Trade) -> String {
        switch trade.state {
        case .needsMyReply:
            return "If you both agree, swap the squishies in person or by post, then tick the hand-over. Nothing moves in your index until you've both ticked."
        case .waitingForReply:
            return "\(trade.friendName) will see this next time they open Squish Index."
        case .inProgress:
            return "Each of you ticks once your squishy is on its way. When both are ticked, it's filed in the new owner's index with its measurements."
        case .completed:
            return "Filed in your index, with where it came from."
        case .declined, .cancelled, .expired:
            return "Nothing changed on either shelf."
        }
    }

    @ViewBuilder
    private func actions(_ trade: Trade) -> some View {
        Group {
            switch trade.state {
            case .needsMyReply:
                HStack(spacing: SquishTheme.Space.sm) {
                    SecondaryPill(title: "No thanks") { run { try await store.respond(to: $0, accept: false) } }
                    PrimaryPill(title: "Accept") { run { try await store.respond(to: $0, accept: true) } }
                }
            case .inProgress where !trade.iHandedOver:
                PrimaryPill(title: "I've handed mine over") { run { try await store.markHandedOver($0) } }
            case .waitingForReply:
                SecondaryPill(title: "Cancel request") { confirmingCancel = true }
            default:
                EmptyView()
            }
        }
        .disabled(isWorking)
        .opacity(isWorking ? 0.5 : 1)
        .padding(.horizontal, SquishTheme.Space.margin)
        .padding(.bottom, SquishTheme.Space.sm)
    }

    private func run(_ action: @escaping (Trade) async throws -> Void) {
        guard let trade else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                try await action(trade)
            } catch {
                self.error = FriendsStore.describe(error)
            }
        }
    }
}
