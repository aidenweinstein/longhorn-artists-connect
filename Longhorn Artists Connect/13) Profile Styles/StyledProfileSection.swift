//
//  StyledProfileSection.swift
//  Longhorn Artists Connect
//
//  The part of a profile that changes with its style, placed under the bio on the
//  user's own Portfolio and on everyone else's profile:
//
//  • Actor — like Actors Access: headshot beside the stats sheet (age range, gender,
//    height…), their reel, a resume of every role (Nexus credits plus ones they typed
//    in), and skills, languages and training.
//  • Filmmaker — like IMDb: a filmography grouped by job, newest first, with year,
//    title and type, then a grid of stills from their work.
//  • Musician — like Spotify: songs, albums & EPs, and upcoming shows.
//
//  Profiles that haven't picked a style show nothing extra (and the owner sees a
//  prompt to pick one).
//

import SwiftUI
import UIKit

struct StyledProfileSection: View {
    /// The person's display name, as credits spell it.
    let name: String
    /// Their directory ID (`UserProfile_…`), when known.
    let profileID: String?
    /// True on the user's own Portfolio.
    var isOwn: Bool = false

    @ObservedObject private var store = SubmissionStore_3_2.shared
    @ObservedObject private var creative = CreativeProfileStore.shared

    @State private var showEditor = false
    @State private var editorStartStyle: ProfileStyle?
    @State private var selectedPost: Submission?
    @State private var selectedProject: Submission?
    @State private var selectedEvent: Submission?
    @State private var liked = false

    private var profile: CreativeProfile? {
        isOwn ? creative.myProfile : creative.profile(forUserID: profileID)
    }

    private var isPerson: (OrderedEntry) -> Bool {
        PersonMatcher.make(name: name, profileID: profileID)
    }

