import CloudKit
import Foundation
import Observation
import SwiftData
import UserNotifications

/// What the friends and trades screens see, and every action they can take.
///
/// The catalogue never waits on this. If iCloud is signed out, offline or
/// failing, the friends screens say so and everything else works exactly as it
/// did before Milestone 6. SPEC.md §7 "do not gate the app on the cloud".
@MainActor
@Observable
final class FriendsStore {
    static let shared = FriendsStore()

    enum Availability: Equatable {
        case checking
        case available
        case noAccount
        case restricted
        case unavailable
    }

    private(set) var availability: Availability = .checking
    private(set) var friends: [Friend] = []
    private(set) var myRequests: [TradeRequest] = []
    private(set) var myReplies: [TradeReply] = []
    private(set) var incomingRequests: [TradeRequest] = []
    private(set) var incomingReplies: [TradeReply] = []
    /// Names of people this user invited who haven't accepted yet.
    private(set) var pendingInvites: [String] = []
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date? = nil
    /// Plain-language, shown on the friends screen. `nil` when all is well.
    private(set) var problem: String? = nil
    /// Set after accepting someone's invite, to offer sharing back.
    var pendingShareBack: Friend? = nil

    private(set) var displayName: String

    private let cloud = ShelfCloud()
    private let defaults = UserDefaults.standard
    private var modelContainer: ModelContainer? = nil
    private var myID: String? = nil
    private var share: CKShare? = nil
    private var publishTask: Task<Void, Never>? = nil
    private var publishedRevisions: [String: String] = [:]
    private var completedTradeIDs: Set<UUID>
    private var announcedIDs: Set<UUID>
    private var completing: Set<UUID> = []
    private var hasStarted = false

    private enum Keys {
        static let displayName = "friends.displayName"
        static let completed = "friends.completedTrades"
        static let announced = "friends.announced"
    }

    private init() {
        displayName = UserDefaults.standard.string(forKey: Keys.displayName) ?? ""
        completedTradeIDs = Set((UserDefaults.standard.stringArray(forKey: Keys.completed) ?? []).compactMap(UUID.init))
        announcedIDs = Set((UserDefaults.standard.stringArray(forKey: Keys.announced) ?? []).compactMap(UUID.init))
        loadCache()
    }

    // MARK: Derived

    func setDisplayName(_ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        displayName = trimmed
        defaults.set(trimmed, forKey: Keys.displayName)
        schedulePublish()
    }

    var hasDisplayName: Bool { !displayName.trimmingCharacters(in: .whitespaces).isEmpty }

    var trades: [Trade] {
        let outgoing = myRequests.map { request in
            Trade(request: request,
                  reply: incomingReplies.first { $0.requestID == request.id },
                  direction: .outgoing,
                  isCompletedHere: completedTradeIDs.contains(request.id))
        }
        let incoming = incomingRequests.map { request in
            Trade(request: request,
                  reply: myReplies.first { $0.requestID == request.id },
                  direction: .incoming,
                  isCompletedHere: completedTradeIDs.contains(request.id))
        }
        return (outgoing + incoming).sorted { $0.request.createdAt > $1.request.createdAt }
    }

    var waitingForMe: [Trade] { trades.filter { $0.state == .needsMyReply } }
    var inProgress: [Trade] { trades.filter { $0.state == .inProgress } }

    /// Things only this user can move forward.
    var badgeCount: Int {
        waitingForMe.count + inProgress.filter { !$0.iHandedOver }.count
    }

    var openOutgoingCount: Int { trades.filter { $0.state == .waitingForReply }.count }
    nonisolated static let maxOpenOutgoing = 5

    /// This user's CloudKit user record name, once known. Shared with nearby
    /// devices at a trade table so they can tell a friend from a stranger.
    var myUserID: String? { myID }

    func friend(_ id: String) -> Friend? { friends.first { $0.id == id } }

    func trades(with friendID: String) -> [Trade] { trades.filter { $0.friendID == friendID } }

    // MARK: Lifecycle

    func attach(_ container: ModelContainer) {
        modelContainer = container
    }

    private var context: ModelContext? { modelContainer?.mainContext }

