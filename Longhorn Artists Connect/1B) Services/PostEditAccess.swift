//
//  PostEditAccess.swift
//  Longhorn Artists Connect
//
//  Shared edit access: the person who posted a project or piece of media can let
//  other Nexus members edit it too.
//
//  Stored on the post record itself as `editorIDs` — a String List of profile IDs
//  ("UserProfile_<userRecordName>") — on every post type. The website reads and writes
//  the same field (web/lib/editPost.ts), so access given in one shows up in the other.
//
//  Editors can change the post and its files. Only the person who posted it (or a
//  moderator) can delete it or change who else can edit it.
//
//  CloudKit Dashboard setup (both needed once, then deploy to Production):
//  1. Add `editorIDs` (String List) to FilmSubmission, MusicSubmission, ReelSubmission,
//     PhotographySubmission, DesignSubmission, ProjectSubmission and EventSubmission.
//  2. Editors save someone else's record, exactly like a moderator edit, so the post
//     record types need Write granted to authenticated users (see SubmissionStore.update).
//

import CloudKit
import SwiftUI

enum PostEditAccess {
    /// The post record field holding who else may edit it.
    static let field = "editorIDs"
    /// How many people one post can be shared with (same limit as the website).
    static let maxEditors = 20

    private static let profilePrefix = "UserProfile_"

    /// A profile ID or a bare user record name, as the bare user record name.
    static func account(of id: String) -> String {
        id.hasPrefix(profilePrefix) ? String(id.dropFirst(profilePrefix.count)) : id
    }

    /// Either form of ID as a profile ID — the form stored in `editorIDs`.
    static func profileID(for id: String) -> String {
        profilePrefix + account(of: id)
    }

    /// The signed-in iCloud account's record name, cached by `CloudKitManager`.
    private static var currentAccount: String? {
        let name = UserDefaults.standard.string(forKey: ModeratorAccess.currentUserRecordNameKey) ?? ""
        return name.isEmpty ? nil : name
    }

    /// The signed-in person posted it. Matched by profile name, like the rest of the app.
    static func isCreator(of post: Submission) -> Bool {
        let first = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let last = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return !currentUser.isEmpty && currentUser == post.submittedBy
    }

    /// The post's creator gave the signed-in account edit access.
    static func isEditor(of post: Submission) -> Bool {
        guard let me = currentAccount else { return false }
        return (post.editorIDs ?? []).contains { account(of: $0) == me }
    }

    private static var isModerating: Bool {
        UserDefaults.standard.bool(forKey: "isModeratorMode") && ModeratorAccess.isModerator
    }

    /// Shows Edit: the creator, anyone they shared it with, or a moderator.
    static func canEdit(_ post: Submission) -> Bool {
        isCreator(of: post) || isEditor(of: post) || isModerating
    }

    /// Shows Delete and Edit Access: the creator or a moderator, never an editor.
    static func canManage(_ post: Submission) -> Bool {
        isCreator(of: post) || isModerating
    }

    /// The CloudKit record type each kind of post is saved as.
    static func recordType(for type: MediaType) -> String {
        switch type {
        case .film: return CloudKitRecordTypes.film
        case .music: return CloudKitRecordTypes.music
        case .reel: return CloudKitRecordTypes.reel
        case .project: return CloudKitRecordTypes.project
        case .event: return CloudKitRecordTypes.event
        case .photography: return CloudKitRecordTypes.photography
        case .design: return CloudKitRecordTypes.design
        }
    }

    /// A message for a failed save of the editor list.
    static func message(for error: Error, type: MediaType) -> String {
        let text = "\(error)"
        if text.contains(field) || (error as? CKError)?.code == .invalidArguments {
            return "Edit access can't be saved yet: add \(field) (String List) to \(recordType(for: type)) in CloudKit Dashboard and deploy it."
        }
        if (error as? CKError)?.code == .permissionFailure {
            return "iCloud won't let this account change who can edit this post."
        }
        return "Couldn't save who can edit this. Check your connection and try again."
    }
}

// MARK: - Edit Access Screen

/// Lets the person who posted something choose who else can edit it. Opened from the
/// "Access" button next to Edit and Delete on a post's detail page.
struct EditAccessView: View {
    let post: Submission

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SubmissionStore_3_2.shared
    @ObservedObject private var people = UserProfileManager.shared

    /// Profile IDs, in the order they were added.
    @State private var editorIDs: [String] = []
    @State private var searchText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var loaded = false

    private var currentPost: Submission { store.currentCopy(of: post) }

    /// The person who posted it, so they don't show up as someone to add.
    private var creatorID: String? {
        people.findUser(byName: currentPost.submittedBy).map { PostEditAccess.profileID(for: $0.id) }
    }

    private var matches: [DirectoryUser] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { return [] }
        let taken = Set(editorIDs.map(PostEditAccess.account(of:)))
        let creator = creatorID.map(PostEditAccess.account(of:))
        return people.searchUsers(query)
            .filter { user in
                let account = PostEditAccess.account(of: user.id)
                return !taken.contains(account) && account != creator
            }
            .prefix(8)
            .map { $0 }
    }

    private var hasChanges: Bool {
        editorIDs != (currentPost.editorIDs ?? []).map(PostEditAccess.profileID(for:))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Add someone by name", text: $searchText)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    ForEach(matches) { user in
                        Button {
                            add(user)
                        } label: {
                            HStack(spacing: 12) {
                                avatar(for: user, name: user.fullName)
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
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.brandOrange)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("They can change the details and files. Only you can delete this post or change who can edit it.")
                }

                Section("Can edit") {
                    if editorIDs.isEmpty {
                        Text("Only you can edit this right now.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(editorIDs, id: \.self) { id in
                        let user = people.findUser(byID: id)
                        HStack(spacing: 12) {
                            avatar(for: user, name: user?.fullName ?? "Nexus member")
                            Text(user?.fullName ?? "Nexus member")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Button("Remove", role: .destructive) {
                                editorIDs.removeAll { $0 == id }
                            }
                            .buttonStyle(.borderless)
                            .font(.subheadline)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Edit Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .fontWeight(.semibold)
                            .disabled(!hasChanges)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving || hasChanges)
            .task {
                guard !loaded else { return }
                loaded = true
                editorIDs = (currentPost.editorIDs ?? []).map(PostEditAccess.profileID(for:))
                if people.allUsers.isEmpty {
                    await people.fetchAllUsers()
                }
            }
        }
    }

    private func add(_ user: DirectoryUser) {
        guard editorIDs.count < PostEditAccess.maxEditors else {
            errorMessage = "A post can be shared with up to \(PostEditAccess.maxEditors) editors."
            return
        }
        errorMessage = nil
        editorIDs.append(PostEditAccess.profileID(for: user.id))
        searchText = ""
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await store.setEditors(editorIDs, for: currentPost)
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorMessage = PostEditAccess.message(for: error, type: post.type)
            }
        }
    }

    @ViewBuilder
    private func avatar(for user: DirectoryUser?, name: String) -> some View {
        if let data = user?.profileImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color.brandOrange.opacity(0.2))
                    .frame(width: 36, height: 36)
                Text(user?.initials ?? String(name.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.brandOrange)
            }
        }
    }
}
