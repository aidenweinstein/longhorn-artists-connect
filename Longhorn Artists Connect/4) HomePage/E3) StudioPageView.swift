//
//  E3) StudioPageView.swift
//  Longhorn Artists Connect
//
//  A profile-style page for a Studio (Collective or Incubator).
//  Shows the studio's work and allows customization via StudioPageManager.
//

import SwiftUI
import PhotosUI

// MARK: - Studio Page View

struct StudioPageView: View {
    let studioType: StudioType

    @ObservedObject private var manager = StudioPageManager.shared
    @ObservedObject private var store: SubmissionStore_3_2 = .shared

    @State private var isEditing = false
    @State private var selectedSubmission: Submission?

    // Define brand colors
    private static let darkBrownColor   = Color(red: 100/255, green: 65/255, blue: 40/255).opacity(1.0)
    private static let orangeNavColor   = Color(red: 191/255, green: 87/255, blue: 0/255)

    private var studio: Studio? { manager.studio(for: studioType) }

    // All submissions that belong to studio members
    private var studioSubmissions: [Submission] {
        guard let studio else { return [] }
        return store.approvedSubmissions.filter { submission in
            studio.members.contains(submission.submittedBy) &&
            submission.type != .event &&
            submission.type != .project
        }
        .sorted { $0.createdDate > $1.createdDate }
    }

    // Pinned / featured submissions
    private var featuredSubmissions: [Submission] {
        guard let studio else { return [] }
        return studio.featuredSubmissionIDs.compactMap { id in
            store.approvedSubmissions.first { $0.id == id }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                bannerSection
                infoSection
                    .padding(.horizontal)
                    .padding(.top, 12)

                if !featuredSubmissions.isEmpty {
                    sectionHeader("Pinned Work")
                    submissionsGrid(featuredSubmissions)
                }

                sectionHeader("All Work")

                if studioSubmissions.isEmpty {
                    Text("No work posted yet.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                } else {
                    submissionsGrid(studioSubmissions)
                }

                membersSection
                    .padding(.top, 8)

                Spacer(minLength: 40)
            }
        }
        .navigationTitle(studio?.name ?? studioType.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Self.orangeNavColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isEditing = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.white)
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let s = studio {
                StudioEditorView(studio: s)
            }
        }
        .sheet(item: $selectedSubmission) { submission in
            PostDetailRouter(post: submission, liked: .constant(false))
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var bannerSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Banner image or gradient fallback
            Group {
                if let data = studio?.bannerImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color.brandOrange, Color.brandOrange.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .clipped()

            // Logo overlay
            if let data = studio?.logoImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .padding(12)
                    .shadow(radius: 4)
            } else {
                Image(systemName: studioType.icon)
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Self.darkBrownColor)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .padding(12)
                    .shadow(radius: 4)
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(studio?.name ?? studioType.rawValue)
                    .font(.title2.bold())

                if let year = studio?.foundedYear, !year.isEmpty {
                    Text("Est. \(year)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let tagline = studio?.tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let bio = studio?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.body)
                    .padding(.top, 2)
            }

            HStack(spacing: 16) {
                if let handle = studio?.instagramHandle, !handle.isEmpty {
                    Label("@\(handle)", systemImage: "camera")
                        .font(.caption)
                        .foregroundStyle(Color.brandOrange)
                }
                if let url = studio?.websiteURL, !url.isEmpty {
                    Label(url, systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(Color.brandOrange)
                        .lineLimit(1)
                }
            }
            .padding(.top, 2)

            // Stats row
            HStack(spacing: 24) {
                statPill(value: studioSubmissions.count, label: "Posts")
                statPill(value: studio?.members.count ?? 0, label: "Members")
                statPill(value: featuredSubmissions.count, label: "Pinned")
            }
            .padding(.top, 6)
        }
    }

    private func statPill(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    private func submissionsGrid(_ submissions: [Submission]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 2
        ) {
            ForEach(submissions) { submission in
                Button {
                    selectedSubmission = submission
                } label: {
                    SubmissionThumbnailCell(submission: submission)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Members")

            if let members = studio?.members, !members.isEmpty {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(members, id: \.self) { member in
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundStyle(Color.brandOrange)
                            Text(member)
                                .font(.subheadline)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 2)
                    }
                }
            } else {
                Text("No members yet.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
    }
}

// MARK: - Submission Thumbnail Cell

private struct SubmissionThumbnailCell: View {
    let submission: Submission

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let data = submission.thumbnailData,
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.width)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: geo.size.width, height: geo.size.width)
                        .overlay(
                            Image(systemName: typeIcon)
                                .foregroundStyle(.secondary)
                        )
                }

                // Type badge
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: typeIcon)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                            .padding(4)
                    }
                    Spacer()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var typeIcon: String {
        switch submission.type {
        case .film:    return "film"
        case .music:   return "music.note"
        case .reel:    return "star.fill"
        case .project: return "doc.text"
        case .event:   return "calendar"
        }
    }
}

