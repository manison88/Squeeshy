import Foundation
import SwiftData
import UIKit

/// The only code that moves squeeshies in and out of the collection because of a
/// trade. Remote trades and the trade table both finish here, so a swap is filed
/// the same way however it happened.
@MainActor
enum TradeLedger {

    /// Squeeshies in the collection with these lineage IDs, in the order given.
    static func held(_ lineageIDs: [String], in context: ModelContext) -> [Squishy] {
        let all = (try? context.fetch(FetchDescriptor<Squishy>())) ?? []
        return lineageIDs.compactMap { id in all.first { $0.lineageID.uuidString == id } }
    }

    /// Files what arrived and lets go of what left.
    ///
    /// Outgoing: a squeeshy owned more than once (`quantity`) loses one; otherwise
    /// it leaves every shelf, its cut-out is deleted, and it moves to the
    /// traded-away archive — exactly what Delete does, plus the record.
    /// Incoming: a trade-back of something already held adds to its quantity;
    /// anything else is filed as new, keeping its traits and cut-out.
    static func complete(receiving payloads: [SpecimenPayload],
                         from sender: String,
                         giving lineageIDs: [String],
                         to recipient: String,
                         in context: ModelContext) {
        let now = Date.now
        var archived: [TradedEntry] = []

        for squishy in held(lineageIDs, in: context) {
            archived.append(TradedEntry(lineageID: squishy.lineageID, name: squishy.name,
                                        speciesRaw: squishy.speciesRaw, hue: squishy.hue,
                                        thumbnail: squishy.shelfThumbnail(),
                                        tradedTo: recipient, tradedAt: now))
            if squishy.quantity > 1 {
                squishy.quantity -= 1
                continue
            }
            for shelf in squishy.shelves ?? [] {
                shelf.items = (shelf.items ?? []).filter { $0.id != squishy.id }
            }
            CutoutCache.shared.forget(squishy.photoFilename)
            PhotoStore.delete(squishy.photoFilename)
            context.delete(squishy)
        }

        let all = (try? context.fetch(FetchDescriptor<Squishy>())) ?? []
        for payload in payloads {
            let tenure = ProvenanceEntry(owner: sender, from: payload.ownerSince, to: now)
            if let existing = all.first(where: { $0.lineageID == payload.lineageID }) {
                existing.quantity += 1
                continue
            }
            let squishy = Squishy(name: payload.name,
                                  species: Species(rawValue: payload.speciesRaw) ?? .round,
                                  hue: payload.hue,
                                  size: SizeClass(rawValue: payload.sizeRaw) ?? .medium,
                                  squeeshiness: payload.squeeshiness,
                                  typeName: payload.typeName,
                                  addedAt: now)
            squishy.saturation = payload.saturation
            squishy.originID = payload.lineageID
            squishy.acquiredFrom = sender
            squishy.provenance = payload.provenance + [tenure]
            if let cutout = payload.cutout, let image = UIImage(data: cutout) {
                squishy.photoFilename = PhotoStore.save(image)
            }
            context.insert(squishy)
        }
        try? context.save()
        TradedArchive.append(archived)
        FriendsStore.shared.reloadTradedAway()
    }
}

// MARK: - Traded-away archive

enum TradedArchive {
    private static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("traded-away.json")
    }

    static func load() -> [TradedEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([TradedEntry].self, from: data)) ?? []
    }

    static func append(_ entries: [TradedEntry]) {
        guard !entries.isEmpty else { return }
        let all = entries + load()
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

// MARK: - Payload files

enum PayloadFile {
    /// Writes payloads to a temporary JSON file, for a CloudKit asset.
    static func write(_ payloads: [SpecimenPayload]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("payload-\(UUID().uuidString).json")
        try JSONEncoder().encode(payloads).write(to: url, options: .atomic)
        return url
    }

    static func read(_ url: URL) -> [SpecimenPayload] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SpecimenPayload].self, from: data)) ?? []
    }
}
