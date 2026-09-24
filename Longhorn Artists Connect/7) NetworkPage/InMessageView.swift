//
//  InMessageView.swift
//  Longhorn Artists Connect
//
//  In-conversation messaging view with attachments support
//

import SwiftUI
import PhotosUI
import CloudKit

struct InMessageView: View {
    // MARK: - Properties
    
    let conversationID: UUID
    let otherUserID: String
    let otherUserName: String
    let otherUserRole: String
    /// When false, hides the built-in nav-bar header (avatar + name) so a host view —
    /// e.g. the New Message composer, which shows its own "To:" bar — can own the top.
    var showsHeader: Bool = true

    @Environment(\.dismiss) private var dismiss

    @StateObject private var messageStore = MessageStore.shared
    @StateObject private var profileManager = UserProfileManager.shared
    @ObservedObject private var blockManager = BlockedUsersManager.shared
    @ObservedObject private var convoPrefs = ConversationPreferencesManager.shared
    @State private var messages: [Message] = []
    @State private var currentUserID: String?
    /// The deterministic thread ID for this pair of users, resolved once the
    /// current user's ID is known. This is where messages are actually stored,
    /// so it — not the passed-in `conversationID` — drives fetching/observing.
    @State private var activeConversationID: UUID?
    
    @State private var newMessageText = ""
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var attachmentURL: URL?
    @State private var attachmentType: Message.AttachmentType?
    
    @State private var isLoadingMessages = false
    /// True while a send is in flight. Blocks a second send before the first
    /// round-trip finishes — that gap previously let a tap-happy user (or one who
    /// saw no immediate feedback) create two identical messages, and two push banners.
    @State private var isSending = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    @FocusState private var isInputFocused: Bool
    
