//
//  CollaborationStats.swift
//  Longhorn Artists Connect
//
//  "Experience" earned by being on set: how many distinct people worked on each
//  post, and — per person — how many collaborations they've racked up across every
//  post they're credited on (films, reels, music, photography, design, projects and
//  events alike) plus how many distinct people that was with. Shown on portfolios;
//  tapping the Collaborators tile lists everyone they've worked with and tapping Collabs
//  lists every post they shared credits on. (Connections — the private, mutual
//  request-based relationship — live in `ConnectionsManager` and are never a number.)
//

import SwiftUI

// MARK: - Credited People on a Post

/// One distinct person credited on a post, however many roles they held on it.
struct Collaborator: Hashable {
    /// Display name, trimmed.
    let name: String
    /// Linked directory profile ID with any `UserProfile_` prefix removed. Nil for a
    /// free-typed credit that was never linked to a profile.
    let profileID: String?

    /// Lowercased, trimmed name used to match free-typed credits to each other.
    var nameKey: String { Collaborator.nameKey(for: name) }

    /// Decides whether two credits are the same person: the linked profile when there
    /// is one, otherwise the case-insensitive name. Two people who share a name but
    /// were both picked from the directory stay distinct.
    var identityKey: String {
        if let profileID, !profileID.isEmpty { return "id:\(profileID)" }
        return "name:\(nameKey)"
    }

    static func nameKey(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Strips the `UserProfile_` record-name prefix so IDs stored in either form
    /// (raw record name vs. profile record name) compare equal.
    static func normalizedProfileID(_ id: String?) -> String? {
        guard let id = id?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { return nil }
        let prefix = "UserProfile_"
        return id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id
    }
}

extension Submission {
    /// Every credit on this post that names a person: cast, crew, music recording and
    /// production credits, plus a photography post's photographer (which lives in
    /// `artist`, not the credit lists). Works for every post type — projects store
    /// their assembled cast/crew in the same lists, and events contribute whatever
    /// credits were attached to them.
    var creditEntries: [OrderedEntry] {
        var entries = orderedCast + orderedCrew + orderedRecording + orderedProduction
        if type == .photography {
            let photographer = artist.trimmingCharacters(in: .whitespaces)
            if !photographer.isEmpty {
                entries.append(OrderedEntry(role: "Photographer", name: photographer))
            }
        }
        return entries
    }

    /// The distinct people who worked on this post. Someone credited several times
    /// (e.g. Director and Editor) appears once. A free-typed credit is merged with a
    /// directory-linked one when the names match on the same post.
    var creditedPeople: [Collaborator] {
        CollaborationStats.distinctPeople(in: creditEntries, resolvingNamesWith: [:])
    }

    /// How many distinct people worked on this post.
    var creditedPeopleCount: Int { creditedPeople.count }
}

// MARK: - Per-Person Totals

/// One person someone has worked with, with how often — a row in the collaborators list.
struct CollaboratorSummary: Identifiable, Equatable {
    /// Stable identity (`Collaborator.identityKey`).
    let id: String
    /// Best-known display name (a directory-linked credit's name wins over a typed one).
    var name: String
    /// Linked directory profile ID (prefix-stripped), when any credit was linked.
    var profileID: String?
    /// How many posts the two of them share credits on.
    var sharedPostCount: Int
    /// Titles of those shared posts, newest first.
    var sharedPostTitles: [String]
    /// Their Nexus directory entry, or nil when the credit names someone who isn't on
    /// the app. Only people with an entry count toward the portfolio's numbers.
    var directoryUser: DirectoryUser? = nil

    var isOnNexus: Bool { directoryUser != nil }
}

/// One post a person shares credits on, with everyone else credited there — a row in
/// the Collaborations list. `members.count` is this post's share of `totalCollaborations`.
struct CollaborationEntry: Identifiable, Equatable {
    /// The post itself, so the row can show its thumbnail and open its detail page.
    let submission: Submission
    /// The other people credited on it who are on Nexus — the ones that count.
    let members: [CollaboratorSummary]
    /// Other credited names that aren't on Nexus — listed, but not counted.
    let nonMembers: [Collaborator]

