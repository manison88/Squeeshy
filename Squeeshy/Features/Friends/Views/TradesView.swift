import SwiftUI
import SwiftData

/// Every trade, grouped by who needs to act, and everything traded away.
struct TradesView: View {
    var showsBack = true

    @Environment(FriendsStore.self) private var store

    private var tint: Tint {
        Tint.sampled(from: store.trades.flatMap { ($0.getting + $0.giving).map(\.hue) })
    }

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: tint)
            VStack(spacing: 0) {
                FriendsHeader(title: "Trades",
                              caption: store.badgeCount > 0 ? "\(store.badgeCount) waiting on you" : nil,
                              showsBack: showsBack)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        group("Waiting for you", store.waitingForMe)
                        group("In progress", store.inProgress)
                        group("Sent", store.trades.filter { $0.state == .waitingForReply })
                        group("Finished", store.trades.filter {
                            [.completed, .declined, .cancelled, .expired].contains($0.state)
                        })

                        if !store.tradedAway.isEmpty {
                            friendsSectionLabel("Traded away", detail: "\(store.tradedAway.count)")
                            ForEach(store.tradedAway) { entry in
                                tradedRow(entry)
                            }
                        }

                        if store.trades.isEmpty && store.tradedAway.isEmpty {
                            Text("No trades yet. Open a friend's collection and tap a squeeshy to ask for it, or trade in person at a table.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.ink2)
                                .padding(.top, 10)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .refreshable { await store.refresh() }
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .filesReadyTrades()
    }

    @ViewBuilder
    private func group(_ title: String, _ trades: [Trade]) -> some View {
        if !trades.isEmpty {
            friendsSectionLabel(title, detail: "\(trades.count)")
            ForEach(trades) { trade in
                NavigationLink(value: FriendsRoute.trade(trade.id)) {
                    TradeRow(trade: trade)
                }
                .buttonStyle(.tap(22))
            }
        }
    }

    private func tradedRow(_ entry: TradedEntry) -> some View {
        HStack(spacing: 13) {
            LooseSquishyImage(image: entry.image, species: entry.species, color: entry.color)
                .frame(width: 44, height: 44)
                .padding(8)
                .opacity(0.6)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.display(16, .semibold))
                    .foregroundStyle(Color.ink)
                MetaLabel(text: "to \(entry.tradedTo) · \(entry.tradedAt.formatted(date: .abbreviated, time: .omitted))")
            }
            Spacer()
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

/// One trade: what each side gives, and the one action that moves it forward
/// for this user.
struct TradeDetailView: View {
    var tradeID: UUID

    @Environment(FriendsStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isWorking = false
    @State private var error: String?
    @State private var confirmingCancel = false

    private var trade: Trade? { store.trades.first { $0.id == tradeID } }

    private var tint: Tint {
        guard let trade else { return .fallback }
        return Tint.sampled(from: (trade.getting + trade.giving).map(\.hue))
    }

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: tint)
            VStack(spacing: 0) {
                FriendsHeader(title: title, caption: caption)
                ScrollView {
                    if let trade {
                        VStack(spacing: 18) {
                            swap(trade)
                            if let line = trade.request.line {
                                Text("“\(line)”")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.ink)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .glassEffect(.regular, in: .capsule)
                            }
                            if trade.state == .inProgress || trade.state == .completed {
                                handover(trade)
                            }
                            Text(explanation(trade))
                                .font(.system(size: 14))
                                .foregroundStyle(Color.ink2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 420)
                            if let error {
                                FriendsNotice(title: "Didn't go through", message: error)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 120)
                    } else {
                        FriendsNotice(title: "Gone", message: "This trade isn't available any more.")
                            .padding(20)
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if let trade { actions(trade) }
        }
        .filesReadyTrades()
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

    private var caption: String? {
        guard let trade else { return nil }
        var parts = ["sent " + trade.request.createdAt.formatted(date: .abbreviated, time: .omitted),
                     "\(trade.request.offered.count) for \(trade.request.wanted.count)"]
        if trade.state == .needsMyReply || trade.state == .waitingForReply {
            let left = max(0, Int((TradeRequest.lifetime - Date.now.timeIntervalSince(trade.request.createdAt)) / 86_400))
            parts.append("expires in \(left) days")
        }
        return parts.joined(separator: " · ")
    }

    private var heroSize: CGFloat { sizeClass == .regular ? 170 : 120 }

    private func swap(_ trade: Trade) -> some View {
        HStack(alignment: .top, spacing: 12) {
            side(trade.direction == .incoming ? "\(trade.friendName) gives" : "you'd get",
                 lines: trade.getting, trade: trade)
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.ink3)
                .padding(.top, heroSize / 2 + 20)
                .accessibilityHidden(true)
            side(trade.direction == .incoming ? "you give" : "you'd give",
                 lines: trade.giving, trade: trade)
        }
        .frame(maxWidth: 620)
    }

    private func side(_ label: String, lines: [TradeLine], trade: Trade) -> some View {
        VStack(spacing: 8) {
            MetaLabel(text: label)
            ForEach(lines) { line in
                TradeLineImage(line: line, friendID: trade.friendID)
                    .frame(width: heroSize, height: heroSize)
                Text(line.name)
                    .font(.display(17, .bold))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private func handover(_ trade: Trade) -> some View {
        VStack(spacing: 0) {
            checkRow(done: trade.theyHandedOver || trade.state == .completed,
                     text: "\(trade.friendName) hands over \(trade.getting.map(\.name).joined(separator: " + "))")
            Rectangle().fill(Color.hairline).frame(height: 1)
            checkRow(done: trade.iHandedOver || trade.state == .completed,
                     text: "You hand over \(trade.giving.map(\.name).joined(separator: " + "))")
        }
        .padding(.horizontal, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .frame(maxWidth: 620)
    }

    private func checkRow(done: Bool, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(done ? Color.ink : Color.ink3)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Color.ink)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Not yet")
    }

    private func explanation(_ trade: Trade) -> String {
        switch trade.state {
        case .needsMyReply:
            return "If you both agree, swap the real squeeshies in person or by post, then tick the hand-over. Nothing changes in your collection until you've both ticked."
        case .waitingForReply:
            return "\(trade.friendName) will see this next time they open Squeeshy."
        case .inProgress:
            return "Tick once yours is on its way. When you both have, each squeeshy lands in its new owner's collection with its traits and cut-out."
        case .completed:
            return "It's in your collection now, and remembers where it came from."
        case .declined, .cancelled, .expired:
            return "Nothing changed on either side."
        }
    }

    @ViewBuilder
    private func actions(_ trade: Trade) -> some View {
        Group {
            switch trade.state {
            case .needsMyReply:
                HStack(spacing: 10) {
                    GlassCTA(title: "No thanks") { run { try await store.respond(to: $0, accept: false) } }
                    TintedCTA(title: "Accept", tint: tint) { run { try await store.respond(to: $0, accept: true) } }
                }
            case .inProgress where !trade.iHandedOver:
                TintedCTA(title: "I've handed mine over", systemImage: "hand.raised", tint: tint) {
                    run { try await store.markHandedOver($0) }
                }
            case .waitingForReply:
                GlassCTA(title: "Cancel request") { confirmingCancel = true }
            default:
                EmptyView()
            }
        }
        .disabled(isWorking)
        .opacity(isWorking ? 0.5 : 1)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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
