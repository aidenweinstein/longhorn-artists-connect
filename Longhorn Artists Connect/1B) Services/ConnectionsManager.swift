//
//  ConnectionsManager.swift
//  Longhorn Artists Connect
//
//  Private, mutual connections between Nexus members. Unlike Collaborators (earned by
//  sharing credits on a post), a connection is simply two people who agreed to connect —
//  a contact list, not a credential. It is never shown as a number anywhere, not even to
//  the person themselves; it only surfaces as a "Connections" section in the Directory,
//  a "connections only" feed filter on Home, and a notification when a connection posts.
//
//  Storage model: one `Connection` record per *direction*, written only by its sender
//  (`fromUserID` → `toUserID`). In the public database only a record's creator may
//  modify it, so the two sides never need to edit a shared record:
//    - I sent an edge, they haven't      → "Requested"
//    - They sent an edge, I haven't      → "Accept" (an incoming request)
//    - Both edges exist                  → "Connected"
//  Accepting means writing my own edge back; withdrawing or disconnecting means deleting
//  my own edge. `kind` on the record ("request" / "accept") lets the recipient's push
//  banner say which of the two just happened.
//
//  Record `Connection` (create in CloudKit Dashboard, Development AND Production):
//    fromUserID  String (queryable)     toUserID  String (queryable)
//    fromName    String                 kind      String (queryable)
//    createdDate Date/Time
//

import Foundation
import CloudKit
import Combine
import UserNotifications

/// Where two people stand, from the current user's point of view.
enum ConnectionState: Equatable {
    /// No edge either way — the button reads "Connect".
    case none
    /// I asked and they haven't answered — "Requested".
    case requested
    /// They asked me — "Accept".
    case incoming
    /// Both edges exist — "Connected".
    case connected
}

@MainActor
final class ConnectionsManager: ObservableObject {
    static let shared = ConnectionsManager()

    /// Canonical IDs of everyone I've written an edge to: requests I've sent plus
    /// requests I've accepted.
    @Published private(set) var outgoingIDs: Set<String> = []
    /// Canonical IDs of everyone who has written an edge to me.
    @Published private(set) var incomingIDs: Set<String> = []
    /// IDs with a save or delete in flight, so buttons can ignore double taps.
    @Published private(set) var busyIDs: Set<String> = []
    @Published private(set) var isLoading = false
    /// The signed-in user's raw CloudKit record name, cached once resolved.
    @Published private(set) var currentUserID: String?

    /// The subscription IDs this manager owns, so the app delegate can route their pushes here.
    static let subscriptionIDs: Set<String> = [requestSubscriptionID, acceptSubscriptionID]
    private static let requestSubscriptionID = "ConnectionRequestSubscription"
    private static let acceptSubscriptionID = "ConnectionAcceptSubscription"

    private let container = CKContainer.default()
    private var database: CKDatabase { container.publicCloudDatabase }

    /// Per-environment so Development and Production connections never mix.
    private var cacheKey: String { "\(CloudKitEnvironmentDetector.localCachePrefix)connections" }
    private var knownPostIDsKey: String { "\(CloudKitEnvironmentDetector.localCachePrefix)connectionKnownPostIDs" }

    private init() {
        loadCache()
        Task {
            await refresh()
            await setupSubscriptions()
        }
    }

    // MARK: - Reading

    /// People connected both ways.
    var connectedIDs: Set<String> { outgoingIDs.intersection(incomingIDs) }

    /// People who asked to connect and are still waiting on me (blocked people excluded).
    var pendingIncomingIDs: Set<String> {
        incomingIDs.subtracting(outgoingIDs).filter { !BlockedUsersManager.shared.isBlocked($0) }
    }

    func state(for userID: String) -> ConnectionState {
        let id = canonicalMessagingID(userID)
        switch (outgoingIDs.contains(id), incomingIDs.contains(id)) {
        case (true, true):   return .connected
        case (true, false):  return .requested
        case (false, true):  return .incoming
        case (false, false): return .none
        }
    }

    func isConnected(_ userID: String) -> Bool { state(for: userID) == .connected }
    func isBusy(_ userID: String) -> Bool { busyIDs.contains(canonicalMessagingID(userID)) }

    /// Directory entries for my connections, in directory order.
    func connectedUsers(in directory: [DirectoryUser]) -> [DirectoryUser] {
        let ids = connectedIDs
        guard !ids.isEmpty else { return [] }
        return directory.filter { ids.contains($0.messagingUserID) }
    }

    /// Directory entries for people whose request I haven't answered.
    func pendingRequesters(in directory: [DirectoryUser]) -> [DirectoryUser] {
        let ids = pendingIncomingIDs
        guard !ids.isEmpty else { return [] }
        return directory.filter { ids.contains($0.messagingUserID) }
    }