    var id: UUID { submission.id }
}

/// Collaboration totals for one person across the posts they're credited on. Only
/// people registered on Nexus (found in the directory) are counted; names typed into
/// credits that don't match a member still appear in the lists under "Not Registered
/// on Nexus" but don't move the numbers.
struct CollaborationStats: Equatable {
    /// Across every post the person is credited on, the sum of how many *other* Nexus
    /// members were credited there. Working with the same person on three posts
    /// counts three.
    var totalCollaborations: Int = 0
    /// Distinct other Nexus members the person has been credited alongside, each
    /// counted once no matter how many posts they shared.
    var uniqueCollaborators: Int = 0
    /// Everyone the person has shared credits with — on Nexus or not — most-worked-with
    /// first, then by name. Filter with `isOnNexus` for the people behind
    /// `uniqueCollaborators`.
    var collaborators: [CollaboratorSummary] = []
    /// Every post the person shares credits on with at least one other person, newest
    /// first. Entries whose `members` is empty contribute nothing to the totals.
    var collaborations: [CollaborationEntry] = []

    /// Collapses credit entries to distinct people. `nameMap` maps a lowercased name to
    /// a known profile ID (see `nameMap(from:)`) so a free-typed credit merges with a
    /// linked credit for the same person; this post's own linked credits are learned
    /// first so the merge also works within a single post.
    static func distinctPeople(in entries: [OrderedEntry],
                               resolvingNamesWith nameMap: [String: String]) -> [Collaborator] {
        var map = nameMap
        for entry in entries {
            guard let id = Collaborator.normalizedProfileID(entry.profileID) else { continue }
            let key = Collaborator.nameKey(for: entry.name)
            if !key.isEmpty, map[key] == nil { map[key] = id }
        }

        var seen = Set<String>()
        var people: [Collaborator] = []
        for entry in entries {
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = Collaborator.nameKey(for: name)
            let id = Collaborator.normalizedProfileID(entry.profileID) ?? map[key]
            // Skip blank placeholder rows that have neither a name nor a link.
            guard !name.isEmpty || id != nil else { continue }
            let person = Collaborator(name: name, profileID: id)
            if seen.insert(person.identityKey).inserted {
                people.append(person)
            }
        }
        return people
    }

    /// Lowercased name → profile ID, learned from every directory-linked credit in
    /// `submissions`. Lets a person typed by name on one post and picked from the
    /// directory on another be recognised as the same collaborator.
    static func nameMap(from submissions: [Submission]) -> [String: String] {
        var map: [String: String] = [:]
        for submission in submissions {
            for entry in submission.creditEntries {
                guard let id = Collaborator.normalizedProfileID(entry.profileID) else { continue }
                let key = Collaborator.nameKey(for: entry.name)
                if !key.isEmpty, map[key] == nil { map[key] = id }
            }
        }
        return map
    }

    /// Computes the totals for one person across `submissions` — every post type,
    /// including events and projects. Only posts the person is actually credited on
    /// count, and the person is left out of their own totals. Each other credit is
    /// matched against `directory`; only matches count toward the numbers.
    ///
    /// - Parameters:
    ///   - name: The person's full name as it appears in credits.
    ///   - profileID: Their directory profile ID (either record-name form), if known.
    ///   - submissions: The posts to scan, normally the approved feed.
    ///   - directory: Every Nexus member (`UserProfileManager.allUsers`). Pass it from
    ///     an observed manager so the numbers refresh once the directory loads.
    static func compute(forPersonNamed name: String,
                        profileID: String?,
                        in submissions: [Submission],
                        directory: [DirectoryUser]) -> CollaborationStats {
        // Portfolio headers call this straight from their view bodies, which re-run on
        // every store or directory change (even while that tab is off screen). The scan
        // is O(posts × credits), so reuse the last result for this person whenever the
        // credits and directory it depends on haven't changed.
        let key = MemoKey(name: name, profileID: profileID)
        let fingerprint = fingerprint(of: submissions, directory: directory)
        if let cached = memoized(for: key), cached.fingerprint == fingerprint {
            return cached.stats
        }
        let stats = computeUncached(forPersonNamed: name, profileID: profileID,
                                    in: submissions, directory: directory)
        memoize(MemoEntry(fingerprint: fingerprint, stats: stats), for: key)
        return stats
    }

