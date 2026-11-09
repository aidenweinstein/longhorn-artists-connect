//
//  ReelSubmissionView.swift
//  Longhorn Artists Connect
//
//  Reel submission form - showcase reels with video, experience, and skills
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ReelSubmissionView: View {
    @Binding var title: String
    /// The reel's headline artist/creator, shown under the title (mirrors music's Artist).
    @Binding var artist: String
    @Binding var reelDescription: String
    /// The reel's release year, shown as a picker in the Details section.
    @Binding var releaseYear: String
    @Binding var selectedReelVideoURL: URL?
    /// The reel video's own first frame, shown in the "video" row. Kept separate from the
    /// poster so a custom thumbnail doesn't change what the video row shows.
    @Binding var reelVideoFirstFrame: UIImage?
    @Binding var reelVideoThumbnail: UIImage?
    /// Set to true when the user picks their own thumbnail, so the auto-generated
    /// first-frame thumbnail doesn't overwrite it.
    @Binding var reelVideoThumbnailIsCustom: Bool
    @Binding var reelVideoLoadError: Bool
    @Binding var isUploadingReelVideo: Bool
    @Binding var showReelVideoPicker: Bool
    @Binding var showReelDocumentPicker: Bool
    @Binding var showReelThumbnailPicker: Bool
    /// UUID strings of other posts referenced as "Featured Work" on this reel.
    @Binding var featuredWorkIDs: [String]
    /// Hand-typed "Featured Work" entries (project + director), each a JSON-encoded
    /// `ManualFeaturedWork`.
    @Binding var featuredWorkManual: [String]
    /// Photos of the performance (any number, images only).
    @Binding var stillImages: [UIImage]
    /// Cast credits (role + performer), edited in the same Cast form films use.
    @Binding var castInfo: CastInfo
    /// Crew credits (role + name), edited in the same Crew form films use.
    @Binding var crewInfo: CrewInfo

    /// Live CloudKit upload state, set once the post is submitted.
    var uploadPhase: MediaUploadPhase? = nil
    var onRetryUpload: () -> Void = {}

    /// When true this form is editing an existing post: the reel video/thumbnail stay
    /// visible but can't be replaced, so their picker buttons are hidden. Every other
    /// field behaves exactly as it does when creating a post.
    var isEditing: Bool = false

    /// This reel's own id (when editing) so it can be excluded from the Featured Work
    /// search — a reel shouldn't feature itself.
    var selfID: UUID? = nil

    /// Edit screen only: a URL for the already-posted reel video (its streaming link)
    /// when it isn't on disk, so its first frame can be read for cropping.
    var loadExistingVideo: (() async -> URL?)? = nil

    /// The reel video's playback crop (`VideoCrop` string). Applied by the player, so
    /// cropping never re-encodes or downloads the video.
    var videoCrop: Binding<String?> = .constant(nil)

    /// Live progress of pulling the picked video out of Photos/Files (incl. iCloud
    /// download). Drives the determinate "Downloading from iCloud…" ring.
    @ObservedObject private var downloadCenter = MediaDownloadCenter.shared
    @State private var showThumbnailPhotoPicker = false
    @State private var thumbnailPhotoItem: PhotosPickerItem?
    @State private var showThumbnailDocumentPicker = false
    @State private var showFeaturedWorkPicker = false
    @State private var showCastForm = false
    @State private var showCrewForm = false
    /// Reveals the "Select headshots" / "Select resume" rows under the thumbnail row.
    @State private var showMoreOptions = false
    // Headshots: one or more images, chosen from Photos or Files.
    @State private var headshotImages: [UIImage] = []
    @State private var showHeadshotPhotoPicker = false
    @State private var headshotPhotoItems: [PhotosPickerItem] = []
    @State private var showHeadshotDocumentPicker = false
    // Resume: a single photo or file (e.g. a PDF).
    @State private var resumeImage: UIImage?
    @State private var resumeFileURL: URL?
    @State private var showResumePhotoPicker = false
    @State private var resumePhotoItem: PhotosPickerItem?
    @State private var showResumeDocumentPicker = false
    // Stills (showcase categories only): any number of images, from Photos or Files.
    @State private var stillPhotoItems: [PhotosPickerItem] = []
    @State private var showStillPhotoPicker = false
    @State private var showStillDocumentPicker = false
    /// The open crop editor, if any (video, thumbnail, or resume image).
    @State private var cropRequest: MediaCropRequest?
    /// Set when the user trashes the existing video while editing, so the row reads as
    /// empty even though an already-posted video may not be on disk to hold a URL for.
    @State private var existingVideoRemoved = false
    @ObservedObject private var store: SubmissionStore_3_2 = .shared
    
    /// The reel categories the form used to offer. The form no longer asks for one, but
    /// older posts still carry these, so `SecurityManager` keeps accepting them.
    static let reelCategories = ["Acting Reel", "Dancing Reel", "Actor Showcase", "Dance Showcase"]

    var body: some View {
        List {
            Section("Upload") {
                reelUploadSection
            }

            Section("Details") {
                TextField("Title", text: $title, axis: .vertical)
                // Performer can be credited to a registered user: suggests matching
                // profiles as you type and autofills their exact name on tap.
                CreditNameField(placeholder: "Performer", text: $artist)

                TextField("Description", text: $reelDescription, axis: .vertical)
                    .lineLimit(4, reservesSpace: true)

                ReleaseYearPicker(releaseYear: $releaseYear)

                // Cast and crew credits, each opening the same full form films use.
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
            }

            Section {
                featuredWorkSection
            } header: {
                Text("Other")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGray6))
        // Pushed (slides in from the side with a back arrow) rather than presented as a
        // bottom sheet. Destinations live on the List itself, not on rows inside it:
        // rows in a lazy container may not exist yet, so destinations declared there
        // can be missed by the navigation stack.
        .navigationDestination(isPresented: $showFeaturedWorkPicker) {
            FeaturedWorkPickerView(selectedIDs: $featuredWorkIDs, excludedID: selfID)
        }
        .navigationDestination(isPresented: $showCastForm) {
            CastFormView(cast: $castInfo)
        }
        .navigationDestination(isPresented: $showCrewForm) {
            CrewFormView(crew: $crewInfo)
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
        .photosPicker(isPresented: $showHeadshotPhotoPicker, selection: $headshotPhotoItems, matching: .images)
        .onChange(of: headshotPhotoItems) { _, newItems in
            loadHeadshots(from: newItems)
        }
        .sheet(isPresented: $showHeadshotDocumentPicker) {
            DocumentPicker(contentTypes: [.image]) { url in
                addHeadshot(from: url)
            } onCancel: {
                showHeadshotDocumentPicker = false
            }
        }
        .photosPicker(isPresented: $showResumePhotoPicker, selection: $resumePhotoItem, matching: .images)
        .onChange(of: resumePhotoItem) { _, newItem in
            loadResume(from: newItem)
        }
        .sheet(isPresented: $showResumeDocumentPicker) {
            DocumentPicker(contentTypes: [.pdf, .image, .content]) { url in
                setResume(from: url)
            } onCancel: {
                showResumeDocumentPicker = false
            }
        }
        // Stills (multiple images, no videos). `maxSelectionCount: 0` = unlimited.
        .photosPicker(isPresented: $showStillPhotoPicker, selection: $stillPhotoItems,
                      maxSelectionCount: 0, matching: .images)
        .onChange(of: stillPhotoItems) { _, newItems in
            loadStills(from: newItems)
            stillPhotoItems = []
        }
        .sheet(isPresented: $showStillDocumentPicker) {
            MultiImageDocumentPicker { images in
                stillImages.append(contentsOf: images)
            } onCancel: {
                showStillDocumentPicker = false
            }
        }
        .mediaCropper($cropRequest)
        // A crop belongs to the video it was framed on; a newly picked video starts uncropped.
        .onChange(of: selectedReelVideoURL) { _, _ in videoCrop.wrappedValue = nil }
    }
    
    @ViewBuilder
    private var reelUploadSection: some View {
        if let uploadPhase {
            MediaUploadStatusView(phase: uploadPhase, onRetry: onRetryUpload)
        } else {
            // The video's loading/error state is scoped to the video field only, so the
            // thumbnail field stays visible (and usable) while the video downloads.
            videoField
            thumbnailSelectionRow
            MultiImageUploadRow(
                title: "Select photos",
                placeholderSystemName: "photo.on.rectangle.angled.fill",
                images: $stillImages,
                showPhotoPicker: $showStillPhotoPicker,
                showFilePicker: $showStillDocumentPicker
            )
            moreOptionsSection
        }
    }

    /// A "More" disclosure row that, once tapped, reveals the headshots and resume rows.
    @ViewBuilder
    private var moreOptionsSection: some View {
        if showMoreOptions {
            headshotsSelectionRow
            resumeSelectionRow
        } else {
            Button {
                withAnimation { showMoreOptions = true }
            } label: {
                HStack {
                    Text("More")
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.brandOrange)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// The "video" field: shows its own download/upload/error state in place of the
    /// video row, without hiding the rest of the Upload section.
    @ViewBuilder
    private var videoField: some View {
        if isEditing {
            // Editing: show the existing reel video (as its poster frame), read-only.
            videoSelectionRow
        } else if reelVideoLoadError {
            VideoErrorStateView(
                videoLoadError: $reelVideoLoadError,
                showVideoPicker: $showReelVideoPicker,
                showDocumentPicker: $showReelDocumentPicker
            )
        } else if let fraction = downloadCenter.fraction {
            DownloadProgressRow(fraction: fraction)
        } else if isUploadingReelVideo {
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

    // MARK: - Featured Work

    /// Currently-referenced posts, resolved from their stored IDs against the store.
    private var featuredWorkPosts: [Submission] {
        let all = store.approvedSubmissions + store.submissions
        return featuredWorkIDs.compactMap { idString in
            guard let uuid = UUID(uuidString: idString) else { return nil }
            return all.first { $0.id == uuid }
        }
    }

    /// Hand-typed featured-work entries, decoded from their stored JSON strings.
    private var manualFeaturedWorks: [ManualFeaturedWork] {
        featuredWorkManual.compactMap(ManualFeaturedWork.init(encoded:))
    }

    @ViewBuilder
    private var featuredWorkSection: some View {
        ForEach(featuredWorkPosts) { post in
            HStack {
                UploadRowThumbnail(image: post.thumbnailData.flatMap(UIImage.init),
                                   placeholderSystemName: iconName(for: post.type))
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(post.type.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    featuredWorkIDs.removeAll { $0 == post.id.uuidString }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }

        Button {
            showFeaturedWorkPicker = true
        } label: {
            HStack {
                Text("Featured Work")
                    .foregroundStyle(Color.primary)
                Spacer()
                Text("Add")
                    .foregroundStyle(Color.brandOrange)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
        }
        .buttonStyle(.plain)

        // Hand-typed entries: a project and its director that aren't posts on the app.
        ForEach(Array(manualFeaturedWorks.enumerated()), id: \.offset) { index, entry in
            HStack {
                UploadRowThumbnail(image: nil, placeholderSystemName: "hammer")
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(entry.director.isEmpty ? "Project" : "Directed by \(entry.director)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    // Remove by matching the encoded value, so index shifts can't delete
                    // the wrong row.
                    if featuredWorkManual.indices.contains(index) {
                        featuredWorkManual.remove(at: index)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }

    }

    /// SF Symbol used to represent a post type in the small thumbnail placeholder.
    private func iconName(for type: MediaType) -> String {
        switch type {
        case .film:    return "film"
        case .music:   return "music.note"
        case .reel:    return "video"
        case .project: return "hammer"
        case .event:   return "calendar"
        case .photography: return "camera"
        case .design:  return "paintpalette.fill"
        }
    }

    // MARK: - Upload Rows

    /// Whether the video row holds a video: a picked one, or (while editing) the
    /// already-posted one unless the user trashed it.
    private var hasVideo: Bool {
        selectedReelVideoURL != nil || (isEditing && !existingVideoRemoved)
    }

    /// "Select video" row: film-strip icon, label, and Photos/Files pickers — swapped
    /// for Crop + Trash once a video is picked.
    private var videoSelectionRow: some View {
        HStack {
            // Show the video's first frame (the auto-generated thumbnail) once a video
            // is picked, scaled to fit so it stays within the row; film icon otherwise.
            UploadRowThumbnail(image: hasVideo ? croppedFirstFrame : nil,
                               placeholderSystemName: "film")
            Text(hasVideo ? "Video selected" : "Select video")
                .foregroundStyle(.primary)
            if hasVideo {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
            Spacer()
            UploadPickerButtons(
                hasSelection: hasVideo,
                onPhotos: { showReelVideoPicker = true },
                onFiles: { showReelDocumentPicker = true },
                onCrop: {
                    // Frame the crop on the video's first frame; the player applies it.
                    let url = selectedReelVideoURL
                    let loadExisting = loadExistingVideo
                    // Only a picked video's row frame is its real first frame; while editing
                    // it's the post's poster, so let the editor pull the frame itself.
                    cropRequest = .playbackCrop(
                        preview: url == nil ? nil : reelVideoFirstFrame,
                        load: {
                            if let url { return url }
                            return await loadExisting?()
                        },
                        current: VideoCrop(videoCrop.wrappedValue)
                    ) { crop in
                        videoCrop.wrappedValue = crop?.encoded
                        // A new post's auto poster is the first frame — keep it matching
                        // what the player will show.
                        if !isEditing, !reelVideoThumbnailIsCustom, let frame = reelVideoFirstFrame {
                            reelVideoThumbnail = crop.map { ImageCropper.crop(frame, to: $0.rect) } ?? frame
                        }
                    }
                },
                onRemove: {
                    selectedReelVideoURL = nil
                    reelVideoFirstFrame = nil
                    videoCrop.wrappedValue = nil
                    existingVideoRemoved = true
                    // Drop the auto-generated poster with its video; a custom one (or a
                    // posted one, while editing) stays.
                    if !reelVideoThumbnailIsCustom && !isEditing { reelVideoThumbnail = nil }
                }
            )
        }
    }

    /// The video row's preview frame with the playback crop applied, so the row shows
    /// what the player will.
    private var croppedFirstFrame: UIImage? {
        guard let frame = reelVideoFirstFrame else { return nil }
        // While editing, the row frame is the post's poster, not the video's frame.
        guard let crop = VideoCrop(videoCrop.wrappedValue), !isEditing else { return frame }
        return ImageCropper.crop(frame, to: crop.rect)
    }

    /// "Select thumbnail" row: thumbnail icon (or chosen image preview), label,
    /// and Photos/Files pickers. Chosen independently of the video.
    @ViewBuilder
    private var thumbnailSelectionRow: some View {
        if downloadCenter.isLoadingImage {
            ImagePullRow()
        } else {
        HStack {
            UploadRowThumbnail(image: reelVideoThumbnail, placeholderSystemName: "photo")
            Text(reelVideoThumbnail == nil ? "Select thumbnail" : "Thumbnail selected")
                .foregroundStyle(.primary)
            if reelVideoThumbnail != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
            Spacer()
            UploadPickerButtons(
                hasSelection: reelVideoThumbnail != nil,
                onPhotos: { showThumbnailPhotoPicker = true },
                onFiles: { showThumbnailDocumentPicker = true },
                onCrop: reelVideoThumbnail.map { image in
                    {
                        cropRequest = .image(image) { cropped in
                            reelVideoThumbnail = cropped
                            reelVideoThumbnailIsCustom = true
                        }
                    }
                },
                onRemove: {
                    reelVideoThumbnail = nil
                    reelVideoThumbnailIsCustom = false
                    thumbnailPhotoItem = nil
                }
            )
        }
        }
    }

    /// "Select headshots" row: one or more images, from Photos or Files.
    private var headshotsSelectionRow: some View {
        HStack {
            UploadRowThumbnail(image: headshotImages.first, placeholderSystemName: "person.crop.rectangle")
            Text(headshotImages.isEmpty
                 ? "Select headshots"
                 : "\(headshotImages.count) headshot\(headshotImages.count == 1 ? "" : "s") selected")
                .foregroundStyle(.primary)
            if !headshotImages.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
            Spacer()
            HStack(spacing: 12) {
                Button {
                    showHeadshotPhotoPicker = true
                } label: {
                    Label("Photos", systemImage: "photo.stack")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.primary)

                Button {
                    showHeadshotDocumentPicker = true
                } label: {
                    Label("Files", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
            }
        }
    }

    /// "Select resume" row: a single photo or file (e.g. a PDF), from Photos or Files.
    private var resumeSelectionRow: some View {
        let hasResume = resumeImage != nil || resumeFileURL != nil
        return HStack {
            UploadRowThumbnail(image: resumeImage, placeholderSystemName: "doc.text")
            Text(hasResume ? "Resume selected" : "Select resume")
                .foregroundStyle(.primary)
            if hasResume {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
            Spacer()
            UploadPickerButtons(
                hasSelection: hasResume,
                onPhotos: { showResumePhotoPicker = true },
                onFiles: { showResumeDocumentPicker = true },
                // Only an image resume can be cropped (not a PDF).
                onCrop: resumeImage.map { image in
                    {
                        cropRequest = .image(image) { cropped in
                            resumeImage = cropped
                            resumeFileURL = nil
                        }
                    }
                },
                onRemove: {
                    resumeImage = nil
                    resumeFileURL = nil
                    resumePhotoItem = nil
                }
            )
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
                    reelVideoThumbnail = image
                    reelVideoThumbnailIsCustom = true
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
            reelVideoThumbnail = image
            reelVideoThumbnailIsCustom = true
        }
        showThumbnailDocumentPicker = false
    }

    // MARK: - Headshots & Resume Loading

    /// Load chosen photos (from the Photos picker) as headshots, replacing the set.
    private func loadHeadshots(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        MediaDownloadCenter.shared.beginImageLoad()
        Task {
            var images: [UIImage] = []
            for item in items {
                if let image = (try? await item.loadTransferable(type: Data.self)).flatMap(UIImage.init) {
                    images.append(image)
                }
            }
            await MainActor.run {
                headshotImages = images
                MediaDownloadCenter.shared.finishImageLoad()
            }
        }
    }

    /// Append a chosen image file (from the Files picker) to the headshots.
    private func addHeadshot(from url: URL) {
        MediaDownloadCenter.shared.beginImageLoad()
        defer { MediaDownloadCenter.shared.finishImageLoad() }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            headshotImages.append(image)
        }
        showHeadshotDocumentPicker = false
    }

    /// Load a chosen photo (from the Photos picker) as the resume.
    private func loadResume(from item: PhotosPickerItem?) {
        guard let item else { return }
        MediaDownloadCenter.shared.beginImageLoad()
        Task {
            let image = (try? await item.loadTransferable(type: Data.self)).flatMap(UIImage.init)
            await MainActor.run {
                if let image {
                    resumeImage = image
                    resumeFileURL = nil
                }
                MediaDownloadCenter.shared.finishImageLoad()
            }
        }
    }

    /// Set a chosen file (from the Files picker) as the resume. Images preview inline;
    /// other files (e.g. PDFs) are kept by URL and shown via the doc placeholder.
    private func setResume(from url: URL) {
        MediaDownloadCenter.shared.beginImageLoad()
        defer { MediaDownloadCenter.shared.finishImageLoad() }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        resumeFileURL = url
        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            resumeImage = image
        } else {
            resumeImage = nil
        }
        showResumeDocumentPicker = false
    }

    // MARK: - Stills Loading

    /// Append chosen photos (from the Photos picker) to the stills, in pick order.
    private func loadStills(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        MediaDownloadCenter.shared.beginImageLoad()
        Task {
            var loaded: [UIImage] = []
            for item in items {
                if let image = (try? await item.loadTransferable(type: Data.self)).flatMap(UIImage.init) {
                    loaded.append(image)
                }
            }
            await MainActor.run {
                stillImages.append(contentsOf: loaded)
                MediaDownloadCenter.shared.finishImageLoad()
            }
        }
    }
}

// MARK: - Featured Work Picker

/// A searchable list of other posts on the app. Tapping a post toggles whether it's
/// referenced as Featured Work on the reel being composed.
struct FeaturedWorkPickerView: View {
    @Binding var selectedIDs: [String]
    var excludedID: UUID? = nil

    @ObservedObject private var store: SubmissionStore_3_2 = .shared
    @State private var searchText = ""

    /// Posts eligible to feature: everything visible in the feeds except this reel.
    private var candidates: [Submission] {
        store.visibleApprovedSubmissions
            .filter { $0.id != excludedID }
            .sorted { $0.createdDate > $1.createdDate }
    }

    private var filtered: [Submission] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return candidates }
        return candidates.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
            $0.submittedBy.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar styled to match the directory's.
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search posts", text: $searchText, axis: .vertical)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Posts listed in the same card style as a portfolio.
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { post in
                        Button {
                            toggle(post)
                        } label: {
                            SubmissionListRow(submission: post) {
                                if selectedIDs.contains(post.id.uuidString) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.brandOrange)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
        }
        .navigationTitle("Featured Work")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ post: Submission) {
        let id = post.id.uuidString
        if let idx = selectedIDs.firstIndex(of: id) {
            selectedIDs.remove(at: idx)
        } else {
            selectedIDs.append(id)
        }
    }
}

// MARK: - Reel Edit View

/// Edit screen for an existing reel submission. Reuses `ReelSubmissionView` so the form
/// is identical to creating a reel; only the already-submitted video/thumbnail is shown
/// read-only and can't be replaced.
struct ReelEditView: View {
    let submission: Submission
    let onSave: (Submission) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edited: Submission
    @State private var reelVideoThumbnail: UIImage?
    @State private var reelVideoFirstFrame: UIImage?

    // Media state driving the form's video/thumbnail rows and pickers.
    @State private var selectedReelVideoURL: URL?
    @State private var reelVideoThumbnailIsCustom = false
    @State private var reelVideoLoadError = false
    @State private var isUploadingReelVideo = false
    // The reel video pickers are presented by the parent in the create flow, so the edit
    // screen hosts them itself.
    @State private var showReelVideoPicker = false
    @State private var showReelDocumentPicker = false
    /// True once the user picks a new reel video, so `save()` copies/re-uploads it.
    @State private var videoWasReplaced = false
    /// The showcase's stills, seeded from any local copies and topped up from CloudKit
    /// on appear (the feed doesn't download them).
    @State private var stillImages: [UIImage]
    /// Cast and crew, rebuilt from the post's stored credits for the shared forms.
    @State private var castInfo: CastInfo
    @State private var crewInfo: CrewInfo

    init(submission: Submission, onSave: @escaping (Submission) -> Void) {
        self.submission = submission
        self.onSave = onSave
        _edited = State(initialValue: submission)
        _stillImages = State(initialValue: submission.stillImageURLs.compactMap { UIImage(contentsOfFile: $0.path) })
        _castInfo = State(initialValue: CastInfo(orderedEntries: submission.orderedCast))
        _crewInfo = State(initialValue: CrewInfo(orderedEntries: submission.orderedCrew))
        _reelVideoThumbnail = State(initialValue: submission.thumbnailData.flatMap(UIImage.init))
        // Editing has only the stored poster to show, so the video row falls back to it.
        _reelVideoFirstFrame = State(initialValue: submission.thumbnailData.flatMap(UIImage.init))
        _selectedReelVideoURL = State(initialValue: submission.videoURL)
    }

    var body: some View {
        NavigationStack {
            ReelSubmissionView(
                title: $edited.title,
                artist: $edited.artist,
                reelDescription: $edited.reelDescription,
                releaseYear: $edited.releaseYear,
                selectedReelVideoURL: $selectedReelVideoURL,
                reelVideoFirstFrame: $reelVideoFirstFrame,
                reelVideoThumbnail: $reelVideoThumbnail,
                reelVideoThumbnailIsCustom: $reelVideoThumbnailIsCustom,
                reelVideoLoadError: $reelVideoLoadError,
                isUploadingReelVideo: $isUploadingReelVideo,
                showReelVideoPicker: $showReelVideoPicker,
                showReelDocumentPicker: $showReelDocumentPicker,
                showReelThumbnailPicker: .constant(false),
                featuredWorkIDs: $edited.featuredWorkIDs,
                featuredWorkManual: $edited.featuredWorkManual,
                stillImages: $stillImages,
                castInfo: $castInfo,
                crewInfo: $crewInfo,
                isEditing: true,
                selfID: submission.id,
                loadExistingVideo: { [submissionID = submission.id] in
                    // The streaming link gives the first frame without a download.
                    await CloudKitManager.shared.streamingURL(submissionID: submissionID, type: .reel)
                },
                videoCrop: $edited.videoCrop
            )
            .navigationTitle("Edit Reel")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Pull the posted stills so they can be kept, removed, or added to.
                guard stillImages.isEmpty else { return }
                let urls = await CloudKitManager.shared.downloadReelStills(submissionID: submission.id)
                let images = urls.compactMap { UIImage(contentsOfFile: $0.path) }
                if stillImages.isEmpty { stillImages = images }
            }
            .sheet(isPresented: $showReelVideoPicker) {
                VideoPickerWithiCloudSupport { result in handleVideoPick(result) }
            }
            .sheet(isPresented: $showReelDocumentPicker) {
                DocumentPicker(contentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie]) { url in
                    handleVideoPick(.success(url))
                } onCancel: {
                    showReelDocumentPicker = false
                }
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
        .presentationDragIndicator(.hidden)
    }

    /// A newly-picked reel video during editing: preview its first frame and remember
    /// to copy/re-upload it on save.
    private func handleVideoPick(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        selectedReelVideoURL = url
        videoWasReplaced = true
        reelVideoLoadError = false
        showReelVideoPicker = false
        showReelDocumentPicker = false
        Task {
            let frame = await VideoThumbnailGenerator.generateThumbnail(from: url, at: 0)
            await MainActor.run {
                reelVideoFirstFrame = frame
                if !reelVideoThumbnailIsCustom { reelVideoThumbnail = frame }
            }
        }
    }

    private func save() {
        guard !edited.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        // Persist a replaced reel video into Documents and re-upload it.
        if videoWasReplaced, let url = selectedReelVideoURL {
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            if let name = persistEditedMediaFile(from: url, as: "video_\(edited.id.uuidString).\(ext)") {
                edited.videoFileName = name
            }
        }

        // Save the current thumbnail (existing, new custom, or new video's first frame).
        if let thumbnail = reelVideoThumbnail {
            edited.thumbnailData = thumbnail.jpegData(compressionQuality: 0.7)
        }

        // Re-write the current stills set (covers additions, removals, and reordering).
        edited.stillImageFileNames = persistFilmExtraImages(stillImages, submissionID: edited.id, kind: "still")

        // Flatten the edited cast and crew back into the stored credit lists.
        edited.orderedCast = castInfo.toOrderedEntries()
        edited.orderedCrew = crewInfo.toOrderedEntries()

        onSave(edited)
        dismiss()
    }
}

#Preview {
    @Previewable @State var title = ""
    @Previewable @State var artist = ""
    @Previewable @State var reelDescription = ""
    @Previewable @State var releaseYear = ""
    @Previewable @State var selectedReelVideoURL: URL? = nil
    @Previewable @State var reelVideoFirstFrame: UIImage? = nil
    @Previewable @State var reelVideoThumbnail: UIImage? = nil
    @Previewable @State var reelVideoThumbnailIsCustom = false
    @Previewable @State var reelVideoLoadError = false
    @Previewable @State var isUploadingReelVideo = false
    @Previewable @State var showReelVideoPicker = false
    @Previewable @State var showReelDocumentPicker = false
    @Previewable @State var showReelThumbnailPicker = false
    
    NavigationStack {
        ReelSubmissionView(
            title: $title,
            artist: $artist,
            reelDescription: $reelDescription,
            releaseYear: $releaseYear,
            selectedReelVideoURL: $selectedReelVideoURL,
            reelVideoFirstFrame: $reelVideoFirstFrame,
            reelVideoThumbnail: $reelVideoThumbnail,
            reelVideoThumbnailIsCustom: $reelVideoThumbnailIsCustom,
            reelVideoLoadError: $reelVideoLoadError,
            isUploadingReelVideo: $isUploadingReelVideo,
            showReelVideoPicker: $showReelVideoPicker,
            showReelDocumentPicker: $showReelDocumentPicker,
            showReelThumbnailPicker: $showReelThumbnailPicker,
            featuredWorkIDs: .constant([]),
            featuredWorkManual: .constant([]),
            stillImages: .constant([]),
            castInfo: .constant(CastInfo()),
            crewInfo: .constant(CrewInfo())
        )
        .navigationTitle("Reel")
        .navigationBarTitleDisplayMode(.inline)
    }
}
