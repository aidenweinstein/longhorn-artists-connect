//
//  NowView.swift
//  Longhorn Artists Connect
//
//  Discover's first page ("Now | Projects | Events"): what you're working on now
//  and what you could get on next, shaped by your profile style.
//
//  • Actor — projects you're cast in, the auditions you've logged, and open cast
//    roles that fit your age, gender, look and skills.
//  • Filmmaker — your projects in production, and crews looking for the jobs your
//    role tags cover.
//  • Musician — your upcoming shows, composer openings, and gigs, open mics and jams.
//
//  Also the way into the public Actors / Filmmakers / Musicians pages.
//

import SwiftUI
import UIKit

struct NowView: View {
    @ObservedObject private var store = SubmissionStore_3_2.shared
    @ObservedObject private var creative = CreativeProfileStore.shared
    @ObservedObject private var people = UserProfileManager.shared

    @AppStorage("userFirstName") private var firstName = ""
    @AppStorage("userLastName") private var lastName = ""
    @AppStorage("userType") private var userTypeRaw = ""
    @AppStorage("isIndustryProfessional") private var isIndustryProfessional = false

    @Environment(\.openURL) private var openURL

    @State private var showEditor = false
    @State private var editorStartStyle: ProfileStyle?
    @State private var selectedProject: Submission?
    @State private var selectedEvent: Submission?
    @State private var directoryStyle: ProfileStyle?

    // MARK: - Me

    private var myName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    private var myTags: Set<UserType> {
        Set(userTypeRaw.split(separator: ",").compactMap {
            UserType(rawValue: $0.trimmingCharacters(in: .whitespaces))
        })
    }

    private var isMe: (OrderedEntry) -> Bool {
        PersonMatcher.make(name: myName, profileID: people.getCurrentUser()?.id)
    }

    private func isMine(_ post: Submission) -> Bool {
        let me = Collaborator.nameKey(for: myName)
        return !me.isEmpty && Collaborator.nameKey(for: post.submittedBy) == me
    }

    private var posts: [Submission] { store.visibleApprovedSubmissions }

    /// Projects still recruiting: Cast & Crew Calls (and legacy projects with no type).
    private var openCalls: [Submission] {
        posts.filter { post in
            post.type == .project
                && (post.projectType.isEmpty || post.projectType == "Cast & Crew Call")
                && !isMine(post)
        }
        .sorted { $0.createdDate > $1.createdDate }
    }

