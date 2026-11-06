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
    /// The additional audio tracks beyond `selectedAudioURL`, which stays track 1. Every
    /// release can carry as many tracks as it likes.
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
    /// Files picker for the next track on the release.
    @State private var showExtraTrackPicker = false
    @State private var showMusicVideoPicker = false
    @State private var showMusicVideoDocumentPicker = false
    @State private var showCreditsForm = false
    @State private var showGenreSelection = false
    @State private var showStreamingLinksForm = false
    @State private var showLyricsForm = false
    /// Photos picker for the album cover.
    @State private var showAlbumCoverPhotoPicker = false
    @State private var albumCoverPhotoItem: PhotosPickerItem?
    /// The open crop editor, if any (album cover or music video).
    @State private var cropRequest: MediaCropRequest?
    /// Set when the user trashes the existing audio while editing, so the row reads as
    /// empty even though an already-posted file may not be on disk to hold a URL for.
    @State private var existingAudioRemoved = false

    // MARK: - Constants
    private let availableGenres = [
        "Pop", "Rock", "Hip Hop", "R&B", "Country",
        "Jazz", "Classical", "Electronic", "Folk", "Blues",
        "Reggae", "Metal", "Punk", "Soul", "Funk",
        "Latin", "Gospel", "Indie", "Alternative"
    ]
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

    /// Editing only: set once CloudKit confirms the post has no `musicAudio` asset, so
    /// the audio row offers "Select audio file" instead of claiming a file is attached.
    var existingAudioMissing: Bool = false

    // MARK: - Tracklist

    /// Every track on the release in running order: the primary audio file first, then
    /// the additional tracks.
    private var allTrackURLs: [URL] {
        (selectedAudioURL.map { [$0] } ?? []) + additionalAudioURLs
    }

    var body: some View {
        List {
            Section("Upload") { uploadSection }

            if uploadPhase == nil {
                detailsSection
                otherSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGray6))
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
        .photosPicker(isPresented: $showAlbumCoverPhotoPicker, selection: $albumCoverPhotoItem, matching: .images)
        .onChange(of: albumCoverPhotoItem) { _, item in
            guard let item else { return }
            MediaDownloadCenter.shared.beginImageLoad()
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data { onAlbumCoverSelected(data) }
                    MediaDownloadCenter.shared.finishImageLoad()
                }
            }
        }
        .mediaCropper($cropRequest)
    }

    // MARK: - Tracklist Editing

    /// Adds a picked file to the release: the first one becomes the primary track (so
    /// single-track playback and the CloudKit `musicAudio` asset keep working unchanged),
    /// every one after that becomes an additional track.
    private func addTrack(_ url: URL) {
        // While editing, a posted track 1 that isn't on disk still holds its slot, so a
        // new pick is an additional track rather than a replacement.
        if selectedAudioURL == nil && !hasExistingAudioOffDisk {
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
        // Audio: the release's tracklist, one row per song plus an "add" row.
        trackListRows

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

                UploadPickerButtons(
                    hasSelection: selectedAlbumCoverData != nil,
                    onPhotos: { showAlbumCoverPhotoPicker = true },
                    onFiles: { showAlbumCoverDocumentPicker = true },
                    onCrop: selectedAlbumCoverData.flatMap(UIImage.init).map { image in
                        {
                            cropRequest = .image(image) { cropped in
                                if let data = cropped.jpegData(compressionQuality: 0.9) {
                                    onAlbumCoverSelected(data)
                                }
                            }
                        }
                    },
                    onRemove: {
                        selectedAlbumCoverData = nil
                        albumCoverPhotoItem = nil
                    }
                )
            }
            }
        }

        // Music Video (Optional)
        VStack(alignment: .leading, spacing: 8) {
            if !isEditing, let fraction = downloadCenter.fraction {
                DownloadProgressRow(fraction: fraction)
            } else {
                HStack(spacing: 12) {
                    if let selectedMusicVideoURL {
                        // First frame of the music video, scaled to fit within the row.
                        UploadRowThumbnail(image: musicVideoThumbnail, placeholderSystemName: "video")
                        Text("Music video attached")
                            .foregroundStyle(.secondary)
                        Spacer()
                        UploadPickerButtons(
                            hasSelection: true,
                            onCrop: {
                                cropRequest = .video(preview: musicVideoThumbnail, load: { selectedMusicVideoURL }) {
                                    onMusicVideoSelected(.success($0))
                                }
                            },
                            onRemove: {
                                self.selectedMusicVideoURL = nil
                                musicVideoThumbnail = nil
                            }
                        )
                    } else {
                        UploadRowThumbnail(image: nil, placeholderSystemName: "film")
                            .frame(width: 24, alignment: .center)
                        Text("Select music video")
                            .foregroundStyle(.primary)
                        Spacer()
                        UploadPickerButtons(
                            hasSelection: false,
                            onPhotos: { showMusicVideoPicker = true },
                            onFiles: { showMusicVideoDocumentPicker = true },
                            onRemove: {}
                        )
                    }
                }
            }
        }
        }
    }

    /// Editing only: the already-posted primary track when there's no local copy to hold
    /// a URL for. It still counts as track 1 unless the user trashed it or CloudKit has
    /// no audio for the post.
    private var hasExistingAudioOffDisk: Bool {
        isEditing && selectedAudioURL == nil && !existingAudioRemoved && !existingAudioMissing
    }

    /// How many tracks the release currently holds, counting a posted track 1 that
    /// isn't on disk.
    private var trackCount: Int {
        allTrackURLs.count + (hasExistingAudioOffDisk ? 1 : 0)
    }

    /// One row per track on the release, plus the row that adds another. Track 1 is the
    /// primary audio file; the rest live in `additionalAudioURLs`.
    @ViewBuilder
    private var trackListRows: some View {
        if hasExistingAudioOffDisk {
            trackRow(number: 1, name: "Audio file attached") {
                existingAudioRemoved = true
            }
        }

        // Numbering continues after a posted track 1 that only lives in CloudKit.
        let numberOffset = hasExistingAudioOffDisk ? 1 : 0
        ForEach(Array(allTrackURLs.enumerated()), id: \.offset) { index, url in
            trackRow(number: index + 1 + numberOffset, name: url.lastPathComponent) {
                if hasExistingAudioOffDisk {
                    // Every local URL is an additional track here, since track 1 is the
                    // posted file; removing one must not promote anything to primary.
                    additionalAudioURLs.remove(at: index)
                } else {
                    removeTrack(at: index)
                }
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
            Text(trackCount == 0 ? "Select song(s)" : "Add another song")
                .foregroundStyle(.primary)
            if trackCount > 0 {
                Text("\(trackCount)")
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

    /// A single tracklist row: waveform icon, "Track N" with the file name beneath, and
    /// a remove button.
    private func trackRow(number: Int, name: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text("Track \(number)")
                    .foregroundStyle(.primary)
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
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
                    Text("Genre(s)")
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

            // The class or organization behind the release. No music classes/orgs are
            // offered yet, so "None" is the only option for now.
            Menu {
                Button("None") {}
            } label: {
                HStack {
                    Text("Class/Org")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("None")
                        .lineLimit(1)
                        .foregroundStyle(Color.brandOrange)
                    Image(systemName: "chevron.up.chevron.down")
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

    /// Streaming links and lyrics, both optional on every release.
    private var otherSection: some View {
        Section("Other") {
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
    /// True once CloudKit confirms the post was published without its audio asset.
    @State private var existingAudioMissing = false

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
                isEditing: true,
                existingAudioMissing: existingAudioMissing
            )
            .task { await checkExistingAudio() }
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

    /// Asks CloudKit whether the post actually has its audio asset — the same lookup the
    /// music card uses — when there's no local copy to vouch for it. Only a definite
    /// "asset missing" flips the row; a network or lookup error keeps assuming the file
    /// is there rather than inviting a needless re-upload.
    private func checkExistingAudio() async {
        guard selectedAudioURL == nil else { return }
        let resolution = await CloudKitManager.shared.streamResolution(submissionID: submission.id, type: .music)
        if case .assetMissing = resolution {
            existingAudioMissing = true
        }
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
    @Previewable @State var additionalAudioURLs: [URL] = []

    NavigationStack {
        MusicSubmissionView(
            title: .constant(""),
            artist: .constant(""),
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