    // MARK: Memo

    // The memo is read and written behind `memoLock`, off any actor, so its pieces are
    // `nonisolated` (the project defaults declarations to the main actor).
    nonisolated private struct MemoKey: Hashable {
        let name: String
        let profileID: String?
    }

    nonisolated private struct MemoEntry {
        let fingerprint: Int
        let stats: CollaborationStats
    }

    nonisolated private static let memoLock = NSLock()
    nonisolated(unsafe) private static var memo: [MemoKey: MemoEntry] = [:]
    /// Most people whose stats are kept at once (the viewer plus a few open profiles).
    nonisolated private static let memoLimit = 8

    nonisolated private static func memoized(for key: MemoKey) -> MemoEntry? {
        memoLock.lock()
        defer { memoLock.unlock() }
        return memo[key]
    }

    nonisolated private static func memoize(_ entry: MemoEntry, for key: MemoKey) {
        memoLock.lock()
        defer { memoLock.unlock() }
        if memo[key] == nil, memo.count >= memoLimit {
            memo.removeAll()
        }
        memo[key] = entry
    }

    /// Hashes exactly the inputs the totals depend on: each post's identity and
    /// credits, and each member's identity, name and school. Deliberately skips bulky
    /// fields like thumbnails, so it costs microseconds rather than a full rescan.
    private static func fingerprint(of submissions: [Submission], directory: [DirectoryUser]) -> Int {
        var hasher = Hasher()
        hasher.combine(submissions.count)
        for submission in submissions {
            hasher.combine(submission.id)
            hasher.combine(submission.type)
            hasher.combine(submission.title)
            hasher.combine(submission.createdDate)
            hasher.combine(submission.artist)
            for entry in submission.creditEntries {
                hasher.combine(entry.role)
                hasher.combine(entry.name)
                hasher.combine(entry.profileID)
            }
        }
        hasher.combine(directory.count)
        for user in directory {
            hasher.combine(user.id)
            hasher.combine(user.firstName)
            hasher.combine(user.lastName)
            hasher.combine(user.school)
        }
        return hasher.finalize()
    }

