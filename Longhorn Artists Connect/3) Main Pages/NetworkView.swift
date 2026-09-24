import SwiftUI
import PhotosUI
import Combine
import CloudKit

// Local types for NetworkView to avoid conflicts with MessagingView
struct NetworkConversation: Identifiable {
    let id = UUID()
    /// The underlying message-store conversation ID, used to clear the thread from
    /// the feed on swipe.
    let conversationID: UUID
    let name: String
    let lastMessage: String
    let timestamp: Date
    let unread: Bool
    let avatarImageData: Data? // The participant's real profile photo, if any.
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

        // `visibleConversations` excludes threads the user has cleared from the feed.
        return messageStore.visibleConversations
            .sorted { ($0.lastMessageTimestamp ?? .distantPast) > ($1.lastMessageTimestamp ?? .distantPast) }
            .compactMap { convo -> NetworkConversation? in
                let otherID = convo.otherParticipant(for: currentUserID)

                // Hide self-conversations. These show up as a confusing "Unknown"
                // thread (both participants are you), so they don't belong here.
                guard Self.normalizedID(otherID) != Self.normalizedID(currentUserID) else {
                    return nil
                }

                // Only show threads whose other participant we can identify in the
                // directory. Unresolvable ("Unknown") conversations are hidden.
                guard let user = userProfileManager.findUser(byID: otherID) else {
                    return nil
                }

                return NetworkConversation(
                    conversationID: convo.id,
                    name: user.fullName,
                    lastMessage: convo.lastMessagePreview ?? "",
                    timestamp: convo.lastMessageTimestamp ?? Date(),
                    // Per-user unread, derived from local messages (not the shared
                    // Conversation.unreadCount field, which can't be per-participant).
                    unread: messageStore.unreadCount(for: convo.id) > 0,
                    avatarImageData: user.profileImageData
                )
            }
    }

    /// Strips the `UserProfile_` prefix so a directory record name and a raw
    /// CloudKit user record name compare equal (matches UserProfileManager).
    private static func normalizedID(_ id: String) -> String {
        let prefix = "UserProfile_"
        return id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id
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
                    List {
                        ForEach(conversations) { conversation in
                            Button {
                                selectedChat = conversation
                            } label: {
                                HStack(spacing: 12) {
                                    // Avatar — the participant's real profile
                                    // photo, falling back to a person symbol.
                                    Group {
                                        if let data = conversation.avatarImageData,
                                           let uiImage = UIImage(data: data) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                        } else {
                                            Image(systemName: "person.crop.circle.fill")
                                                .resizable()
                                                .scaledToFit()
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(width: feedFormat.avatarSize, height: feedFormat.avatarSize)
                                    .background(Circle().fill(Color.secondary.opacity(0.1)))
                                    .clipShape(Circle())

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
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowBackground(Color.clear)
                            // Swipe right-to-left to clear a chat from the feed. This
                            // only hides the thread — the messages are kept, and it
                            // reappears if a newer message arrives.
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    messageStore.clearConversation(conversation.conversationID)
                                } label: {
                                    Label("Clear", systemImage: "xmark.circle")
                                }
                                .tint(.gray)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
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
                .presentationDragIndicator(.hidden)
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

        /// Returns a copy with every size (logo, pills, fonts, bar height, pill length)
        /// multiplied by `k`. Positions/offsets are left unchanged.
        func scaled(by k: CGFloat) -> ToolbarFormat {
            guard k != 1 else { return self }
            var f = self
            f.directoryFontSize *= k
            f.composeWidth *= k
            f.composeFontSize *= k
            f.pillHeight *= k
            f.logoHeight *= k
            f.barHeight *= k
            if let p = f.pillLength { f.pillLength = p * k }
            return f
        }
    }

    /// Universal toolbar resizer: one knob that scales every toolbar element (logo, pills,
    /// fonts, bar height) across ALL screen sizes at once, keeping the per-device
    /// proportions tuned below. 1.0 = current size; 1.2 = 20% larger; 0.85 = 15% smaller.
    /// Positions and offsets are untouched.
    private var toolbarSizeMultiplier: CGFloat { 1.0 }

    // MARK: - Per-Element Toolbar Tuning (affects every screen size at once)
    // Network asset (the wordmark logo).
    private var networkSize: CGFloat { 1.2 }       // size multiplier
    private var networkOffsetX: CGFloat { -4 }      // + = right
    private var networkOffsetY: CGFloat { -2 }      // + = down
    // Directory & New Message buttons (moved/sized together).
    private var dirMsgSize: CGFloat { 1.1 }
    private var dirMsgOffsetX: CGFloat { 0 }
    private var dirMsgOffsetY: CGFloat { -5 }
    private var dirMsgPadding: CGFloat { 0 }    // space reserved around each

    /// The per-device format, universally scaled by `toolbarSizeMultiplier`, with the
    /// Network asset additionally scaled by `networkSize`.
    private var toolbarFormat: ToolbarFormat {
        var f = baseToolbarFormat.scaled(by: toolbarSizeMultiplier)
        f.logoHeight *= networkSize
        return f
    }

    /// Adjust the values in each case to tune the toolbar for that screen size.
    private var baseToolbarFormat: ToolbarFormat {
        switch ScreenSizeFormat.current {
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return ToolbarFormat(directoryFontSize: 14, composeWidth: 43, composeFontSize: 18, pillHeight: 40, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 28, barHeight: 50)
        case .size402x874: // iPhone 16 Pro, 17
            return ToolbarFormat(directoryFontSize: 14, composeWidth: 44, composeFontSize: 18, pillHeight: 41, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 29, barHeight: 50)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return ToolbarFormat(directoryFontSize: 15, composeWidth: 47, composeFontSize: 20, pillHeight: 44, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 30, barHeight: 52)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return ToolbarFormat(directoryFontSize: 16, composeWidth: 48, composeFontSize: 20, pillHeight: 45, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 32, barHeight: 53)
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return ToolbarFormat(directoryFontSize: 20, composeWidth: 62, composeFontSize: 26, pillHeight: 56, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 40, logoOffsetX: 0, logoOffsetY: 0, pillLength: nil, barHeight: 66)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return ToolbarFormat(directoryFontSize: 23, composeWidth: 72, composeFontSize: 30, pillHeight: 64, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 46, logoOffsetX: 0, logoOffsetY: 0, pillLength: nil, barHeight: 72)
        }
    }

    // ORANGE HEADER
    private var topBar: some View {
        HStack(spacing: 0) {
            Image("Network")
                .resizable()
                .scaledToFill()
                .frame(height: toolbarFormat.logoHeight)
                .offset(x: 0, y: 2)
                .offset(x: toolbarFormat.logoOffsetX, y: toolbarFormat.logoOffsetY)
                .offset(x: networkOffsetX, y: networkOffsetY)
            Spacer(minLength: 8)
            filterPill
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // Orange fills the bar and bleeds up behind the status bar / Dynamic Island.
        .frame(maxWidth: .infinity, minHeight: toolbarFormat.barHeight, maxHeight: toolbarFormat.barHeight)
        .background(Color.brandOrange, ignoresSafeAreaEdges: .top)
    }

    // TOOLBAR PILLS (distinct buttons with space between them)
    private var filterPill: some View {
        HStack(spacing: 10) {
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
            .padding(dirMsgPadding)
            .scaleEffect(dirMsgSize)
            .offset(x: dirMsgOffsetX, y: dirMsgOffsetY)

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
            .padding(dirMsgPadding)
            .scaleEffect(dirMsgSize)
            .offset(x: dirMsgOffsetX, y: dirMsgOffsetY)
        }
    }

    /// Resolves a recipient's CloudKit user ID from their display name so recent
    /// chats open the same `InMessageView` (and thus the same conversation/history)
    /// as the New Message flow. Falls back to the name if no profile is found.
    private func otherUserID(forName name: String) -> String {
        UserProfileManager.shared.allUsers.first { $0.fullName == name }?.messagingUserID ?? name
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

#Preview("Network 440 × 956") {
    let _ = (ScreenSizeFormat.previewOverride = .size440x956)
    NetworkView()
        .previewDevice("iPhone 16 Pro Max")
}

#endif
