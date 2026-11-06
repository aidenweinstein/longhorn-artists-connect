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
    /// Active tag filter (empty = show everyone under "On Nexus"). When non-empty,
    /// students matching any selected tag are grouped under a header naming those
    /// tags, and the rest fall under "Everyone Else".
    @State private var selectedFilterTags: Set<String> = []
    @AppStorage("isModeratorMode") private var isModeratorMode: Bool = false
    /// Private connections, so they can be listed in their own sections (Requests
    /// waiting on me, then my Connections) ahead of the general directory.
    @ObservedObject private var connections = ConnectionsManager.shared
    /// Profile styles and moderator listings, for the Actors / Filmmakers / Musicians
    /// pages and their counts.
    @ObservedObject private var creative = CreativeProfileStore.shared

    // The signed-in user's locally-stored profile. Used to synthesize their own
    // directory entry so they can always find and view their own profile — even
    // before their CloudKit `UserProfile` record has synced back into `allUsers`.
    @AppStorage("userFirstName") private var userFirstName: String = ""
    @AppStorage("userLastName") private var userLastName: String = ""
    @AppStorage("userMajor") private var userMajor: String = ""
    @AppStorage("userGraduationYear") private var userGraduationYear: String = ""
    @AppStorage("userType") private var userType: String = ""
    @AppStorage("userBio") private var userBio: String = ""
    @AppStorage("isIndustryProfessional") private var isIndustryProfessional: Bool = false
    @AppStorage("userIndustry") private var userIndustry: String = ""
    @AppStorage("userCompany") private var userCompany: String = ""
    @AppStorage("userCompanyRole") private var userCompanyRole: String = ""

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
            // Industry pros aren't UT students — flag them so their own entry lands in
            // the Industry Professionals section rather than the student list.
            isUTStudent: !isIndustryProfessional,
            isIndustryProfessional: isIndustryProfessional,
            industry: userIndustry,
            company: userCompany,
            companyRole: userCompanyRole
        )
    }

    /// How the directory lists are ordered.
    enum DirectorySort: String, CaseIterable, Identifiable {
        case nameAsc = "Name (A–Z)"
        case nameDesc = "Name (Z–A)"
        case gradYearAsc = "Grad Year (A–Z)"
        case gradYearDesc = "Grad Year (Z–A)"
        case majorAsc = "Major (A–Z)"
        case majorDesc = "Major (Z–A)"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .nameAsc, .gradYearAsc, .majorAsc: return "arrow.up"
            case .nameDesc, .gradYearDesc, .majorDesc: return "arrow.down"
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
        case .gradYearAsc, .gradYearDesc:
            // Group by graduation year, empties last, then by name within each year.
            let ascending = sortOption == .gradYearAsc
            return users.sorted {
                let a = $0.graduationYear, b = $1.graduationYear
                if a.isEmpty != b.isEmpty { return !a.isEmpty }
                if a.localizedCaseInsensitiveCompare(b) != .orderedSame {
                    let order = a.localizedCaseInsensitiveCompare(b)
                    return ascending ? order == .orderedAscending : order == .orderedDescending
                }
                return $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }
        case .majorAsc, .majorDesc:
            // Group by major, empties last, then by name within each major.
            let ascending = sortOption == .majorAsc
            return users.sorted {
                let a = $0.major, b = $1.major
                if a.isEmpty != b.isEmpty { return !a.isEmpty }
                if a.localizedCaseInsensitiveCompare(b) != .orderedSame {
                    let order = a.localizedCaseInsensitiveCompare(b)
                    return ascending ? order == .orderedAscending : order == .orderedDescending
                }
                return $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }
        }
    }
    
    // Get all unique people from project credits (legacy support)
    var allCreditedPeople: Set<String> {
        var people = Set<String>()
        
        // Only credits on posts from the schools this user sees.
        let visibleSchoolIDs = SchoolScope.visibleSchoolIDs
        for submission in store.approvedSubmissions where SchoolScope.isVisible(schoolID: submission.schoolID, in: visibleSchoolIDs) {
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

    /// People who asked to connect with me and are waiting on an answer, narrowed by
    /// the search text. Listed first so a request is never missed.
    var requestUsers: [DirectoryUser] {
        sortUsers(connections.pendingRequesters(in: filteredCloudKitUsers))
    }

    /// My connections (both sides agreed), narrowed by the search text. They get their
    /// own section and are left out of the general lists below so the two never overlap.
    var connectionUsers: [DirectoryUser] {
        sortUsers(connections.connectedUsers(in: filteredCloudKitUsers))
    }

    // Only students appear in the directory, and only from the schools this user
    // sees (`SchoolScope`). Guest accounts are hidden — moderators can move users
    // to/from Guest in Moderator Mode. Connections are listed in their own section.
    var filteredUTStudents: [DirectoryUser] {
        let visibleSchoolIDs = SchoolScope.visibleSchoolIDs
        let connectedIDs = connections.connectedIDs
        return sortUsers(filteredCloudKitUsers.filter {
            $0.isUTStudent
                && SchoolScope.isVisible(schoolName: $0.school, in: visibleSchoolIDs)
                && !connectedIDs.contains($0.messagingUserID)
        })
    }

    /// Industry Professionals, listed on their own pushed page.
    var filteredIndustryProfessionals: [DirectoryUser] {
        sortUsers(filteredCloudKitUsers.filter { $0.isIndustryProfessional })
    }

    /// True when a student matches the active tag filter (or when no filter is set).
    private func matchesTagFilter(_ user: DirectoryUser) -> Bool {
        guard !selectedFilterTags.isEmpty else { return true }
        return user.userTypes.contains { selectedFilterTags.contains($0) }
    }

    /// UT students whose roles intersect the active tag filter.
    var tagMatchedStudents: [DirectoryUser] {
        filteredUTStudents.filter { matchesTagFilter($0) }
    }

    /// UT students that don't match the active tag filter ("Everyone Else").
    var tagUnmatchedStudents: [DirectoryUser] {
        filteredUTStudents.filter { !matchesTagFilter($0) }
    }

    /// Header for the matched-students section: the selected tags, pluralized and
    /// joined in enum order (e.g. "Actors, Musicians, Cinematographers").
    var selectedTagsHeader: String {
        UserType.allCases
            .map(\.rawValue)
            .filter { selectedFilterTags.contains($0) }
            .map { $0 + "s" }
            .joined(separator: ", ")
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

                    // Filter menu — narrow the "On Nexus" list to selected tags.
                    Menu {
                        // Toggles keep the menu open across taps, so multiple filters can
                        // be selected in one pass.
                        ForEach(UserType.allCases) { type in
                            Toggle(isOn: Binding(
                                get: { selectedFilterTags.contains(type.rawValue) },
                                set: { isOn in
                                    if isOn {
                                        selectedFilterTags.insert(type.rawValue)
                                    } else {
                                        selectedFilterTags.remove(type.rawValue)
                                    }
                                }
                            )) {
                                Text(type.rawValue)
                            }
                        }

                        // Always present (disabled when there's nothing to clear) so the
                        // menu's content structure never changes as tags are toggled.
                        Divider()
                        Button(role: .destructive) {
                            selectedFilterTags.removeAll()
                        } label: {
                            Label("Clear Filters", systemImage: "xmark.circle")
                        }
                        .disabled(selectedFilterTags.isEmpty)
                    } label: {
                        // Static label: its icon/color must NOT change with the selection.
                        // Mutating a Menu's label while it's open forces SwiftUI to dismiss
                        // the menu — which is what closed it after every tap before.
                        Image(systemName: "line.3.horizontal.decrease.circle")
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
                    // Connection requests waiting on me, with an inline Accept.
                    if !requestUsers.isEmpty {
                        Section("Requests") {
                            ForEach(requestUsers) { user in
                                requestRow(user)
                            }
                        }
                    }

                    // My connections, kept apart from the general directory below.
                    if !connectionUsers.isEmpty {
                        Section("Connections") {
                            ForEach(connectionUsers) { user in
                                directoryUserRow(user)
                            }
                        }
                    }

                    // The public Actors / Filmmakers / Musicians pages: one entry per
                    // base profile, each pushing that page (with a segmented control
                    // to hop between the three). Only moderator-approved profiles are
                    // listed. Hidden while searching, since the search is by person.
                    if searchText.isEmpty {
                        Section("Pages") {
                            ForEach(ProfileStyle.allCases) { style in
                                NavigationLink {
                                    CreativeDirectoryPage(style: style)
                                } label: {
                                    directoryFieldRow(
                                        icon: style.symbol,
                                        title: style.plural,
                                        subtitle: pageSubtitle(for: style),
                                        count: creative.listedPeople(for: style, in: userProfileManager.allUsers).count
                                    )
                                }
                            }
                        }
                    }

                    // ✅ SECTION 1: UT students registered on the app.
                    if selectedFilterTags.isEmpty {
                        // No filter — everyone under "On Nexus".
                        if !filteredUTStudents.isEmpty {
                            Section("On Nexus") {
                                ForEach(filteredUTStudents) { user in
                                    directoryUserRow(user)
                                }
                            }
                        }
                    } else {
                        // Filtered — matched tags first, then "Everyone Else".
                        if !tagMatchedStudents.isEmpty {
                            Section(selectedTagsHeader) {
                                ForEach(tagMatchedStudents) { user in
                                    directoryUserRow(user)
                                }
                            }
                        }

                        if !tagUnmatchedStudents.isEmpty {
                            Section("Everyone Else") {
                                ForEach(tagUnmatchedStudents) { user in
                                    directoryUserRow(user)
                                }
                            }
                        }
                    }

                    // ✅ SECTION 2: Credited but Not Registered — a field that pushes
                    // a page listing all those names.
                    if !filteredUsersOffApp.isEmpty {
                        Section {
                            NavigationLink {
                                creditedNotOnNexusPage
                            } label: {
                                directoryFieldRow(
                                    icon: "person.crop.circle.badge.questionmark",
                                    title: "Credited on Projects",
                                    subtitle: "Not on Nexus",
                                    count: filteredUsersOffApp.count
                                )
                            }
                        }
                    }

                    // ✅ SECTION 3: Industry Professionals — a field that pushes a page
                    // listing only accounts registered as Industry Professionals.
                    if !filteredIndustryProfessionals.isEmpty {
                        Section {
                            NavigationLink {
                                industryProfessionalsPage
                            } label: {
                                directoryFieldRow(
                                    icon: "briefcase",
                                    title: "Industry Professionals",
                                    subtitle: nil,
                                    count: filteredIndustryProfessionals.count
                                )
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
                    await creative.refresh(force: true)
                }
                // Load styles and listings so the Pages counts are right (throttled
                // internally when already fresh).
                .task { await creative.refresh() }
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
                    UserPortfolioView(user: UserProfile(directoryUser: user), portfolioOrder: user.portfolioOrder)
                }
            }
            .sheet(isPresented: $showAddUserSheet) {
                AddUserProfileView()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
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
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(user.fullName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        UserVerifiedBadge(userID: user.id)
                            .font(.system(size: 13))
                    }

                    // Industry pros show role/company; students show their role tags.
                    if user.isIndustryProfessional {
                        let subtitle = [user.companyRole, user.company]
                            .filter { !$0.isEmpty }
                            .joined(separator: " • ")
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else if !user.userTypes.isEmpty {
                        Text(user.rolesString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // The year chip is student-only; industry pros have no class year.
                if !user.isIndustryProfessional, !user.graduationYear.isEmpty {
                    Text("'\(String(user.graduationYear.suffix(2)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            // Fill the row and hit-test the whole rectangle so taps on the empty
            // space between the name and the year chip still open the profile.
            // `.plain` buttons otherwise only respond on opaque content.
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    /// A directory row for someone whose connection request is waiting on me: the
    /// usual tappable row plus an inline Accept, so answering doesn't require opening
    /// their profile. Declining isn't a separate action — ignoring a request leaves it
    /// here, and the sender can withdraw it from their side.
    @ViewBuilder
    private func requestRow(_ user: DirectoryUser) -> some View {
        HStack(spacing: 8) {
            directoryUserRow(user)

            Button {
                Task { await connections.connect(with: user) }
            } label: {
                Text("Accept")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.brandOrange)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(connections.isBusy(user.messagingUserID))
            .accessibilityLabel("Accept \(user.fullName)'s connection request")
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    /// A tappable "field" row used to push a dedicated list page (Credited on
    /// Projects, Industry Professionals). Shows an icon, title, optional subtitle,
    /// and the number of entries on the destination page.
    @ViewBuilder
    private func directoryFieldRow(icon: String, title: String, subtitle: String?, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(Color.brandOrange)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(count)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    /// What each public page holds, for the Pages rows.
    private func pageSubtitle(for style: ProfileStyle) -> String {
        switch style {
        case .actor: return "Headshots, reels & resumes"
        case .filmmaker: return "Filmographies & stills"
        case .musician: return "Discographies & shows"
        }
    }

    /// Pushed page listing everyone credited on projects but not registered on Nexus.
    @ViewBuilder
    private var creditedNotOnNexusPage: some View {
        List {
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
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Credited on Projects")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Pushed page listing only accounts registered as Industry Professionals.
    @ViewBuilder
    private var industryProfessionalsPage: some View {
        List {
            ForEach(filteredIndustryProfessionals) { user in
                directoryUserRow(user)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Industry Professionals")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Titles of the approved posts (from the schools this user sees) that credit
    /// `name` — as cast, crew, music recording/production, or a photography post's
    /// photographer. Deduplicated, in feed order, so the invite can list them.
    private func creditedTitles(for name: String) -> [String] {
        let visibleSchoolIDs = SchoolScope.visibleSchoolIDs
        var seen = Set<String>()
        var titles: [String] = []
        for submission in store.approvedSubmissions
        where SchoolScope.isVisible(schoolID: submission.schoolID, in: visibleSchoolIDs) {
            let isCredited =
                submission.orderedCast.contains(where: { $0.name == name }) ||
                submission.orderedCrew.contains(where: { $0.name == name }) ||
                submission.orderedRecording.contains(where: { $0.name == name }) ||
                submission.orderedProduction.contains(where: { $0.name == name }) ||
                submission.isPhotographer(named: name)
            let title = submission.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isCredited, !title.isEmpty, seen.insert(title).inserted else { continue }
            titles.append(title)
        }
        return titles
    }

    /// Builds the invite text for someone credited on posts but not yet on Nexus,
    /// e.g. `Johnny Test, you've been credited on two projects: "Worms" and
    /// "Graphite" on Nexus by LAC! …`. Falls back to a generic invite when no
    /// credited titles can be found.
    private func inviteMessage(for name: String) -> String {
        let callToAction = "Download the app to connect with college creators, share your work, and stay informed about opportunities. (Website and Android versions coming soon.)"
        let titles = creditedTitles(for: name)
        guard !titles.isEmpty else {
            return "\(name), join Nexus by LAC! \(callToAction)"
        }

        // "two projects" / "one project", spelled out for small counts.
        let countFormatter = NumberFormatter()
        countFormatter.numberStyle = .spellOut
        let countWord = titles.count <= 10
            ? (countFormatter.string(from: NSNumber(value: titles.count)) ?? "\(titles.count)")
            : "\(titles.count)"
        let noun = titles.count == 1 ? "project" : "projects"

        // "Worms" and "Graphite" / "A", "B", and "C"
        let quoted = titles.map { "\"\($0)\"" }
        let titleList = ListFormatter.localizedString(byJoining: quoted)

        return "\(name), you've been credited on \(countWord) \(noun): \(titleList) on Nexus by LAC! \(callToAction)"
    }

    private func shareInviteLink(for name: String) {
        // Create invite message naming the person and the posts they're credited on
        let inviteText = inviteMessage(for: name)
        let appURL = "https://apps.apple.com/app/id6758110788"
        
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