    private static func computeUncached(forPersonNamed name: String,
                                        profileID: String?,
                                        in submissions: [Submission],
                                        directory: [DirectoryUser]) -> CollaborationStats {
        let selfNameKey = Collaborator.nameKey(for: name)
        let nameMap = nameMap(from: submissions)
        var selfID = Collaborator.normalizedProfileID(profileID)
        if selfID == nil, !selfNameKey.isEmpty { selfID = nameMap[selfNameKey] }

        guard selfID != nil || !selfNameKey.isEmpty else { return CollaborationStats() }

        func isSelf(_ person: Collaborator) -> Bool {
            // When both sides are linked to a profile, trust the IDs — a namesake who
            // was picked from the directory is a different person.
            if let selfID, let personID = person.profileID { return personID == selfID }
            return !selfNameKey.isEmpty && person.nameKey == selfNameKey
        }

        // Directory lookups: by raw record ID (the form credits link with), then by name
        // for free-typed credits whose spelling matches a member exactly.
        var membersByID: [String: DirectoryUser] = [:]
        var membersByName: [String: DirectoryUser] = [:]
        for user in directory {
            membersByID[user.messagingUserID] = user
            let key = Collaborator.nameKey(for: user.fullName)
            if !key.isEmpty, membersByName[key] == nil { membersByName[key] = user }
        }
        func member(for person: Collaborator) -> DirectoryUser? {
            if let id = person.profileID, let user = membersByID[id] { return user }
            return membersByName[person.nameKey]
        }

        var stats = CollaborationStats()
        var summaries: [String: CollaboratorSummary] = [:]
        // Posts paired with the other people on them, so the per-post entries can be
        // built after every summary has its final name and directory match.
        var postOthers: [(submission: Submission, others: [Collaborator])] = []
        // Newest first so each collaborator's shared-post titles read in that order.
        for submission in submissions.sorted(by: { $0.createdDate > $1.createdDate }) {
            let people = distinctPeople(in: submission.creditEntries, resolvingNamesWith: nameMap)
            guard people.contains(where: isSelf) else { continue }
            let others = people.filter { !isSelf($0) }
            guard !others.isEmpty else { continue }
            postOthers.append((submission, others))

            for person in others {
                let key = person.identityKey
                if var existing = summaries[key] {
                    existing.sharedPostCount += 1
                    existing.sharedPostTitles.append(submission.title)
                    // Prefer a non-empty name; a linked credit's spelling wins.
                    if existing.name.isEmpty || (existing.profileID == nil && person.profileID != nil) {
                        existing.name = person.name.isEmpty ? existing.name : person.name
                    }
                    if existing.profileID == nil { existing.profileID = person.profileID }
                    if existing.directoryUser == nil { existing.directoryUser = member(for: person) }
                    summaries[key] = existing
                } else {
                    summaries[key] = CollaboratorSummary(
                        id: key,
                        name: person.name,
                        profileID: person.profileID,
                        sharedPostCount: 1,
                        sharedPostTitles: [submission.title],
                        directoryUser: member(for: person)
                    )
                }
            }
        }

        for (submission, others) in postOthers {
            var members: [CollaboratorSummary] = []
            var nonMembers: [Collaborator] = []
            for person in others {
                if let summary = summaries[person.identityKey], summary.isOnNexus {
                    members.append(summary)
                } else {
                    nonMembers.append(person)
                }
            }
            stats.totalCollaborations += members.count
            stats.collaborations.append(
                CollaborationEntry(submission: submission, members: members, nonMembers: nonMembers)
            )
        }

        stats.collaborators = summaries.values.sorted {
            if $0.sharedPostCount != $1.sharedPostCount { return $0.sharedPostCount > $1.sharedPostCount }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        stats.uniqueCollaborators = stats.collaborators.filter(\.isOnNexus).count
        return stats
    }
}

// MARK: - Portfolio Stats View

/// Instagram-style stats row for a portfolio header, shown beside the profile photo:
/// credits, then unique collaborators ("Collaborators"), then total collaborations
/// ("Collabs") — each a bold number over a small label, in three equal columns.
/// Tapping Collaborators opens the searchable list of people this person has worked
/// with; tapping Collabs opens the searchable list of posts they shared credits on.
/// Shared by the user's own portfolio and every view of someone else's. Every number
/// here is earned from approved posts — connections are deliberately not counted.
struct CollaborationStatsView: View {
    let stats: CollaborationStats
    /// How many posts appear on this person's portfolio.
    let postCount: Int
    /// Whose stats these are, for the list pages' accessibility hints.
    let personName: String

    @State private var showCollaborators = false
    @State private var showCollaborations = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            stat(value: postCount, title: "Credits")

            // Both tappable tiles stay enabled even when empty so their labels keep
            // the same color as Credits (a disabled plain button dims to grey); the
            // page they open simply shows an empty state.
            Button {
                showCollaborators = true
            } label: {
                stat(value: stats.uniqueCollaborators, title: "Collaborators")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows everyone \(personName) has worked with")

            Button {
                showCollaborations = true
            } label: {
                stat(value: stats.totalCollaborations, title: "Collabs")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows every post \(personName) shared credits on")
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showCollaborators) {
            CollaboratorsListView(collaborators: stats.collaborators)
        }
        .sheet(isPresented: $showCollaborations) {
            CollaborationsListView(collaborations: stats.collaborations)
        }
    }

