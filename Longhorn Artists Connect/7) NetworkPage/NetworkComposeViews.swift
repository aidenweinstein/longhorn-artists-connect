//
//  NetworkComposeViews.swift
//  Longhorn Artists Connect
//
//  Compose-side sheets for NetworkView: starting a new message, a brand-new
//  conversation, and the lightweight document-picker placeholder.
//  Split out of NetworkView.swift to keep that file (and its preview) lightweight.
//

import SwiftUI
import UIKit
import PhotosUI
import CloudKit

// MARK: - New Message View

/// New Message composer, styled after Apple's: a "To:" bar at the top to add
/// recipients, with the standard in-message chat (`InMessageView`) shown below once
/// someone is chosen. One recipient is a one-to-one chat; two or more make a group,
/// which is created when the first message is sent (after that the recipient list is
/// locked, like Messages).
struct NewMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var userProfileManager = UserProfileManager.shared
    @ObservedObject private var blockManager = BlockedUsersManager.shared
    @State private var searchText = ""

    // The chosen recipients, in the order they were added. Until someone is picked,
    // the "To:" field searches the directory and the suggestions list is shown
    // instead of a chat.
    @State private var selectedRecipients: [DirectoryUser] = []

    // Set once a group's record exists (first message sent). From then on the
    // recipients can't change — that's the group now.
    @State private var createdGroupID: UUID?

    // The current user's CloudKit record name, used to keep yourself out of the
    // recipient list — you can't message yourself.
    @State private var currentUserID: String?

    @FocusState private var isToFieldFocused: Bool

    // ✅ Get all CloudKit users (only users on Nexus), excluding yourself.
    var registeredUsers: [DirectoryUser] {
        excludingSelf(userProfileManager.allUsers)
    }

    var filteredContacts: [DirectoryUser] {
        if searchText.isEmpty {
            return registeredUsers
        }
        return excludingSelf(userProfileManager.searchUsers(searchText))
    }

    /// Removes the current user, anyone they've blocked, and people already added,
    /// from a list of directory users.
    private func excludingSelf(_ users: [DirectoryUser]) -> [DirectoryUser] {
        let chosen = Set(selectedRecipients.map(\.messagingUserID))
        return users.filter { user in
            if let currentUserID, user.messagingUserID == currentUserID { return false }
            if chosen.contains(user.messagingUserID) { return false }
            return !blockManager.isBlocked(user.messagingUserID)
        }
    }

    /// The directory is searched while the To field has text; otherwise the chat for
    /// the chosen people shows (or, with nobody chosen yet, everyone to pick from).
    private var showsSuggestions: Bool {
        selectedRecipients.isEmpty || (isToFieldFocused && !searchText.isEmpty)
    }

    private var isGroupDraft: Bool { selectedRecipients.count >= 2 || createdGroupID != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                recipientBar
                Divider()

                if showsSuggestions {
                    suggestionsList
                } else if let createdGroupID {
                    // The group exists now; keep chatting in it.
                    InMessageView(thread: .group(createdGroupID), showsHeader: false)
                        .id(createdGroupID)
                } else if selectedRecipients.count == 1, let recipient = selectedRecipients.first {
                    // Standard in-message chat for the chosen 1:1 thread. Its built-in
                    // header is hidden so this composer's "To:" bar owns the top.
                    InMessageView(
                        conversationID: existingConversationID(forOtherUser: recipient.messagingUserID) ?? UUID(),
                        otherUserID: recipient.messagingUserID,
                        otherUserName: recipient.fullName,
                        otherUserRole: recipient.rolesString,
                        showsHeader: false
                    )
                    .id(recipient.messagingUserID)   // rebuild the chat when the recipient changes
                } else {
                    // Two or more people: a group that's created on the first send.
                    let memberIDs = selectedRecipients.map(\.messagingUserID)
                    InMessageView(thread: .newGroup(memberIDs: memberIDs), showsHeader: false) { id in
                        createdGroupID = id
                    }
                    .id(memberIDs.joined(separator: "|"))   // rebuild when the roster changes
                }
            }
            .navigationTitle(isGroupDraft ? "New Group" : "New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    // Override the app's orange accent so the close X stays grey.
                    .tint(.secondary)
                    .accessibilityLabel("Close")
                }
            }
            .task {
                if currentUserID == nil {
                    currentUserID = try? await CKContainer.default().userRecordID().recordName
                }
                await userProfileManager.fetchAllUsers()
            }
            .onAppear { isToFieldFocused = selectedRecipients.isEmpty }
        }
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(false) // Allow pull to dismiss
    }

    // MARK: - "To:" bar

    private var recipientBar: some View {
        HStack(spacing: 8) {
            Text("To:")
                .foregroundStyle(.secondary)

            // Tokens for everyone added so far, then the search field to add more. Once
            // the group exists the field goes away and the tokens lose their "x".
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(selectedRecipients) { user in
                        recipientToken(user, removable: createdGroupID == nil)
                    }
                    if createdGroupID == nil {
                        // `axis: .vertical` makes this a multiline field, which on iOS 26 does NOT
                        // get the single-line "capsule" box that a plain TextField picks up. (This
                        // is why the submission fields, all `axis: .vertical`, stay boxless.)
                        TextField(selectedRecipients.isEmpty ? "" : "Add people for a group", text: $searchText, axis: .vertical)
                            .focused($isToFieldFocused)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .frame(minWidth: 160)
                    }
                }
            }
            // A ScrollView is greedy in both axes, so without this the horizontal
            // token strip would stretch the "To:" bar to fill the screen. Keep it
            // at its content height (one line of tokens / text), like a plain field.
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// A chosen recipient shown as a removable chip, like Apple's blue address tokens.
    private func recipientToken(_ user: DirectoryUser, removable: Bool) -> some View {
        HStack(spacing: 6) {
            Text(user.fullName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.brandOrange)
                .lineLimit(1)

            if removable {
                Button {
                    selectedRecipients.removeAll { $0.id == user.id }
                    searchText = ""
                    isToFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(user.fullName)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.brandOrange.opacity(0.12)))
    }

    // MARK: - Suggestions

    @ViewBuilder
    private var suggestionsList: some View {
        if userProfileManager.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                    .padding()
                Text("Loading users...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredContacts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: searchText.isEmpty ? "person.2" : "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(searchText.isEmpty ? "No users found" : "No results found")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if searchText.isEmpty {
                    Text("Users will appear here when they complete their profile")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(filteredContacts) { user in
                    Button {
                        selectRecipient(user)
                    } label: {
                        contactRow(user)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .listStyle(.plain)
            .refreshable {
                await userProfileManager.fetchAllUsers(forceRefresh: true)
            }
        }
    }

    private func selectRecipient(_ user: DirectoryUser) {
        guard !selectedRecipients.contains(where: { $0.id == user.id }) else { return }
        selectedRecipients.append(user)
        searchText = ""
        // Drop to the chat; tapping the To field again adds more people.
        isToFieldFocused = false
    }

    private func contactRow(_ user: DirectoryUser) -> some View {
        HStack(spacing: 12) {
            // Profile image or initials
            if let imageData = user.profileImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(Color.brandOrange.opacity(0.2))
                        .frame(width: 36, height: 36)

                    Text(user.initials)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.brandOrange)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(user.fullName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                if !user.userTypes.isEmpty {
                    Text(user.rolesString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !user.graduationYear.isEmpty {
                Text("'\(String(user.graduationYear.suffix(2)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Returns the ID of an existing 1:1 conversation with the given user, if one
    /// is already loaded. Any conversation containing `otherUserID` as a participant
    /// is the thread with that user; nil means a fresh thread is created on first send.
    private func existingConversationID(forOtherUser otherUserID: String) -> UUID? {
        MessageStore.shared.conversations.first {
            $0.participant1UserID == otherUserID || $0.participant2UserID == otherUserID
        }?.id
    }
}

// MARK: - Previews

#Preview("New Message") {
    NewMessageView()
}