    /// Every approved post crediting this person, with their credits on it.
    private var credited: [(post: Submission, entries: [OrderedEntry])] {
        store.visibleApprovedSubmissions.compactMap { post -> (post: Submission, entries: [OrderedEntry])? in
            let entries = post.credits(where: isPerson)
            return entries.isEmpty ? nil : (post: post, entries: entries)
        }
        .sorted { lhs, rhs in
            if lhs.post.creditYear != rhs.post.creditYear { return lhs.post.creditYear > rhs.post.creditYear }
            return lhs.post.createdDate > rhs.post.createdDate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Always on screen (zero height), so the styles load even for a profile
            // that shows nothing extra yet.
            Color.clear
                .frame(height: 0)
                .task { await creative.refresh() }

            if let profile {
                VStack(alignment: .leading, spacing: 20) {
                    Divider()
                    header(profile.style)
                    switch profile.style {
                    case .actor: actorLayout(profile)
                    case .filmmaker: filmmakerLayout(profile)
                    case .musician: musicianLayout(profile)
                    }
                }
            } else if isOwn {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                    StyleChooserCard(suggested: nil) { style in
                        editorStartStyle = style
                        showEditor = true
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            ProfileStyleEditorView(startingStyle: editorStartStyle)
        }
        .sheet(item: $selectedPost) { post in
            PostDetailRouter(post: post, liked: $liked)
        }
        .sheet(item: $selectedProject) { project in
            UpcomingProjectDetailView(submission: project)
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event)
        }
    }

    private func header(_ style: ProfileStyle) -> some View {
        HStack {
            Label(style.rawValue, systemImage: style.symbol)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer()
            if isOwn {
                Button("Edit") {
                    editorStartStyle = nil
                    showEditor = true
                }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    /// Opens whichever detail page fits the post.
    private func open(_ post: Submission) {
        switch post.type {
        case .project: selectedProject = post
        case .event: selectedEvent = post
        default: selectedPost = post
        }
    }

    private func headshotImage(_ profile: CreativeProfile) -> UIImage? {
        if isOwn, let mine = creative.myHeadshot { return mine }
        guard let url = profile.headshotFileURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    // MARK: - Actor (Actors Access)

    @ViewBuilder
    private func actorLayout(_ profile: CreativeProfile) -> some View {
        let details = profile.details.actor

        HStack(alignment: .top, spacing: 16) {
            Group {
                if let headshot = headshotImage(profile) {
                    Image(uiImage: headshot)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .overlay(
                            VStack(spacing: 4) {
                                Image(systemName: "person.crop.rectangle")
                                    .font(.title)
                                Text("No headshot").font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 120, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                if details.statRows.isEmpty {
                    Text(isOwn ? "Add your age range, height and more with Edit." : "No details yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(details.statRows, id: \.label) { row in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(row.value)
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
            Spacer(minLength: 0)
        }

        if let reelID = details.reelPostID,
           let reel = store.visibleApprovedSubmissions.first(where: { $0.id.uuidString == reelID }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Reel").font(.title3.bold())
                Button { open(reel) } label: {
                    ZStack {
                        Color.secondary.opacity(0.15)
                            .frame(maxWidth: .infinity)
                            .frame(height: 190)
                            .overlay {
                                if let data = reel.thumbnailData, let image = UIImage(data: data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(.white)
                            .shadow(radius: 6)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text(reel.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(8)
                    }
                }
                .buttonStyle(.plain)
            }
        }

        actorResume(details)

        let extras = [("Special skills", details.specialSkills),
                      ("Languages", details.languages),
                      ("Training", details.training)]
            .filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        ForEach(extras, id: \.0) { item in
            VStack(alignment: .leading, spacing: 4) {
                Text(item.0).font(.headline)
                Text(item.1)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One resume line, from a Nexus credit or a typed-in credit.
    private struct ResumeLine: Identifiable {
        let id: String
        let category: String
        let project: String
        let role: String
        let company: String
        let year: String
        let post: Submission?
    }

    private func resumeLines(_ details: ActorDetails) -> [ResumeLine] {
        var lines: [ResumeLine] = []
        for item in credited {
            let castRoles = item.post.orderedCast.filter(isPerson)
            guard !castRoles.isEmpty else { continue }
            let category: String
            switch item.post.type {
            case .film: category = "Film"
            case .reel: category = "Performance"
            case .project: category = "In production"
            case .event: category = "Theatre & live"
            default: category = "Other"
            }
            let director = item.post.orderedCrew.first {
                $0.role.trimmingCharacters(in: .whitespaces).lowercased() == "director"
            }?.name ?? ""
            lines.append(ResumeLine(
                id: item.post.id.uuidString,
                category: category,
                project: item.post.title,
                role: castRoles.map(\.role).filter { !$0.isEmpty }.joined(separator: ", "),
                company: director,
                year: item.post.creditYear,
                post: item.post
            ))
        }
        for credit in details.resume where !credit.project.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append(ResumeLine(id: credit.id.uuidString, category: credit.category, project: credit.project,
                                    role: credit.role, company: credit.company, year: credit.year, post: nil))
        }
        return lines
    }

    @ViewBuilder
    private func actorResume(_ details: ActorDetails) -> some View {
        let lines = resumeLines(details)
        let order = ["In production", "Film", "Television", "Theatre", "Theatre & live", "Performance",
                     "Commercial", "New Media", "Other"]
        let categories = order.filter { category in lines.contains { $0.category == category } }
            + Set(lines.map(\.category)).subtracting(order).sorted()

        VStack(alignment: .leading, spacing: 12) {
            Text("Resume").font(.title3.bold())
            if lines.isEmpty {
                Text(isOwn ? "Roles you're credited for on Nexus appear here. Add others with Edit." : "No credits yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(categories, id: \.self) { category in
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.brandOrange)
                    ForEach(lines.filter { $0.category == category }) { line in
                        Button {
                            if let post = line.post { open(post) }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(line.project)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(line.role.isEmpty ? "—" : line.role)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text([line.company, line.year].filter { !$0.isEmpty }.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .lineLimit(2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(line.post == nil)
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Filmmaker (IMDb)

    /// Credits grouped by job ("Director", "Editor", "Actor"…), biggest group first.
    private var filmographyGroups: [(role: String, items: [(post: Submission, detail: String)])] {
        var groups: [String: [(post: Submission, detail: String)]] = [:]
        var displayNames: [String: String] = [:]
        for item in credited {
            for entry in item.entries {
                let isCast = item.post.orderedCast.contains(entry)
                let role = isCast ? "Actor" : entry.role.trimmingCharacters(in: .whitespaces)
                guard !role.isEmpty else { continue }
                let key = role.lowercased()
                displayNames[key] = displayNames[key] ?? role
                var list = groups[key] ?? []
                if !list.contains(where: { $0.post.id == item.post.id }) {
                    let detail = isCast && !entry.role.isEmpty ? "as \(entry.role)" : ""
                    list.append((post: item.post, detail: detail))
                }
                groups[key] = list
            }
        }
        return groups
            .map { (role: displayNames[$0.key] ?? $0.key, items: $0.value) }
            .sorted { $0.items.count != $1.items.count ? $0.items.count > $1.items.count : $0.role < $1.role }
    }

    private static func typeLabel(_ post: Submission) -> String {
        switch post.type {
        case .project: return NowView.stage(of: post)
        case .reel: return "Performance"
        case .music: return post.musicCategory.isEmpty ? "Music" : post.musicCategory
        default: return post.type.displayName
        }
    }

    /// Still frames for the grid: the post's own stills when they're on this device,
    /// otherwise its thumbnail.
    private var stills: [(id: String, image: UIImage, post: Submission)] {
        var result: [(id: String, image: UIImage, post: Submission)] = []
        for item in credited where [.film, .reel, .photography, .design].contains(item.post.type) {
            var added = false
            for file in item.post.stillImageFileNames + item.post.photoImageFileNames {
                guard result.count < 18 else { break }
                if let url = FileManager.default.mediaFileURL(named: file), let image = UIImage(contentsOfFile: url.path) {
                    result.append((id: "\(item.post.id.uuidString)-\(file)", image: image, post: item.post))
                    added = true
                }
            }
            if !added, result.count < 18, let data = item.post.thumbnailData, let image = UIImage(data: data) {
                result.append((id: item.post.id.uuidString, image: image, post: item.post))
            }
        }
        return result
    }

    @ViewBuilder
    private func filmmakerLayout(_ profile: CreativeProfile) -> some View {
        let details = profile.details.filmmaker
        let groups = filmographyGroups

        if !details.specialties.isEmpty || !details.gear.isEmpty || details.openToCrew {
            VStack(alignment: .leading, spacing: 6) {
                if details.openToCrew {
                    StatusPill(text: "Open to joining crews", emphasized: true)
                }
                if !details.specialties.isEmpty {
                    Text(details.specialties).font(.subheadline)
                }
                if !details.gear.isEmpty {
                    Text("Gear: \(details.gear)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }

        VStack(alignment: .leading, spacing: 14) {
            Text("Filmography").font(.title3.bold())
            if groups.isEmpty {
                Text(isOwn ? "Everything you're credited on shows up here by job." : "No credits yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(groups, id: \.role) { group in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.role).font(.headline)
                        Text("\(group.items.count) credit\(group.items.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 6)
                    ForEach(group.items, id: \.post.id) { item in
                        Button { open(item.post) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(item.post.creditYear)
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.post.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.brandOrange)
                                    Text([Self.typeLabel(item.post), item.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }

        let stills = self.stills
        if !stills.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stills").font(.title3.bold())
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    ForEach(stills, id: \.id) { still in
                        Button { open(still.post) } label: {
                            Color.clear
                                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                .overlay(
                                    Image(uiImage: still.image)
                                        .resizable()
                                        .scaledToFill()
                                )
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Musician (Spotify)

    private func releases(_ details: MusicianDetails) -> [Submission] {
        let names = Set([name, details.artistName].map(Collaborator.nameKey(for:)).filter { !$0.isEmpty })
        return store.visibleApprovedSubmissions
            .filter { post in
                post.type == .music
                    && (names.contains(Collaborator.nameKey(for: post.artist)) || !post.credits(where: isPerson).isEmpty)
            }
            .sorted { lhs, rhs in
                if lhs.creditYear != rhs.creditYear { return lhs.creditYear > rhs.creditYear }
                return lhs.createdDate > rhs.createdDate
            }
    }

    private func upcomingShows(_ details: MusicianDetails) -> [Submission] {
        let names = [name, details.artistName].map(Collaborator.nameKey(for:)).filter { !$0.isEmpty }
        return store.visibleApprovedSubmissions
            .filter { event in
                guard event.isUpcomingEvent else { return false }
                if !event.credits(where: isPerson).isEmpty { return true }
                if names.contains(Collaborator.nameKey(for: event.submittedBy)) { return true }
                let lineup = (event.eventLineup ?? "").lowercased()
                return names.contains { lineup.contains($0) }
            }
            .sorted { ($0.eventStartDate ?? .distantFuture) < ($1.eventStartDate ?? .distantFuture) }
    }

    @ViewBuilder
    private func musicianLayout(_ profile: CreativeProfile) -> some View {
        let details = profile.details.musician
        let all = releases(details)
        let songs = all.filter { !["EP", "Album"].contains($0.musicCategory) }
        let records = all.filter { ["EP", "Album"].contains($0.musicCategory) }
        let shows = upcomingShows(details)

        VStack(alignment: .leading, spacing: 6) {
            if !details.artistName.isEmpty {
                Text(details.artistName).font(.title2.bold())
            }
            let facts = [details.genres, details.instruments].filter { !$0.isEmpty }
            if !facts.isEmpty {
                Text(facts.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !details.availability.isEmpty {
                ChipRow(chips: details.availability.map { "Available: \($0)" })
            }
        }

        if !shows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Upcoming shows").font(.title3.bold())
                ForEach(shows) { event in
                    Button { open(event) } label: {
                        HStack(spacing: 12) {
                            if let start = event.eventStartDate {
                                VStack(spacing: 0) {
                                    Text(start.formatted(.dateTime.month(.abbreviated)).uppercased())
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(Color.brandOrange)
                                    Text(start.formatted(.dateTime.day()))
                                        .font(.title3.bold())
                                }
                                .frame(width: 44)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title).font(.subheadline.weight(.semibold))
                                Text([event.eventLocation ?? "", event.eventStartDate?.formatted(date: .omitted, time: .shortened) ?? ""]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Songs").font(.title3.bold())
            if songs.isEmpty {
                Text(isOwn ? "Music you're credited on shows up here." : "No songs yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(songs.prefix(10).enumerated()), id: \.element.id) { index, song in
                Button { open(song) } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        NowThumbnail(data: song.thumbnailData, width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(song.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                if song.explicit {
                                    Text("E")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 3)
                                        .background(Color.secondary.opacity(0.3), in: RoundedRectangle(cornerRadius: 2))
                                }
                            }
                            Text([song.artist, song.creditYear].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Albums & EPs").font(.title3.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(records) { record in
                            Button { open(record) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    NowThumbnail(data: record.thumbnailData, width: 132, height: 132)
                                    Text(record.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text("\(record.creditYear) · \(record.musicCategory)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 132, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
