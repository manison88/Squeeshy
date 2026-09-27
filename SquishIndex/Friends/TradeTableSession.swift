import Foundation
import MultipeerConnectivity
import Observation
import SwiftData
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
        var squishLevel: Int
        var thumbnail: Data?

        var image: UIImage? { thumbnail.flatMap(UIImage.init(data:)) }
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

    static let serviceType = "squish-table"

    // MARK: Derived

    var partnerName: String { connectedPeer?.displayName ?? "Friend" }

    /// Names both sides of the table, identically on both devices.
    var tableKey: String {
        let a = mine.map(\.id).sorted().joined(separator: ",")
        let b = theirs.map(\.id).sorted().joined(separator: ",")
        return [a, b].sorted().joined(separator: "#")
    }

    var bothSidesFilled: Bool { !mine.isEmpty && !theirs.isEmpty }

    /// `nil` = not voted on this table.
    var myCurrentVote: Bool? { myVote?.key == tableKey ? myVote?.yes : nil }
    var theirCurrentVote: Bool? { theirVote?.key == tableKey ? theirVote?.yes : nil }

    var statusLine: String {
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
        let peer = MCPeerID(displayName: String(name.prefix(40)))
        myPeer = peer

        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let info = userID.map { ["uid": $0] }
        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: info, serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser

        phase = .looking
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
        nearby = []
        mine = []
        theirs = []
        myVote = nil
        theirVote = nil
        theirPayload = nil
        theyReceivedKey = nil
        sentPayloadKey = nil
    }

    // MARK: Connecting

    func open(with peer: NearbyPeer) {
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

    /// Adds or removes one of this user's specimens. Any change voids both votes
    /// because the table key changes.
    func toggle(_ specimen: Squishy) {
        let id = specimen.lineageID.uuidString
        if let index = mine.firstIndex(where: { $0.id == id }) {
            mine.remove(at: index)
        } else {
            mine.append(TableItem(id: id, name: specimen.name, squishLevel: specimen.squishLevel,
                                  thumbnail: specimen.shelfThumbnail()))
        }
        send(.table(mine))
    }

    func contains(_ specimen: Squishy) -> Bool {
        mine.contains { $0.id == specimen.lineageID.uuidString }
    }

    func vote(_ yes: Bool) {
        guard bothSidesFilled else { return }
        myVote = (tableKey, yes)
        send(.vote(key: tableKey, yes: yes))
        advanceIfAgreed()
    }

    private func advanceIfAgreed() {
        let key = tableKey
        guard myCurrentVote == true, theirCurrentVote == true, sentPayloadKey != key,
              let modelContext else { return }
        let specimens = TradeLedger.held(mine.map(\.id), in: modelContext)
        guard specimens.count == mine.count else {
            // Something on the table left the shelf in the meantime; start over.
            vote(false)
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
            await TradeLedger.complete(receiving: received, from: partner,
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
            advanceIfAgreed()
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
            if case .traded = phase { return }
            let name = peer.displayName
            connectedPeer = nil
            theirs = []
            theirVote = nil
            phase = .ended("\(name) left the table. Nothing was traded.")
        case .connecting:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - MultipeerConnectivity delegates

extension TradeTableSession: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in self.peerChanged(peerID, to: state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(Message.self, from: data) else { return }
        Task { @MainActor in self.handle(message) }
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
            let isFriend = uid.map { id in FriendsStore.shared.friends.contains { $0.id == id } } ?? false
            self.nearby.append(NearbyPeer(peer: peerID, isFriend: isFriend))
            // Friends first, then everyone else.
            self.nearby.sort { ($0.isFriend ? 0 : 1, $0.name) < ($1.isFriend ? 0 : 1, $1.name) }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.nearby.removeAll { $0.peer == peerID } }
    }
}
