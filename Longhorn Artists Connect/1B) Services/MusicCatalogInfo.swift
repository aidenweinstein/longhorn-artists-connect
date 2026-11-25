//
//  MusicCatalogInfo.swift
//  Longhorn Artists Connect
//
//  What a music post remembers about the streaming-catalog release it was imported
//  from (Apple Music, cross-matched to Spotify by ISRC). Stored on the CloudKit record
//  as one JSON string field, `musicCatalog`, so a new kind of catalog fact is a code
//  change rather than another Dashboard field. Absent on posts whose audio was uploaded
//  by hand.
//
//  The audio itself isn't here: an imported post's 30-second preview is the record's
//  `musicAudioURL` (and `musicTracksURLs` for the rest of an album), the same link
//  fields a big website upload uses, so every client that already streams those plays
//  the preview without knowing anything about imports.
//

import Foundation

nonisolated struct MusicCatalogInfo: Codable, Hashable, Sendable {
    /// Which catalog the post was imported from. "appleMusic" today.
    var source: String = "appleMusic"

    // Apple Music
    var appleMusicSongID: String?
    var appleMusicAlbumID: String?
    var appleMusicArtistID: String?
    /// The artist exactly as the catalog names them, kept separately from the editable
    /// `artist` field so a moderator can compare it to the poster's profile name.
    var catalogArtistName: String = ""

    // Cross-service identity
    var isrc: String?
    var spotifyTrackID: String?
    var spotifyArtistID: String?

    /// Length of the full track in seconds, as listed by the catalog. The post itself
    /// only carries the preview, so this is what the detail view quotes.
    var fullDuration: Double?
    /// Length of the streamed preview in seconds (Apple previews are 30s).
    var previewDuration: Double = 30
    /// Track titles for an imported album/EP, in running order, so the tracklist can
    /// name songs instead of saying "Track 2".
    var trackTitles: [String] = []
    /// When the import happened.
    var importedAt: Date = Date()

    // MARK: JSON (the CloudKit field value)

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// The value written to the record's `musicCatalog` field.
    var jsonString: String? {
        guard let data = try? Self.encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Parses a record's `musicCatalog` field. Nil for an empty or unreadable value, so a
    /// hand-uploaded post (empty string) and a malformed one both read as "not imported".
    init?(jsonString: String?) {
        guard let jsonString, !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8),
              let decoded = try? Self.decoder.decode(MusicCatalogInfo.self, from: data)
        else { return nil }
        self = decoded
    }

    init() {}

    /// Whether the post plays a catalog preview rather than the full track.
    var isPreview: Bool { true }
}

// MARK: - Streaming link parsing

/// Pulls identifiers out of the streaming links users paste (or imports fill in), so a
/// post can be matched to its catalog entry whether or not it was imported.
nonisolated enum StreamingLinkParser {
    /// The Spotify track ID in an `open.spotify.com/track/<id>` link (any locale prefix,
    /// query, or `spotify:track:<id>` URI). Nil for anything else.
    static func spotifyTrackID(from link: String) -> String? {
        spotifyID(kind: "track", from: link)
    }

    /// The Spotify artist ID in an `open.spotify.com/artist/<id>` link or URI.
    static func spotifyArtistID(from link: String) -> String? {
        spotifyID(kind: "artist", from: link)
    }

    private static func spotifyID(kind: String, from link: String) -> String? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // spotify:track:<id>
        let uriPrefix = "spotify:\(kind):"
        if trimmed.lowercased().hasPrefix(uriPrefix) {
            return validSpotifyID(String(trimmed.dropFirst(uriPrefix.count)))
        }

        guard let url = URL(string: trimmed), let host = url.host?.lowercased(),
              host == "open.spotify.com" || host.hasSuffix(".spotify.com")
        else { return nil }
        // Locale-prefixed paths look like /intl-de/track/<id>.
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let index = parts.firstIndex(of: kind), parts.indices.contains(index + 1) else { return nil }
        return validSpotifyID(parts[index + 1])
    }

    /// Spotify IDs are 22 base-62 characters.
    private static func validSpotifyID(_ raw: String) -> String? {
        let id = raw.split(separator: "?").first.map(String.init) ?? raw
        guard id.count == 22, id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return id
    }

    /// The Apple Music song ID in a catalog link. Song links are album links with the
    /// song in the `i` query item (`/album/<slug>/<albumID>?i=<songID>`), and song pages
    /// are `/song/<slug>/<songID>`.
    static func appleMusicSongID(from link: String) -> String? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(), host.hasSuffix("music.apple.com")
        else { return nil }
        if let item = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "i" })?.value,
           !item.isEmpty, item.allSatisfy(\.isNumber) {
            return item
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        if let index = parts.firstIndex(of: "song"), let last = parts.last, index < parts.count - 1,
           last.allSatisfy(\.isNumber) {
            return last
        }
        return nil
    }
}

// MARK: - Genre mapping

/// Maps catalog genre names onto the app's own genre list (see the music form's
/// `availableGenres`). Apple names a few genres differently ("Hip-Hop/Rap", "R&B/Soul")
/// and files everything under a catch-all "Music" that means nothing on a post.
nonisolated enum CatalogGenreMapper {
    static func appGenres(from catalogGenres: [String]) -> [String] {
        var out: [String] = []
        for raw in catalogGenres {
            for mapped in map(raw) where !out.contains(mapped) {
                out.append(mapped)
            }
        }
        return out
    }

    private static func map(_ raw: String) -> [String] {
        let name = raw.trimmingCharacters(in: .whitespaces)
        switch name.lowercased() {
        case "music":                           return []
        case "hip-hop/rap", "hip hop/rap", "rap", "hip-hop", "hip hop":
            return ["Hip Hop"]
        case "r&b/soul":                        return ["R&B", "Soul"]
        case "r&b":                             return ["R&B"]
        case "soul":                            return ["Soul"]
        case "christian & gospel", "gospel", "christian":
            return ["Gospel"]
        case "singer/songwriter", "folk":       return ["Folk"]
        case "dance", "electronic", "house", "techno", "edm":
            return ["Electronic"]
        case "alternative", "alternative rock": return ["Alternative"]
        case "indie", "indie rock", "indie pop": return ["Indie"]
        case "latin", "latino", "latin urbano", "reggaeton", "urbano latino":
            return ["Latin"]
        case "reggae", "dancehall":             return ["Reggae"]
        case "metal", "heavy metal", "hard rock": return ["Metal"]
        case "punk", "pop punk":                return ["Punk"]
        case "funk":                            return ["Funk"]
        case "blues":                           return ["Blues"]
        case "jazz":                            return ["Jazz"]
        case "classical", "classical crossover": return ["Classical"]
        case "country":                         return ["Country"]
        case "rock":                            return ["Rock"]
        case "pop", "k-pop", "j-pop":           return ["Pop"]
        default:
            // Anything already on the app's list passes through unchanged.
            let known = ["Pop", "Rock", "Hip Hop", "R&B", "Country", "Jazz", "Classical", "Electronic",
                         "Folk", "Blues", "Reggae", "Metal", "Punk", "Soul", "Funk", "Latin", "Gospel",
                         "Indie", "Alternative"]
            return known.first { $0.lowercased() == name.lowercased() }.map { [$0] } ?? []
        }
    }
}
