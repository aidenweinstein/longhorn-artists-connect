//
//  RoleCallNotifier.swift
//  Longhorn Artists Connect
//
//  "Casting call" / "crew call" notifications matched to the user's role tags. When a
//  project post lists open cast roles, everyone tagged Actor hears about it; when it
//  lists an open crew position, everyone whose tag covers that job hears about it — an
//  "Editor" for "Assistant Editor", a "Cinematographer" for "DP", a "Sound Mixer" for
//  "Boom Operator". A role added to a project later (an edit) is announced the same way.
//
//  These are local notifications posted after each feed sync, the same way "a
//  connection posted" works (see `ConnectionsManager.noticeNewPosts`). By then approval,
//  school scope and moderation have already been applied, so nothing here needs a
//  server-side subscription per tag, and a moderator approving a post is what triggers
//  the call rather than the raw submission.
//

import Foundation
import UserNotifications

enum RoleCallNotifier {

    /// Per-environment UserDefaults key for `[postID: [role keys already announced]]`.
    private static var notifiedRolesKey: String {
        "\(CloudKitEnvironmentDetector.localCachePrefix)roleCallNotifiedRoles"
    }

    /// Posts (or edits) older than this never notify, so a device that's been offline
    /// for a while doesn't deliver a stack of stale calls at once.
    private static let freshnessWindow: TimeInterval = 7 * 24 * 60 * 60

    /// Call after each feed sync with the visible approved list. Posts one notification
    /// per project that has an open role matching one of my tags and that hasn't been
    /// announced before. The first call only seeds the known set, so installing the app
    /// (or picking tags for the first time) never replays the whole feed.
    static func noticeOpenRoles(in posts: [Submission]) async {
        let myTags = currentTags()
        guard !myTags.isEmpty else { return }

        let defaults = UserDefaults.standard
        let isFirstRun = defaults.object(forKey: notifiedRolesKey) == nil
        var notified = defaults.dictionary(forKey: notifiedRolesKey) as? [String: [String]] ?? [:]

        let me = Collaborator.nameKey(for: currentUserName())
        let cutoff = Date().addingTimeInterval(-freshnessWindow)
        var calls: [(project: Submission, roles: [OpenRole])] = []

        for project in posts where project.type == .project {
            let id = project.id.uuidString
            let openRoles = openRoles(of: project)
            let already = Set(notified[id] ?? [])

            // Remember every role currently listed, matching or not, so a later tag
            // change never re-announces something that was already on the post.
            notified[id] = Array(Set(openRoles.map(\.key)).union(already))

            guard !isFirstRun else { continue }
            // My own posts, and posts whose last change is old news, never notify.
            guard Collaborator.nameKey(for: project.submittedBy) != me,
                  (project.lastEditedDate ?? project.createdDate) >= cutoff else { continue }

            let matches = openRoles.filter { !already.contains($0.key) && $0.matches(myTags) }
            if !matches.isEmpty {
                calls.append((project, matches))
            }
        }

        // Always write back (even an empty dictionary) so the seed is recorded.
        defaults.set(notified, forKey: notifiedRolesKey)
        guard !calls.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }

