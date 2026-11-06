//
//  ProfileActionButtons.swift
//  Longhorn Artists Connect
//
//  The two action boxes under the role tags on someone else's profile: Connect on the
//  left, Message on the right. Both hide together when there's nothing to act on — the
//  viewer is a guest, it's their own profile, the person is blocked, or the name has no
//  Nexus account.
//

import SwiftUI

/// Shared gate for the profile action buttons.
enum ProfileInteraction {
    /// Guests can't interact, you can't interact with yourself, and blocked people are hidden.
    @MainActor
    static func canInteract(with user: DirectoryUser) -> Bool {
        guard !UserDefaults.standard.bool(forKey: "isGuestUser") else { return false }
        if let me = MessageStore.shared.currentUserID, me == user.messagingUserID { return false }
        if let myProfileID = UserProfileManager.shared.getCurrentUser()?.id, myProfileID == user.id { return false }
        return !BlockedUsersManager.shared.isBlocked(user.messagingUserID)
    }
}

struct ProfileActionButtons: View {
    /// The directory entry of the person whose profile is being viewed. Nil (no
    /// account) renders nothing.
    let user: DirectoryUser?

    // Observed so the row appears/disappears as the viewer's identity or block list resolve.
    @AppStorage("isGuestUser") private var isGuestUser: Bool = false
    @ObservedObject private var messageStore = MessageStore.shared
    @ObservedObject private var blockManager = BlockedUsersManager.shared

    var body: some View {
        if let user, ProfileInteraction.canInteract(with: user) {
            HStack(spacing: 10) {
                ProfileConnectButton(user: user)
                ProfileMessageButton(user: user)
            }
        }
    }
}

// MARK: - Connect Button

/// "Connect" → "Requested" → "Connected", plus "Accept" when the other person asked
/// first. Requested and Connected tap through to a confirmation to withdraw / disconnect.
struct ProfileConnectButton: View {
    let user: DirectoryUser

    @ObservedObject private var connections = ConnectionsManager.shared
    @State private var showWithdrawConfirm = false
    @State private var showDisconnectConfirm = false

    private var state: ConnectionState { connections.state(for: user.messagingUserID) }
    private var isBusy: Bool { connections.isBusy(user.messagingUserID) }

    var body: some View {
        Button {
            switch state {
            case .none, .incoming:
                Task { await connections.connect(with: user) }
            case .requested:
                showWithdrawConfirm = true
            case .connected:
                showDisconnectConfirm = true
            }
        } label: {
            Label(title, systemImage: icon)
                .profileActionBox(filled: state == .none || state == .incoming)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.15), value: state)
        .accessibilityLabel(accessibilityLabel)
        .confirmationDialog("Withdraw your connection request to \(user.fullName)?",
                            isPresented: $showWithdrawConfirm, titleVisibility: .visible) {
            Button("Withdraw Request", role: .destructive) {
                Task { await connections.disconnect(from: user.messagingUserID) }
            }
        }
        .confirmationDialog("Remove \(user.fullName) from your connections?",
                            isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                Task { await connections.disconnect(from: user.messagingUserID) }
            }
        }
    }

    private var title: String {
        switch state {
        case .none:      return "Connect"
        case .requested: return "Requested"
        case .incoming:  return "Accept"
        case .connected: return "Connected"
        }
    }

    private var icon: String {
        switch state {
        case .none:      return "person.badge.plus"
        case .requested: return "clock"
        case .incoming:  return "person.badge.plus"
        case .connected: return "checkmark"
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .none:      return "Connect with \(user.fullName)"
        case .requested: return "Connection request to \(user.fullName) pending. Tap to withdraw."
        case .incoming:  return "Accept \(user.fullName)'s connection request"
        case .connected: return "Connected with \(user.fullName). Tap to disconnect."
        }
    }
}

// MARK: - Shared Box Style

extension View {
    /// The rectangular action box used by both profile buttons: equal width, brand
    /// color — solid when the action is the primary thing to do, tinted when it's a
    /// status (Requested / Connected).
    func profileActionBox(filled: Bool) -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(filled ? Color.white : Color.brandOrange)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            // ====== UI CONTROLS!!!!! ======
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(filled ? Color.brandOrange : Color.brandOrange.opacity(0.12))
            )
            // ==============================
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
