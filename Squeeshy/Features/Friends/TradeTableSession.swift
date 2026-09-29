import CryptoKit
import Foundation
import MultipeerConnectivity
import Observation
import SwiftData
import SwiftUI
import UIKit

/// The in-person trade table. Two devices near each other connect directly
/// (Wi-Fi / Bluetooth, no internet), each puts squishies on the table, and each
/// votes. It trades only when both vote yes on the *same* table.
///
/// Rules the protocol enforces rather than trusts:
/// - A vote is tied to a `tableKey` naming exactly what is on both sides.
///   Changing anything changes the key, so both votes clear on their own and a
///   yes can never carry over to a different squishy.
/// - After two yeses, each side sends its specimens and acknowledges the
///   other's. A device files the swap only when it has *their* specimens and
///   they have confirmed receiving *its* — so a dropped connection mid-swap
///   leaves both catalogues untouched rather than one of them half-done.
@MainActor
@Observable
final class TradeTableSession: NSObject {

    struct NearbyPeer: Identifiable, Hashable {
        let peer: MCPeerID
        let isFriend: Bool
        var id: MCPeerID { peer }
        var name: String { peer.displayName }
    }

    struct TableItem: Codable, Identifiable, Hashable {
        var id: String
        var name: String
        var squeeshiness: Double
        var hue: Double
        var speciesRaw: String
        var thumbnail: Data?

        var image: UIImage? { thumbnail.flatMap(UIImage.init(data:)) }
        var species: Species { Species(rawValue: speciesRaw) ?? .round }
        var color: Color { Hue.color(hue) }
    }

