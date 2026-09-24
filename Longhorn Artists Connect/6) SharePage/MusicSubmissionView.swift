//
//  MusicSubmissionView.swift
//  Longhorn Artists Connect
//
//  Music submission form - handles audio uploads with cover art, credits, and optional music video
//

import SwiftUI
import PhotosUI

struct MusicSubmissionView: View {
    // MARK: - Bindings from Parent
    @Binding var title: String
    @Binding var artist: String
    @Binding var category: String
    @Binding var selectedGenres: Set<String>
    @Binding var releaseYear: String
    @Binding var explicitRating: Bool
    @Binding var recordingCredits: [OrderedEntry]
    @Binding var productionCredits: [OrderedEntry]
    @Binding var spotifyLink: String
    @Binding var appleMusicLink: String
    @Binding var youtubeMusicLink: String
    @Binding var soundcloudLink: String
    @Binding var lyrics: String
    @Binding var selectedAudioURL: URL?
    /// EP/Album only: the additional audio tracks beyond `selectedAudioURL`, which stays
    /// track 1. Ignored (and cleared) by the Song and Performance categories.
    @Binding var additionalAudioURLs: [URL]
    @Binding var selectedAlbumCoverData: Data?
    @Binding var selectedMusicVideoURL: URL?
    @Binding var musicVideoThumbnail: UIImage?
    @Binding var isUploadingAudio: Bool

    /// Live progress of pulling the picked music video out of Photos/Files (incl.
    /// iCloud download). Drives the determinate "Downloading from iCloud…" ring.
    @ObservedObject private var downloadCenter = MediaDownloadCenter.shared

    // MARK: - Local State
    @State private var showAlbumCoverPicker = false
    @State private var showAlbumCoverDocumentPicker = false
    @State private var showAudioDocumentPicker = false
    /// Files picker for an additional EP/Album track.
    @State private var showExtraTrackPicker = false
    @State private var showMusicVideoPicker = false
    @State private var showMusicVideoDocumentPicker = false
    @State private var showCreditsForm = false
    @State private var showGenreSelection = false
    @State private var showStreamingLinksForm = false
    @State private var showLyricsForm = false
    
    // MARK: - Constants
    private let availableGenres = [
        "Pop", "Rock", "Hip Hop", "R&B", "Country",
        "Jazz", "Classical", "Electronic", "Folk", "Blues",
        "Reggae", "Metal", "Punk", "Soul", "Funk",
        "Latin", "Gospel", "Indie", "Alternative"
    ]
    /// What kind of music release this post is. Stored as the raw string so older
    /// records (which have no category) simply read back as empty.
    private let availableCategories = ["Song", "EP", "Album", "Performance"]
    /// Selectable release years: next year down through nine years back (e.g. 2027…2017).
    private var releaseYears: [String] {
        let current = Calendar.current.component(.year, from: Date())
        return (0...10).map { String(current + 1 - $0) }
    }
    
    // MARK: - Callbacks
    var onAudioPickerResult: (Result<URL, Error>) -> Void
    var onAlbumCoverSelected: (Data) -> Void
    var onMusicVideoSelected: (Result<URL, Error>) -> Void

    /// Live CloudKit upload state, set once the post is submitted.
    var uploadPhase: MediaUploadPhase? = nil
    var onRetryUpload: () -> Void = {}

    /// When true this form is editing an existing post: the audio, album art, and music
    /// video stay visible but can't be replaced, so their picker buttons are hidden. Every
    /// other field behaves exactly as it does when creating a post.
    var isEditing: Bool = false

    // MARK: - Category-Driven Fields

    /// EP and Album releases hold a whole tracklist; Song and Performance hold one track.
    private var isMultiTrackRelease: Bool { category == "EP" || category == "Album" }
    /// A live performance isn't on the streaming services, so it has no links.
    private var showsStreamingLinks: Bool { category != "Performance" }
    /// Lyrics belong to a single song, not to a release or a performance.
    private var showsLyrics: Bool { category == "Song" }

