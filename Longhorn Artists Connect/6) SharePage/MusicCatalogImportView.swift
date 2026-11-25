//
//  MusicCatalogImportView.swift
//  Longhorn Artists Connect
//
//  "Import from Apple Music" for the music form. Search the Apple Music catalog for an
//  artist, song, or album, pick a release, and the form fills itself in: title, artist,
//  artwork, genres, release year, explicit flag, the Apple Music link — and the Spotify
//  link too, matched by ISRC through the Worker (see SpotifyLookupService).
//
//  What plays on the post is the catalog's 30-second preview, streamed from Apple's own
//  URL. Neither store lets an app download a full track, and Spotify no longer hands
//  previews to new apps at all, so Apple Music is the preview source even for a release
//  the artist thinks of as Spotify-first. The post's "Also On" links take listeners to
//  the full track.
//
//  Catalog reads need no Apple Music sign-in from the student; they do need the MusicKit
//  App Service switched on for this App ID in the developer portal, or every request
//  fails with a developer-token error (surfaced below, in plain words).
//

import SwiftUI
import MusicKit

// MARK: - Result

/// Everything the import hands to the music form.
struct MusicCatalogImportResult {
    var title: String
    var artist: String
    var genres: [String]
    var releaseYear: String
    var explicit: Bool
    /// "Song", "EP" or "Album" — the form's release category.
    var category: String
    var appleMusicLink: String
    var spotifyLink: String
    /// Album artwork, JPEG/PNG bytes straight from the catalog CDN.
    var coverData: Data?
    /// Preview of track 1 (nil when the catalog offers no preview for it).
    var previewURL: URL?
    /// Previews of tracks 2..n of an album/EP, in running order.
    var trackPreviewURLs: [URL]
    /// Songwriters, from the catalog's composer credit.
    var productionCredits: [OrderedEntry]
    var catalog: MusicCatalogInfo

    var trackCount: Int { (previewURL == nil ? 0 : 1) + trackPreviewURLs.count }
}

// MARK: - View

