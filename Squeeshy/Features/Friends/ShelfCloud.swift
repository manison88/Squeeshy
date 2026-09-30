import CloudKit
import Foundation

/// The CloudKit side of friends and trading. Stateless apart from the container:
/// `FriendsStore` owns what the UI sees and calls in here.
///
/// This is separate from the collection itself, which stays local: SwiftData is
/// opened with `cloudKitDatabase: .none`, and only this shelf zone goes to iCloud.
///
/// Layout (Design/FRIENDS-AND-TRADING.md §3):
/// - Each user has one zone, `Shelf`, in their private database, shared
///   read-only with each friend through a zone-wide `CKShare`.
/// - It holds a `Profile`, one `Specimen` per squeeshy (a small cut-out only),
///   the `TradeRequest`s they sent and the `TradeReply`s they wrote.
/// - Friends' zones appear in this user's shared database.
///
/// Nobody ever writes into someone else's zone, so every share is read-only.
/// Everything is fetched whole with `recordZoneChanges(since: nil)`: shelves
/// are small, and a full read needs no queryable indexes in the production
/// schema and can never drift out of sync the way a change-token cache can.
final class ShelfCloud {
    static let zoneName = "Shelf"

    enum RecordType {
        static let profile = "Profile"
        static let specimen = "Specimen"
        static let request = "TradeRequest"
        static let reply = "TradeReply"
    }

    enum Key {
        static let displayName = "displayName"
        static let name = "name"
        static let species = "species"
        static let hue = "hue"
        static let saturation = "saturation"
        static let size = "size"
        static let squeeshiness = "squeeshiness"
        static let typeName = "typeName"
        static let keeping = "keeping"
        static let addedAt = "addedAt"
        static let thumb = "thumb"
        static let rev = "rev"
        static let fromID = "fromID"
        static let fromName = "fromName"
        static let toID = "toID"
        static let toName = "toName"
        static let offered = "offered"
        static let wanted = "wanted"
        static let line = "line"
        static let createdAt = "createdAt"
        static let handedOver = "handedOver"
        static let cancelled = "cancelled"
        static let requestID = "requestID"
        static let accepted = "accepted"
        static let repliedAt = "repliedAt"
        static let payload = "payload"
    }

    /// Everything but the payload asset: payloads are only downloaded at the
    /// moment a trade completes.
    static let listKeys: [CKRecord.FieldKey] = [
        Key.displayName, Key.name, Key.species, Key.hue, Key.saturation, Key.size,
        Key.squeeshiness, Key.typeName, Key.keeping, Key.addedAt,
        Key.thumb, Key.rev, Key.fromID, Key.fromName, Key.toID, Key.toName, Key.offered,
        Key.wanted, Key.line, Key.createdAt, Key.handedOver, Key.cancelled, Key.requestID,
        Key.accepted, Key.repliedAt
    ]

    /// Lazy, so nothing touches CloudKit until friends are actually used — a
    /// simulator build signed without the iCloud entitlement, or the debug
    /// friends simulation, never creates a container at all.
    lazy var container = CKContainer.default()
    var privateDB: CKDatabase { container.privateCloudDatabase }
    var sharedDB: CKDatabase { container.sharedCloudDatabase }

    let zoneID = CKRecordZone.ID(zoneName: ShelfCloud.zoneName, ownerName: CKCurrentUserDefaultName)

    private static let subscriptionID = "shared-shelves"

    // MARK: Account

    func accountStatus() async -> CKAccountStatus {
        (try? await container.accountStatus()) ?? .couldNotDetermine
    }

    func userRecordName() async throws -> String {
        try await container.userRecordID().recordName
    }

    // MARK: Zone, share, subscription

    func ensureZone() async throws {
        _ = try await privateDB.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
    }

