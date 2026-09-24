//
//  MusicDetailView.swift
//  Longhorn Artists Connect
//
//  Detail view specifically for Music submissions.
//  Audio playback and the rest of the backend logic live in
//  10) Streaming/MusicModel.swift.
//

import SwiftUI
import AVKit

struct MusicDetailView: View {
    /// The track as originally passed in. Display reads go through `music` (below), which
    /// resolves the current version from the store so an edit is reflected immediately.
    private let passedMusic: Submission
    @Binding var liked: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // Observed so the view refreshes (and re-reads `music`) when an edit updates the store.
    @ObservedObject private var store: SubmissionStore_3_2 = .shared

    /// The live version of this track from the store (falling back to the passed-in copy),
    /// so edits to the artist/genres/credits/links/cover appear without reopening the detail.
    private var music: Submission {
        store.approvedSubmissions.first { $0.id == passedMusic.id }
            ?? store.submissions.first { $0.id == passedMusic.id }
            ?? passedMusic
    }

    // Backend model handles all logic
    @StateObject private var model: MusicModel

    @State private var selectedPortfolioName: CreditedPerson?

    // Icon color that adapts to light/dark mode
    private var iconColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    // UI State
    @State private var showSendMessage = false
    @State private var showDeleteConfirmation = false
    @State private var showReportSheet = false
    @State private var showEditSheet = false
    @State private var showCollectionPicker = false
    /// Shown only once loading has run for over 1.5s (first-launch content download).
    @State private var showSlowLoadingMessage = false
    /// The resolved local audio file. The feed no longer downloads audio assets, so
    /// this is filled from a cached copy or an on-demand fetch when the track opens.
    @State private var resolvedAudioURL: URL?
    @State private var isLoadingAudio = false
    /// Set once `resolveAudio()` finishes without a playable track, describing *why* — so
    /// the row states the actual reason ("Coming Soon", "Record Not Found", "Error
    /// Streaming", …) instead of collapsing every failure into "Audio unavailable".
    /// Nil while resolving, and once a playable URL is found.
    @State private var streamStatus: VideoStreamStatus?

    /// The track's length as synced with the record. For music posts the audio length
    /// rides in the shared `videoDuration` field (see `CloudKitTransitionAdapter`), so the
    /// scrubber can be drawn before the stream reports its own duration. Nil if unknown.
    private var syncedAudioDuration: Double? {
        guard let stored = music.videoDuration, stored.isFinite, stored > 0 else { return nil }
        return stored
    }

    /// Whether this post is expected to have audio at all. A track uploaded with audio
    /// syncs its length to the feed, so a stored duration means "there should be a file" —
    /// which separates a genuine "Coming Soon" from a file missing in CloudKit.
    private var expectsAudio: Bool {
        syncedAudioDuration != nil
    }

    /// Resolves the playable audio. Uses the uploader's local copy if one is on disk and
    /// actually decodable; otherwise streams from a range-supporting CDN URL (AVPlayer
    /// streams it directly). The audio is never downloaded to the device. Every
    /// non-playable outcome sets `streamStatus` to the exact reason.
    private func resolveAudio() async {
        if let local = music.audioURL {
            // A file that exists but carries no audio track (a truncated or
            // wrong-container upload) would otherwise drive dead, silent controls.
            if await Self.hasAudioTrack(local) {
                resolvedAudioURL = local
                print("🎵 [MusicCard] PLAYING LOCAL FILE (not streaming): \(local.scheme ?? "?") \(local.lastPathComponent)")
                return
            }
            print("🎵 [MusicCard] local file has no audio track, falling back to streaming: \(local.lastPathComponent)")
        }
        guard resolvedAudioURL == nil, !isLoadingAudio else { return }
        isLoadingAudio = true
        let resolution = await CloudKitManager.shared.streamResolution(submissionID: music.id, type: .music)
        switch resolution {
        case .streaming(let streamURL):
            resolvedAudioURL = streamURL
            print("🎵 [MusicCard] STREAMING via CDN (no download): scheme=\(streamURL.scheme ?? "?") host=\(streamURL.host ?? "?")")
        case .assetMissing:
            streamStatus = expectsAudio ? .fileNonExistent : .comingSoon
        case .recordNotFound:
            streamStatus = .recordNotFound
        case .noDownloadURL:
            streamStatus = .noDownloadURL
        case .lookupError(let code):
            streamStatus = .errorStreaming(code)
        case .notConfigured:
            streamStatus = .notConfigured
        }
        isLoadingAudio = false
    }