    enum Phase: Equatable {
        case idle
        case looking
        case connecting(String)
        case atTable(String)
        case traded(received: [String])
        case ended(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var nearby: [NearbyPeer] = []
    /// Someone asked to open a table with this device.
    private(set) var invitation: NearbyPeer? = nil

    private(set) var mine: [TableItem] = []
    private(set) var theirs: [TableItem] = []
    private var myVote: (key: String, yes: Bool)? = nil
    private var theirVote: (key: String, yes: Bool)? = nil

    private var theirPayload: (key: String, payloads: [SpecimenPayload])? = nil
    private var theyReceivedKey: String? = nil
    private var sentPayloadKey: String? = nil

    private var myPeer: MCPeerID? = nil
    private var session: MCSession? = nil
    private var advertiser: MCNearbyServiceAdvertiser? = nil
    private var browser: MCNearbyServiceBrowser? = nil
    private var invitationHandler: ((Bool, MCSession?) -> Void)? = nil
    private var connectedPeer: MCPeerID? = nil
    private var modelContext: ModelContext? = nil

    #if DEBUG
    /// Debug builds: a pretend second phone, when `FriendsDebug.isOn`.
    private(set) var simulated: SimulatedTablePartner? = nil
    #endif

    static let serviceType = "squish-table"

    /// MultipeerConnectivity rejects a display name over 63 UTF-8 bytes with an
    /// exception, and a short name with emoji can pass a character limit and
    /// still be too long.
    static func peerName(_ name: String) -> String {
        var trimmed = String(name.prefix(40))
        while trimmed.utf8.count > 63 { trimmed.removeLast() }
        return trimmed.isEmpty ? "Squeeshy" : trimmed
    }

    nonisolated static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Derived

    var partnerName: String { connectedPeer?.displayName ?? "Friend" }

    /// Names both sides of the table, identically on both devices.
    var tableKey: String {
        let a = mine.map(\.id).sorted().joined(separator: ",")
        let b = theirs.map(\.id).sorted().joined(separator: ",")
        return [a, b].sorted().joined(separator: "#")
    }

    var bothSidesFilled: Bool { !mine.isEmpty && !theirs.isEmpty }

    /// Both said yes to this table: the swap is under way.
    var isSwapping: Bool { myCurrentVote == true && theirCurrentVote == true }

    // MARK: A "no"

    /// Someone said no. It stays set while the table plays the rejection, then
    /// the board is wiped and it clears. The view animates off its `id`.
    struct Rejection: Equatable {
        enum Reason: Equatable {
            case me, partner
            /// Something on this side left the collection before it could be sent.
            case itemLeft
        }

        let id = UUID()
        let reason: Reason

        var byMe: Bool { reason == .me }
    }

    private(set) var rejection: Rejection? = nil
    /// What each side held when the no landed. The wipe only clears a side that
    /// still holds exactly that, so a squeeshy put in *during* the animation stays.
    private var rejectedSides: (mine: Set<String>, theirs: Set<String>)? = nil

    /// Long enough for the stamp, the shake and the sweep to play out.
    static let wipeDelay: Duration = .seconds(1.7)

    private func noticeRejection(_ reason: Rejection.Reason) {
        // Only an open table can be rejected. A late or stale no after the trade
        // was filed must not wipe what the celebration is showing.
        guard case .atTable = phase, rejection == nil else { return }
        let current = Rejection(reason: reason)
        rejection = current
        rejectedSides = (Set(mine.map(\.id)), Set(theirs.map(\.id)))
        Task {
            try? await Task.sleep(for: Self.wipeDelay)
            guard rejection?.id == current.id else { return }
            wipeAfterRejection()
        }
    }

    /// Each device empties its own side and says so, so both boards end clean
    /// whichever phone said no. The other side is cleared locally too, when it is
    /// unchanged, so it doesn't flash back while the partner's update is in flight.
    private func wipeAfterRejection() {
        guard case .atTable = phase else {
            rejectedSides = nil
            rejection = nil
            return
        }
        if let sides = rejectedSides {
            if Set(mine.map(\.id)) == sides.mine {
                mine = []
                send(.table([]))
            }
            if Set(theirs.map(\.id)) == sides.theirs {
                theirs = []
            }
        }
        myVote = nil
        theirVote = nil
        // Anything a half-started exchange left behind goes too, so the same
        // squeeshies put back later start a fresh exchange.
        theirPayload = nil
        theyReceivedKey = nil
        sentPayloadKey = nil
        rejectedSides = nil
        rejection = nil
    }

    /// `nil` = not voted on this table.
    var myCurrentVote: Bool? { myVote?.key == tableKey ? myVote?.yes : nil }
    var theirCurrentVote: Bool? { theirVote?.key == tableKey ? theirVote?.yes : nil }

    var statusLine: String {
        if let rejection {
            switch rejection.reason {
            case .me: return "You said no · clearing the table"
            case .partner: return "\(partnerName) said no · clearing the table"
            case .itemLeft: return "One of yours left your collection · clearing the table"
            }
        }
        if mine.isEmpty { return "Put something on the table" }
        if theirs.isEmpty { return "Waiting for \(partnerName) to put one in" }
        if myCurrentVote == false || theirCurrentVote == false {
            return "Someone said no · change what's on the table to try again"
        }
        if myCurrentVote == nil { return "Both sides ready · vote" }
        if theirCurrentVote == nil { return "Waiting for \(partnerName) to vote" }
        return "Both said yes · swapping"
    }

    // MARK: Lifecycle

    func begin(displayName: String, userID: String?, context: ModelContext) {
        guard phase == .idle || isEnded else { return }
        reset()
        modelContext = context
        let name = displayName.isEmpty ? UIDevice.current.name : displayName
        let peer = MCPeerID(displayName: Self.peerName(name))
        myPeer = peer

        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        // A digest, not the iCloud user record name itself: enough for a friend's
        // device to recognise this one, and nothing for anyone else nearby.
        let info = userID.map { ["uid": Self.digest($0)] }
        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: info, serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser

        phase = .looking
        #if DEBUG
        startSimulatedPartner()
        #endif
    }

    func end() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        invitationHandler?(false, nil)
        reset()
        phase = .idle
    }

    private var isEnded: Bool {
        if case .ended = phase { return true }
        if case .traded = phase { return true }
        return false
    }

    private func reset() {
        advertiser = nil
        browser = nil
        session = nil
        invitationHandler = nil
        invitation = nil
        connectedPeer = nil
        #if DEBUG
        simulated = nil
        #endif
        nearby = []
        mine = []
        theirs = []
        myVote = nil
        theirVote = nil
        theirPayload = nil
        theyReceivedKey = nil
        sentPayloadKey = nil
        rejection = nil
        rejectedSides = nil
    }

    // MARK: Connecting

    func open(with peer: NearbyPeer) {
        #if DEBUG
        if let simulated, peer.peer == simulated.peer {
            phase = .connecting(peer.name)
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                guard self.simulated === simulated, case .connecting = self.phase else { return }
                self.peerChanged(peer.peer, to: .connected)
            }
            return
        }
        #endif
        guard let session else { return }
        browser?.invitePeer(peer.peer, to: session, withContext: nil, timeout: 30)
        phase = .connecting(peer.name)
    }

    func answerInvitation(_ join: Bool) {
        guard let handler = invitationHandler else { return }
        handler(join, join ? session : nil)
        if join, let invitation { phase = .connecting(invitation.name) }
        invitationHandler = nil
        invitation = nil
    }

