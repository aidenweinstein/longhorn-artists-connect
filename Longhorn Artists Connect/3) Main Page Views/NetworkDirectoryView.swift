//
//  NetworkDirectoryView.swift
//  Longhorn Artists Connect
//
//  Directory sheet for NetworkView listing on-app and credited users.
//  Split out of NetworkView.swift to keep that file (and its preview) lightweight.
//

import SwiftUI
import UIKit

struct NetworkDirectoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @ObservedObject var userProfileManager = UserProfileManager.shared
    @State private var searchText = ""
    @State private var showAddUserSheet = false
    @State private var selectedUser: DirectoryUser?
    @State private var sortOption: DirectorySort = .nameAsc
    @AppStorage("isModeratorMode") private var isModeratorMode: Bool = false

    // The signed-in user's locally-stored profile. Used to synthesize their own
    // directory entry so they can always find and view their own profile — even
    // before their CloudKit `UserProfile` record has synced back into `allUsers`.
    @AppStorage("userFirstName") private var userFirstName: String = ""
    @AppStorage("userLastName") private var userLastName: String = ""
    @AppStorage("userMajor") private var userMajor: String = ""
    @AppStorage("userGraduationYear") private var userGraduationYear: String = ""
    @AppStorage("userType") private var userType: String = ""
    @AppStorage("userBio") private var userBio: String = ""

    /// A `DirectoryUser` built from the signed-in user's local profile, or nil if
    /// they haven't set a name yet. Mirrors `parseUserProfile`'s field handling so
    /// it looks identical to a CloudKit-sourced entry.
    private var currentUserEntry: DirectoryUser? {
        let first = userFirstName.trimmingCharacters(in: .whitespaces)
        let last = userLastName.trimmingCharacters(in: .whitespaces)
        guard !(first.isEmpty && last.isEmpty) else { return nil }

        let userTypes = userType
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var imageData: Data?
        if let path = UserDefaults.standard.string(forKey: "profileImagePath"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let thumb = UIImage(data: data)?.jpegData(compressionQuality: 0.3) {
            imageData = thumb
        }

        return DirectoryUser(
            id: "currentUser",   // placeholder id; deduped by name against CloudKit entries
            firstName: first,
            lastName: last,
            major: userMajor,
            graduationYear: userGraduationYear,
            userTypes: userTypes,
            bio: userBio,
            instagramHandle: "",
            profileImageData: imageData,
            isUTStudent: true
        )
    }

    /// How the directory lists are ordered.
    enum DirectorySort: String, CaseIterable, Identifiable {
        case nameAsc = "Name (A–Z)"
        case nameDesc = "Name (Z–A)"
        case major = "Major"
        case tags = "Tags"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .nameAsc: return "arrow.up"
            case .nameDesc: return "arrow.down"
            case .major: return "graduationcap"
            case .tags: return "tag"
            }
        }
    }

    /// Applies the current sort to a list of directory users.
    private func sortUsers(_ users: [DirectoryUser]) -> [DirectoryUser] {
        switch sortOption {
        case .nameAsc:
            return users.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        case .nameDesc:
            return users.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedDescending }
        case .major:
            // Group by major, empties last, then by name within each major.
            return users.sorted {
                let a = $0.major, b = $1.major
                if a.isEmpty != b.isEmpty { return !a.isEmpty }
                if a.localizedCaseInsensitiveCompare(b) != .orderedSame {
                    return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
                }
                return $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }
        case .tags:
            // Group by roles string, empties last, then by name.
            return users.sorted {
                let a = $0.rolesString, b = $1.rolesString
                if a.isEmpty != b.isEmpty { return !a.isEmpty }
                if a.localizedCaseInsensitiveCompare(b) != .orderedSame {
                    return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
                }
                return $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }
        }
    }
    
    // Get all unique people from project credits (legacy support)
    var allCreditedPeople: Set<String> {
        var people = Set<String>()
        
        for submission in store.approvedSubmissions {
            // Add cast members
            for entry in submission.orderedCast {
                people.insert(entry.name)
            }
            
            // Add crew members
            for entry in submission.orderedCrew {
                people.insert(entry.name)
            }
            
            // Add submitter
            if !submission.submittedBy.isEmpty {
                people.insert(submission.submittedBy)
            }
        }
        
        return people
    }
    
    // ✅ NEW: Get all registered users from CloudKit
    var registeredUsers: Set<String> {
        // Use CloudKit user profiles
        var users = Set<String>()
        
        for user in userProfileManager.allUsers {
            users.insert(user.fullName)
        }
        
        // Fallback: Add users from local submissions (for backwards compatibility)
        for submission in store.approvedSubmissions where !submission.submittedBy.isEmpty {
            users.insert(submission.submittedBy)
        }
        
        return users
    }
    
    // ✅ NEW: Users with profiles in CloudKit, guaranteeing the signed-in user is
    // present. If CloudKit already has them (matched by name) that authoritative
    // entry is kept and the local one is dropped, so there's never a duplicate.
    var cloudKitUsers: [DirectoryUser] {
        let base = userProfileManager.allUsers
        guard let me = currentUserEntry else { return base }
        let alreadyListed = base.contains {
            $0.fullName.caseInsensitiveCompare(me.fullName) == .orderedSame
        }
        return alreadyListed ? base : base + [me]
    }
    
    var usersOnApp: [String] {
        Array(allCreditedPeople.intersection(registeredUsers)).sorted()
    }
    
    var usersOffApp: [String] {
        Array(allCreditedPeople.subtracting(registeredUsers)).sorted()
    }
    
    var filteredUsersOnApp: [String] {
        if searchText.isEmpty {
            return usersOnApp
        }
        return usersOnApp.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    var filteredUsersOffApp: [String] {
        let base = searchText.isEmpty
            ? usersOffApp
            : usersOffApp.filter { $0.localizedCaseInsensitiveContains(searchText) }
        // These are just names (no major/tags), so honor A–Z / Z–A and leave the
        // other sort modes alphabetical.
        return sortOption == .nameDesc ? base.sorted(by: >) : base.sorted(by: <)
    }
    
    // ✅ NEW: Filtered CloudKit users. Filters the merged `cloudKitUsers` locally
    // (rather than delegating to `searchUsers`, which only knows CloudKit records)
    // so the signed-in user's own entry is searchable too. Match fields mirror
    // `UserProfileManager.searchUsers`.
    var filteredCloudKitUsers: [DirectoryUser] {
        if searchText.isEmpty {
            return cloudKitUsers
        }
        let query = searchText.lowercased()
        return cloudKitUsers.filter { user in
            user.fullName.lowercased().contains(query) ||
            user.firstName.lowercased().contains(query) ||
            user.lastName.lowercased().contains(query) ||
            user.userTypes.contains { $0.lowercased().contains(query) } ||
            user.major.lowercased().contains(query)
        }
    }

    // Only UT students appear in the directory. Guest (non-UT) accounts are
    // hidden — moderators can move users to/from Guest in Moderator Mode.
    var filteredUTStudents: [DirectoryUser] {
        sortUsers(filteredCloudKitUsers.filter { $0.isUTStudent })
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar + sort button - reduced top padding
                HStack(spacing: 10) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search by name...", text: $searchText)

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    // Sort menu
                    Menu {
                        Picker("Sort", selection: $sortOption) {
                            ForEach(DirectorySort.allCases) { option in
                                Label(option.rawValue, systemImage: option.systemImage).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.brandOrange)
                            .frame(width: 44, height: 44)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                // User list
                List {
                    // ✅ SECTION 1: UT students registered on the app
                    if !filteredUTStudents.isEmpty {
                        Section("On Nexus") {
                            ForEach(filteredUTStudents) { user in
                                directoryUserRow(user)
                            }
                        }
                    }

                    // ✅ SECTION 2: Credited but Not Registered (Legacy support)
                    if !filteredUsersOffApp.isEmpty {
                        Section("Credited on Projects (Not on Nexus)") {
                            ForEach(filteredUsersOffApp, id: \.self) { name in
                                HStack(spacing: 12) {
                                    Image(systemName: "person.crop.circle")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 36, height: 36)
                                    
                                    Text(name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    
                                    Spacer()
                                    
                                    Button {
                                        shareInviteLink(for: name)
                                    } label: {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 16))
                                            .foregroundStyle(Color.brandOrange)
                                    }
                                }
                                .padding(.vertical, 4)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                        }
                    }
                    
                    // Empty state
                    if filteredCloudKitUsers.isEmpty && filteredUsersOffApp.isEmpty {
                        Section {
                            VStack(spacing: 12) {
                                if userProfileManager.isLoading {
                                    ProgressView()
                                        .padding()
                                    Text("Loading users...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else if let errorMessage = userProfileManager.errorMessage {
                                    // Surface the real CloudKit failure instead of a
                                    // silent "no people" state, so directory problems
                                    // (missing index, undeployed schema, wrong
                                    // environment) are diagnosable on-device.
                                    Image(systemName: "exclamationmark.icloud")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.orange)

                                    Text("Couldn't load directory")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)

                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .multilineTextAlignment(.center)
                                        .textSelection(.enabled)
                                        .padding(.horizontal)

                                    Button {
                                        Task {
                                            await userProfileManager.fetchAllUsers(forceRefresh: true)
                                        }
                                    } label: {
                                        Label("Try Again", systemImage: "arrow.clockwise")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(.bordered)
                                    .padding(.top, 8)
                                } else {
                                    Image(systemName: searchText.isEmpty ? "person.2" : "magnifyingglass")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.secondary)
                                    
                                    Text(searchText.isEmpty ? "No people in directory" : "No results found")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                    
                                    if searchText.isEmpty {
                                        Text("Users will appear here when they complete their profile")
                                            .font(.subheadline)
                                            .foregroundStyle(.tertiary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal)
                                        
                                        Button {
                                            Task {
                                                await userProfileManager.fetchAllUsers(forceRefresh: true)
                                            }
                                        } label: {
                                            Label("Refresh Directory", systemImage: "arrow.clockwise")
                                                .font(.subheadline)
                                        }
                                        .buttonStyle(.bordered)
                                        .padding(.top, 8)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await userProfileManager.fetchAllUsers(forceRefresh: true)
                }
            }
            .navigationTitle("Directory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isModeratorMode {
                        Button {
                            showAddUserSheet = true
                        } label: {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.title3)
                                .foregroundStyle(Color.brandOrange)
                        }
                    }
                }
            }
            .sheet(item: $selectedUser) { user in
                NavigationStack {
                    UserPortfolioView(user: UserProfile(directoryUser: user))
                }
            }
            .sheet(isPresented: $showAddUserSheet) {
                AddUserProfileView()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    
    /// A tappable directory row for a registered (Nexus) user — shared by the
    /// "On Nexus" and "Non-UT Students" sections.
    @ViewBuilder
    private func directoryUserRow(_ user: DirectoryUser) -> some View {
        Button {
            selectedUser = user
        } label: {
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
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func shareInviteLink(for name: String) {
        // Create invite message
        let inviteText = "Join me on Nexus from Longhorn Artists Connect! Download the app to connect with UT creators, share your work, and learn about upcoming projects."
        let appURL = "https://apps.apple.com/app/nexus" // Replace with actual App Store URL when available
        
        let activityVC = UIActivityViewController(
            activityItems: [inviteText, URL(string: appURL) as Any],
            applicationActivities: nil
        )
        
        // Present the share sheet
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            
            // Find the topmost view controller
            var topController = rootVC
            while let presented = topController.presentedViewController {
                topController = presented
            }
            
            // For iPad, set the popover presentation
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topController.view
                popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            topController.present(activityVC, animated: true)
        }
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        NetworkDirectoryView()
    }
}
