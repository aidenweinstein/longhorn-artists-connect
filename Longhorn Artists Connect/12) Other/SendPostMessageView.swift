//
//  SendPostMessageView-9)Supporting.swift
//  Longhorn Artists Connect
//
//  View for sharing submissions via messages
//

import SwiftUI
import CloudKit

// MARK: - Send Post Message View

struct SendPostMessageView: View {
    let post: Submission
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var userManager = UserProfileManager.shared
    /// Provides the current user's existing conversations, so people they've been
    /// messaging float to the top of the recipient list.
    @ObservedObject private var messageStore = MessageStore.shared
    @State private var searchText = ""
    @State private var messageText = ""
    /// IDs of every profile the post will be sent to. Each recipient receives the
    /// post as a separate message — this is not a group chat.
    @State private var selectedUserIDs: Set<String> = []
    /// The signed-in user's CloudKit record name, used to hide their own profile
    /// (you can't send a post to yourself).
    @State private var currentUserID: String?
    /// True while the post is being sent, so the button shows progress and can't be
    /// tapped twice.
    @State private var isSending = false
    /// A send failure to surface to the user. Previously send errors were only
    /// printed, so a failed send looked exactly like a successful one (the sheet just
    /// dismissed) — hiding, e.g., a CloudKit schema/permission error.
    @State private var sendError: String?

    // Convenience initializer to support different parameter names
    init(post: Submission) {
        self.post = post
    }

    init(submission: Submission) {
        self.post = submission
    }

    /// Three equal-width columns of profiles.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    /// Directory profiles to choose from, filtered by the search text. The signed-in
    /// user is never shown — you can't send a post to yourself.
    ///
    /// People the current user already has a conversation with are floated to the top,
    /// ordered by how recently they last exchanged a message; everyone else follows
    /// alphabetically.
    private var displayedUsers: [DirectoryUser] {
        let recency = conversationRecency
        let all = userManager.allUsers.filter { !isCurrentUser($0) }
        let filtered = searchText.isEmpty
            ? all
            : all.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }

