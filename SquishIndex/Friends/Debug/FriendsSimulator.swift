#if DEBUG
import Foundation
import MultipeerConnectivity
import SwiftData
import UIKit

/// Debug builds only. Stands in for iCloud and for a second phone so friends,
/// remote trades and the trade table can be exercised on one simulator.
///
/// Turn on with the Debug panel on the Friends screen, or launch with
/// `-SimulateFriends YES`. The simulated friends only ever touch this store's
/// in-memory state and the local catalogue; nothing goes to CloudKit.
enum FriendsDebug {
    static let key = "SimulateFriends"

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// The other side of every simulated friendship: their shelves, the requests
/// they send, the replies they write, and how they behave.
@MainActor
@Observable
final class FriendsSimulator {

    enum ReplyBehaviour: String, CaseIterable, Identifiable {
        case accept = "Accept"
        case decline = "Decline"
        case ignore = "Ignore"
        var id: String { rawValue }
    }

    /// How a simulated friend answers a request from this user.
    var replyBehaviour: ReplyBehaviour = .accept
    /// Whether a simulated friend ticks "handed over" on their own.
    var autoHandOver = true
    /// Seconds before a simulated friend reacts to anything.
    var delay: Double = 1.5

    private(set) var shelves: [String: (name: String, items: [SpecimenPayload])] = [:]
    private(set) var order: [String] = []
    private(set) var requests: [TradeRequest] = []
    private(set) var replies: [TradeReply] = []
    private(set) var log: [String] = []

    /// What each side put up, by request ID.
    private var myPayloads: [UUID: [SpecimenPayload]] = [:]
    private var theirPayloads: [UUID: [SpecimenPayload]] = [:]
    private var settled: Set<UUID> = []

    init() {
        pairFriend(named: "Mia")
    }

    // MARK: Friends

    var friends: [Friend] {
        order.compactMap { id in
            guard let shelf = shelves[id] else { return nil }
            return Friend(id: id, name: shelf.name, updatedAt: .now,
                          items: shelf.items.map(Self.item).sorted { $0.addedAt > $1.addedAt })
        }
    }

    @discardableResult
    func pairFriend(named name: String? = nil) -> Friend {
        let names = ["Mia", "Leo", "Zara", "Theo", "Ivy", "Sam", "Noor", "Kai"]
        let used = Set(shelves.values.map(\.name))
        let name = name ?? names.first { !used.contains($0) } ?? "Friend \(order.count + 1)"
        let id = "sim-" + UUID().uuidString.prefix(8)
        shelves[id] = (name, (0..<6).map { _ in Self.makePayload(owner: name) })
        order.append(id)
        note("Paired with \(name)")
        return friends.first { $0.id == id }!
    }

    func unpair(_ id: String) {
        guard let name = shelves[id]?.name else { return }
        shelves[id] = nil
        order.removeAll { $0 == id }
        note("\(name) removed")
    }

    // MARK: Trades — this user's side, mirrored in

    func recordSent(_ request: TradeRequest, payloads: [SpecimenPayload]) {
        myPayloads[request.id] = payloads
        note("Sent request to \(request.toName)")
    }

    func recordReply(_ reply: TradeReply, payloads: [SpecimenPayload]) {
        if reply.accepted { myPayloads[reply.requestID] = payloads }
        note(reply.accepted ? "You accepted" : "You declined")
    }

    /// The payload the *friend* put up for a trade, as the store would fetch
    /// it from their zone.
    func payload(for requestID: UUID) -> [SpecimenPayload] {
        theirPayloads[requestID] ?? []
    }

    // MARK: Trades — the friend's side

