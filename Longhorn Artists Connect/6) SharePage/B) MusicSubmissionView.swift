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
    @Binding var explicitRating: Bool
    @Binding var recordingCredits: [OrderedEntry]
    @Binding var productionCredits: [OrderedEntry]
    @Binding var spotifyLink: String
    @Binding var appleMusicLink: String
    @Binding var youtubeMusicLink: String
    @Binding var selectedAudioURL: URL?
    @Binding var selectedAlbumCoverData: Data?
    @Binding var selectedMusicVideoURL: URL?
    @Binding var musicVideoThumbnail: UIImage?
    @Binding var isUploadingAudio: Bool
    
    // MARK: - Local State
    @State private var showAlbumCoverPicker = false
    @State private var showAlbumCoverDocumentPicker = false
    @State private var showAudioDocumentPicker = false
    @State private var showMusicVideoPicker = false
    @State private var showMusicVideoDocumentPicker = false
    @State private var showCreditsForm = false
    @State private var showGenreSelection = false
    @State private var showStreamingLinksForm = false
    
    // MARK: - Constants
    private let availableGenres = [
        "Pop", "Rock", "Hip Hop", "R&B", "Country",
        "Jazz", "Classical", "Electronic", "Folk", "Blues",
        "Reggae", "Metal", "Punk", "Soul", "Funk",
        "Latin", "Gospel", "Indie", "Alternative"
    ]
    
    // MARK: - Callbacks
    var onAudioPickerResult: (Result<URL, Error>) -> Void
    var onAlbumCoverSelected: (Data) -> Void
    var onMusicVideoSelected: (Result<URL, Error>) -> Void

    /// Live CloudKit upload state, set once the post is submitted.
    var uploadPhase: MediaUploadPhase? = nil
    var onRetryUpload: () -> Void = {}

    var body: some View {
        List {
            Section("Upload") {
                if let uploadPhase {
                    MediaUploadStatusView(phase: uploadPhase, onRetry: onRetryUpload)
                } else {
                // Audio
                if isUploadingAudio {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Uploading audio...")
                            .foregroundStyle(.secondary)
                    }
                } else if selectedAudioURL != nil {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Audio file attached")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showAudioDocumentPicker = true
                        } label: {
                            Label("Replace", systemImage: "folder")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
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
                    if let coverData = selectedAlbumCoverData, let image = UIImage(data: coverData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 200)
                            .cornerRadius(8)
                    }
                    
                    HStack(spacing: 12) {
                        Image(systemName: "circle.square")
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .center)
                        Text("Select album cover")
                            .foregroundStyle(.primary)

                        Spacer()
                        
                        PhotosPicker(selection: Binding(
                            get: { nil },
                            set: { item in
                                if let item = item {
                                    Task {
                                        if let data = try? await item.loadTransferable(type: Data.self) {
                                            onAlbumCoverSelected(data)
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
                
                // Music Video (Optional)
                VStack(alignment: .leading, spacing: 8) {
                    if let musicVideoURL = selectedMusicVideoURL {
                        if let thumbnail = musicVideoThumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .cornerRadius(8)
                        }
                        HStack {
                            Image(systemName: "video")
                                .foregroundStyle(.secondary)
                            Text("Music video attached")
                                .foregroundStyle(.secondary)
                            Spacer()
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
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "film")
                                .foregroundStyle(.secondary)
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

            Section("Details") {
                TextField("Title", text: $title, axis: .vertical)
                TextField("Artist", text: $artist, axis: .vertical)
                
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
                
                Toggle("Explicit", isOn: $explicitRating)
                
                Button {
                    showCreditsForm = true
                } label: {
                    HStack {
                        Text("Credits")
                            .foregroundStyle(.primary)
                        Spacer()
                        let hasCredits = !recordingCredits.isEmpty || !productionCredits.isEmpty
                        Text(hasCredits ? "Edited" : "Add")
                            .foregroundStyle(Color.brandOrange)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.brandOrange)
                    }
                }
                .buttonStyle(.plain)
            }

            Section("Other") {
                Button {
                    showStreamingLinksForm = true
                } label: {
                    HStack {
                        Text("Streaming Links")
                            .foregroundStyle(.primary)
                        Spacer()
                        let hasLinks = !spotifyLink.isEmpty || !appleMusicLink.isEmpty || !youtubeMusicLink.isEmpty
                        Text(hasLinks ? "Edited" : "Add")
                            .foregroundStyle(Color.brandOrange)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.brandOrange)
                    }
                }
                .buttonStyle(.plain)
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
                youtubeMusicLink: $youtubeMusicLink
            )
        }
        .navigationDestination(isPresented: $showGenreSelection) {
            MusicGenreSelectionView(selectedGenres: $selectedGenres, availableGenres: availableGenres)
        }
        .sheet(isPresented: $showAudioDocumentPicker) {
            DocumentPickerView(allowedTypes: [.audio]) { result in
                onAudioPickerResult(result)
            }
        }
        .sheet(isPresented: $showAlbumCoverDocumentPicker) {
            DocumentPickerView(allowedTypes: [.image]) { result in
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
}

// MARK: - Music Streaming Links Form View

struct MusicStreamingLinksFormView: View {
    @Binding var spotifyLink: String
    @Binding var appleMusicLink: String
    @Binding var youtubeMusicLink: String

    var body: some View {
        List {
            Section {
                StreamingLinkRow(label: "Spotify", placeholder: "Spotify Link", text: $spotifyLink)
                StreamingLinkRow(label: "Apple Music", placeholder: "Apple Music Link", text: $appleMusicLink)
                StreamingLinkRow(label: "YouTube Music", placeholder: "YouTube Music Link", text: $youtubeMusicLink)
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
                        TextField("Custom genre", text: $customGenre)
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

/// Metadata-only edit screen for an existing music submission. Audio, album art, and
/// music video cannot be replaced here — co-located with the music creation form.
struct MusicEditView: View {
    let submission: Submission
    let onSave: (Submission) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edited: Submission
    @State private var showCreditsForm = false

    private let availableGenres = [
        "Pop", "Rock", "Hip Hop", "R&B", "Country",
        "Jazz", "Classical", "Electronic", "Folk", "Blues",
        "Reggae", "Metal", "Punk", "Soul", "Funk",
        "Latin", "Gospel", "Indie", "Alternative"
    ]

    init(submission: Submission, onSave: @escaping (Submission) -> Void) {
        self.submission = submission
        self.onSave = onSave
        _edited = State(initialValue: submission)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $edited.title)
                    TextField("Artist", text: $edited.artist)

                    Menu {
                        ForEach(availableGenres, id: \.self) { genre in
                            Button {
                                toggleGenre(genre)
                            } label: {
                                HStack {
                                    Text(genre)
                                    if edited.genres.contains(genre) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Genres")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(edited.genres.isEmpty ? "Select" : edited.genres.sorted().joined(separator: ", "))
                                .lineLimit(1)
                                .foregroundStyle(edited.genres.isEmpty ? .secondary : Color.brandOrange)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(Color.brandOrange)
                        }
                    }
                    .buttonStyle(.plain)

                    Toggle("Explicit", isOn: $edited.explicit)

                    Button {
                        showCreditsForm = true
                    } label: {
                        HStack {
                            Text("Credits")
                                .foregroundStyle(.primary)
                            Spacer()
                            let hasCredits = !edited.orderedRecording.isEmpty || !edited.orderedProduction.isEmpty
                            Text(hasCredits ? "Edited" : "Add")
                                .foregroundStyle(Color.brandOrange)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.brandOrange)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Streaming Links (Optional)") {
                    StreamingLinkRow(label: "Spotify", placeholder: "Spotify Link", text: $edited.spotifyLink)
                    StreamingLinkRow(label: "Apple Music", placeholder: "Apple Music Link", text: $edited.appleMusicLink)
                    StreamingLinkRow(label: "YouTube Music", placeholder: "YouTube Music Link", text: $edited.youtubeMusicLink)
                }

                Section {
                    Text("Audio, album art, and music video can't be changed when editing. To replace media, delete this post and create a new one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Music")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showCreditsForm) {
                MusicCreditsFormView(
                    recordingCredits: $edited.orderedRecording,
                    productionCredits: $edited.orderedProduction
                )
            }
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
    }

    private func toggleGenre(_ genre: String) {
        if let index = edited.genres.firstIndex(of: genre) {
            edited.genres.remove(at: index)
        } else {
            edited.genres.append(genre)
        }
    }

    private func save() {
        guard !edited.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onSave(edited)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        MusicSubmissionView(
            title: .constant(""),
            artist: .constant(""),
            selectedGenres: .constant([]),
            explicitRating: .constant(false),
            recordingCredits: .constant([]),
            productionCredits: .constant([]),
            spotifyLink: .constant(""),
            appleMusicLink: .constant(""),
            youtubeMusicLink: .constant(""),
            selectedAudioURL: .constant(nil),
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
