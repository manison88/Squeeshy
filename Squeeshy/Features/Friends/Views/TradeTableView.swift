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
    /// How open the portals under both seats are, 0 → 1.
    @State private var portalOpen: CGFloat = 0
    /// How far the squeeshies have gone down through their portals, 0 → 1.
    @State private var sink: CGFloat = 0
    /// The arcs of light between the portals, 0 → 1.
    @State private var beam: Double = 0
    /// The squeeshies have come up through the other portal: each seat shows the other side's.
    @State private var crossed = false
    /// After a no: the portals flicker grey, shudder, and throw the squeeshies back up.
    @State private var glitching = false
    @State private var shake: CGFloat = 0
    @State private var thrown: CGFloat = 0
    @State private var sparksAt: Date?
    /// The swap has played out, so the celebration may take over once the trade is filed.
    @State private var swapDone = false
    @State private var wiped = false
    /// The last no, shown on the cleared board until something new goes on.
    @State private var lastNo: TradeTableSession.Rejection?
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
                // the collection): bring the squeeshies back up on their own seats.
                swapTask?.cancel()
                swapDone = false
                sparksAt = nil
                withTransaction(Transaction(animation: nil)) { crossed = false; beam = 0 }
                withAnimation(Motion.arrive) { sink = 0; portalOpen = 0 }
            }
        }
        .onChange(of: session.rejection?.id) { _, id in
            if id != nil { runRejection() } else { endRejection() }
        }
        .onChange(of: session.mine.isEmpty && session.theirs.isEmpty) { _, empty in
            if !empty { withAnimation(Motion.tap) { lastNo = nil } }
        }
        .sensoryFeedback(trigger: isTradedPhase) { _, traded in traded ? .success : nil }
        .sensoryFeedback(trigger: crossed) { _, crossed in crossed ? .impact(weight: .medium) : nil }
        .sensoryFeedback(trigger: session.rejection?.id) { _, id in id != nil ? .error : nil }
    }

    // MARK: Staging

    /// Two yeses: glowing portals open under both seats, each side's squeeshies
    /// sink into theirs, arcs of light cross the table, and they come up through
    /// the other portal. The celebration waits for this to finish.
    private func runSwap() {
        withAnimation(Motion.tap) { expanded = nil }
        swapTask?.cancel()
        guard !reduceMotion else {
            withTransaction(Transaction(animation: nil)) { crossed = true }
            withAnimation(Motion.nav) { swapDone = true }
            return
        }
        swapTask = Task {
            beam = 0
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { portalOpen = 1 }
            guard await pause(0.45) else { return }
            withAnimation(.easeIn(duration: 0.55)) { sink = 1 }
            guard await pause(0.55) else { return }
            withAnimation(.linear(duration: 0.9)) { beam = 1 }
            guard await pause(0.9) else { return }
            // Out of sight below both portals: change sides without animating it.
            withTransaction(Transaction(animation: nil)) { crossed = true }
            sparksAt = .now
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { sink = 0 }
            guard await pause(0.6) else { return }
            withAnimation(.easeIn(duration: 0.3)) { portalOpen = 0 }
            guard await pause(0.45) else { return }
            withAnimation(Motion.nav) { swapDone = true }
        }
    }

    private var isTradedPhase: Bool {
        if case .traded = session.phase { return true }
        return false
    }

    /// A no: the portals open and start to pull, then glitch grey, shudder, and
    /// throw the squeeshies back up onto their own seats, where they dissolve.
    /// The session empties the sides once this has played (`wipeDelay`), which
    /// ends the rejection and leaves the notice saying who said no.
    private func runRejection() {
        withAnimation(Motion.tap) { expanded = nil }
        lastNo = session.rejection
        rejectionTask?.cancel()
        rejectionTask = Task {
            if reduceMotion {
                guard await pause(0.3) else { return }
                withAnimation(.easeOut(duration: 0.3)) { wiped = true }
                return
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { portalOpen = 1 }
            guard await pause(0.4) else { return }
            withAnimation(.easeInOut(duration: 0.45)) { sink = 0.5 }
            guard await pause(0.45) else { return }
            glitching = true
            for x: CGFloat in [-6, 6, -5, 5, -4, 4, -3, 3, 0] {
                withAnimation(.linear(duration: 0.06)) { shake = x }
                guard await pause(0.065) else { return }
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { sink = 0; thrown = 90 }
            withAnimation(.easeIn(duration: 0.3)) { portalOpen = 0 }
            guard await pause(0.3) else { return }
            glitching = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { thrown = 0 }
            guard await pause(0.45) else { return }
            withAnimation(Motion.tap) { wiped = true }
        }
    }

    /// Sleeps, then says whether the staging should carry on.
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    private func endRejection() {
        rejectionTask?.cancel()
        rejectionTask = nil
        wiped = false
        glitching = false
        shake = 0
        thrown = 0
        sink = 0
        portalOpen = 0
    }

    private func restart() {
        swapTask?.cancel()
        swapTask = nil
        withTransaction(Transaction(animation: nil)) {
            crossed = false
            beam = 0
        }
        sparksAt = nil
        swapDone = false
        expanded = nil
        lastNo = nil
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
                // A refused squeeshy is thrown up above its seat; don't cut it off.
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
        let staging = portalOpen > 0 || sink > 0 || crossed
        return VStack(spacing: large ? 30 : 18) {
            HStack(alignment: .top, spacing: 10) {
                TableSeat(title: large ? "you put in" : "you",
                          items: crossed ? session.theirs : session.mine,
                          vote: session.myCurrentVote,
                          emptyText: "tap one of yours\nto put it in",
                          isWiped: wiped,
                          hidesCaption: staging,
                          portal: portal(under: .mine),
                          sink: sink, lift: thrown, jitter: shake) {
                    withAnimation(Motion.arrive) { expanded = .mine }
                }

                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ink3)
                    .frame(width: 20)
                    .padding(.top, large ? 150 : 90)
                    .opacity(staging ? 0 : 1)
                    .accessibilityHidden(true)

                TableSeat(title: large ? "\(session.partnerName) puts in" : session.partnerName,
                          items: crossed ? session.mine : session.theirs,
                          vote: session.theirCurrentVote,
                          emptyText: "waiting for\n\(session.partnerName)",
                          isWiped: wiped,
                          hidesCaption: staging,
                          portal: portal(under: .theirs),
                          sink: sink, lift: thrown, jitter: -shake) {
                    withAnimation(Motion.arrive) { expanded = .theirs }
                }
            }
            .padding(.top, 6)
            .overlay {
                PortalBeams(progress: beam,
                            hues: (mine: session.mine.first?.hue ?? 330,
                                   theirs: session.theirs.first?.hue ?? 330))
            }

            if let lastNo, showsNoNotice {
                NoTradeNotice(reason: lastNo.reason, partner: session.partnerName)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

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
        .animation(Motion.arrive, value: showsNoNotice)
    }

    /// The cleared board says who said no, until something new goes on.
    private var showsNoNotice: Bool {
        lastNo != nil && session.rejection == nil && session.mine.isEmpty && session.theirs.isEmpty
    }

    private var canVote: Bool { session.bothSidesFilled && session.canChangeTable }

    /// Each portal glows in the colour of what's coming up through it.
    private func portal(under side: TableSide) -> SeatPortal {
        let incoming = side == .mine ? session.theirs : session.mine
        return SeatPortal(open: portalOpen,
                          hue: incoming.first?.hue ?? 330,
                          glitching: glitching,
                          sparksAt: sparksAt)
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
