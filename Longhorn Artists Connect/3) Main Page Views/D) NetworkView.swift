import SwiftUI
import PhotosUI
import Combine
import CloudKit

// MARK: - NetworkFlowLayout Helper (Local to avoid conflicts)

struct NetworkFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowLayoutResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowLayoutResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowLayoutResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// Local types for NetworkView to avoid conflicts with MessagingView
struct NetworkConversation: Identifiable {
    let id = UUID()
    let name: String
    let lastMessage: String
    let timestamp: Date
    let unread: Bool
    let avatar: String // SF Symbol name or emoji
}

struct NetworkMessage: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date
    let isFromCurrentUser: Bool
}

struct NetworkView: View {
    @StateObject private var messageStore = MessageStore.shared
    @ObservedObject private var userProfileManager = UserProfileManager.shared
    @State private var currentUserID: String?

    /// Real conversations from the message store, most recently messaged first.
    /// Each row resolves the other participant's name via the directory.
    private var conversations: [NetworkConversation] {
        guard let currentUserID else { return [] }

        return messageStore.conversations
            .sorted { ($0.lastMessageTimestamp ?? .distantPast) > ($1.lastMessageTimestamp ?? .distantPast) }
            .map { convo -> NetworkConversation in
                let otherID = convo.otherParticipant(for: currentUserID)
                let name = userProfileManager.allUsers.first { $0.id == otherID }?.fullName ?? "Unknown"
                return NetworkConversation(
                    name: name,
                    lastMessage: convo.lastMessagePreview ?? "",
                    timestamp: convo.lastMessageTimestamp ?? Date(),
                    unread: convo.unreadCount > 0,
                    avatar: "👤"
                )
            }
    }

    @State private var showNewMessage = false
    @State private var showDirectory = false
    @State private var selectedChat: NetworkConversation?
    
