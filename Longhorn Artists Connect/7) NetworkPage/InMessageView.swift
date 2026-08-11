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
    
    @StateObject private var messageStore = MessageStore.shared
    @StateObject private var profileManager = UserProfileManager.shared
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
    @State private var showError = false
    @State private var errorMessage = ""
    
    @FocusState private var isInputFocused: Bool
    
    @State private var showRecipientProfile = false
    
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
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .any(of: [.images, .videos]))
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
    
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        MessageBubbleView(
                            message: message,
                            isFromCurrentUser: message.senderUserID == currentUserID,
                            senderName: message.senderUserID == currentUserID ? "You" : resolvedOtherUserName
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
    
    private var messageInputArea: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                // Attachment button
                attachmentButton
                
                // Text input
                messageTextField
                
                // Send button
                sendButton
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .systemBackground))
    }
    
    private var attachmentButton: some View {
        Menu {
            Button {
                isInputFocused = false
                showPhotoPicker = true
            } label: {
                Label("Photo or Video", systemImage: "photo")
            }

            Button {
                isInputFocused = false
                showDocumentPicker = true
            } label: {
                Label("Document", systemImage: "doc")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.brandOrange)
        }
        .menuOrder(.fixed)
    }
    
    private var messageTextField: some View {
        TextField("Message", text: $newMessageText, axis: .vertical)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.secondary.opacity(0.1))
            )
            .lineLimit(1...6)
            .focused($isInputFocused)
    }
    
    private var sendButton: some View {
        Button {
            sendMessage()
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(sendButtonColor)
        }
        .disabled(newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    
    private var sendButtonColor: Color {
        newMessageText.isEmpty ? .secondary : Color.brandOrange
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
        
        Task {
            do {
                _ = try await messageStore.sendMessage(
                    to: otherUserID,
                    content: messageContent.isEmpty ? "" : messageContent,
                    conversationID: conversationID,
                    attachmentURL: attachmentURL,
                    attachmentType: attachmentType
                )
                
                // Clear input
                await MainActor.run {
                    newMessageText = ""
                    attachmentURL = nil
                    attachmentType = nil
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func handlePhotoSelection(_ item: PhotosPickerItem) {
        Task {
            // Load the photo/video data
            if let data = try? await item.loadTransferable(type: Data.self) {
                // Save to temporary location
                let tempDir = FileManager.default.temporaryDirectory
                let filename = "\(UUID().uuidString).\(item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg")"
                let tempURL = tempDir.appendingPathComponent(filename)
                
                try? data.write(to: tempURL)
                
                // Determine attachment type
                if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) {
                    attachmentType = .video
                } else {
                    attachmentType = .image
                }
                
                attachmentURL = tempURL
                
                // Optionally send immediately or let user add a message
                // For now, we'll just show they have an attachment ready to send
                print("📷 Photo/Video ready to send")
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
    let senderName: String

    @State private var showPostDetail = false
    @State private var postLiked = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isFromCurrentUser {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Sender name (only show for received messages)
                if !isFromCurrentUser {
                    Text(senderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
                
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
                            .font(.body)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(isFromCurrentUser ? Color.brandOrange : Color.secondary.opacity(0.15))
                            )
                            .foregroundStyle(isFromCurrentUser ? .white : .primary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        if message.attachmentType != nil {
                            AttachmentPreview(attachmentType: message.attachmentType)
                        }

                        if !message.content.isEmpty {
                            Text(message.content)
                                .font(.body)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isFromCurrentUser ? Color.brandOrange : Color.secondary.opacity(0.15))
                    )
                    .foregroundStyle(isFromCurrentUser ? .white : .primary)
                }
                
                // Timestamp
                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
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
            case .film, .music, .reel:
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
    
    var body: some View {
        Group {
            switch attachmentType {
            case .image:
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 200, height: 150)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("Image")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                
            case .video:
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 200, height: 150)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "video")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("Video")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                
            case .document:
                HStack(spacing: 12) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Document.pdf")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("2.4 MB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(width: 200)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.1))
                )
                
            case .post:
                // Shared posts are rendered by SharedPostMessageBubble, not here.
                EmptyView()

            case .none:
                EmptyView()
            }
        }
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