    /// A simulated friend asks for one of this user's open squishies.
    func sendIncomingRequest(to myID: String, myName: String, from friendID: String? = nil,
                             context: ModelContext) -> String? {
        guard let friendID = friendID ?? order.first, let shelf = shelves[friendID] else {
            return "Pair a friend first."
        }
        let mine = ((try? context.fetch(FetchDescriptor<Squishy>())) ?? [])
            .filter { !$0.isTraded && !$0.isKeeping }
        guard let wanted = mine.randomElement() else { return "Nothing on your shelf is open to trade. Seed some first." }
        guard let offered = shelf.items.randomElement() else { return "\(shelf.name)'s shelf is empty." }
        let request = TradeRequest(
            id: UUID(), fromID: friendID, fromName: shelf.name,
            toID: myID, toName: myName.isEmpty ? "You" : myName,
            offered: [TradeLine(id: offered.lineageID.uuidString, name: offered.name, squishLevel: offered.squishLevel)],
            wanted: [TradeLine(id: wanted.lineageID.uuidString, name: wanted.name, squishLevel: wanted.squishLevel)],
            line: TradePreset.allCases.randomElement()?.rawValue,
            createdAt: .now, handedOver: false, cancelled: false)
        requests.append(request)
        theirPayloads[request.id] = [offered]
        note("\(shelf.name) asked for \(wanted.name)")
        return nil
    }

    func cancelIncoming(_ requestID: UUID) {
        guard let index = requests.firstIndex(where: { $0.id == requestID }) else { return }
        requests[index].cancelled = true
        note("\(requests[index].fromName) cancelled their request")
    }

    /// Everything a friend would do on their own device since last time.
    /// Returns true if anything changed.
    @discardableResult
    func tick(myRequests: [TradeRequest], myReplies: [TradeReply], force: Bool = false) -> Bool {
        var changed = false
        let now = Date.now

        // Answer this user's requests.
        for request in myRequests where shelves[request.toID] != nil && !request.cancelled {
            guard !replies.contains(where: { $0.requestID == request.id }) else { continue }
            guard force || now.timeIntervalSince(request.createdAt) >= delay else { continue }
            let behaviour = force && replyBehaviour == .ignore ? .accept : replyBehaviour
            guard behaviour != .ignore else { continue }
            let shelf = shelves[request.toID]!
            let giving = request.wanted.compactMap { line in shelf.items.first { $0.lineageID.uuidString == line.id } }
            let accept = behaviour == .accept && giving.count == request.wanted.count
            if accept { theirPayloads[request.id] = giving }
            replies.append(TradeReply(requestID: request.id, fromID: request.toID, toID: request.fromID,
                                      accepted: accept, handedOver: false, repliedAt: now))
            note("\(shelf.name) \(accept ? "accepted" : "declined") your request")
            changed = true
        }

        guard autoHandOver || force else { return changed }

        // Hand over once this user has accepted (incoming) or once the friend
        // has accepted (outgoing).
        for index in replies.indices where replies[index].accepted && !replies[index].handedOver {
            guard let request = myRequests.first(where: { $0.id == replies[index].requestID }),
                  !request.cancelled else { continue }
            replies[index].handedOver = true
            note("\(shelves[replies[index].fromID]?.name ?? "Friend") handed theirs over")
            changed = true
        }
        for index in requests.indices where !requests[index].handedOver && !requests[index].cancelled {
            guard myReplies.contains(where: { $0.requestID == requests[index].id && $0.accepted }) else { continue }
            requests[index].handedOver = true
            note("\(requests[index].fromName) handed theirs over")
            changed = true
        }
        changed = settle(myRequests: myRequests, myReplies: myReplies) || changed
        return changed
    }

