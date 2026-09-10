//
//  MusicCard.swift
//  Longhorn Artists Connect
//
//  UI for Music submissions - Clean, customizable interface
//  Backend logic is in MusicModel.swift
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

    /// Resolves the playable audio. Uses the uploader's local copy if one is already on
    /// disk; otherwise streams from a range-supporting CDN URL (AVPlayer streams it
    /// directly). The audio is never downloaded to the device — if no streaming URL is
    /// available, the URL stays nil so the view shows "Audio unavailable".
    private func resolveAudio() async {
        if let local = music.audioURL {
            resolvedAudioURL = local
            return
        }
        guard resolvedAudioURL == nil, !isLoadingAudio else { return }
        isLoadingAudio = true
        resolvedAudioURL = await CloudKitManager.shared.streamingURL(submissionID: music.id, type: .music)
        isLoadingAudio = false
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

                                        // Genres and explicit tag
                                        HStack(spacing: 8) {
                                            if !music.genres.isEmpty {
                                                Text(music.genres.joined(separator: " • "))
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                    // Keep genres on a single line; shrink to fit rather than wrap.
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.7)
                                            }

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

                                        // Release year, shown just under the genres line.
                                        if !music.releaseYear.isEmpty {
                                            Text(music.releaseYear)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

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
                                        // Play/Pause button
                                        Button {
                                            model.togglePlayPause()
                                        } label: {
                                            Image(systemName: model.isAudioPlaying ? "pause.fill" : "play.fill")
                                                .font(.system(size: 20))
                                                .foregroundStyle(.primary)
                                                .frame(width: 44, height: 44)
                                                .background(
                                                    Circle()
                                                        .fill(Color.secondary.opacity(0.1))
                                                )
                                        }
                                        
                                        // Progress bar and time labels
                                        VStack(spacing: 8) {
                                            GeometryReader { geometry in
                                                ZStack(alignment: .leading) {
                                                    Rectangle()
                                                        .fill(Color.secondary.opacity(0.3))
                                                        .frame(height: 4)
                                                    
                                                    Rectangle()
                                                        .fill(Color.brandOrange)
                                                        .frame(width: geometry.size.width * (model.duration > 0 ? CGFloat(model.currentTime / model.duration) : 0), height: 4)
                                                }
                                                .clipShape(Capsule())
                                                .gesture(
                                                    DragGesture(minimumDistance: 0)
                                                        .onChanged { value in
                                                            let newTime = Double(value.location.x / geometry.size.width) * model.duration
                                                            model.seek(to: max(0, min(newTime, model.duration)))
                                                        }
                                                        .onEnded { value in
                                                            let seekTime = Double(value.location.x / geometry.size.width) * model.duration
                                                            model.seek(to: seekTime)
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
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                                .onAppear {
                                    model.setupAudioPlayer(url: audioURL)
                                }
                                .onDisappear {
                                    model.cleanupAudioPlayer()
                                }
                            } else {
                                // The feed skips heavy audio assets, so download on
                                // demand when the track is opened.
                                HStack(spacing: 8) {
                                    if isLoadingAudio {
                                        ProgressView()
                                    }
                                    Text(isLoadingAudio ? "Loading audio…" : "Audio unavailable")
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