    func fetchShare() async throws -> CKShare? {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            return try await privateDB.record(for: id) as? CKShare
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// Private by default: a forwarded invite link lets nobody else in.
    ///
    /// Returns the share as the server saved it. A save that failed must throw:
    /// an unsaved share has no link, and the invite sheet shown for one can't
    /// copy a link and spins forever in Messages.
    func createShare(title: String) async throws -> CKShare {
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = title
        share.publicPermission = .none
        let result = try await privateDB.modifyRecords(saving: [share], deleting: [])
        switch result.saveResults[share.recordID] {
        case .success(let saved)?:
            guard let savedShare = saved as? CKShare else { throw CKError(.internalError) }
            return savedShare
        case .failure(let error)?:
            // Made meanwhile by another device (or an earlier tap): use that one.
            if (error as? CKError)?.code == .serverRecordChanged, let existing = try await fetchShare() {
                return existing
            }
            throw error
        case nil:
            throw CKError(.internalError)
        }
    }

    func save(share: CKShare) async throws {
        _ = try await privateDB.modifyRecords(saving: [share], deleting: [], savePolicy: .changedKeys)
    }

    /// A silent push whenever anything in a friend's shelf changes, so a new
    /// trade request shows up without opening the app.
    func ensureSubscription() async {
        let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try? await sharedDB.modifySubscriptions(saving: [subscription], deleting: [])
    }

    func accept(_ metadata: CKShare.Metadata) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            operation.acceptSharesResultBlock = { result in continuation.resume(with: result) }
            container.add(operation)
        }
    }

    /// Leaving a friend's shelf: a participant deletes the shared zone from their
    /// own shared database, which removes them from the share.
    func leaveShelf(ownedBy ownerName: String) async throws {
        let zone = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: ownerName)
        _ = try await sharedDB.modifyRecordZones(saving: [], deleting: [zone])
    }

    // MARK: Reads

    func friendZones() async throws -> [CKRecordZone.ID] {
        try await sharedDB.allRecordZones()
            .map(\.zoneID)
            .filter { $0.zoneName == Self.zoneName }
    }

    func allRecords(in zone: CKRecordZone.ID,
                    of database: CKDatabase,
                    desiredKeys: [CKRecord.FieldKey]? = ShelfCloud.listKeys) async throws -> [CKRecord] {
        var token: CKServerChangeToken?
        var records: [CKRecord] = []
        var moreComing = true
        while moreComing {
            let changes = try await database.recordZoneChanges(inZoneWith: zone,
                                                               since: token,
                                                               desiredKeys: desiredKeys,
                                                               resultsLimit: 200)
            for (_, result) in changes.modificationResultsByID {
                if case .success(let modification) = result {
                    records.append(modification.record)
                }
            }
            token = changes.changeToken
            moreComing = changes.moreComing
        }
        return records
    }

    /// A single record with its payload asset downloaded.
    func payload(recordName: String, in zone: CKRecordZone.ID, of database: CKDatabase) async throws -> [SpecimenPayload] {
        let record = try await database.record(for: CKRecord.ID(recordName: recordName, zoneID: zone))
        guard let asset = record[Key.payload] as? CKAsset, let url = asset.fileURL else { return [] }
        return PayloadFile.read(url)
    }

    // MARK: Writes

    /// `.changedKeys` so a fresh `CKRecord` with a known ID updates just the
    /// fields set on it — no fetch-modify-save round trip.
    func save(_ records: [CKRecord], deleting ids: [CKRecord.ID] = []) async throws {
        var remainingSaves = records[...]
        var remainingDeletes = ids[...]
        while !remainingSaves.isEmpty || !remainingDeletes.isEmpty {
            let saves = Array(remainingSaves.prefix(150))
            let deletes = Array(remainingDeletes.prefix(150))
            remainingSaves = remainingSaves.dropFirst(saves.count)
            remainingDeletes = remainingDeletes.dropFirst(deletes.count)
            _ = try await privateDB.modifyRecords(saving: saves,
                                                  deleting: deletes,
                                                  savePolicy: .changedKeys,
                                                  atomically: false)
        }
    }

    func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }
}

// MARK: - Record mapping

extension ShelfCloud {
    func profileRecord(displayName: String) -> CKRecord {
        let record = CKRecord(recordType: RecordType.profile, recordID: recordID("profile"))
        record[Key.displayName] = displayName
        return record
    }

    func specimenRecord(_ squishy: Squishy, thumbnail: URL?) -> CKRecord {
        let record = CKRecord(recordType: RecordType.specimen,
                              recordID: recordID("specimen-" + squishy.lineageID.uuidString))
        record[Key.name] = squishy.name
        record[Key.species] = squishy.speciesRaw
        record[Key.hue] = squishy.hue
        record[Key.saturation] = squishy.saturation
        record[Key.size] = squishy.sizeRaw
        record[Key.squeeshiness] = squishy.squeeshiness
        record[Key.typeName] = squishy.typeName
        record[Key.keeping] = squishy.isKeeping ? 1 : 0
        record[Key.addedAt] = squishy.addedAt
        record[Key.rev] = squishy.shelfRevision
        if let thumbnail { record[Key.thumb] = CKAsset(fileURL: thumbnail) }
        return record
    }

