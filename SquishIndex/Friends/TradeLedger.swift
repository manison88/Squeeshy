import Foundation
import SwiftData
import UIKit

/// The only code that moves specimens in and out of the catalogue because of a
/// trade. Remote trades and the in-person trade table both finish here, so a
/// swap is filed the same way however it happened.
@MainActor
enum TradeLedger {

    /// Held specimens with these lineage IDs, in the order given.
    static func held(_ lineageIDs: [String], in context: ModelContext) -> [Squishy] {
        let all = (try? context.fetch(FetchDescriptor<Squishy>())) ?? []
        return lineageIDs.compactMap { id in
            all.first { $0.lineageID.uuidString == id && !$0.isTraded }
        }
    }

    /// Files what arrived and archives what left. Idempotent per lineage: an
    /// item already held is not filed twice, and an item already traded is not
    /// traded twice.
    static func complete(receiving payloads: [SpecimenPayload],
                         from sender: String,
                         giving lineageIDs: [String],
                         to recipient: String,
                         in context: ModelContext) async {
        // Feature prints are regenerated here rather than trusted from another
        // device, so duplicate detection keeps working on this one.
        var prints: [UUID: Data] = [:]
        for payload in payloads {
            let photo = payload.photo
            prints[payload.lineageID] = await Task.detached(priority: .userInitiated) {
                UIImage(data: photo).flatMap(SquishyVision.featurePrint(for:)) ?? Data()
            }.value
        }

        let all = (try? context.fetch(FetchDescriptor<Squishy>())) ?? []
        let now = Date.now

        for id in lineageIDs {
            guard let outgoing = all.first(where: { $0.lineageID.uuidString == id && !$0.isTraded }) else { continue }
            outgoing.tradeStatus = Squishy.tradedStatus
            outgoing.tradedTo = recipient
            outgoing.tradedAt = now
        }

        for payload in payloads {
            let tenure = ProvenanceEntry(owner: sender, from: payload.ownerSince, to: now)
            if let existing = all.first(where: { $0.lineageID == payload.lineageID }) {
                // A trade-back: the archived record comes back to life rather
                // than a second copy appearing.
                guard existing.isTraded else { continue }
                existing.tradeStatus = nil
                existing.tradedTo = nil
                existing.tradedAt = nil
                existing.acquiredFrom = sender
                existing.provenance = payload.provenance + [tenure]
                existing.addedAt = now
                continue
            }
            let specimen = Squishy(
                name: payload.name,
                squishLevel: payload.squishLevel,
                addedAt: now,
                photo: payload.photo,
                featurePrint: prints[payload.lineageID] ?? Data(),
                widthMM: payload.widthMM,
                heightMM: payload.heightMM,
                measurementMethod: payload.measurementMethod,
                confidence: payload.confidence,
                dominantHue: payload.dominantHue,
                dominantSaturation: payload.dominantSaturation,
                dominantBrightness: payload.dominantBrightness,
                paletteHex: payload.paletteHex,
                paletteProportions: payload.paletteProportions,
                form: payload.form,
                type: payload.type,
                subject: payload.subject,
                material: payload.material,
                surface: payload.surface,
                tags: payload.tags
            )
            specimen.originID = payload.lineageID
            specimen.acquiredFrom = sender
            specimen.provenance = payload.provenance + [tenure]
            context.insert(specimen)
        }
        try? context.save()
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

// MARK: - Thumbnails

extension Squishy {
    /// What friends see: small enough to keep a whole shelf light, large enough
    /// for a two-up grid on an iPad.
    func shelfThumbnail() -> Data? {
        guard let image = UIImage(data: photo) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 480 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = image.preparingThumbnail(of: size) ?? image
        return resized.jpegData(compressionQuality: 0.72)
    }
}
