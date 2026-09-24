import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

struct FilmSubmissionView: View {
    // MARK: - Bindings from Parent
    @Binding var title: String
    @Binding var logline: String
    @Binding var selectedGenres: Set<String>
    @Binding var releaseYear: String
    @Binding var selectedAgeRating: AgeRating
    @Binding var castInfo: CastInfo
    @Binding var crewInfo: CrewInfo
    @Binding var selectedStudio: String
    @Binding var selectedVideoURL: URL?
    /// The video's own first frame, shown in the "video" row. This is independent of the
    /// poster/thumbnail so picking a custom thumbnail doesn't change what the video row shows.
    @Binding var videoFirstFrame: UIImage?
    @Binding var videoThumbnail: UIImage?
    /// Set to true when the user picks their own thumbnail, so the auto-generated
    /// first-frame thumbnail doesn't overwrite it.
    @Binding var videoThumbnailIsCustom: Bool
    @Binding var videoLoadError: Bool
    @Binding var isUploadingVideo: Bool
    /// When true the film is "festival-bound": kept private (hidden from the public feed
    /// and search, shown only on a credited person's profile or when sent directly).
    @Binding var festivalBound: Bool

    // MARK: - Film Extras Bindings
    /// A single trailer video, separate from the feature film video above.
    @Binding var selectedTrailerURL: URL?
    /// The trailer's first frame, shown as its row preview.
    @Binding var trailerFirstFrame: UIImage?
    /// Behind-the-scenes photos (any number, images only).
    @Binding var btsImages: [UIImage]
    /// Promotional stills (any number, images only).
    @Binding var stillImages: [UIImage]

    // MARK: - Local State
    /// Live progress of pulling the picked video out of Photos/Files (incl. iCloud
    /// download). Drives the determinate "Downloading from iCloud…" ring.
    @ObservedObject private var downloadCenter = MediaDownloadCenter.shared
    @State private var showVideoPicker = false
    @State private var showDocumentPicker = false
    @State private var showThumbnailPhotoPicker = false
    @State private var thumbnailPhotoItem: PhotosPickerItem?
    @State private var showThumbnailDocumentPicker = false
    @State private var showCastForm = false
    @State private var showCrewForm = false
    /// Hides the optional extras (trailer, BTS photos, stills) behind a "More" button
    /// until the user taps to reveal them.
    @State private var showMoreUpload = false

    // Film extras pickers
    @State private var showTrailerPicker = false
    @State private var showTrailerDocumentPicker = false
    @State private var btsPhotoItems: [PhotosPickerItem] = []
    @State private var showBTSPhotoPicker = false
    @State private var showBTSDocumentPicker = false
    @State private var stillPhotoItems: [PhotosPickerItem] = []
    @State private var showStillPhotoPicker = false
    @State private var showStillDocumentPicker = false
    
    /// The production category, derived from `selectedStudio` on appear and written back
    /// to it whenever the user changes category. Not persisted on its own. `nil` until a
    /// category is picked — the rest of the form stays hidden until then.
    @State private var selectedCategory: FilmCategory?

    // MARK: - Constants
    /// Studios shown when the category is "Org Project".
    private let availableStudios = ["Collective", "Incubator", "Beyond Frame Productions", "DKA", "Black Lens"]
    /// Production classes shown when the category is "Class Project". Each is listed by
    /// course code and name (e.g. "RTF 304D Intro to Production"); the home feed credits them
    /// by code alone.
    private let availableClasses = ProductionClassCatalog.names
    private let allGenres = [
        "Action", "Adventure", "Advertisement", "Animation", "Biographical", "Comedy", "Coming-of-Age", "Crime",
        "Documentary", "Drama","Epic", "Fantasy", "Feel-Good","Heist", "Historical", "Horror", "Musical", "Mystery","Puppetry", "Romance", "Satire", "Sci-Fi", "Sports", "Stop-Motion", "Thriller", "Western",  "Experimental"
    ]
    /// Selectable release years: next year down through nine years back (e.g. 2027…2017).
    private var releaseYears: [String] {
        let current = Calendar.current.component(.year, from: Date())
        return (0...10).map { String(current + 1 - $0) }
    }
    
    // MARK: - Callbacks
    var onVideoPickerResult: (Result<URL, Error>) -> Void
    var onGenerateThumbnail: (URL) -> Void
    /// Called when a trailer video is picked (Photos or Files); the parent copies it in
    /// and generates its first-frame preview, mirroring the feature-video flow.
    var onTrailerPickerResult: (Result<URL, Error>) -> Void = { _ in }