    func requestRecord(_ request: TradeRequest, payload: URL?) -> CKRecord {
        let record = CKRecord(recordType: RecordType.request,
                              recordID: recordID("request-" + request.id.uuidString))
        record[Key.fromID] = request.fromID
        record[Key.fromName] = request.fromName
        record[Key.toID] = request.toID
        record[Key.toName] = request.toName
        record[Key.offered] = Self.encode(request.offered)
        record[Key.wanted] = Self.encode(request.wanted)
        record[Key.line] = request.line
        record[Key.createdAt] = request.createdAt
        record[Key.handedOver] = request.handedOver ? 1 : 0
        record[Key.cancelled] = request.cancelled ? 1 : 0
        if let payload { record[Key.payload] = CKAsset(fileURL: payload) }
        return record
    }

    /// Only the flags — used for "handed over" and "cancel".
    func requestFlags(id: UUID, handedOver: Bool, cancelled: Bool) -> CKRecord {
        let record = CKRecord(recordType: RecordType.request, recordID: recordID("request-" + id.uuidString))
        record[Key.handedOver] = handedOver ? 1 : 0
        record[Key.cancelled] = cancelled ? 1 : 0
        return record
    }

    func replyRecord(_ reply: TradeReply, payload: URL?) -> CKRecord {
        let record = CKRecord(recordType: RecordType.reply,
                              recordID: recordID("reply-" + reply.requestID.uuidString))
        record[Key.requestID] = reply.requestID.uuidString
        record[Key.fromID] = reply.fromID
        record[Key.toID] = reply.toID
        record[Key.accepted] = reply.accepted ? 1 : 0
        record[Key.handedOver] = reply.handedOver ? 1 : 0
        record[Key.repliedAt] = reply.repliedAt
        if let payload { record[Key.payload] = CKAsset(fileURL: payload) }
        return record
    }

    static func displayName(from record: CKRecord) -> String? {
        record[Key.displayName] as? String
    }

    static func friendItem(from record: CKRecord) -> FriendItem? {
        guard record.recordType == RecordType.specimen,
              let name = record[Key.name] as? String else { return nil }
        let id = record.recordID.recordName.replacingOccurrences(of: "specimen-", with: "")
        var thumbnail: Data?
        if let asset = record[Key.thumb] as? CKAsset, let url = asset.fileURL {
            thumbnail = try? Data(contentsOf: url)
        }
        return FriendItem(id: id,
                          name: name,
                          speciesRaw: record[Key.species] as? String ?? Species.round.rawValue,
                          hue: record[Key.hue] as? Double ?? 0,
                          saturation: record[Key.saturation] as? Double ?? 0.45,
                          sizeRaw: record[Key.size] as? String ?? SizeClass.medium.rawValue,
                          squeeshiness: record[Key.squeeshiness] as? Double ?? 5,
                          typeName: record[Key.typeName] as? String ?? "",
                          isKeeping: (record[Key.keeping] as? Int ?? 0) != 0,
                          addedAt: record[Key.addedAt] as? Date ?? .distantPast,
                          thumbnail: thumbnail)
    }

    static func request(from record: CKRecord) -> TradeRequest? {
        guard record.recordType == RecordType.request,
              let id = UUID(uuidString: record.recordID.recordName.replacingOccurrences(of: "request-", with: "")),
              let fromID = record[Key.fromID] as? String,
              let toID = record[Key.toID] as? String else { return nil }
        return TradeRequest(id: id,
                            fromID: fromID,
                            fromName: record[Key.fromName] as? String ?? "A friend",
                            toID: toID,
                            toName: record[Key.toName] as? String ?? "A friend",
                            offered: decode(record[Key.offered] as? String),
                            wanted: decode(record[Key.wanted] as? String),
                            line: record[Key.line] as? String,
                            createdAt: record[Key.createdAt] as? Date ?? .distantPast,
                            handedOver: (record[Key.handedOver] as? Int ?? 0) != 0,
                            cancelled: (record[Key.cancelled] as? Int ?? 0) != 0)
    }

    static func reply(from record: CKRecord) -> TradeReply? {
        guard record.recordType == RecordType.reply,
              let requestString = record[Key.requestID] as? String,
              let requestID = UUID(uuidString: requestString),
              let fromID = record[Key.fromID] as? String,
              let toID = record[Key.toID] as? String else { return nil }
        return TradeReply(requestID: requestID,
                          fromID: fromID,
                          toID: toID,
                          accepted: (record[Key.accepted] as? Int ?? 0) != 0,
                          handedOver: (record[Key.handedOver] as? Int ?? 0) != 0,
                          repliedAt: record[Key.repliedAt] as? Date ?? .distantPast)
    }

    private static func encode(_ lines: [TradeLine]) -> String {
        (try? String(data: JSONEncoder().encode(lines), encoding: .utf8)) ?? "[]"
    }

    private static func decode(_ string: String?) -> [TradeLine] {
        guard let data = string?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([TradeLine].self, from: data)) ?? []
    }
}