    /// The friend's device files the swap once both sides handed over.
    private func settle(myRequests: [TradeRequest], myReplies: [TradeReply]) -> Bool {
        var changed = false
        let outgoing = myRequests.compactMap { request -> (UUID, String)? in
            guard let reply = replies.first(where: { $0.requestID == request.id }),
                  reply.accepted, reply.handedOver, request.handedOver else { return nil }
            return (request.id, request.toID)
        }
        let incoming = requests.compactMap { request -> (UUID, String)? in
            guard let reply = myReplies.first(where: { $0.requestID == request.id }),
                  reply.accepted, reply.handedOver, request.handedOver else { return nil }
            return (request.id, request.fromID)
        }
        for (id, friendID) in outgoing + incoming where !settled.contains(id) {
            guard var shelf = shelves[friendID] else { continue }
            let gone = Set((theirPayloads[id] ?? []).map(\.lineageID))
            shelf.items.removeAll { gone.contains($0.lineageID) }
            shelf.items += (myPayloads[id] ?? []).map { payload in
                var payload = payload
                payload.ownerSince = .now
                return payload
            }
            shelves[friendID] = shelf
            settled.insert(id)
            note("\(shelf.name) filed the swap")
            changed = true
        }
        return changed
    }

    // MARK: Trade table

    /// Filed on the partner's side when a table trade finishes.
    func settleTable(friendID: String, gave: [SpecimenPayload], got: [SpecimenPayload]) {
        guard var shelf = shelves[friendID] else { return }
        let gone = Set(gave.map(\.lineageID))
        shelf.items.removeAll { gone.contains($0.lineageID) }
        shelf.items += got
        shelves[friendID] = shelf
        note("\(shelf.name) filed the table swap")
    }

    func shelf(_ friendID: String) -> [SpecimenPayload] { shelves[friendID]?.items ?? [] }
    func name(_ friendID: String) -> String { shelves[friendID]?.name ?? "Friend" }

    // MARK: Log

    func note(_ line: String) {
        let time = Date.now.formatted(date: .omitted, time: .standard)
        log.insert("\(time)  \(line)", at: 0)
        if log.count > 40 { log.removeLast() }
    }

    // MARK: Fixtures

    private static let names = ["Mochi Bun", "Peach Puff", "Cloud Cat", "Toast Buddy", "Jelly Bean",
                                "Dumpling", "Frog Loaf", "Moon Cake", "Boba Bear", "Pudding Pup",
                                "Squid Kid", "Taffy", "Marshmallow Moo", "Berry Blob"]
    private static let colours: [(String, UIColor)] = [
        ("#F4A6B8", UIColor(red: 0.96, green: 0.65, blue: 0.72, alpha: 1)),
        ("#F6C667", UIColor(red: 0.96, green: 0.78, blue: 0.40, alpha: 1)),
        ("#9ED9C4", UIColor(red: 0.62, green: 0.85, blue: 0.77, alpha: 1)),
        ("#A7C4F2", UIColor(red: 0.65, green: 0.77, blue: 0.95, alpha: 1)),
        ("#C9B2EB", UIColor(red: 0.79, green: 0.70, blue: 0.92, alpha: 1)),
        ("#F29E6D", UIColor(red: 0.95, green: 0.62, blue: 0.43, alpha: 1)),
    ]

    static func makePayload(owner: String) -> SpecimenPayload {
        let colour = colours.randomElement()!
        let form = [SpecimenForm.round, .oval, .tall, .wide, .lobed].randomElement()!
        let width = Double.random(in: 50...140)
        return SpecimenPayload(
            lineageID: UUID(),
            name: names.randomElement()!,
            squishLevel: Int.random(in: 1...10),
            photo: photo(colour.1, form: form),
            widthMM: width,
            heightMM: width * Double.random(in: 0.7...1.3),
            measurementMethod: [MeasurementMethod.lidar, .depth, .card].randomElement()!.rawValue,
            confidence: 0.8,
            dominantHue: 0, dominantSaturation: 0.5, dominantBrightness: 0.9,
            paletteHex: [colour.0, "#FFFFFF", "#3A2E2A"],
            paletteProportions: [0.7, 0.2, 0.1],
            form: form.rawValue,
            type: nil, subject: nil, material: nil, surface: nil,
            tags: [],
            provenance: [],
            ownerSince: Date.now.addingTimeInterval(-Double.random(in: 86_400...8_000_000)))
    }

