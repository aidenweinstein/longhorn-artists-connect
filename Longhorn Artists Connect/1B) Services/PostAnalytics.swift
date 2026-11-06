//
//  PostAnalytics.swift
//  Longhorn Artists Connect
//

import Foundation

/// The engagements recorded against a post. Raw values are what's stored in
/// `NewPostView.eventKind` and in the record name, so never rename them.
enum PostEngagementKind: String, CaseIterable {
    /// The post's detail page appeared.
    case open
    /// Video or audio actually played (a couple of seconds, not just loaded).
    case play
    /// Watched/listened for 30 seconds or half the length, whichever comes first.
    case engaged
    /// Tapped through to someone credited on the post.
    case profileVisit
    /// Started sending the post in a message.
    case message

    /// Short column label for the moderator analytics page.
    var label: String {
        switch self {
        case .open:         return "Opens"
        case .play:         return "Plays"
        case .engaged:      return "Engaged"
        case .profileVisit: return "Profiles"
        case .message:      return "Messages"
        }
    }

    var icon: String {
        switch self {
        case .open:         return "eye"
        case .play:         return "play.fill"
        case .engaged:      return "hourglass"
        case .profileVisit: return "person.crop.circle"
        case .message:      return "paperplane"
        }
    }
}

/// Records post engagement to CloudKit (`NewPostView`) for the moderator-only analytics
/// page. Nothing here is ever shown to artists.
///
/// Each kind counts at most once per user, per post, per day. That's enforced twice:
/// locally (so repeat opens don't cost a network round trip) and by the deterministic
/// record name server-side (so a second device can't double-count either).
///
/// Not counted: the post's own creator looking at their post, and anyone browsing
/// with moderator mode on (reviewing posts would otherwise inflate every number).
@MainActor
final class PostAnalytics {
    static let shared = PostAnalytics()
    private init() {}

    /// UserDefaults key for the engagements already sent today.
    private static let sentKey = "postAnalyticsSentToday"
    /// UserDefaults key for the UTC day `sentKey` belongs to.
    private static let sentDayKey = "postAnalyticsSentDay"

    /// UTC day stamp ("yyyyMMdd") — UTC so every device agrees on where a day ends.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    func record(_ kind: PostEngagementKind, for post: Submission) {
        guard shouldCount(post) else { return }

        let day = Self.dayFormatter.string(from: Date())
        let defaults = UserDefaults.standard
        var sent = defaults.string(forKey: Self.sentDayKey) == day
            ? Set(defaults.stringArray(forKey: Self.sentKey) ?? [])
            : []
        let key = "\(kind.rawValue)_\(post.id.uuidString)"
        guard !sent.contains(key) else { return }

        // Marked sent before the save, win or lose: a failure (offline, or `NewPostView`
        // not yet in the schema) shouldn't turn every re-open into another request.
        sent.insert(key)
        defaults.set(Array(sent), forKey: Self.sentKey)
        defaults.set(day, forKey: Self.sentDayKey)

        Task {
            do {
                try await CloudKitManager.shared.recordPostView(kind: kind.rawValue, postID: post.id, day: day)
            } catch {
                print("📊 Couldn't record \(kind.rawValue) for \(post.title): \(error.localizedDescription)")
            }
        }
    }

    private func shouldCount(_ post: Submission) -> Bool {
        if UserDefaults.standard.bool(forKey: "isModeratorMode") && ModeratorAccess.isModerator {
            return false
        }
        let first = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let last = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return currentUser.isEmpty || currentUser != post.submittedBy
    }
}

/// Turns a player's periodic time updates into `play` / `engaged` events. Only
/// counts time that actually played — a jump of more than a couple of seconds is a
/// seek, so scrubbing to the end doesn't register as a full listen.
struct PlaybackEngagementTracker {
    private var playedSeconds: Double = 0
    private var lastTime: Double?
    private var sentPlay = false
    private var sentEngaged = false

    /// Seconds of playback that count as a real play rather than a bounce.
    private static let playThreshold: Double = 2
    /// Engaged after this long, or half the length for anything shorter than a minute.
    private static let engagedThreshold: Double = 30

    /// Feed every time-observer tick; returns the events newly crossed on this tick.
    mutating func update(time: Double, duration: Double) -> [PostEngagementKind] {
        guard time.isFinite, time >= 0 else { return [] }
        defer { lastTime = time }
        guard let last = lastTime else { return [] }
        let delta = time - last
        guard delta > 0, delta <= 2 else { return [] }
        playedSeconds += delta

        var crossed: [PostEngagementKind] = []
        if !sentPlay, playedSeconds >= Self.playThreshold {
            sentPlay = true
            crossed.append(.play)
        }
        let engagedAt = duration > 0 && duration.isFinite
            ? min(Self.engagedThreshold, duration / 2)
            : Self.engagedThreshold
        if !sentEngaged, playedSeconds >= max(engagedAt, Self.playThreshold) {
            sentEngaged = true
            crossed.append(.engaged)
        }
        return crossed
    }
}
