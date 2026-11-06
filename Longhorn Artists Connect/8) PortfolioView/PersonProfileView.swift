//
//  PersonProfileView.swift
//  Longhorn Artists Connect
//
//  Profile sheet shown from the NetworkView directory, plus its project thumbnail card.
//  Uses the exact same layout format as the user's own portfolio page (Portfolio_5):
//  orange top bar with pills, profile header row, role bubbles, bio, and submission list.
//

import SwiftUI
import UIKit

struct PersonProfileView: View {
    let name: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @ObservedObject private var profileManager = UserProfileManager.shared
    @AppStorage("isModeratorMode") private var isModeratorMode: Bool = false
    @State private var showDeleteAlert = false
    @State private var selectedProject: Submission?
    @State private var liked = false
    @State private var showEnlargedPhoto = false
    /// Where the header photo sits on screen, so the zoom overlay can start from it.
    @State private var profileImageFrame: CGRect = .zero
    /// Whether posts show as the thumbnail-only Grid (the default when viewing someone
    /// else's profile) or the List. Not persisted: every profile opens on the Grid.
    @State private var showsGrid = true

    // Check if this is a created profile
    private var isCreatedProfile: Bool {
        let createdProfiles = UserDefaults.standard.stringArray(forKey: "createdUserProfiles") ?? []
        return createdProfiles.contains(name)
    }

    // Load created profile data
    private var profileData: (firstName: String, lastName: String, graduationYear: String, userType: String, bio: String, major: String, minor: String, hometown: String, imageData: Data?)? {
        let profileKey = "userProfile_\(name.replacingOccurrences(of: " ", with: "_"))"

        guard let firstName = UserDefaults.standard.string(forKey: "\(profileKey)_firstName"),
              let lastName = UserDefaults.standard.string(forKey: "\(profileKey)_lastName") else {
            return nil
        }

        let graduationYear = UserDefaults.standard.string(forKey: "\(profileKey)_graduationYear") ?? ""
        let userType = UserDefaults.standard.string(forKey: "\(profileKey)_userType") ?? ""
        let bio = UserDefaults.standard.string(forKey: "\(profileKey)_bio") ?? ""
        let major = UserDefaults.standard.string(forKey: "\(profileKey)_major") ?? ""
        let minor = UserDefaults.standard.string(forKey: "\(profileKey)_minor") ?? ""
        let hometown = UserDefaults.standard.string(forKey: "\(profileKey)_hometown") ?? ""
        let imageData = Self.loadProfileImageData(forKey: profileKey)

        return (firstName, lastName, graduationYear, userType, bio, major, minor, hometown, imageData)
    }