    /// A plain drawn squishy: a blob with a face, on a pale plate.
    static func photo(_ colour: UIColor, form: SpecimenForm) -> Data {
        let size = CGSize(width: 600, height: 600)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: 0.97, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let body: CGRect = switch form {
            case .tall: CGRect(x: 190, y: 90, width: 220, height: 420)
            case .wide: CGRect(x: 70, y: 190, width: 460, height: 240)
            case .oval: CGRect(x: 110, y: 150, width: 380, height: 300)
            default: CGRect(x: 120, y: 120, width: 360, height: 360)
            }
            UIColor(white: 0, alpha: 0.08).setFill()
            UIBezierPath(ovalIn: CGRect(x: body.minX + 20, y: body.maxY - 10, width: body.width - 40, height: 30)).fill()
            colour.setFill()
            UIBezierPath(roundedRect: body, cornerRadius: min(body.width, body.height) * 0.45).fill()
            UIColor(white: 1, alpha: 0.35).setFill()
            UIBezierPath(ovalIn: CGRect(x: body.minX + body.width * 0.18, y: body.minY + body.height * 0.12,
                                        width: body.width * 0.22, height: body.height * 0.12)).fill()
            UIColor(red: 0.23, green: 0.18, blue: 0.16, alpha: 1).setFill()
            let eyeY = body.midY - 10
            UIBezierPath(ovalIn: CGRect(x: body.midX - 50, y: eyeY, width: 18, height: 22)).fill()
            UIBezierPath(ovalIn: CGRect(x: body.midX + 32, y: eyeY, width: 18, height: 22)).fill()
            let mouth = UIBezierPath()
            mouth.move(to: CGPoint(x: body.midX - 14, y: eyeY + 34))
            mouth.addQuadCurve(to: CGPoint(x: body.midX + 14, y: eyeY + 34), controlPoint: CGPoint(x: body.midX, y: eyeY + 48))
            mouth.lineWidth = 5
            UIColor(red: 0.23, green: 0.18, blue: 0.16, alpha: 1).setStroke()
            mouth.stroke()
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }

    /// Adds sample squishies to this user's own catalogue — the simulator has
    /// no camera to capture real ones.
    static func seedMyShelf(count: Int, in context: ModelContext) {
        for _ in 0..<count {
            let p = makePayload(owner: "me")
            context.insert(Squishy(name: p.name, squishLevel: p.squishLevel, photo: p.photo,
                                   featurePrint: Data(), widthMM: p.widthMM, heightMM: p.heightMM,
                                   measurementMethod: p.measurementMethod, confidence: p.confidence,
                                   paletteHex: p.paletteHex, paletteProportions: p.paletteProportions,
                                   form: p.form))
        }
        try? context.save()
    }

    static func item(_ payload: SpecimenPayload) -> FriendItem {
        FriendItem(id: payload.lineageID.uuidString, name: payload.name, squishLevel: payload.squishLevel,
                   widthMM: payload.widthMM, heightMM: payload.heightMM,
                   measurementMethod: payload.measurementMethod,
                   paletteHex: payload.paletteHex, paletteProportions: payload.paletteProportions,
                   form: payload.form, isKeeping: false, addedAt: payload.ownerSince,
                   thumbnail: UIImage(data: payload.photo)?.preparingThumbnail(of: CGSize(width: 240, height: 240))?
                    .jpegData(compressionQuality: 0.7))
    }
}

// MARK: - Simulated trade-table partner

/// Delivers messages one at a time, in order, after a short hop — like
/// MultipeerConnectivity's `.reliable` mode.
@MainActor
final class SimulatedLink {
    private var last: Task<Void, Never>?

