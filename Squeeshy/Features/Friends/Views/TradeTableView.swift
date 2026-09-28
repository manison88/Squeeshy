import SwiftUI
import SwiftData

/// The in-person trade table. Two devices side by side, each puts squeeshies in,
/// each votes. Both yes on the same table → traded, on both devices at once.
/// Changing anything on the table clears both votes.
struct TradeTableView: View {
    var showsBack = true

    @Environment(FriendsStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Squishy.addedAt, order: .reverse) private var squishies: [Squishy]

    @State private var session = TradeTableSession()

    /// Something already promised in a remote trade can't go on the table too.
    private var offerable: [Squishy] {
        let promised = store.promisedIDs
        return squishies.filter { !promised.contains($0.lineageID.uuidString) }
    }

    private var tint: Tint {
        Tint.sampled(from: (session.mine + session.theirs).map(\.hue) + squishies.prefix(12).map(\.hue))
    }

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: tint)
            Group {
                switch session.phase {
                case .idle, .looking:
                    looking
                case .connecting(let name):
                    centred(title: "Connecting to \(name)…",
                            message: "Keep your phones close together.")
                case .atTable:
                    table
                case .traded(let received):
                    traded(received)
                case .ended(let message):
                    centred(title: "Table closed", message: message) {
                        TintedCTA(title: "Look again", tint: tint) { restart() }
                    }
                }
            }
            .transition(.opacity)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .animation(Motion.nav, value: session.phase)
        .onAppear { restart() }
        .onDisappear { session.end() }
        .sheet(item: Binding(get: { session.invitation }, set: { _ in })) { invitation in
            InvitationSheet(peer: invitation) { join in session.answerInvitation(join) }
                .presentationDetents([.medium])
                .interactiveDismissDisabled()
        }
        .sensoryFeedback(.success, trigger: isTraded)
    }

    private var isTraded: Bool {
        if case .traded = session.phase { return true }
        return false
    }

    private func restart() {
        session.end()
        session.begin(displayName: store.displayName, userID: store.myUserID, context: context)
    }

    /// On iPad the table can be the root of the detail column, where `dismiss()`
    /// does nothing — so leaving goes back to looking instead.
    private func leave() {
        if showsBack { dismiss() } else { restart() }
    }

    // MARK: Looking

    private var looking: some View {
        VStack(spacing: 0) {
            FriendsHeader(title: "Trade in person", caption: "no internet needed", showsBack: showsBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hold your phones near each other. Both need Squeeshy open on this screen.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ink2)

                    Radar()
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)

                    #if DEBUG
                    TableDebugControls(session: session)
                    #endif

                    friendsSectionLabel("Nearby", detail: "\(session.nearby.count)")
                    if session.nearby.isEmpty {
                        Text("Nobody nearby yet. Ask your friend to open Trade in person too.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.ink2)
                    }
                    ForEach(session.nearby) { peer in
                        nearbyRow(peer)
                    }
                    MetaLabel(text: "only someone who taps join can see your side", color: .ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func nearbyRow(_ peer: TradeTableSession.NearbyPeer) -> some View {
        let friend = store.friends.first { $0.name == peer.name }
        return HStack(spacing: 13) {
            FriendStack(items: friend?.items ?? [])
            VStack(alignment: .leading, spacing: 3) {
                Text(peer.name)
                    .font(.display(16, .semibold))
                    .foregroundStyle(Color.ink)
                MetaLabel(text: peer.isFriend ? "friend · right here" : "not a friend yet")
            }
            Spacer(minLength: 8)
            Button { session.open(with: peer) } label: {
                Text(peer.isFriend ? "Open table" : "Ask")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.tap(18))
            .accessibilityLabel("Open a trade table with \(peer.name)")
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    // MARK: The table

    @ViewBuilder
    private var table: some View {
        if sizeClass == .regular {
            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 0) {
                    tableHeader
                    #if DEBUG
                    TableDebugControls(session: session).padding(.horizontal, 20)
                    #endif
                    board(large: true).padding(.horizontal, 20)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    MetaLabel(text: "your squeeshies · tap to put in")
                        .padding(.top, 70)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                            ForEach(offerable) { shelfTile($0) }
                        }
                        .padding(.bottom, 30)
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(width: 380)
                .padding(.trailing, 20)
            }
        } else {
            VStack(spacing: 0) {
                tableHeader
                #if DEBUG
                TableDebugControls(session: session).padding(.horizontal, 20)
                #endif
                ScrollView {
                    board(large: false).padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                VStack(alignment: .leading, spacing: 8) {
                    MetaLabel(text: "your squeeshies")
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 10) {
                            ForEach(offerable) { shelfTile($0).frame(width: 96) }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: 112)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }

    private var tableHeader: some View {
        FriendsHeader(title: "Trade table", caption: "with \(session.partnerName) · nearby", showsBack: false) {
            Button("Leave") { leave() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ink)
                .buttonStyle(.tap)
        }
    }

    private func board(large: Bool) -> some View {
        VStack(spacing: large ? 30 : 18) {
            HStack(alignment: .top, spacing: 10) {
                Seat(title: large ? "you put in" : "you",
                     items: session.mine,
                     vote: session.myCurrentVote,
                     emptyText: "tap one of yours\nto put it in")
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ink3)
                    .padding(.top, large ? 150 : 90)
                    .accessibilityHidden(true)
                Seat(title: large ? "\(session.partnerName) puts in" : session.partnerName,
                     items: session.theirs,
                     vote: session.theirCurrentVote,
                     emptyText: "waiting for\n\(session.partnerName)")
            }
            .padding(.top, 6)

            MetaLabel(text: session.statusLine)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.updatesFrequently)

            HStack(spacing: 12) {
                VoteButton(title: "No trade", systemImage: "xmark", isYes: false,
                           isChosen: session.myCurrentVote == false, tint: tint) { session.vote(false) }
                VoteButton(title: "Trade", systemImage: "checkmark", isYes: true,
                           isChosen: session.myCurrentVote == true, tint: tint) { session.vote(true) }
            }
            .disabled(!session.bothSidesFilled)
            .opacity(session.bothSidesFilled ? 1 : 0.35)
        }
    }

    private func shelfTile(_ squishy: Squishy) -> some View {
        PickTile(name: squishy.name,
                 tint: squishy.color,
                 isOn: session.contains(squishy)) {
            SquishyImage(squishy: squishy)
        } action: {
            session.toggle(squishy)
        }
    }

    // MARK: Traded

    private func traded(_ received: [String]) -> some View {
        centred(title: received.isEmpty ? "Traded"
                    : "\(received.joined(separator: " and ")) \(received.count == 1 ? "is" : "are") yours",
                message: "Swap the real squeeshies now. What you got is in your collection with its cut-out and traits, and what you gave is under Trades → Traded away.",
                stamp: true) {
            VStack(spacing: 10) {
                TintedCTA(title: "Done", tint: tint) { leave() }
                GlassCTA(title: "Trade again") { restart() }
            }
        }
    }

    // MARK: Layout helper

    private func centred(title: String, message: String) -> some View {
        centred(title: title, message: message, stamp: false) { EmptyView() }
    }

    private func centred<Actions: View>(title: String, message: String, stamp: Bool = false,
                                        @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 18) {
            Spacer()
            if stamp {
                Text("TRADED")
                    .font(.mono(13, .semibold))
                    .tracking(4)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ink, lineWidth: 2))
                    .rotationEffect(.degrees(-4))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.display(28, .heavy))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
            actions()
                .frame(maxWidth: 420)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Pieces

private struct Seat: View {
    var title: String
    var items: [TradeTableSession.TableItem]
    var vote: Bool?
    var emptyText: String

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                MetaLabel(text: title, color: .ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                VoteMark(vote: vote)
            }
            Group {
                if let first = items.first {
                    LooseSquishyImage(image: first.image, species: first.species, color: first.color)
                        .padding(14)
                        .overlay(alignment: .bottomTrailing) {
                            if items.count > 1 {
                                Text("+\(items.count - 1)")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.ink)
                                    .padding(.horizontal, 8)
                                    .frame(height: 24)
                                    .glassEffect(.regular, in: .capsule)
                                    .padding(8)
                            }
                        }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Color.ink3, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .overlay(MetaLabel(text: emptyText, color: .ink3).multilineTextAlignment(.center))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            Text(items.map(\.name).joined(separator: " + "))
                .font(.display(15, .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(minHeight: 20)
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.arrive, value: items)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(items.isEmpty ? "Empty" : items.map(\.name).joined(separator: ", "))
    }
}

/// ✓ / ✗ / thinking — a shape and a word, never colour alone.
private struct VoteMark: View {
    var vote: Bool?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: vote == true ? "checkmark.circle.fill"
                  : vote == false ? "xmark.circle" : "circle.dashed")
                .font(.system(size: 14, weight: .semibold))
            Text(vote == true ? "YES" : vote == false ? "NO" : "THINKING")
                .font(.mono(9, .semibold))
                .tracking(1)
        }
        .foregroundStyle(vote == nil ? Color.ink3 : Color.ink)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .glassEffect(.regular, in: .capsule)
        .contentTransition(.symbolEffect(.replace))
        .animation(Motion.tap, value: vote)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(vote == true ? "Voted yes" : vote == false ? "Voted no" : "Not voted yet")
    }
}

private struct VoteButton: View {
    var title: String
    var systemImage: String
    var isYes: Bool
    var isChosen: Bool
    var tint: Tint
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 15, weight: .bold))
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(isYes ? Color(red: 0.05, green: 0.04, blue: 0.08) : Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background {
                if isYes {
                    Capsule().fill(LinearGradient(colors: [tint.primary, tint.secondary],
                                                  startPoint: .leading, endPoint: .trailing))
                }
            }
            .glassEffect(isYes ? .identity : .regular.interactive(), in: .capsule)
            .overlay(Capsule().inset(by: -4).strokeBorder(Color.ink, lineWidth: isChosen ? 2 : 0))
            .scaleEffect(isChosen ? 1.03 : 1)
        }
        .buttonStyle(.tap(30))
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isChosen)
        .animation(Motion.tap, value: isChosen)
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }
}

