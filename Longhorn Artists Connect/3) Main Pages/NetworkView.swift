import SwiftUI
import PhotosUI
import Combine
import CloudKit

// Local types for NetworkView to avoid conflicts with MessagingView
struct NetworkConversation: Identifiable {
    let id = UUID()
    /// The underlying message-store conversation ID, used to clear the thread from
    /// the feed on swipe. `nil` for a connection you haven't messaged yet.
    let conversationID: UUID?
    let name: String
    let lastMessage: String
    /// When the last message was sent. `nil` for a connection with no thread yet,
    /// so the row shows no time.
    let timestamp: Date?
    let unread: Bool
    let avatarImageData: Data? // The participant's real profile photo, if any.
    /// Title of the project this person is currently working on (an approved Cast &
    /// Crew Call they posted or are on the team of, whose shoot hasn't wrapped).
    /// `nil` when they have none; shown to the right of their name.
    let currentProject: String?

    /// True for a connection you haven't messaged yet — the row invites you to
    /// "Say hi!" instead of showing a last message.
    var isSayHi: Bool { conversationID == nil }
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
    /// Private connections, so people you've connected with but never messaged
    /// still appear in the feed with a "Say hi!" prompt.
    @ObservedObject private var connections = ConnectionsManager.shared
    /// Approved posts, used to find the project each person is currently on.
    @ObservedObject private var submissionStore = SubmissionStore_3_2.shared
    @State private var currentUserID: String?

    /// The feed: real conversations (most recent first), followed by connections
    /// you haven't messaged yet, alphabetically, each inviting you to "Say hi!".
    private var conversations: [NetworkConversation] {
        let threads = messageThreads
        // Connections already covered by a thread are left out so nobody appears twice.
        let threadedIDs = Set(threads.map { Self.normalizedID($0.otherUserID) })
        let sayHi = connections.connectedUsers(in: userProfileManager.allUsers)
            .filter { user in
                !threadedIDs.contains(user.messagingUserID)
                    && Self.normalizedID(user.messagingUserID) != Self.normalizedID(currentUserID ?? "")
                    && !BlockedUsersManager.shared.isBlocked(user.messagingUserID)
            }
            .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
            .map { user in
                NetworkConversation(
                    conversationID: nil,
                    name: user.fullName,
                    lastMessage: "Say hi!",
                    timestamp: nil,
                    unread: false,
                    avatarImageData: user.profileImageData,
                    currentProject: currentProjectTitle(for: user)
                )
            }
        return threads.map(\.row) + sayHi
    }

    /// Real conversations from the message store, most recently messaged first,
    /// paired with the other participant's ID. Each row resolves the other
    /// participant's name via the directory.
    private var messageThreads: [(otherUserID: String, row: NetworkConversation)] {
        guard let currentUserID else { return [] }

        // `visibleConversations` excludes threads the user has cleared from the feed.
        return messageStore.visibleConversations
            .sorted { ($0.lastMessageTimestamp ?? .distantPast) > ($1.lastMessageTimestamp ?? .distantPast) }
            .compactMap { convo -> (otherUserID: String, row: NetworkConversation)? in
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

                let row = NetworkConversation(
                    conversationID: convo.id,
                    name: user.fullName,
                    lastMessage: convo.lastMessagePreview ?? "",
                    timestamp: convo.lastMessageTimestamp ?? Date(),
                    // Per-user unread, derived from local messages (not the shared
                    // Conversation.unreadCount field, which can't be per-participant).
                    unread: messageStore.unreadCount(for: convo.id) > 0,
                    avatarImageData: user.profileImageData,
                    currentProject: currentProjectTitle(for: user)
                )
                return (otherUserID: otherID, row: row)
            }
    }

    /// Strips the `UserProfile_` prefix so a directory record name and a raw
    /// CloudKit user record name compare equal (matches UserProfileManager).
    private static func normalizedID(_ id: String) -> String {
        let prefix = "UserProfile_"
        return id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id
    }

    // MARK: - Current Project

    /// The title of the project `user` is currently working on, or `nil` if none.
    ///
    /// A "current project" is an approved Cast & Crew Call (from the schools this
    /// user sees) that the person posted or is on the assembled cast/crew of, and
    /// whose shoot hasn't wrapped yet — the same completed-shoot rule Discover uses
    /// to split its project feed. Projects with TBD dates count as current. When
    /// someone is on several, the most recently posted one wins.
    private func currentProjectTitle(for user: DirectoryUser) -> String? {
        let name = user.fullName
        let userID = Self.normalizedID(user.messagingUserID)
        guard !name.isEmpty else { return nil }

        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)