    /// Live CloudKit upload state, set once the post is submitted. `nil` while the
    /// user is still filling out the form.
    var uploadPhase: MediaUploadPhase? = nil
    var onRetryUpload: () -> Void = {}

    /// When true this form is editing an existing post: the already-submitted media
    /// (video/thumbnail) stays visible but can't be replaced, so the picker buttons are
    /// hidden. Every other field behaves exactly as it does when creating a post.
    var isEditing: Bool = false

    var body: some View {
        List {
            // Category first, and on its own until it's chosen: the rest of the form
            // depends on it (Org films pick a studio, class films pick a class).
            Section("Category") {
                categoryMenu
            }

            if selectedCategory != nil {
                Section("Upload") {
                    filmUploadSection
                }

                Section("Details") {
                    TextField("Title", text: $title, axis: .vertical)

                    // Only Org and Class films carry this; independent films have no such field.
                    studioOrClassField

                    TextField("Logline", text: $logline, axis: .vertical)
                        .lineLimit(3...6)

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

                Section {
                    Toggle("Festival-Bound", isOn: $festivalBound)
                        .tint(Color.brandOrange)
                } header: {
                    Text("Other")
                } footer: {
                    Text("Keeps the actual film private while still showing thumbnail, logline, credits, etc. Submission can be editied at any time to be publicly visible when ready.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGray6))
        // Seed the category from the stored studio value so resuming a draft or editing
        // an existing film shows the right category and field.
        .onAppear { deriveCategory() }
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
        // Trailer pickers (single video).
        .sheet(isPresented: $showTrailerPicker) {
            VideoPickerWithiCloudSupport { result in
                onTrailerPickerResult(result)
            }
        }
        .sheet(isPresented: $showTrailerDocumentPicker) {
            DocumentPicker(contentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie]) { url in
                onTrailerPickerResult(.success(url))
            } onCancel: {
                showTrailerDocumentPicker = false
            }
        }
        // BTS photos & stills (multiple images, no videos). `maxSelectionCount: 0` = unlimited.
        .photosPicker(isPresented: $showBTSPhotoPicker, selection: $btsPhotoItems,
                      maxSelectionCount: 0, matching: .images)
        .onChange(of: btsPhotoItems) { _, newItems in
            loadExtraImages(from: newItems, into: $btsImages)
            btsPhotoItems = []
        }
        .photosPicker(isPresented: $showStillPhotoPicker, selection: $stillPhotoItems,
                      maxSelectionCount: 0, matching: .images)
        .onChange(of: stillPhotoItems) { _, newItems in
            loadExtraImages(from: newItems, into: $stillImages)
            stillPhotoItems = []
        }
        // Files-app pickers for BTS photos & stills (multiple images, no videos).
        .sheet(isPresented: $showBTSDocumentPicker) {
            MultiImageDocumentPicker { images in
                btsImages.append(contentsOf: images)
            } onCancel: {
                showBTSDocumentPicker = false
            }
        }
        .sheet(isPresented: $showStillDocumentPicker) {
            MultiImageDocumentPicker { images in
                stillImages.append(contentsOf: images)
            } onCancel: {
                showStillDocumentPicker = false
            }
        }
    }
    
    // MARK: - Category

    /// "Category" row: Org / Class / Independent. Changing it resets the stored studio so
    /// a value from the previous category doesn't linger.
    private var categoryMenu: some View {
        Menu {
            ForEach(FilmCategory.allCases) { category in
                Button {
                    applyCategory(category)
                } label: {
                    HStack {
                        Text(category.rawValue)
                        if selectedCategory == category {
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
                Text(selectedCategory?.rawValue ?? "Select Category")
                    .lineLimit(1)
                    .foregroundStyle(Color.brandOrange)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
        }
        .buttonStyle(.plain)
    }

    /// The studio/class selector, shown in Details only for Org (studios) and Class
    /// (classes) categories. Independent films have no such field.
    @ViewBuilder
    private var studioOrClassField: some View {
        switch selectedCategory {
        case .org:
            studioSelectionMenu(label: "Studio", options: availableStudios)
        case .classProject:
            studioSelectionMenu(label: "Class", options: availableClasses)
        case .independent, nil:
            EmptyView()
        }
    }

    /// A single-select menu bound to `selectedStudio`, reused for both the studio and
    /// class lists.
    private func studioSelectionMenu(label: String, options: [String]) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selectedStudio = option
                } label: {
                    HStack {
                        Text(option)
                        if selectedStudio == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                Text(selectedStudio.isEmpty ? "Select" : selectedStudio)
                    .lineLimit(1)
                    .foregroundStyle(Color.brandOrange)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
        }
        .buttonStyle(.plain)
    }

    /// Derives the category from the current `selectedStudio` value: a class name means
    /// Class, "Independent" means Independent, anything else means Org. An empty studio
    /// means nothing has been chosen yet, so the category stays unset and the rest of the
    /// form stays hidden.
    private func deriveCategory() {
        // Only seed once. Org/Class both clear `selectedStudio` when picked, so re-deriving
        // after the view reappears (e.g. returning from the Cast page) would wipe the
        // user's choice.
        guard selectedCategory == nil else { return }

        if let productionClass = ProductionClassCatalog.match(selectedStudio) {
            selectedCategory = .classProject
            // Films posted before the classes were renamed store the old name, which
            // wouldn't match any menu entry. Upgrade it to the canonical "code + name"
            // so the picker shows it as selected.
            selectedStudio = productionClass.fullName
        } else if selectedStudio.isEmpty {
            selectedCategory = nil
        } else if selectedStudio == "Independent" {
            selectedCategory = .independent
        } else {
            selectedCategory = .org
        }
    }

    /// Applies a newly-chosen category and resets `selectedStudio` so it never holds a
    /// value that doesn't belong to the new category's field.
    private func applyCategory(_ category: FilmCategory) {
        selectedCategory = category
        switch category {
        case .independent:
            selectedStudio = "Independent"
        case .org, .classProject:
            selectedStudio = ""
        }
    }

    // MARK: - Film Upload Section

    @ViewBuilder
    private var filmUploadSection: some View {
        if let uploadPhase {
            MediaUploadStatusView(phase: uploadPhase, onRetry: onRetryUpload)
        } else {
            // The video's loading/error state is scoped to the video field only, so the
            // thumbnail field stays visible (and usable) while the video downloads.
            videoField
            thumbnailSelectionRow
            if showMoreUpload {
                trailerSelectionRow
                btsPhotosRow
                stillsRow
            } else {
                Button {
                    withAnimation { showMoreUpload = true }
                } label: {
                    HStack {
                        Text("More")
                            .foregroundStyle(Color.brandOrange)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(Color.brandOrange)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The "video" field: shows its own download/upload/error state in place of the
    /// video row, without hiding the rest of the Upload section.
    @ViewBuilder
    private var videoField: some View {
        if isEditing {
            // Editing: show the existing video (as its poster frame), read-only.
            videoSelectionRow
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
        } else if let fraction = downloadCenter.fraction {
            DownloadProgressRow(fraction: fraction)
        } else if isUploadingVideo {
            HStack {
                ProgressView()
                    .padding(.trailing, 8)
                Text("Uploading...")
                    .foregroundStyle(.secondary)
            }
        } else {
            videoSelectionRow
        }
    }

    // MARK: - Upload Rows

    /// "Select video" row: film-strip icon, label, and Photos/Files pickers.
    private var videoSelectionRow: some View {
        HStack {
            // Show the video's first frame (the auto-generated thumbnail) once a video
            // is picked, scaled to fit so it stays within the row; film icon otherwise.
            UploadRowThumbnail(image: (selectedVideoURL == nil && !isEditing) ? nil : videoFirstFrame,
                               placeholderSystemName: "film")
            Text((selectedVideoURL == nil && !isEditing) ? "Select film" : "Video selected")
                .foregroundStyle(.primary)
            if selectedVideoURL != nil || isEditing {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
            Spacer()
            if true { // media pickers available when creating and editing
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
    }

    /// "Select thumbnail" row: thumbnail icon (or chosen image preview), label,
    /// and Photos/Files pickers. Chosen independently of the video.
    @ViewBuilder
    private var thumbnailSelectionRow: some View {
        if downloadCenter.isLoadingImage {
            ImagePullRow()
        } else {
        HStack {
            UploadRowThumbnail(image: videoThumbnail, placeholderSystemName: "photo.artframe")
            Text(videoThumbnail == nil ? "Select thumbnail" : "Thumbnail selected")
                .foregroundStyle(.primary)
            if videoThumbnail != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
            Spacer()
            if true { // media pickers available when creating and editing
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
        }
    }

    // MARK: - Film Extras Rows

    /// "Select trailer" row: a single additional video, picked from Photos or Files.
    /// Re-picking replaces the current trailer.
    private var trailerSelectionRow: some View {
        HStack {
            UploadRowThumbnail(image: selectedTrailerURL == nil ? nil : trailerFirstFrame,
                               placeholderSystemName: "popcorn")
            Text(selectedTrailerURL == nil ? "Select trailer" : "Trailer selected")
                .foregroundStyle(.primary)
            if selectedTrailerURL != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
            Spacer()
            HStack(spacing: 12) {
                Button {
                    showTrailerPicker = true
                } label: {
                    Label("Photos", systemImage: "photo.stack")
                        .labelStyle(.iconOnly)
                        .symbolRenderingMode(.multicolor)
                }
                .buttonStyle(.bordered)
                .tint(.primary)

                Button {
                    showTrailerDocumentPicker = true
                } label: {
                    Label("Files", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
            }
        }
    }

    /// "BTS photos" row: any number of images (no videos). Picked images show as a
    /// removable horizontal strip below the header.
    @ViewBuilder
    private var btsPhotosRow: some View {
        extrasImageRow(
            title: "Select BTS photos",
            placeholderSystemName: "camera",
            images: $btsImages,
            showPhotoPicker: $showBTSPhotoPicker,
            showFilePicker: $showBTSDocumentPicker
        )
    }

    /// "Select stills" row: any number of images (no videos).
    @ViewBuilder
    private var stillsRow: some View {
        extrasImageRow(
            title: "Select stills",
            placeholderSystemName: "photo.on.rectangle.angled.fill",
            images: $stillImages,
            showPhotoPicker: $showStillPhotoPicker,
            showFilePicker: $showStillDocumentPicker
        )
    }

    /// Shared layout for the two multi-image rows: a header (icon, label, count, Photos +
    /// Files add buttons) plus a horizontal strip of tap-to-remove thumbnails.
    @ViewBuilder
    private func extrasImageRow(title: String,
                                placeholderSystemName: String,
                                images: Binding<[UIImage]>,
                                showPhotoPicker: Binding<Bool>,
                                showFilePicker: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: images.wrappedValue.isEmpty ? 0 : 10) {
            HStack {
                UploadRowThumbnail(image: images.wrappedValue.first, placeholderSystemName: placeholderSystemName)
                Text(title)
                    .foregroundStyle(.primary)
                if !images.wrappedValue.isEmpty {
                    Text("\(images.wrappedValue.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.brandOrange)
                }
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        showPhotoPicker.wrappedValue = true
                    } label: {
                        Label("Photos", systemImage: "photo.stack")
                            .labelStyle(.iconOnly)
                            .symbolRenderingMode(.multicolor)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)

                    Button {
                        showFilePicker.wrappedValue = true
                    } label: {
                        Label("Files", systemImage: "folder")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }
            }

            if !images.wrappedValue.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(images.wrappedValue.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        images.wrappedValue.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                            .padding(2)
                                    }
                                    .buttonStyle(.plain)
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Thumbnail Loading

    /// Load a chosen photo (from the Photos picker) as the thumbnail.
    private func loadThumbnail(from item: PhotosPickerItem?) {
        guard let item else { return }
        MediaDownloadCenter.shared.beginImageLoad()
        Task {
            let image = (try? await item.loadTransferable(type: Data.self)).flatMap(UIImage.init)
            await MainActor.run {
                if let image {
                    videoThumbnail = image
                    videoThumbnailIsCustom = true
                }
                MediaDownloadCenter.shared.finishImageLoad()
            }
        }
    }

    /// Load a chosen image file (from the Files picker) as the thumbnail.
    private func loadThumbnail(from url: URL) {
        MediaDownloadCenter.shared.beginImageLoad()
        defer { MediaDownloadCenter.shared.finishImageLoad() }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            videoThumbnail = image
            videoThumbnailIsCustom = true
        }
        showThumbnailDocumentPicker = false
    }

    // MARK: - Film Extras Loading

    /// Loads the picked photos (images only) into the given array, appending them, then
    /// clears the picker selection so the same photos can be re-picked later if removed.
    private func loadExtraImages(from items: [PhotosPickerItem], into images: Binding<[UIImage]>) {
        guard !items.isEmpty else { return }
        MediaDownloadCenter.shared.beginImageLoad()
        Task {
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loaded.append(image)
                }
            }
            await MainActor.run {
                images.wrappedValue.append(contentsOf: loaded)
                MediaDownloadCenter.shared.finishImageLoad()
            }
        }
    }
}

// MARK: - Film Edit View

/// Edit screen for an existing film submission. Reuses `FilmSubmissionView` so the form
/// is identical to creating a film; only the already-submitted media (video/thumbnail)
/// is shown read-only and can't be replaced.
struct FilmEditView: View {
    let submission: Submission
    let onSave: (Submission) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edited: Submission
    @State private var selectedGenres: Set<String>
    @State private var releaseYear: String
    @State private var selectedAgeRating: AgeRating
    @State private var castInfo: CastInfo
    @State private var crewInfo: CrewInfo
    @State private var selectedStudio: String
    @State private var videoThumbnail: UIImage?
    @State private var videoFirstFrame: UIImage?

    // Media bindings the form needs; in edit mode the pickers are hidden, so these only
    // drive the read-only preview of the existing video/thumbnail.
    @State private var selectedVideoURL: URL?
    @State private var videoThumbnailIsCustom = false
    @State private var videoLoadError = false
    @State private var isUploadingVideo = false
    /// True once the user picks a new video during editing, so `save()` knows to copy
    /// the new file in and re-upload it (rather than keeping the original).
    @State private var videoWasReplaced = false

    // Film extras being edited. Images are seeded from whatever's cached on disk (the
    // detail view downloads them on open); on save the current sets are re-persisted.
    @State private var selectedTrailerURL: URL?
    @State private var trailerFirstFrame: UIImage?
    @State private var trailerWasReplaced = false
    @State private var btsImages: [UIImage]
    @State private var stillImages: [UIImage]

    init(submission: Submission, onSave: @escaping (Submission) -> Void) {
        self.submission = submission
        self.onSave = onSave
        _edited = State(initialValue: submission)
        _selectedGenres = State(initialValue: Set(submission.genres))
        _releaseYear = State(initialValue: submission.releaseYear)
        _selectedAgeRating = State(initialValue: AgeRating(rawValue: submission.ageRating) ?? .general)
        _castInfo = State(initialValue: CastInfo(orderedEntries: submission.orderedCast))
        _crewInfo = State(initialValue: CrewInfo(orderedEntries: submission.orderedCrew))
        _selectedStudio = State(initialValue: submission.studio)
        _videoThumbnail = State(initialValue: submission.thumbnailData.flatMap(UIImage.init))
        // Editing has only the stored poster to show, so the video row falls back to it.
        _videoFirstFrame = State(initialValue: submission.thumbnailData.flatMap(UIImage.init))
        _selectedVideoURL = State(initialValue: submission.videoURL)
        _selectedTrailerURL = State(initialValue: submission.trailerURL)
        _btsImages = State(initialValue: submission.btsImageURLs.compactMap { UIImage(contentsOfFile: $0.path) })
        _stillImages = State(initialValue: submission.stillImageURLs.compactMap { UIImage(contentsOfFile: $0.path) })
    }

    var body: some View {
        NavigationStack {
            FilmSubmissionView(
                title: $edited.title,
                logline: $edited.logline,
                selectedGenres: $selectedGenres,
                releaseYear: $releaseYear,
                selectedAgeRating: $selectedAgeRating,
                castInfo: $castInfo,
                crewInfo: $crewInfo,
                selectedStudio: $selectedStudio,
                selectedVideoURL: $selectedVideoURL,
                videoFirstFrame: $videoFirstFrame,
                videoThumbnail: $videoThumbnail,
                videoThumbnailIsCustom: $videoThumbnailIsCustom,
                videoLoadError: $videoLoadError,
                isUploadingVideo: $isUploadingVideo,
                festivalBound: $edited.festivalBound,
                selectedTrailerURL: $selectedTrailerURL,
                trailerFirstFrame: $trailerFirstFrame,
                btsImages: $btsImages,
                stillImages: $stillImages,
                onVideoPickerResult: { result in handleVideoPick(result) },
                onGenerateThumbnail: { _ in },
                onTrailerPickerResult: { result in handleTrailerPick(result) },
                isEditing: true
            )
            .navigationTitle("Edit Film")
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

    /// A newly-picked video during editing: preview its first frame and remember to
    /// copy/re-upload it on save.
    private func handleVideoPick(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        selectedVideoURL = url
        videoWasReplaced = true
        videoLoadError = false
        Task {
            let frame = await VideoThumbnailGenerator.generateThumbnail(from: url, at: 0)
            await MainActor.run {
                videoFirstFrame = frame
                // Only adopt the new first frame as the poster if the user hasn't
                // chosen a custom thumbnail.
                if !videoThumbnailIsCustom { videoThumbnail = frame }
            }
        }
    }

    /// A newly-picked trailer during editing: preview its first frame and remember to
    /// copy/re-upload it on save.
    private func handleTrailerPick(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        selectedTrailerURL = url
        trailerWasReplaced = true
        Task {
            let frame = await VideoThumbnailGenerator.generateThumbnail(from: url, at: 0)
            await MainActor.run { trailerFirstFrame = frame }
        }
    }

    private func save() {
        guard !edited.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        edited.genres = Array(selectedGenres)
        edited.releaseYear = releaseYear
        edited.ageRating = selectedAgeRating.rawValue
        edited.studio = selectedStudio
        edited.orderedCast = castInfo.toOrderedEntries()
        edited.orderedCrew = crewInfo.toOrderedEntries()

        // Persist a replaced video into Documents and re-upload it. Clearing the stored
        // duration makes the upload re-read it from the new file.
        if videoWasReplaced, let url = selectedVideoURL {
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            if let name = persistEditedMediaFile(from: url, as: "video_\(edited.id.uuidString).\(ext)") {
                edited.videoFileName = name
                edited.videoDuration = nil
            }
        }

        // Save the current thumbnail (existing, new custom, or new video's first frame).
        if let thumbnail = videoThumbnail {
            edited.thumbnailData = thumbnail.jpegData(compressionQuality: 0.7)
        }

        // Persist a replaced trailer, then re-write the current BTS/stills sets (covers
        // additions, removals, and reordering).
        if trailerWasReplaced, let url = selectedTrailerURL {
            if let name = persistEditedMediaFile(from: url, as: "\(edited.id.uuidString)_trailer.mov") {
                edited.trailerFileName = name
            }
        } else if selectedTrailerURL == nil {
            edited.trailerFileName = nil
        }
        edited.btsImageFileNames = persistFilmExtraImages(btsImages, submissionID: edited.id, kind: "bts")
        edited.stillImageFileNames = persistFilmExtraImages(stillImages, submissionID: edited.id, kind: "still")

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
    @Previewable @State var releaseYear = ""
    @Previewable @State var selectedAgeRating: AgeRating = .general
    @Previewable @State var castInfo = CastInfo()
    @Previewable @State var crewInfo = CrewInfo()
    @Previewable @State var selectedStudio = ""
    @Previewable @State var selectedVideoURL: URL? = nil
    @Previewable @State var videoFirstFrame: UIImage? = nil
    @Previewable @State var videoThumbnail: UIImage? = nil
    @Previewable @State var videoThumbnailIsCustom = false
    @Previewable @State var videoLoadError = false
    @Previewable @State var isUploadingVideo = false
    @Previewable @State var festivalBound = false
    @Previewable @State var selectedTrailerURL: URL? = nil
    @Previewable @State var trailerFirstFrame: UIImage? = nil
    @Previewable @State var btsImages: [UIImage] = []
    @Previewable @State var stillImages: [UIImage] = []

    NavigationStack {
        FilmSubmissionView(
            title: $title,
            logline: $logline,
            selectedGenres: $selectedGenres,
            releaseYear: $releaseYear,
            selectedAgeRating: $selectedAgeRating,
            castInfo: $castInfo,
            crewInfo: $crewInfo,
            selectedStudio: $selectedStudio,
            selectedVideoURL: $selectedVideoURL,
            videoFirstFrame: $videoFirstFrame,
            videoThumbnail: $videoThumbnail,
            videoThumbnailIsCustom: $videoThumbnailIsCustom,
            videoLoadError: $videoLoadError,
            isUploadingVideo: $isUploadingVideo,
            festivalBound: $festivalBound,
            selectedTrailerURL: $selectedTrailerURL,
            trailerFirstFrame: $trailerFirstFrame,
            btsImages: $btsImages,
            stillImages: $stillImages,
            onVideoPickerResult: { _ in },
            onGenerateThumbnail: { _ in }
        )
        .navigationTitle("Film")
        .navigationBarTitleDisplayMode(.inline)
    }
}
