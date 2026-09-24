//
//  MessageRecordHandling.swift
//  Longhorn Artists Connect
//
//  CloudKit-based messaging system with local persistence and push notifications
//

import Foundation
import CloudKit
import Combine
import CryptoKit
import UserNotifications

// MARK: - Messaging ID Normalization

/// Collapses a messaging participant ID to the raw CloudKit user record name.
///
/// A user's own ID (`container.userRecordID().recordName`) is the bare record name,
/// but IDs coming from the directory are the profile-record form
/// `UserProfile_<userRecordName>`. If those two forms aren't unified, the sender and
/// recipient compute *different* conversation thread IDs (see `deterministicID`) and
/// recipient queries never match — so messages silently fail to appear. Stripping the
/// `UserProfile_` prefix makes both forms resolve to the same identity.
func canonicalMessagingID(_ id: String) -> String {
    let prefix = "UserProfile_"
    return id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id
}

// MARK: - Blocked Users

/// Tracks users the current person has blocked. Blocking hides that user from the
/// Messages list and the New Message directory. IDs are stored in canonical form
/// (bare CloudKit user record name) so the two ID shapes — raw and
/// `UserProfile_`-prefixed — always resolve to the same identity. Persisted locally
/// so it applies immediately and survives relaunches.
final class BlockedUsersManager: ObservableObject {
    static let shared = BlockedUsersManager()

    /// Canonical CloudKit user record names of blocked users.
    @Published private(set) var blockedUserIDs: Set<String> = []

    private let storageKey = "blockedUserIDs"

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey) {
            blockedUserIDs = Set(saved)
        }
    }

    /// Whether the given messaging ID (raw or `UserProfile_`-prefixed) is blocked.
    func isBlocked(_ userID: String) -> Bool {
        blockedUserIDs.contains(canonicalMessagingID(userID))
    }

    func block(_ userID: String) {
        let id = canonicalMessagingID(userID)
        guard !id.isEmpty else { return }
        blockedUserIDs.insert(id)
        persist()
    }

    func unblock(_ userID: String) {
        blockedUserIDs.remove(canonicalMessagingID(userID))
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(blockedUserIDs), forKey: storageKey)
    }
}

// MARK: - Conversation Preferences (Mute / Pin)

/// Per-conversation preferences the current user controls: muting notifications and
/// pinning a thread to the top of the Messages list. Keyed by the other participant's
/// canonical CloudKit user record name (so the raw and `UserProfile_`-prefixed forms
/// match), and persisted locally.
final class ConversationPreferencesManager: ObservableObject {
    static let shared = ConversationPreferencesManager()

    @Published private(set) var mutedUserIDs: Set<String> = []
    @Published private(set) var pinnedUserIDs: Set<String> = []

    private let mutedKey = "mutedConversationUserIDs"
    private let pinnedKey = "pinnedConversationUserIDs"

    private init() {
        mutedUserIDs = Set(UserDefaults.standard.stringArray(forKey: mutedKey) ?? [])
        pinnedUserIDs = Set(UserDefaults.standard.stringArray(forKey: pinnedKey) ?? [])
    }

    func isMuted(_ userID: String) -> Bool { mutedUserIDs.contains(canonicalMessagingID(userID)) }
    func isPinned(_ userID: String) -> Bool { pinnedUserIDs.contains(canonicalMessagingID(userID)) }

    func toggleMute(_ userID: String) {
        let id = canonicalMessagingID(userID)
        guard !id.isEmpty else { return }
        if mutedUserIDs.contains(id) { mutedUserIDs.remove(id) } else { mutedUserIDs.insert(id) }
        UserDefaults.standard.set(Array(mutedUserIDs), forKey: mutedKey)
    }

    func togglePin(_ userID: String) {
        let id = canonicalMessagingID(userID)
        guard !id.isEmpty else { return }
        if pinnedUserIDs.contains(id) { pinnedUserIDs.remove(id) } else { pinnedUserIDs.insert(id) }
        UserDefaults.standard.set(Array(pinnedUserIDs), forKey: pinnedKey)
    }
}

// MARK: - Message Model

/// Represents a single message in a conversation
struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let conversationID: UUID
    var content: String
    var timestamp: Date
    let senderUserID: String // CKRecord.ID representation as string
    let recipientUserID: String
    var isRead: Bool
    var attachmentType: AttachmentType?
    var attachmentFileName: String? // Stored in CloudKit as CKAsset
    
    // CloudKit record metadata
    var recordName: String?
    var lastModified: Date?
    
    enum AttachmentType: String, Codable {
        case image
        case video
        case document
        /// A shared post. `attachmentFileName` holds the submission's UUID string.
        case post
    }

    /// Short text shown in a push banner: the message body, or a description of the
    /// attachment when there's no text.
    var notificationPreview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        switch attachmentType {
        case .image:    return "📷 Photo"
        case .video:    return "🎥 Video"
        case .document: return "📎 Attachment"
        case .post:     return "Shared a post"
        case .none:     return "New message"
        }
    }
    
    init(
        id: UUID = UUID(),
        conversationID: UUID,
        content: String,
        timestamp: Date = Date(),
        senderUserID: String,
        recipientUserID: String,
        isRead: Bool = false,
        attachmentType: AttachmentType? = nil,
        attachmentFileName: String? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        self.content = content
        self.timestamp = timestamp
        self.senderUserID = senderUserID
        self.recipientUserID = recipientUserID
        self.isRead = isRead
        self.attachmentType = attachmentType
        self.attachmentFileName = attachmentFileName
    }
}

// MARK: - Conversation Model