    private var upcomingEvents: [Submission] {
        posts.filter(\.isUpcomingEvent)
            .sorted { ($0.eventStartDate ?? .distantFuture) < ($1.eventStartDate ?? .distantFuture) }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                browseRow

                if isIndustryProfessional {
                    Text("Browse approved actors, filmmakers and musicians above.")
                        .foregroundStyle(.secondary)
                } else if let style = creative.myStyle {
                    styleHeader(style)
                    switch style {
                    case .actor: actorSections
                    case .filmmaker: filmmakerSections
                    case .musician: musicianSections
                    }
                } else {
                    StyleChooserCard(suggested: ProfileStyle.suggested(for: myTags)) { style in
                        editorStartStyle = style
                        showEditor = true
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable {
            await store.syncWithCloudKit()
            await creative.refresh(force: true)
        }
        .task {
            await creative.refresh()
            await people.fetchAllUsers()
        }
        .sheet(isPresented: $showEditor) {
            ProfileStyleEditorView(startingStyle: editorStartStyle)
        }
        .sheet(item: $selectedProject) { project in
            UpcomingProjectDetailView(submission: project)
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event)
        }
        .sheet(item: $directoryStyle) { style in
            CreativeDirectoryView(style: style)
        }
    }

    // MARK: - Header

    private var browseRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Browse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(spacing: 8) {
                ForEach(ProfileStyle.allCases) { style in
                    Button {
                        directoryStyle = style
                    } label: {
                        Label(style.plural, systemImage: style.symbol)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.brandOrange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(Color.brandOrange)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func styleHeader(_ style: ProfileStyle) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(style.rawValue) profile", systemImage: style.symbol)
                    .font(.title3.bold())
                if let status = creative.myListingStatus {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Edit") {
                editorStartStyle = nil
                showEditor = true
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - Actor

    private var actor: ActorDetails { creative.myDetails.actor }

    private var bookedProjects: [Submission] {
        posts.filter { $0.type == .project && $0.orderedCast.contains(where: isMe) }
            .sorted { $0.createdDate > $1.createdDate }
    }

    /// Open cast lines that fit this actor, one row per role.
    private var matchingRoles: [(project: Submission, role: String, requirements: CastRoleRequirements)] {
        openCalls.flatMap { project in
            project.castNeeded
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .compactMap { wording -> (project: Submission, role: String, requirements: CastRoleRequirements)? in
                    let requirements = CastRoleRequirements(wording: wording)
                    return requirements.fits(actor) ? (project: project, role: wording, requirements: requirements) : nil
                }
        }
    }

    @ViewBuilder
    private var actorSections: some View {
        if !bookedProjects.isEmpty {
            NowSection(title: "Shooting", count: bookedProjects.count) {
                ForEach(bookedProjects) { project in
                    let character = project.orderedCast.first(where: isMe)?.role ?? ""
                    NowCard(
                        thumbnail: project.thumbnailData,
                        title: project.title,
                        subtitle: character.isEmpty ? "Cast" : "as \(character)",
                        detail: project.shootDates.isEmpty ? nil : "Shoots \(project.shootDates)",
                        chips: []
                    ) { selectedProject = project }
                }
            }
        }

        NowSection(title: "Your auditions", count: creative.auditions.count) {
            if creative.auditions.isEmpty {
                NowEmpty("Roles you audition for below are tracked here.")
            } else {
                ForEach(creative.auditions) { entry in
                    auditionRow(entry)
                }
            }
        }

        NowSection(title: "Roles you could audition for", count: matchingRoles.count) {
            if !actor.hasMatchingBasics {
                Button {
                    editorStartStyle = nil
                    showEditor = true
                } label: {
                    Label("Add your age range and gender so these fit you", systemImage: "slider.horizontal.3")
                        .font(.footnote.weight(.semibold))
                }
            }
            if matchingRoles.isEmpty {
                NowEmpty("No open roles fit your profile right now.")
            } else {
                ForEach(Array(matchingRoles.enumerated()), id: \.offset) { _, match in
                    roleRow(match.project, role: match.role, requirements: match.requirements)
                }
            }
        }
    }

    private func auditionRow(_ entry: AuditionEntry) -> some View {
        let project = posts.first { $0.id == entry.projectID }
        // Being added to the project's cast means they got it.
        let booked = project?.orderedCast.contains(where: isMe) ?? false
        let status: AuditionStatus = booked ? .booked : entry.status
        return NowCard(
            thumbnail: project?.thumbnailData,
            title: entry.projectTitle,
            subtitle: entry.role,
            detail: entry.date.formatted(date: .abbreviated, time: .omitted),
            chips: []
        ) {
            if let project { selectedProject = project }
        } trailing: {
            Menu {
                ForEach(AuditionStatus.allCases) { option in
                    Button(option.rawValue) { creative.setStatus(option, for: entry) }
                }
                Divider()
                Button("Remove", role: .destructive) { creative.removeAudition(entry) }
            } label: {
                StatusPill(text: status.rawValue, emphasized: status == .booked || status == .callback)
            }
        }
    }

    private func roleRow(_ project: Submission, role: String, requirements: CastRoleRequirements) -> some View {
        let done = creative.hasAuditioned(projectID: project.id, role: role)
        return NowCard(
            thumbnail: project.thumbnailData,
            title: role,
            subtitle: project.title,
            detail: project.shootDates.isEmpty ? nil : "Shoots \(project.shootDates)",
            chips: requirements.summary
        ) {
            selectedProject = project
        } trailing: {
            Button {
                creative.recordAudition(project: project, role: role)
                if let link = project.projectAuditionURL, let url = URL(string: link), url.scheme != nil {
                    openURL(url)
                } else {
                    selectedProject = project
                }
            } label: {
                Text(done ? "Auditioned" : "Audition")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(done ? Color.secondary.opacity(0.15) : Color.brandOrange, in: Capsule())
                    .foregroundStyle(done ? Color.secondary : Color.white)
            }
            .buttonStyle(.plain)
            .disabled(done)
        }
    }

    // MARK: - Filmmaker

    private var myProductions: [Submission] {
        posts.filter { post in
            post.type == .project
                && (isMine(post) || post.orderedCrew.contains(where: isMe) || post.orderedCast.contains(where: isMe))
        }
        .sorted { $0.createdDate > $1.createdDate }
    }

    private var crewOpenings: [(project: Submission, roles: [String])] {
        openCalls.compactMap { project -> (project: Submission, roles: [String])? in
            let roles: [String]
            if myTags.isEmpty {
                roles = project.crewNeeded.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } else {
                roles = RoleCallNotifier.matchingOpenRoles(of: project, for: myTags).crew
            }
            return roles.isEmpty ? nil : (project: project, roles: roles)
        }
    }

    @ViewBuilder
    private var filmmakerSections: some View {
        NowSection(title: "In production", count: myProductions.count) {
            if myProductions.isEmpty {
                NowEmpty("Projects you post or are credited on show up here.")
            } else {
                ForEach(myProductions) { project in
                    let roles = project.credits(where: isMe).map(\.role).filter { !$0.isEmpty }
                    NowCard(
                        thumbnail: project.thumbnailData,
                        title: project.title,
                        subtitle: roles.isEmpty ? (isMine(project) ? "Your project" : "Credited") : roles.joined(separator: ", "),
                        detail: project.shootDates.isEmpty ? nil : "Shoots \(project.shootDates)",
                        chips: []
                    ) {
                        selectedProject = project
                    } trailing: {
                        StatusPill(text: Self.stage(of: project), emphasized: true)
                    }
                }
            }
        }

        NowSection(title: "Crews you could join", count: crewOpenings.count) {
            if myTags.isEmpty {
                NowEmpty("Add role tags to your profile to see only the jobs you do.")
            }
            if crewOpenings.isEmpty {
                NowEmpty("No crews are looking for your roles right now.")
            } else {
                ForEach(Array(crewOpenings.enumerated()), id: \.offset) { _, opening in
                    NowCard(
                        thumbnail: opening.project.thumbnailData,
                        title: opening.project.title,
                        subtitle: "Posted by \(opening.project.submittedBy)",
                        detail: opening.project.shootDates.isEmpty ? nil : "Shoots \(opening.project.shootDates)",
                        chips: opening.roles
                    ) { selectedProject = opening.project }
                }
            }
        }
    }

    /// A project's stage, from its project type.
    static func stage(of project: Submission) -> String {
        switch project.projectType {
        case "In-Development": return "In development"
        case "In-Post-Production": return "Post-production"
        case "Script": return "Script"
        default: return "Crewing up"
        }
    }

    // MARK: - Musician

    private var myShows: [Submission] {
        let me = Collaborator.nameKey(for: myName)
        let artist = Collaborator.nameKey(for: creative.myDetails.musician.artistName)
        return upcomingEvents.filter { event in
            if isMine(event) || !event.credits(where: isMe).isEmpty { return true }
            let lineup = (event.eventLineup ?? "").lowercased()
            return (!me.isEmpty && lineup.contains(me)) || (!artist.isEmpty && lineup.contains(artist))
        }
    }

    private var composerOpenings: [(project: Submission, roles: [String])] {
        openCalls.compactMap { project -> (project: Submission, roles: [String])? in
            let roles = (project.crewNeeded + project.castNeeded)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { Self.isMusicRole($0) }
            return roles.isEmpty ? nil : (project: project, roles: roles)
        }
    }

    private var gigs: [Submission] {
        let mine = Set(myShows.map(\.id))
        return upcomingEvents.filter { event in
            guard !mine.contains(event.id) else { return false }
            if event.eventCategoryName == "Concert" || event.eventCategoryName == "Artist Mixer" { return true }
            let text = "\(event.title) \(event.details)".lowercased()
            return text.range(of: Self.gigPattern, options: .regularExpression) != nil
        }
    }

    @ViewBuilder
    private var musicianSections: some View {
        NowSection(title: "Your upcoming shows", count: myShows.count) {
            if myShows.isEmpty {
                NowEmpty("Events you post, are credited on, or are in the lineup for show up here and on your profile.")
            } else {
                ForEach(myShows) { event in eventRow(event) }
            }
        }

        NowSection(title: "Composer openings", count: composerOpenings.count) {
            if composerOpenings.isEmpty {
                NowEmpty("No projects are looking for a composer right now.")
            } else {
                ForEach(Array(composerOpenings.enumerated()), id: \.offset) { _, opening in
                    NowCard(
                        thumbnail: opening.project.thumbnailData,
                        title: opening.project.title,
                        subtitle: "Posted by \(opening.project.submittedBy)",
                        detail: opening.project.expectedReleaseDate.isEmpty ? nil : "Release \(opening.project.expectedReleaseDate)",
                        chips: opening.roles
                    ) { selectedProject = opening.project }
                }
            }
        }

        NowSection(title: "Gigs, open mics & jams", count: gigs.count) {
            if gigs.isEmpty {
                NowEmpty("No upcoming gigs, open mics or jam sessions yet.")
            } else {
                ForEach(gigs) { event in eventRow(event) }
            }
        }
    }

    private func eventRow(_ event: Submission) -> some View {
        NowCard(
            thumbnail: event.thumbnailData,
            title: event.title,
            subtitle: [event.eventCategoryName, event.eventLocation ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
            detail: event.eventStartDate?.formatted(date: .abbreviated, time: .shortened),
            chips: []
        ) { selectedEvent = event }
    }

    static func isMusicRole(_ wording: String) -> Bool {
        wording.lowercased().range(of: "compos|\\bscor(e|ing)\\b|\\bmusic|songwrit|sound design|\\bsinger|\\bband\\b|\\bvocalist", options: .regularExpression) != nil
    }

    static let gigPattern = "open mic|\\bjam\\b|jam session|\\bgig\\b|\\bgigs\\b|\\bband\\b|busk|karaoke|battle of the bands|musicians? wanted|songwriter|live music|recital"
}

// MARK: - Building Blocks

/// A titled group of rows on Now.
struct NowSection<Content: View>: View {
    let title: String
    var count: Int? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.title3.bold())
                if let count, count > 0 {
                    Text("\(count)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            content
        }
    }
}

/// One project, role, audition or event on Now.
struct NowCard<Trailing: View>: View {
    let thumbnail: Data?
    let title: String
    let subtitle: String
    let detail: String?
    let chips: [String]
    let action: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: action) {
                HStack(alignment: .top, spacing: 12) {
                    NowThumbnail(data: thumbnail)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if let detail, !detail.isEmpty {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !chips.isEmpty {
                            ChipRow(chips: chips)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            trailing
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension NowCard where Trailing == EmptyView {
    init(thumbnail: Data?, title: String, subtitle: String, detail: String?, chips: [String],
         action: @escaping () -> Void) {
        self.init(thumbnail: thumbnail, title: title, subtitle: subtitle, detail: detail,
                  chips: chips, action: action) { EmptyView() }
    }
}

struct NowThumbnail: View {
    let data: Data?
    var width: CGFloat = 52
    var height: CGFloat = 68

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct NowEmpty: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

struct StatusPill: View {
    let text: String
    var emphasized: Bool = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(emphasized ? Color.brandOrange.opacity(0.18) : Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(emphasized ? Color.brandOrange : Color.primary)
    }
}

/// Small wrapping chips (role names, requirements).
struct ChipRow: View {
    let chips: [String]

    var body: some View {
        ProfileStyleFlowLayout(spacing: 4) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                Text(chip)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.brandOrange.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.brandOrange)
            }
        }
    }
}

/// Left-aligned wrapping layout for chips.
struct ProfileStyleFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Shown on Now (and your own portfolio) until a style is picked.
struct StyleChooserCard: View {
    var suggested: ProfileStyle?
    let onPick: (ProfileStyle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose your profile style")
                .font(.title3.bold())
            Text("It decides what Nexus recommends to you and how your profile looks to everyone else.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(ProfileStyle.allCases) { style in
                Button {
                    onPick(style)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: style.symbol)
                            .font(.title2)
                            .frame(width: 32)
                            .foregroundStyle(Color.brandOrange)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(style.rawValue).font(.headline)
                                if style == suggested {
                                    Text("Suggested")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.brandOrange.opacity(0.18), in: Capsule())
                                        .foregroundStyle(Color.brandOrange)
                                }
                            }
                            Text(style.pitch)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
