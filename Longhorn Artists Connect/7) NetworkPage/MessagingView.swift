//
//  MessagingView.swift
//  Longhorn Artists Connect
//
//  LEGACY FILE - Now uses MessageRecordHandling.swift for the new CloudKit messaging system
//
//  This file maintains backward compatibility with existing code.
//  All new code should use ConversationsListView and InMessageView.
//

import SwiftUI
import Combine
import CloudKit

// MARK: - Legacy Type Aliases (for backward compatibility)

// Note: The actual Message and Conversation types are now defined in MessageRecordHandling.swift
// These type aliases and wrappers maintain compatibility with old code

typealias LegacyMessage = OldMessage

struct OldMessage: Identifiable, Codable, Equatable {
    let id: UUID
    var conversationId: UUID
    var senderId: String
    var senderName: String
    var recipientId: String
    var recipientName: String
    var content: String
    var timestamp: Date
    var isRead: Bool
    
    init(id: UUID = UUID(),
         conversationId: UUID,
         senderId: String,
         senderName: String,
         recipientId: String,
         recipientName: String,
         content: String,
         timestamp: Date = Date(),
         isRead: Bool = false) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.senderName = senderName
        self.recipientId = recipientId
        self.recipientName = recipientName
        self.content = content
        self.timestamp = timestamp
        self.isRead = isRead
    }
}

struct OldConversation: Identifiable, Codable, Equatable {
    let id: UUID
    var participantIds: [String]
    var participantNames: [String]
    var lastMessage: String
    var lastMessageDate: Date
    var unreadCount: Int
    
    init(id: UUID = UUID(),
         participantIds: [String],
         participantNames: [String],
         lastMessage: String = "",
         lastMessageDate: Date = Date(),
         unreadCount: Int = 0) {
        self.id = id
        self.participantIds = participantIds
        self.participantNames = participantNames
        self.lastMessage = lastMessage
        self.lastMessageDate = lastMessageDate
        self.unreadCount = unreadCount
    }
}

// MARK: - Legacy Messaging Store (Deprecated - Use MessageStore from MessageRecordHandling.swift)

@MainActor
@available(*, deprecated, message: "Use MessageStore from MessageRecordHandling.swift instead")
class MessagingStore: ObservableObject {
    static let shared = MessagingStore()
    
    @Published var conversations: [OldConversation] = []
    @Published var messages: [UUID: [OldMessage]] = [:]
    @Published var isLoading = false
    @Published var isSendingMessage = false
    
    private init() {
        // Deprecated - use MessageStore instead
        print("⚠️ MessagingStore is deprecated. Use MessageStore from MessageRecordHandling.swift")
    }
}

// MARK: - Legacy Views (Deprecated - Use ConversationsListView and InMessageView)

@available(*, deprecated, message: "Use ConversationsListView from ConversationsListView.swift instead")
struct MessagesListView: View {
    var body: some View {
        ConversationsListView()
    }
}

@available(*, deprecated, message: "Use MessageBubbleView from InMessageView.swift instead")
struct OldMessageBubbleView: View {
    let message: OldMessage
    let isFromCurrentUser: Bool
    
    var body: some View {
        HStack {
            if isFromCurrentUser {
                Spacer()
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isFromCurrentUser ? Color.brandOrange : Color.secondary.opacity(0.2))
                    )
                    .foregroundStyle(isFromCurrentUser ? .white : .primary)
                
                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 250, alignment: isFromCurrentUser ? .trailing : .leading)
            
            if !isFromCurrentUser {
                Spacer()
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Note

/*
 This file contains legacy messaging code.
 
 For new implementations, use:
 - MessageStore from MessageRecordHandling.swift
 - ConversationsListView from ConversationsListView.swift  
 - InMessageView from InMessageView.swift
 - StartConversationButton from StartConversationButton.swift
 
 These provide a modern CloudKit-based messaging system with:
 - Push notifications
 - Attachment support
 - Local caching
 - Better privacy and security
 */

#Preview {
    ConversationsListView()
}