        for call in calls {
            do {
                try await center.add(request(for: call.project, roles: call.roles))
            } catch {
                print("⚠️ Couldn't post role call notification: \(error.localizedDescription)")
            }
        }
        print("🔔 Posted \(calls.count) casting/crew call notification(s)")
    }

    /// The open roles on `project` that someone with `tags` would be called for, as
    /// the poster wrote them. Shared with the Now page in Discover so it lists exactly
    /// the crew and cast calls these notifications announce.
    static func matchingOpenRoles(of project: Submission, for tags: Set<UserType>) -> (cast: [String], crew: [String]) {
        let matches = openRoles(of: project).filter { $0.matches(tags) }
        return (cast: matches.filter { $0.isCast }.map { $0.wording },
                crew: matches.filter { !$0.isCast }.map { $0.wording })
    }

    // MARK: - Open roles

    /// One open position on a project, as the poster wrote it.
    private struct OpenRole {
        let wording: String
        let isCast: Bool

        /// Stable identity for the "already announced" set.
        var key: String { "\(isCast ? "cast" : "crew"):\(RoleCallNotifier.normalize(wording))" }

        /// Whether someone with these tags should hear about this role.
        func matches(_ tags: Set<UserType>) -> Bool {
            if isCast {
                // Any casting call is for actors. Cast lines that name another
                // performing tag ("Dancer", "Singer") reach those people too.
                if tags.contains(.actor) { return true }
                return RoleCallNotifier.wordMatchedTags(in: wording).intersection(tags).isEmpty == false
            }
            // Crew: let the role guide resolve the poster's wording ("DP", "1st AC",
            // "Assistant Editor") to a known position, then map that position to tags.
            // Only when the guide doesn't recognise the role at all do we fall back to a
            // plain word match, so "Art Director" never pings every Director.
            if let known = CrewRoleGuide.description(for: wording) {
                return RoleCallNotifier.tagsByGuideTitle[known.title]?.intersection(tags).isEmpty == false
            }
            return RoleCallNotifier.wordMatchedTags(in: wording).intersection(tags).isEmpty == false
        }
    }

    private static func openRoles(of project: Submission) -> [OpenRole] {
        let cast = project.castNeeded
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { OpenRole(wording: $0, isCast: true) }
        let crew = project.crewNeeded
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { OpenRole(wording: $0, isCast: false) }
        return cast + crew
    }

    // MARK: - Tag matching

    /// Which tags each crew position in `CrewRoleGuide` is for. Keyed by the guide's
    /// own titles; built by resolving plain names through the guide so this table
    /// never has to spell a title exactly the way the guide does.
    private static let tagsByGuideTitle: [String: Set<UserType>] = {
        let wanted: [UserType: [String]] = [
            .director: ["director"],
            .producer: ["producer", "line producer"],
            .writer: ["writer"],
            .editor: ["editor"],
            .cinematographer: ["director of photography", "camera operator",
                               "1st assistant camera", "2nd assistant camera"],
            .photographer: ["still photographer"],
            .composer: ["composer"],
            .soundMixer: ["on-set mixer", "boom operator", "sound mixer", "sound effects designer"],
            .vfxArtist: ["vfx artist"],
            .animator: ["storyboard artist"],
            .painter: ["storyboard artist"]
        ]
        var table: [String: Set<UserType>] = [:]
        for (tag, names) in wanted {
            for name in names {
                guard let title = CrewRoleGuide.description(for: name)?.title else { continue }
                table[title, default: []].insert(tag)
            }
        }
        return table
    }()

    /// Tags whose name appears as a whole word (singular or plural) in `wording`,
    /// e.g. "Lead Animator" → Animator, "Dancers" → Dancer. Enthusiast is never a job.
    private static func wordMatchedTags(in wording: String) -> Set<UserType> {
        let padded = " \(normalize(wording)) "
        var found: Set<UserType> = []
        for tag in UserType.allCases where tag != .enthusiast {
            let name = normalize(tag.rawValue)
            if padded.contains(" \(name) ") || padded.contains(" \(name)s ") {
                found.insert(tag)
            }
        }
        return found
    }

    /// Lowercased, punctuation stripped, single spaces.
    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
    }

    // MARK: - Current user

    /// The tags picked in onboarding / Edit Profile, stored comma-separated.
    private static func currentTags() -> Set<UserType> {
        let stored = UserDefaults.standard.string(forKey: "userType") ?? ""
        return Set(stored.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { UserType(rawValue: $0) })
    }

    private static func currentUserName() -> String {
        let first = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let last = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        return "\(first) \(last)".trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Notification

    private static func request(for project: Submission, roles: [OpenRole]) -> UNNotificationRequest {
        let hasCast = roles.contains { $0.isCast }
        let hasCrew = roles.contains { !$0.isCast }
        let kind = hasCast && hasCrew ? "Cast & Crew Call" : hasCast ? "Casting Call" : "Crew Call"
        let projectTitle = project.title.trimmingCharacters(in: .whitespaces)

        let content = UNMutableNotificationContent()
        content.title = projectTitle.isEmpty ? kind : "\(kind): \(projectTitle)"
        var body = "Looking for \(roles.map(\.wording).formatted(.list(type: .and)))"
        let poster = project.submittedBy.trimmingCharacters(in: .whitespaces)
        if !poster.isEmpty { body += " — posted by \(poster)" }
        content.body = body
        content.sound = .default
        content.threadIdentifier = "role-calls"
        content.userInfo = ["postID": project.id.uuidString, "roleCall": true]

        // Unique per delivery so a later edit that adds another matching role can
        // notify again rather than replacing a banner the user may not have seen.
        return UNNotificationRequest(
            identifier: "role-call-\(project.id.uuidString)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
    }
}
