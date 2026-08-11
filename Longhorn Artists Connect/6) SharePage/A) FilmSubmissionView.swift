import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

struct FilmSubmissionView: View {
    // MARK: - Bindings from Parent
    @Binding var title: String
    @Binding var logline: String
    @Binding var selectedGenres: Set<String>
    @Binding var selectedAgeRating: AgeRating
    @Binding var castInfo: CastInfo
    @Binding var crewInfo: CrewInfo
    @Binding var selectedStudio: String
    @Binding var selectedVideoURL: URL?
    @Binding var videoThumbnail: UIImage?
    @Binding var videoLoadError: Bool
    @Binding var isUploadingVideo: Bool
    
    // MARK: - Local State
    @State private var showVideoPicker = false
    @State private var showDocumentPicker = false
    @State private var showThumbnailPhotoPicker = false
    @State private var thumbnailPhotoItem: PhotosPickerItem?
    @State private var showThumbnailDocumentPicker = false
    @State private var showCastForm = false
    @State private var showCrewForm = false
    
    // MARK: - Constants
    private let availableStudios = ["Collective", "Incubator", "Beyond Frame Productions", "DKA", "Black Lens", "Independent"]
    private let allGenres = [
        "Action", "Adventure", "Animation", "Comedy", "Crime",
        "Documentary", "Drama", "Fantasy", "Horror", "Mystery",
        "Romance", "Sci-Fi", "Thriller", "Western", "Musical",
         "Historical", "Biographical", "Experimental"
    ]
    
    // MARK: - Callbacks
    var onVideoPickerResult: (Result<URL, Error>) -> Void
    var onGenerateThumbnail: (URL) -> Void

    /// Live CloudKit upload state, set once the post is submitted. `nil` while the
    /// user is still filling out the form.
    var uploadPhase: MediaUploadPhase? = nil
    var onRetryUpload: () -> Void = {}

