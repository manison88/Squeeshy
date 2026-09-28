#if DEBUG
import Foundation
import SwiftData

/// Debug builds only. Launch with `-FriendsSelfTest YES` to run every friends
/// and trading flow against the simulator and print PASS / FAIL lines
/// (prefixed `[SelfTest]`) to the console. Uses the real store, ledger and
/// trade-table protocol; only iCloud and the other phone are simulated.
@MainActor
enum FriendsSelfTest {
    static var isRequested: Bool { UserDefaults.standard.bool(forKey: "FriendsSelfTest") }

    private static var passed = 0
    private static var failed = 0

    static func run(container: ModelContainer) async {
        let store = FriendsStore.shared
        let context = container.mainContext
        log("start")
        await store.setSimulation(true)
        // No friends screen is open during the test, so allow filing explicitly.
        store.beginFiling()
        store.setDisplayName("Tester")
        store.debugSeedShelf(8)
        guard let sim = store.simulator, let mia = store.friends.first else {
            return check("simulation starts with a friend", false)
        }
        check("simulation starts with a friend", mia.name == "Mia")

        // 1. Outgoing request, accepted, handed over both ways.
        sim.replyBehaviour = .accept
        sim.autoHandOver = true
        var mine = held(context)
        let offer = mine[0]
        // Deleted when traded away, so only its ID is safe to read afterwards.
        let offerID = offer.lineageID.uuidString
        let want = mia.items[0]
        try? await store.sendRequest(to: mia, wanting: [want], offering: [offer], line: .double)
        let out = await waitFor("outgoing request accepted") { store.trades.first?.state == .inProgress }
        if out, let trade = store.trades.first {
            try? await store.markHandedOver(trade)
            await waitFor("outgoing trade completes") { store.trades.first { $0.id == trade.id }?.state == .completed }
            check("offered squeeshy left the collection and was archived", isGone(offerID, context)
                  && store.tradedAway.contains { $0.lineageID.uuidString == offerID && $0.tradedTo == "Mia" })
            let got = all(context).first { $0.lineageID.uuidString == want.id }
            check("wanted squishy filed with provenance",
                  got != nil && got?.acquiredFrom == "Mia" && got?.provenance.last?.owner == "Mia")
            check("Mia's shelf swapped", store.friend(mia.id).map { f in
                f.items.contains { $0.id == offerID } && !f.items.contains { $0.id == want.id }
            } ?? false)
        }

        // 2. Incoming request, accepted.
        let problem = store.debugIncomingRequest()
        check("friend can send a request", problem == nil)
        let inc = await waitFor("incoming request shows as waiting for me") { !store.waitingForMe.isEmpty }
        if inc, let trade = store.waitingForMe.first {
            check("badge counts the waiting request", store.badgeCount >= 1)
            let giving = trade.giving.first?.id
            try? await store.respond(to: trade, accept: true)
            await waitFor("friend hands over after I accept") {
                store.trades.first { $0.id == trade.id }?.theyHandedOver == true
            }
            if let current = store.trades.first(where: { $0.id == trade.id }) {
                try? await store.markHandedOver(current)
            }
            await waitFor("incoming trade completes") { store.trades.first { $0.id == trade.id }?.state == .completed }
            check("given squeeshy left the collection", giving.map { isGone($0, context) } ?? false)
        }

        // 3. Declined.
        sim.replyBehaviour = .decline
        mine = held(context)
        if let mia = store.friend(mia.id), let item = mia.items.first {
            try? await store.sendRequest(to: mia, wanting: [item], offering: [mine[0]], line: nil)
            let id = store.trades.first?.id
            await waitFor("declined request shows declined") { store.trades.first { $0.id == id }?.state == .declined }
        }

        // 4. Cancelled before a reply; a friend must not answer it afterwards.
        sim.replyBehaviour = .ignore
        if let mia = store.friend(mia.id), let item = mia.items.first {
            try? await store.sendRequest(to: mia, wanting: [item], offering: [mine[1]], line: nil)
            if let trade = store.trades.first(where: { $0.state == .waitingForReply }) {
                try? await store.cancel(trade)
                sim.replyBehaviour = .accept
                try? await Task.sleep(for: .seconds(2.5))
                check("cancelled request stays cancelled", store.trades.first { $0.id == trade.id }?.state == .cancelled)
            }
        }

        // 5. Limit on open outgoing requests.
        sim.replyBehaviour = .ignore
        var sentOK = 0
        var limitHit = false
        mine = held(context)
        for index in 0..<(FriendsStore.maxOpenOutgoing + 1) {
            guard let mia = store.friend(mia.id), let item = mia.items.first else { break }
            do {
                try await store.sendRequest(to: mia, wanting: [item], offering: [mine[index % mine.count]], line: nil)
                sentOK += 1
            } catch FriendsStore.TradeError.tooManyOpen {
                limitHit = true
            } catch {}
        }
        check("open request limit enforced at \(FriendsStore.maxOpenOutgoing)", limitHit && sentOK == FriendsStore.maxOpenOutgoing)
        for trade in store.trades where trade.state == .waitingForReply { try? await store.cancel(trade) }

        // 6. The same squishy offered in two requests at once.
        sim.replyBehaviour = .accept
        mine = held(context)
        let doubled = mine[0]
        if let mia = store.friend(mia.id), mia.items.count >= 2 {
            try? await store.sendRequest(to: mia, wanting: [mia.items[0]], offering: [doubled], line: nil)
            let second = try? await store.sendRequest(to: mia, wanting: [mia.items[1]], offering: [doubled], line: nil)
            check("same squeeshy can't be offered in two open requests", second == nil)
            for trade in store.trades where trade.state == .waitingForReply || trade.state == .inProgress {
                try? await store.cancel(trade)
            }
        }

        await tableTests(context: context)

        log("done · \(passed) passed · \(failed) failed")
    }

