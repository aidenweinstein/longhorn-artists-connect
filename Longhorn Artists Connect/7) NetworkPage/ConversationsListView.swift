//
//  ConversationsListView.swift
//  Longhorn Artists Connect
//
//  View displaying all user conversations
//

import SwiftUI
import CloudKit

struct ConversationsListView: View {
    @StateObject private var messageStore = MessageStore.shared
    @ObservedObject private var blockManager = BlockedUsersManager.shared
    @ObservedObject private var convoPrefs = ConversationPreferencesManager.shared
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var currentUserID: String?
    
    // For displaying user information (you'll need to integrate with your user store)
    @State private var userInfoCache: [String: UserDisplayInfo] = [:]
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading && visibleConversations.isEmpty {
                    ProgressView("Loading conversations...")
                } else if visibleConversations.isEmpty {
                    ContentUnavailableView(
                        "No Messages",
                        systemImage: "message",
                        description: Text("Start a conversation by messaging someone from their profile.")
                    )
                } else {
                    conversationsList
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await refreshConversations()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .task {
                // Ask for notification permission in context — the first time the user
                // opens Messages — rather than cold at launch/onboarding.
                PushAuthorization.request()
                await loadConversations()
            }
            .refreshable {
                await refreshConversations()
            }
        }
    }
    
    // MARK: - View Components

    /// Threads to show: the store's visible conversations minus any with a blocked
    /// participant, with pinned threads sorted to the top and the rest by recency.
    private var visibleConversations: [Conversation] {
        let uid = currentUserID ?? ""
        return messageStore.visibleConversations
            .filter { !blockManager.isBlocked($0.otherParticipant(for: uid)) }
            .sorted { a, b in
                let aPinned = convoPrefs.isPinned(a.otherParticipant(for: uid))
                let bPinned = convoPrefs.isPinned(b.otherParticipant(for: uid))
                if aPinned != bPinned { return aPinned }   // pinned threads first
                // then most-recent first
                return (a.lastMessageTimestamp ?? .distantPast) > (b.lastMessageTimestamp ?? .distantPast)
            }
    }

    private var conversationsList: some View {
        List {
            ForEach(visibleConversations) { conversation in
                NavigationLink {
                    destinationView(for: conversation)
                } label: {
                    ConversationRow(
                        conversation: conversation,
                        userInfo: userInfo(for: conversation),
                        currentUserID: currentUserID,
                        // Per-user unread, derived from local messages (not the shared
                        // Conversation.unreadCount field, which can't be per-participant).
                        unreadCount: messageStore.unreadCount(for: conversation.id),
                        isPinned: convoPrefs.isPinned(conversation.otherParticipant(for: currentUserID ?? "")),
                        isMuted: convoPrefs.isMuted(conversation.otherParticipant(for: currentUserID ?? ""))
                    )
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        messageStore.clearConversation(conversation.id)
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .tint(.gray)
                }
                .swipeActions(edge: .leading) {
                    if messageStore.unreadCount(for: conversation.id) > 0 {
                        Button {
                            Task {
                                await markAsRead(conversation)
                            }
                        } label: {
                            Label("Mark Read", systemImage: "envelope.open")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
    
    @ViewBuilder
    private func destinationView(for conversation: Conversation) -> some View {
        let info = userInfo(for: conversation)
        
        InMessageView(
            conversationID: conversation.id,
            otherUserID: conversation.otherParticipant(for: currentUserID ?? ""),
            otherUserName: info.name,
            otherUserRole: info.role
        )
    }
    
    // MARK: - Actions
    
    private func loadConversations() async {
        isLoading = true
        defer { isLoading = false }
        
        // Get current user ID
        do {
            let userRecordID = try await CKContainer.default().userRecordID()
            currentUserID = userRecordID.recordName
        } catch {
            errorMessage = "Failed to authenticate with iCloud"
            showError = true
            return
        }
        
        // One-time cleanup of duplicate threads from older builds.
        await messageStore.migrateLegacyConversationsIfNeeded()

        // Fetch conversations
        do {
            try await messageStore.fetchConversations()
            
            // Load user info for all participants
            await loadUserInfo()
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func refreshConversations() async {
        await loadConversations()
    }
    
    private func markAsRead(_ conversation: Conversation) async {
        do {
            try await messageStore.markConversationAsRead(conversation.id)
        } catch {
            errorMessage = "Failed to mark conversation as read"
            showError = true
        }
    }
    
    // MARK: - User Info Helpers
    
    private func loadUserInfo() async {
        // Load user display info for all conversation participants
        let participantIDs = Set(messageStore.conversations.flatMap {
            [
                $0.otherParticipant(for: currentUserID ?? "")
            ]
        })

        // Make sure the directory is populated so we can resolve names.
        let profileManager = UserProfileManager.shared
        await profileManager.fetchAllUsers()

        for userID in participantIDs {
            if let user = profileManager.findUser(byID: userID) {
                // Resolve the real name/role from the user directory.
                userInfoCache[userID] = UserDisplayInfo(
                    id: userID,
                    name: user.displayName,
                    role: user.rolesString
                )
            } else if userInfoCache[userID] == nil {
                // Fallback for participants not (yet) in the directory.
                userInfoCache[userID] = UserDisplayInfo(
                    id: userID,
                    name: "User \(userID.prefix(8))",
                    role: "Artist"
                )
            }
        }
    }
    
    private func userInfo(for conversation: Conversation) -> UserDisplayInfo {
        let otherUserID = conversation.otherParticipant(for: currentUserID ?? "")
        return userInfoCache[otherUserID] ?? UserDisplayInfo(
            id: otherUserID,
            name: "Unknown User",
            role: ""
        )
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation
    let userInfo: UserDisplayInfo
    let currentUserID: String?
    /// Per-user unread count, derived from local messages by the parent list. Drives
    /// the unread badge — replaces the shared `Conversation.unreadCount` field.
    var unreadCount: Int = 0
    var isPinned: Bool = false
    var isMuted: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Profile placeholder
            Circle()
                .fill(Color.brandOrange.opacity(0.2))
                .frame(width: 56, height: 56)
                .overlay {
                    Text(userInfo.initials)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.brandOrange)
                }

            // Conversation info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(userInfo.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(45))
                    }

                    if let timestamp = conversation.lastMessageTimestamp {
                        Text(formatTimestamp(timestamp))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let preview = conversation.lastMessagePreview, !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("Start a conversation")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
            
            // Unread indicator
            if unreadCount > 0 {
                VStack {
                    Badge(count: unreadCount)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}

// MARK: - Badge View

struct Badge: View {
    let count: Int
    
    var body: some View {
        Text("\(count)")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, count > 9 ? 6 : 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.brandOrange)
            )
            .frame(minWidth: 20, minHeight: 20)
    }
}

// MARK: - Supporting Types

struct UserDisplayInfo {
    let id: String
    var name: String
    var role: String
    
    var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else if let first = components.first {
            return String(first.prefix(1)).uppercased()
        }
        return "?"
    }
}

// MARK: - Preview

#Preview {
    ConversationsListView()
}