/// Represents a conversation between two users
struct Conversation: Identifiable, Codable, Equatable {
    let id: UUID
    let participant1UserID: String
    let participant2UserID: String
    var lastMessageTimestamp: Date?
    var lastMessagePreview: String?
    var unreadCount: Int
    
    // CloudKit record metadata
    var recordName: String?
    
    init(
        id: UUID = UUID(),
        participant1UserID: String,
        participant2UserID: String,
        lastMessageTimestamp: Date? = nil,
        lastMessagePreview: String? = nil,
        unreadCount: Int = 0
    ) {
        self.id = id
        self.participant1UserID = participant1UserID
        self.participant2UserID = participant2UserID
        self.lastMessageTimestamp = lastMessageTimestamp
        self.lastMessagePreview = lastMessagePreview
        self.unreadCount = unreadCount
    }
    
    /// Returns the other participant's user ID
    func otherParticipant(for currentUserID: String) -> String {
        // Compare canonically so a raw self-ID still matches a `UserProfile_`-prefixed
        // participant (and vice versa) on legacy records.
        let me = canonicalMessagingID(currentUserID)
        return me == canonicalMessagingID(participant1UserID) ? participant2UserID : participant1UserID
    }
}

// MARK: - Message Store

/// Manages message persistence, CloudKit sync, and notifications
@MainActor
class MessageStore: ObservableObject {
    static let shared = MessageStore()
    
    // MARK: - Published Properties
    
    @Published var conversations: [Conversation] = []
    @Published var messagesByConversation: [UUID: [Message]] = [:]
    @Published var isLoading: Bool = false
    @Published var error: MessageError?

    /// The current user's CloudKit record name, cached once resolved. Published so
    /// views deriving per-user state (e.g. the unread indicator) update when it
    /// first becomes known.
    @Published private(set) var currentUserID: String?

    /// Local file URLs for message attachments, keyed by message id. Populated when
    /// a message is sent (the file we uploaded) and when a CloudKit record's CKAsset
    /// is read back, so bubbles can render the real image/file instead of a
    /// placeholder. Backed by files in the on-disk attachments directory.
    @Published var attachmentURLs: [UUID: URL] = [:]

    /// Conversation IDs the user has "cleared" from the Messages list, mapped to
    /// the time they were cleared. Clearing only hides the thread — its messages are
    /// kept — and a thread reappears automatically once a newer message arrives.
    @Published private(set) var clearedConversations: [UUID: Date] = [:]
    
    // MARK: - Private Properties
    
    private let container: CKContainer
    private let publicDatabase: CKDatabase
    private var subscriptionID = "MessageSubscription"
    private var conversationSubscriptionID = "ConversationSubscription"
    private var cancellables = Set<AnyCancellable>()
    private let clearedConversationsKey = "clearedConversationTimestamps"
    
    // Local file storage
    private let conversationsFileURL: URL
    private let messagesFileURL: URL
    /// Directory holding downloaded/sent attachment files, named `<messageID>.<ext>`.
    private let attachmentsDir: URL
    
    // MARK: - Initialization
    
    private init() {
        // Initialize CloudKit
        self.container = CKContainer.default()
        self.publicDatabase = container.publicCloudDatabase
        
        // Setup local file URLs
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let messagingDir = documentsDir.appendingPathComponent("Messaging", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: messagingDir, withIntermediateDirectories: true)
        
        self.conversationsFileURL = messagingDir.appendingPathComponent("conversations.json")
        self.messagesFileURL = messagingDir.appendingPathComponent("messages.json")

        // Attachments live in their own subdirectory, one file per message.
        self.attachmentsDir = messagingDir.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

        // Load local data
        loadLocalData()
        loadAttachmentIndex()
        
        // Setup CloudKit subscriptions
        Task {
            await setupCloudKitSubscriptions()
        }
    }
    
    // MARK: - Public Methods

    /// The signed-in user's display name, used to label the push banner shown to the
    /// recipient. Falls back to a neutral label if the profile name isn't set yet.
    static func currentUserDisplayName() -> String {
        let first = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let last = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let name = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "New message" : name
    }

    /// Conversations to show in the Messages list: everything except threads the
    /// user has cleared, unless a newer message has arrived since it was cleared
    /// (in which case it comes back so new activity is never hidden).
    var visibleConversations: [Conversation] {
        conversations.filter { conversation in
            guard let clearedAt = clearedConversations[conversation.id] else { return true }
            if let lastTimestamp = conversation.lastMessageTimestamp {
                return lastTimestamp > clearedAt
            }
            return false
        }
    }

    /// Clears a conversation from the Messages list without deleting any messages.
    /// The thread stays in CloudKit and locally, and reappears if a newer message
    /// arrives.
    func clearConversation(_ conversationID: UUID) {
        clearedConversations[conversationID] = Date()
        saveClearedConversations()
    }

