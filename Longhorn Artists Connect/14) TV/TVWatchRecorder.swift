//
//  TVWatchRecorder.swift
//  Longhorn Artists Connect
//
//  The Apple TV half of `PostAnalytics`. The verification service writes the
//  `NewPostView` record (a TV may not be signed in to iCloud, and an email
//  sign-in isn't an iCloud account at all), under the same deterministic name
//  the iPhone app uses, so one person counts once per post per day across
//  every device they watch on.
//

import Foundation

final class TVWatchRecorder {
    static let shared = TVWatchRecorder()
    private init() {}

    /// UserDefaults keys for the engagements already sent today, so repeat plays
    /// don't cost a request. The service de-duplicates on its own as well.
    private static let sentKey = "tvPostAnalyticsSentToday"
    private static let sentDayKey = "tvPostAnalyticsSentDay"

    /// UTC day stamp ("yyyyMMdd"), the same one `PostAnalytics` uses.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    private struct Recorded: Decodable {
        let recorded: Bool
    }

    func record(_ kind: PostEngagementKind, for video: TVVideo, by viewer: TVViewer) {
        // A creator watching their own post doesn't count.
        guard viewer.name.isEmpty || viewer.name != video.creator else { return }
        guard let token = TVSessionStore.token else { return }

        let day = Self.dayFormatter.string(from: Date())
        let defaults = UserDefaults.standard
        var sent = defaults.string(forKey: Self.sentDayKey) == day
            ? Set(defaults.stringArray(forKey: Self.sentKey) ?? [])
            : []
        let key = "\(kind.rawValue)_\(video.id.uuidString)"
        guard !sent.contains(key) else { return }
        sent.insert(key)
        defaults.set(Array(sent), forKey: Self.sentKey)
        defaults.set(day, forKey: Self.sentDayKey)

        Task {
            do {
                let _: Recorded = try await TVService.post(
                    "v1/tv/view",
                    ["token": token, "postID": video.id.uuidString, "kind": kind.rawValue]
                )
            } catch {
                print("📊 Couldn't record \(kind.rawValue) for \(video.title): \(error.localizedDescription)")
            }
        }
    }
}