// MARK: - Studio Editor Sheet

struct StudioEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = StudioPageManager.shared

    @State private var draft: Studio
    @State private var bannerPickerItem: PhotosPickerItem?
    @State private var logoPickerItem: PhotosPickerItem?
    @State private var newMember = ""
    @State private var showingAddMember = false

    init(studio: Studio) {
        _draft = State(initialValue: studio)
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Identity
                Section("Identity") {
                    TextField("Studio Name", text: $draft.name)
                    TextField("Tagline", text: $draft.tagline)
                    TextField("Bio", text: $draft.bio, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Founded Year", text: $draft.foundedYear)
                        .keyboardType(.numberPad)
                }

                // MARK: Links
                Section("Links") {
                    HStack {
                        Text("Instagram")
                            .foregroundStyle(.secondary)
                        TextField("@handle", text: $draft.instagramHandle)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    HStack {
                        Text("Website")
                            .foregroundStyle(.secondary)
                        TextField("https://…", text: $draft.websiteURL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                }

                // MARK: Images
                Section("Images") {
                    PhotosPicker(selection: $bannerPickerItem, matching: .images) {
                        Label(
                            draft.bannerImageData != nil ? "Change Banner" : "Set Banner Image",
                            systemImage: "photo.on.rectangle"
                        )
                    }
                    .onChange(of: bannerPickerItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                draft.bannerImageData = data
                            }
                        }
                    }

                    if draft.bannerImageData != nil {
                        Button("Remove Banner", role: .destructive) {
                            draft.bannerImageData = nil
                        }
                    }

                    PhotosPicker(selection: $logoPickerItem, matching: .images) {
                        Label(
                            draft.logoImageData != nil ? "Change Logo" : "Set Logo Image",
                            systemImage: "photo.circle"
                        )
                    }
                    .onChange(of: logoPickerItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                draft.logoImageData = data
                            }
                        }
                    }

                    if draft.logoImageData != nil {
                        Button("Remove Logo", role: .destructive) {
                            draft.logoImageData = nil
                        }
                    }
                }

                // MARK: Members
                Section {
                    ForEach(draft.members, id: \.self) { member in
                        Text(member)
                    }
                    .onDelete { indexSet in
                        draft.members.remove(atOffsets: indexSet)
                    }

                    Button {
                        showingAddMember = true
                    } label: {
                        Label("Add Member", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Members")
                } footer: {
                    Text("Swipe left to remove a member.")
                }
            }
            .navigationTitle("Edit \(draft.type.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        manager.update(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Add Member", isPresented: $showingAddMember) {
                TextField("Full name", text: $newMember)
                    .autocorrectionDisabled()
                Button("Add") {
                    let trimmed = newMember.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && !draft.members.contains(trimmed) {
                        draft.members.append(trimmed)
                    }
                    newMember = ""
                }
                Button("Cancel", role: .cancel) {
                    newMember = ""
                }
            } message: {
                Text("Enter the member's display name as it appears on their posts.")
            }
        }
    }
}