    // Define colors as static constants to prevent color changes on tab switch
    private static let darkBrownColor = Color(red: 80/255, green: 50/255, blue: 30/255).opacity(1.0)  // Darker for unselected
    private static let mediumBrownColor = Color(red: 140/255, green: 90/255, blue: 55/255).opacity(1.0)  // Brighter for selected
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                Group {
                    if conversations.isEmpty {
                    VStack(spacing: 0) {
                        Text("No messages.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                        
                        Divider()
                        
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(conversations) { conversation in
                                Button {
                                    selectedChat = conversation
                                } label: {
                                    HStack(spacing: 12) {
                                        // Avatar
                                        Text(conversation.avatar)
                                            .font(.system(size: feedFormat.avatarEmojiSize))
                                            .frame(width: feedFormat.avatarSize, height: feedFormat.avatarSize)
                                            .background(Circle().fill(Color.secondary.opacity(0.1)))

                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(conversation.name)
                                                    .font(.system(size: feedFormat.nameFontSize, weight: conversation.unread ? .semibold : .regular))
                                                    .foregroundStyle(.primary)

                                                Spacer()

                                                Text(formatTimestamp(conversation.timestamp))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }

                                            HStack {
                                                Text(conversation.lastMessage)
                                                    .font(.subheadline)
                                                    .foregroundStyle(conversation.unread ? .primary : .secondary)
                                                    .lineLimit(2)

                                                Spacer()

                                                if conversation.unread {
                                                    Circle()
                                                        .fill(Color.brandOrange)
                                                        .frame(width: 8, height: 8)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.vertical, feedFormat.rowVerticalPadding)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)

                                // Separator after each user, including the last —
                                // never above the first.
                                Divider()
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .refreshable {
                        await refreshMessages()
                    }
                }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await loadConversations()
            }
            .sheet(item: $selectedChat, onDismiss: {
                // Refresh the feed after returning from a conversation so a
                // newly-messaged person appears (and re-sorts to the top).
                Task { await loadConversations() }
            }) { conversation in
                let uid = otherUserID(forName: conversation.name)
                NavigationStack {
                    InMessageView(
                        conversationID: existingConversationID(forOtherUser: uid) ?? UUID(),
                        otherUserID: uid,
                        otherUserName: conversation.name,
                        otherUserRole: otherUserRole(forName: conversation.name)
                    )
                }
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showNewMessage, onDismiss: {
                // A message may have been sent from the New Message flow.
                Task { await loadConversations() }
            }) {
                NewMessageView()
            }
            .sheet(isPresented: $showDirectory) {
                NetworkDirectoryView()
            }
        }
    }
    
    // MARK: - Feed Format Per Screen Size
    /// Tunable sizing for the main feed (the conversations list).
    /// - `avatarSize`: diameter of the circular avatar.
    /// - `avatarEmojiSize`: font size of the emoji inside the avatar.
    /// - `nameFontSize`: size of the conversation name text.
    /// - `rowVerticalPadding`: extra vertical padding inside each row.
    private struct FeedFormat {
        var avatarSize: CGFloat
        var avatarEmojiSize: CGFloat
        var nameFontSize: CGFloat
        var rowVerticalPadding: CGFloat
    }

    /// Adjust the values in each case to tune the feed for that screen size.
    private var feedFormat: FeedFormat {
        switch ScreenSizeFormat.current {
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return FeedFormat(avatarSize: 56, avatarEmojiSize: 40, nameFontSize: 16, rowVerticalPadding: 15)
        case .size402x874: // iPhone 16 Pro, 17
            return FeedFormat(avatarSize: 57, avatarEmojiSize: 41, nameFontSize: 16, rowVerticalPadding: 15)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return FeedFormat(avatarSize: 61, avatarEmojiSize: 44, nameFontSize: 17, rowVerticalPadding: 15)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return FeedFormat(avatarSize: 63, avatarEmojiSize: 45, nameFontSize: 18, rowVerticalPadding: 15)
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return FeedFormat(avatarSize: 80, avatarEmojiSize: 58, nameFontSize: 22, rowVerticalPadding: 7)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return FeedFormat(avatarSize: 92, avatarEmojiSize: 66, nameFontSize: 25, rowVerticalPadding: 8)
        }
    }

    // MARK: - Toolbar Format Per Screen Size
    /// Tunable toolbar item sizes and positions for the Network page.
    /// - `directoryFontSize/pillHeight`: size of the Directory pill.
    /// - `composeWidth/composeFontSize`: size of the new-message button pill.
    /// - `pillOffsetX/Y`: nudges both pills from their default spot.
    /// - `logoHeight`: height of the Network logo image.
    private struct ToolbarFormat {
        var directoryFontSize: CGFloat
        var composeWidth: CGFloat
        var composeFontSize: CGFloat
        var pillHeight: CGFloat
        var pillOffsetX: CGFloat
        var pillOffsetY: CGFloat
        var logoHeight: CGFloat
        // iPad-only knobs (default to no-ops so iPhone layout is unaffected):
        /// Extra horizontal/vertical nudge applied to the logo.
        var logoOffsetX: CGFloat = 0
        var logoOffsetY: CGFloat = 0
        /// Fixed length (width) of the Directory pill. `nil` sizes it to its content.
        var pillLength: CGFloat? = nil
        /// How far down the orange toolbar bar extends.
        var barHeight: CGFloat = 60
    }

    /// Adjust the values in each case to tune the toolbar for that screen size.
    private var toolbarFormat: ToolbarFormat {
        switch ScreenSizeFormat.current {
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return ToolbarFormat(directoryFontSize: 14, composeWidth: 43, composeFontSize: 18, pillHeight: 40, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 46)
        case .size402x874: // iPhone 16 Pro, 17
            return ToolbarFormat(directoryFontSize: 14, composeWidth: 44, composeFontSize: 18, pillHeight: 41, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 47)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return ToolbarFormat(directoryFontSize: 15, composeWidth: 47, composeFontSize: 20, pillHeight: 44, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 50)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return ToolbarFormat(directoryFontSize: 16, composeWidth: 48, composeFontSize: 20, pillHeight: 45, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 52)
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return ToolbarFormat(directoryFontSize: 20, composeWidth: 62, composeFontSize: 26, pillHeight: 56, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 66, logoOffsetX: 0, logoOffsetY: 0, pillLength: nil, barHeight: 80)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return ToolbarFormat(directoryFontSize: 23, composeWidth: 72, composeFontSize: 30, pillHeight: 64, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 76, logoOffsetX: 0, logoOffsetY: 0, pillLength: nil, barHeight: 90)
        }
    }

    // ORANGE HEADER
    private var topBar: some View {
        ZStack {
            Color.brandOrange
                .ignoresSafeArea(edges: .top)
                .frame(height: toolbarFormat.barHeight)
            HStack(spacing: 0) {
                Image("Network")
                    .resizable()
                    .scaledToFill()
                    .frame(height: toolbarFormat.logoHeight)
                    .offset(x: 0, y: 2)
                    .offset(x: toolbarFormat.logoOffsetX, y: toolbarFormat.logoOffsetY)
                Spacer(minLength: 8)
                filterPill
            }
            .frame(height: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // TOOLBAR PILLS (distinct buttons with space between them)
    private var filterPill: some View {
        HStack(spacing: 4) {
            Button {
                showDirectory = true
            } label: {
                Text("Directory")
                    .font(.system(size: toolbarFormat.directoryFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: toolbarFormat.pillLength, height: toolbarFormat.pillHeight)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(Color.pillActive))
            .offset(x: toolbarFormat.pillOffsetX, y: toolbarFormat.pillOffsetY)

            Button {
                showNewMessage = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: toolbarFormat.composeFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: toolbarFormat.composeWidth, height: toolbarFormat.pillHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(Color.pillActive))
            .offset(x: toolbarFormat.pillOffsetX, y: toolbarFormat.pillOffsetY)
        }
    }

    /// Resolves a recipient's CloudKit user ID from their display name so recent
    /// chats open the same `InMessageView` (and thus the same conversation/history)
    /// as the New Message flow. Falls back to the name if no profile is found.
    private func otherUserID(forName name: String) -> String {
        UserProfileManager.shared.allUsers.first { $0.fullName == name }?.id ?? name
    }

    /// The roles string for a user, used as the subtitle in `InMessageView`.
    private func otherUserRole(forName name: String) -> String {
        UserProfileManager.shared.allUsers.first { $0.fullName == name }?.rolesString ?? ""
    }

    /// Returns the ID of an existing 1:1 conversation with the given user, if one
    /// is already loaded, so the same message history is shown regardless of whether
    /// the thread was opened from New Message or recent chats.
    private func existingConversationID(forOtherUser otherUserID: String) -> UUID? {
        MessageStore.shared.conversations.first {
            $0.participant1UserID == otherUserID || $0.participant2UserID == otherUserID
        }?.id
    }

    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return formatter.string(from: date)
        }
    }
    
    private func refreshMessages() async {
        // Refresh user profiles for messaging
        await UserProfileManager.shared.fetchAllUsers(forceRefresh: true)
        // Refresh the conversation feed
        try? await messageStore.fetchConversations()

        // Small delay for better UX
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }

    /// Loads the current user's ID and their conversations so the feed reflects
    /// who they've messaged (most recent first).
    private func loadConversations() async {
        if currentUserID == nil {
            currentUserID = try? await CKContainer.default().userRecordID().recordName
        }
        // Ensure the directory is loaded so participant names resolve.
        await userProfileManager.fetchAllUsers()
        try? await messageStore.fetchConversations()
    }
}

#Preview {
    NetworkView()
}

// MARK: - Screen Size Previews

#if DEBUG

#Preview("Network 393 × 852", traits: .fixedLayout(width: 393, height: 852)) {
    let _ = (ScreenSizeFormat.previewOverride = .size393x852)
    NetworkView()
}

#Preview("Network 402 × 874", traits: .fixedLayout(width: 402, height: 874)) {
    let _ = (ScreenSizeFormat.previewOverride = .size402x874)
    NetworkView()
}

#Preview("Network 430 × 932", traits: .fixedLayout(width: 430, height: 932)) {
    let _ = (ScreenSizeFormat.previewOverride = .size430x932)
    NetworkView()
}

#Preview("Network 440 × 956", traits: .fixedLayout(width: 440, height: 956)) {
    let _ = (ScreenSizeFormat.previewOverride = .size440x956)
    NetworkView()
}

#endif
