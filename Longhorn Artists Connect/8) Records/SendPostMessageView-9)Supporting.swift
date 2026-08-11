//
//  SendPostMessageView-9)Supporting.swift
//  Longhorn Artists Connect
//
//  View for sharing submissions via messages
//

import SwiftUI

// MARK: - Send Post Message View

struct SendPostMessageView: View {
    let post: Submission
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var userManager = UserProfileManager.shared
    @State private var searchText = ""
    @State private var messageText = ""
    /// IDs of every profile the post will be sent to. Each recipient receives the
    /// post as a separate message — this is not a group chat.
    @State private var selectedUserIDs: Set<String> = []

    // Convenience initializer to support different parameter names
    init(post: Submission) {
        self.post = post
    }

    init(submission: Submission) {
        self.post = submission
    }

    /// Three equal-width columns of profiles.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    /// Directory profiles to choose from, filtered by the search text.
    private var displayedUsers: [DirectoryUser] {
        let all = userManager.allUsers.sorted { $0.fullName.lowercased() < $1.fullName.lowercased() }
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
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
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemBackground)) // no transparency
        .task { await userManager.fetchAllUsers() }
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
                Label(sendButtonTitle, systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedUserIDs.isEmpty)
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
        let recipientIDs = selectedUserIDs
        Task {
            for recipientID in recipientIDs {
                do {
                    _ = try await MessageStore.shared.sendMessage(
                        to: recipientID,
                        content: note,
                        attachmentType: .post,
                        sharedSubmissionID: post.id.uuidString
                    )
                } catch {
                    print("❌ Failed to send shared post to \(recipientID): \(error.localizedDescription)")
                }
            }
        }

        dismiss()
    }
}

// MARK: - Preview

#Preview {
    SendPostMessageView(
        post: Submission(id: UUID(), type: .film, title: "Sample Film", details: "A great movie")
    )
}
