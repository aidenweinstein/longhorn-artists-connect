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

/// New Message composer, styled after Apple's: a "To:" bar at the top to add a
/// recipient, with the standard in-message chat (`InMessageView`) shown below once a
/// recipient is chosen. Messaging is 1:1, so exactly one recipient is supported.
struct NewMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var userProfileManager = UserProfileManager.shared
    @ObservedObject private var blockManager = BlockedUsersManager.shared
    @State private var searchText = ""

    // The chosen recipient. Until one is picked, the "To:" field searches the
    // directory and the suggestions list is shown instead of a chat.
    @State private var selectedRecipient: DirectoryUser?

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

    /// Removes the current user, and anyone they've blocked, from a list of directory
    /// users — so you never see (or can pick) yourself or a blocked person as a recipient.
    private func excludingSelf(_ users: [DirectoryUser]) -> [DirectoryUser] {
        users.filter { user in
            if let currentUserID, user.messagingUserID == currentUserID { return false }
            return !blockManager.isBlocked(user.messagingUserID)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                recipientBar
                Divider()

                if let recipient = selectedRecipient {
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
                    suggestionsList
                }
            }
            .navigationTitle("New Message")
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
            .onAppear { isToFieldFocused = (selectedRecipient == nil) }
        }
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(false) // Allow pull to dismiss
    }

    // MARK: - "To:" bar

    private var recipientBar: some View {
        HStack(spacing: 8) {
            Text("To:")
                .foregroundStyle(.secondary)

            if let recipient = selectedRecipient {
                recipientToken(recipient)
                Spacer(minLength: 0)
            } else {
                // `axis: .vertical` makes this a multiline field, which on iOS 26 does NOT
                // get the single-line "capsule" box that a plain TextField picks up. (This
                // is why the submission fields, all `axis: .vertical`, stay boxless.)
                TextField("", text: $searchText, axis: .vertical)
                    .focused($isToFieldFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// The chosen recipient shown as a removable chip, like Apple's blue address tokens.
    private func recipientToken(_ user: DirectoryUser) -> some View {
        HStack(spacing: 6) {
            Text(user.fullName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.brandOrange)

            Button {
                selectedRecipient = nil
                searchText = ""
                isToFieldFocused = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove recipient")
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
        selectedRecipient = user
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