    // MARK: - Writing

    /// Sends a request to `user`, or accepts theirs if one is waiting. Optimistic: the
    /// button flips immediately and reverts only if CloudKit rejects the save.
    func connect(with user: DirectoryUser) async {
        guard let me = await resolveCurrentUserID() else { return }
        let other = user.messagingUserID
        guard !other.isEmpty, other != me, !busyIDs.contains(other) else { return }

        let isAcceptance = incomingIDs.contains(other)
        busyIDs.insert(other)
        defer { busyIDs.remove(other) }
        outgoingIDs.insert(other)
        saveCache()

        // So the other person's answer (or their request) can reach this device.
        PushAuthorization.request()

        let record = CKRecord(recordType: CloudKitRecordTypes.connection,
                              recordID: Self.recordID(from: me, to: other))
        record["fromUserID"] = me as CKRecordValue
        record["toUserID"] = other as CKRecordValue
        record["fromName"] = Self.currentUserDisplayName() as CKRecordValue
        record["kind"] = (isAcceptance ? "accept" : "request") as CKRecordValue
        record["createdDate"] = Date() as CKRecordValue

        do {
            // `.allKeys` overwrites a stale edge with the same deterministic ID instead
            // of failing with a conflict.
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        } catch {
            outgoingIDs.remove(other)
            saveCache()
            print("⚠️ Couldn't save connection to \(user.fullName): \(error.localizedDescription)")
        }
    }

    /// Withdraws my request to, or disconnects from, `userID` by deleting my own edge.
    func disconnect(from userID: String) async {
        guard let me = await resolveCurrentUserID() else { return }
        let other = canonicalMessagingID(userID)
        guard !other.isEmpty, !busyIDs.contains(other) else { return }

        busyIDs.insert(other)
        defer { busyIDs.remove(other) }
        let hadEdge = outgoingIDs.remove(other) != nil
        saveCache()

        do {
            _ = try await database.deleteRecord(withID: Self.recordID(from: me, to: other))
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone — nothing to undo.
        } catch {
            if hadEdge {
                outgoingIDs.insert(other)
                saveCache()
            }
            print("⚠️ Couldn't remove connection: \(error.localizedDescription)")
        }
    }

    // MARK: - Sync

    /// Reloads both edge sets from CloudKit. A failed query keeps the cached set rather
    /// than wiping it, so a network blip never makes everyone look disconnected.
    func refresh() async {
        guard let me = await resolveCurrentUserID() else { return }
        isLoading = true
        defer { isLoading = false }

        async let outgoing = fetchIDs(where: "fromUserID", equals: me, returning: "toUserID")
        async let incoming = fetchIDs(where: "toUserID", equals: me, returning: "fromUserID")
        let (fetchedOutgoing, fetchedIncoming) = await (outgoing, incoming)

        if let fetchedOutgoing { outgoingIDs = fetchedOutgoing }
        if let fetchedIncoming { incomingIDs = fetchedIncoming }
        saveCache()
    }