    /// Every track on the release in running order: the primary audio file first, then
    /// the additional EP/Album tracks.
    private var allTrackURLs: [URL] {
        (selectedAudioURL.map { [$0] } ?? []) + additionalAudioURLs
    }

    var body: some View {
        List {
            // Category first, and on its own until it's chosen: it decides whether the
            // release takes one track or a tracklist, and which extras it carries.
            Section("Category") { categoryMenu }

            if !category.isEmpty {
                Section("Upload") { uploadSection }

                if uploadPhase == nil {
                    detailsSection
                    if showsStreamingLinks || showsLyrics { otherSection }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGray6))
        // Switching to a single-track category drops any extra tracks, so they can't be
        // silently submitted with a Song or a Performance.
        .onChange(of: category) { _, _ in
            if !isMultiTrackRelease { additionalAudioURLs.removeAll() }
        }
        .navigationDestination(isPresented: $showCreditsForm) {
            MusicCreditsFormView(recordingCredits: $recordingCredits, productionCredits: $productionCredits)
        }
        .navigationDestination(isPresented: $showStreamingLinksForm) {
            MusicStreamingLinksFormView(
                spotifyLink: $spotifyLink,
                appleMusicLink: $appleMusicLink,
                youtubeMusicLink: $youtubeMusicLink,
                soundcloudLink: $soundcloudLink
            )
        }
        .navigationDestination(isPresented: $showLyricsForm) {
            MusicLyricsFormView(lyrics: $lyrics)
        }
        .navigationDestination(isPresented: $showGenreSelection) {
            MusicGenreSelectionView(selectedGenres: $selectedGenres, availableGenres: availableGenres)
        }
        .sheet(isPresented: $showAudioDocumentPicker) {
            DocumentPickerView(allowedTypes: [.audio]) { result in
                onAudioPickerResult(result)
            }
        }
        .sheet(isPresented: $showExtraTrackPicker) {
            DocumentPickerView(allowedTypes: [.audio]) { result in
                if case .success(let url) = result { addTrack(url) }
            }
        }
        .sheet(isPresented: $showAlbumCoverDocumentPicker) {
            DocumentPickerView(allowedTypes: [.image]) { result in
                MediaDownloadCenter.shared.beginImageLoad()
                defer { MediaDownloadCenter.shared.finishImageLoad() }
                if case .success(let url) = result,
                   let data = try? Data(contentsOf: url) {
                    onAlbumCoverSelected(data)
                }
            }
        }
        .sheet(isPresented: $showMusicVideoPicker) {
            VideoPickerView { result in
                onMusicVideoSelected(result)
            }
        }
        .sheet(isPresented: $showMusicVideoDocumentPicker) {
            DocumentPickerView(allowedTypes: [.movie]) { result in
                onMusicVideoSelected(result)
            }
        }
    }

    // MARK: - Tracklist Editing

    /// Adds a picked file to the release: the first one becomes the primary track (so
    /// single-track playback and the CloudKit `musicAudio` asset keep working unchanged),
    /// every one after that becomes an additional track.
    private func addTrack(_ url: URL) {
        if selectedAudioURL == nil {
            onAudioPickerResult(.success(url))
        } else {
            additionalAudioURLs.append(url)
        }
    }

    /// Removes a track by its position in `allTrackURLs`. Removing track 1 promotes the
    /// next track to primary so the release never has a hole at the front.
    private func removeTrack(at index: Int) {
        if index == 0 {
            selectedAudioURL = additionalAudioURLs.isEmpty ? nil : additionalAudioURLs.removeFirst()
        } else if additionalAudioURLs.indices.contains(index - 1) {
            additionalAudioURLs.remove(at: index - 1)
        }
    }

    // MARK: - Upload

    @ViewBuilder
    private var uploadSection: some View {
        if let uploadPhase {
            MediaUploadStatusView(phase: uploadPhase, onRetry: onRetryUpload)
        } else {
        // Audio: a tracklist for an EP/Album, a single file otherwise.
        if isMultiTrackRelease {
            trackListRows
        } else if isUploadingAudio {
            HStack {
                ProgressView()
                    .padding(.trailing, 8)
                Text("Uploading audio...")
                    .foregroundStyle(.secondary)
            }
        } else if selectedAudioURL != nil || isEditing {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .center)
                Text("Audio file selected")
                    .foregroundStyle(.secondary)
                // Checkmark to the right of the audio text once it's uploaded.
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
                Spacer()
                if true { // media pickers available when creating and editing
                    Button {
                        showAudioDocumentPicker = true
                    } label: {
                        Label("Replace", systemImage: "folder")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .center)
                Text("Select audio file")
                    .foregroundStyle(.primary)
                Spacer()

                Button {
                    showAudioDocumentPicker = true
                } label: {
                    Label("Files", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
            }
        }

        // Album Cover
        VStack(alignment: .leading, spacing: 8) {
            if downloadCenter.isLoadingImage {
                ImagePullRow()
            } else {
            HStack(spacing: 12) {
                // Show the chosen cover (aspect ratio preserved, bounded) in
                // place of the icon once one is picked.
                UploadRowThumbnail(image: selectedAlbumCoverData.flatMap(UIImage.init),
                                   placeholderSystemName: "circle.square")
                Text(selectedAlbumCoverData == nil ? "Select album cover" : "Album cover selected")
                    .foregroundStyle(.primary)
                if selectedAlbumCoverData != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.brandOrange)
                }

                Spacer()

                if true { // media pickers available when creating and editing
                    PhotosPicker(selection: Binding(
                        get: { nil },
                        set: { item in
                            if let item = item {
                                MediaDownloadCenter.shared.beginImageLoad()
                                Task {
                                    let data = try? await item.loadTransferable(type: Data.self)
                                    await MainActor.run {
                                        if let data { onAlbumCoverSelected(data) }
                                        MediaDownloadCenter.shared.finishImageLoad()
                                    }
                                }
                            }
                        }
                    ), matching: .images) {
                        Label("Photos", systemImage: "photo.stack")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)

                    Button {
                        showAlbumCoverDocumentPicker = true
                    } label: {
                        Label("Files", systemImage: "folder")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }
            }
            }
        }

        // Music Video (Optional)
        VStack(alignment: .leading, spacing: 8) {
            if !isEditing, let fraction = downloadCenter.fraction {
                DownloadProgressRow(fraction: fraction)
            } else if selectedMusicVideoURL != nil {
                HStack {
                    // First frame of the music video, scaled to fit within the row.
                    UploadRowThumbnail(image: musicVideoThumbnail, placeholderSystemName: "video")
                    Text("Music video attached")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if true { // media pickers available when creating and editing
                        Button {
                            showMusicVideoPicker = true
                        } label: {
                            Label("Replace", systemImage: "photo")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)

                        Button {
                            showMusicVideoDocumentPicker = true
                        } label: {
                            Label("Replace", systemImage: "folder")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    UploadRowThumbnail(image: nil, placeholderSystemName: "film")
                        .frame(width: 24, alignment: .center)
                    Text("Select music video")
                        .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        showMusicVideoPicker = true
                    } label: {
                        Label("Photos", systemImage: "photo.stack")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)

                    Button {
                        showMusicVideoDocumentPicker = true
                    } label: {
                        Label("Files", systemImage: "folder")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }
            }
        }
        }
    }

    /// One row per track on an EP/Album, plus the row that adds another. Track 1 is the
    /// primary audio file; the rest live in `additionalAudioURLs`.
    @ViewBuilder
    private var trackListRows: some View {
        ForEach(Array(allTrackURLs.enumerated()), id: \.offset) { index, url in
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Track \(index + 1)")
                        .foregroundStyle(.primary)
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button {
                    removeTrack(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }

        if isUploadingAudio {
            HStack {
                ProgressView()
                    .padding(.trailing, 8)
                Text("Uploading audio...")
                    .foregroundStyle(.secondary)
            }
        }

        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            Text(allTrackURLs.isEmpty ? "Select songs" : "Add another song")
                .foregroundStyle(.primary)
            if !allTrackURLs.isEmpty {
                Text("\(allTrackURLs.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandOrange)
            }
            Spacer()
            Button {
                showExtraTrackPicker = true
            } label: {
                Label("Files", systemImage: "folder")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .tint(.primary)
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        Section("Details") {
            TextField("Title", text: $title, axis: .vertical)
            // Artist can be credited to a registered user: suggests matching
            // profiles as you type and autofills their exact name on tap.
            CreditNameField(placeholder: "Artist", text: $artist)
            
            Button {
                showGenreSelection = true
            } label: {
                HStack {
                    Text("Genres")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(selectedGenres.isEmpty ? "Select" : selectedGenres.sorted().joined(separator: ", "))
                        .lineLimit(1)
                        .foregroundStyle(Color.brandOrange)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.brandOrange)
                }
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(releaseYears, id: \.self) { year in
                    Button {
                        releaseYear = year
                    } label: {
                        HStack {
                            Text(year)
                            if releaseYear == year {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text("Release Year")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(releaseYear.isEmpty ? "Select" : releaseYear)
                        .lineLimit(1)
                        .foregroundStyle(Color.brandOrange)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.brandOrange)
                }
            }
            .buttonStyle(.plain)

            Button {
                showCreditsForm = true
            } label: {
                HStack {
                    Text("Credits")
                        .foregroundStyle(.primary)
                    Spacer()
                    // Only count credits with an actual name — the form pre-seeds
                    // empty role rows, which shouldn't read as "Edited".
                    let hasCredits = recordingCredits.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                        || productionCredits.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                    Text(hasCredits ? "Edited" : "Add")
                        .foregroundStyle(Color.brandOrange)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.brandOrange)
                }
            }
            .buttonStyle(.plain)

            Toggle("Explicit", isOn: $explicitRating)
        }
    }

    // MARK: - Other

    /// Streaming links (every category except a live Performance) and lyrics (a single
    /// Song only). Hidden entirely when the category carries neither.
    @ViewBuilder
    private var otherSection: some View {
        Section("Other") {
            if showsStreamingLinks {
                Button {
                    showStreamingLinksForm = true
                } label: {
                    HStack {
                        Text("Streaming Links")
                            .foregroundStyle(.primary)
                        Spacer()
                        let hasLinks = !spotifyLink.isEmpty || !appleMusicLink.isEmpty || !youtubeMusicLink.isEmpty || !soundcloudLink.isEmpty
                        Text(hasLinks ? "Edited" : "Add")
                            .foregroundStyle(Color.brandOrange)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.brandOrange)
                    }
                }
                .buttonStyle(.plain)
            }

            if showsLyrics {
                Button {
                    showLyricsForm = true
                } label: {
                    HStack {
                        Text("Lyrics")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add" : "Edited")
                            .foregroundStyle(Color.brandOrange)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.brandOrange)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Category

    private var categoryMenu: some View {
        Menu {
            ForEach(availableCategories, id: \.self) { option in
                Button {
                    category = option
                } label: {
                    HStack {
                        Text(option)
                        if category == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text("Category")
                    .foregroundStyle(.primary)
                Spacer()
                Text(category.isEmpty ? "Select Category" : category)
                    .lineLimit(1)
                    .foregroundStyle(Color.brandOrange)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Music Streaming Links Form View

struct MusicStreamingLinksFormView: View {
    @Binding var spotifyLink: String
    @Binding var appleMusicLink: String
    @Binding var youtubeMusicLink: String
    @Binding var soundcloudLink: String

    var body: some View {
        List {
            Section {
                StreamingLinkRow(label: "Spotify", placeholder: "Spotify Link", text: $spotifyLink)
                StreamingLinkRow(label: "Apple Music", placeholder: "Apple Music Link", text: $appleMusicLink)
                StreamingLinkRow(label: "YouTube Music", placeholder: "YouTube Music Link", text: $youtubeMusicLink)
                StreamingLinkRow(label: "SoundCloud", placeholder: "SoundCloud Link", text: $soundcloudLink)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGray6))
        .navigationTitle("Streaming Links")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A single streaming-link row, styled like the Music Credits form: the service
/// name stays visible as a label above the field, so you can always tell which
/// link you're entering even after filling it in.
struct StreamingLinkRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Music Lyrics Form View

/// Full-screen editor for a track's lyrics: a single large, multi-line text box the
/// user types into. The entered lyrics appear at the bottom of the music card below
/// the streaming links.
struct MusicLyricsFormView: View {
    @Binding var lyrics: String

    var body: some View {
        List {
            Section {
                TextField("Enter lyrics", text: $lyrics, axis: .vertical)
                    .lineLimit(20, reservesSpace: true)
            } footer: {
                Text("Lyrics appear at the bottom of your music card, below the streaming links.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGray6))
        .navigationTitle("Lyrics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Music Genre Selection View

struct MusicGenreSelectionView: View {
    @Binding var selectedGenres: Set<String>
    let availableGenres: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var customGenre: String = ""
    @State private var showAddCustomGenre: Bool = false
    
    var body: some View {
        List {
            Section("Select Genres") {
                ForEach(availableGenres, id: \.self) { genre in
                    Button {
                        if selectedGenres.contains(genre) {
                            selectedGenres.remove(genre)
                        } else {
                            selectedGenres.insert(genre)
                        }
                    } label: {
                        HStack {
                            Text(genre)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedGenres.contains(genre) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.brandOrange)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Section {
                if showAddCustomGenre {
                    HStack {
                        TextField("Custom genre", text: $customGenre, axis: .vertical)
                        Button("Add") {
                            if !customGenre.isEmpty {
                                selectedGenres.insert(customGenre)
                                customGenre = ""
                                showAddCustomGenre = false
                            }
                        }
                        .foregroundStyle(Color.brandOrange)
                    }
                } else {
                    Button {
                        showAddCustomGenre = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.brandOrange)
                            Text("Add Custom Genre")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Genres")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
    }
}

// MARK: - Music Edit View

/// Edit screen for an existing music submission. Reuses `MusicSubmissionView` so the form
/// is identical to creating a track; only the already-submitted audio, album art, and
/// music video are shown read-only and can't be replaced.
struct MusicEditView: View {
    let submission: Submission
    let onSave: (Submission) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edited: Submission
    @State private var selectedGenres: Set<String>
    @State private var releaseYear: String

    // Media bindings the form needs; in edit mode the pickers are hidden, so these only
    // drive the read-only preview of the existing media.
    @State private var selectedAudioURL: URL?
    /// EP/Album tracks beyond the first, seeded from whatever's already on disk.
    @State private var additionalAudioURLs: [URL]
    @State private var selectedAlbumCoverData: Data?
    @State private var selectedMusicVideoURL: URL?
    @State private var musicVideoThumbnail: UIImage?
    @State private var isUploadingAudio = false
    /// Track which file assets the user replaced so `save()` copies/re-uploads them.
    @State private var audioWasReplaced = false
    @State private var musicVideoWasReplaced = false

    init(submission: Submission, onSave: @escaping (Submission) -> Void) {
        self.submission = submission
        self.onSave = onSave
        _edited = State(initialValue: submission)
        _selectedGenres = State(initialValue: Set(submission.genres))
        _releaseYear = State(initialValue: submission.releaseYear)
        _selectedAudioURL = State(initialValue: submission.audioURL)
        _additionalAudioURLs = State(initialValue: (submission.musicTrackFileNames ?? [])
            .compactMap { FileManager.default.mediaFileURL(named: $0) })
        _selectedAlbumCoverData = State(initialValue: submission.thumbnailData)
        _selectedMusicVideoURL = State(initialValue: submission.videoURL)
    }

    var body: some View {
        NavigationStack {
            MusicSubmissionView(
                title: $edited.title,
                artist: $edited.artist,
                category: $edited.musicCategory,
                selectedGenres: $selectedGenres,
                releaseYear: $releaseYear,
                explicitRating: $edited.explicit,
                recordingCredits: $edited.orderedRecording,
                productionCredits: $edited.orderedProduction,
                spotifyLink: $edited.spotifyLink,
                appleMusicLink: $edited.appleMusicLink,
                youtubeMusicLink: $edited.youtubeMusicLink,
                soundcloudLink: $edited.soundcloudLink,
                lyrics: $edited.lyrics,
                selectedAudioURL: $selectedAudioURL,
                additionalAudioURLs: $additionalAudioURLs,
                selectedAlbumCoverData: $selectedAlbumCoverData,
                selectedMusicVideoURL: $selectedMusicVideoURL,
                musicVideoThumbnail: $musicVideoThumbnail,
                isUploadingAudio: $isUploadingAudio,
                onAudioPickerResult: { result in
                    if case .success(let url) = result {
                        selectedAudioURL = url
                        audioWasReplaced = true
                    }
                },
                onAlbumCoverSelected: { data in selectedAlbumCoverData = data },
                onMusicVideoSelected: { result in handleMusicVideoPick(result) },
                isEditing: true
            )
            .navigationTitle("Edit Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(edited.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDragIndicator(.hidden)
    }

    /// A newly-picked music video during editing: preview its first frame and remember
    /// to copy/re-upload it on save.
    private func handleMusicVideoPick(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        selectedMusicVideoURL = url
        musicVideoWasReplaced = true
        Task {
            let frame = await VideoThumbnailGenerator.generateThumbnail(from: url, at: 0)
            await MainActor.run { musicVideoThumbnail = frame }
        }
    }

    private func save() {
        guard !edited.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        edited.genres = Array(selectedGenres)
        edited.releaseYear = releaseYear

        // Drop the pre-seeded role rows the credits form fills in — an entry with no
        // name isn't a real credit and shouldn't be saved or shown on the card.
        edited.orderedRecording = edited.orderedRecording.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        edited.orderedProduction = edited.orderedProduction.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }

        // Persist replaced file assets into Documents so they re-upload to CloudKit.
        if audioWasReplaced, let url = selectedAudioURL {
            let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
            if let name = persistEditedMediaFile(from: url, as: "\(edited.id.uuidString)_audio.\(ext)") {
                edited.audioFileName = name
            }
        }
        if musicVideoWasReplaced, let url = selectedMusicVideoURL {
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            if let name = persistEditedMediaFile(from: url, as: "video_\(edited.id.uuidString).\(ext)") {
                edited.videoFileName = name
            }
        }

        // EP/Album tracks beyond the first. Rewritten on every save so added, removed
        // and reordered tracks all land under the right names.
        let trackNames = persistMusicTracks(additionalAudioURLs, submissionID: edited.id)
        edited.musicTrackFileNames = trackNames.isEmpty ? nil : trackNames

        // Album cover art is stored as the submission's thumbnail data.
        edited.thumbnailData = selectedAlbumCoverData

        onSave(edited)
        dismiss()
    }
}

#Preview {
    // Category-backed state rather than a constant, so the canvas can switch between
    // Song / EP / Album / Performance and exercise the fields each one shows.
    @Previewable @State var category = "Song"
    @Previewable @State var additionalAudioURLs: [URL] = []

    NavigationStack {
        MusicSubmissionView(
            title: .constant(""),
            artist: .constant(""),
            category: $category,
            selectedGenres: .constant([]),
            releaseYear: .constant(""),
            explicitRating: .constant(false),
            recordingCredits: .constant([]),
            productionCredits: .constant([]),
            spotifyLink: .constant(""),
            appleMusicLink: .constant(""),
            youtubeMusicLink: .constant(""),
            soundcloudLink: .constant(""),
            lyrics: .constant(""),
            selectedAudioURL: .constant(nil),
            additionalAudioURLs: $additionalAudioURLs,
            selectedAlbumCoverData: .constant(nil),
            selectedMusicVideoURL: .constant(nil),
            musicVideoThumbnail: .constant(nil),
            isUploadingAudio: .constant(false),
            onAudioPickerResult: { _ in },
            onAlbumCoverSelected: { _ in },
            onMusicVideoSelected: { _ in }
        )
        .navigationTitle("Music")
        .navigationBarTitleDisplayMode(.inline)
    }
}
