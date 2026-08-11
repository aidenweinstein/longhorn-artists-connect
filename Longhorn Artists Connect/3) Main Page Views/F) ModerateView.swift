import SwiftUI

struct ModerateView_3_1: View {
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @State private var selectedSubmission: Submission?
    @State private var liked = false
    @State private var showHistory = false
    @State private var showModeratorInfo = false
    @State private var showDeleted = false
    @State private var showUsers = false
    
    var body: some View {
        NavigationStack {
            Group {
                if store.approvedSubmissions.isEmpty {
                    List {
                        Text("No posts on the platform.")
                            .foregroundStyle(.secondary)
                    }
                    .listStyle(.plain)
                } else {
                    List {
                        ForEach(sortedSubmissions) { submission in
                            SubmissionModerateCard(
                                submission: submission,
                                onApprove: {
                                    // No longer needed since posts are auto-approved
                                },
                                onDeny: {
                                    // Hide the post from users (kept in CloudKit,
                                    // visible in the "Deleted Posts" page).
                                    store.softDelete(submission)
                                },
                                onTap: {
                                    selectedSubmission = submission
                                }
                            )
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 191/255, green: 87/255, blue: 0/255), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Text("Moderate")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Button {
                            showUsers = true
                        } label: {
                            Text("Users")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 50)
                                .frame(height: 28)
                                .contentShape(Rectangle())
                        }

                        Button {
                            showDeleted = true
                        } label: {
                            Text("Deleted")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 55)
                                .frame(height: 28)
                                .contentShape(Rectangle())
                        }

                        Button {
                            showHistory = true
                        } label: {
                            Text("History")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 55)
                                .frame(height: 28)
                                .contentShape(Rectangle())
                        }

                        Button {
                            showModeratorInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 28)
                                .contentShape(Rectangle())
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(red: 120/255, green: 80/255, blue: 50/255))
                    )
                }
            }
            .sheet(item: $selectedSubmission) { submission in
                ProjectDetailView(post: submission, liked: $liked)
            }
            .sheet(isPresented: $showHistory) {
                ModerationHistoryView()
            }
            .sheet(isPresented: $showModeratorInfo) {
                ModeratorInfoView()
            }
            .sheet(isPresented: $showDeleted) {
                DeletedPostsView()
            }
            .sheet(isPresented: $showUsers) {
                UsersModerationView()
            }
        }
    }
    
    // Sort submissions by newest first
    private var sortedSubmissions: [Submission] {
        store.approvedSubmissions.sorted { submission1, submission2 in
            submission1.createdDate > submission2.createdDate
        }
    }
}

// MARK: - Deleted Posts View

/// Moderator-only page listing posts that have been hidden from users. Posts here
/// can be restored (made visible again) or permanently deleted from CloudKit.
struct DeletedPostsView: View {
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSubmission: Submission?
    @State private var liked = false