    /// The `returning` field of every `Connection` whose `field` equals `value`, in
    /// canonical form. Nil when the query failed (including the record type not existing
    /// yet in this environment).
    private func fetchIDs(where field: String, equals value: String, returning key: String) async -> Set<String>? {
        let query = CKQuery(recordType: CloudKitRecordTypes.connection,
                            predicate: NSPredicate(format: "%K == %@", field, value))
        var ids = Set<String>()
        do {
            var (results, cursor) = try await database.records(matching: query, desiredKeys: [key], resultsLimit: 200)
            while true {
                for (_, result) in results {
                    if let record = try? result.get(), let id = record[key] as? String {
                        ids.insert(canonicalMessagingID(id))
                    }
                }
                guard let next = cursor else { break }
                (results, cursor) = try await database.records(continuingMatchFrom: next, desiredKeys: [key], resultsLimit: 200)
            }
            return ids
        } catch {
            print("⚠️ Connections fetch (\(field)) failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Push Subscriptions

    /// Two subscriptions on edges written *to* me, split by `kind` so the banner can say
    /// "sent you a connection request" vs. "accepted your connection request".
    private func setupSubscriptions() async {
        guard let me = await resolveCurrentUserID() else { return }
        await saveSubscription(id: Self.requestSubscriptionID, kind: "request", me: me,
                               alert: "%@ sent you a connection request")
        await saveSubscription(id: Self.acceptSubscriptionID, kind: "accept", me: me,
                               alert: "%@ accepted your connection request")
    }

    private func saveSubscription(id: String, kind: String, me: String, alert: String) async {
        let predicate = NSPredicate(format: "toUserID == %@ AND kind == %@", me, kind)
        let subscription = CKQuerySubscription(
            recordType: CloudKitRecordTypes.connection,
            predicate: predicate,
            subscriptionID: id,
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        // Wake the app to refresh the edge sets, and show who it was. CloudKit
        // substitutes the record's `fromName` into the "%@".
        info.shouldSendContentAvailable = true
        info.alertLocalizationKey = alert
        info.alertLocalizationArgs = ["fromName"]
        info.soundName = "default"
        info.desiredKeys = ["fromUserID", "fromName", "kind"]
        subscription.notificationInfo = info
        do {
            _ = try await database.save(subscription)
        } catch {
            print("⚠️ Couldn't save \(id): \(error.localizedDescription)")
        }
    }

    // MARK: - "A connection posted" notifications

    /// Call after each feed sync with the full approved list. Posts the local
    /// notification "<name> posted a new film" for every post that wasn't in the list
    /// last time and was made by one of my connections. The first call only seeds the
    /// known set, so installing the app never replays the whole feed as notifications.
    func noticeNewPosts(_ posts: [Submission], directory: [DirectoryUser]) {
        let defaults = UserDefaults.standard
        let known = Set(defaults.stringArray(forKey: knownPostIDsKey) ?? [])
        let currentIDs = posts.map { $0.id.uuidString }
        // Union rather than replace: a partial fetch (one record type failing) must not
        // make its posts look brand-new when they come back.
        defaults.set(Array(known.union(currentIDs)), forKey: knownPostIDsKey)
        guard !known.isEmpty else { return }

        let connected = connectedIDs
        guard !connected.isEmpty else { return }

        // Posts only carry the poster's name, so match it to a connected member's name.
        var connectedByName: [String: DirectoryUser] = [:]
        for user in directory where connected.contains(user.messagingUserID) {
            connectedByName[Collaborator.nameKey(for: user.fullName)] = user
        }
        guard !connectedByName.isEmpty else { return }

        // Ignore anything older than a few days so a long-offline device doesn't
        // deliver a stack of stale banners at once.
        let cutoff = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        for post in posts where !known.contains(post.id.uuidString) && post.createdDate >= cutoff {
            guard let poster = connectedByName[Collaborator.nameKey(for: post.submittedBy)],
                  poster.messagingUserID != currentUserID else { continue }
            scheduleNotification(for: post, by: poster)
        }
    }

    private func scheduleNotification(for post: Submission, by poster: DirectoryUser) {
        let content = UNMutableNotificationContent()
        // Shown as a communication notification (see `CommunicationNotifications`): the
        // poster's profile picture is the big icon with the Nexus icon small in its
        // corner, like a message from them. The system puts the sender's name in the
        // title, so the "posted a new …" phrase moves into the body.
        let kind = post.type.displayName.lowercased()
        let title = post.title.trimmingCharacters(in: .whitespaces)
        content.title = poster.fullName
        content.body = title.isEmpty
            ? "Posted a new \(kind). Open Nexus to take a look."
            : "Posted a new \(kind): \(title)"
        content.sound = .default
        content.userInfo = ["postID": post.id.uuidString]

        let identifier = "connection-post-\(post.id.uuidString)"
        Task {
            let styled = await CommunicationNotifications.styled(
                content,
                senderID: poster.messagingUserID,
                senderName: poster.fullName,
                senderImageData: poster.profileImageData,
                // Separate from the DM thread so post banners don't stack with messages.
                conversationID: "post-\(poster.messagingUserID)"
            )
            let request = UNNotificationRequest(identifier: identifier, content: styled, trigger: nil)
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print("⚠️ Couldn't post connection notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    /// Deterministic record name for the edge `from` → `to`, so a re-request after a
    /// withdrawal overwrites instead of duplicating.
    private static func recordID(from: String, to: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "Connection_\(from)_\(to)")
    }

    private func resolveCurrentUserID() async -> String? {
        if let currentUserID { return currentUserID }
        do {
            let id = try await container.userRecordID().recordName
            currentUserID = id
            return id
        } catch {
            print("⚠️ Connections: couldn't resolve current user: \(error.localizedDescription)")
            return nil
        }
    }

    /// The signed-in user's name as it should appear in the other person's push banner.
    private static func currentUserDisplayName() -> String {
        let first = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let last = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let name = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Someone" : name
    }

    private func loadCache() {
        guard let dict = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: [String]] else { return }
        outgoingIDs = Set(dict["out"] ?? [])
        incomingIDs = Set(dict["in"] ?? [])
    }

    private func saveCache() {
        UserDefaults.standard.set(["out": Array(outgoingIDs), "in": Array(incomingIDs)], forKey: cacheKey)
    }
}
