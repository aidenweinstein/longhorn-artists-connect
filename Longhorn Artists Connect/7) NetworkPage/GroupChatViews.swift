//
//  GroupChatViews.swift
//  Longhorn Artists Connect
//
//  Group-chat pieces shared by the Network tab: which thread a chat view shows
//  (`MessageThread`), the group avatar, the Group Info sheet (name, members, add
//  people, leave) and the add-members picker.
//

import SwiftUI
import CloudKit

// MARK: - Thread Descriptor

/// What an `InMessageView` is showing: a one-to-one chat with someone, an existing
/// group, or a group that's about to be created (it gets its record on first send).
enum MessageThread: Equatable {
    case direct(otherUserID: String, name: String, role: String)
    case group(UUID)
    case newGroup(memberIDs: [String])
}

// MARK: - Group Avatar

/// The round avatar for a group thread: the first two other members' photos overlapping
/// (callers pass everyone except the current user),
/// or a people symbol when there are no photos to show.
struct GroupAvatarView: View {
    let members: [DirectoryUser]
    var size: CGFloat = 56

    private var photos: [UIImage] {
        members.compactMap { $0.profileImageData.flatMap(UIImage.init(data:)) }.prefix(2).map { $0 }
    }

    var body: some View {
        ZStack {
            Circle().fill(Color.brandOrange.opacity(0.15))
            if photos.count >= 2 {
                // Two photos, back-left and front-right, like Messages' group icon.
                let small = size * 0.62
                Image(uiImage: photos[0])
                    .resizable()
                    .scaledToFill()
                    .frame(width: small, height: small)
                    .clipShape(Circle())
                    .offset(x: -size * 0.16, y: -size * 0.14)
                Image(uiImage: photos[1])
                    .resizable()
                    .scaledToFill()
                    .frame(width: small, height: small)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                    .offset(x: size * 0.16, y: size * 0.14)
            } else {
                Image(systemName: "person.2.fill")
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(Color.brandOrange)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Group Info

/// Details of a group chat: its name (editable), who's in it, a way to add people,
/// and Leave Group. Presented from the chat's header.
struct GroupInfoView: View {
    let conversationID: UUID
    /// Called after the user leaves, so the chat behind this sheet can close too.
    var onLeft: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var messageStore = MessageStore.shared
    @ObservedObject private var profileManager = UserProfileManager.shared
    @ObservedObject private var convoPrefs = ConversationPreferencesManager.shared

    @State private var nameDraft = ""
    @State private var isSavingName = false
    @State private var showAddMembers = false
    @State private var showLeaveConfirmation = false
    @State private var isLeaving = false
    @State private var selectedMember: DirectoryUser?
    @State private var errorMessage: String?

    private var conversation: Conversation? {
        messageStore.conversations.first { $0.id == conversationID }
    }

    private var memberIDs: [String] { conversation?.allMemberIDs ?? [] }

    private var members: [(id: String, user: DirectoryUser?)] {
        memberIDs.map { ($0, profileManager.findUser(byID: $0)) }
    }

    /// Everyone but the current user — what the avatar collage shows.
    private var otherMembers: [DirectoryUser] {
        let me = messageStore.currentUserID.map(canonicalMessagingID)
        return members.filter { $0.id != me }.compactMap(\.user)
    }

    private var currentTitle: String {
        conversation?.displayTitle(for: messageStore.currentUserID) { profileManager.findUser(byID: $0)?.firstName } ?? "Group"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        GroupAvatarView(members: otherMembers, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentTitle)
                                .font(.headline)
                            Text("\(memberIDs.count) people")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Group Name") {
                    HStack {
                        TextField("Name this group", text: $nameDraft)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(saveName)
                        if isSavingName {
                            ProgressView()
                        } else if nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (conversation?.groupName ?? "") {
                            Button("Save", action: saveName)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }

                Section("\(memberIDs.count) Members") {
                    ForEach(members, id: \.id) { member in
                        Button {
                            if let user = member.user { selectedMember = user }
                        } label: {
                            memberRow(member.id, user: member.user)
                        }
                        .buttonStyle(.plain)
                        .disabled(member.user == nil)
                    }

                    Button {
                        showAddMembers = true
                    } label: {
                        Label("Add People", systemImage: "person.badge.plus")
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { convoPrefs.isMuted(conversationID.uuidString) },
                        set: { _ in convoPrefs.toggleMute(conversationID.uuidString) }
                    )) {
                        Label("Mute Notifications", systemImage: "bell.slash")
                    }
                    Toggle(isOn: Binding(
                        get: { convoPrefs.isPinned(conversationID.uuidString) },
                        set: { _ in convoPrefs.togglePin(conversationID.uuidString) }
                    )) {
                        Label("Pin Conversation", systemImage: "pin")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showLeaveConfirmation = true
                    } label: {
                        HStack {
                            Label("Leave Group", systemImage: "rectangle.portrait.and.arrow.right")
                            if isLeaving { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isLeaving)
                }
            }
            .navigationTitle("Group Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                nameDraft = conversation?.groupName ?? ""
                await profileManager.fetchAllUsers()
            }
            .sheet(isPresented: $showAddMembers) {
                AddGroupMembersView(existingMemberIDs: memberIDs) { newIDs in
                    Task {
                        do {
                            try await messageStore.addMembers(newIDs, to: conversationID)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            .sheet(item: $selectedMember) { user in
                PersonProfileView(name: user.fullName)
            }
            .confirmationDialog("Leave \(currentTitle)?", isPresented: $showLeaveConfirmation, titleVisibility: .visible) {
                Button("Leave Group", role: .destructive, action: leave)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll stop getting messages from this group. Someone in it can add you back.")
            }
            .alert("Couldn't Update Group", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func memberRow(_ id: String, user: DirectoryUser?) -> some View {
        HStack(spacing: 12) {
            if let data = user?.profileImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.brandOrange.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(user?.initials ?? "?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.brandOrange)
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user?.displayName ?? "Nexus member")
                        .font(.body)
                        .foregroundStyle(.primary)
                    if canonicalMessagingID(id) == canonicalMessagingID(messageStore.currentUserID ?? "") {
                        Text("You")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let roles = user?.rolesString, !roles.isEmpty {
                    Text(roles)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func saveName() {
        guard !isSavingName else { return }
        isSavingName = true
        Task {
            do {
                try await messageStore.renameGroup(conversationID, to: nameDraft)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSavingName = false
        }
    }

    private func leave() {
        guard !isLeaving else { return }
        isLeaving = true
        Task {
            do {
                try await messageStore.leaveGroup(conversationID)
                dismiss()
                onLeft()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLeaving = false
        }
    }
}

// MARK: - Add Members

/// Picks people from the directory to add to a group. Current members, the user,
/// and anyone they've blocked aren't offered.
struct AddGroupMembersView: View {
    let existingMemberIDs: [String]
    let onAdd: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profileManager = UserProfileManager.shared
    @ObservedObject private var blockManager = BlockedUsersManager.shared
    @ObservedObject private var messageStore = MessageStore.shared
    @State private var searchText = ""
    @State private var selectedIDs: [String] = []

    private var candidates: [DirectoryUser] {
        let existing = Set(existingMemberIDs.map(canonicalMessagingID))
        let me = canonicalMessagingID(messageStore.currentUserID ?? "")
        let users = searchText.isEmpty ? profileManager.allUsers : profileManager.searchUsers(searchText)
        return users.filter { user in
            let id = user.messagingUserID
            return !existing.contains(id) && id != me && !blockManager.isBlocked(id)
        }
    }

    var body: some View {
        NavigationStack {
            List(candidates) { user in
                let isSelected = selectedIDs.contains(user.messagingUserID)
                Button {
                    if isSelected {
                        selectedIDs.removeAll { $0 == user.messagingUserID }
                    } else {
                        selectedIDs.append(user.messagingUserID)
                    }
                } label: {
                    HStack(spacing: 12) {
                        if let data = user.profileImageData, let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.brandOrange.opacity(0.2))
                                .frame(width: 36, height: 36)
                                .overlay {
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
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.brandOrange : Color.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search people")
            .navigationTitle("Add People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selectedIDs.isEmpty ? "Add" : "Add \(selectedIDs.count)") {
                        onAdd(selectedIDs)
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .task { await profileManager.fetchAllUsers() }
        }
    }
}

// MARK: - Previews

#Preview("Group Avatar") {
    HStack(spacing: 20) {
        GroupAvatarView(members: [], size: 56)
        GroupAvatarView(members: [], size: 32)
    }
    .padding()
}