private struct InvitationSheet: View {
    var peer: TradeTableSession.NearbyPeer
    var answer: (Bool) -> Void

    @Environment(FriendsStore.self) private var store

    var body: some View {
        let friend = store.friends.first { $0.name == peer.name }
        ZStack {
            AdaptiveBackground(tint: friend?.tint ?? .fallback)
            VStack(spacing: 16) {
                Spacer()
                FriendStack(items: friend?.items ?? [])
                    .scaleEffect(1.4)
                    .padding(.bottom, 10)
                Text("\(peer.name) wants to open a trade table")
                    .font(.display(24, .heavy))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                if !peer.isFriend {
                    MetaLabel(text: "not a friend yet", color: .ink)
                }
                Text("You'll each put squeeshies on the table and vote. Nothing trades unless you both say yes.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                Spacer()
                HStack(spacing: 10) {
                    GlassCTA(title: "Not now") { answer(false) }
                    TintedCTA(title: "Join table", tint: friend?.tint ?? .fallback) { answer(true) }
                }
            }
            .padding(22)
        }
    }
}

private struct Radar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach([120.0, 190.0], id: \.self) { size in
                Circle()
                    .strokeBorder(Color.hairline, lineWidth: 1)
                    .frame(width: size, height: size)
            }
            if !reduceMotion {
                Circle()
                    .strokeBorder(Color.ink3, lineWidth: 1)
                    .frame(width: pulse ? 240 : 60, height: pulse ? 240 : 60)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false), value: pulse)
            }
            MetaLabel(text: "looking nearby")
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular, in: .capsule)
        }
        .onAppear { pulse = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Looking for people nearby")
    }
}