        return filtered.sorted { lhs, rhs in
            let lhsDate = recency[canonicalMessagingID(lhs.messagingUserID)]
            let rhsDate = recency[canonicalMessagingID(rhs.messagingUserID)]
            switch (lhsDate, rhsDate) {
            case let (l?, r?):
                // Both are messaging partners — most recent first, then by name.
                if l != r { return l > r }
                return lhs.fullName.lowercased() < rhs.fullName.lowercased()
            case (.some, .none):
                return true  // a messaging partner outranks a non-partner
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.fullName.lowercased() < rhs.fullName.lowercased()
            }
        }
    }

    /// The most recent message timestamp for each person the current user has a
    /// conversation with, keyed by the other participant's canonical CloudKit user
    /// record name. A conversation with no messages yet still counts (as
    /// `.distantPast`), so a started thread still ranks ahead of strangers.
    private var conversationRecency: [String: Date] {
        guard let currentUserID else { return [:] }
        var recency: [String: Date] = [:]
        for conversation in messageStore.conversations {
            let other = canonicalMessagingID(conversation.otherParticipant(for: currentUserID))
            guard !other.isEmpty else { continue }
            let timestamp = conversation.lastMessageTimestamp ?? .distantPast
            if let existing = recency[other], existing >= timestamp { continue }
            recency[other] = timestamp
        }
        return recency
    }

    /// Whether a directory profile is the signed-in user. Compared by the raw
    /// CloudKit user record name (`messagingUserID`) so it's immune to name clashes.
    private func isCurrentUser(_ user: DirectoryUser) -> Bool {
        guard let currentUserID else { return false }
        return user.messagingUserID == currentUserID
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBarSection
                profilesGridSection
                Divider()
                messageInputSection
            }
            .background(Color(uiColor: .systemBackground)) // opaque sheet background
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn't Send", isPresented: Binding(
                get: { sendError != nil },
                set: { if !$0 { sendError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sendError ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(uiColor: .systemBackground)) // no transparency
        .task {
            await userManager.fetchAllUsers()
            currentUserID = try? await CKContainer.default().userRecordID().recordName
            // Refresh conversations so recent messaging partners rank first. Loads from
            // the local cache immediately; this pulls any newer threads from CloudKit.
            try? await messageStore.fetchConversations()
        }
    }

    // MARK: - View Components

    var searchBarSection: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search for someone...", text: $searchText)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding()
    }

    @ViewBuilder
    var profilesGridSection: some View {
        if displayedUsers.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(displayedUsers) { user in
                        profileCell(for: user)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom)
            }
        }
    }

    func profileCell(for user: DirectoryUser) -> some View {
        let isSelected = selectedUserIDs.contains(user.id)
        return Button {
            if isSelected {
                selectedUserIDs.remove(user.id)
            } else {
                selectedUserIDs.insert(user.id)
            }
        } label: {
            VStack(spacing: 6) {
                avatar(for: user, selected: isSelected)
                Text(user.firstName.isEmpty ? user.displayName : user.firstName)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func avatar(for user: DirectoryUser, selected: Bool) -> some View {
        ZStack {
            if let data = user.profileImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                Text(user.initials)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay(
            Circle().stroke(Color.brandOrange, lineWidth: selected ? 3 : 0)
        )
        .overlay(alignment: .bottomTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, Color.brandOrange)
                    .background(Circle().fill(.white))
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No people to send to yet" : "No people found")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    var messageInputSection: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                TextField("Add a message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                    )
                    .lineLimit(1...4)
            }
            .padding(.horizontal)

            Button {
                sendMessage()
            } label: {
                Group {
                    if isSending {
                        ProgressView()
                    } else {
                        Label(sendButtonTitle, systemImage: "paperplane.fill")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedUserIDs.isEmpty || isSending)
            .padding(.horizontal)
        }
        .padding(.vertical)
    }

    private var sendButtonTitle: String {
        switch selectedUserIDs.count {
        case 0:
            return "Send"
        case 1:
            if let id = selectedUserIDs.first,
               let user = userManager.allUsers.first(where: { $0.id == id }) {
                return "Send to \(user.firstName.isEmpty ? user.displayName : user.firstName)"
            }
            return "Send to 1 person"
        default:
            return "Send to \(selectedUserIDs.count) people"
        }
    }

    func sendMessage() {
        guard !selectedUserIDs.isEmpty else { return }

        // Send the post as a `.post` message carrying the submission's UUID, plus
        // any optional note the user typed. Each recipient gets a separate
        // message — this is not a group chat.
        let note = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        // `selectedUserIDs` holds each directory record name ("UserProfile_<id>").
        // Messages and conversation threads are keyed by the *raw* CloudKit user record
        // name (`messagingUserID`), so map to that — otherwise the post lands in a
        // different thread than the conversation the user actually sees.
        let recipientMessagingIDs = selectedUserIDs.compactMap { id in
            userManager.allUsers.first(where: { $0.id == id })?.messagingUserID
        }

        isSending = true
        Task {
            var firstError: Error?
            for recipientID in recipientMessagingIDs {
                do {
                    _ = try await MessageStore.shared.sendMessage(
                        to: recipientID,
                        content: note,
                        attachmentType: .post,
                        sharedSubmissionID: post.id.uuidString
                    )
                } catch {
                    print("❌ Failed to send shared post to \(recipientID): \(error.localizedDescription)")
                    if firstError == nil { firstError = error }
                }
            }

            isSending = false
            // Only dismiss on a clean send; otherwise surface the error so a failed
            // send doesn't silently look like a successful one.
            if let firstError {
                sendError = firstError.localizedDescription
            } else {
                dismiss()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SendPostMessageView(
        post: Submission(id: UUID(), type: .film, title: "Sample Film", details: "A great movie")
    )
}
