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
        return currentUserID == participant1UserID ? participant2UserID : participant1UserID
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
    
    // MARK: - Private Properties
    
    private let container: CKContainer
    private let publicDatabase: CKDatabase
    private var subscriptionID = "MessageSubscription"
    private var conversationSubscriptionID = "ConversationSubscription"
    private var cancellables = Set<AnyCancellable>()
    
    // Local file storage
    private let conversationsFileURL: URL
    private let messagesFileURL: URL
    
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
        
        // Load local data
        loadLocalData()
        
        // Setup CloudKit subscriptions
        Task {
            await setupCloudKitSubscriptions()
        }
    }
    
    // MARK: - Public Methods
    
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
        
        // Find or create conversation. The thread is keyed by a deterministic ID
        // derived from the two participants, so `conversationID` (if passed) is
        // only a hint — both users always resolve to the same single thread.
        let conversation = try await findOrCreateConversation(
            participant1: currentUserID,
            participant2: recipientUserID
        )
        
        // Create message
        let message = Message(
            conversationID: conversation.id,
            content: content,
            senderUserID: currentUserID,
            recipientUserID: recipientUserID,
            attachmentType: attachmentType,
            attachmentFileName: sharedSubmissionID ?? attachmentURL?.lastPathComponent
        )
        
        // Save to CloudKit
        let savedMessage = try await saveMessageToCloudKit(message, attachmentURL: attachmentURL)

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
        
        let predicate = NSPredicate(
            format: "participant1UserID == %@ OR participant2UserID == %@",
            currentUserID,
            currentUserID
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
        guard let messages = messagesByConversation[conversationID] else { return }
        
        let unreadMessages = messages.filter { !$0.isRead }
        
        for message in unreadMessages {
            try? await markMessageAsRead(message.id)
        }
        
        // Update conversation unread count
        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[index].unreadCount = 0
            saveConversationsLocally()
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
        let flagKey = "didMigrateDeterministicConversations"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        guard let currentUserID = await getCurrentUserID() else { return }

        do {
            // Every conversation this user participates in.
            let predicate = NSPredicate(
                format: "participant1UserID == %@ OR participant2UserID == %@",
                currentUserID, currentUserID
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
                    record["lastMessagePreview"] = latest.content
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
            record["attachmentFileName"] = attachmentFileName
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
            
            let messages = records.compactMap { record -> Message? in
                return Message.fromCloudKitRecord(record)
            }
            
            messagesByConversation[conversationID] = messages
            saveMessagesLocally()
            
            return messages
            
        } catch {
            throw MessageError.cloudKitError(error)
        }
    }
    
    private func findOrCreateConversation(
        participant1: String,
        participant2: String
    ) async throws -> Conversation {
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
    
    private func updateConversation(_ conversationID: UUID, lastMessage: Message) async throws {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }),
              let recordName = conversations[index].recordName else {
            return
        }
        
        let recordID = CKRecord.ID(recordName: recordName)
        let currentUserID = await getCurrentUserID()
        let incrementsUnread = lastMessage.recipientUserID != currentUserID

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
                record["lastMessagePreview"] = lastMessage.content
                if incrementsUnread {
                    let currentUnread = record["unreadCount"] as? Int ?? 0
                    record["unreadCount"] = currentUnread + 1
                }

                _ = try await publicDatabase.save(record)

                // Update locally
                conversations[index].lastMessageTimestamp = lastMessage.timestamp
                conversations[index].lastMessagePreview = lastMessage.content
                if incrementsUnread {
                    conversations[index].unreadCount += 1
                }
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
        notificationInfo.shouldSendContentAvailable = true
        notificationInfo.alertBody = "You have a new message"
        notificationInfo.soundName = "default"
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
        do {
            let recordID = try await container.userRecordID()
            return recordID.recordName
        } catch {
            print("⚠️ Failed to get current user ID: \(error)")
            return nil
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
        
        let attachmentFileName = record["attachmentFileName"] as? String
        
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
        let key = [participantA, participantB].sorted().joined(separator: "|")
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
        }
    }
}