    /// Sends a new message
    func sendMessage(
        to recipientUserID: String,
        content: String,
        conversationID: UUID? = nil,
        attachmentURL: URL? = nil,
        attachmentType: Message.AttachmentType? = nil,
        // When sharing a post, its submission UUID string. Stored in
        // `attachmentFileName` (no CKAsset) so recipients can look up the post.
        sharedSubmissionID: String? = nil
    ) async throws -> Message {
        guard let currentUserID = await getCurrentUserID() else {
            throw MessageError.userNotAuthenticated
        }

        // Normalize the recipient to the raw record name so the stored message/thread
        // uses the same identity the recipient's own device reports for itself —
        // otherwise the message never reaches their queries.
        let recipient = canonicalMessagingID(recipientUserID)

        // You can't message yourself. A self-thread has both participants equal to
        // the current user, which makes every message look like both a sent and a
        // received message and shows up as a confusing "Unknown" conversation.
        guard recipient != currentUserID else {
            throw MessageError.cannotMessageSelf
        }

        // Find or create conversation. The thread is keyed by a deterministic ID
        // derived from the two participants, so `conversationID` (if passed) is
        // only a hint — both users always resolve to the same single thread.
        let conversation = try await findOrCreateConversation(
            participant1: currentUserID,
            participant2: recipient
        )

        // Create message
        let message = Message(
            conversationID: conversation.id,
            content: content,
            senderUserID: currentUserID,
            recipientUserID: recipient,
            attachmentType: attachmentType,
            attachmentFileName: sharedSubmissionID ?? attachmentURL?.lastPathComponent
        )
        
        // Save to CloudKit
        let savedMessage = try await saveMessageToCloudKit(message, attachmentURL: attachmentURL)

        // Keep a local copy of the attachment so the sender sees the real media
        // immediately, rather than waiting to download it back from CloudKit.
        if let attachmentURL {
            storeAttachment(for: savedMessage.id, from: attachmentURL)
        }

        // Save locally IMMEDIATELY, before touching the shared conversation record.
        // The message is already safely in CloudKit at this point, so a conflict while
        // updating the conversation's metadata must never keep it out of the sender's
        // own thread (which is exactly what happened when the oplock error propagated
        // before this line was reached).
        await saveLocally(message: savedMessage)

        // Update the conversation metadata (last message preview/timestamp, unread
        // count). This is best-effort: the message is already delivered, so a failure
        // here must not surface as a send error. `updateConversation` retries on
        // conflict internally; if it still fails we just log and let the next
        // successful update or sync correct the metadata.
        do {
            try await updateConversation(conversation.id, lastMessage: savedMessage)
        } catch {
            print("⚠️ Conversation metadata update failed (message already sent): \(error)")
        }

        return savedMessage
    }
    
    /// Fetches messages for a specific conversation
    func fetchMessages(for conversationID: UUID) async throws -> [Message] {
        isLoading = true
        defer { isLoading = false }
        
        // Check if we have local messages
        if let localMessages = messagesByConversation[conversationID], !localMessages.isEmpty {
            // Return local messages immediately, then sync in background
            Task {
                try? await syncMessagesFromCloudKit(for: conversationID)
            }
            return localMessages
        }
        
        // Fetch from CloudKit
        return try await syncMessagesFromCloudKit(for: conversationID)
    }
    
    /// Fetches all conversations for the current user
    func fetchConversations() async throws {
        guard let currentUserID = await getCurrentUserID() else {
            throw MessageError.userNotAuthenticated
        }

        isLoading = true
        defer { isLoading = false }

        // Match both the raw record name and the legacy `UserProfile_`-prefixed form so
        // conversations created before ID normalization still load.
        let idForms = [currentUserID, "UserProfile_\(currentUserID)"]
        let predicate = NSPredicate(
            format: "participant1UserID IN %@ OR participant2UserID IN %@",
            idForms,
            idForms
        )

        let query = CKQuery(recordType: "Conversation", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "lastMessageTimestamp", ascending: false)]
        
