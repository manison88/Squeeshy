import Foundation
import SwiftUI

// Value types for everything that crosses a device boundary: friends' shelves,
// trade requests and replies, and the full squeeshy that travels when a trade
// completes. None of it is SwiftData — friends' data is a copy of someone
// else's iCloud and must never mix into this collection, its shelves or its tint.

// MARK: - A friend's shelf

/// One squeeshy on a friend's shelf, as their device published it.
struct FriendItem: Codable, Identifiable, Hashable {
    /// The squeeshy's lineage ID, as a string.
    var id: String
    var name: String
    var speciesRaw: String
    var hue: Double
    var saturation: Double
    var sizeRaw: String
    var squeeshiness: Double
    var typeName: String
    var isKeeping: Bool
    var addedAt: Date
    /// A small transparent PNG of the cut-out. Nil for a drawn squeeshy.
    var thumbnail: Data?

    var species: Species { Species(rawValue: speciesRaw) ?? .round }
    var size: SizeClass { SizeClass(rawValue: sizeRaw) ?? .medium }
    var color: Color { Hue.color(hue, saturation: saturation) }
    var image: UIImage? { thumbnail.flatMap(UIImage.init(data:)) }

    /// "Cat · Round · Medium", matching `Squishy.traitLine`.
    var traitLine: String {
        [typeName, species.shapeName, size.label].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// A friend is a shelf someone shared with this user. Their `id` is the CloudKit
/// owner name of that shared zone, which is also their user record name — the
/// one handle both devices agree on.
struct Friend: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var updatedAt: Date?
    var items: [FriendItem]

    var openCount: Int { items.filter { !$0.isKeeping }.count }
    var tint: Tint { Tint.sampled(from: items.map(\.hue)) }
}

// MARK: - Trades

/// A line in a trade: enough to show what was asked for even after the
/// squeeshy has left the shelf it was on.
struct TradeLine: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var hue: Double
    var speciesRaw: String

    var species: Species { Species(rawValue: speciesRaw) ?? .round }
    var color: Color { Hue.color(hue) }
}

/// Lives in the *requester's* zone. Only the requester ever writes it.
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

/// A request and its reply, as seen from this device.
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

    /// Both sides accepted and handed over: time to file the swap.
    var isReadyToComplete: Bool {
        !isCompletedHere && !request.cancelled && (reply?.accepted ?? false)
            && request.handedOver && (reply?.handedOver ?? false)
    }
}

/// The fixed lines a request can carry. No free text means nothing to moderate.
enum TradePreset: String, CaseIterable, Identifiable {
    case double = "I have a double!"
    case school = "Swap at school?"
    case post = "I can post it"

    var id: String { rawValue }
}

// MARK: - The squeeshy itself, in transit

/// Everything needed to file a squeeshy on its new owner's device: traits, the
/// transparent cut-out, and where it has been. Travels as a CloudKit asset or
/// over the trade-table link; never as a queryable record.
struct SpecimenPayload: Codable, Hashable {
    var lineageID: UUID
    var name: String
    var speciesRaw: String
    var hue: Double
    var saturation: Double
    var sizeRaw: String
    var squeeshiness: Double
    var typeName: String
    /// The cut-out as PNG, alpha intact. Nil for a drawn squeeshy.
    var cutout: Data?
    /// Earlier owners, not including the sender.
    var provenance: [ProvenanceEntry]
    /// When the sender got it — the start of their tenure.
    var ownerSince: Date
}

extension SpecimenPayload {
    init(_ squishy: Squishy) {
        self.init(lineageID: squishy.lineageID,
                  name: squishy.name,
                  speciesRaw: squishy.speciesRaw,
                  hue: squishy.hue,
                  saturation: squishy.saturation,
                  sizeRaw: squishy.sizeRaw,
                  squeeshiness: squishy.squeeshiness,
                  typeName: squishy.typeName,
                  cutout: squishy.photoFilename.flatMap { try? Data(contentsOf: PhotoStore.url(for: $0)) },
                  provenance: squishy.provenance,
                  ownerSince: squishy.addedAt)
    }

    var line: TradeLine {
        TradeLine(id: lineageID.uuidString, name: name, hue: hue, speciesRaw: speciesRaw)
    }
}

// MARK: - Squishy, for trading

/// One earlier owner. The current owner is never listed: their tenure is
/// `addedAt` to now.
struct ProvenanceEntry: Codable, Hashable {
    var owner: String
    var from: Date
    var to: Date
}

extension Squishy {
    var lineageID: UUID { originID ?? id }

    var isKeeping: Bool {
        get { keepFlag ?? false }
        set { keepFlag = newValue ? true : nil }
    }

    var provenance: [ProvenanceEntry] {
        get {
            guard let provenanceData else { return [] }
            return (try? JSONDecoder().decode([ProvenanceEntry].self, from: provenanceData)) ?? []
        }
        set { provenanceData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var line: TradeLine {
        TradeLine(id: lineageID.uuidString, name: name, hue: hue, speciesRaw: speciesRaw)
    }

    /// Changes whenever anything a friend can see changes, so only what moved is
    /// re-uploaded. The photo filename is its own segment so a new cut-out is
    /// detected separately from a rename.
    var shelfRevision: String {
        [name, speciesRaw, String(format: "%.1f", hue), sizeRaw,
         String(format: "%.1f", squeeshiness), typeName, isKeeping ? "K" : "O",
         "photo:" + (photoFilename ?? "-")].joined(separator: "|")
    }

    /// What friends see: a small transparent PNG, light enough for a whole shelf.
    /// Nil for a drawn squeeshy, which the friend's device draws itself.
    func shelfThumbnail() -> Data? {
        Self.thumbnailData(forPhoto: photoFilename)
    }

    /// The same, from a cut-out's file name alone, so it can run off the main
    /// actor without touching a model object.
    static func thumbnailData(forPhoto filename: String?) -> Data? {
        guard let image = PhotoStore.load(filename) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 360 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.pngData()
    }
}

// MARK: - Traded away

/// A squeeshy that went to a friend. It leaves the collection — shelves, tint,
/// share cards — but the record of having owned it is part of the collection
/// too, so it is kept here.
struct TradedEntry: Codable, Identifiable, Hashable {
    /// Its own identity: the same squeeshy can be traded away more than once.
    var id = UUID()
    var lineageID: UUID
    var name: String
    var speciesRaw: String
    var hue: Double
    var thumbnail: Data?
    var tradedTo: String
    var tradedAt: Date

    var species: Species { Species(rawValue: speciesRaw) ?? .round }
    var color: Color { Hue.color(hue) }
    var image: UIImage? { thumbnail.flatMap(UIImage.init(data:)) }
}
