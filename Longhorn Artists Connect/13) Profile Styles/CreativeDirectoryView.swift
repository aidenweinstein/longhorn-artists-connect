//
//  CreativeDirectoryView.swift
//  Longhorn Artists Connect
//
//  The public Actors / Filmmakers / Musicians pages, and the moderator's queue that
//  decides who appears on them.
//
//  Only profiles a moderator approved for their current style are listed. Picking
//  a style (or switching to a new one) puts a profile in the queue; editing a
//  declined profile sends it back.
//

import SwiftUI
import UIKit

// MARK: - Public Pages

/// The public pages presented as a sheet (from Now's Browse row). Wraps
/// `CreativeDirectoryPage` in its own navigation stack with a Done button; the
/// Network directory pushes the page directly instead.
struct CreativeDirectoryView: View {
    let style: ProfileStyle

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CreativeDirectoryPage(style: style)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// One public page — Actors, Filmmakers or Musicians — with a segmented control to
/// move between the three. Pushable: the Network directory lists each as its own
/// entry (see `NetworkDirectoryView`), and Now presents it in a sheet.
struct CreativeDirectoryPage: View {
    @State var style: ProfileStyle

    @ObservedObject private var creative = CreativeProfileStore.shared
    @ObservedObject private var people = UserProfileManager.shared
    @ObservedObject private var store = SubmissionStore_3_2.shared

    @State private var search = ""
    @State private var selectedPerson: DirectoryUser?