struct MusicCatalogImportView: View {
    var onImport: (MusicCatalogImportResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var artists: [Artist] = []
    @State private var songs: [Song] = []
    @State private var albums: [Album] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    /// ID of the song/album currently being imported (a spinner replaces its chevron).
    @State private var importingID: String?
    @State private var importError: String?

    private var hasResults: Bool { !artists.isEmpty || !songs.isEmpty || !albums.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                if let searchError {
                    Section {
                        Label(searchError, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if !hasResults && !isSearching && searchError == nil {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(query.trimmingCharacters(in: .whitespaces).count < 2
                                 ? "Search for your artist name, a song, or an album."
                                 : "No matches on Apple Music.")
                                .foregroundStyle(.secondary)
                            Text("Only import music you made or are credited on. Imported posts play the catalog's 30-second preview and link out to the full track.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !artists.isEmpty {
                    Section("Artists") {
                        ForEach(artists) { artist in
                            NavigationLink(value: artist) {
                                CatalogRow(artwork: artist.artwork, title: artist.name,
                                           subtitle: artist.genreNames?.first ?? "Artist", circular: true)
                            }
                        }
                    }
                }

                if !songs.isEmpty {
                    Section("Songs") {
                        ForEach(songs) { song in
                            importRow(id: song.id.rawValue, artwork: song.artwork, title: song.title,
                                      subtitle: [song.artistName, song.albumTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                                      explicit: song.contentRating == .explicit) {
                                try await MusicCatalogImporter.importSong(song)
                            }
                        }
                    }
                }

                if !albums.isEmpty {
                    Section("Albums") {
                        ForEach(albums) { album in
                            importRow(id: album.id.rawValue, artwork: album.artwork, title: album.title,
                                      subtitle: AlbumRowText.subtitle(for: album),
                                      explicit: album.contentRating == .explicit) {
                                try await MusicCatalogImporter.importAlbum(album)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if isSearching && !hasResults {
                    ProgressView()
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Artist, song, or album")
            .autocorrectionDisabled()
            .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
            .navigationTitle("Import from Apple Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: Artist.self) { artist in
                ArtistReleasesView(artist: artist, importingID: $importingID, importError: $importError) { result in
                    finish(result)
                }
            }
            .alert("Couldn't Import", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    // MARK: Rows

    /// A song/album row that imports on tap. Only one import runs at a time.
    private func importRow(id: String, artwork: Artwork?, title: String, subtitle: String, explicit: Bool,
                           perform: @escaping () async throws -> MusicCatalogImportResult) -> some View {
        Button {
            guard importingID == nil else { return }
            importingID = id
            Task {
                do {
                    let result = try await perform()
                    await MainActor.run {
                        importingID = nil
                        finish(result)
                    }
                } catch {
                    await MainActor.run {
                        importingID = nil
                        importError = MusicCatalogAccess.friendlyMessage(for: error)
                    }
                }
            }
        } label: {
            HStack {
                CatalogRow(artwork: artwork, title: title, subtitle: subtitle, explicit: explicit)
                Spacer()
                if importingID == id {
                    ProgressView()
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(Color.brandOrange)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(importingID != nil && importingID != id)
    }

    private func finish(_ result: MusicCatalogImportResult) {
        onImport(result)
        dismiss()
    }

    // MARK: Search

    /// Debounced catalog search; a new keystroke cancels the in-flight one.
    private func scheduleSearch(_ term: String) {
        searchTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            artists = []; songs = []; albums = []
            isSearching = false
            searchError = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run { isSearching = true; searchError = nil }
            do {
                let response = try await MusicCatalogAccess.perform {
                    var request = MusicCatalogSearchRequest(term: trimmed, types: [Artist.self, Song.self, Album.self])
                    request.limit = 10
                    return try await request.response()
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    artists = Array(response.artists)
                    songs = Array(response.songs)
                    albums = Array(response.albums)
                    isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    artists = []; songs = []; albums = []
                    isSearching = false
                    searchError = MusicCatalogAccess.friendlyMessage(for: error)
                }
            }
        }
    }
}

// MARK: - Artist drill-down

/// Every release under an artist — albums, EPs, and singles together, newest first.
private struct ArtistReleasesView: View {
    let artist: Artist
    @Binding var importingID: String?
    @Binding var importError: String?
    var onImport: (MusicCatalogImportResult) -> Void

    @State private var releases: [Album] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        List {
            if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !isLoading && releases.isEmpty {
                Text("No releases found for this artist on Apple Music.")
                    .foregroundStyle(.secondary)
            }

            ForEach(releases) { album in
                Button {
                    guard importingID == nil else { return }
                    importingID = album.id.rawValue
                    Task {
                        do {
                            let result = try await MusicCatalogImporter.importAlbum(album)
                            await MainActor.run {
                                importingID = nil
                                onImport(result)
                            }
                        } catch {
                            await MainActor.run {
                                importingID = nil
                                importError = MusicCatalogAccess.friendlyMessage(for: error)
                            }
                        }
                    }
                } label: {
                    HStack {
                        CatalogRow(artwork: album.artwork, title: album.title,
                                   subtitle: AlbumRowText.subtitle(for: album),
                                   explicit: album.contentRating == .explicit)
                        Spacer()
                        if importingID == album.id.rawValue {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundStyle(Color.brandOrange)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(importingID != nil && importingID != album.id.rawValue)
            }
        }
        .listStyle(.insetGrouped)
        .overlay { if isLoading { ProgressView() } }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let detailed = try await MusicCatalogAccess.perform {
                try await artist.with([.albums, .singles])
            }
            var seen = Set<String>()
            var all: [Album] = []
            for album in Array(detailed.albums ?? []) + Array(detailed.singles ?? []) {
                if seen.insert(album.id.rawValue).inserted { all.append(album) }
            }
            all.sort { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
            releases = all
        } catch {
            loadError = MusicCatalogAccess.friendlyMessage(for: error)
        }
        isLoading = false
    }
}

// MARK: - Row pieces

private struct CatalogRow: View {
    let artwork: Artwork?
    let title: String
    let subtitle: String
    var explicit: Bool = false
    var circular: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let artwork {
                    ArtworkImage(artwork, width: 48, height: 48)
                } else {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                        .frame(width: 48, height: 48)
                        .background(Color.secondary.opacity(0.15))
                }
            }
            .clipShape(circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if explicit {
                        Text("E")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private enum AlbumRowText {
    static func subtitle(for album: Album) -> String {
        var parts: [String] = []
        parts.append(MusicCatalogImporter.category(for: album, trackCount: album.trackCount))
        if let date = album.releaseDate {
            parts.append(String(Calendar.current.component(.year, from: date)))
        }
        if album.trackCount > 1 { parts.append("\(album.trackCount) tracks") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Catalog access

/// Runs a MusicKit request, asking for authorization once if the OS insists on it, and
/// turns MusicKit's errors into sentences a student can act on.
enum MusicCatalogAccess {
    static func perform<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            // Catalog reads don't normally need user authorization, but a device that
            // has never answered the prompt can refuse the first request. Ask once.
            if MusicAuthorization.currentStatus == .notDetermined {
                let status = await MusicAuthorization.request()
                if status == .authorized { return try await work() }
            }
            throw error
        }
    }

    static func friendlyMessage(for error: Error) -> String {
        let text = String(describing: error).lowercased()
        if text.contains("developer token") || text.contains("developertoken") {
            return "Apple Music access isn't enabled for this app yet. In the Apple Developer portal, turn on the MusicKit App Service for the app's App ID, then rebuild."
        }
        if error is SpotifyLookupError { return error.localizedDescription }
        if MusicAuthorization.currentStatus == .denied || MusicAuthorization.currentStatus == .restricted {
            return "Apple Music access is turned off for Nexus. Allow it in Settings › Nexus to search the catalog."
        }
        if text.contains("offline") || text.contains("network") || text.contains("internet") {
            return "Couldn't reach Apple Music. Check your connection and try again."
        }
        return "Apple Music didn't respond. Try again in a moment."
    }
}

// MARK: - Importer

/// Turns a catalog song or album into the form's fields.
enum MusicCatalogImporter {
    enum ImportError: Error, LocalizedError {
        case noTracks
        var errorDescription: String? {
            switch self {
            case .noTracks: return "That release has no songs Apple Music can preview."
            }
        }
    }

    /// A single song, as its own post.
    static func importSong(_ song: Song) async throws -> MusicCatalogImportResult {
        let detailed = try await MusicCatalogAccess.perform { try await song.with([.artists, .albums]) }
        let album = detailed.albums?.first
        let artist = detailed.artists?.first

        var catalog = MusicCatalogInfo()
        catalog.appleMusicSongID = song.id.rawValue
        catalog.appleMusicAlbumID = album?.id.rawValue
        catalog.appleMusicArtistID = artist?.id.rawValue
        catalog.catalogArtistName = song.artistName
        catalog.isrc = song.isrc
        catalog.fullDuration = song.duration

        let spotify = await spotifyMatch(isrc: song.isrc)
        catalog.spotifyTrackID = spotify?.trackID
        catalog.spotifyArtistID = spotify?.artistID

        let credits = composerCredits([song])

        return MusicCatalogImportResult(
            title: song.title,
            artist: song.artistName,
            genres: CatalogGenreMapper.appGenres(from: song.genreNames),
            releaseYear: year(from: song.releaseDate ?? album?.releaseDate),
            explicit: song.contentRating == .explicit,
            category: "Song",
            appleMusicLink: song.url?.absoluteString ?? "",
            spotifyLink: spotify?.url ?? "",
            coverData: await artworkData(song.artwork ?? album?.artwork),
            previewURL: song.previewAssets?.first?.url,
            trackPreviewURLs: [],
            productionCredits: credits,
            catalog: catalog
        )
    }

    /// An album, EP, or single — one post carrying every track's preview.
    static func importAlbum(_ album: Album) async throws -> MusicCatalogImportResult {
        let detailed = try await MusicCatalogAccess.perform { try await album.with([.tracks, .artists]) }
        let songs: [Song] = (detailed.tracks ?? []).compactMap { track in
            if case .song(let song) = track { return song }
            return nil
        }
        guard !songs.isEmpty else { throw ImportError.noTracks }

        // A one-song release reads better as a song post titled after the song.
        if songs.count == 1, let only = songs.first {
            var result = try await importSong(only)
            result.catalog.appleMusicAlbumID = album.id.rawValue
            if result.appleMusicLink.isEmpty { result.appleMusicLink = album.url?.absoluteString ?? "" }
            return result
        }

        let artist = detailed.artists?.first
        let previews = songs.map { $0.previewAssets?.first?.url }
        let durations = songs.compactMap(\.duration)

        var catalog = MusicCatalogInfo()
        catalog.appleMusicAlbumID = album.id.rawValue
        catalog.appleMusicSongID = songs.first?.id.rawValue
        catalog.appleMusicArtistID = artist?.id.rawValue
        catalog.catalogArtistName = album.artistName
        catalog.isrc = songs.first?.isrc
        catalog.fullDuration = durations.isEmpty ? nil : durations.reduce(0, +)
        catalog.trackTitles = songs.map(\.title)

        let spotify = await spotifyMatch(isrc: songs.first?.isrc)
        catalog.spotifyTrackID = spotify?.trackID
        catalog.spotifyArtistID = spotify?.artistID

        // Prefer a link to the Spotify album when the first track matched; the track
        // match only knows its own URL, so fall back to that.
        let spotifyLink = spotify?.url ?? ""

        let genres = CatalogGenreMapper.appGenres(from: album.genreNames + songs.flatMap(\.genreNames))

        // Track 1's preview must exist for the post to have a player; if the catalog
        // withholds it, promote the first track that does have one.
        let orderedPreviews = previews.compactMap { $0 }
        return MusicCatalogImportResult(
            title: album.title,
            artist: album.artistName,
            genres: genres,
            releaseYear: year(from: album.releaseDate),
            explicit: album.contentRating == .explicit || songs.contains { $0.contentRating == .explicit },
            category: category(for: album, trackCount: songs.count),
            appleMusicLink: album.url?.absoluteString ?? "",
            spotifyLink: spotifyLink,
            coverData: await artworkData(album.artwork),
            previewURL: orderedPreviews.first,
            trackPreviewURLs: Array(orderedPreviews.dropFirst()),
            productionCredits: composerCredits(songs),
            catalog: catalog
        )
    }

    /// The form's release category for a catalog album.
    static func category(for album: Album, trackCount: Int) -> String {
        if album.isSingle == true || trackCount <= 1 { return "Song" }
        return trackCount <= 6 ? "EP" : "Album"
    }

    // MARK: Helpers

    private static func year(from date: Date?) -> String {
        guard let date else { return "" }
        return String(Calendar.current.component(.year, from: date))
    }

    /// Best-effort Spotify match. A Worker that isn't deployed or configured simply
    /// leaves the Spotify link blank for the student to paste by hand.
    private static func spotifyMatch(isrc: String?) async -> SpotifyTrackMatch? {
        guard let isrc, !isrc.isEmpty else { return nil }
        return try? await SpotifyLookupService.shared.match(isrc: isrc)
    }

    /// Full-size artwork bytes, or nil if the CDN fetch fails (the form then shows the
    /// usual "Select album cover" row).
    private static func artworkData(_ artwork: Artwork?) async -> Data? {
        guard let url = artwork?.url(width: 1000, height: 1000) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              !data.isEmpty
        else { return nil }
        return data
    }

    /// "Songwriter" production credits from the composer names, de-duplicated and
    /// capped so a 20-track album doesn't pre-fill a wall of names.
    private static func composerCredits(_ songs: [Song]) -> [OrderedEntry] {
        var names: [String] = []
        for song in songs {
            guard let composer = song.composerName else { continue }
            // Composer strings often list several people: "A. Writer, B. Writer & C. Writer".
            for piece in composer.replacingOccurrences(of: " & ", with: ",").split(separator: ",") {
                let name = piece.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, !names.contains(name) { names.append(name) }
            }
            if names.count >= 5 { break }
        }
        return names.prefix(5).map { OrderedEntry(role: "Songwriter", name: $0) }
    }
}