    // MARK: The table

    /// False while a swap is being exchanged or a no is playing out. Changing the
    /// table mid-exchange could let one phone finish the trade while the other
    /// doesn't, so it is locked until the outcome settles.
    var canChangeTable: Bool { !isSwapping && rejection == nil }

    /// Adds or removes one of this user's squeeshies. Any change voids both votes
    /// because the table key changes.
    func toggle(_ specimen: Squishy) {
        guard canChangeTable else { return }
        let id = specimen.lineageID.uuidString
        if let index = mine.firstIndex(where: { $0.id == id }) {
            mine.remove(at: index)
        } else {
            mine.append(TableItem(id: id, name: specimen.name, squeeshiness: specimen.squeeshiness,
                                  hue: specimen.hue, speciesRaw: specimen.speciesRaw,
                                  thumbnail: specimen.shelfThumbnail()))
        }
        send(.table(mine))
    }

    /// Takes one of this user's squeeshies off the table by ID — used from the
    /// expanded view, which lists table items rather than collection rows.
    func remove(itemID: String) {
        guard canChangeTable, let index = mine.firstIndex(where: { $0.id == itemID }) else { return }
        mine.remove(at: index)
        send(.table(mine))
    }

    func contains(_ specimen: Squishy) -> Bool {
        mine.contains { $0.id == specimen.lineageID.uuidString }
    }

    func vote(_ yes: Bool) {
        guard bothSidesFilled, rejection == nil, !isSwapping else { return }
        myVote = (tableKey, yes)
        send(.vote(key: tableKey, yes: yes))
        if yes {
            advanceIfAgreed()
        } else {
            noticeRejection(.me)
        }
    }

    private func advanceIfAgreed() {
        let key = tableKey
        guard myCurrentVote == true, theirCurrentVote == true, sentPayloadKey != key,
              let modelContext else { return }
        let specimens = TradeLedger.held(mine.map(\.id), in: modelContext)
        guard specimens.count == mine.count else {
            // Something on the table left the collection in the meantime: say no
            // on this side's behalf, which wipes the table for a fresh start.
            // Not through `vote(_:)`, which refuses once both have said yes.
            myVote = (key, false)
            send(.vote(key: key, yes: false))
            noticeRejection(.itemLeft)
            return
        }
        sentPayloadKey = key
        send(.payload(key: key, specimens: specimens.map(SpecimenPayload.init)))
        finishIfBothReceived()
    }

    private func finishIfBothReceived() {
        let key = tableKey
        guard let theirPayload, theirPayload.key == key,
              theyReceivedKey == key, sentPayloadKey == key,
              let modelContext else { return }
        let received = theirPayload.payloads
        let giving = mine.map(\.id)
        let partner = partnerName
        self.theirPayload = nil
        Task {
            TradeLedger.complete(receiving: received, from: partner,
                                       giving: giving, to: partner, in: modelContext)
            FriendsStore.shared.schedulePublish()
            phase = .traded(received: received.map(\.name))
            // Let the last acknowledgement reach the other device before the
            // link drops.
            try? await Task.sleep(for: .seconds(1.5))
            session?.disconnect()
        }
    }

    // MARK: Wire format

    private enum Message: Codable {
        case table([TableItem])
        case vote(key: String, yes: Bool)
        case payload(key: String, specimens: [SpecimenPayload])
        case received(key: String)
    }