        do {
            let records = try await publicDatabase.records(matching: query).matchResults.compactMap { try? $0.1.get() }
            
            let fetchedConversations = records.compactMap { record -> Conversation? in
                return Conversation.fromCloudKitRecord(record)
            }
            
            self.conversations = fetchedConversations
            saveConversationsLocally()
            
        } catch {
            throw MessageError.cloudKitError(error)
        }
    }
    
    /// Marks a message as read
    func markMessageAsRead(_ messageID: UUID) async throws {
        guard var message = findMessage(by: messageID) else {
            throw MessageError.messageNotFound
        }
        
        message.isRead = true
        
        // Update in CloudKit
        if let recordName = message.recordName {
            let recordID = CKRecord.ID(recordName: recordName)
            
            do {
                let record = try await publicDatabase.record(for: recordID)
                record["isRead"] = true
                _ = try await publicDatabase.save(record)
                
                // Update locally
                await updateLocalMessage(message)
                
            } catch {
                throw MessageError.cloudKitError(error)
            }
        }
    }
    
    /// Marks all messages in a conversation as read
    func markConversationAsRead(_ conversationID: UUID) async throws {
        let messages = messagesByConversation[conversationID] ?? []

        let unreadMessages = messages.filter { !$0.isRead }

        for message in unreadMessages {
            try? await markMessageAsRead(message.id)
        }

        // Update conversation unread count locally…
        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[index].unreadCount = 0
            saveConversationsLocally()
        }

        // …and bring the home-screen badge down to match the new unread total.
        syncApplicationBadge()

        // …and in CloudKit. Without this, the shared Conversation record still
        // has unreadCount > 0, so the next `fetchConversations()` (e.g. when the
        // Network feed reloads) brings the unread dot right back even though the
        // chat has already been read.
        await resetUnreadCountInCloudKit(conversationID)
    }

    /// Best-effort reset of a conversation's `unreadCount` to 0 in CloudKit,
    /// retrying on the shared-record oplock conflict the same way
    /// `updateConversation` does. Failures are non-fatal — the local state is
    /// already correct and a later successful write will reconcile it.
    private func resetUnreadCountInCloudKit(_ conversationID: UUID) async {
        guard let recordName = conversations.first(where: { $0.id == conversationID })?.recordName else {
            return
        }
        let recordID = CKRecord.ID(recordName: recordName)

        var attemptsRemaining = 4
        while true {
            do {
                let record = try await publicDatabase.record(for: recordID)
                if (record["unreadCount"] as? Int ?? 0) == 0 { return }
                record["unreadCount"] = 0
                _ = try await publicDatabase.save(record)
                return
            } catch let error as CKError where error.code == .serverRecordChanged && attemptsRemaining > 1 {
                attemptsRemaining -= 1
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            } catch {
                print("⚠️ Failed to reset unread count in CloudKit: \(error)")
                return
            }
        }
    }
    
    /// Deletes a message (soft delete - only removes locally)
    func deleteMessage(_ messageID: UUID) async throws {
        guard let message = findMessage(by: messageID) else {
            throw MessageError.messageNotFound
        }
        
        let conversationID = message.conversationID
        
        // Remove from local storage
        messagesByConversation[conversationID]?.removeAll { $0.id == messageID }
        saveMessagesLocally()
    }

    // MARK: - Migration

    /// One-time cleanup for chats created by older builds, which keyed each
    /// conversation by a random UUID and could split a single chat into
    /// duplicate threads. This re-points any legacy messages onto the
    /// deterministic per-pair thread and deletes the leftover conversation
    /// records. Safe to call repeatedly — it no-ops after the first success.
    ///
    /// In the public database a user can only modify/delete records they
    /// created, so each participant's run cleans up their own duplicates;
    /// records owned by the other user are skipped without failing.
    func migrateLegacyConversationsIfNeeded() async {
        // Bumped when ID normalization landed so the merge re-runs and heals threads
        // that were split across the raw vs. `UserProfile_`-prefixed ID forms.
        let flagKey = "didMigrateMessagingIDs_v2"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        guard let currentUserID = await getCurrentUserID() else { return }

        do {
            // Every conversation this user participates in — including legacy records
            // stored under the `UserProfile_`-prefixed form.
            let idForms = [currentUserID, "UserProfile_\(currentUserID)"]
            let predicate = NSPredicate(
                format: "participant1UserID IN %@ OR participant2UserID IN %@",
                idForms, idForms
            )
            let query = CKQuery(recordType: "Conversation", predicate: predicate)
            let records = try await publicDatabase.records(matching: query)
                .matchResults.compactMap { try? $0.1.get() }
            let allConversations = records.compactMap { Conversation.fromCloudKitRecord($0) }

            // Group by the canonical deterministic ID for each participant pair.
            var groups: [UUID: [Conversation]] = [:]
            for convo in allConversations {
                let canonical = Conversation.deterministicID(
                    convo.participant1UserID,
                    convo.participant2UserID
                )
                groups[canonical, default: []].append(convo)
            }

            for (canonicalID, group) in groups {
                let legacy = group.filter { $0.id != canonicalID }
                guard !legacy.isEmpty else { continue } // already canonical

                // Make sure the canonical thread exists (created by either user).
                let pair = [group[0].participant1UserID, group[0].participant2UserID].sorted()
                _ = try? await findOrCreateConversation(participant1: pair[0], participant2: pair[1])

                // Re-point each duplicate's messages, then remove the duplicate.
                for convo in legacy {
                    await repointMessages(from: convo.id, to: canonicalID)
                    if let recordName = convo.recordName {
                        try? await publicDatabase.deleteRecord(
                            withID: CKRecord.ID(recordName: recordName)
                        )
                    }
                    messagesByConversation[convo.id] = nil
                }

                // Refresh the canonical thread's preview from its newest message.
                let canonicalMessages = (try? await syncMessagesFromCloudKit(for: canonicalID)) ?? []
                if let latest = canonicalMessages.last,
                   let recordName = conversations.first(where: { $0.id == canonicalID })?.recordName,
                   let record = try? await publicDatabase.record(
                       for: CKRecord.ID(recordName: recordName)
                   ) {
                    record["lastMessageTimestamp"] = latest.timestamp
                    record["lastMessagePreview"] = conversationPreview(for: latest)
                    _ = try? await publicDatabase.save(record)
                }
            }

            saveMessagesLocally()
            saveConversationsLocally()
            UserDefaults.standard.set(true, forKey: flagKey)

        } catch {
            // Leave the flag unset so a later launch can retry.
            print("⚠️ Conversation migration failed: \(error)")
        }
    }

    /// Rewrites the `conversationID` field of every message in `oldID` to point
    /// at `newID`. Messages authored by the other participant may be skipped due
    /// to public-database write permissions.
    private func repointMessages(from oldID: UUID, to newID: UUID) async {
        let predicate = NSPredicate(format: "conversationID == %@", oldID.uuidString)
        let query = CKQuery(recordType: "Message", predicate: predicate)
        guard let records = try? await publicDatabase.records(matching: query)
            .matchResults.compactMap({ try? $0.1.get() }) else { return }

        for record in records {
            record["conversationID"] = newID.uuidString
            _ = try? await publicDatabase.save(record)
        }
    }

    // MARK: - CloudKit Methods
    
    private func saveMessageToCloudKit(_ message: Message, attachmentURL: URL?) async throws -> Message {
        var updatedMessage = message
        
        let record = CKRecord(recordType: "Message", recordID: CKRecord.ID(recordName: message.id.uuidString))
        record["conversationID"] = message.conversationID.uuidString
        record["content"] = message.content
        record["timestamp"] = message.timestamp
        record["senderUserID"] = message.senderUserID
        record["recipientUserID"] = message.recipientUserID
        record["isRead"] = message.isRead
        // Fields that power the push banner on the recipient's device.
        record["senderName"] = MessageStore.currentUserDisplayName()
        record["messagePreview"] = message.notificationPreview
        
        if let attachmentType = message.attachmentType {
            record["attachmentType"] = attachmentType.rawValue
        }
        
        // Handle attachment
        if let attachmentURL = attachmentURL {
            let asset = CKAsset(fileURL: attachmentURL)
            record["attachment"] = asset
        }
        // Persist the file name / shared-post ID even when there's no CKAsset
        // (e.g. a shared post carries its submission UUID here).
        if let attachmentFileName = message.attachmentFileName {
            record["attachmentFileString"] = attachmentFileName
        }
        
        do {
            let savedRecord = try await publicDatabase.save(record)
            updatedMessage.recordName = savedRecord.recordID.recordName
            updatedMessage.lastModified = savedRecord.modificationDate
            
            return updatedMessage
            
        } catch {
            throw MessageError.cloudKitError(error)
        }
    }
    
    private func syncMessagesFromCloudKit(for conversationID: UUID) async throws -> [Message] {
        let predicate = NSPredicate(format: "conversationID == %@", conversationID.uuidString)
        let query = CKQuery(recordType: "Message", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        do {
            let records = try await publicDatabase.records(matching: query).matchResults.compactMap { try? $0.1.get() }

            let remoteMessages = records.compactMap { record -> Message? in
                guard let message = Message.fromCloudKitRecord(record) else { return nil }
                // Cache the attachment file locally the first time we see it, so the
                // bubble can render the real media. CKAsset file URLs from a query are
                // temporary, so copy into our own directory for stable access.
                if attachmentURLs[message.id] == nil,
                   let asset = record["attachment"] as? CKAsset,
                   let assetURL = asset.fileURL {
                    storeAttachment(for: message.id, from: assetURL)
                }
                return message
            }

            // Merge, don't replace. CloudKit's public-database queries are eventually
            // consistent, so a message saved seconds ago (e.g. a post just shared to
            // this person) often isn't returned by the query yet. Blindly overwriting
            // the local list with the server's would erase that just-sent message and
            // make it vanish from the thread. Keep any local message the query hasn't
            // returned yet; the server copy wins once it's indexed (dedup by id). This
            // is safe because messages are never individually deleted server-side.
            let remoteIDs = Set(remoteMessages.map { $0.id })
            let localOnly = (messagesByConversation[conversationID] ?? []).filter { !remoteIDs.contains($0.id) }
            let merged = (remoteMessages + localOnly).sorted { $0.timestamp < $1.timestamp }

            messagesByConversation[conversationID] = merged
            saveMessagesLocally()

            return merged

        } catch {
            throw MessageError.cloudKitError(error)
        }
    }
    
    private func findOrCreateConversation(
        participant1 rawParticipant1: String,
        participant2 rawParticipant2: String
    ) async throws -> Conversation {
        // Store participants in the canonical raw form so recipient queries (which use
        // the raw self-ID) match.
        let participant1 = canonicalMessagingID(rawParticipant1)
        let participant2 = canonicalMessagingID(rawParticipant2)

        // A single deterministic ID per participant pair. Both users compute the
        // same value, so a conversation always lives in one shared thread instead
        // of splitting into duplicate records.
        let conversationID = Conversation.deterministicID(participant1, participant2)
        let recordID = CKRecord.ID(recordName: conversationID.uuidString)

        // Already cached locally?
        if let existing = conversations.first(where: { $0.id == conversationID }) {
            return existing
        }

        // The other participant may have already created the shared record.
        if let record = try? await publicDatabase.record(for: recordID),
           let existing = Conversation.fromCloudKitRecord(record) {
            conversations.append(existing)
            saveConversationsLocally()
            return existing
        }

        // Otherwise create it.
        let conversation = Conversation(
            id: conversationID,
            participant1UserID: participant1,
            participant2UserID: participant2
        )

        let record = CKRecord(recordType: "Conversation", recordID: recordID)
        record["participant1UserID"] = participant1
        record["participant2UserID"] = participant2
        record["unreadCount"] = 0

        do {
            let savedRecord = try await publicDatabase.save(record)
            var savedConversation = conversation
            savedConversation.recordName = savedRecord.recordID.recordName

            conversations.append(savedConversation)
            saveConversationsLocally()

            return savedConversation

        } catch let error as CKError where error.code == .serverRecordChanged {
            // Race: the other participant created the same shared record first.
            // Fetch and use theirs so we still share a single thread.
            if let record = try? await publicDatabase.record(for: recordID),
               let existing = Conversation.fromCloudKitRecord(record) {
                conversations.append(existing)
                saveConversationsLocally()
                return existing
            }
            throw MessageError.cloudKitError(error)
        } catch {
            throw MessageError.cloudKitError(error)
        }
    }
    
    /// The text shown as a thread's preview in the Messages list. A shared post reads
    /// "Shared a film: Title" ("song" for music, "reel" for reels, etc.), resolving the
    /// title from the local submission store. Everything else uses the message text.
    /// If the post isn't available locally (e.g. on the recipient's device before it
    /// syncs), it falls back to a generic "Shared a post".
    private func conversationPreview(for message: Message) -> String {
        guard message.attachmentType == .post,
              let idString = message.attachmentFileName,
              let uuid = UUID(uuidString: idString) else {
            return message.content
        }
        guard let post = SubmissionStore_3_2.shared.approvedSubmissions.first(where: { $0.id == uuid }) else {
            return "Shared a post"
        }
        switch post.type {
        case .film:    return "Shared a film: \(post.title)"
        case .music:   return "Shared a song: \(post.title)"
        case .reel:    return "Shared a reel: \(post.title)"
        case .project: return "Shared a project: \(post.title)"
        case .event:   return "Shared an event: \(post.title)"
        case .photography: return "Shared photography: \(post.title)"
        case .design:  return "Shared a design: \(post.title)"
        }
    }

    private func updateConversation(_ conversationID: UUID, lastMessage: Message) async throws {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }),
              let recordName = conversations[index].recordName else {
            return
        }
        
        let recordID = CKRecord.ID(recordName: recordName)
        let currentUserID = await getCurrentUserID()
        let incrementsUnread = lastMessage.recipientUserID != currentUserID
        let preview = conversationPreview(for: lastMessage)

        // The Conversation record is shared by both participants and has a
        // deterministic ID, so concurrent sends (both people messaging at once, rapid
        // double-sends, or a migration touching it mid-send) collide on the same
        // record and CloudKit rejects the stale write with a "client oplock" error
        // (.serverRecordChanged). Retry that case the same way findOrCreateConversation
        // does: refetch the latest record and reapply our changes. Reapplying matters
        // for the unread increment in particular, since it must build on the current
        // server value rather than a stale one.
        var attemptsRemaining = 4
        while true {
            do {
                let record = try await publicDatabase.record(for: recordID)
                record["lastMessageTimestamp"] = lastMessage.timestamp
                record["lastMessagePreview"] = preview
                if incrementsUnread {
                    let currentUnread = record["unreadCount"] as? Int ?? 0
                    record["unreadCount"] = currentUnread + 1
                }

                _ = try await publicDatabase.save(record)

                // Update locally. NB: only the shared CloudKit record's unread count is
                // bumped above (for the recipient) — we must NOT bump our *own* local
                // copy here. This method only ever runs on the sender's device, so
                // incrementing the local count made the sender's own conversation show
                // as unread for a message they just sent.
                conversations[index].lastMessageTimestamp = lastMessage.timestamp
                conversations[index].lastMessagePreview = preview
                saveConversationsLocally()
                return

            } catch let error as CKError where error.code == .serverRecordChanged && attemptsRemaining > 1 {
                attemptsRemaining -= 1
                print("⏳ Conversation update conflict (oplock); refetching and retrying (\(attemptsRemaining) attempt(s) left)…")
                // Brief backoff so the competing write settles before we refetch.
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            } catch {
                throw MessageError.cloudKitError(error)
            }
        }
    }
    
    /// Ensures a `Conversation` exists locally for an incoming message, so a thread
    /// (especially a brand-new one) appears in the Messages list immediately.
    ///
    /// The `ConversationSubscription` only fires on record *update*, so the first
    /// message in a new thread never delivers a conversation push. We reconcile here:
    /// refresh the row if we already have it, otherwise fetch the shared Conversation
    /// record the sender created, and if that isn't visible yet (index lag) synthesize
    /// one from the message's participants. Its ID is deterministic, so a later
    /// `fetchConversations()` reconciles it with the authoritative record.
    private func ensureConversationExists(for message: Message) async {
        let conversationID = message.conversationID

        // Already known — just move its preview/timestamp forward if this is newer.
        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            if (conversations[index].lastMessageTimestamp ?? .distantPast) < message.timestamp {
                conversations[index].lastMessageTimestamp = message.timestamp
                conversations[index].lastMessagePreview = conversationPreview(for: message)
                saveConversationsLocally()
            }
            return
        }

        // Pull the shared Conversation record the sender created.
        let recordID = CKRecord.ID(recordName: conversationID.uuidString)
        if let record = try? await publicDatabase.record(for: recordID),
           let fetched = Conversation.fromCloudKitRecord(record) {
            conversations.append(fetched)
            saveConversationsLocally()
            return
        }

        // Not visible yet (CloudKit index lag): synthesize a placeholder so the
        // message is never stranded. A later fetchConversations replaces it with the
        // authoritative record.
        var synthesized = Conversation(
            id: conversationID,
            participant1UserID: message.senderUserID,
            participant2UserID: message.recipientUserID,
            lastMessageTimestamp: message.timestamp,
            lastMessagePreview: conversationPreview(for: message),
            unreadCount: 1
        )
        synthesized.recordName = conversationID.uuidString
        conversations.append(synthesized)
        saveConversationsLocally()
    }

    // MARK: - CloudKit Subscriptions

    private func setupCloudKitSubscriptions() async {
        // Subscribe to new messages
        await setupMessageSubscription()
        
        // Subscribe to conversation updates
        await setupConversationSubscription()
    }
    
    private func setupMessageSubscription() async {
        guard let currentUserID = await getCurrentUserID() else { return }
        
        // Create subscription for messages where current user is recipient
        let predicate = NSPredicate(format: "recipientUserID == %@", currentUserID)
        let subscription = CKQuerySubscription(
            recordType: "Message",
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        // Wake the app to sync the thread…
        notificationInfo.shouldSendContentAvailable = true
        // …and show the sender + message text in the banner. These keys reference the
        // Message record's String fields; CloudKit substitutes their values into the
        // "%@" format at delivery, so the real name/message appear in the notification.
        notificationInfo.titleLocalizationKey = "%@"
        notificationInfo.titleLocalizationArgs = ["senderName"]
        notificationInfo.alertLocalizationKey = "%@"
        notificationInfo.alertLocalizationArgs = ["messagePreview"]
        notificationInfo.soundName = "default"
        notificationInfo.shouldBadge = true
        // Carried in the push payload so the app can honor per-conversation mute in the
        // foreground without a follow-up fetch.
        notificationInfo.desiredKeys = ["senderUserID", "senderName", "messagePreview"]
        subscription.notificationInfo = notificationInfo
        
        do {
            _ = try await publicDatabase.save(subscription)
            print("✅ Message subscription created successfully")
        } catch {
            print("⚠️ Failed to create message subscription: \(error)")
        }
    }
    
    private func setupConversationSubscription() async {
        guard let currentUserID = await getCurrentUserID() else { return }
        
        let predicate = NSPredicate(
            format: "participant1UserID == %@ OR participant2UserID == %@",
            currentUserID,
            currentUserID
        )
        
        let subscription = CKQuerySubscription(
            recordType: "Conversation",
            predicate: predicate,
            subscriptionID: conversationSubscriptionID,
            options: [.firesOnRecordUpdate]
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        do {
            _ = try await publicDatabase.save(subscription)
            print("✅ Conversation subscription created successfully")
        } catch {
            print("⚠️ Failed to create conversation subscription: \(error)")
        }
    }
    
    /// Call this from AppDelegate when receiving remote notifications
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification else {
            return
        }
        
        // Fetch the new/updated record
        if let recordID = notification.recordID {
            do {
                let record = try await publicDatabase.record(for: recordID)
                
                if record.recordType == "Message" {
                    if let message = Message.fromCloudKitRecord(record) {
                        await saveLocally(message: message)
                        // Make sure the thread itself exists locally. The Conversation
                        // subscription only fires on record *update*, so the first
                        // message in a brand-new thread (common when someone shares a
                        // post with a person they've never messaged) pushes no
                        // conversation change — without this the message would arrive
                        // but no row would appear in the Messages list to open.
                        await ensureConversationExists(for: message)
                    }
                } else if record.recordType == "Conversation" {
                    if let conversation = Conversation.fromCloudKitRecord(record) {
                        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                            conversations[index] = conversation
                        } else {
                            conversations.append(conversation)
                        }
                        saveConversationsLocally()
                    }
                }
            } catch {
                print("⚠️ Failed to fetch record from notification: \(error)")
            }
        }
    }
    
    // MARK: - Local Persistence
    
    private func loadLocalData() {
        // Load conversations
        if let data = try? Data(contentsOf: conversationsFileURL),
           let loadedConversations = try? JSONDecoder().decode([Conversation].self, from: data) {
            self.conversations = loadedConversations
        }
        
        // Load messages
        if let data = try? Data(contentsOf: messagesFileURL),
           let loadedMessages = try? JSONDecoder().decode([UUID: [Message]].self, from: data) {
            self.messagesByConversation = loadedMessages
        }

        // Load the set of cleared (hidden-from-list) conversations.
        if let data = UserDefaults.standard.data(forKey: clearedConversationsKey),
           let loadedCleared = try? JSONDecoder().decode([UUID: Date].self, from: data) {
            self.clearedConversations = loadedCleared
        }
    }

    private func saveClearedConversations() {
        if let data = try? JSONEncoder().encode(clearedConversations) {
            UserDefaults.standard.set(data, forKey: clearedConversationsKey)
        }
    }
    
    private func saveConversationsLocally() {
        if let data = try? JSONEncoder().encode(conversations) {
            try? data.write(to: conversationsFileURL, options: .atomic)
        }
    }
    
    private func saveMessagesLocally() {
        if let data = try? JSONEncoder().encode(messagesByConversation) {
            try? data.write(to: messagesFileURL, options: .atomic)
        }
    }

    // MARK: - Attachment Files

    /// Rebuilds the in-memory attachment index from files already on disk, so
    /// previously sent/received attachments are available after a relaunch.
    private func loadAttachmentIndex() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: attachmentsDir, includingPropertiesForKeys: nil
        ) else { return }
        for url in files {
            // File name is "<messageID>.<ext>"; the stem is the message id.
            if let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) {
                attachmentURLs[id] = url
            }
        }
    }

    /// Copies an attachment file into the persistent attachments directory keyed by
    /// message id and records it in `attachmentURLs`. Returns the stored URL.
    @discardableResult
    private func storeAttachment(for messageID: UUID, from sourceURL: URL) -> URL? {
        let ext = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension
        let destination = attachmentsDir.appendingPathComponent("\(messageID.uuidString).\(ext)")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            attachmentURLs[messageID] = destination
            return destination
        } catch {
            print("⚠️ Failed to store attachment for \(messageID): \(error)")
            return nil
        }
    }
    
    private func saveLocally(message: Message) async {
        let conversationID = message.conversationID
        
        if messagesByConversation[conversationID] == nil {
            messagesByConversation[conversationID] = []
        }
        
        // Add or update message
        if let index = messagesByConversation[conversationID]?.firstIndex(where: { $0.id == message.id }) {
            messagesByConversation[conversationID]?[index] = message
        } else {
            messagesByConversation[conversationID]?.append(message)
        }
        
        // Sort by timestamp
        messagesByConversation[conversationID]?.sort { $0.timestamp < $1.timestamp }
        
        saveMessagesLocally()
    }
    
    private func updateLocalMessage(_ message: Message) async {
        let conversationID = message.conversationID
        
        if let index = messagesByConversation[conversationID]?.firstIndex(where: { $0.id == message.id }) {
            messagesByConversation[conversationID]?[index] = message
            saveMessagesLocally()
        }
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentUserID() async -> String? {
        // The record name is stable for the session, so cache it after the first
        // lookup — avoids repeat CloudKit round-trips and lets `unreadCount(for:)`
        // read it synchronously.
        if let currentUserID { return currentUserID }
        do {
            let recordID = try await container.userRecordID()
            currentUserID = recordID.recordName
            return recordID.recordName
        } catch {
            print("⚠️ Failed to get current user ID: \(error)")
            return nil
        }
    }

    /// The number of messages the current user has *received but not read* in a
    /// conversation, derived from local message state. Unlike the shared
    /// `Conversation.unreadCount` field (one counter for both participants, which
    /// can't represent "unread for me"), this counts only messages addressed to me
    /// that I haven't opened — so a message I *sent* never shows as unread on my own
    /// device, and a message I received shows as unread until I read it.
    func unreadCount(for conversationID: UUID) -> Int {
        guard let me = currentUserID else { return 0 }
        let mine = canonicalMessagingID(me)
        return (messagesByConversation[conversationID] ?? []).filter {
            !$0.isRead && canonicalMessagingID($0.recipientUserID) == mine
        }.count
    }
    
    /// Total messages addressed to the current user that they haven't read, across
    /// every conversation. Drives the home-screen app icon badge.
    var totalUnreadCount: Int {
        conversations.reduce(0) { $0 + unreadCount(for: $1.id) }
    }

    /// Sets the app icon badge to the real unread total.
    ///
    /// Messages are the only thing that badges the icon — feed/media pushes are
    /// silent (`shouldSendContentAvailable` only). CloudKit's `shouldBadge` only ever
    /// *increments* the badge on delivery and nothing decrements it, so without this
    /// the red badge lingered on the home screen after every message had been read.
    /// Call on scene-active and whenever unread state changes.
    func syncApplicationBadge() {
        let count = totalUnreadCount
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error {
                print("⚠️ Failed to update app badge: \(error.localizedDescription)")
            }
        }
    }

    private func findMessage(by id: UUID) -> Message? {
        for (_, messages) in messagesByConversation {
            if let message = messages.first(where: { $0.id == id }) {
                return message
            }
        }
        return nil
    }
}

