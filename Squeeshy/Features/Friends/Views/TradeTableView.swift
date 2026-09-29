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

    // Animation state. The session decides *what* happened; these only stage it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 at rest, 1 mid-swap (lifted and crossing), 2 landed on the other side.
    @State private var swapStep = 0
    /// The swap has played out, so the celebration may take over once the trade is filed.
    @State private var swapDone = false
    @State private var boardWidth: CGFloat = 0
    @State private var shake: CGFloat = 0
    @State private var sweep: Double = 0
    @State private var wiped = false
    @State private var expanded: TableSide?
    /// The running stagings, so a table that closes mid-animation can't have an old
    /// animation land on the next one.
    @State private var swapTask: Task<Void, Never>?
    @State private var rejectionTask: Task<Void, Never>?

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
                case .traded:
                    // Hold the table on screen until the swap has finished moving,
                    // however quickly the two phones finished exchanging.
                    if swapDone {
                        TradedCelebration(received: session.theirs, given: session.mine, tint: tint,
                                          onDone: leave, onAgain: restart)
                            .transition(.opacity)
                    } else {
                        table
                    }
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
        .overlay { expandedSeat }
        .onChange(of: session.isSwapping) { _, swapping in
            if swapping {
                runSwap()
            } else if !isTradedPhase {
                // Two yeses that didn't become a trade (a late no, something left
                // the collection): put the squeeshies back on their own seats.
                swapTask?.cancel()
                swapDone = false
                withAnimation(Motion.arrive) { swapStep = 0 }
            }
        }
        .onChange(of: session.rejection?.id) { _, id in
            if id != nil { runRejection() } else { endRejection() }
        }
        .sensoryFeedback(trigger: isTradedPhase) { _, traded in traded ? .success : nil }
        .sensoryFeedback(trigger: swapStep) { _, step in step == 1 ? .impact(weight: .medium) : nil }
        .sensoryFeedback(trigger: session.rejection?.id) { _, id in id != nil ? .error : nil }
    }

    // MARK: Staging

    /// Two yeses: each side's squeeshies lift, cross in an arc through a burst of
    /// the table's colours, and land on the other side. The celebration waits for
    /// this to finish.
    private func runSwap() {
        withAnimation(Motion.tap) { expanded = nil }
        swapTask?.cancel()
        guard !reduceMotion else {
            withAnimation(Motion.nav) { swapDone = true }
            return
        }
        swapTask = Task {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { swapStep = 1 }
            try? await Task.sleep(for: .seconds(0.45))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) { swapStep = 2 }
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.nav) { swapDone = true }
        }
    }

    private var isTradedPhase: Bool {
        if case .traded = session.phase { return true }
        return false
    }

    /// A no: the stamp lands (NoTradeStamp animates itself), the board shakes,
    /// and a sweep crosses it, taking the squeeshies with it. The session empties
    /// the sides a moment later, which ends the rejection.
    private func runRejection() {
        withAnimation(Motion.tap) { expanded = nil }
        rejectionTask?.cancel()
        rejectionTask = Task {
            if !reduceMotion {
                for x in [-16.0, 13, -10, 7, -4, 0] {
                    withAnimation(.spring(response: 0.08, dampingFraction: 0.5)) { shake = x }
                    try? await Task.sleep(for: .milliseconds(65))
                    guard !Task.isCancelled else { return }
                }
            }
            try? await Task.sleep(for: .seconds(0.35))
            guard !Task.isCancelled else { return }
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.3)) { wiped = true }
                return
            }
            withAnimation(.easeInOut(duration: 0.7)) { sweep = 1 }
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.tap) { wiped = true }
        }
    }

    private func endRejection() {
        rejectionTask?.cancel()
        rejectionTask = nil
        wiped = false
        sweep = 0
        shake = 0
    }

    private func restart() {
        swapTask?.cancel()
        swapTask = nil
        swapStep = 0
        swapDone = false
        expanded = nil
        endRejection()
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
                // The swap lifts squeeshies above their seats; don't cut them off.
                .scrollClipDisabled()
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
                TableSeat(title: large ? "you put in" : "you",
                          items: session.mine,
                          vote: session.myCurrentVote,
                          emptyText: "tap one of yours\nto put it in",
                          isWiped: wiped,
                          hidesCaption: swapStep > 0,
                          swapOffset: swapOffset(for: .mine),
                          swapRotation: .degrees(swapStep == 1 ? 14 : 0),
                          swapScale: swapStep == 1 ? 1.12 : 1) {
                    withAnimation(Motion.arrive) { expanded = .mine }
                }
                .zIndex(swapStep > 0 ? 2 : 0)

                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ink3)
                    .frame(width: 20)
                    .padding(.top, large ? 150 : 90)
                    .opacity(swapStep > 0 ? 0 : 1)
                    .accessibilityHidden(true)

                TableSeat(title: large ? "\(session.partnerName) puts in" : session.partnerName,
                          items: session.theirs,
                          vote: session.theirCurrentVote,
                          emptyText: "waiting for\n\(session.partnerName)",
                          isWiped: wiped,
                          hidesCaption: swapStep > 0,
                          swapOffset: swapOffset(for: .theirs),
                          swapRotation: .degrees(swapStep == 1 ? -14 : 0),
                          swapScale: swapStep == 1 ? 1.12 : 1) {
                    withAnimation(Motion.arrive) { expanded = .theirs }
                }
                .zIndex(swapStep > 0 ? 1 : 0)
            }
            .padding(.top, 6)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boardWidth = $0 }
            .overlay { SwapGlow(tint: tint, isActive: swapStep == 1) }
            .overlay { SweepBar(progress: sweep) }
            .overlay {
                if let rejection = session.rejection {
                    NoTradeStamp(reason: rejection.reason, partner: session.partnerName)
                        .transition(.opacity)
                }
            }
            .offset(x: shake)
            .animation(Motion.tap, value: session.rejection?.id)

            MetaLabel(text: session.statusLine)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)
                .animation(Motion.tap, value: session.statusLine)
                .accessibilityAddTraits(.updatesFrequently)

            HStack(spacing: 12) {
                VoteButton(title: "No trade", systemImage: "xmark", isYes: false,
                           isChosen: session.myCurrentVote == false, tint: tint) { session.vote(false) }
                VoteButton(title: "Trade", systemImage: "checkmark", isYes: true,
                           isChosen: session.myCurrentVote == true, tint: tint) { session.vote(true) }
            }
            .disabled(!canVote)
            .opacity(canVote ? 1 : 0.35)
        }
    }

    private var canVote: Bool { session.bothSidesFilled && session.canChangeTable }

    /// How far each side's squeeshies travel to land on the other seat: the
    /// distance between the two seat centres. Lifted one way and dropped the other
    /// mid-flight, so they cross in an arc rather than colliding.
    private func swapOffset(for side: TableSide) -> CGSize {
        let travel = (boardWidth + 40) / 2
        let direction: CGFloat = side == .mine ? 1 : -1
        switch swapStep {
        case 1: return CGSize(width: direction * travel / 2, height: side == .mine ? -44 : 44)
        case 2: return CGSize(width: direction * travel, height: 0)
        default: return .zero
        }
    }

    /// A seat opened up to show everything on that side.
    @ViewBuilder
    private var expandedSeat: some View {
        if let side = expanded, case .atTable = session.phase {
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(Motion.tap) { expanded = nil } }
                    .accessibilityHidden(true)
                SeatExpanded(title: side == .mine ? "You put in" : "\(session.partnerName) puts in",
                             items: side == .mine ? session.mine : session.theirs,
                             canRemove: side == .mine && session.canChangeTable,
                             onRemove: { id in
                                 withAnimation(Motion.arrive) { session.remove(itemID: id) }
                                 if session.mine.isEmpty {
                                     withAnimation(Motion.tap) { expanded = nil }
                                 }
                             },
                             onClose: { withAnimation(Motion.tap) { expanded = nil } })
                    .transition(.scale(scale: 0.7, anchor: side == .mine ? .leading : .trailing)
                        .combined(with: .opacity))
            }
            .transition(.opacity)
        }
    }

    private func shelfTile(_ squishy: Squishy) -> some View {
        PickTile(name: squishy.name,
                 tint: squishy.color,
                 isOn: session.contains(squishy),
                 isEnabled: session.canChangeTable) {
            SquishyImage(squishy: squishy)
        } action: {
            session.toggle(squishy)
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
