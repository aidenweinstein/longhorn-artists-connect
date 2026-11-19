//
//  StyledProfileSection.swift
//  Longhorn Artists Connect
//
//  The part of a profile that the person's role tags unlock, placed under the bio on
//  the user's own Portfolio and on everyone else's profile (see CreativeGroup.swift):
//
//  First, a compact card per group with what they filled in (Actor stats; Filmmaker
//  studios, certifications and gear; Musician names, instruments, genres and streaming
//  pages), only for groups with something filled in. Then, per group:
//
//  • Actor / Dancer tags — like Actors Access: headshot, their reel, a resume of every
//    role (Nexus credits plus ones they typed in), and skills, languages and training.
//  • Film tags — like IMDb: a filmography grouped by job, newest first, with year,
//    title and type.
//  • Musician / Singer / Composer tags — like Spotify: songs, albums & EPs, and
//    upcoming shows.
//
//  Someone with tags in more than one group gets every matching section. People
//  with none of these tags show nothing extra.
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
    @ObservedObject private var people = UserProfileManager.shared
    @Environment(\.openURL) private var openURL

    @AppStorage("userType") private var myTagsRaw = ""

    @State private var showEditor = false
    @State private var selectedPost: Submission?
    @State private var selectedProject: Submission?
    @State private var selectedEvent: Submission?
    @State private var liked = false

    /// The person's directory entry, for their tags.
    private var directoryUser: DirectoryUser? {
        if let profileID, let user = people.allUsers.first(where: { $0.id == profileID }) { return user }
        return people.findUser(byName: name)
    }

    /// The groups the person's tags put them in, in display order.
    private var groups: [CreativeGroup] {
        let set: Set<CreativeGroup>
        if isOwn {
            set = CreativeGroup.groups(forStoredTags: myTagsRaw)
        } else {
            set = CreativeGroup.groups(forTagNames: directoryUser?.userTypes ?? [])
        }
        return CreativeGroup.ordered(set)
    }

    /// Their saved details; empty defaults when they've never filled anything in, so
    /// the credit-driven parts (filmography, discography, resume) still show.
    private var details: CreativeDetails {
        if isOwn { return creative.myDetails }
        return creative.profile(forUserID: profileID ?? directoryUser?.id)?.details ?? CreativeDetails()
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
            // Always on screen (zero height), so details load even for a profile that
            // shows nothing extra yet.
            Color.clear
                .frame(height: 0)
                .task { await creative.refresh() }

            // Compact Actor / Filmmaker / Musician cards right under the bio — only the
            // ones with something filled in, Actor always first.
            let cards = groups.filter(hasCardInfo)
            if !cards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(cards) { group in
                        infoCard(group)
                    }
                }
                .padding(.bottom, 20)
            }

            // Musicians with nothing credited yet (no shows, songs, or records) get no
            // Musician section rather than an empty one.
            let sections = groups.filter { $0 != .musician || hasMusicianCredits(details.musician) }
            if !sections.isEmpty {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(sections) { group in
                        VStack(alignment: .leading, spacing: 20) {
                            Divider()
                            header(group)
                            switch group {
                            case .actor: actorLayout(details.actor)
                            case .filmmaker: filmmakerLayout(details.filmmaker)
                            case .musician: musicianLayout(details.musician)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            CreativeDetailsEditorView()
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

    // MARK: - Info Cards

    /// The label/value rows a group's card shows, skipping blanks.
    private func cardRows(_ group: CreativeGroup) -> [(label: String, value: String)] {
        let rows: [(String, String)]
        switch group {
        case .actor:
            return details.actor.statRows
        case .filmmaker:
            let f = details.filmmaker
            rows = [("Studio(s)", f.studios), ("Certifications", f.certifications), ("Gear", f.gear)]
        case .musician:
            let m = details.musician
            rows = [("Solo act", m.soloName), ("Band", m.bandName),
                    ("Instruments", m.instrumentList.joined(separator: ", ")),
                    ("Genres", m.genreList.joined(separator: ", "))]
        }
        return rows
            .filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { (label: $0.0, value: $0.1) }
    }

    private func hasCardInfo(_ group: CreativeGroup) -> Bool {
        !cardRows(group).isEmpty || (group == .musician && !details.musician.links.isEmpty)
    }

    private func infoCard(_ group: CreativeGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(group.rawValue, systemImage: group.symbol)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.brandOrange)
            ForEach(cardRows(group), id: \.label) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 104, alignment: .leading)
                    Text(row.value)
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if group == .musician {
                let links = details.musician.links
                if !links.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(links, id: \.service) { link in
                                Button {
                                    openURL(link.url)
                                } label: {
                                    Label(link.service.rawValue, systemImage: link.service.symbol)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.brandOrange, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.15)))
    }

    private func header(_ group: CreativeGroup) -> some View {
        HStack {
            Label(group.rawValue, systemImage: group.symbol)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer()
            if isOwn {
                Button("Edit") { showEditor = true }
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

    private var headshotImage: UIImage? {
        if isOwn { return creative.myHeadshot }
        return creative.headshot(forUserID: profileID ?? directoryUser?.id)
    }

    // MARK: - Actor (Actors Access)

    @ViewBuilder
    private func actorLayout(_ details: ActorDetails) -> some View {
        // The stats are on the Actor card under the bio; the headshot leads the section.
        if let headshot = headshotImage {
            Image(uiImage: headshot)
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if isOwn {
            Text("Add your headshot, playable age, height and more with Edit.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func filmmakerLayout(_ details: FilmmakerDetails) -> some View {
        let groups = filmographyGroups

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

    }

    // MARK: - Musician (Spotify)

    /// Plain loops rather than `filter` closures: `Collaborator.nameKey` is main-actor
    /// isolated, and a loop body in this (main-actor) view stays isolated where a
    /// closure wouldn't.
    private func releases(_ details: MusicianDetails) -> [Submission] {
        let names = Set(([name] + details.actNames).map { Collaborator.nameKey(for: $0) }.filter { !$0.isEmpty })
        var result: [Submission] = []
        for post in store.visibleApprovedSubmissions where post.type == .music {
            if names.contains(Collaborator.nameKey(for: post.artist)) || !post.credits(where: isPerson).isEmpty {
                result.append(post)
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.creditYear != rhs.creditYear { return lhs.creditYear > rhs.creditYear }
            return lhs.createdDate > rhs.createdDate
        }
    }

    private func upcomingShows(_ details: MusicianDetails) -> [Submission] {
        let names = ([name] + details.actNames).map { Collaborator.nameKey(for: $0) }.filter { !$0.isEmpty }
        var result: [Submission] = []
        for event in store.visibleApprovedSubmissions where event.isUpcomingEvent {
            let lineup = (event.eventLineup ?? "").lowercased()
            if !event.credits(where: isPerson).isEmpty
                || names.contains(Collaborator.nameKey(for: event.submittedBy))
                || names.contains(where: { lineup.contains($0) }) {
                result.append(event)
            }
        }
        return result.sorted { ($0.eventStartDate ?? .distantFuture) < ($1.eventStartDate ?? .distantFuture) }
    }

    /// True when anything would appear under Musician: an upcoming show, a song, or a record.
    private func hasMusicianCredits(_ details: MusicianDetails) -> Bool {
        !releases(details).isEmpty || !upcomingShows(details).isEmpty
    }

    @ViewBuilder
    private func musicianLayout(_ details: MusicianDetails) -> some View {
        let all = releases(details)
        let songs = all.filter { !["EP", "Album"].contains($0.musicCategory) }
        let records = all.filter { ["EP", "Album"].contains($0.musicCategory) }
        let shows = upcomingShows(details)

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

        if !songs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Songs").font(.title3.bold())
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
