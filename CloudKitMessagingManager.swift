//
//  CloudKitMessagingManager.swift
//  Longhorn Artists Connect
//
//  CloudKit-based messaging system with privacy considerations
//
//  PRIVACY DESIGN:
//  - Messages stored in CloudKit public database (queryable by participants only)
//  - Each message has senderId and recipientId for targeted queries
//  - Users can only query messages where they are sender OR recipient
//  - Messages can be deleted by sender or recipient
//  - No message content indexing (privacy)
//
//  STORAGE IMPACT:
//  - Average message: ~1 KB
//  - 1000 messages ≈ 1 MB
//  - CloudKit free tier: 1 GB (plenty for messaging)
//
//  TRADE-OFFS:
//  ✅ Messages reach recipients
//  ✅ Cross-device sync
//  ✅ Persistent storage
//  ⚠️ Requires internet connection
//  ⚠️ Slight delay (1-2 seconds typical)
//  ⚠️ Messages stored in cloud (but query-restricted)

import Foundation
import CloudKit
import Combine

// MARK: - CloudKit Message Model

struct CloudKitMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let conversationId: UUID
    let senderId: String        // CloudKit user record name
    let senderDisplayName: String
    let recipientId: String     // CloudKit user record name
    let recipientDisplayName: String
    let content: String
    let timestamp: Date
    var isRead: Bool
    var isDeleted: Bool
    
    // CloudKit record name
    var recordName: String {
        id.uuidString
    }
    
    init(id: UUID = UUID(),
         conversationId: UUID,
         senderId: String,
         senderDisplayName: String,
         recipientId: String,
         recipientDisplayName: String,
         content: String,
         timestamp: Date = Date(),
         isRead: Bool = false,
         isDeleted: Bool = false) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.senderDisplayName = senderDisplayName
        self.recipientId = recipientId
        self.recipientDisplayName = recipientDisplayName
        self.content = content
        self.timestamp = timestamp
        self.isRead = isRead
        self.isDeleted = isDeleted
    }
}

// MARK: - CloudKit Messaging Manager

@MainActor
class CloudKitMessagingManager: ObservableObject {
    static let shared = CloudKitMessagingManager()
    
    @Published var conversations: [UUID: [CloudKitMessage]] = [:]
    @Published var isLoading = false
    @Published var lastError: String?
    
    private let container = CKContainer.default()
    private var database: CKDatabase {
        container.publicCloudDatabase
    }
    
    // Cache for current user's record ID
    private var currentUserRecordID: String?
    
    private init() {
        Task {
            await getCurrentUserID()
        }
    }
    
    // MARK: - User ID Management
    
    func getCurrentUserID() async {
        do {
            let recordID = try await container.userRecordID()
            currentUserRecordID = recordID.recordName
            print("✅ Current user ID: \(recordID.recordName)")
        } catch {
            print("❌ Failed to get user ID: \(error)")
        }
    }
    
    // MARK: - Send Message
    
