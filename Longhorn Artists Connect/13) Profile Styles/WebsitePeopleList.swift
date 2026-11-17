//
//  WebsitePeopleList.swift
//  Longhorn Artists Connect
//
//  Who the Nexus website features on its Actors / Filmmakers / Musicians pages, so
//  the directory's group pages list the same people. The website's admins pick them
//  in Manage; the verification service keeps that list and publishes it at
//  GET /v1/people/listed (public — it is what the website shows anyone). The app's
//  moderators' own picks (`DirectoryUser.directoryGroups`) sit on top of this, and
//  the website shows those too, so both sides list exactly the same people.
//
//  The last answer is kept in UserDefaults so the pages are right straight away
//  (and offline); it's refreshed when the directory opens, at most every few minutes.
//

import Foundation
import Combine

@MainActor
final class WebsitePeopleList: ObservableObject {
    static let shared = WebsitePeopleList()

    /// Raw user record names (no `UserProfile_` prefix) on each website page.
    @Published private(set) var listed: [CreativeGroup: Set<String>] = [:]

    private var lastFetch: Date?
    private let defaults = UserDefaults.standard
    private let cacheKey = "websitePeopleListed"

    /// The website's page slugs, as the service keys its JSON.
    private static let groupsBySlug: [String: CreativeGroup] = [
        "actors": .actor, "filmmakers": .filmmaker, "musicians": .musician,
    ]

    private init() {
        if let data = defaults.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([String: [String]].self, from: data) {
            apply(cached)
        }
    }

    /// Whether the website lists this person on the group's page. Accepts a
    /// `UserProfile_…` record name or the raw user ID.
    func contains(userID: String, group: CreativeGroup) -> Bool {
        guard let raw = CreativeProfileStore.rawUserID(userID) else { return false }
        return listed[group]?.contains(raw) ?? false
    }

    /// Fetches the website's list unless it was fetched in the last `maxAge` seconds.
    /// Quiet on failure or without a service URL: the cached list stands.
    func refresh(maxAge: TimeInterval = 300) async {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < maxAge { return }
        guard let baseURL = StudentVerificationManager.baseURL else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/people/listed"))
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let decoded = try JSONDecoder().decode([String: [String]].self, from: data)
            apply(decoded)
            defaults.set(data, forKey: cacheKey)
            lastFetch = Date()
        } catch {
            // Offline or the service is down: keep showing the last list.
        }
    }

    private func apply(_ pages: [String: [String]]) {
        var next: [CreativeGroup: Set<String>] = [:]
        for (slug, ids) in pages {
            guard let group = Self.groupsBySlug[slug] else { continue }
            next[group] = Set(ids.compactMap(CreativeProfileStore.rawUserID))
        }
        listed = next
    }
}