    private var sortedDeleted: [Submission] {
        store.deletedSubmissions.sorted { $0.createdDate > $1.createdDate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedDeleted.isEmpty {
                    List {
                        Text("No deleted posts.")
                            .foregroundStyle(.secondary)
                    }
                    .listStyle(.plain)
                } else {
                    List {
                        ForEach(sortedDeleted) { submission in
                            SubmissionModerateCard(
                                submission: submission,
                                onApprove: {},
                                onDeny: {
                                    // From this page, the context-menu "Delete" removes it for good.
                                    store.permanentlyDelete(submission)
                                },
                                onTap: {
                                    selectedSubmission = submission
                                }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    store.restore(submission)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)

                                Button(role: .destructive) {
                                    store.permanentlyDelete(submission)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Deleted Posts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedSubmission) { submission in
                ProjectDetailView(post: submission, liked: $liked)
            }
        }
    }
}

// MARK: - Users Moderation View

/// Moderator-only page listing every user profile in the directory. Any profile
/// can be deleted from here (subject to CloudKit public-database permissions).
struct UsersModerationView: View {
    @ObservedObject var userManager: UserProfileManager = .shared
    @Environment(\.dismiss) private var dismiss
    @State private var userToDelete: DirectoryUser?
    @State private var errorMessage: String?
    @State private var isRefreshing = false

    private var sortedUsers: [DirectoryUser] {
        userManager.allUsers.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedUsers.isEmpty {
                    List {
                        Text(isRefreshing ? "Loading users…" : "No user profiles found.")
                            .foregroundStyle(.secondary)
                    }
                    .listStyle(.plain)
                } else {
                    List {
                        Section {
                            ForEach(sortedUsers) { user in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(user.displayName)
                                            .font(.headline)
                                        if !user.isUTStudent {
                                            Text("Guest")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.brandOrange.opacity(0.2))
                                                .foregroundStyle(Color.brandOrange)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    if !user.rolesString.isEmpty {
                                        Text(user.rolesString)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !user.major.isEmpty || !user.graduationYear.isEmpty {
                                        Text([user.major, user.graduationYear].filter { !$0.isEmpty }.joined(separator: " • "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !user.isUTStudent {
                                        Text("Hidden from the directory")
                                            .font(.caption2)
                                            .foregroundStyle(Color.brandOrange)
                                    }
                                    Text(user.id)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 2)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        Task {
                                            let result = await userManager.setGuestStatus(user, isGuest: user.isUTStudent)
                                            await MainActor.run { errorMessage = result }
                                        }
                                    } label: {
                                        if user.isUTStudent {
                                            Label("Make Guest", systemImage: "person.fill.questionmark")
                                        } else {
                                            Label("Make UT Student", systemImage: "graduationcap.fill")
                                        }
                                    }
                                    .tint(user.isUTStudent ? Color.brandOrange : .blue)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        userToDelete = user
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } footer: {
                            Text("\(sortedUsers.count) profile\(sortedUsers.count == 1 ? "" : "s"). Swipe left to delete, swipe right to move a user to/from Guest. Guest profiles are hidden from the directory.")
                        }
                    }
                }
            }
            .navigationTitle("Users")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await refresh() }
            .alert(item: $userToDelete) { user in
                Alert(
                    title: Text("Delete Profile?"),
                    message: Text("Permanently remove \(user.displayName)'s profile from the directory?"),
                    primaryButton: .destructive(Text("Delete")) {
                        Task {
                            let result = await userManager.deleteUserProfile(user)
                            await MainActor.run { errorMessage = result }
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert("Couldn't Delete", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func refresh() async {
        isRefreshing = true
        await userManager.fetchAllUsers(forceRefresh: true)
        isRefreshing = false
    }
}

struct SubmissionModerateCard: View {
    let submission: Submission
    let onApprove: () -> Void
    let onDeny: () -> Void
    let onTap: () -> Void
    
    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(submission.title.hashValue)
        return colors[hash % colors.count]
    }
    
    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 12) {
                // Thumbnail
                ZStack {
                    if let thumbnailData = submission.thumbnailData,
                       let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Rectangle()
                            .fill(LinearGradient(colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 100, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        Image(systemName: submission.type == .film ? "film" : "music.note")
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(submission.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    
                    Text("By \(submission.submittedBy)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text(submission.type.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(tintColor.opacity(0.2))
                        .foregroundStyle(tintColor)
                        .clipShape(Capsule())
                }
                
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("View Details", systemImage: "eye")
            }
            
            Button(role: .destructive) {
                onDeny()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    ModerateView_3_1()
}

// MARK: - Moderation History View

struct ModerationHistoryView: View {
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @Environment(\.dismiss) private var dismiss
    
    var sortedHistory: [HistoryEntry] {
        store.history.sorted { $0.timestamp > $1.timestamp }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if sortedHistory.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No history yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(sortedHistory) { entry in
                        HistoryEntryRow(entry: entry)
                    }
                }
            }
            .navigationTitle("Moderation History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct HistoryEntryRow: View {
    let entry: HistoryEntry
    
    private var actionColor: Color {
        switch entry.action {
        case .submitted:
            return .blue
        case .approved:
            return .green
        case .edited:
            return .orange
        case .denied:
            return .red
        case .deleted:
            return .gray
        }
    }
    
    private var actionIcon: String {
        switch entry.action {
        case .submitted:
            return "arrow.up.circle.fill"
        case .approved:
            return "checkmark.circle.fill"
        case .edited:
            return "pencil.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .deleted:
            return "trash.circle.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Action icon
            Image(systemName: actionIcon)
                .font(.title2)
                .foregroundStyle(actionColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                // Action and title
                HStack(spacing: 6) {
                    Text(entry.action.rawValue)
                        .font(.headline)
                        .foregroundStyle(actionColor)
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    Text(entry.submissionTitle)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                
                // Type and performer
                HStack(spacing: 6) {
                    Text(entry.submissionType.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                    
                    Text("by \(entry.performedBy)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Timestamp
                Text(formatTimestamp(entry.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview("History") {
    ModerationHistoryView()
}

// MARK: - Moderator Info View

struct ModeratorInfoView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            ModeratorInfoBubble(
                                icon: "checkmark.shield.fill",
                                title: "Approve/Deny Posts",
                                message: "Review and moderate all submitted content to ensure quality and adherence to community guidelines."
                            )
                            
                            ModeratorInfoBubble(
                                icon: "person.crop.circle.badge.plus",
                                title: "Add User Profiles",
                                message: "Create profiles for users who are credited on projects but haven't registered yet."
                            )
                            
                            ModeratorInfoBubble(
                                icon: "chart.bar.fill",
                                title: "See Analytics",
                                message: "Access moderation history and track all actions taken on submitted content."
                            )
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Moderator Capabilities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Moderator Capabilities")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct ModeratorInfoBubble: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.brandOrange)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.brandOrange.opacity(0.1))
        )
    }
}

