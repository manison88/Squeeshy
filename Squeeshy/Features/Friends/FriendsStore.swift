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
    /// Squeeshies that went to friends, newest first. Kept outside SwiftData so a
    /// traded squeeshy leaves every shelf, tint and share card with no filtering.
    private(set) var tradedAway: [TradedEntry] = TradedArchive.load()
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

    #if DEBUG
    /// Debug builds: stands in for iCloud when `FriendsDebug.isOn`.
    private(set) var simulator: FriendsSimulator? = nil
    private var simulatorTask: Task<Void, Never>? = nil
    #endif

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
        waitingForMe.count + inProgress.filter { !$0.iHandedOver || $0.isReadyToComplete }.count
    }

    // MARK: Filing

    /// Screens that can safely have squeeshies disappear under them.
    ///
    /// Filing a finished trade deletes what was given away, and the field and
    /// detail screens hold snapshots of the squeeshies they show — reading a
    /// deleted model from one of those crashes. So finished trades are filed only
    /// while a friends screen is on show (they are counted in the badge until
    /// then, which is what brings the user here).
    private var filingHolds = 0

    func beginFiling() {
        filingHolds += 1
        Task { await completeReadyTrades() }
    }

    func endFiling() {
        filingHolds = max(0, filingHolds - 1)
    }

    var openOutgoingCount: Int { trades.filter { $0.state == .waitingForReply }.count }
    nonisolated static let maxOpenOutgoing = 5

    /// This user's CloudKit user record name, once known. Shared with nearby
    /// devices at a trade table so they can tell a friend from a stranger.
    var myUserID: String? { myID }

    /// Lineage IDs this user has put up in trades that could still complete.
    /// A squeeshy can only be promised once, or it could be handed to two people.
    var promisedIDs: Set<String> {
        Set(trades.filter { $0.state == .waitingForReply || $0.state == .inProgress }
            .flatMap(\.giving).map(\.id))
    }

    func reloadTradedAway() {
        tradedAway = TradedArchive.load()
    }

    func friend(_ id: String) -> Friend? { friends.first { $0.id == id } }

    func trades(with friendID: String) -> [Trade] { trades.filter { $0.friendID == friendID } }

    // MARK: Lifecycle

    func attach(_ container: ModelContainer) {
        modelContainer = container
    }

    private var context: ModelContext? { modelContainer?.mainContext }

    /// Safe to call repeatedly; re-runs the account check each time.
    func start() async {
        #if DEBUG
        if FriendsDebug.isOn {
            await startSimulation()
            return
        }
        #endif
        #if targetEnvironment(simulator)
        // project.yml turns signing off for the simulator SDK, so a simulator build
        // carries no iCloud entitlement, and the first touch of a CKContainer raises
        // an exception. Real friends need a device; the debug simulation does not.
        availability = .unavailable
        problem = "Friends need iCloud, which the Simulator build can't use because it isn't signed. Turn on the debug simulation above, or run on a device."
        return
        #else
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
        #endif
    }

    // MARK: Refresh

    func refresh() async {
        #if DEBUG
        if let simulator {
            refreshSimulation(simulator)
            await completeReadyTrades()
            return
        }
        #endif
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
        #if DEBUG
        if simulator != nil { return }
        #endif
        guard availability == .available, myID != nil, let context else { return }
        // Traded-away squeeshies are deleted, so everything in the store is held.
        let held = (try? context.fetch(FetchDescriptor<Squishy>())) ?? []

        // Everything read from the models happens here, before any `await`: a trade
        // can delete one of them while the upload is in flight, and reading a
        // deleted model crashes.
        var saves: [CKRecord] = []
        var thumbnailJobs: [(record: CKRecord, photo: String?)] = []
        var revisions: [String: String] = [:]
        for squishy in held {
            let name = "specimen-" + squishy.lineageID.uuidString
            let revision = squishy.shelfRevision
            revisions[name] = revision
            guard publishedRevisions[name] != revision else { continue }
            let record = cloud.specimenRecord(squishy, thumbnail: nil)
            saves.append(record)
            // Only re-send the picture when the cut-out itself changed.
            let photoSegment = "photo:" + (squishy.photoFilename ?? "-")
            if !(publishedRevisions[name] ?? "").hasSuffix(photoSegment) {
                thumbnailJobs.append((record, squishy.photoFilename))
            }
        }
        let deletes = publishedRevisions.keys
            .filter { revisions[$0] == nil }
            .map(cloud.recordID)
        if hasDisplayName {
            saves.append(cloud.profileRecord(displayName: displayName))
        }
        guard !saves.isEmpty || !deletes.isEmpty else { return }

        // Thumbnails are decoded, resized and encoded off the main actor, from file
        // names only — a whole collection's worth would otherwise stall the UI.
        let files = thumbnailJobs.compactMap(\.photo)
        let urls: [String: URL] = await Task.detached(priority: .utility) {
            var out: [String: URL] = [:]
            for file in files {
                guard let data = Squishy.thumbnailData(forPhoto: file) else { continue }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("thumb-\(file)")
                if (try? data.write(to: url, options: .atomic)) != nil { out[file] = url }
            }
            return out
        }.value
        for job in thumbnailJobs {
            if let photo = job.photo, let url = urls[photo] {
                job.record[ShelfCloud.Key.thumb] = CKAsset(fileURL: url)
            } else if job.photo == nil {
                // Became a drawn squeeshy: clear the old picture.
                job.record[ShelfCloud.Key.thumb] = nil
            }
        }

        do {
            try await cloud.save(saves, deleting: deletes)
            publishedRevisions = revisions
        } catch {
            problem = Self.describe(error)
        }
    }

    // MARK: Friending

    /// The share friends are invited to. Created on first use.
    func shareForInvite() async throws -> CKShare {
        guard availability == .available else { throw TradeError.notReady }
        if let share { return share }
        // The zone has to exist before a zone-wide share can be saved into it. It
        // normally does from `start()`, but not if that step failed earlier.
        try await cloud.ensureZone()
        if let existing = try await cloud.fetchShare() {
            share = existing
            return existing
        }
        let title = hasDisplayName ? "\(displayName)'s squeeshies" : "Squeeshy shelf"
        let created = try await cloud.createShare(title: title)
        share = created
        requestNotificationPermission()
        // Not awaited: the invite sheet must not wait on a whole collection's upload.
        schedulePublish()
        return created
    }

    /// Shows a failure on the Friends screen rather than letting it vanish.
    func report(_ error: Error) {
        problem = Self.describe(error)
    }

    func report(_ message: String) {
        problem = message
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
        #if DEBUG
        if let simulator {
            simulator.unpair(friend.id)
            friends.removeAll { $0.id == friend.id }
            return
        }
        #endif
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
        case alreadyPromised

        var errorDescription: String? {
            switch self {
            case .notReady: "Friends need iCloud. Check you're signed in, then try again."
            case .tooManyOpen: "You have \(FriendsStore.maxOpenOutgoing) requests waiting already. Wait for a reply or cancel one."
            case .nothingOffered: "Pick at least one of yours to offer."
            case .itemGone: "One of those squeeshies isn't in your collection any more."
            case .alreadyPromised: "One of those squeeshies is already in another trade. Cancel that one first."
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
        guard promisedIDs.isDisjoint(with: offered.map(\.lineageID.uuidString)) else { throw TradeError.alreadyPromised }

        let request = TradeRequest(
            id: UUID(),
            fromID: myID,
            fromName: hasDisplayName ? displayName : "A friend",
            toID: friend.id,
            toName: friend.name,
            offered: offered.map(\.line),
            wanted: wanted.map { TradeLine(id: $0.id, name: $0.name, hue: $0.hue, speciesRaw: $0.speciesRaw) },
            line: line?.rawValue,
            createdAt: .now,
            handedOver: false,
            cancelled: false)
        #if DEBUG
        if let simulator {
            simulator.recordSent(request, payloads: offered.map(SpecimenPayload.init))
            myRequests.append(request)
            simulateSoon()
            return
        }
        #endif
        let payload = try PayloadFile.write(offered.map(SpecimenPayload.init))
        try await cloud.save([cloud.requestRecord(request, payload: payload)])
        myRequests.append(request)
        saveCache()
    }

    func respond(to trade: Trade, accept: Bool) async throws {
        guard let myID, let context else { throw TradeError.notReady }
        var payloadURL: URL?
        var giving: [Squishy] = []
        if accept {
            giving = TradeLedger.held(trade.giving.map(\.id), in: context)
            guard giving.count == trade.giving.count else { throw TradeError.itemGone }
            guard promisedIDs.isDisjoint(with: trade.giving.map(\.id)) else { throw TradeError.alreadyPromised }
            payloadURL = try PayloadFile.write(giving.map(SpecimenPayload.init))
        }
        let reply = TradeReply(requestID: trade.request.id,
                               fromID: myID,
                               toID: trade.request.fromID,
                               accepted: accept,
                               handedOver: false,
                               repliedAt: .now)
        #if DEBUG
        if let simulator {
            simulator.recordReply(reply, payloads: giving.map(SpecimenPayload.init))
            myReplies.removeAll { $0.requestID == reply.requestID }
            myReplies.append(reply)
            simulateSoon()
            return
        }
        #endif
        try await cloud.save([cloud.replyRecord(reply, payload: payloadURL)])
        myReplies.removeAll { $0.requestID == reply.requestID }
        myReplies.append(reply)
        saveCache()
    }

    func markHandedOver(_ trade: Trade) async throws {
        #if DEBUG
        if simulator != nil {
            switch trade.direction {
            case .outgoing:
                if let index = myRequests.firstIndex(where: { $0.id == trade.request.id }) {
                    myRequests[index].handedOver = true
                }
            case .incoming:
                if let index = myReplies.firstIndex(where: { $0.requestID == trade.request.id }) {
                    myReplies[index].handedOver = true
                }
            }
            simulator?.note("You handed yours over")
            await refresh()
            simulateSoon()
            return
        }
        #endif
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
        #if DEBUG
        if simulator == nil {
            try await cloud.save([cloud.requestFlags(id: trade.request.id, handedOver: false, cancelled: true)])
        }
        #else
        try await cloud.save([cloud.requestFlags(id: trade.request.id, handedOver: false, cancelled: true)])
        #endif
        if let index = myRequests.firstIndex(where: { $0.id == trade.request.id }) {
            myRequests[index].cancelled = true
        }
        saveCache()
    }

    /// Files every trade both sides have handed over. The payload comes from
    /// the *other* person's record, which lives in their zone.
    private func completeReadyTrades() async {
        guard let context, filingHolds > 0 else { return }
        for trade in trades where trade.isReadyToComplete && !completing.contains(trade.id) {
            completing.insert(trade.id)
            defer { completing.remove(trade.id) }
            let payloads: [SpecimenPayload]
            #if DEBUG
            if let simulator {
                payloads = simulator.payload(for: trade.id)
            } else {
                payloads = await fetchPayload(for: trade)
            }
            #else
            payloads = await fetchPayload(for: trade)
            #endif
            guard !payloads.isEmpty else { continue }
            TradeLedger.complete(receiving: payloads,
                                       from: trade.friendName,
                                       giving: trade.giving.map(\.id),
                                       to: trade.friendName,
                                       in: context)
            completedTradeIDs.insert(trade.id)
            defaults.set(completedTradeIDs.map(\.uuidString), forKey: Keys.completed)
        }
        schedulePublish()
    }

    private func fetchPayload(for trade: Trade) async -> [SpecimenPayload] {
        let zone = CKRecordZone.ID(zoneName: ShelfCloud.zoneName, ownerName: trade.friendID)
        let recordName = (trade.direction == .outgoing ? "reply-" : "request-") + trade.request.id.uuidString
        return (try? await cloud.payload(recordName: recordName, in: zone, of: cloud.sharedDB)) ?? []
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
        #if DEBUG
        // Simulated friends must never leak into the real cache.
        if simulator != nil { return }
        #endif
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
            case .badContainer, .missingEntitlement:
                return "This build isn't set up for iCloud yet: the container iCloud.com.squeeshy.app needs to exist and be ticked under Signing & Capabilities → iCloud."
            case .permissionFailure:
                return "iCloud refused permission for this account. Check Settings → your name → iCloud, and that iCloud Drive is on."
            case .accountTemporarilyUnavailable:
                return "iCloud needs attention on this device. Open Settings and check your Apple Account."
            default:
                // Anything else: say what iCloud said, so it can be diagnosed.
                return "iCloud said: \(ckError.localizedDescription) (code \(ckError.code.rawValue))"
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? "Something went wrong: \(error.localizedDescription)"
    }
}

// MARK: - Debug simulation

#if DEBUG
extension FriendsStore {
    var isSimulating: Bool { simulator != nil }

    /// Swaps iCloud for simulated friends. The real cache is left on disk and
    /// comes back when the simulation stops.
    fileprivate func startSimulation() async {
        if simulator == nil {
            simulator = FriendsSimulator()
            friends = []
            myRequests = []
            myReplies = []
            incomingRequests = []
            incomingReplies = []
            pendingInvites = []
            requestNotificationPermission()
        }
        availability = .available
        myID = "sim-me"
        problem = nil
        refreshSimulation(simulator!)
        await completeReadyTrades()
        // Stands in for CloudKit's silent pushes.
        simulatorTask?.cancel()
        simulatorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.refresh()
            }
        }
    }

    fileprivate func refreshSimulation(_ simulator: FriendsSimulator) {
        simulator.tick(myRequests: myRequests, myReplies: myReplies)
        friends = simulator.friends
        incomingRequests = simulator.requests
        incomingReplies = simulator.replies
        lastRefresh = .now
        announceNewActivity()
    }

    fileprivate func simulateSoon() {
        Task { await refresh() }
    }

    func setSimulation(_ on: Bool) async {
        FriendsDebug.isOn = on
        guard !on else { return await start() }
        simulatorTask?.cancel()
        simulatorTask = nil
        simulator = nil
        myID = nil
        friends = []
        myRequests = []
        myReplies = []
        incomingRequests = []
        incomingReplies = []
        loadCache()
        await start()
    }

    func debugPairFriend() {
        guard let simulator else { return }
        let friend = simulator.pairFriend()
        friends = simulator.friends
        pendingShareBack = nil
        _ = friend
    }

    /// Returns a problem to show, or nil.
    func debugIncomingRequest() -> String? {
        guard let simulator, let myID, let context else { return "Simulation is off." }
        let problem = simulator.sendIncomingRequest(to: myID, myName: displayName, context: context)
        simulateSoon()
        return problem
    }

    /// Makes simulated friends act now, whatever their settings.
    func debugForceFriends() {
        guard let simulator else { return }
        simulator.tick(myRequests: myRequests, myReplies: myReplies, force: true)
        simulateSoon()
    }

    func debugSeedShelf(_ count: Int = 6) {
        guard let context else { return }
        FriendsSimulator.seedMyShelf(count: count, in: context)
        simulator?.note("Added \(count) sample squeeshies to your collection")
    }
}
#endif
