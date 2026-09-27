import Foundation
import SwiftUI

// Value types for everything that crosses a device boundary: friends'
// shelves, trade requests and replies, and the full specimen payload that
// travels when a trade completes. Nothing here is SwiftData — friends' data
// is a cache of someone else's iCloud, never part of this user's catalogue.
// Design/FRIENDS-AND-TRADING.md §3–§5.

/// One squishy on a friend's shelf, as that friend's device published it.
struct FriendItem: Codable, Identifiable, Hashable {
    /// The specimen's lineage ID, as a string.
    var id: String
    var name: String
    var squishLevel: Int
    var widthMM: Double?
    var heightMM: Double?
    var measurementMethod: String
    var paletteHex: [String]
    var paletteProportions: [Double]
    var form: String
    var isKeeping: Bool
    var addedAt: Date
    var thumbnail: Data?

    var image: UIImage? { thumbnail.flatMap(UIImage.init(data:)) }
    var squish: SquishLevel { SquishLevel(squishLevel) }
    var method: MeasurementMethod { MeasurementMethod(rawValue: measurementMethod) ?? .none }
    var silhouette: SpecimenForm { SpecimenForm(rawValue: form) ?? .irregular }

    var dominantColor: Color {
        paletteHex.first.flatMap { Color(hexString: $0) } ?? SquishTheme.soft
    }

    var spokenSummary: String {
        var parts = ["\(name).", "Squish \(squishLevel) of 10, \(squish.term.lowercased())."]
        if isKeeping { parts.append("Keeping.") }
        return parts.joined(separator: " ")
    }
}

/// A friend is a shelf someone shared with this user. Their `id` is the
/// CloudKit owner name of that shared zone, which is also their user record
/// name — the one stable handle both devices agree on.
struct Friend: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var updatedAt: Date?
    var items: [FriendItem]

    var openCount: Int { items.filter { !$0.isKeeping }.count }
    /// Four colours from their own shelf stand in for an avatar.
    var monogram: [String] { items.prefix(4).compactMap(\.paletteHex.first) }
}

/// A line in a trade: enough to show what was asked for even after the
/// specimen has left the shelf it was on.
struct TradeLine: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var squishLevel: Int
}

/// Lives in the *requester's* zone. The requester is the only one who writes it.
struct TradeRequest: Codable, Identifiable, Hashable {
    var id: UUID
    var fromID: String
    var fromName: String
    var toID: String
    var toName: String
    /// What the requester gives.
    var offered: [TradeLine]
    /// What the requester gets.
    var wanted: [TradeLine]
    var line: String?
    var createdAt: Date
    var handedOver: Bool
    var cancelled: Bool

    static let lifetime: TimeInterval = 14 * 24 * 3600
    var isExpired: Bool { Date.now.timeIntervalSince(createdAt) > Self.lifetime }
}

/// Lives in the *responder's* zone, one per request.
struct TradeReply: Codable, Identifiable, Hashable {
    var requestID: UUID
    var fromID: String
    var toID: String
    var accepted: Bool
    var handedOver: Bool
    var repliedAt: Date

    var id: UUID { requestID }
}

/// A request and its reply, seen from this device.
struct Trade: Identifiable, Hashable {
    enum Direction { case incoming, outgoing }

    enum State: Equatable {
        case waitingForReply
        case needsMyReply
        case inProgress
        case completed
        case declined
        case cancelled
        case expired
    }

    let request: TradeRequest
    let reply: TradeReply?
    let direction: Direction
    let isCompletedHere: Bool

    var id: UUID { request.id }
    var friendID: String { direction == .outgoing ? request.toID : request.fromID }
    var friendName: String { direction == .outgoing ? request.toName : request.fromName }
    /// What this user gives up.
    var giving: [TradeLine] { direction == .outgoing ? request.offered : request.wanted }
    /// What this user receives.
    var getting: [TradeLine] { direction == .outgoing ? request.wanted : request.offered }

    var iHandedOver: Bool {
        direction == .outgoing ? request.handedOver : (reply?.handedOver ?? false)
    }
    var theyHandedOver: Bool {
        direction == .outgoing ? (reply?.handedOver ?? false) : request.handedOver
    }

    var state: State {
        if isCompletedHere { return .completed }
        if request.cancelled { return .cancelled }
        if let reply {
            guard reply.accepted else { return .declined }
            return .inProgress
        }
        if request.isExpired { return .expired }
        return direction == .incoming ? .needsMyReply : .waitingForReply
    }

    /// Both sides have accepted and handed over — time to file the swap.
    var isReadyToComplete: Bool {
        !isCompletedHere && !request.cancelled && (reply?.accepted ?? false)
            && request.handedOver && (reply?.handedOver ?? false)
    }
}

/// Everything needed to file a specimen on a new owner's device. Travels as a
/// CloudKit asset (or over the local link at a trade table), never as a
/// queryable record.
struct SpecimenPayload: Codable, Hashable {
    var lineageID: UUID
    var name: String
    var squishLevel: Int
    var photo: Data
    var widthMM: Double?
    var heightMM: Double?
    var measurementMethod: String
    var confidence: Double
    var dominantHue: Double
    var dominantSaturation: Double
    var dominantBrightness: Double
    var paletteHex: [String]
    var paletteProportions: [Double]
    var form: String
    var type: String?
    var subject: String?
    var material: String?
    var surface: String?
    var tags: [String]
    /// Earlier owners, not including the sender.
    var provenance: [ProvenanceEntry]
    /// When the sender got it — the start of their tenure.
    var ownerSince: Date
}

extension SpecimenPayload {
    init(_ specimen: Squishy) {
        self.init(lineageID: specimen.lineageID,
                  name: specimen.name,
                  squishLevel: specimen.squishLevel,
                  photo: specimen.photo,
                  widthMM: specimen.widthMM,
                  heightMM: specimen.heightMM,
                  measurementMethod: specimen.measurementMethod,
                  confidence: specimen.confidence,
                  dominantHue: specimen.dominantHue,
                  dominantSaturation: specimen.dominantSaturation,
                  dominantBrightness: specimen.dominantBrightness,
                  paletteHex: specimen.paletteHex,
                  paletteProportions: specimen.paletteProportions,
                  form: specimen.form,
                  type: specimen.type,
                  subject: specimen.subject,
                  material: specimen.material,
                  surface: specimen.surface,
                  tags: specimen.tags,
                  provenance: specimen.provenance,
                  ownerSince: specimen.addedAt)
    }
}

/// The fixed lines a request can carry. No free text means nothing to moderate.
enum TradePreset: String, CaseIterable, Identifiable {
    case double = "I have a double!"
    case school = "Swap at school?"
    case post = "I can post it"

    var id: String { rawValue }
}