    /// Whether a file actually has a playable audio track (not just a file that exists).
    private static func hasAudioTrack(_ url: URL) async -> Bool {
        let tracks = try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
        return (tracks?.isEmpty == false)
    }

    init(music: Submission, liked: Binding<Bool>) {
        self.passedMusic = music
        self._liked = liked
        self._model = StateObject(wrappedValue: MusicModel(submission: music))
    }
    
    var body: some View {
        ZStack {
            // MARK: - Loading State
            if model.isLoading && !model.contentLoaded {
                VStack(spacing: 16) { // ⚙️ Spacing between spinner and text
                    ProgressView()
                        .scaleEffect(1.5) // ⚙️ Loading spinner size
                    Text("Loading...")
                        .font(.headline) // ⚙️ Loading text font
                        .foregroundStyle(.secondary) // ⚙️ Loading text color

                    if showSlowLoadingMessage {
                        Text("When first downloading Nexus, content may take a few minutes to load. But, from there on after, it will be quick!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    // Only surface the first-launch hint if loading is still going after 1.5s.
                    // SwiftUI cancels this task when content loads and the view is removed.
                    try? await Task.sleep(for: .seconds(1.5))
                    showSlowLoadingMessage = true
                }
            } else {
                // MARK: - Main Content
                ScrollView {
                    VStack(spacing: 0) {
                        // Album Cover Section — display only; tapping it must NOT open a
                        // fullscreen view.
                        VStack(alignment: .leading, spacing: 0) {
                            ZStack {
                                if let thumbnailData = music.thumbnailData,
                                   let uiImage = UIImage(data: thumbnailData) {
                                    // Show the cover at its natural aspect ratio so
                                    // non-square artwork isn't letterboxed into a square.
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Rectangle()
                                        .fill(LinearGradient(
                                            colors: [model.tintColor.opacity(0.55), model.tintColor.opacity(0.25)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                        .frame(maxWidth: .infinity)
                                        .aspectRatio(1.0, contentMode: .fit)
                                    Image(systemName: "music.note")
                                        .font(.system(size: 60, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .clipped()
                            
                            // Title, genres, explicit tag, and action buttons
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(music.title)
                                            .font(.system(size: 28, weight: .bold))
                                            .minimumScaleFactor(0.6)
                                            .lineLimit(2)

                                        // Artist name
                                        if !music.artist.isEmpty {
                                            Text(music.artist)
                                                .font(.title3)
                                                .foregroundStyle(.secondary)
                                        }

                                        // Genres and explicit tag, with the release year
                                        // pinned to the row's right edge.
                                        GenreReleaseYearRow(releaseYear: music.releaseYear) {
                                            GenreText(genres: music.genres.joined(separator: " • "))

                                            if music.explicit {
                                                Text("Explicit")
                                                    .font(.subheadline)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(.red.opacity(0.2))
                                                    .foregroundStyle(.red)
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                            }
                                        }
                                    }
                                    // No Spacer here: the genre/year row above is
                                    // full-width, so the info column already pushes the
                                    // buttons right — and a Spacer would split the
                                    // leftover width, pulling the year off the edge.

                                    // Action buttons — packed tight to leave the title more room.
                                    HStack(spacing: 2) {
                                        Button {
                                            model.toggleLike()
                                        } label: {
                                            // Like counts are private: only credited collaborators
                                            // see them on their own portfolio page.
                                            Image(systemName: model.isLiked() ? "heart.fill" : "heart")
                                                .font(.system(size: 20))
                                                .foregroundStyle(model.isLiked() ? .red : .primary)
                                                .frame(minWidth: 30, minHeight: 32)
                                        }

                                        Button {
                                            showCollectionPicker = true
                                        } label: {
                                            Image(systemName: model.isInAnyCollection() ? "bookmark.fill" : "bookmark")
                                                .font(.system(size: 20))
                                                .foregroundStyle(iconColor)
                                                .frame(width: 30, height: 32)
                                        }

                                        Button {
                                            showSendMessage = true
                                        } label: {
                                            Image(systemName: "paperplane")
                                                .font(.system(size: 20))
                                                .foregroundStyle(iconColor)
                                                .frame(width: 30, height: 32)
                                        }

                                        Button {
                                            showReportSheet = true
                                        } label: {
                                            Image(systemName: "flag")
                                                .font(.system(size: 20))
                                                .foregroundStyle(iconColor)
                                                .frame(width: 30, height: 32)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                            
                            // Audio Player Controls
                            if let audioURL = resolvedAudioURL {
                                VStack(spacing: 8) {
                                    HStack(spacing: 12) {
                                        // Play/Pause button — shows a spinner while the
                                        // stream fills its buffer, so a track that hasn't
                                        // started yet doesn't look like a dead button.
                                        Button {
                                            model.togglePlayPause()
                                        } label: {
                                            ZStack {
                                                Circle()
                                                    .fill(Color.secondary.opacity(0.1))
                                                if model.isBuffering {
                                                    ProgressView()
                                                } else {
                                                    Image(systemName: model.isAudioPlaying ? "pause.fill" : "play.fill")
                                                        .font(.system(size: 20))
                                                        .foregroundStyle(.primary)
                                                }
                                            }
                                            .frame(width: 44, height: 44)
                                        }
                                        
                                        // Progress bar and time labels
                                        VStack(spacing: 8) {
                                            GeometryReader { geometry in
                                                ZStack(alignment: .leading) {
                                                    Rectangle()
                                                        .fill(Color.secondary.opacity(0.3))
                                                        .frame(height: 4)
                                                    
                                                    // `model.progress` is clamped to 0...1
                                                    // and never NaN — feeding a raw
                                                    // currentTime/duration ratio in here
                                                    // produced a NaN width (and a broken
                                                    // layout) before the stream reported
                                                    // its duration.
                                                    Rectangle()
                                                        .fill(Color.brandOrange)
                                                        .frame(width: geometry.size.width * CGFloat(model.progress), height: 4)
                                                }
                                                .clipShape(Capsule())
                                                .gesture(
                                                    DragGesture(minimumDistance: 0)
                                                        .onChanged { value in
                                                            // Preview only. Seeking on every
                                                            // drag update cancels the stream's
                                                            // in-flight range requests, which
                                                            // stalls playback mid-scrub.
                                                            guard geometry.size.width > 0 else { return }
                                                            model.scrub(to: Double(value.location.x / geometry.size.width) * model.duration)
                                                        }
                                                        .onEnded { value in
                                                            guard geometry.size.width > 0 else { return }
                                                            model.endScrubbing(at: Double(value.location.x / geometry.size.width) * model.duration)
                                                        }
                                                )
                                            }
                                            .frame(height: 4)
                                            
                                            HStack {
                                                Text(model.formatTime(model.currentTime))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .monospacedDigit()
                                                
                                                Spacer()
                                                
                                                Text(model.formatTime(model.duration))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .monospacedDigit()
                                            }
                                        }
                                    }

                                    // A stream that failed outright says so, rather than
                                    // leaving controls that silently do nothing.
                                    if let playbackError = model.playbackError {
                                        Text("Error streaming audio — \(playbackError)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                                // `setupAudioPlayer` is idempotent per URL, so a re-appear
                                // reuses the existing player instead of stacking another.
                                .onAppear {
                                    model.setupAudioPlayer(url: audioURL, knownDuration: syncedAudioDuration)
                                }
                                .onDisappear {
                                    model.cleanupAudioPlayer()
                                }
                            } else {
                                // The feed skips heavy audio assets, so the track resolves
                                // on demand when the post is opened.
                                HStack(spacing: 8) {
                                    if isLoadingAudio {
                                        ProgressView()
                                    }
                                    Text(isLoadingAudio ? "Loading audio…" : (streamStatus?.label ?? "Audio unavailable"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                                .task { await resolveAudio() }
                            }
                        }
                        
                        // Music Information
                        VStack(alignment: .leading, spacing: 12) {
                            // Recording credits
                            if !music.orderedRecording.isEmpty {
                                Divider()
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Recording")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    
                                    ForEach(model.consolidatedCrew(music.orderedRecording), id: \.name) { consolidated in
                                        HStack(alignment: .top) {
                                            Text(consolidated.roles.joined(separator: ", "))
                                                .font(.body)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)

                                            Spacer()

                                            CreditNameView(name: consolidated.name, selection: $selectedPortfolioName)
                                        }
                                    }
                                }
                            }
                            
                            // Production credits
                            if !music.orderedProduction.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Production")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    
                                    ForEach(model.consolidatedCrew(music.orderedProduction), id: \.name) { consolidated in
                                        HStack(alignment: .top) {
                                            Text(consolidated.roles.joined(separator: ", "))
                                                .font(.body)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)

                                            Spacer()

                                            CreditNameView(name: consolidated.name, selection: $selectedPortfolioName)
                                        }
                                    }
                                }
                            }
                            
                            // Streaming links
                            if !music.spotifyLink.isEmpty || !music.appleMusicLink.isEmpty || !music.amazonMusicLink.isEmpty || !music.youtubeMusicLink.isEmpty || !music.soundcloudLink.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Also On")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 16) {
                                        if !music.spotifyLink.isEmpty, let url = URL(string: music.spotifyLink) {
                                            Link(destination: url) {
                                                Image("Spotify")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 40, height: 40)
                                                    .frame(width: 60)
                                            }
                                        }

                                        if !music.appleMusicLink.isEmpty, let url = URL(string: music.appleMusicLink) {
                                            Link(destination: url) {
                                                Image("Apple Music")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 40, height: 40)
                                                    .frame(width: 60)
                                            }
                                        }

                                        if !music.amazonMusicLink.isEmpty, let url = URL(string: music.amazonMusicLink) {
                                            Link(destination: url) {
                                                Image(systemName: "music.note")
                                                    .font(.system(size: 32))
                                                    .foregroundStyle(.blue)
                                                    .frame(width: 60)
                                            }
                                        }

                                        if !music.youtubeMusicLink.isEmpty, let url = URL(string: music.youtubeMusicLink) {
                                            Link(destination: url) {
                                                Image("YouTube Music")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 80, height: 80)
                                                    .frame(width: 90)
                                            }
                                        }

                                        if !music.soundcloudLink.isEmpty, let url = URL(string: music.soundcloudLink) {
                                            Link(destination: url) {
                                                Image("Soundcloud")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 40, height: 40)
                                                    .frame(width: 60)
                                            }
                                        }
                                    }
                                }
                            }

                            // Lyrics — shown at the bottom, below the streaming links.
                            if !music.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Divider()
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Lyrics")
                                        .font(.title2)
                                        .fontWeight(.bold)

                                    Text(music.lyrics)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            // Moderator info
                            if UserDefaults.standard.bool(forKey: "isModeratorMode"), ModeratorAccess.isModerator {
                                Text("Submitted by \(music.submittedBy)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                                    .padding(.top, 16)
                            }
                            
                            // Edit and Delete buttons
                            if model.canEditOrDelete {
                                OwnerActionButtons(
                                    onEdit: { showEditSheet = true },
                                    onDelete: { showDeleteConfirmation = true }
                                )
                                .padding(.horizontal)
                                .padding(.top, 24)
                                .padding(.bottom)
                            }
                        }
                        .padding()
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .presentationDragIndicator(.hidden)
        .onAppear {
            Task {
                await model.simulateLoading()
            }
        }
        .sheet(item: $selectedPortfolioName) { person in
            PersonProfileView(name: person.name)
        }
        .sheet(isPresented: $showSendMessage) {
            SendPostMessageView(post: music)
        }
        .sheet(isPresented: $showReportSheet) {
            ReportContentView(post: music)
        }
        .sheet(isPresented: $showEditSheet) {
            MusicEditView(submission: music) { updatedSubmission in
                model.update(updatedSubmission)
                // An edit can replace the audio at the same file path, so the player
                // won't notice the change on its own. Tear it down and re-resolve.
                model.cleanupAudioPlayer()
                resolvedAudioURL = nil
                streamStatus = nil
            }
        }
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerView(post: music)
        }
        .alert("Delete Music?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                model.delete()
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

}

#Preview {
    // Pretend a subset of the credited people already have Nexus accounts, so
    // those names render orange/clickable while the rest stay grey.
    let _ = UserDefaults.standard.set(
        ["Sofia Nguyen", "Marcus Bell"],
        forKey: "createdUserProfiles"
    )
    return MusicDetailView(
        music: Submission(
            id: UUID(),
            type: .music,
            title: "Sample Song",
            details: "A great track",
            genres: ["Indie", "Pop"],
            releaseYear: "2023",
            artist: "The Sample Band",
            orderedRecording: [
                OrderedEntry(role: "Vocals", name: "Sofia Nguyen"),
                OrderedEntry(role: "Guitar", name: "Liam O'Brien")
            ],
            orderedProduction: [
                OrderedEntry(role: "Producer", name: "Marcus Bell"),
                OrderedEntry(role: "Mixing", name: "Priya Patel")
            ]
        ),
        liked: .constant(false)
    )
}