    @State private var showRecipientProfile = false
    @State private var showBlockConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            if isLoadingMessages {
                ProgressView("Loading messages...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if messages.isEmpty {
                Text("Start the conversation!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                messagesScrollView
            }
            
            Divider()
            
            // Input area
            messageInputArea
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsHeader {
                // Profile picture pinned to the leading edge, like a standard
                // messaging app. The navigation bar provides the background and
                // hairline separator from the messages below.
                ToolbarItem(placement: .topBarLeading) {
                    otherUserAvatar
                }
                // Recipient's name centered in the middle of the header bar.
                ToolbarItem(placement: .principal) {
                    Text(resolvedOtherUserName)
                        .font(.headline)
                }
                // Overflow menu, opposite the avatar: view profile, block/unblock.
                ToolbarItem(placement: .topBarTrailing) {
                    moreMenu
                }
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
        .sheet(isPresented: $showDocumentPicker) {
            InMessageDocumentPickerView { url in
                handleDocumentSelection(url)
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            if let newValue {
                handlePhotoSelection(newValue)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .task {
            await loadMessages()
            // Ensure the directory is loaded so the header avatar can appear
            // (throttled internally, so this is cheap if already fetched).
            await profileManager.fetchAllUsers()
        }
        .onReceive(messageStore.$messagesByConversation) { messagesByConversation in
            let threadID = activeConversationID ?? conversationID
            if let conversationMessages = messagesByConversation[threadID] {
                self.messages = conversationMessages
            }
        }
        .sheet(isPresented: $showRecipientProfile) {
            PersonProfileView(name: otherUserName)
        }
        .presentationDragIndicator(.hidden)
    }

    // MARK: - View Components
    
    /// Directory entry for the person being messaged, used for their avatar.
    /// Falls back to a name match because some flows pass a local UUID
    /// instead of the CloudKit record name as `otherUserID`.
    private var otherUser: DirectoryUser? {
        profileManager.findUser(byID: otherUserID)
            ?? profileManager.allUsers.first { $0.fullName == otherUserName }
    }

    /// The header name, preferring the freshly-resolved directory entry so it
    /// self-corrects if the caller passed a placeholder (e.g. "Unknown User").
    private var resolvedOtherUserName: String {
        otherUser?.displayName ?? otherUserName
    }
    
    /// Tapping the avatar opens the recipient's profile page.
    private var otherUserAvatar: some View {
        Button {
            showRecipientProfile = true
        } label: {
            // Fill the fixed circular frame then clip, so the image is always
            // centered and never stretched/deformed while the sheet is dragged.
            Group {
                if let imageData = otherUser?.profileImageData,
                   let uiImage = UIImage(data: imageData) {
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
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
    
    /// Overflow ("…") menu shown opposite the avatar. Pin/mute the thread or
    /// block the person. (The avatar itself opens the profile.)
    private var moreMenu: some View {
        Menu {
            Button {
                convoPrefs.togglePin(otherUserID)
            } label: {
                Label(convoPrefs.isPinned(otherUserID) ? "Unpin Conversation" : "Pin Conversation",
                      systemImage: convoPrefs.isPinned(otherUserID) ? "pin.slash" : "pin")
            }

            Button {
                convoPrefs.toggleMute(otherUserID)
            } label: {
                // Short labels so the system menu (which has a fixed max width and won't
                // widen) keeps each row on one line — the bell icon conveys "notifications".
                Label(convoPrefs.isMuted(otherUserID) ? "Unmute Notifs" : "Mute Notifications",
                      systemImage: convoPrefs.isMuted(otherUserID) ? "bell.slash" : "bell")
            }

            Divider()

            if blockManager.isBlocked(otherUserID) {
                Button {
                    blockManager.unblock(otherUserID)
                } label: {
                    Label("Unblock", systemImage: "hand.raised.slash")
                }
            } else {
                Button(role: .destructive) {
                    // Defer to the next runloop so the menu finishes dismissing before
                    // the confirmation presents — otherwise SwiftUI swallows it and the
                    // dialog never appears.
                    DispatchQueue.main.async { showBlockConfirmation = true }
                } label: {
                    Label("Block", systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
        }
        // Anchor the block confirmation to the ellipsis so, when shown as a popover,
        // its tail points at the "…" rather than the middle of the screen.
        .confirmationDialog(
            "Block \(resolvedOtherUserName)?",
            isPresented: $showBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                blockManager.block(otherUserID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see \(resolvedOtherUserName) in your messages or the directory, and they won't be able to reach you. You can unblock them anytime.")
        }
    }

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        MessageBubbleView(
                            message: message,
                            isFromCurrentUser: message.senderUserID == currentUserID,
                            showsTimestamp: shouldShowTimestamp(at: index),
                            attachmentURL: messageStore.attachmentURLs[message.id]
                        )
                        .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Show a timestamp only when a message starts a new time group — the first
    /// message, or one sent at least an hour after the previous one. This keeps
    /// 1-on-1 threads from repeating the time on every bubble.
    private func shouldShowTimestamp(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let interval = messages[index].timestamp.timeIntervalSince(messages[index - 1].timestamp)
        return interval >= 3600
    }

    private var messageInputArea: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                // Attachment button
                attachmentButton

                // Text input (with any staged attachment thumbnail inside the bubble)
                messageInputBubble

                // Send button — the same arrow sends text and/or the attachment.
                sendButton
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .systemBackground))
    }

    /// The rounded input field. When a photo/file is staged, its thumbnail sits
    /// inside the bubble above the text — like iMessage — and is sent with the
    /// same arrow button.
    private var messageInputBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            if attachmentURL != nil {
                stagedAttachmentThumbnail
            }

            TextField("Message", text: $newMessageText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isInputFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    /// The staged attachment's thumbnail (image) or icon (video/file), shown inside
    /// the input bubble with an "x" to remove it before sending.
    @ViewBuilder
    private var stagedAttachmentThumbnail: some View {
        if let attachmentURL {
            ZStack(alignment: .topTrailing) {
                Group {
                    if attachmentType == .image, let image = UIImage(contentsOfFile: attachmentURL.path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: attachmentType == .video ? "video.fill" : "doc.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.brandOrange)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 70, height: 70)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    self.attachmentURL = nil
                    self.attachmentType = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .padding(4)
            }
        }
    }

    private var attachmentButton: some View {
        Menu {
            Button {
                isInputFocused = false
                showPhotoPicker = true
            } label: {
                Label("Photos", systemImage: "photo.stack")
            }

            Button {
                isInputFocused = false
                showDocumentPicker = true
            } label: {
                Label("Files", systemImage: "folder")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.brandOrange)
        }
        .menuOrder(.fixed)
    }
    
    private var sendButton: some View {
        Button {
            sendMessage()
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(sendButtonColor)
        }
        .disabled(!canSend)
    }

    /// A message can be sent when there's text or a staged attachment — and not while
    /// a previous send is still in flight, so the same message can't be sent twice.
    private var canSend: Bool {
        guard !isSending else { return false }
        return !newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachmentURL != nil
    }

    private var sendButtonColor: Color {
        canSend ? Color.brandOrange : .secondary
    }
    
    // MARK: - Actions
    
    private func loadMessages() async {
        isLoadingMessages = true
        defer { isLoadingMessages = false }
        
        // Get current user ID
        do {
            let userRecordID = try await CKContainer.default().userRecordID()
            currentUserID = userRecordID.recordName
        } catch {
            errorMessage = "Failed to authenticate with iCloud"
            showError = true
            return
        }

        // Resolve the shared thread ID for these two users. Both participants
        // compute the same value, so we always read/write the one thread.
        let threadID = Conversation.deterministicID(currentUserID ?? "", otherUserID)
        activeConversationID = threadID

        // Fetch messages
        do {
            let fetchedMessages = try await messageStore.fetchMessages(for: threadID)
            self.messages = fetchedMessages

            // Mark conversation as read
            try? await messageStore.markConversationAsRead(threadID)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func sendMessage() {
        let messageContent = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageContent.isEmpty || attachmentURL != nil else { return }
        // Ignore a repeat tap while the previous send is still round-tripping to
        // CloudKit — otherwise the same message is sent (and pushed) twice.
        guard !isSending else { return }

        // Capture the payload, then clear the input immediately. Clearing up front
        // gives instant feedback (so the user doesn't tap again thinking nothing
        // happened) and, with `isSending`, closes the double-send window. On failure
        // we restore the text so nothing is lost.
        let sentAttachmentURL = attachmentURL
        let sentAttachmentType = attachmentType
        isSending = true
        newMessageText = ""
        attachmentURL = nil
        attachmentType = nil

        Task {
            do {
                _ = try await messageStore.sendMessage(
                    to: otherUserID,
                    content: messageContent,
                    conversationID: conversationID,
                    attachmentURL: sentAttachmentURL,
                    attachmentType: sentAttachmentType
                )
                await MainActor.run { isSending = false }
            } catch {
                await MainActor.run {
                    // Restore what the user typed so the failed send can be retried.
                    newMessageText = messageContent
                    attachmentURL = sentAttachmentURL
                    attachmentType = sentAttachmentType
                    isSending = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func handlePhotoSelection(_ item: PhotosPickerItem) {
        Task {
            // Only still photos are allowed (videos take up too much storage), so the
            // picker is limited to `.images` and every selection is treated as one.
            if let data = try? await item.loadTransferable(type: Data.self) {
                // Save to temporary location
                let tempDir = FileManager.default.temporaryDirectory
                let filename = "\(UUID().uuidString).\(item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg")"
                let tempURL = tempDir.appendingPathComponent(filename)

                try? data.write(to: tempURL)

                attachmentType = .image
                attachmentURL = tempURL

                print("📷 Photo ready to send")
            }

            await MainActor.run {
                selectedPhoto = nil
            }
        }
    }
    
    private func handleDocumentSelection(_ url: URL) {
        // Copy document to temporary location
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(url.lastPathComponent)
        
        do {
            // Access security-scoped resource
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            // Copy file
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.copyItem(at: url, to: tempURL)
            
            attachmentURL = tempURL
            attachmentType = .document
            
            print("📄 Document ready to send: \(url.lastPathComponent)")
            
        } catch {
            errorMessage = "Failed to prepare document: \(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: Message
    let isFromCurrentUser: Bool
    /// Whether to show the timestamp beneath this bubble. Only true when the
    /// message starts a new time group (see `shouldShowTimestamp(at:)`).
    let showsTimestamp: Bool
    /// Local file URL for this message's attachment, if it's been downloaded/cached.
    var attachmentURL: URL? = nil

    @State private var showPostDetail = false
    @State private var postLiked = false

    /// Bubble fill: brand orange for the current user, neutral for the other person.
    private var bubbleColor: Color {
        isFromCurrentUser ? Color.brandOrange : Color.secondary.opacity(0.15)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isFromCurrentUser {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Message content
                if message.attachmentType == .post {
                    // Shared post: its own bubble (artwork + title), plus any note.
                    // Tapping opens the post's detail page.
                    Button {
                        if sharedPost != nil { showPostDetail = true }
                    } label: {
                        SharedPostMessageBubble(
                            thumbnail: sharedPostThumbnail,
                            title: sharedPostTitle,
                            placeholderSymbol: sharedPostSymbol,
                            isFromCurrentUser: isFromCurrentUser
                        )
                    }
                    .buttonStyle(.plain)

                    if !message.content.isEmpty {
                        Text(message.content)
                            .textBubble(isFromCurrentUser: isFromCurrentUser, fill: bubbleColor)
                    }
                } else {
                    // Media attachment (image/video/document) renders as its own bubble.
                    if message.attachmentType != nil {
                        AttachmentPreview(
                            attachmentType: message.attachmentType,
                            localURL: attachmentURL,
                            fileName: message.attachmentFileName,
                            isFromCurrentUser: isFromCurrentUser
                        )
                    }

                    // Any accompanying text sits in its own speech bubble below.
                    if !message.content.isEmpty {
                        Text(message.content)
                            .textBubble(isFromCurrentUser: isFromCurrentUser, fill: bubbleColor)
                    }
                }
                
                // Timestamp — only when this message starts a new time group.
                if showsTimestamp {
                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: 280, alignment: isFromCurrentUser ? .trailing : .leading)
            
            if !isFromCurrentUser {
                Spacer(minLength: 60)
            }
        }
        .sheet(isPresented: $showPostDetail) {
            sharedPostDetail
        }
    }

    /// The correct detail page for the shared post's media type.
    @ViewBuilder
    private var sharedPostDetail: some View {
        if let post = sharedPost {
            switch post.type {
            case .film, .music, .reel, .photography, .design:
                PostDetailRouter(post: post, liked: $postLiked)
            case .project:
                UpcomingProjectDetailView(submission: post)
            case .event:
                EventDetailView(event: post)
            }
        }
    }

    // MARK: - Shared Post Lookup

    /// The shared submission for a `.post` message, looked up by the UUID stored
    /// in `attachmentFileName`. Nil if the post isn't available locally yet.
    private var sharedPost: Submission? {
        guard message.attachmentType == .post,
              let idString = message.attachmentFileName,
              let uuid = UUID(uuidString: idString) else { return nil }
        return SubmissionStore_3_2.shared.approvedSubmissions.first { $0.id == uuid }
    }

    private var sharedPostThumbnail: UIImage? {
        guard let data = sharedPost?.thumbnailData else { return nil }
        return UIImage(data: data)
    }

    private var sharedPostTitle: String {
        sharedPost?.title ?? "Shared post"
    }

    private var sharedPostSymbol: String {
        switch sharedPost?.type {
        case .music: return "music.note"
        case .reel:  return "video"
        case .event: return "calendar"
        case .project: return "movieclapper"
        default: return "film"
        }
    }

    private func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        
        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            formatter.timeStyle = .short
            return "Yesterday, \(formatter.string(from: date))"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Shared Post Message

/// A message-bubble style for a post shared from one profile to another: a small
/// version of the post's thumbnail / album cover / flyer, with the title beneath.
/// This is the visual template — wire it into the message model once the look is set.
struct SharedPostMessageBubble: View {
    /// The post's thumbnail, album cover, or flyer.
    let thumbnail: UIImage?
    /// The post's title, shown under the artwork.
    let title: String
    /// Fallback SF Symbol shown when no artwork is available (e.g. "film", "music.note").
    var placeholderSymbol: String = "film"
    /// Tints/aligns the bubble like a sent (true) vs received (false) message.
    var isFromCurrentUser: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let thumbnail {
                    // Preserve the thumbnail's own aspect ratio, bounded by a max width.
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 180)
                } else {
                    // No artwork yet — fall back to a poster-shaped placeholder.
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 140, height: 180)
                        .overlay {
                            Image(systemName: placeholderSymbol)
                                .font(.system(size: 30))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 180)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isFromCurrentUser ? Color.brandOrange : Color.secondary.opacity(0.15))
        )
        .foregroundStyle(isFromCurrentUser ? .white : .primary)
    }
}

// MARK: - Attachment Preview

struct AttachmentPreview: View {
    let attachmentType: Message.AttachmentType?
    /// Local file URL for the attachment once it's been downloaded/cached.
    var localURL: URL? = nil
    /// The original file name, used to label documents.
    var fileName: String? = nil
    /// Tints the document chip like a sent (true) vs received (false) message.
    var isFromCurrentUser: Bool = false

    private let mediaCornerRadius: CGFloat = 18

    var body: some View {
        switch attachmentType {
        case .image:
            imageView

        case .video:
            videoView

        case .document:
            documentView

        case .post, .none:
            // Shared posts are rendered by SharedPostMessageBubble, not here.
            EmptyView()
        }
    }

    /// The real image, clipped to a rounded bubble. Falls back to a loading tile
    /// while the file is still downloading from CloudKit.
    @ViewBuilder
    private var imageView: some View {
        if let localURL, let uiImage = UIImage(contentsOfFile: localURL.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240)
                .clipShape(RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous))
        } else {
            loadingTile(symbol: "photo")
        }
    }

    /// A video tile with a play glyph. (Frame extraction is out of scope, so we
    /// show a consistent poster rather than the first frame.)
    private var videoView: some View {
        RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.85))
            .frame(width: 200, height: 150)
            .overlay {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.9))
            }
    }

    private var documentView: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.system(size: 30))
                .foregroundStyle(isFromCurrentUser ? .white : Color.brandOrange)

            Text(fileName ?? "Document")
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .truncationMode(.middle)
                .foregroundStyle(isFromCurrentUser ? .white : .primary)
        }
        .padding(12)
        .frame(maxWidth: 240, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous)
                .fill(isFromCurrentUser ? Color.brandOrange : Color.secondary.opacity(0.15))
        )
    }

    private func loadingTile(symbol: String) -> some View {
        RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous)
            .fill(Color.gray.opacity(0.25))
            .frame(width: 200, height: 150)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    ProgressView()
                }
            }
    }
}

// MARK: - Text Bubble Styling

extension View {
    /// Styles a text message as a speech bubble. The `MessageBubbleShape` reserves
    /// space on the tail side and along the bottom for the tail, so the text is
    /// padded extra on those edges to stay optically centered within the visible body.
    func textBubble(isFromCurrentUser: Bool, fill: Color) -> some View {
        let shape = MessageBubbleShape(isFromCurrentUser: isFromCurrentUser)
        return self
            .font(.body)
            .padding(.top, 10)
            .padding(.bottom, 10 + shape.tailDrop)
            .padding(.leading, 14 + (isFromCurrentUser ? 0 : shape.tailWidth))
            .padding(.trailing, 14 + (isFromCurrentUser ? shape.tailWidth : 0))
            .background(shape.fill(fill))
            .foregroundStyle(isFromCurrentUser ? .white : .primary)
    }
}

// MARK: - Message Bubble Shape

/// An iMessage-style speech bubble: a rounded rectangle with a small tail curling
/// out of the bottom corner — trailing for the current user's messages, leading for
/// the other person's. The tail is drawn within the shape's own frame, inset a few
/// points on the tail side, so callers can use it as a drop-in background/clip shape.
struct MessageBubbleShape: Shape {
    let isFromCurrentUser: Bool
    var cornerRadius: CGFloat = 17
    /// Horizontal space reserved on the tail side for the tail to occupy.
    /// The tail curls out of the bottom corner into this strip.
    var tailWidth: CGFloat = 7
    /// Kept for the `textBubble` padding math; the tail no longer dips below the body.
    var tailDrop: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        // The rounded body leaves `tailWidth` of room on the tail side; the tail
        // curls out of the bottom corner into that reserved strip, hugging the
        // bottom edge the way iMessage bubbles do.
        let r = min(cornerRadius, min(w - tailWidth, h) / 2)
        var path = Path()

        if isFromCurrentUser {
            let bodyRight = w - tailWidth
            // Body, clockwise from the top-left corner.
            path.move(to: CGPoint(x: r, y: 0))
            path.addLine(to: CGPoint(x: bodyRight - r, y: 0))
            path.addQuadCurve(to: CGPoint(x: bodyRight, y: r),
                              control: CGPoint(x: bodyRight, y: 0))
            // Right edge down to where the tail begins to swing out.
            path.addLine(to: CGPoint(x: bodyRight, y: h - r))
            // Convex outer edge swinging out to a rounded tail tip that sits on
            // the baseline just past the body — a gentle bulge, not a sharp beak.
            path.addQuadCurve(to: CGPoint(x: w, y: h),
                              control: CGPoint(x: bodyRight, y: h - r * 0.55))
            // Tight concave curl back under the tail to the bottom edge, ending
            // close to the corner so the tail reads as a small hook.
            path.addQuadCurve(to: CGPoint(x: bodyRight - r * 0.35, y: h),
                              control: CGPoint(x: bodyRight, y: h))
            // Bottom edge and remaining corners.
            path.addLine(to: CGPoint(x: r, y: h))
            path.addQuadCurve(to: CGPoint(x: 0, y: h - r),
                              control: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: 0, y: r))
            path.addQuadCurve(to: CGPoint(x: r, y: 0),
                              control: CGPoint(x: 0, y: 0))
            path.closeSubpath()
        } else {
            let bodyLeft = tailWidth
            // Body, counter-clockwise from the top-right corner.
            path.move(to: CGPoint(x: w - r, y: 0))
            path.addLine(to: CGPoint(x: bodyLeft + r, y: 0))
            path.addQuadCurve(to: CGPoint(x: bodyLeft, y: r),
                              control: CGPoint(x: bodyLeft, y: 0))
            // Left edge down to where the tail begins to swing out.
            path.addLine(to: CGPoint(x: bodyLeft, y: h - r))
            // Convex outer edge swinging out to a rounded tail tip on the baseline.
            path.addQuadCurve(to: CGPoint(x: 0, y: h),
                              control: CGPoint(x: bodyLeft, y: h - r * 0.55))
            // Tight concave curl back under the tail to the bottom edge.
            path.addQuadCurve(to: CGPoint(x: bodyLeft + r * 0.35, y: h),
                              control: CGPoint(x: bodyLeft, y: h))
            // Bottom edge and remaining corners.
            path.addLine(to: CGPoint(x: w - r, y: h))
            path.addQuadCurve(to: CGPoint(x: w, y: h - r),
                              control: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: w, y: r))
            path.addQuadCurve(to: CGPoint(x: w - r, y: 0),
                              control: CGPoint(x: w, y: 0))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Document Picker

struct InMessageDocumentPickerView: UIViewControllerRepresentable {
    let onSelect: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .text, .plainText, .data])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL) -> Void
        
        init(onSelect: @escaping (URL) -> Void) {
            self.onSelect = onSelect
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onSelect(url)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        InMessageView(
            conversationID: UUID(),
            otherUserID: "mockUserID",
            otherUserName: "Sarah Johnson",
            otherUserRole: "Director"
        )
    }
}

// Text-bubble tail shape, sent + received, for tuning MessageBubbleShape.
#Preview("Text Bubbles") {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            Text("What up buddy")
                .textBubble(isFromCurrentUser: false, fill: Color.secondary.opacity(0.15))
            Spacer(minLength: 60)
        }
        HStack {
            Text("Does ts work yet")
                .textBubble(isFromCurrentUser: false, fill: Color.secondary.opacity(0.15))
            Spacer(minLength: 60)
        }
        HStack {
            Spacer(minLength: 60)
            Text("You get this?")
                .textBubble(isFromCurrentUser: true, fill: Color.brandOrange)
        }
        HStack {
            Spacer(minLength: 60)
            Text("Hell yeah")
                .textBubble(isFromCurrentUser: true, fill: Color.brandOrange)
        }
    }
    .padding()
}

// Template conversation showing the shared-post message style in both a received
// and a sent position. Tweak `SharedPostMessageBubble` to change the look.
#Preview("Shared Post Message") {
    VStack(spacing: 16) {
        // Received
        HStack {
            SharedPostMessageBubble(
                thumbnail: nil,
                title: "The Midnight Garden",
                placeholderSymbol: "film"
            )
            Spacer(minLength: 60)
        }
        // Sent
        HStack {
            Spacer(minLength: 60)
            SharedPostMessageBubble(
                thumbnail: nil,
                title: "Neon Dreams",
                placeholderSymbol: "music.note",
                isFromCurrentUser: true
            )
        }
    }
    .padding()
}