    /// Safe to call repeatedly; re-runs the account check each time.
    func start() async {
        if !hasStarted {
            hasStarted = true
            NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.start() }
            }
        }
        switch await cloud.accountStatus() {
        case .available:
            availability = .available
        case .noAccount:
            availability = .noAccount
            return
        case .restricted:
            availability = .restricted
            return
        default:
            availability = .unavailable
            return
        }
        do {
            myID = try await cloud.userRecordName()
            try await cloud.ensureZone()
            share = try await cloud.fetchShare()
            await cloud.ensureSubscription()
            problem = nil
        } catch {
            problem = Self.describe(error)
            return
        }
        await refresh()
        await publish()
    }

    // MARK: Refresh

    func refresh() async {
        guard availability == .available, let myID, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let mine = try await cloud.allRecords(in: cloud.zoneID, of: cloud.privateDB)
            myRequests = mine.compactMap(ShelfCloud.request(from:))
            myReplies = mine.compactMap(ShelfCloud.reply(from:))
            var revisions: [String: String] = [:]
            for record in mine where record.recordType == ShelfCloud.RecordType.specimen {
                revisions[record.recordID.recordName] = record[ShelfCloud.Key.rev] as? String ?? ""
            }
            publishedRevisions = revisions

            var loadedFriends: [Friend] = []
            var requests: [TradeRequest] = []
            var replies: [TradeReply] = []
            for zone in try await cloud.friendZones() {
                let records: [CKRecord]
                do {
                    records = try await cloud.allRecords(in: zone, of: cloud.sharedDB)
                } catch {
                    // A friend who stopped sharing leaves a zone that no longer
                    // opens. Skip it rather than failing the whole refresh.
                    continue
                }
                let shareTitle = records.compactMap { $0 as? CKShare }.first?[CKShare.SystemFieldKey.title] as? String
                let name = records.compactMap(ShelfCloud.displayName(from:)).first ?? shareTitle ?? "Friend"
                let items = records.compactMap(ShelfCloud.friendItem(from:))
                    .sorted { $0.addedAt > $1.addedAt }
                let updated = records.compactMap(\.modificationDate).max()
                loadedFriends.append(Friend(id: zone.ownerName, name: name, updatedAt: updated, items: items))
                requests += records.compactMap(ShelfCloud.request(from:)).filter { $0.toID == myID }
                replies += records.compactMap(ShelfCloud.reply(from:)).filter { $0.toID == myID }
            }
            friends = loadedFriends.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            incomingRequests = requests
            incomingReplies = replies

            share = try await cloud.fetchShare()
            pendingInvites = (share?.participants ?? [])
                .filter { $0.role != .owner && $0.acceptanceStatus == .pending }
                .map { Self.name(of: $0) }

            lastRefresh = .now
            problem = nil
            saveCache()
            announceNewActivity()
            await completeReadyTrades()
        } catch {
            problem = Self.describe(error)
        }
    }

    func handleRemoteNotification() async {
        await refresh()
    }

    // MARK: Publishing this user's shelf

    /// Debounced: a burst of edits (filing, renaming, re-rating) uploads once.
    func schedulePublish() {
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.publish()
        }
    }

    func publish() async {
        guard availability == .available, myID != nil, let context else { return }
        let held = ((try? context.fetch(FetchDescriptor<Squishy>())) ?? []).filter { !$0.isTraded }

        var saves: [CKRecord] = []
        var wanted = Set<String>()
        for specimen in held {
            let name = "specimen-" + specimen.lineageID.uuidString
            wanted.insert(name)
            guard publishedRevisions[name] != specimen.shelfRevision else { continue }
            // Only re-send the thumbnail when the photo could have changed.
            var thumbnailURL: URL?
            if publishedRevisions[name] == nil || !(publishedRevisions[name] ?? "").contains("|\(specimen.photo.count)|"),
               let data = specimen.shelfThumbnail() {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).jpg")
                if (try? data.write(to: url, options: .atomic)) != nil { thumbnailURL = url }
            }
            saves.append(cloud.specimenRecord(specimen, thumbnail: thumbnailURL))
        }
        let deletes = publishedRevisions.keys
            .filter { !wanted.contains($0) }
            .map(cloud.recordID)
        if hasDisplayName {
            saves.append(cloud.profileRecord(displayName: displayName))
        }
        guard !saves.isEmpty || !deletes.isEmpty else { return }

        do {
            try await cloud.save(saves, deleting: deletes)
            for specimen in held {
                publishedRevisions["specimen-" + specimen.lineageID.uuidString] = specimen.shelfRevision
            }
            for id in deletes { publishedRevisions[id.recordName] = nil }
        } catch {
            problem = Self.describe(error)
        }
    }

    // MARK: Friending

    /// The share friends are invited to. Created on first use.
    func shareForInvite() async throws -> CKShare {
        if let share { return share }
        if let existing = try await cloud.fetchShare() {
            share = existing
            return existing
        }
        let title = hasDisplayName ? "\(displayName)'s squishies" : "Squish Index shelf"
        let created = try await cloud.createShare(title: title)
        share = created
        requestNotificationPermission()
        await publish()
        return created
    }

    var container: CKContainer { cloud.container }

    func accept(_ metadata: CKShare.Metadata) async {
        do {
            try await cloud.accept(metadata)
            await start()
            let ownerID = metadata.share.recordID.zoneID.ownerName
            // Friendship is mutual: offer to share back unless already shared.
            let alreadySharedBack = share?.participants.contains {
                $0.userIdentity.userRecordID?.recordName == ownerID
            } ?? false
            if !alreadySharedBack, let friend = friend(ownerID) {
                pendingShareBack = friend
            }
            requestNotificationPermission()
        } catch {
            problem = Self.describe(error)
        }
    }

    func remove(_ friend: Friend) async {
        do {
            try await cloud.leaveShelf(ownedBy: friend.id)
            if let share {
                for participant in share.participants
                where participant.userIdentity.userRecordID?.recordName == friend.id {
                    share.removeParticipant(participant)
                }
                try await cloud.save(share: share)
            }
            friends.removeAll { $0.id == friend.id }
            saveCache()
        } catch {
            problem = Self.describe(error)
        }
    }

    // MARK: Trades

    enum TradeError: LocalizedError {
        case notReady
        case tooManyOpen
        case nothingOffered
        case itemGone

        var errorDescription: String? {
            switch self {
            case .notReady: "Friends need iCloud. Check you're signed in, then try again."
            case .tooManyOpen: "You have \(FriendsStore.maxOpenOutgoing) requests waiting already. Wait for a reply or cancel one."
            case .nothingOffered: "Pick at least one of yours to offer."
            case .itemGone: "One of those squishies isn't on the shelf any more."
            }
        }
    }

    func sendRequest(to friend: Friend,
                     wanting wanted: [FriendItem],
                     offering offered: [Squishy],
                     line: TradePreset?) async throws {
        guard let myID, availability == .available else { throw TradeError.notReady }
        guard !offered.isEmpty else { throw TradeError.nothingOffered }
        guard openOutgoingCount < Self.maxOpenOutgoing else { throw TradeError.tooManyOpen }

        let request = TradeRequest(
            id: UUID(),
            fromID: myID,
            fromName: hasDisplayName ? displayName : "A friend",
            toID: friend.id,
            toName: friend.name,
            offered: offered.map { TradeLine(id: $0.lineageID.uuidString, name: $0.name, squishLevel: $0.squishLevel) },
            wanted: wanted.map { TradeLine(id: $0.id, name: $0.name, squishLevel: $0.squishLevel) },
            line: line?.rawValue,
            createdAt: .now,
            handedOver: false,
            cancelled: false)
        let payload = try PayloadFile.write(offered.map(SpecimenPayload.init))
        try await cloud.save([cloud.requestRecord(request, payload: payload)])
        myRequests.append(request)
        saveCache()
    }

    func respond(to trade: Trade, accept: Bool) async throws {
        guard let myID, let context else { throw TradeError.notReady }
        var payloadURL: URL?
        if accept {
            let giving = TradeLedger.held(trade.giving.map(\.id), in: context)
            guard giving.count == trade.giving.count else { throw TradeError.itemGone }
            payloadURL = try PayloadFile.write(giving.map(SpecimenPayload.init))
        }
        let reply = TradeReply(requestID: trade.request.id,
                               fromID: myID,
                               toID: trade.request.fromID,
                               accepted: accept,
                               handedOver: false,
                               repliedAt: .now)
        try await cloud.save([cloud.replyRecord(reply, payload: payloadURL)])
        myReplies.removeAll { $0.requestID == reply.requestID }
        myReplies.append(reply)
        saveCache()
    }

    func markHandedOver(_ trade: Trade) async throws {
        switch trade.direction {
        case .outgoing:
            try await cloud.save([cloud.requestFlags(id: trade.request.id, handedOver: true, cancelled: false)])
        case .incoming:
            guard var reply = trade.reply else { return }
            reply.handedOver = true
            try await cloud.save([cloud.replyRecord(reply, payload: nil)])
        }
        await refresh()
    }

    func cancel(_ trade: Trade) async throws {
        guard trade.direction == .outgoing else { return }
        try await cloud.save([cloud.requestFlags(id: trade.request.id, handedOver: false, cancelled: true)])
        if let index = myRequests.firstIndex(where: { $0.id == trade.request.id }) {
            myRequests[index].cancelled = true
        }
        saveCache()
    }

    /// Files every trade both sides have handed over. The payload comes from
    /// the *other* person's record, which lives in their zone.
    private func completeReadyTrades() async {
        guard let context else { return }
        for trade in trades where trade.isReadyToComplete && !completing.contains(trade.id) {
            completing.insert(trade.id)
            defer { completing.remove(trade.id) }
            let zone = CKRecordZone.ID(zoneName: ShelfCloud.zoneName, ownerName: trade.friendID)
            let recordName = (trade.direction == .outgoing ? "reply-" : "request-") + trade.request.id.uuidString
            guard let payloads = try? await cloud.payload(recordName: recordName, in: zone, of: cloud.sharedDB),
                  !payloads.isEmpty else { continue }
            await TradeLedger.complete(receiving: payloads,
                                       from: trade.friendName,
                                       giving: trade.giving.map(\.id),
                                       to: trade.friendName,
                                       in: context)
            completedTradeIDs.insert(trade.id)
            defaults.set(completedTradeIDs.map(\.uuidString), forKey: Keys.completed)
        }
        schedulePublish()
    }

    // MARK: Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    /// A local notification for each new request or acceptance. The first
    /// refresh on a device only records what is already there.
    private func announceNewActivity() {
        let firstRun = defaults.stringArray(forKey: Keys.announced) == nil
        var fresh: [(UUID, String)] = []
        for request in incomingRequests where !request.cancelled && !request.isExpired && !announcedIDs.contains(request.id) {
            fresh.append((request.id, "\(request.fromName) wants to trade"))
        }
        for reply in incomingReplies where reply.accepted && !announcedIDs.contains(reply.requestID) {
            let name = myRequests.first { $0.id == reply.requestID }?.toName ?? "A friend"
            fresh.append((reply.requestID, "\(name) said yes to your trade"))
        }
        for (id, title) in fresh {
            announcedIDs.insert(id)
            guard !firstRun else { continue }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = "Open Squish Index to see it."
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil))
        }
        defaults.set(announcedIDs.map(\.uuidString), forKey: Keys.announced)
    }

    // MARK: Cache

    private struct Cache: Codable {
        var friends: [Friend]
        var myRequests: [TradeRequest]
        var myReplies: [TradeReply]
        var incomingRequests: [TradeRequest]
        var incomingReplies: [TradeReply]
    }

    private var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("friends-cache.json")
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        friends = cache.friends
        myRequests = cache.myRequests
        myReplies = cache.myReplies
        incomingRequests = cache.incomingRequests
        incomingReplies = cache.incomingReplies
    }

    private func saveCache() {
        let cache = Cache(friends: friends, myRequests: myRequests, myReplies: myReplies,
                          incomingRequests: incomingRequests, incomingReplies: incomingReplies)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    // MARK: Helpers

    private static func name(of participant: CKShare.Participant) -> String {
        if let components = participant.userIdentity.nameComponents {
            let formatter = PersonNameComponentsFormatter()
            formatter.style = .short
            let formatted = formatter.string(from: components)
            if !formatted.isEmpty { return formatted }
        }
        return "Invited friend"
    }

    static func describe(_ error: Error) -> String {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .networkUnavailable, .networkFailure:
                return "You're offline. Showing what was here last time."
            case .notAuthenticated:
                return "Sign in to iCloud in Settings to use friends."
            case .quotaExceeded:
                return "Your iCloud storage is full, so your shelf can't update."
            case .serviceUnavailable, .requestRateLimited, .zoneBusy:
                return "iCloud is busy. Try again in a minute."
            default:
                break
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? "Something went wrong talking to iCloud."
    }
}