    private func stat(value: Int, title: String) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .number)
                // ====== UI CONTROLS!!!!! ======
                .font(.title3)
                // ==============================
                .bold()
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                // Labels wrap to two lines in a narrow column rather than shrinking
                // to unreadable sizes.
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - School Sections

/// Splits the rows of a Collaborators or Collaborations page into the three sections
/// both pages share: the viewer's own school, other schools, and "Not Registered on
/// Nexus". Guests and industry professionals have no school, so for them everyone on
/// Nexus sits in a single "On Nexus" section instead.
@MainActor
enum CollaborationSchoolSections {
    static let otherSchoolsTitle = "Other Schools"
    static let notRegisteredTitle = "Not Registered on Nexus"

    static var yourSchoolTitle: String {
        SchoolScope.isUnscopedAccount ? "On Nexus" : "Your School"
    }

    /// Groups `items` by the school each resolves to. `school` returns the school's
    /// display name, or nil when the item isn't on Nexus. Empty sections are dropped.
    static func group<Item>(_ items: [Item],
                            school: (Item) -> String?) -> [(title: String, rows: [Item])] {
        // Read once; `visibleSchoolIDs` costs several UserDefaults reads.
        let visibleIDs = SchoolScope.visibleSchoolIDs
        var yours: [Item] = []
        var others: [Item] = []
        var notRegistered: [Item] = []
        for item in items {
            guard let school = school(item) else {
                notRegistered.append(item)
                continue
            }
            if SchoolScope.isVisible(schoolName: school, in: visibleIDs) {
                yours.append(item)
            } else {
                others.append(item)
            }
        }
        return [
            (yourSchoolTitle, yours),
            (otherSchoolsTitle, others),
            (notRegisteredTitle, notRegistered)
        ].filter { !$0.rows.isEmpty }
    }
}

// MARK: - Collaborators List

/// Everyone a person has worked with, most-worked-with first, in three sections: Nexus
/// members from the viewer's school ("Your School"), members from other schools, and
/// credited names that aren't on Nexus. Searchable by name or by the title of a post
/// they shared. Members (and locally-created profiles) tap through to their profile;
/// everyone else is a plain row.
struct CollaboratorsListView: View {
    let collaborators: [CollaboratorSummary]

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profileManager = UserProfileManager.shared
    @State private var selectedPerson: CreditedPerson?
    @State private var searchText = ""