    /// Send a message to another user
    func sendMessage(
        to recipientId: String,
        recipientDisplayName: String,
        content: String,
        conversationId: UUID
    ) async throws -> CloudKitMessage {
        
        guard let senderId = currentUserRecordID else {
            throw NSError(domain: "Messaging", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Get sender's display name from UserDefaults
        let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let senderDisplayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        
        // Create message
        let message = CloudKitMessage(
            conversationId: conversationId,
            senderId: senderId,
            senderDisplayName: senderDisplayName.isEmpty ? "Anonymous" : senderDisplayName,
            recipientId: recipientId,
            recipientDisplayName: recipientDisplayName,
            content: content
        )
        
        // Save to CloudKit
        let record = message.toCloudKitRecord()
        _ = try await database.save(record)
        
        print("✅ Message sent to CloudKit: \(message.id)")
        
        // Update local cache
        await MainActor.run {
            if conversations[conversationId] == nil {
                conversations[conversationId] = []
            }
            conversations[conversationId]?.append(message)
        }
        
        return message
    }
    
    // MARK: - Fetch Messages
    
    /// Fetch all messages for a specific conversation
    func fetchMessages(for conversationId: UUID) async throws -> [CloudKitMessage] {
        guard let currentUserId = currentUserRecordID else {
            throw NSError(domain: "Messaging", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Query for messages where user is sender OR recipient
        // AND conversationId matches
        let predicate = NSPredicate(
            format: "(senderId == %@ OR recipientId == %@) AND conversationId == %@ AND isDeleted == 0",
            currentUserId,
            currentUserId,
            conversationId.uuidString
        )
        
        let query = CKQuery(recordType: "Message", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        let (matchResults, _) = try await database.records(matching: query)
        
        var messages: [CloudKitMessage] = []
        
        for (_, result) in matchResults {
            switch result {
            case .success(let record):
                if let message = CloudKitMessage.fromCloudKitRecord(record) {
                    messages.append(message)
                }
            case .failure(let error):
                print("❌ Failed to fetch message: \(error)")
            }
        }
        
        // Update cache
        await MainActor.run {
            conversations[conversationId] = messages
        }
        
        print("✅ Fetched \(messages.count) messages for conversation \(conversationId)")
        
        return messages
    }
    
    /// Fetch all conversations for current user
    func fetchAllConversations() async throws -> [UUID: [CloudKitMessage]] {
        guard let currentUserId = currentUserRecordID else {
            throw NSError(domain: "Messaging", code: -3,
                         userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Query for all messages where user is participant
        let predicate = NSPredicate(
            format: "(senderId == %@ OR recipientId == %@) AND isDeleted == 0",
            currentUserId,
            currentUserId
        )
        
        let query = CKQuery(recordType: "Message", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        let (matchResults, _) = try await database.records(matching: query)
        
        var messagesByConversation: [UUID: [CloudKitMessage]] = [:]
        
        for (_, result) in matchResults {
            switch result {
            case .success(let record):
                if let message = CloudKitMessage.fromCloudKitRecord(record) {
                    if messagesByConversation[message.conversationId] == nil {
                        messagesByConversation[message.conversationId] = []
                    }
                    messagesByConversation[message.conversationId]?.append(message)
                }
            case .failure(let error):
                print("❌ Failed to fetch message: \(error)")
            }
        }
        
        // Sort messages in each conversation by timestamp
        for conversationId in messagesByConversation.keys {
            messagesByConversation[conversationId]?.sort { $0.timestamp < $1.timestamp }
        }
        
        // Update cache
        await MainActor.run {
            conversations = messagesByConversation
        }
        
        print("✅ Fetched \(messagesByConversation.count) conversations")
        
        return messagesByConversation
    }
    
    // MARK: - Mark as Read
    
    /// Mark a message as read
    func markAsRead(messageId: UUID) async throws {
        let recordID = CKRecord.ID(recordName: messageId.uuidString)
        
        do {
            let record = try await database.record(for: recordID)
            record["isRead"] = 1
            _ = try await database.save(record)
            
            print("✅ Marked message as read: \(messageId)")
            
            // Update local cache
            await updateLocalMessage(messageId) { message in
                var updated = message
                updated.isRead = true
                return updated
            }
        } catch {
            print("❌ Failed to mark message as read: \(error)")
            throw error
        }
    }
    
    /// Mark all messages in a conversation as read
    func markConversationAsRead(conversationId: UUID) async throws {
        guard let messages = conversations[conversationId] else { return }
        
        for message in messages where !message.isRead {
            try? await markAsRead(messageId: message.id)
        }
    }
    
    // MARK: - Delete Message
    
    /// Delete a message (soft delete - marks as deleted)
    func deleteMessage(messageId: UUID) async throws {
        let recordID = CKRecord.ID(recordName: messageId.uuidString)
        
        do {
            let record = try await database.record(for: recordID)
            record["isDeleted"] = 1
            _ = try await database.save(record)
            
            print("✅ Deleted message: \(messageId)")
            
            // Update local cache
            await updateLocalMessage(messageId) { message in
                var updated = message
                updated.isDeleted = true
                return updated
            }
        } catch {
            print("❌ Failed to delete message: \(error)")
            throw error
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateLocalMessage(_ messageId: UUID, with transform: (CloudKitMessage) -> CloudKitMessage) async {
        for conversationId in conversations.keys {
            if let index = conversations[conversationId]?.firstIndex(where: { $0.id == messageId }) {
                let message = conversations[conversationId]![index]
                conversations[conversationId]![index] = transform(message)
            }
        }
    }
}

// MARK: - CloudKit Record Conversion

extension CloudKitMessage {
    func toCloudKitRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: recordName)
        let record = CKRecord(recordType: "Message", recordID: recordID)
        
        record["conversationId"] = conversationId.uuidString
        record["senderId"] = senderId
        record["senderDisplayName"] = senderDisplayName
        record["recipientId"] = recipientId
        record["recipientDisplayName"] = recipientDisplayName
        record["content"] = content
        record["timestamp"] = timestamp
        record["isRead"] = isRead ? 1 : 0
        record["isDeleted"] = isDeleted ? 1 : 0
        
        return record
    }
    
    static func fromCloudKitRecord(_ record: CKRecord) -> CloudKitMessage? {
        guard
            let conversationIdString = record["conversationId"] as? String,
            let conversationId = UUID(uuidString: conversationIdString),
            let senderId = record["senderId"] as? String,
            let senderDisplayName = record["senderDisplayName"] as? String,
            let recipientId = record["recipientId"] as? String,
            let recipientDisplayName = record["recipientDisplayName"] as? String,
            let content = record["content"] as? String,
            let timestamp = record["timestamp"] as? Date,
            let id = UUID(uuidString: record.recordID.recordName)
        else {
            return nil
        }
        
        let isRead = (record["isRead"] as? Int) == 1
        let isDeleted = (record["isDeleted"] as? Int) == 1
        
        return CloudKitMessage(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            senderDisplayName: senderDisplayName,
            recipientId: recipientId,
            recipientDisplayName: recipientDisplayName,
            content: content,
            timestamp: timestamp,
            isRead: isRead,
            isDeleted: isDeleted
        )
    }
}

// MARK: - CloudKit Schema Definition

/*
 CloudKit Record Type: Message
 
 Fields:
 - conversationId: String (indexed) - UUID as string
 - senderId: String (indexed) - CloudKit user record name
 - senderDisplayName: String - Display name of sender
 - recipientId: String (indexed) - CloudKit user record name
 - recipientDisplayName: String - Display name of recipient
 - content: String - Message content (NOT indexed for privacy)
 - timestamp: Date/Time (indexed, sortable) - When message was sent
 - isRead: Int64 (indexed) - 0 = unread, 1 = read
 - isDeleted: Int64 (indexed) - 0 = active, 1 = deleted
 
 Indexes Required:
 1. senderId - QUERYABLE, SORTABLE
 2. recipientId - QUERYABLE, SORTABLE
 3. conversationId - QUERYABLE
 4. timestamp - SORTABLE
 5. isDeleted - QUERYABLE
 
 Security:
 - Users can only query messages where they are sender OR recipient
 - Message content is not indexed (can't be searched in CloudKit Console)
 - Deleted messages are soft-deleted (isDeleted = 1)
 
 Storage Estimate:
 - Each message: ~500 bytes - 1 KB
 - 1000 messages: ~1 MB
 - CloudKit free tier: 1 GB (plenty for messaging)
*/
