//
//  ProfileMessageButton.swift
//  Longhorn Artists Connect
//
//  The "Message" box on someone else's profile — the right-hand half of
//  `ProfileActionButtons`. Opens the standard 1:1 chat (`InMessageView`) with that person
//  directly, skipping the Network tab's "To:" picker. Hidden when the viewer is a guest,
//  when the profile is the viewer's own, when the person has been blocked, or when the
//  person isn't a Nexus member (no directory entry means there's no account to message).
//

import SwiftUI

struct ProfileMessageButton: View {
    /// The directory entry of the person whose profile is being viewed. Nil (no
    /// account) renders nothing.
    let user: DirectoryUser?

    @AppStorage("isGuestUser") private var isGuestUser: Bool = false
    @ObservedObject private var messageStore = MessageStore.shared
    @ObservedObject private var blockManager = BlockedUsersManager.shared
    @State private var showChat = false

    var body: some View {
        if let user, ProfileInteraction.canInteract(with: user) {
            Button {
                showChat = true
            } label: {
                Label("Message", systemImage: "message.fill")
                    .profileActionBox(filled: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Message \(user.fullName)")
            .sheet(isPresented: $showChat) {
                NavigationStack {
                    InMessageView(
                        conversationID: existingConversationID(forOtherUser: user.messagingUserID) ?? UUID(),
                        otherUserID: user.messagingUserID,
                        otherUserName: user.fullName,
                        otherUserRole: user.rolesString
                    )
                }
                .presentationDragIndicator(.hidden)
            }
        }
    }

    /// The already-loaded thread with this person, if any. `InMessageView` resolves the
    /// deterministic pair ID itself, so a fresh UUID is a fine fallback (same as the
    /// Network tab's New Message flow).
    private func existingConversationID(forOtherUser otherUserID: String) -> UUID? {
        messageStore.conversations.first {
            $0.participant1UserID == otherUserID || $0.participant2UserID == otherUserID
        }?.id
    }
}