// MARK: - CloudKit Extensions

extension Message {
    static func fromCloudKitRecord(_ record: CKRecord) -> Message? {
        guard
            let conversationIDString = record["conversationID"] as? String,
            let conversationID = UUID(uuidString: conversationIDString),
            let content = record["content"] as? String,
            let timestamp = record["timestamp"] as? Date,
            let senderUserID = record["senderUserID"] as? String,
            let recipientUserID = record["recipientUserID"] as? String
        else {
            return nil
        }
        
        let idString = record.recordID.recordName
        guard let id = UUID(uuidString: idString) else {
            return nil
        }
        
        let isRead = record["isRead"] as? Bool ?? false
        
        var attachmentType: AttachmentType?
        if let typeString = record["attachmentType"] as? String {
            attachmentType = AttachmentType(rawValue: typeString)
        }
        
        let attachmentFileName = record["attachmentFileString"] as? String
        
        var message = Message(
            id: id,
            conversationID: conversationID,
            content: content,
            timestamp: timestamp,
            senderUserID: senderUserID,
            recipientUserID: recipientUserID,
            isRead: isRead,
            attachmentType: attachmentType,
            attachmentFileName: attachmentFileName
        )
        
        message.recordName = record.recordID.recordName
        message.lastModified = record.modificationDate
        
        return message
    }
}