        func isAttached(_ project: Submission) -> Bool {
            if project.submittedBy == name { return true }
            return (project.orderedCast + project.orderedCrew).contains { entry in
                if let profileID = entry.profileID, !profileID.isEmpty {
                    return Self.normalizedID(profileID) == userID
                }
                return entry.name == name
            }
        }

        func hasWrapped(_ project: Submission) -> Bool {
            switch project.shootSchedule {
            case .days(let days)?:
                return days.last.map { ($0.end ?? $0.start) < now } ?? false
            case .range(let start, let end)?:
                return (end ?? start) < startOfToday
            case nil:
                return false
            }
        }

        let current = submissionStore.visibleApprovedSubmissions
            .filter { $0.type == .project && !hasWrapped($0) && isAttached($0) }
            .max { $0.createdDate < $1.createdDate }

        let title = current?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? nil : title
    }

    @State private var showNewMessage = false
    @State private var showDirectory = false
    @State private var selectedChat: NetworkConversation?

    /// Which feed the toolbar toggle shows: every thread, or only unread ones.
    enum FeedMode: String, CaseIterable, Identifiable {
        case all
        case unread

        var id: String { rawValue }

        /// A tray for all messages, a badged envelope for unread.
        var symbol: String {
            switch self {
            case .all: return "tray.fill"
            case .unread: return "envelope.badge.fill"
            }
        }

        var label: String {
            switch self {
            case .all: return "All Messages"
            case .unread: return "Unread Messages"
            }
        }

        var emptyText: String {
            switch self {
            case .all: return "No messages."
            case .unread: return "No unread messages."
            }
        }
    }

    @State private var feedMode: FeedMode = .all

    /// The conversations for the selected feed mode. Unread is a filter over the
    /// same list, keyed off each row's per-user unread flag.
    private var displayedConversations: [NetworkConversation] {
        switch feedMode {
        case .all: return conversations
        case .unread: return conversations.filter(\.unread)
        }
    }

    // Define colors as static constants to prevent color changes on tab switch
    private static let darkBrownColor = Color(red: 80/255, green: 50/255, blue: 30/255).opacity(1.0)  // Darker for unselected
    private static let mediumBrownColor = Color(red: 140/255, green: 90/255, blue: 55/255).opacity(1.0)  // Brighter for selected
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                Group {
                    if displayedConversations.isEmpty {
                    VStack(spacing: 0) {
                        Text(feedMode.emptyText)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                        
                        Divider()
                        
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(displayedConversations) { conversation in
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
                                                .lineLimit(1)
                                                // The name never truncates; the project title gives way.
                                                .layoutPriority(1)

                                            // The project they're currently working on, if any.
                                            if let project = conversation.currentProject {
                                                Text(project)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                            }

                                            Spacer()

                                            // Connections without a thread have no time to show.
                                            if let timestamp = conversation.timestamp {
                                                Text(formatTimestamp(timestamp))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        HStack {
                                            // "Say hi!" is tinted so it reads as an invitation,
                                            // not a message the other person sent.
                                            Text(conversation.lastMessage)
                                                .font(.subheadline)
                                                .foregroundStyle(conversation.isSayHi ? Color.brandOrange
                                                                 : (conversation.unread ? .primary : .secondary))
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
                                // "Say hi!" rows have no thread to clear.
                                if let conversationID = conversation.conversationID {
                                    Button {
                                        messageStore.clearConversation(conversationID)
                                    } label: {
                                        Label("Clear", systemImage: "xmark.circle")
                                    }
                                    .tint(.gray)
                                }
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomTrailing) {
                    composeButton
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
        // iPad keeps the iPhone layout and sizes for this page.
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return FeedFormat(avatarSize: 57, avatarEmojiSize: 41, nameFontSize: 16, rowVerticalPadding: 15)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return FeedFormat(avatarSize: 57, avatarEmojiSize: 41, nameFontSize: 16, rowVerticalPadding: 15)
        }
    }

    // MARK: - Toolbar Format Per Screen Size
    /// Tunable toolbar item sizes and positions for the Network page.
    /// - `directoryFontSize/pillHeight`: size of the Directory pill.
    /// - `composeWidth/composeFontSize`: width and symbol size of each segment of
    ///   the All / Unread feed toggle.
    /// - `pillOffsetX/Y`: nudges both pills from their default spot.
    /// - `logoHeight`: height of the Network logo image.
    private struct ToolbarFormat {
        var directoryFontSize: CGFloat
        var composeWidth: CGFloat
        var composeFontSize: CGFloat
        /// On-screen height of both pills, shared with the other pages (see
        /// `ScreenSizeFormat.toolbarPillHeight`). Buttons divide it by their own
        /// `scaleEffect` so the rendered height matches Home's exactly.
        var pillHeight: CGFloat = ScreenSizeFormat.toolbarPillHeight
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
    private var networkSize: CGFloat { 1.35 }       // size multiplier
    private var networkOffsetX: CGFloat { 2 }      // + = right
    private var networkOffsetY: CGFloat { -2 }      // + = down
    // Directory & New Message buttons (moved/sized together).
    private var dirMsgSize: CGFloat { 1.1 }
    private var dirMsgOffsetX: CGFloat { 0 }
    private var dirMsgOffsetY: CGFloat { -4 }    // matches Home/Discover pill center (measured)
    private var dirMsgPadding: CGFloat { 0 }    // space reserved around each
    // All / Unread feed toggle (moved/sized independently of Directory).
    private var feedToggleSize: CGFloat { 1.1 }     // size multiplier
    private var feedToggleOffsetX: CGFloat { 0 }    // + = right
    private var feedToggleOffsetY: CGFloat { -4 }   // + = down (starts level with Directory)
    private var feedTogglePadding: CGFloat { 0 }    // space reserved around it

    /// Pre-scale button height: the shared pill height divided by the buttons'
    /// `scaleEffect`, so both pills render at exactly the Home pill's height.
    private var dirMsgPillHeight: CGFloat { toolbarFormat.pillHeight / dirMsgSize }
    private var feedTogglePillHeight: CGFloat { toolbarFormat.pillHeight / feedToggleSize }

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
            return ToolbarFormat(directoryFontSize: 14, composeWidth: 36, composeFontSize: 15, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 28, barHeight: 50)
        case .size402x874: // iPhone 16 Pro, 17
            return ToolbarFormat(directoryFontSize: 14, composeWidth: 36, composeFontSize: 15, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 29, barHeight: 50)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return ToolbarFormat(directoryFontSize: 15, composeWidth: 38, composeFontSize: 16, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 30, barHeight: 52)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return ToolbarFormat(directoryFontSize: 16, composeWidth: 39, composeFontSize: 16, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 32, barHeight: 53)
        // iPad: the orange bar spans the screen, but its contents stay iPhone-sized and
        // centered (see `ScreenSizeFormat.toolbarContentMaxWidth`), so these match the phone.
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return ToolbarFormat(directoryFontSize: 14, composeWidth: 36, composeFontSize: 15, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 29, barHeight: 50)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return ToolbarFormat(directoryFontSize: 14, composeWidth: 36, composeFontSize: 15, pillOffsetX: -3, pillOffsetY: 0, logoHeight: 29, barHeight: 50)
        }
    }

    // ORANGE HEADER
    private var topBar: some View {
        HStack(spacing: 0) {
            SchoolAssetImage("Network")
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
        // iPad: keep the wordmark and pills iPhone-sized and centered while the orange
        // bar behind them still runs edge to edge. `nil` (no limit) on iPhone.
        .frame(maxWidth: ScreenSizeFormat.toolbarContentMaxWidth)
        .padding(.vertical, 6)
        // Orange fills the bar and bleeds up behind the status bar / Dynamic Island.
        .frame(maxWidth: .infinity, minHeight: toolbarFormat.barHeight, maxHeight: toolbarFormat.barHeight)
        .background(Color.brandOrange, ignoresSafeAreaEdges: .top)
    }

    // TOOLBAR PILLS (distinct buttons with space between them)
    private var filterPill: some View {
        HStack(spacing: 10) {
            feedToggle

            Button {
                showDirectory = true
            } label: {
                Text("Directory")
                    .font(.system(size: toolbarFormat.directoryFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: toolbarFormat.pillLength, height: dirMsgPillHeight)
                    .padding(.horizontal, 10)
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

    /// Two-segment pill left of Directory: a tray for all threads, a badged
    /// envelope for unread only. The selected segment is highlighted and the
    /// feed below filters to match. Styled and positioned like the Directory pill.
    private var feedToggle: some View {
        HStack(spacing: 0) {
            ForEach(FeedMode.allCases) { mode in
                Button {
                    feedMode = mode
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: toolbarFormat.composeFontSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: toolbarFormat.composeWidth, height: feedTogglePillHeight)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.label)
                .accessibilityAddTraits(feedMode == mode ? .isSelected : [])
            }
        }
        // HIGHLIGHTED CAPSULE: one capsule slides between the segments on selection,
        // using the same spring as the Home and Discover toggles.
        .background(alignment: .leading) {
            Capsule()
                .fill(Color.pillBackground)
                .frame(width: feedHighlightWidth, height: feedHighlightHeight)
                .offset(x: feedHighlightOffsetX)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: feedMode)
        }
        .background(Capsule().fill(Color.pillActive))
        .offset(x: toolbarFormat.pillOffsetX, y: toolbarFormat.pillOffsetY)
        .padding(feedTogglePadding)
        .scaleEffect(feedToggleSize)
        .offset(x: feedToggleOffsetX, y: feedToggleOffsetY)
    }

    /// How much smaller the highlight capsule is than the segment it sits behind.
    /// 1.0 fills the segment; smaller values leave a visible ring of the outer pill.
    private var feedHighlightScale: CGFloat { 0.8 }

    /// Size of the highlight capsule: the segment's width and height reduced by
    /// `feedHighlightScale`.
    private var feedHighlightWidth: CGFloat { toolbarFormat.composeWidth * feedHighlightScale }
    private var feedHighlightHeight: CGFloat { feedTogglePillHeight * feedHighlightScale }

    /// Leading offset of the feed toggle's highlight capsule: one segment width per
    /// position of the selected mode, with the (narrower) capsule centered in it.
    private var feedHighlightOffsetX: CGFloat {
        let index = CGFloat(FeedMode.allCases.firstIndex(of: feedMode) ?? 0)
        return index * toolbarFormat.composeWidth + (toolbarFormat.composeWidth - feedHighlightWidth) / 2
    }

    // MARK: - New Message Button (floating, bottom-right of the feed)
    /// Tunable sizing for the floating compose button, per screen size.
    /// - `diameter`: size of the circle.
    /// - `iconSize`: size of the pencil symbol inside it.
    /// - `edgePadding`: distance from the trailing and bottom edges of the feed.
    private struct ComposeButtonFormat {
        var diameter: CGFloat
        var iconSize: CGFloat
        var edgePadding: CGFloat
    }

    private var composeButtonFormat: ComposeButtonFormat {
        switch ScreenSizeFormat.current {
        case .size393x852:
            return ComposeButtonFormat(diameter: 60, iconSize: 24, edgePadding: 20)
        case .size402x874:
            return ComposeButtonFormat(diameter: 61, iconSize: 24, edgePadding: 20)
        case .size430x932:
            return ComposeButtonFormat(diameter: 64, iconSize: 26, edgePadding: 22)
        case .size440x956:
            return ComposeButtonFormat(diameter: 65, iconSize: 26, edgePadding: 22)
        // iPad keeps the iPhone size for this button.
        case .iPad11:
            return ComposeButtonFormat(diameter: 61, iconSize: 24, edgePadding: 20)
        case .iPad13:
            return ComposeButtonFormat(diameter: 61, iconSize: 24, edgePadding: 20)
        }
    }

    /// Large brand-orange Liquid Glass circle, like the iOS 26 Messages compose button.
    private var composeButton: some View {
        Button {
            showNewMessage = true
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: composeButtonFormat.iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: composeButtonFormat.diameter, height: composeButtonFormat.diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(BrandGlassCircle())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .accessibilityLabel("New Message")
        .padding(.trailing, composeButtonFormat.edgePadding)
        .padding(.bottom, composeButtonFormat.edgePadding)
    }

    /// Brand-orange tinted Liquid Glass circle on iOS 26+, solid orange circle otherwise.
    private struct BrandGlassCircle: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.tint(Color.brandOrange).interactive(), in: .circle)
            } else {
                content.background(Circle().fill(Color.brandOrange))
            }
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
        // Refresh the conversation feed and the connections shown as "Say hi!" rows
        try? await messageStore.fetchConversations()
        await connections.refresh()

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
        // Pick up any connections made since the last visit for the "Say hi!" rows.
        await connections.refresh()
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
