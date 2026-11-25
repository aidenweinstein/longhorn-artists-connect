//
//  SpotifyLookupService.swift
//  Longhorn Artists Connect
//
//  Client for the Worker's Spotify routes (verification-service/src/spotify.ts). The
//  Worker holds the Spotify credentials; the app only ever sees catalog facts:
//
//    GET /v1/music/spotify/lookup?isrc=   the Spotify track matching an ISRC, used by
//                                          the Apple Music import to fill the Spotify link
//    GET /v1/music/spotify/stats?track=   follower count and popularity for a track's
//                                          artist, shown next to the song
//
//  Spotify doesn't expose monthly listeners or play counts through its API, so followers
//  and the 0–100 popularity score are the honest figures available. The Worker caches
//  them for a day and refreshes the ones people look at nightly.
//

import Foundation

/// The Spotify track a release matched to, by ISRC.
nonisolated struct SpotifyTrackMatch: Codable, Hashable, Sendable {
    let trackID: String
    let url: String
    let name: String
    let artistID: String?
    let artistName: String?
    let albumName: String?
}

/// Spotify's public numbers for a track and its primary artist.
nonisolated struct SpotifyStats: Codable, Hashable, Sendable {
    struct Track: Codable, Hashable, Sendable {
        let id: String
        let name: String
        let url: String
        let popularity: Int
    }
    struct Artist: Codable, Hashable, Sendable {
        let id: String
        let name: String
        let url: String
        let followers: Int
        let popularity: Int
    }
    let track: Track
    let artist: Artist
    /// Unix seconds when the Worker last refreshed these from Spotify.
    let fetchedAt: Int

    /// "12.4K" style follower count for the stats row.
    var followersLabel: String {
        Self.compact(artist.followers)
    }

    static func compact(_ value: Int) -> String {
        let n = Double(value)
        switch value {
        case ..<1_000: return "\(value)"
        case ..<10_000: return String(format: "%.1fK", n / 1_000).replacingOccurrences(of: ".0K", with: "K")
        case ..<1_000_000: return "\(Int((n / 1_000).rounded()))K"
        default: return String(format: "%.1fM", n / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        }
    }
}

enum SpotifyLookupError: Error, LocalizedError {
    case notConfigured
    case network
    case service(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Spotify lookups aren't set up on the server yet."
        case .network: return "Couldn't reach the server."
        case .service(let message): return message
        }
    }
}

/// Talks to the Worker. Results are memoized per launch so the detail view can ask on
/// every appearance without a request each time.
actor SpotifyLookupService {
    static let shared = SpotifyLookupService()

    private var matchCache: [String: SpotifyTrackMatch?] = [:]
    private var statsCache: [String: SpotifyStats] = [:]
    /// Set once the Worker says the routes are disabled, so the UI stops asking.
    private(set) var isUnavailable = false

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        return URLSession(configuration: config)
    }()

    /// Same deployment as student verification; nil when the build has no service URL.
    static var baseURL: URL? { StudentVerificationManager.baseURL }

    // MARK: Lookups

    /// The Spotify track with this ISRC, or nil when Spotify has no such recording.
    /// Throws only for a transport/server problem.
    func match(isrc rawISRC: String) async throws -> SpotifyTrackMatch? {
        let isrc = rawISRC.uppercased().filter { $0.isLetter || $0.isNumber }
        guard isrc.count == 12 else { return nil }
        if let cached = matchCache[isrc] { return cached }

        struct Payload: Decodable { let match: SpotifyTrackMatch? }
        let payload: Payload = try await get(path: "v1/music/spotify/lookup", query: [URLQueryItem(name: "isrc", value: isrc)])
        matchCache[isrc] = .some(payload.match)
        return payload.match
    }

    /// Follower/popularity figures for a Spotify track (by the ID in its link).
    func stats(trackID: String) async throws -> SpotifyStats {
        if let cached = statsCache[trackID] { return cached }
        let stats: SpotifyStats = try await get(path: "v1/music/spotify/stats", query: [URLQueryItem(name: "track", value: trackID)])
        statsCache[trackID] = stats
        return stats
    }

    /// Convenience for a post: parses the track ID out of its Spotify link first.
    func stats(forSpotifyLink link: String) async throws -> SpotifyStats? {
        guard let id = StreamingLinkParser.spotifyTrackID(from: link) else { return nil }
        return try await stats(trackID: id)
    }

    // MARK: Networking

    private struct ServiceErrorPayload: Decodable { let error: String; let message: String }

    private func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        guard !isUnavailable, let baseURL = Self.baseURL else { throw SpotifyLookupError.notConfigured }
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw SpotifyLookupError.notConfigured
        }
        components.queryItems = query
        guard let url = components.url else { throw SpotifyLookupError.notConfigured }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw SpotifyLookupError.network
        }
        guard let http = response as? HTTPURLResponse else { throw SpotifyLookupError.network }

        guard (200..<300).contains(http.statusCode) else {
            let payload = try? JSONDecoder().decode(ServiceErrorPayload.self, from: data)
            if payload?.error == "not_configured" || http.statusCode == 404 {
                isUnavailable = true
                throw SpotifyLookupError.notConfigured
            }
            throw SpotifyLookupError.service(payload?.message ?? "Spotify lookup failed.")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SpotifyLookupError.service("Unexpected response from the server.")
        }
    }
}