    private var listed: [(user: DirectoryUser, profile: CreativeProfile)] {
        let all = creative.listedPeople(for: style, in: people.allUsers)
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter { item in
            let haystack = [item.user.fullName, item.user.rolesString, item.user.school,
                            item.profile.details.musician.artistName, item.profile.details.musician.genres,
                            item.profile.details.actor.basedIn, item.profile.details.filmmaker.specialties]
                .joined(separator: " ")
                .lowercased()
            return haystack.contains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Page", selection: $style) {
                    ForEach(ProfileStyle.allCases) { Text($0.plural).tag($0) }
                }
                .pickerStyle(.segmented)

                if listed.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: style.symbol)
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(search.isEmpty ? "No \(style.plural.lowercased()) listed yet" : "No matches")
                            .font(.headline)
                        Text("Profiles appear here once a moderator approves them.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    switch style {
                    case .actor: actorGrid
                    case .filmmaker, .musician: personList
                    }
                }
            }
            .padding()
        }
        .searchable(text: $search, prompt: "Search \(style.plural.lowercased())")
        .navigationTitle(style.plural)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await creative.refresh(force: true)
            await people.fetchAllUsers(forceRefresh: true)
        }
        .task {
            await creative.refresh()
            await people.fetchAllUsers()
        }
        .sheet(item: $selectedPerson) { user in
            PersonProfileView(name: user.fullName)
        }
    }

    // MARK: Actors — headshot grid, like a casting site

    private var actorGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
            ForEach(listed, id: \.user.id) { item in
                Button { selectedPerson = item.user } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Color.secondary.opacity(0.12)
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .overlay {
                                if let image = headshot(for: item) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Image(systemName: "person.crop.rectangle")
                                        .font(.largeTitle)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(item.user.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        let actor = item.profile.details.actor
                        Text([actor.ageRangeText, actor.gender, actor.basedIn].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func headshot(for item: (user: DirectoryUser, profile: CreativeProfile)) -> UIImage? {
        if let url = item.profile.headshotFileURL, let image = UIImage(contentsOfFile: url.path) { return image }
        return item.user.profileImageData.flatMap { UIImage(data: $0) }
    }

    // MARK: Filmmakers & Musicians — rows

    private var personList: some View {
        VStack(spacing: 0) {
            ForEach(listed, id: \.user.id) { item in
                Button { selectedPerson = item.user } label: {
                    HStack(spacing: 12) {
                        avatar(item.user, square: style == .musician)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(for: item))
                                .font(.headline)
                                .lineLimit(1)
                            Text(subtitle(for: item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    private func title(for item: (user: DirectoryUser, profile: CreativeProfile)) -> String {
        let artist = item.profile.details.musician.artistName
        if style == .musician, !artist.isEmpty, artist != item.user.fullName {
            return "\(artist) (\(item.user.displayName))"
        }
        return item.user.displayName
    }

    private func subtitle(for item: (user: DirectoryUser, profile: CreativeProfile)) -> String {
        switch style {
        case .musician:
            let musician = item.profile.details.musician
            return [musician.genres, musician.instruments].filter { !$0.isEmpty }.joined(separator: " · ")
        default:
            let credits = store.visibleApprovedSubmissions.filter { post in
                !post.credits(where: PersonMatcher.make(name: item.user.fullName, profileID: item.user.id)).isEmpty
            }.count
            let parts = [item.user.rolesString, credits > 0 ? "\(credits) credit\(credits == 1 ? "" : "s")" : ""]
            return parts.filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    private func avatar(_ user: DirectoryUser, square: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: square ? 6 : 26)
        return Group {
            if let data = user.profileImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
                    .overlay(Text(user.initials).font(.headline).foregroundStyle(.secondary))
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(shape)
    }
}

// MARK: - Moderation

/// Row in the Moderate tab linking to the profile review queue.
struct CreativeListingsModerationSection: View {
    @ObservedObject private var creative = CreativeProfileStore.shared

    var body: some View {
        Section {
            NavigationLink {
                CreativeListingsModerationView()
            } label: {
                HStack {
                    Label("Actors, Filmmakers & Musicians pages", systemImage: "person.crop.rectangle.stack")
                    Spacer()
                    let pending = creative.pendingProfiles.count
                    if pending > 0 {
                        Text("\(pending)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.brandOrange, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .task { await creative.refresh() }
    }
}

/// Approve or decline profiles for the public style pages.
struct CreativeListingsModerationView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case pending = "To review"
        case listed = "Listed"
        case declined = "Declined"
        var id: String { rawValue }
    }

    @ObservedObject private var creative = CreativeProfileStore.shared
    @ObservedObject private var people = UserProfileManager.shared
    @State private var filter: Filter = .pending
    @State private var preview: DirectoryUser?

    private var rows: [CreativeProfile] {
        switch filter {
        case .pending: return creative.pendingProfiles
        case .listed: return creative.listedProfiles
        case .declined: return creative.declinedProfiles
        }
    }

    private func user(for profile: CreativeProfile) -> DirectoryUser? {
        people.allUsers.first { $0.messagingUserID == profile.userID }
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if let error = creative.lastError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if rows.isEmpty {
                Text(filter == .pending ? "Nothing to review." : "None yet.")
                    .foregroundStyle(.secondary)
            }

            ForEach(rows) { profile in
                row(profile)
            }
        }
        .navigationTitle("Profile pages")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await creative.refresh(force: true)
            await people.fetchAllUsers(forceRefresh: true)
        }
        .task { await creative.refresh(force: true) }
        .sheet(item: $preview) { user in
            PersonProfileView(name: user.fullName)
        }
    }

    private func row(_ profile: CreativeProfile) -> some View {
        let person = user(for: profile)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                preview = person
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: profile.style.symbol)
                        .frame(width: 24)
                        .foregroundStyle(Color.brandOrange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person?.displayName ?? "Unknown account")
                            .font(.headline)
                        Text("\(profile.style.rawValue) · updated \(profile.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !summary(profile).isEmpty {
                            Text(summary(profile))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(person == nil)

            HStack {
                if filter != .listed {
                    Button {
                        Task { await creative.setListing(for: profile, status: .approved) }
                    } label: {
                        Label("Approve", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                if filter != .declined {
                    Button(role: .destructive) {
                        Task { await creative.setListing(for: profile, status: .declined) }
                    } label: {
                        Label(filter == .listed ? "Remove" : "Decline", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    private func summary(_ profile: CreativeProfile) -> String {
        switch profile.style {
        case .actor:
            let a = profile.details.actor
            return [a.ageRangeText, a.gender, a.basedIn, profile.headshotFileURL == nil ? "no headshot" : "headshot"]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        case .musician:
            let m = profile.details.musician
            return [m.artistName, m.genres, m.instruments].filter { !$0.isEmpty }.joined(separator: " · ")
        case .filmmaker:
            return profile.details.filmmaker.specialties
        }
    }
}