    func post(_ work: @escaping @MainActor () -> Void) {
        let previous = last
        last = Task { @MainActor in
            await previous?.value
            try? await Task.sleep(for: .seconds(0.35))
            work()
        }
    }
}

/// A second device at the trade table. It speaks the same wire messages as a
/// real peer and keeps its own view of the table, so the session's protocol
/// (table key, votes, two-phase exchange) is exercised as written.
@MainActor
@Observable
final class SimulatedTablePartner {
    enum Message {
        case table([TradeTableSession.TableItem])
        case vote(key: String, yes: Bool)
        case payload(key: String, specimens: [SpecimenPayload])
        case received(key: String)
    }

    let friendID: String
    let peer: MCPeerID
    /// Partner → this device, and this device → partner.
    let inbound = SimulatedLink()
    let outbound = SimulatedLink()
    /// Votes yes as soon as this user does.
    var autoYes = true

    private(set) var mine: [SpecimenPayload] = []
    private var theirs: [TradeTableSession.TableItem] = []
    private var myVote: (key: String, yes: Bool)?
    private var theirVote: (key: String, yes: Bool)?
    private var sentKey: String?
    private var gotPayload: (key: String, specimens: [SpecimenPayload])?
    private var theyGotKey: String?
    private(set) var isDone = false

    /// Delivers a message to the real session.
    var deliver: (Message) -> Void = { _ in }

    init(friendID: String, name: String) {
        self.friendID = friendID
        self.peer = MCPeerID(displayName: "\(name) (simulated)")
    }

    private var simulator: FriendsSimulator? { FriendsStore.shared.simulator }
    var shelf: [SpecimenPayload] { simulator?.shelf(friendID) ?? [] }

    var tableKey: String {
        let a = mine.map(\.lineageID.uuidString).sorted().joined(separator: ",")
        let b = theirs.map(\.id).sorted().joined(separator: ",")
        return [a, b].sorted().joined(separator: "#")
    }

    // MARK: Driven from the debug controls

    func putInRandom() {
        guard let next = shelf.first(where: { item in !mine.contains { $0.lineageID == item.lineageID } }) else { return }
        mine.append(next)
        sendTable()
    }

    func takeOneOut() {
        guard !mine.isEmpty else { return }
        mine.removeLast()
        sendTable()
    }

    func vote(_ yes: Bool) {
        guard !mine.isEmpty, !theirs.isEmpty else { return }
        myVote = (tableKey, yes)
        send(.vote(key: tableKey, yes: yes))
        advance()
    }

    // MARK: Protocol

    func receive(_ message: Message) {
        switch message {
        case .table(let items):
            theirs = items
            if autoYes, mine.isEmpty { putInRandom() }
        case .vote(let key, let yes):
            theirVote = (key, yes)
            if autoYes, yes, key == tableKey, myVote?.key != key { vote(true) } else { advance() }
        case .payload(let key, let specimens):
            guard key == tableKey, Set(specimens.map(\.lineageID.uuidString)) == Set(theirs.map(\.id)) else { return }
            gotPayload = (key, specimens)
            send(.received(key: key))
            finish()
        case .received(let key):
            theyGotKey = key
            finish()
        }
    }

    private func advance() {
        let key = tableKey
        guard myVote?.key == key, myVote?.yes == true, theirVote?.key == key, theirVote?.yes == true,
              sentKey != key else { return }
        sentKey = key
        send(.payload(key: key, specimens: mine))
        finish()
    }

    private func finish() {
        let key = tableKey
        guard !isDone, let gotPayload, gotPayload.key == key, theyGotKey == key, sentKey == key else { return }
        isDone = true
        simulator?.settleTable(friendID: friendID, gave: mine, got: gotPayload.specimens)
    }

    private func sendTable() {
        send(.table(mine.map { payload in
            TradeTableSession.TableItem(id: payload.lineageID.uuidString, name: payload.name,
                                        squishLevel: payload.squishLevel,
                                        thumbnail: FriendsSimulator.item(payload).thumbnail)
        }))
    }

    private func send(_ message: Message) {
        deliver(message)
    }
}
#endif
