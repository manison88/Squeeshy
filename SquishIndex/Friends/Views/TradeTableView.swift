import SwiftData
import SwiftUI

/// T1–T5 — the in-person trade table. Two devices side by side, each puts
/// squishies in, each votes. Both yes on the same table → traded, on both
/// devices at once. Any change to the table clears both votes.
struct TradeTableView: View {
    var showsBack = true

    @Environment(FriendsStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Squishy.addedAt, order: .reverse) private var allSpecimens: [Squishy]

    @State private var session = TradeTableSession()

    private var mine: [Squishy] { allSpecimens.filter { !$0.isTraded } }

    var body: some View {
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
                    PrimaryPill(title: "Look again") { restart() }
                }
            }
        }
        .background(SquishTheme.putty.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .animation(SquishTheme.Motion.surface, value: session.phase)
        .onAppear { restart() }
        .onDisappear { session.end() }
        .sheet(item: Binding(get: { session.invitation }, set: { _ in })) { invitation in
            InvitationSheet(peer: invitation) { join in session.answerInvitation(join) }
                .interactiveDismissDisabled()
        }
        .sensoryFeedback(.success, trigger: isTraded)
    }

    private var isTraded: Bool {
        if case .traded = session.phase { return true }
        return false
    }

    /// On iPad the table is the root of the detail column, where `dismiss()`
    /// does nothing — so leaving goes back to looking instead.
    private func leave() {
        if showsBack {
            dismiss()
        } else {
            restart()
        }
    }

    private func restart() {
        session.end()
        session.begin(displayName: store.displayName, userID: store.myUserID, context: modelContext)
    }

    // MARK: T1 — looking

    private var looking: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FriendsHeader(title: "Trade in person", eyebrow: "In person", showsBack: showsBack)
                Text("Hold your phones near each other. Both need Squish Index open on this screen.")
                    .typeStyle(.b1)
                    .foregroundStyle(SquishTheme.soft)
                    .padding(.horizontal, SquishTheme.Space.margin)
                    .padding(.top, SquishTheme.Space.xs)

                Radar()
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)

                #if DEBUG
                TableDebugControls(session: session)
                #endif

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(title: "Nearby", detail: "\(session.nearby.count)")
                    if session.nearby.isEmpty {
                        Text("Nobody nearby yet. Ask your friend to open Trade in person too.")
                            .typeStyle(.b1)
                            .foregroundStyle(SquishTheme.soft)
                    }
                    ForEach(session.nearby) { peer in
                        HairlineRule()
                        HStack(spacing: SquishTheme.Space.gutter) {
                            FriendMonogram(hexes: store.friends.first { $0.name == peer.name }?.monogram ?? [])
                            VStack(alignment: .leading, spacing: 3) {
                                Text(peer.name)
                                    .typeStyle(.d4)
                                    .foregroundStyle(SquishTheme.ink)
                                MonoLabel(text: peer.isFriend ? "Friend · right here" : "Not a friend yet")
                            }
                            Spacer()
                            Button { session.open(with: peer) } label: {
                                Text(peer.isFriend ? "Open table" : "Ask")
                                    .typeStyle(.m1)
                                    .foregroundStyle(peer.isFriend ? SquishTheme.chalk : SquishTheme.ink)
                                    .padding(.horizontal, SquishTheme.Space.gutter)
                                    .frame(height: 36)
                                    .background(peer.isFriend ? SquishTheme.ink : SquishTheme.chalk, in: Capsule())
                                    .overlay(Capsule().strokeBorder(SquishTheme.line, lineWidth: peer.isFriend ? 0 : 1))
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("Open a trade table with \(peer.name)")
                        }
                        .frame(minHeight: 68)
                    }
                    Text("Only someone who taps Join can see your side of the table. Works without internet.")
                        .typeStyle(.b3)
                        .foregroundStyle(SquishTheme.soft)
                        .padding(.top, SquishTheme.Space.margin)
                }
                .padding(.horizontal, SquishTheme.Space.margin)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: T3/T4 — the table

    @ViewBuilder
    private var table: some View {
        if sizeClass == .regular {
            HStack(alignment: .top, spacing: SquishTheme.Space.lg) {
                VStack(alignment: .leading, spacing: 0) {
                    tableHeader
                    #if DEBUG
                    TableDebugControls(session: session)
                    #endif
                    board(large: true)
                        .padding(.horizontal, SquishTheme.Space.margin)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: SquishTheme.Space.sm) {
                    Eyebrow("Your shelf · tap to put in", tint: SquishTheme.ink)
                        .padding(.top, 90)
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SquishTheme.Space.gutter), count: 3),
                                  spacing: SquishTheme.Space.gutter) {
                            ForEach(mine) { specimen in shelfPlate(specimen) }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(width: 400)
                .padding(.trailing, SquishTheme.Space.margin)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                tableHeader
                #if DEBUG
                TableDebugControls(session: session)
                #endif
                ScrollView {
                    board(large: false)
                        .padding(.horizontal, SquishTheme.Space.margin)
                }
                .scrollIndicators(.hidden)
                VStack(alignment: .leading, spacing: SquishTheme.Space.sm) {
                    Eyebrow("Your shelf", tint: SquishTheme.ink)
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: SquishTheme.Space.gutter) {
                            ForEach(mine) { specimen in
                                shelfPlate(specimen).frame(width: 104)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: 170)
                }
                .padding(.horizontal, SquishTheme.Space.margin)
                .padding(.bottom, SquishTheme.Space.sm)
            }
        }
    }

    private var tableHeader: some View {
        FriendsHeader(title: "Trade table",
                      subtitle: "With \(session.partnerName) · nearby",
                      showsBack: false) {
            Button("Leave") { leave() }
                .typeStyle(.m1)
                .foregroundStyle(SquishTheme.quietInk)
                .frame(minHeight: 44)
        }
    }

    private func board(large: Bool) -> some View {
        VStack(spacing: large ? SquishTheme.Space.lg : SquishTheme.Space.margin) {
            HStack(alignment: .top, spacing: SquishTheme.Space.sm) {
                Seat(title: large ? "You put in" : "You",
                     items: session.mine,
                     vote: session.myCurrentVote,
                     emptyText: "Tap a squishy\nto put it in")
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(SquishTheme.soft)
                    .padding(.top, large ? 150 : 90)
                    .accessibilityHidden(true)
                Seat(title: large ? "\(session.partnerName) puts in" : session.partnerName,
                     items: session.theirs,
                     vote: session.theirCurrentVote,
                     emptyText: "Waiting for\n\(session.partnerName)")
            }
            .padding(.top, SquishTheme.Space.gutter)

            MonoLabel(text: session.statusLine)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.updatesFrequently)

            HStack(spacing: SquishTheme.Space.gutter) {
                VoteButton(title: "No trade", systemImage: "xmark", isYes: false,
                           isChosen: session.myCurrentVote == false) { session.vote(false) }
                VoteButton(title: "Trade", systemImage: "checkmark", isYes: true,
                           isChosen: session.myCurrentVote == true) { session.vote(true) }
            }
            .disabled(!session.bothSidesFilled)
            .opacity(session.bothSidesFilled ? 1 : 0.3)
        }
    }

    private func shelfPlate(_ specimen: Squishy) -> some View {
        PickablePlate(image: specimen.image,
                      name: specimen.name,
                      squish: specimen.squishLevel,
                      isSelected: session.contains(specimen)) {
            session.toggle(specimen)
        }
    }

    // MARK: T5 — traded

    private func traded(_ received: [String]) -> some View {
        centred(title: received.isEmpty ? "Traded" : "\(received.joined(separator: " and ")) \(received.count == 1 ? "is" : "are") yours",
                message: "Swap the real squishies now. What you got is filed in your index with its measurements, and what you gave moves to your Traded list.",
                stamp: true) {
            VStack(spacing: SquishTheme.Space.sm) {
                PrimaryPill(title: "Done") { leave() }
                SecondaryPill(title: "Trade again") { restart() }
            }
        }
    }

    // MARK: Layout helper

    private func centred(title: String, message: String) -> some View {
        centred(title: title, message: message, stamp: false) { EmptyView() }
    }

    private func centred<Actions: View>(title: String, message: String, stamp: Bool = false,
                                        @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: SquishTheme.Space.margin) {
            Spacer()
            if stamp {
                Text("Traded")
                    .typeStyle(.m2)
                    .textCase(.uppercase)
                    .tracking(3)
                    .foregroundStyle(SquishTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, SquishTheme.Space.sm)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SquishTheme.ink, lineWidth: 2))
                    .rotationEffect(.degrees(-4))
                    .accessibilityHidden(true)
            }
            Text(title)
                .typeStyle(.d2)
                .foregroundStyle(SquishTheme.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .typeStyle(.b1)
                .foregroundStyle(SquishTheme.soft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
            actions()
                .frame(maxWidth: 420)
        }
        .padding(SquishTheme.Space.margin)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Pieces

private struct Seat: View {
    let title: String
    let items: [TradeTableSession.TableItem]
    let vote: Bool?
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: SquishTheme.Space.sm) {
            HStack {
                Eyebrow(title, tint: SquishTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                VoteMark(vote: vote)
            }
            Group {
                if let first = items.first {
                    PhotoPlate(image: first.image) {
                        if items.count > 1 {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    StatusTag(text: "+\(items.count - 1) more")
                                }
                            }
                            .padding(SquishTheme.Space.sm)
                        }
                    }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    RoundedRectangle(cornerRadius: SquishTheme.Radius.plate, style: .continuous)
                        .strokeBorder(SquishTheme.soft.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .overlay(MonoLabel(text: emptyText).multilineTextAlignment(.center))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            Text(items.map(\.name).joined(separator: " + "))
                .typeStyle(.d4)
                .foregroundStyle(SquishTheme.ink)
                .lineLimit(2)
                .frame(minHeight: 21, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(SquishTheme.Motion.surface, value: items)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(items.isEmpty ? "Empty" : items.map(\.name).joined(separator: ", "))
    }
}

/// ✓ / ✗ / thinking — a shape and a word, never colour alone.
private struct VoteMark: View {
    let vote: Bool?

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                switch vote {
                case .some(true):
                    Circle().fill(SquishTheme.ink)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(SquishTheme.chalk)
                case .some(false):
                    Circle().strokeBorder(SquishTheme.ink, lineWidth: 1.5)
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(SquishTheme.ink)
                case .none:
                    Circle().strokeBorder(SquishTheme.soft, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                }
            }
            .frame(width: 18, height: 18)
            Text(vote == true ? "Yes" : vote == false ? "No" : "Thinking")
                .typeStyle(.m1)
                .foregroundStyle(vote == nil ? SquishTheme.quietInk : SquishTheme.ink)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(height: 26)
        .background(SquishTheme.chalk, in: Capsule())
        .overlay(Capsule().strokeBorder(vote == true ? SquishTheme.ink : SquishTheme.line, lineWidth: SquishTheme.hairline))
        .animation(SquishTheme.Motion.readout, value: vote)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(vote == true ? "Voted yes" : vote == false ? "Voted no" : "Not voted yet")
    }
}

private struct VoteButton: View {
    let title: String
    let systemImage: String
    let isYes: Bool
    let isChosen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                Text(title).typeStyle(.b2)
            }
            .foregroundStyle(filled ? SquishTheme.chalk : SquishTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(filled ? SquishTheme.ink : SquishTheme.chalk, in: Capsule())
            .overlay(Capsule().strokeBorder(SquishTheme.ink, lineWidth: 1.5))
            .overlay(Capsule().inset(by: -5).strokeBorder(SquishTheme.ink, lineWidth: isChosen ? 2 : 0))
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isChosen)
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    private var filled: Bool { isYes || isChosen }
}

private struct InvitationSheet: View {
    let peer: TradeTableSession.NearbyPeer
    let answer: (Bool) -> Void

    @Environment(FriendsStore.self) private var store

    var body: some View {
        VStack(spacing: SquishTheme.Space.margin) {
            Spacer()
            FriendMonogram(hexes: store.friends.first { $0.name == peer.name }?.monogram ?? [], size: 88)
            Text("\(peer.name) wants to open a trade table")
                .typeStyle(.d2)
                .foregroundStyle(SquishTheme.ink)
                .multilineTextAlignment(.center)
            if !peer.isFriend {
                StatusTag(text: "Not a friend yet")
            }
            Text("You'll each put squishies on the table and vote. Nothing trades unless you both say yes.")
                .typeStyle(.b1)
                .foregroundStyle(SquishTheme.soft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
            HStack(spacing: SquishTheme.Space.sm) {
                SecondaryPill(title: "Not now") { answer(false) }
                PrimaryPill(title: "Join table") { answer(true) }
            }
        }
        .padding(SquishTheme.Space.margin)
        .background(SquishTheme.putty.ignoresSafeArea())
        .presentationCornerRadius(SquishTheme.Radius.sheet)
    }
}

private struct Radar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach([120.0, 190.0], id: \.self) { size in
                Circle()
                    .strokeBorder(SquishTheme.line, lineWidth: SquishTheme.hairline)
                    .frame(width: size, height: size)
            }
            if !reduceMotion {
                Circle()
                    .strokeBorder(SquishTheme.line, lineWidth: SquishTheme.hairline)
                    .frame(width: pulse ? 240 : 60, height: pulse ? 240 : 60)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false), value: pulse)
            }
            MonoLabel(text: "Looking nearby")
                .padding(.horizontal, SquishTheme.Space.sm)
                .padding(.vertical, 4)
                .background(SquishTheme.putty)
        }
        .onAppear { pulse = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Looking for people nearby")
    }
}