extension Conversation {
    /// A stable conversation ID derived from the two participant IDs. Sorting the
    /// pair makes the result independent of who initiates, so both users always
    /// resolve to the same single shared thread.
    static func deterministicID(_ participantA: String, _ participantB: String) -> UUID {
        // Normalize both IDs so the same person's raw and `UserProfile_`-prefixed forms
        // resolve to one shared thread on both participants' devices.
        let key = [canonicalMessagingID(participantA), canonicalMessagingID(participantB)]
            .sorted().joined(separator: "|")
        let digest = Insecure.MD5.hash(data: Data(key.utf8))
        var bytes = Array(digest) // MD5 is exactly 16 bytes — a full UUID.

        // Stamp the version/variant bits so it's a well-formed (v5-style) UUID.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let uuid: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }

    static func fromCloudKitRecord(_ record: CKRecord) -> Conversation? {
        guard
            let participant1UserID = record["participant1UserID"] as? String,
            let participant2UserID = record["participant2UserID"] as? String
        else {
            return nil
        }
        
        let idString = record.recordID.recordName
        guard let id = UUID(uuidString: idString) else {
            return nil
        }
        
        let lastMessageTimestamp = record["lastMessageTimestamp"] as? Date
        let lastMessagePreview = record["lastMessagePreview"] as? String
        let unreadCount = record["unreadCount"] as? Int ?? 0
        
        var conversation = Conversation(
            id: id,
            participant1UserID: participant1UserID,
            participant2UserID: participant2UserID,
            lastMessageTimestamp: lastMessageTimestamp,
            lastMessagePreview: lastMessagePreview,
            unreadCount: unreadCount
        )
        
        conversation.recordName = record.recordID.recordName
        
        return conversation
    }
}

// MARK: - Error Types

enum MessageError: LocalizedError {
    case userNotAuthenticated
    case cloudKitError(Error)
    case messageNotFound
    case conversationNotFound
    case attachmentError
    case cannotMessageSelf

    var errorDescription: String? {
        switch self {
        case .userNotAuthenticated:
            return "User is not authenticated with iCloud"
        case .cloudKitError(let error):
            return "CloudKit error: \(error.localizedDescription)"
        case .messageNotFound:
            return "Message not found"
        case .conversationNotFound:
            return "Conversation not found"
        case .attachmentError:
            return "Failed to handle attachment"
        case .cannotMessageSelf:
            return "You can't send a message to yourself."
        }
    }
}