    /// File URL where a created profile's photo is stored on disk.
    static func profileImageURL(forKey profileKey: String) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("\(profileKey)_profileImage.jpg")
    }

    /// Loads a created profile's photo. Photos now live on disk with only the
    /// path in UserDefaults. Older installs stored the raw JPEG under the
    /// `_imageData` key, which overflows CFPreferences' ~4 MB limit; migrate any
    /// such blob to a file on first access and drop the oversized default.
    static func loadProfileImageData(forKey profileKey: String) -> Data? {
        let defaults = UserDefaults.standard

        if let legacyData = defaults.data(forKey: "\(profileKey)_imageData") {
            let imageURL = profileImageURL(forKey: profileKey)
            try? legacyData.write(to: imageURL)
            defaults.set(imageURL.path, forKey: "\(profileKey)_imagePath")
            defaults.removeObject(forKey: "\(profileKey)_imageData")
            return legacyData
        }

        if let path = defaults.string(forKey: "\(profileKey)_imagePath") {
            return try? Data(contentsOf: URL(fileURLWithPath: path))
        }
        return nil
    }

    // The synced directory entry for this person, used so their CloudKit
    // profile (bio, photo, roles, academics) shows even when there's no local
    // created-profile record. Locally-created data still takes precedence.
    private var directoryUser: DirectoryUser? {
        profileManager.findUser(byName: name)
    }

    // Load profile image: prefer a locally-created profile's image, then fall
    // back to the synced directory photo (already cropped/baked).
    private var profileImage: UIImage? {
        if let data = profileData,
           let imageData = data.imageData,
           let uiImage = UIImage(data: imageData) {
            return uiImage
        }
        if let imageData = directoryUser?.profileImageData,
           let uiImage = UIImage(data: imageData) {
            return uiImage
        }
        return nil
    }

    // Unified profile fields: locally-created values win when present,
    // otherwise fall back to the synced directory entry.
    private var resolvedBio: String {
        if let bio = profileData?.bio, !bio.isEmpty { return bio }
        return directoryUser?.bio ?? ""
    }

    private var resolvedGraduationYear: String {
        if let year = profileData?.graduationYear, !year.isEmpty { return year }
        return directoryUser?.graduationYear ?? ""
    }

    private var resolvedMajor: String {
        if let major = profileData?.major, !major.isEmpty { return major }
        return directoryUser?.major ?? ""
    }

    private var resolvedUserType: String {
        if let type = profileData?.userType, !type.isEmpty { return type }
        return directoryUser?.rolesString ?? ""
    }

    // Get all projects this person is credited on.
    // Uses visibleApprovedSubmissions so a still-uploading post doesn't appear until
    // its CloudKit upload has fully confirmed.
    var personProjects: [Submission] {
        store.visibleApprovedSubmissions.filter { submission in
            // Show only posts this person is actually credited on (cast, crew, music
            // recording/production, or a photography post's photographer). Being the
            // submitter alone no longer qualifies, so posts they made for projects they
            // aren't part of stay off their profile.
            submission.orderedCast.contains(where: { $0.name == name }) ||
            submission.orderedCrew.contains(where: { $0.name == name }) ||
            submission.orderedRecording.contains(where: { $0.name == name }) ||
            submission.orderedProduction.contains(where: { $0.name == name }) ||
            submission.isPhotographer(named: name)
        }
    }

    // Person's submissions shown in the portfolio list (excluding events and projects,
    // matching the user's own portfolio page)
    private var personSubmissions: [Submission] {
        let subs = personProjects.filter { submission in
            submission.type != .event &&
            submission.type != .project
        }
        // Honor the order this person arranged in their own portfolio (synced via
        // their CloudKit profile). Falls back to newest-first when they haven't set one.
        return portfolioSorted(subs, order: directoryUser?.portfolioOrder ?? [])
    }

    /// Grid arrangement for this person's posts. Their own Custom Grid layout lives only
    /// on their device, so viewers get the default tile size in the person's portfolio
    /// order. The grid is read-only here, so this is never written back.
    private var personGridLayoutRaw: String {
        PortfolioGridStorage.encode(personSubmissions.map {
            PortfolioGridTile(id: $0.id.uuidString, widthFraction: PortfolioGridStorage.defaultFraction)
        })
    }

    // Get person's roles in a specific submission (same rules as the user's own portfolio)
    private func personRolesInSubmission(_ submission: Submission) -> String? {
        // List every role the person played across cast and crew, so someone who both
        // acted and (e.g.) directed reads "Actor, Director" instead of just one.
        var roles: [String] = []
        if submission.orderedCast.contains(where: { $0.name == name }) {
            roles.append("Actor")
        }
        for crewEntry in submission.orderedCrew where crewEntry.name == name {
            roles.append(crewEntry.role)
        }
        if submission.isPhotographer(named: name) {
            roles.append("Photographer")
        }

        if !roles.isEmpty {
            return roles.joined(separator: ", ")
        }

        // Uncredited but the submitter: show "Creator" rather than the media type.
        return "Creator"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    profileHeaderView
                    bioView
                    // Actor resume / filmmaker filmography / musician discography.
                    StyledProfileSection(name: name, profileID: directoryUser?.id)
                    CurrentWorkSection(source: store.visibleApprovedSubmissions) { $0.name == name }
                    SeeYouAtSection(userID: directoryUser?.id, source: store.visibleApprovedSubmissions)
                    postsSeparator
                    submissionsView
                    if isModeratorMode && isCreatedProfile {
                        Divider()
                        deleteProfileButton
                    }
                }
                // ====== UI CONTROLS!!!!! ======
                .padding()
                // ==============================
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedProject) { project in
                ProjectDetailView(post: project, liked: $liked)
            }
            .task {
                // Make sure the directory is loaded so this person's synced
                // bio/photo/roles appear (throttled internally if already fresh).
                await profileManager.fetchAllUsers()
            }
        }
        // Instagram-style zoom: the circular photo flies from the header to the
        // center while the sheet dims; tap anywhere to send it back.
        .overlay {
            if showEnlargedPhoto, let profileImage {
                ProfilePhotoZoomOverlay(isPresented: $showEnlargedPhoto, sourceFrame: profileImageFrame) { diameter in
                    circularProfileImage(profileImage, diameter: diameter)
                }
            }
        }
        // No grabber; this profile is a sheet, so it is dismissed by swiping
        // down rather than a header close button.
        .presentationDragIndicator(.hidden)
        .alert("Delete Profile?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteProfile()
            }
        } message: {
            Text("This will permanently delete \(name)'s profile. This action cannot be undone.")
        }
    }

    // MARK: - View Components

    private var profileHeaderView: some View {
        // Instagram-style header, matching the user's own portfolio: a large photo
        // on the left; beside it the name and class/major sit on top with the stats
        // row (posts, unique collaborators, total collaborations) underneath.
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 20) {
                profileImageView
                    // Track where the photo sits so the zoom can lift off from it, and
                    // hide the original while its enlarged twin is on screen.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                        profileImageFrame = $0
                    }
                    .opacity(showEnlargedPhoto ? 0 : 1)
                    // Tap the photo to see it enlarged and centered (only when set).
                    .onTapGesture {
                        if profileImage != nil { showEnlargedPhoto = true }
                    }

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(name)
                                .font(.title)
                                .bold()
                            // School-colored seal once this person's email is verified.
                            UserVerifiedBadge(userID: directoryUser?.id)
                                .font(.title3)
                        }
                        academicInfoView
                    }

                    // Experience from being on set: collaborations across every
                    // credited post. Tapping Unique Collaborators lists everyone
                    // they've worked with.
                    CollaborationStatsView(
                        stats: collaborationStats,
                        postCount: personSubmissions.count,
                        personName: name
                    )
                }
            }

            if !resolvedUserType.isEmpty {
                userTypeBubbles(resolvedUserType)
            }

            // Connect with / message this person (hidden for guests, yourself,
            // blocked people, and names without a Nexus account).
            ProfileActionButtons(user: directoryUser)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Collaboration totals for this person across every approved post (all types,
    /// including events and projects) they're credited on. They're excluded from
    /// their own counts.
    private var collaborationStats: CollaborationStats {
        CollaborationStats.compute(
            forPersonNamed: name,
            profileID: directoryUser?.id,
            in: store.visibleApprovedSubmissions,
            directory: profileManager.allUsers
        )
    }

    /// The person's photo cropped to a circle of the given diameter. Shared by the
    /// header thumbnail and the zoom overlay so both show the identical crop.
    private func circularProfileImage(_ image: UIImage, diameter: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
    }

    private var profileImageView: some View {
        Group {
            if let profileImage {
                // ====== UI CONTROLS!!!!! ======
                circularProfileImage(profileImage, diameter: 96)
                // ==============================
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .scaledToFit()
                    // ====== UI CONTROLS!!!!! ======
                    .frame(width: 96, height: 96)
                    // ==============================
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var academicInfoView: some View {
        let year = resolvedGraduationYear
        let major = resolvedMajor
        return HStack(spacing: 4) {
            if !year.isEmpty {
                // Abbreviate the graduation year, e.g. "2028" → "'28".
                Text("Class of '\(year.suffix(2))")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if !year.isEmpty && !major.isEmpty {
                Text("•")
                    .foregroundStyle(.secondary)
            }
            if !major.isEmpty {
                // The major stays on one line; it shrinks slightly to fit rather than
                // wrapping to a second line.
                Text(major)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    /// This person's school colors for their tags. Locally-created profiles with
    /// no directory entry get the app's own brand pair.
    private var roleTagTheme: SchoolTheme {
        directoryUser.map { SchoolTheme.forSchool($0.school) } ?? .nexusDefault
    }

    private func userTypeBubbles(_ userType: String) -> some View {
        // Use the portfolio's shared FlowLayout (which centers each wrapped row) so
        // the role tags sit in a full-width band below the photo and academic text,
        // matching the user's own portfolio page instead of drifting up beside them.
        let theme = roleTagTheme
        return RoleTagFlowLayout(spacing: 6) {
            ForEach(userType.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }, id: \.self) { role in
                RoleTagBubble(tag: role, theme: theme)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bioView: some View {
        let bio = resolvedBio
        return Text(bio.isEmpty ? "No bio yet." : bio)
            .foregroundStyle(bio.isEmpty ? .secondary : .primary)
            .italic(bio.isEmpty)
    }

    /// Separator line between the bio and the posts, with the Grid ↔ List toggle on its
    /// leading edge, matching the user's own portfolio page. Hidden when there are no
    /// posts to lay out.
    private var postsSeparator: some View {
        HStack(spacing: 8) {
            if !personSubmissions.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showsGrid.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                        Text(showsGrid ? "Grid" : "List")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brandOrange)
                    .fixedSize()
                }
                .buttonStyle(.plain)
            }

            Rectangle()
                .fill(Color(UIColor.separator))
                .frame(height: 1)
        }
    }

    private var submissionsView: some View {
        Group {
            if personSubmissions.isEmpty {
                Text("No projects yet.")
                    .foregroundStyle(.secondary)
            } else if showsGrid {
                // Read-only grid: tiles bleed past the page's 16pt padding to run edge
                // to edge, like the user's own Custom Grid.
                PortfolioCustomGridView(
                    submissions: personSubmissions,
                    layoutRaw: .constant(personGridLayoutRaw),
                    isEditing: false,
                    edgeBleed: 16,
                    onOpen: { selectedProject = $0 }
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(personSubmissions) { submission in
                        submissionButton(for: submission)
                    }
                }
            }
        }
    }

    private func submissionButton(for submission: Submission) -> some View {
        Button {
            selectedProject = submission
        } label: {
            HStack(spacing: 12) {
                submissionThumbnail(for: submission)
                submissionInfo(for: submission)
                Spacer()
            }
            .padding(8)
            // ====== UI CONTROLS!!!!! ======
            // Fixed dark mode glitch - using proper adaptive background
            .background(Color(UIColor.secondarySystemGroupedBackground))
            // ==============================
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func submissionThumbnail(for submission: Submission) -> some View {
        if let thumbnailData = submission.thumbnailData,
           let uiImage = UIImage(data: thumbnailData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                // ====== UI CONTROLS!!!!! ======
                .frame(width: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                // ==============================
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                // ====== UI CONTROLS!!!!! ======
                .frame(width: 100, height: 60)
                .cornerRadius(8)
                // ==============================
                .overlay(
                    Image(systemName: submission.type == .film ? "film" : "music.note")
                        .foregroundStyle(.secondary)
                )
        }
    }

    private func submissionInfo(for submission: Submission) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(submission.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let personRoles = personRolesInSubmission(submission) {
                Text(personRoles)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Like counts are only shown on your own portfolio, not when viewing
            // someone else's profile.
        }
    }

    // Delete button for moderators on created profiles
    private var deleteProfileButton: some View {
        Button {
            showDeleteAlert = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete Profile")
            }
            .font(.headline)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func deleteProfile() {
        let profileKey = "userProfile_\(name.replacingOccurrences(of: " ", with: "_"))"

        // Remove all profile data
        UserDefaults.standard.removeObject(forKey: "\(profileKey)_firstName")
        UserDefaults.standard.removeObject(forKey: "\(profileKey)_lastName")
        UserDefaults.standard.removeObject(forKey: "\(profileKey)_graduationYear")
        UserDefaults.standard.removeObject(forKey: "\(profileKey)_userType")
        UserDefaults.standard.removeObject(forKey: "\(profileKey)_bio")
        UserDefaults.standard.removeObject(forKey: "\(profileKey)_major")
        UserDefaults.standard.removeObject(forKey: "\(profileKey)_minor")
        UserDefaults.standard.removeObject(forKey: "\(profileKey)_hometown")

        // Remove the on-disk photo plus both the current path key and any
        // legacy inline-image key.
        try? FileManager.default.removeItem(at: Self.profileImageURL(forKey: profileKey))
        UserDefaults.standard.removeObject(forKey: "\(profileKey)_imagePath")
        UserDefaults.standard.removeObject(forKey: "\(profileKey)_imageData")

        // Remove from list
        var createdProfiles = UserDefaults.standard.stringArray(forKey: "createdUserProfiles") ?? []
        createdProfiles.removeAll { $0 == name }
        UserDefaults.standard.set(createdProfiles, forKey: "createdUserProfiles")

        dismiss()
    }
}

// MARK: - Current Work Section

/// "Current Work" on a profile: the person's in-progress projects as a single
/// horizontally scrolling row of thumbnails, each with their role underneath. Shared by
/// the user's own portfolio and every view of someone else's profile.
///
/// Working on a project means being in its assembled Cast or Crew — posting the project
/// alone doesn't count. The section (including its leading divider) is hidden when the
/// person has no current projects.
struct CurrentWorkSection: View {
    /// Submissions to search; only `.project` posts are considered.
    let source: [Submission]
    /// Whether a cast/crew entry is this person (by name, and/or linked profile ID).
    let isPerson: (OrderedEntry) -> Bool

    @State private var selectedProject: Submission?

    private var projects: [Submission] {
        source
            .filter { submission in
                submission.type == .project &&
                (submission.orderedCast.contains(where: isPerson) ||
                 submission.orderedCrew.contains(where: isPerson))
            }
            .sorted { $0.createdDate > $1.createdDate }
    }

    var body: some View {
        if !projects.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Work")
                        .font(.title3)
                        .bold()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(projects) { project in
                                Button {
                                    selectedProject = project
                                } label: {
                                    item(for: project)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .sheet(item: $selectedProject) { project in
                UpcomingProjectDetailView(submission: project)
            }
        }
    }

    private func item(for project: Submission) -> some View {
        let thumbnail = project.thumbnailData.flatMap { UIImage(data: $0) }
        // Every thumbnail shares the row height; its width follows the image's own
        // aspect ratio so posters, squares, and landscape stills aren't cropped.
        // Projects without a thumbnail fall back to the 2:3 poster placeholder.
        // ====== UI CONTROLS!!!!! ======
        let height: CGFloat = 150
        // ==============================
        let aspectRatio: CGFloat = {
            guard let thumbnail, thumbnail.size.height > 0 else { return 2.0 / 3.0 }
            return thumbnail.size.width / thumbnail.size.height
        }()
        let width = (height * aspectRatio).rounded()

        return VStack(spacing: 6) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                } else {
                    ZStack {
                        Color.secondary.opacity(0.1)
                        Image(systemName: "photo")
                            .imageScale(.large)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(role(in: project))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: width)
        }
        .contentShape(Rectangle())
    }

    /// The person's role(s) on a project: "Actor" for a cast spot plus each crew role,
    /// e.g. "Actor, Director".
    private func role(in project: Submission) -> String {
        var roles: [String] = []
        if project.orderedCast.contains(where: isPerson) {
            roles.append("Actor")
        }
        for crewEntry in project.orderedCrew where isPerson(crewEntry) {
            roles.append(crewEntry.role)
        }
        return roles.joined(separator: ", ")
    }
}

// MARK: - See You At Section

/// "See You At" on a profile: the upcoming events the person tapped "I'm Going" on, as a
/// single horizontally scrolling row of flyers with each event's date underneath. Past
/// events are left out. Hidden (with its leading divider) when there's nothing upcoming,
/// or when the person has no CloudKit account to look RSVPs up by.
struct SeeYouAtSection: View {
    /// The person's CloudKit user ID (raw record name or `UserProfile_` record name).
    /// Nil for locally-created profiles, which can't RSVP.
    let userID: String?
    /// Submissions to search; only `.event` posts are considered.
    let source: [Submission]

    @State private var attendedEventIDs: Set<UUID> = []
    @State private var selectedEvent: Submission?

    private var events: [Submission] {
        source
            .filter { $0.type == .event && attendedEventIDs.contains($0.id) && !$0.eventHasEnded }
            .sorted { (nextDate(for: $0) ?? .distantFuture) < (nextDate(for: $1) ?? .distantFuture) }
    }

    var body: some View {
        Group {
            if !events.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("See You At")
                            .font(.title3)
                            .bold()
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(events) { event in
                                    Button {
                                        selectedEvent = event
                                    } label: {
                                        item(for: event)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task(id: userID) {
            guard let userID,
                  let ids = try? await CloudKitManager.shared.fetchEventIDsAttended(byUserID: userID)
            else { return }
            attendedEventIDs = ids
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event)
        }
    }

    private func item(for event: Submission) -> some View {
        VStack(spacing: 6) {
            Group {
                if let thumbnailData = event.thumbnailData,
                   let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.secondary.opacity(0.1)
                        Image(systemName: "calendar")
                            .imageScale(.large)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // ====== UI CONTROLS!!!!! ======
            .frame(width: 100, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            // ==============================

            if let date = nextDate(for: event) {
                Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 100)
            }
        }
        .contentShape(Rectangle())
    }

    /// When the person will next be at the event: the next showing still to start for
    /// multi-showing events, otherwise the event's start date.
    private func nextDate(for event: Submission) -> Date? {
        let now = Date()
        if let upcoming = (event.eventShowings ?? []).map(\.start).filter({ $0 >= now }).min() {
            return upcoming
        }
        return event.eventStartDate
    }
}