    private func send(_ message: Message) {
        #if DEBUG
        if let simulated, connectedPeer == simulated.peer {
            deliverToSimulated(message, simulated)
            return
        }
        #endif
        guard let session, !session.connectedPeers.isEmpty,
              let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    private func handle(_ message: Message) {
        switch message {
        case .table(let items):
            theirs = items
        case .vote(let key, let yes):
            theirVote = (key, yes)
            if !yes && key == tableKey {
                noticeRejection(.partner)
            } else {
                advanceIfAgreed()
            }
        case .payload(let key, let specimens):
            // Only accept exactly what was on their side of this table.
            let expected = Set(theirs.map(\.id))
            let got = Set(specimens.map(\.lineageID.uuidString))
            guard key == tableKey, expected == got else { return }
            theirPayload = (key, specimens)
            send(.received(key: key))
            finishIfBothReceived()
        case .received(let key):
            theyReceivedKey = key
            finishIfBothReceived()
        }
    }

    private func peerChanged(_ peer: MCPeerID, to state: MCSessionState) {
        switch state {
        case .connected:
            connectedPeer = peer
            advertiser?.stopAdvertisingPeer()
            browser?.stopBrowsingForPeers()
            phase = .atTable(peer.displayName)
            send(.table(mine))
        case .notConnected:
            guard peer == connectedPeer || connectedPeer == nil else { return }
            switch phase {
            case .traded, .idle, .ended:
                return
            case .looking:
                // A peer that never connected — nothing to close.
                return
            case .connecting, .atTable:
                break
            }
            let name = peer.displayName
            let wasAtTable = connectedPeer != nil
            connectedPeer = nil
            theirs = []
            theirVote = nil
            phase = .ended(wasAtTable ? "\(name) left the table. Nothing was traded."
                                      : "\(name) didn't join. Nothing was traded.")
        case .connecting:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - MultipeerConnectivity delegates

extension TradeTableSession: MCSessionDelegate {
    // Callbacks from a session this table already closed (after Leave or
    // Look again) are dropped, so they can't end or feed the new table.
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            guard session === self.session else { return }
            self.peerChanged(peerID, to: state)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(Message.self, from: data) else { return }
        Task { @MainActor in
            guard session === self.session, peerID == self.connectedPeer else { return }
            self.handle(message)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream,
                             withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension TradeTableSession: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            // One table at a time: a second invitation is declined silently.
            guard self.invitationHandler == nil, self.connectedPeer == nil else {
                invitationHandler(false, nil)
                return
            }
            let isFriend = self.nearby.first { $0.peer == peerID }?.isFriend ?? false
            self.invitationHandler = invitationHandler
            self.invitation = NearbyPeer(peer: peerID, isFriend: isFriend)
        }
    }
}

extension TradeTableSession: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        let uid = info?["uid"]
        Task { @MainActor in
            guard peerID != self.myPeer, !self.nearby.contains(where: { $0.peer == peerID }) else { return }
            let isFriend = uid.map { id in
                FriendsStore.shared.friends.contains { TradeTableSession.digest($0.id) == id }
            } ?? false
            self.nearby.append(NearbyPeer(peer: peerID, isFriend: isFriend))
            // Friends first, then everyone else.
            self.nearby.sort { ($0.isFriend ? 0 : 1, $0.name) < ($1.isFriend ? 0 : 1, $1.name) }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.nearby.removeAll { $0.peer == peerID } }
    }
}

// MARK: - Debug simulation

#if DEBUG
extension TradeTableSession {
    fileprivate func startSimulatedPartner() {
        guard FriendsDebug.isOn, let simulator = FriendsStore.shared.simulator,
              let friend = simulator.friends.first else { return }
        let partner = SimulatedTablePartner(friendID: friend.id, name: friend.name)
        partner.deliver = { [weak self, weak partner] message in
            partner?.inbound.post {
                guard let self, let partner, self.simulated === partner,
                      self.connectedPeer == partner.peer else { return }
                self.handle(Self.convert(message))
            }
        }
        simulated = partner
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard self.simulated === partner, self.phase == .looking else { return }
            self.nearby.insert(NearbyPeer(peer: partner.peer, isFriend: true), at: 0)
        }
    }

    private func deliverToSimulated(_ message: Message, _ partner: SimulatedTablePartner) {
        let converted: SimulatedTablePartner.Message = switch message {
        case .table(let items): .table(items)
        case .vote(let key, let yes): .vote(key: key, yes: yes)
        case .payload(let key, let specimens): .payload(key: key, specimens: specimens)
        case .received(let key): .received(key: key)
        }
        partner.outbound.post { [weak self] in
            guard self?.simulated === partner else { return }
            partner.receive(converted)
        }
    }

    private static func convert(_ message: SimulatedTablePartner.Message) -> Message {
        switch message {
        case .table(let items): .table(items)
        case .vote(let key, let yes): .vote(key: key, yes: yes)
        case .payload(let key, let specimens): .payload(key: key, specimens: specimens)
        case .received(let key): .received(key: key)
        }
    }

    /// The simulated friend taps "Open table" on their phone.
    func debugSimulatedInvite() {
        guard let partner = simulated, phase == .looking, invitationHandler == nil else { return }
        invitationHandler = { [weak self] join, _ in
            guard join else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.6))
                guard let self, self.simulated === partner else { return }
                self.peerChanged(partner.peer, to: .connected)
            }
        }
        invitation = NearbyPeer(peer: partner.peer, isFriend: true)
    }

    /// The simulated friend walks away mid-table.
    func debugSimulatedLeaves() {
        guard let partner = simulated, connectedPeer == partner.peer else { return }
        peerChanged(partner.peer, to: .notConnected)
    }
}
#endif
