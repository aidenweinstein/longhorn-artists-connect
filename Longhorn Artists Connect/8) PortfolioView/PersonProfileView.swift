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
                    Divider()
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
            .fullScreenCover(isPresented: $showEnlargedPhoto) {
                if let profileImage {
                    ProfilePhotoViewer(image: profileImage)
                }
            }
            .task {
                // Make sure the directory is loaded so this person's synced
                // bio/photo/roles appear (throttled internally if already fresh).
                await profileManager.fetchAllUsers()
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
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                profileImageView
                    // Tap the photo to see it enlarged and centered (only when set).
                    .onTapGesture {
                        if profileImage != nil { showEnlargedPhoto = true }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.largeTitle)
                        .bold()
                    academicInfoView
                }
                Spacer(minLength: 0)
            }

            if !resolvedUserType.isEmpty {
                userTypeBubbles(resolvedUserType)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileImageView: some View {
        Group {
            if let profileImage {
                Image(uiImage: profileImage)
                    .resizable()
                    .scaledToFill()
                    // ====== UI CONTROLS!!!!! ======
                    .frame(width: 72, height: 72)
                    // ==============================
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .scaledToFit()
                    // ====== UI CONTROLS!!!!! ======
                    .frame(width: 72, height: 72)
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

    private func userTypeBubbles(_ userType: String) -> some View {
        // Use the portfolio's shared FlowLayout (which centers each wrapped row) so
        // the role tags sit in a full-width band below the photo and academic text,
        // matching the user's own portfolio page instead of drifting up beside them.
        RoleTagFlowLayout(spacing: 6) {
            ForEach(userType.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }, id: \.self) { role in
                Text(role)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    // ====== UI CONTROLS!!!!! ======
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.utBrandOrange)
                    .cornerRadius(8)
                    // ==============================
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

    private var submissionsView: some View {
        Group {
            if personSubmissions.isEmpty {
                Text("No projects yet.")
                    .foregroundStyle(.secondary)
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