    /// Rows matching the search text (all of them when it's blank). Matches the
    /// display name from the directory as well as the name typed in the credits.
    private var filteredCollaborators: [CollaboratorSummary] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return collaborators }
        return collaborators.filter { collaborator in
            let names = [collaborator.name, directoryUser(for: collaborator)?.fullName ?? ""]
            return names.contains { $0.localizedCaseInsensitiveContains(query) }
                || collaborator.sharedPostTitles.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    /// The filtered rows split into their sections, in display order, with empty
    /// sections dropped.
    private var sections: [(title: String, rows: [CollaboratorSummary])] {
        CollaborationSchoolSections.group(
            filteredCollaborators,
            school: { directoryUser(for: $0)?.school }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if collaborators.isEmpty {
                    Text("No collaborators yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredCollaborators.isEmpty {
                    Text("No collaborators match “\(searchText)”.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(sections, id: \.title) { section in
                            Section(section.title) {
                                ForEach(section.rows) { collaborator in
                                    row(for: collaborator)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .searchable(text: $searchText, prompt: "Search collaborators")
            .navigationTitle("Collaborators")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .tint(.secondary)
                    .accessibilityLabel("Close")
                }
            }
            .task {
                // Make sure the directory is loaded so avatars resolve and member rows
                // become tappable (throttled internally if already fresh).
                await profileManager.fetchAllUsers()
            }
        }
        .sheet(item: $selectedPerson) { person in
            PersonProfileView(name: person.name)
        }
        .presentationDragIndicator(.hidden)
    }

    @ViewBuilder
    private func row(for collaborator: CollaboratorSummary) -> some View {
        let user = directoryUser(for: collaborator)
        let displayName = user?.fullName ?? collaborator.name
        let isMember = user != nil || isCreatedProfile(named: displayName)

        if isMember {
            Button {
                selectedPerson = CreditedPerson(name: displayName)
            } label: {
                rowContent(collaborator, user: user, displayName: displayName, isMember: true)
            }
            .buttonStyle(.plain)
        } else {
            rowContent(collaborator, user: user, displayName: displayName, isMember: false)
        }
    }

    private func rowContent(_ collaborator: CollaboratorSummary,
                            user: DirectoryUser?,
                            displayName: String,
                            isMember: Bool) -> some View {
        HStack(spacing: 12) {
            avatar(for: user, name: displayName)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName.isEmpty ? "Unknown" : displayName)
                    .font(.headline)
                    .foregroundStyle(isMember ? .primary : .secondary)
                Text(subtitle(for: collaborator))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if isMember {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    /// "3 posts together · Film A, Film B" — the count plus up to two shared titles.
    private func subtitle(for collaborator: CollaboratorSummary) -> String {
        let count = collaborator.sharedPostCount
        var text = count == 1 ? "1 post together" : "\(count) posts together"
        let titles = collaborator.sharedPostTitles.filter { !$0.isEmpty }
        if !titles.isEmpty {
            let shown = titles.prefix(2).joined(separator: ", ")
            text += " · \(shown)"
            if titles.count > 2 { text += " +\(titles.count - 2)" }
        }
        return text
    }

    @ViewBuilder
    private func avatar(for user: DirectoryUser?, name: String) -> some View {
        Group {
            if let data = user?.profileImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color.secondary.opacity(0.15))
                    Text(initials(for: name))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        // ====== UI CONTROLS!!!!! ======
        .frame(width: 44, height: 44)
        // ==============================
        .clipShape(Circle())
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? (parts.last?.first.map(String.init) ?? "") : ""
        let result = (first + last).uppercased()
        return result.isEmpty ? "?" : result
    }

    /// The directory entry for a collaborator: the match made when the stats were
    /// computed, else (if the directory loaded since) by linked profile ID, then name.
    private func directoryUser(for collaborator: CollaboratorSummary) -> DirectoryUser? {
        if let user = collaborator.directoryUser { return user }
        if let id = collaborator.profileID,
           let user = profileManager.allUsers.first(where: { $0.messagingUserID == id || $0.id == id }) {
            return user
        }
        let key = Collaborator.nameKey(for: collaborator.name)
        guard !key.isEmpty else { return nil }
        return profileManager.allUsers.first { Collaborator.nameKey(for: $0.fullName) == key }
    }

    private func isCreatedProfile(named name: String) -> Bool {
        let created = UserDefaults.standard.stringArray(forKey: "createdUserProfiles") ?? []
        return created.contains(name)
    }
}

// MARK: - Collaborations List

/// Every post a person shared credits on, newest first, with who else was on it. Posts
/// are sectioned by the school they belong to ("Your School" / "Other Schools"); posts
/// whose only other credits are names not on Nexus — which count for nothing — sit
/// under "Not Registered on Nexus". Searchable by post title, post type, or a
/// collaborator's name. Tapping a row opens the post's own detail page.
struct CollaborationsListView: View {
    let collaborations: [CollaborationEntry]

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedEntry: CollaborationEntry?
    /// Placeholder for the detail views' like binding; the heart isn't shown from here.
    @State private var liked = false

    /// Rows matching the search text (all of them when it's blank).
    private var filteredCollaborations: [CollaborationEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return collaborations }
        return collaborations.filter { entry in
            entry.submission.title.localizedCaseInsensitiveContains(query)
                || entry.submission.type.displayName.localizedCaseInsensitiveContains(query)
                || entry.members.contains { ($0.directoryUser?.fullName ?? $0.name).localizedCaseInsensitiveContains(query) }
                || entry.nonMembers.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    /// The filtered rows split into their sections, in display order, with empty
    /// sections dropped. A post is placed by its own `schoolID`; one with no Nexus
    /// members among its other credits goes to "Not Registered on Nexus".
    private var sections: [(title: String, rows: [CollaborationEntry])] {
        CollaborationSchoolSections.group(filteredCollaborations) { entry in
            guard !entry.members.isEmpty else { return nil }
            return CollaborationsListView.schoolName(forPostSchoolID: entry.submission.schoolID)
        }
    }

    /// The display name for a post's registry slug (unstamped posts are UT Austin),
    /// so posts and people can be sectioned by the same school check.
    private static func schoolName(forPostSchoolID schoolID: String?) -> String {
        let slug = schoolID.flatMap { $0.isEmpty ? nil : $0 } ?? SchoolScope.legacyDefault
        return SchoolScope.registeredSchools.first { $0.slug == slug }?.name ?? slug
    }

    var body: some View {
        NavigationStack {
            Group {
                if collaborations.isEmpty {
                    Text("No collaborations yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredCollaborations.isEmpty {
                    Text("No collaborations match “\(searchText)”.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(sections, id: \.title) { section in
                            Section(section.title) {
                                ForEach(section.rows) { entry in
                                    Button {
                                        selectedEntry = entry
                                    } label: {
                                        row(for: entry)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .searchable(text: $searchText, prompt: "Search collaborations")
            .navigationTitle("Collaborations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .tint(.secondary)
                    .accessibilityLabel("Close")
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            detail(for: entry.submission)
        }
        .presentationDragIndicator(.hidden)
    }

    private func row(for entry: CollaborationEntry) -> some View {
        HStack(spacing: 12) {
            thumbnail(for: entry.submission)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.submission.title.isEmpty ? "Untitled" : entry.submission.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle(for: entry))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            // This post's share of the Collabs total; hidden when nobody on it counts.
            if !entry.members.isEmpty {
                Text(entry.members.count, format: .number)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    /// "Film · Oct 2026 · with Sam Carter, Priya Patel · +1 not on Nexus" — type,
    /// month, the Nexus members on it, and how many credited names aren't members.
    /// A post with no members lists the non-member names instead.
    private func subtitle(for entry: CollaborationEntry) -> String {
        var parts = [
            entry.submission.type.displayName,
            entry.submission.createdDate.formatted(.dateTime.month(.abbreviated).year())
        ]
        let memberNames = entry.members.map { $0.directoryUser?.fullName ?? $0.name }.filter { !$0.isEmpty }
        let nonMemberNames = entry.nonMembers.map(\.name).filter { !$0.isEmpty }
        if !memberNames.isEmpty {
            parts.append("with " + memberNames.joined(separator: ", "))
            if !nonMemberNames.isEmpty {
                parts.append("+\(nonMemberNames.count) not on Nexus")
            }
        } else if !nonMemberNames.isEmpty {
            parts.append("with " + nonMemberNames.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func thumbnail(for submission: Submission) -> some View {
        Group {
            if let data = submission.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        // ====== UI CONTROLS!!!!! ======
        .frame(width: 44, height: 44)
        // ==============================
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// The same detail page each post type opens from the feed or Discover.
    @ViewBuilder
    private func detail(for submission: Submission) -> some View {
        switch submission.type {
        case .project:
            UpcomingProjectDetailView(submission: submission)
        case .event:
            EventDetailView(event: submission)
        default:
            PostDetailRouter(post: submission, liked: $liked)
        }
    }
}

#Preview("Collaboration Stats") {
    let stats = CollaborationStats(
        totalCollaborations: 42,
        uniqueCollaborators: 3,
        collaborators: [
            CollaboratorSummary(id: "name:sam carter", name: "Sam Carter", profileID: nil,
                                sharedPostCount: 3, sharedPostTitles: ["Last Call", "Between the Lines", "Neon"]),
            CollaboratorSummary(id: "name:priya patel", name: "Priya Patel", profileID: nil,
                                sharedPostCount: 2, sharedPostTitles: ["Last Call", "The Waiting Room"]),
            CollaboratorSummary(id: "name:jordan lee", name: "Jordan Lee", profileID: nil,
                                sharedPostCount: 1, sharedPostTitles: ["Golden Hour"])
        ]
    )
    return CollaborationStatsView(stats: stats, postCount: 12, personName: "Maya Rodriguez")
        .padding()
}