    var body: some View {
        List {
            Section("Upload") {
                filmUploadSection
            }
            
            Section("Details") {
                TextField("Title", text: $title, axis: .vertical)

                TextField("Logline", text: $logline, axis: .vertical)
                    .lineLimit(3...6)
                
                Menu {
                    ForEach(availableStudios, id: \.self) { studio in
                        Button {
                            selectedStudio = studio
                        } label: {
                            HStack {
                                Text(studio)
                                if selectedStudio == studio {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Studio")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(selectedStudio)
                            .lineLimit(1)
                            .foregroundStyle(Color.brandOrange)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(Color.brandOrange)
                    }
                }
                .buttonStyle(.plain)
                
                Menu {
                    ForEach(allGenres, id: \.self) { genre in
                        Button {
                            if selectedGenres.contains(genre) {
                                selectedGenres.remove(genre)
                            } else {
                                selectedGenres.insert(genre)
                            }
                        } label: {
                            HStack {
                                Text(genre)
                                if selectedGenres.contains(genre) {
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
                        let summary = selectedGenres.isEmpty ? "Select" : selectedGenres.sorted().joined(separator: ", ")
                        Text(summary)
                            .lineLimit(1)
                            .foregroundStyle(Color.brandOrange)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(Color.brandOrange)
                    }
                }
                .buttonStyle(.plain)
                
                Button {
                    showCastForm = true
                } label: {
                    HStack {
                        Text("Cast")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(castInfo.summary.isEmpty ? "Add" : "Edited")
                            .foregroundStyle(Color.brandOrange)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.brandOrange)
                    }
                }
                .buttonStyle(.plain)
                
                Button {
                    showCrewForm = true
                } label: {
                    HStack {
                        Text("Crew")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(crewInfo.summary.isEmpty ? "Add" : "Edited")
                            .foregroundStyle(Color.brandOrange)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.brandOrange)
                    }
                }
                .buttonStyle(.plain)
                
                Picker("Age Rating", selection: $selectedAgeRating) {
                    ForEach(AgeRating.allCases) { rating in
                        Text(rating.rawValue).tag(rating)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGray6))
        // Navigation destinations live on the List itself, not on rows inside
        // it: rows in a lazy container may not exist yet, so destinations
        // declared there can be missed by the navigation stack.
        .navigationDestination(isPresented: $showCastForm) {
            CastFormView(cast: $castInfo)
        }
        .navigationDestination(isPresented: $showCrewForm) {
            CrewFormView(crew: $crewInfo)
        }
        .sheet(isPresented: $showVideoPicker) {
            VideoPickerWithiCloudSupport { result in
                onVideoPickerResult(result)
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker(contentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie]) { url in
                onVideoPickerResult(.success(url))
            } onCancel: {
                showDocumentPicker = false
            }
        }
        .photosPicker(isPresented: $showThumbnailPhotoPicker, selection: $thumbnailPhotoItem, matching: .images)
        .onChange(of: thumbnailPhotoItem) { _, newItem in
            loadThumbnail(from: newItem)
        }
        .sheet(isPresented: $showThumbnailDocumentPicker) {
            DocumentPicker(contentTypes: [.image]) { url in
                loadThumbnail(from: url)
            } onCancel: {
                showThumbnailDocumentPicker = false
            }
        }
    }
    
    // MARK: - Film Upload Section
    
    @ViewBuilder
    private var filmUploadSection: some View {
        if let uploadPhase {
            MediaUploadStatusView(phase: uploadPhase, onRetry: onRetryUpload)
        } else if videoLoadError {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Failed to load video")
                        .foregroundStyle(.red)
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    Button("Try Again") {
                        videoLoadError = false
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    
                    Spacer()
                    
                    Button {
                        videoLoadError = false
                        showVideoPicker = true
                    } label: {
                        Label("Photos", systemImage: "photo")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                    
                    Button {
                        videoLoadError = false
                        showDocumentPicker = true
                    } label: {
                        Label("Files", systemImage: "folder")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }
            }
        } else if isUploadingVideo {
            HStack {
                ProgressView()
                    .padding(.trailing, 8)
                Text("Uploading...")
                    .foregroundStyle(.secondary)
            }
        } else {
            videoSelectionRow
            thumbnailSelectionRow
        }
    }

    // MARK: - Upload Rows

    /// "Select video" row: film-strip icon, label, and Photos/Files pickers.
    private var videoSelectionRow: some View {
        HStack {
            Image(systemName: "film")
                .foregroundStyle(.secondary)
            Text(selectedVideoURL == nil ? "Select video" : "Video selected")
                .foregroundStyle(.primary)
            if selectedVideoURL != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
            Spacer()
            HStack(spacing: 12) {
                Button {
                    showVideoPicker = true
                } label: {
                    Label("Photos", systemImage: "photo.stack")
                        .labelStyle(.iconOnly)
                        .symbolRenderingMode(.multicolor)
                }
                .buttonStyle(.bordered)
                .tint(.primary)

                Button {
                    showDocumentPicker = true
                } label: {
                    Label("Files", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
            }
        }
    }

    /// "Select thumbnail" row: thumbnail icon (or chosen image preview), label,
    /// and Photos/Files pickers. Chosen independently of the video.
    private var thumbnailSelectionRow: some View {
        HStack {
            if let thumbnail = videoThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
            Text(videoThumbnail == nil ? "Select thumbnail" : "Thumbnail selected")
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 12) {
                Button {
                    showThumbnailPhotoPicker = true
                } label: {
                    Label("Photos", systemImage: "photo.stack")
                        .labelStyle(.iconOnly)
                        .symbolRenderingMode(.multicolor)
                }
                .buttonStyle(.bordered)
                .tint(.primary)

                Button {
                    showThumbnailDocumentPicker = true
                } label: {
                    Label("Files", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
            }
        }
    }

    // MARK: - Thumbnail Loading

    /// Load a chosen photo (from the Photos picker) as the thumbnail.
    private func loadThumbnail(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run { videoThumbnail = image }
            }
        }
    }

    /// Load a chosen image file (from the Files picker) as the thumbnail.
    private func loadThumbnail(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            videoThumbnail = image
        }
        showThumbnailDocumentPicker = false
    }
}

// MARK: - Film Edit View

/// Metadata-only edit screen for an existing film submission. Media (video/thumbnail)
/// cannot be replaced here — co-located with the film creation form for consistency.
struct FilmEditView: View {
    let submission: Submission
    let onSave: (Submission) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edited: Submission
    @State private var castInfo: CastInfo
    @State private var crewInfo: CrewInfo
    @State private var showCastForm = false
    @State private var showCrewForm = false

    private let availableStudios = ["Collective", "Incubator", "Beyond Frame Productions", "DKA", "Black Lens", "Independent"]
    private let allGenres = [
        "Action", "Adventure", "Animation", "Comedy", "Crime",
        "Documentary", "Drama", "Fantasy", "Horror", "Mystery",
        "Romance", "Sci-Fi", "Thriller", "Western", "Musical",
        "War", "Historical", "Biographical", "Experimental"
    ]

    init(submission: Submission, onSave: @escaping (Submission) -> Void) {
        self.submission = submission
        self.onSave = onSave
        _edited = State(initialValue: submission)
        _castInfo = State(initialValue: CastInfo(orderedEntries: submission.orderedCast))
        _crewInfo = State(initialValue: CrewInfo(orderedEntries: submission.orderedCrew))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $edited.title)
                    TextField("Logline", text: $edited.logline, axis: .vertical)
                        .lineLimit(3...6)

                    Menu {
                        ForEach(availableStudios, id: \.self) { studio in
                            Button {
                                edited.studio = studio
                            } label: {
                                HStack {
                                    Text(studio)
                                    if edited.studio == studio {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Studio")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(edited.studio.isEmpty ? "Select" : edited.studio)
                                .lineLimit(1)
                                .foregroundStyle(Color.brandOrange)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(Color.brandOrange)
                        }
                    }
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(allGenres, id: \.self) { genre in
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
                                .foregroundStyle(Color.brandOrange)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(Color.brandOrange)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        showCastForm = true
                    } label: {
                        HStack {
                            Text("Cast")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(castInfo.summary.isEmpty ? "Add" : "Edited")
                                .foregroundStyle(Color.brandOrange)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.brandOrange)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        showCrewForm = true
                    } label: {
                        HStack {
                            Text("Crew")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(crewInfo.summary.isEmpty ? "Add" : "Edited")
                                .foregroundStyle(Color.brandOrange)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.brandOrange)
                        }
                    }
                    .buttonStyle(.plain)

                    Picker("Age Rating", selection: $edited.ageRating) {
                        ForEach(AgeRating.allCases) { rating in
                            Text(rating.rawValue).tag(rating.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text("Media (video/thumbnail) can't be changed when editing. To replace media, delete this post and create a new one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Film")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showCastForm) {
                CastFormView(cast: $castInfo)
            }
            .navigationDestination(isPresented: $showCrewForm) {
                CrewFormView(crew: $crewInfo)
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
        edited.orderedCast = castInfo.toOrderedEntries()
        edited.orderedCrew = crewInfo.toOrderedEntries()
        onSave(edited)
        dismiss()
    }
}

// MARK: - Placeholder Views
// Note: VideoPickerView, DocumentPickerView, and ThumbnailSelectionView
// are defined in SharedSubmissionTypes.swift and used via sheet modifiers above

// MARK: - Preview

#Preview {
    @Previewable @State var title = ""
    @Previewable @State var logline = ""
    @Previewable @State var selectedGenres: Set<String> = []
    @Previewable @State var selectedAgeRating: AgeRating = .general
    @Previewable @State var castInfo = CastInfo()
    @Previewable @State var crewInfo = CrewInfo()
    @Previewable @State var selectedStudio = "Independent"
    @Previewable @State var selectedVideoURL: URL? = nil
    @Previewable @State var videoThumbnail: UIImage? = nil
    @Previewable @State var videoLoadError = false
    @Previewable @State var isUploadingVideo = false
    
    NavigationStack {
        FilmSubmissionView(
            title: $title,
            logline: $logline,
            selectedGenres: $selectedGenres,
            selectedAgeRating: $selectedAgeRating,
            castInfo: $castInfo,
            crewInfo: $crewInfo,
            selectedStudio: $selectedStudio,
            selectedVideoURL: $selectedVideoURL,
            videoThumbnail: $videoThumbnail,
            videoLoadError: $videoLoadError,
            isUploadingVideo: $isUploadingVideo,
            onVideoPickerResult: { _ in },
            onGenerateThumbnail: { _ in }
        )
        .navigationTitle("Film")
        .navigationBarTitleDisplayMode(.inline)
    }
}