    // MARK: Trade table

    private static func tableTests(context: ModelContext) async {
        let store = FriendsStore.shared

        // A full swap.
        var session = TradeTableSession()
        session.begin(displayName: store.displayName, userID: store.myUserID, context: context)
        guard await waitFor("simulated partner appears nearby", { !session.nearby.isEmpty }),
              let peer = session.nearby.first else { return }
        session.open(with: peer)
        await waitFor("table opens") { if case .atTable = session.phase { true } else { false } }
        await waitFor("partner puts one in") { !session.theirs.isEmpty }
        let giving = held(context)[0]
        let givingID = giving.lineageID.uuidString
        if !session.contains(giving) { session.toggle(giving) }
        let receivingID = session.theirs.first?.id
        await waitFor("partner sees my side") { session.theirs.count == 1 }
        session.vote(true)
        let traded = await waitFor("table trade completes") { if case .traded = session.phase { true } else { false } }
        if traded {
            check("table: given squeeshy left the collection", isGone(givingID, context))
            check("table: received squeeshy filed", all(context).contains { $0.lineageID.uuidString == receivingID })
        }
        session.end()

        // Changing the table clears votes.
        session = TradeTableSession()
        session.begin(displayName: store.displayName, userID: store.myUserID, context: context)
        await waitFor("partner nearby again") { !session.nearby.isEmpty }
        session.simulated?.autoYes = false
        session.open(with: session.nearby[0])
        await waitFor("table opens again") { if case .atTable = session.phase { true } else { false } }
        session.simulated?.putInRandom()
        session.toggle(held(context)[0])
        await waitFor("both sides filled") { session.bothSidesFilled }
        session.vote(true)
        session.simulated?.vote(true)
        try? await Task.sleep(for: .seconds(0.1))
        session.simulated?.putInRandom()
        await waitFor("partner's change clears my yes") { session.theirs.count == 2 && session.myCurrentVote == nil }
        check("no trade after the table changed", { if case .traded = session.phase { false } else { true } }())

        // Partner walks away.
        session.debugSimulatedLeaves()
        check("partner leaving closes the table", { if case .ended = session.phase { true } else { false } }())
        session.end()

        // They invite me.
        session = TradeTableSession()
        session.begin(displayName: store.displayName, userID: store.myUserID, context: context)
        await waitFor("partner nearby for invite") { !session.nearby.isEmpty }
        session.debugSimulatedInvite()
        check("invitation shows", session.invitation != nil)
        session.answerInvitation(true)
        await waitFor("joining an invitation opens the table") { if case .atTable = session.phase { true } else { false } }
        session.end()
        check("ending returns to idle", session.phase == .idle)
    }

    // MARK: Helpers

    private static func all(_ context: ModelContext) -> [Squishy] {
        (try? context.fetch(FetchDescriptor<Squishy>(sortBy: [SortDescriptor(\.addedAt)]))) ?? []
    }

    /// Squeeshies photographed here, as opposed to ones received by trade.
    private static func held(_ context: ModelContext) -> [Squishy] {
        all(context).filter { $0.acquiredFrom == nil }
    }

    private static func isGone(_ lineageID: String, _ context: ModelContext) -> Bool {
        !all(context).contains { $0.lineageID.uuidString == lineageID }
    }

    @discardableResult
    private static func waitFor(_ name: String, timeout: Double = 8, _ condition: () -> Bool) async -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { check(name, true); return true }
            try? await Task.sleep(for: .milliseconds(150))
        }
        check(name, false)
        return false
    }

    private static func check(_ name: String, _ ok: Bool) {
        if ok { passed += 1 } else { failed += 1 }
        log("\(ok ? "PASS" : "FAIL")  \(name)")
    }

    private static func log(_ line: String) {
        print("[SelfTest] \(line)")
    }
}
#endif
