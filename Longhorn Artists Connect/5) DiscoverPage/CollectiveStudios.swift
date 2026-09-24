//
//  Collective Studios.swift
//  Longhorn Artists Connect
//
//  Hardcoded catalog of Collective Studios "Weekly Shorts", grouped by season.
//
//  The Collective org page's Weekly Shorts section is driven by this catalog (it bypasses
//  the CloudKit `OrgContentLink` path used by other orgs — see `DiscoverView`). Each
//  episode is matched to a real posted submission by title, so tapping it opens the actual
//  post. The season/episode code also prefixes the studio credit on the home feed
//  (e.g. "S1E1 • Collective").
//

import Foundation

// MARK: - Episode

/// One Weekly Short. `title` must match the real post's title (matching is done with
/// `CollectiveStudios.normalize`, so capitalization, curly quotes and trailing periods
/// don't have to match exactly).
struct CollectiveEpisode: Identifiable, Hashable {
    let season: Int
    let episode: Int
    let title: String

    /// e.g. "S1E1" — used as the row label, the id, and the home-feed credit prefix.
    var code: String { "S\(season)E\(episode)" }
    var id: String { code }
}

// MARK: - Catalog

enum CollectiveStudios {

    /// Every Weekly Short, listed in season/episode order. Season/episode numbers are the
    /// source of truth for ordering and for the on-feed "SxEy" credit.
    static let episodes: [CollectiveEpisode] = [
        // MARK: Season 1
        CollectiveEpisode(season: 1, episode: 1,  title: "The Creative Life"),
        CollectiveEpisode(season: 1, episode: 2,  title: "Collective on Wheels"),
        CollectiveEpisode(season: 1, episode: 3,  title: "Out of My Mind"),
        CollectiveEpisode(season: 1, episode: 4,  title: "Just Getting Started"),
        CollectiveEpisode(season: 1, episode: 5,  title: "Slow Down"),
        CollectiveEpisode(season: 1, episode: 6,  title: "Seeing Double"),
        CollectiveEpisode(season: 1, episode: 7,  title: "Out the Basement"),
        CollectiveEpisode(season: 1, episode: 8,  title: "Fake Faith"),
        CollectiveEpisode(season: 1, episode: 9,  title: "The Special"),
        CollectiveEpisode(season: 1, episode: 10, title: "Cowboy"),

        // MARK: Season 2
        CollectiveEpisode(season: 2, episode: 1,  title: "excursion"),
        CollectiveEpisode(season: 2, episode: 2,  title: "free lemonade?"),
        CollectiveEpisode(season: 2, episode: 3,  title: "summer’s overrated anyways"),
        CollectiveEpisode(season: 2, episode: 4,  title: "game over"),
        CollectiveEpisode(season: 2, episode: 5,  title: "gonna give you the slip"),
        CollectiveEpisode(season: 2, episode: 6,  title: "in your own way, on your own time"),
        CollectiveEpisode(season: 2, episode: 7,  title: "crashout"),
        CollectiveEpisode(season: 2, episode: 8,  title: "hell of a life"),
        CollectiveEpisode(season: 2, episode: 9,  title: "passing notes"),
        CollectiveEpisode(season: 2, episode: 10, title: "psycho"),
        CollectiveEpisode(season: 2, episode: 11, title: "tote bag + matcha?"),
        CollectiveEpisode(season: 2, episode: 12, title: "live. fit. go. celsius."),
        CollectiveEpisode(season: 2, episode: 13, title: "pov you’re a lighter"),
        CollectiveEpisode(season: 2, episode: 14, title: "hive."),
        CollectiveEpisode(season: 2, episode: 15, title: "dorm drop"),
        CollectiveEpisode(season: 2, episode: 16, title: "the rubber penalty"),
        CollectiveEpisode(season: 2, episode: 17, title: "best take"),
        CollectiveEpisode(season: 2, episode: 18, title: "running out of time"),

        // MARK: Season 3
        CollectiveEpisode(season: 3, episode: 1,  title: "NEXT BIG THING."),
        CollectiveEpisode(season: 3, episode: 2,  title: "NEW YEAR."),
        CollectiveEpisode(season: 3, episode: 3,  title: "STRUCK BY LOVE."),
        CollectiveEpisode(season: 3, episode: 4,  title: "PERFECT by Marc Jacobs."),
        CollectiveEpisode(season: 3, episode: 5,  title: "BLEED OUT."),
        CollectiveEpisode(season: 3, episode: 6,  title: "MATCH POINT"),
        CollectiveEpisode(season: 3, episode: 7,  title: "LOOF & GLOOM."),
        CollectiveEpisode(season: 3, episode: 8,  title: "HITCH."),
        CollectiveEpisode(season: 3, episode: 9,  title: "KNOCKOUT."),
        CollectiveEpisode(season: 3, episode: 10, title: "UP IN THE SKY."),
        CollectiveEpisode(season: 3, episode: 11, title: "HEAT RISES."),
        CollectiveEpisode(season: 3, episode: 12, title: "AQUAMARINE.")
    ]

    /// Season numbers present, ascending (e.g. [1, 2, 3]).
    static var seasons: [Int] {
        Array(Set(episodes.map(\.season))).sorted()
    }

    /// The episodes in one season, ascending by episode number.
    static func episodes(inSeason season: Int) -> [CollectiveEpisode] {
        episodes.filter { $0.season == season }.sorted { $0.episode < $1.episode }
    }

    /// The catalog episode a post title corresponds to, if any (matched on normalized title).
    static func episode(forTitle title: String) -> CollectiveEpisode? {
        byNormalizedTitle[normalize(title)]
    }

    /// The season/episode code (e.g. "S1E1") for a post title, if it's a Weekly Short.
    static func episodeCode(forTitle title: String) -> String? {
        episode(forTitle: title)?.code
    }

    /// Normalized-title → episode lookup, built once. If two titles normalize to the same
    /// key the earlier (lower season/episode) wins, which is deterministic given `episodes`
    /// is authored in order.
    private static let byNormalizedTitle: [String: CollectiveEpisode] = {
        Dictionary(episodes.map { (normalize($0.title), $0) }, uniquingKeysWith: { first, _ in first })
    }()

    /// Normalizes a title for matching: lowercased, curly quotes → straight, trailing
    /// periods/whitespace dropped, and internal whitespace collapsed. This lets a post
    /// titled "Perfect by Marc Jacobs" match the catalog's "PERFECT by Marc Jacobs.".
    static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()
        s = s.replacingOccurrences(of: "\u{2019}", with: "'") // ’ → '
        s = s.replacingOccurrences(of: "\u{2018}", with: "'") // ‘ → '
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = s.last, last == "." || last == " " { s.removeLast() }
        let parts = s.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        return parts.joined(separator: " ")
    }
}
