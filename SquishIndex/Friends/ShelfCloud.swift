import CloudKit
import Foundation

/// The CloudKit side of friends and trading. Stateless apart from the container:
/// `FriendsStore` owns what the UI sees and calls in here.
///
/// Layout (Design/FRIENDS-AND-TRADING.md §3):
/// - Each user has one zone, `Shelf`, in their private database, shared
///   read-only with each friend through a zone-wide `CKShare`.
/// - It holds a `Profile`, one `Specimen` per held squishy (thumbnail only),
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
        static let squish = "squish"
        static let widthMM = "widthMM"
        static let heightMM = "heightMM"
        static let method = "method"
        static let paletteHex = "paletteHex"
        static let paletteProportions = "paletteProportions"
        static let form = "form"
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
        Key.displayName, Key.name, Key.squish, Key.widthMM, Key.heightMM, Key.method,
        Key.paletteHex, Key.paletteProportions, Key.form, Key.keeping, Key.addedAt,
        Key.thumb, Key.rev, Key.fromID, Key.fromName, Key.toID, Key.toName, Key.offered,
        Key.wanted, Key.line, Key.createdAt, Key.handedOver, Key.cancelled, Key.requestID,
        Key.accepted, Key.repliedAt
    ]

    let container = CKContainer.default()
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
    func createShare(title: String) async throws -> CKShare {
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = title
        share.publicPermission = .none
        let result = try await privateDB.modifyRecords(saving: [share], deleting: [])
        if case .success(let saved)? = result.saveResults[share.recordID], let savedShare = saved as? CKShare {
            return savedShare
        }
        return share
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

    /// Leaving a friend's shelf: deleting the share from the shared database
    /// removes this user as a participant.
    func leaveShelf(ownedBy ownerName: String) async throws {
        let zone = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: ownerName)
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
        _ = try await sharedDB.modifyRecords(saving: [], deleting: [id])
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

    func specimenRecord(_ specimen: Squishy, thumbnail: URL?) -> CKRecord {
        let record = CKRecord(recordType: RecordType.specimen,
                              recordID: recordID("specimen-" + specimen.lineageID.uuidString))
        record[Key.name] = specimen.name
        record[Key.squish] = specimen.squishLevel
        record[Key.widthMM] = specimen.widthMM
        record[Key.heightMM] = specimen.heightMM
        record[Key.method] = specimen.measurementMethod
        record[Key.paletteHex] = specimen.paletteHex
        record[Key.paletteProportions] = specimen.paletteProportions
        record[Key.form] = specimen.form
        record[Key.keeping] = specimen.isKeeping ? 1 : 0
        record[Key.addedAt] = specimen.addedAt
        record[Key.rev] = specimen.shelfRevision
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
                          squishLevel: record[Key.squish] as? Int ?? 5,
                          widthMM: record[Key.widthMM] as? Double,
                          heightMM: record[Key.heightMM] as? Double,
                          measurementMethod: record[Key.method] as? String ?? MeasurementMethod.none.rawValue,
                          paletteHex: record[Key.paletteHex] as? [String] ?? [],
                          paletteProportions: record[Key.paletteProportions] as? [Double] ?? [],
                          form: record[Key.form] as? String ?? SpecimenForm.irregular.rawValue,
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
