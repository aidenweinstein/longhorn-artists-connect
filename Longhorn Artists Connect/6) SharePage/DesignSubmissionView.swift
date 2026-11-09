//
//  DesignSubmissionView.swift
//  Longhorn Artists Connect
//
//  Design submission form — artwork and design pieces (graphic, magazine, drawing,
//  painting, modeling) uploaded as images and/or a video, with a description, year and
//  credits. Also hosts the owner edit form and the feed detail view.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Design Category

/// The kinds of design a post can be filed under. The raw values are what's stored on
/// the submission and in CloudKit, so they must not be renamed once posts exist.
enum DesignCategory: String, CaseIterable, Identifiable {
    case graphic  = "Graphic"
    case magazine = "Magazine"
    case drawing  = "Drawing"
    case painting = "Painting"
    case modeling = "Modeling"

    var id: String { rawValue }
}

// MARK: - Design Submission Form

struct DesignSubmissionView: View {
    @Binding var title: String
    @Binding var designDescription: String
    /// The year the piece was made/released.
    @Binding var releaseYear: String
    /// The picked images. The first doubles as the post thumbnail.
    @Binding var images: [UIImage]
    /// An optional video, for motion/3D work. Picked from Photos or Files.
    @Binding var videoURL: URL?
    /// The video's first frame, shown in the video row (and used as the thumbnail when
    /// the post has no images).
    @Binding var videoFirstFrame: UIImage?
    /// People credited on the piece. Edited on a pushed subpage and stored as the
    /// post's crew credits.
    @Binding var credits: CrewInfo

    /// Live CloudKit upload state, set once the post is submitted.
    var uploadPhase: MediaUploadPhase? = nil
    var onRetryUpload: () -> Void = {}

    /// When true this form is editing an existing post; behaves the same, it's only used
    /// to label the picker.
    var isEditing: Bool = false

    /// The video's playback crop (`VideoCrop` string). Applied by the player, so cropping
    /// never re-encodes the video.
    var videoCrop: Binding<String?> = .constant(nil)

    @State private var pickerItems: [PhotosPickerItem] = []
    /// Picker batches still loading. Library photos can take seconds to come down from
    /// iCloud, so more than one batch can be in flight at once.
    @State private var loadingBatchCount = 0
    /// The most recently enqueued batch. Each new batch waits on this one before it
    /// appends, so images land in the order they were picked rather than the order they
    /// happened to finish loading.
    @State private var lastLoad: Task<Void, Never>?
    /// Camera-roll (Photos) and Files pickers for the images (the Photos picker also
    /// accepts the optional video).
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var isLoadingVideo = false
    /// The open video crop editor, if any.
    @State private var cropRequest: MediaCropRequest?
    /// Drives the pushed Credits subpage.
    @State private var showCreditsForm = false
    /// Drives the pushed Reorder subpage.
    @State private var showReorderForm = false

    private var isLoadingImages: Bool { loadingBatchCount > 0 }

    /// How many pieces of media are attached: the images plus the video, if any.
    private var mediaCount: Int { images.count + (videoURL == nil ? 0 : 1) }

    var body: some View {
        List {
            Section("Upload") {
                if let uploadPhase {
                    MediaUploadStatusView(phase: uploadPhase, onRetry: onRetryUpload)
                } else {
                    imageGallery
                    imagePickerRow
                    if isLoadingImages || isLoadingVideo {
                        HStack {
                            ProgressView().padding(.trailing, 8)
                            Text("Loading media…").foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if uploadPhase == nil {
                Section("Details") {
                    TextField("Title", text: $title, axis: .vertical)

                    TextField("Description", text: $designDescription, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)

                    ReleaseYearPicker(releaseYear: $releaseYear)

                    Button {
                        showCreditsForm = true
                    } label: {
                        HStack {
                            Text("Credits")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(credits.summary.isEmpty ? "Add" : "Edited")
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
        .scrollContentBackground(.hidden)
        .background(Color(.systemGray6))
        // Navigation destinations live on the List, not on a row inside it: rows in a
        // lazy container may not exist yet, so a destination declared there can be missed.
        .navigationDestination(isPresented: $showCreditsForm) {
            CrewFormView(
                crew: $credits,
                navigationTitle: "Credits",
                sectionTitle: "Credits",
                addButtonTitle: "Add Credit"
            )
        }
        .navigationDestination(isPresented: $showReorderForm) {
            DesignImageReorderView(images: $images)
        }
        // `.ordered` numbers the picks and hands them back in tap order, so the numbered
        // selection order becomes the order they appear in the post. `nil` is the
        // documented way to ask for the system maximum (0 isn't a defined value). Videos
        // are accepted too: a picked video becomes the post's (single) video.
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItems,
                      maxSelectionCount: nil, selectionBehavior: .ordered,
                      matching: .any(of: [.images, .videos]))
        .onChange(of: pickerItems) { _, newItems in
            loadImages(from: newItems)
        }
        .sheet(isPresented: $showFilePicker) {
            MultiImageDocumentPicker { picked in
                appendInPickOrder(picked)
            } onCancel: {
                showFilePicker = false
            }
        }
        .mediaCropper($cropRequest)
    }

    /// "Select image(s)/video(s)" header row: label, count, and Photos + Files pickers —
    /// matching the two-button layout used by the other submission views.
    private var imagePickerRow: some View {
        HStack {
            Label(mediaCount == 0 ? "Select image(s)/video(s)" : "Add more", systemImage: "photo")
                .foregroundStyle(.primary)
            if mediaCount > 0 {
                Text("\(mediaCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandOrange)
            }
            Spacer()
            HStack(spacing: 12) {
                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Photos", systemImage: "photo.stack")
                        .labelStyle(.iconOnly)
                        .symbolRenderingMode(.multicolor)
                }
                .buttonStyle(.bordered)
                .tint(.primary)

                Button {
                    showFilePicker = true
                } label: {
                    Label("Files", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
            }
        }
    }

    /// The picked video's tile in the gallery strip: its first frame (with the playback
    /// crop applied, so it shows what the player will) under a play badge, with Crop and
    /// Remove controls. Sits after the images since the model holds a single video.
    @ViewBuilder
    private var videoTile: some View {
        if let url = videoURL {
            let frame = videoFirstFrame.map { frame in
                VideoCrop(videoCrop.wrappedValue).map { ImageCropper.crop(frame, to: $0.rect) } ?? frame
            }
            Group {
                if let frame {
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 120)
                        .overlay { Image(systemName: "video").foregroundStyle(.secondary) }
                }
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topLeading) {
                Image(systemName: "play.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.black.opacity(0.6)))
                    .padding(4)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    videoURL = nil
                    videoFirstFrame = nil
                    videoCrop.wrappedValue = nil
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                        .background(Circle().fill(.white))
                }
                .buttonStyle(.plain)
                .padding(4)
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    cropRequest = .playbackCrop(
                        preview: videoFirstFrame,
                        load: { url },
                        current: VideoCrop(videoCrop.wrappedValue)
                    ) { crop in
                        videoCrop.wrappedValue = crop?.encoded
                    }
                } label: {
                    Image(systemName: "crop")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
    }

    /// Horizontal strip of chosen images, each shown at its real aspect ratio (fixed
    /// height, variable width), numbered at the top-left, and removable at the top-right,
    /// followed by the video tile when a video is picked.
    /// Reordering is done on a dedicated pushed screen via the "Reorder" button, since
    /// drag-to-reorder doesn't work reliably inside this `List`-hosted horizontal strip.
    @ViewBuilder
    private var imageGallery: some View {
        if mediaCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Keyed by the UIImage instance (a reference type) so identity is
                        // stable across reorders, letting the move animate smoothly.
                        ForEach(Array(images.enumerated()), id: \.element) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topLeading) {
                                    Text("\(index + 1)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                        .padding(4)
                                }
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        images.remove(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                            .background(Circle().fill(.white))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(4)
                                }
                        }

                        videoTile
                    }
                    .padding(.vertical, 4)
                }

                if images.count > 1 {
                    Button {
                        showReorderForm = true
                    } label: {
                        Label("Reorder", systemImage: "arrow.up.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.brandOrange)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Stores the picked video and grabs its first frame for the row's preview. A new
    /// video starts uncropped.
    private func setVideo(_ url: URL) {
        videoURL = url
        videoCrop.wrappedValue = nil
        isLoadingVideo = true
        Task {
            let frame = await VideoThumbnailGenerator.generateThumbnail(from: url, at: 0)
            await MainActor.run {
                videoFirstFrame = frame
                isLoadingVideo = false
            }
        }
    }

    /// Loads the picked images into `images`, appending to any already chosen — always in
    /// the order they were picked.
    ///
    /// Three things keep that order: `.ordered` hands the items back in tap order; they're
    /// decoded into index-aligned slots so one that fails to load can't shift the rest;
    /// and the batch waits on any batch still in flight, so a slow iCloud download picked
    /// first still lands ahead of a quick one picked afterwards.
    ///
    /// A picked video isn't an image: it's copied out of the library and becomes the
    /// post's single video (replacing any earlier pick), with the images loading as usual.
    private func loadImages(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let videoItems = items.filter { $0.isVideo }
        let imageItems = items.filter { !$0.isVideo }

        // Only the last video picked can be kept, since the post holds one.
        if let videoItem = videoItems.last {
            isLoadingVideo = true
            Task {
                let movie = try? await videoItem.loadTransferable(type: VideoTransferable.self)
                await MainActor.run {
                    isLoadingVideo = false
                    if let movie { setVideo(movie.url) }
                }
            }
        }

        guard !imageItems.isEmpty else {
            pickerItems = []
            return
        }
        loadingBatchCount += 1
        let previous = lastLoad
        lastLoad = Task {
            await previous?.value

            var loaded = [UIImage?](repeating: nil, count: imageItems.count)
            for (index, item) in imageItems.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    loaded[index] = UIImage(data: data)
                }
            }

            await MainActor.run {
                images.append(contentsOf: loaded.compactMap { $0 })
                pickerItems = []
                loadingBatchCount -= 1
            }
        }
    }

    /// Appends images that are already decoded (the Files picker hands back finished
    /// `UIImage`s) behind any batch still loading, so a Files pick can't jump ahead of
    /// images that were picked from the library first and are still downloading.
    private func appendInPickOrder(_ picked: [UIImage]) {
        guard !picked.isEmpty else { return }
        guard let previous = lastLoad else {
            images.append(contentsOf: picked)
            return
        }

        loadingBatchCount += 1
        lastLoad = Task {
            await previous.value
            await MainActor.run {
                images.append(contentsOf: picked)
                loadingBatchCount -= 1
            }
        }
    }
}

private extension PhotosPickerItem {
    /// Whether the picked item is a video rather than a still image.
    var isVideo: Bool {
        supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }
    }
}

// MARK: - Image Reorder View

/// Dedicated pushed screen for reordering a design post's images. Uses a vertical `List`
/// with `.onMove` in always-on edit mode so each row shows a drag handle — the standard,
/// reliable way to reorder, avoiding the drag issues of the horizontal strip inside a
/// `List`. Edits the shared `images` binding directly, so changes apply immediately.
private struct DesignImageReorderView: View {
    @Binding var images: [UIImage]

    var body: some View {
        List {
            // Keyed by the UIImage instance (a reference type) so identity is stable
            // across moves, letting rows animate smoothly.
            ForEach(Array(images.enumerated()), id: \.element) { index, image in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.black.opacity(0.6)))

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .onMove { from, to in
                images.move(fromOffsets: from, toOffset: to)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGray6))
        // Always in edit mode so the drag handles are visible without a toolbar toggle.
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Reorder Images")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Design Edit View

/// Edit screen for an existing design submission. Reuses `DesignSubmissionView` so the
/// form is identical to creating a post.
struct DesignEditView: View {
    let submission: Submission
    let onSave: (Submission) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edited: Submission
    @State private var images: [UIImage]
    @State private var credits: CrewInfo
    @State private var videoURL: URL?
    @State private var videoFirstFrame: UIImage?

    init(submission: Submission, onSave: @escaping (Submission) -> Void) {
        self.submission = submission
        self.onSave = onSave
        _edited = State(initialValue: submission)
        _images = State(initialValue: submission.designImageURLs.compactMap { UIImage(contentsOfFile: $0.path) })
        _credits = State(initialValue: CrewInfo(orderedEntries: submission.orderedCrew))
        _videoURL = State(initialValue: submission.videoURL)
    }

    var body: some View {
        NavigationStack {
            DesignSubmissionView(
                title: $edited.title,
                designDescription: $edited.details,
                releaseYear: $edited.releaseYear,
                images: $images,
                videoURL: $videoURL,
                videoFirstFrame: $videoFirstFrame,
                credits: $credits,
                isEditing: true,
                videoCrop: $edited.videoCrop
            )
            .navigationTitle("Edit Design")
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

    private func save() {
        // Re-persist the (possibly reordered/added/removed) images under the
        // deterministic names the upload/parse expect, and refresh the thumbnail.
        edited.designImageFileNames = persistFilmExtraImages(images, submissionID: edited.id, kind: "design")
        if let first = images.first {
            edited.thumbnailData = first.jpegData(compressionQuality: 0.7)
        } else if let frame = videoFirstFrame {
            edited.thumbnailData = frame.jpegData(compressionQuality: 0.7)
        }

        // A replaced video is copied under the same deterministic name the creation
        // form uses; clearing it drops both the file name and the synced duration.
        if let videoURL, videoURL != submission.videoURL {
            let fileName = "video_\(edited.id.uuidString).\(videoURL.pathExtension)"
            edited.videoFileName = persistEditedMediaFile(from: videoURL, as: fileName)
            edited.videoDuration = nil   // re-read from the new file at upload
        } else if videoURL == nil {
            edited.videoFileName = nil
            edited.videoDuration = nil
        }

        edited.orderedCrew = credits.toOrderedEntries()
        onSave(edited)
        dismiss()
    }
}

// MARK: - Design Detail View

/// Feed detail view for a design post: the images (swipeable when there's more than one)
/// or the video, plus title, category, year, description and credits. Mirrors
/// `PhotographyDetailView`'s action buttons and owner controls.
struct DesignDetailView: View {
    private let passedDesign: Submission
    @Binding var liked: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: SubmissionStore_3_2 = .shared

    /// The live version from the store (falling back to the passed-in copy), so edits
    /// appear without reopening the detail.
    private var design: Submission {
        store.approvedSubmissions.first { $0.id == passedDesign.id }
            ?? store.submissions.first { $0.id == passedDesign.id }
            ?? passedDesign
    }

    init(design: Submission, liked: Binding<Bool>) {
        self.passedDesign = design
        self._liked = liked
        // Open the player at the video's known shape (from a previous load or the
        // poster's dimensions) so it doesn't snap from 16:9 later.
        self._videoAspectRatio = State(initialValue: VideoAspectCache.shared.displayAspect(for: design))
    }

    /// The video's width ÷ height (after any playback crop), used to size the inline
    /// player to the post's real shape. `nil` until known (falls back to 16:9).
    @State private var videoAspectRatio: CGFloat?
    @State private var galleryImages: [UIImage] = []
    @State private var currentIndex = 0
    /// The resolved playable video (a local copy, or a streaming CDN URL).
    @State private var resolvedVideoURL: URL?
    /// Set once resolution finishes without a playable video, describing why.
    @State private var streamStatus: VideoStreamStatus?
    @State private var streamDebug: String?
    /// Bumped after an edit replaces the video so the inline player is recreated.
    @State private var videoReloadToken = 0
    /// A tapped credit name, which opens that person's portfolio (as on the other cards).
    @State private var selectedPortfolioName: CreditedPerson?
    @State private var showSendMessage = false
    @State private var showDeleteConfirmation = false
    @State private var showReportSheet = false
    @State private var showEditSheet = false
    @State private var showCollectionPicker = false

    private var iconColor: Color { colorScheme == .dark ? .white : .black }

    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(design.title.hashValue)
        return colors[hash % colors.count]
    }

    /// Whether this post carries a video. The asset itself is omitted from the feed
    /// fetch, so the synced duration is what tells other devices one exists.
    private var hasVideo: Bool {
        design.videoFileName != nil || (design.videoDuration ?? 0) > 0
    }

    private var canEditOrDelete: Bool {
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        let isUserCreator = !currentUser.isEmpty && currentUser == design.submittedBy

        let isModeratorMode = UserDefaults.standard.bool(forKey: "isModeratorMode")
        let canUseModerator = isModeratorMode && ModeratorAccess.isModerator

        return isUserCreator || canUseModerator
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero

                // Title and action buttons
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            // Up to three lines, shrinking rather than truncating so every
                            // word of the title is always visible.
                            Text(design.title)
                                .font(.system(size: 28, weight: .bold))
                                .minimumScaleFactor(0.5)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)

                            // Category on the left, release year pinned to the row's
                            // right edge.
                            GenreReleaseYearRow(
                                genres: design.designCategory,
                                releaseYear: design.releaseYear
                            )
                        }
                        // No Spacer here: the category/year row above is full-width, so
                        // the info column already pushes the buttons right — and a
                        // Spacer would split the leftover width, pulling the year off
                        // the edge.

                        actionButtons
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Description
                VStack(alignment: .leading, spacing: 12) {
                    if !design.details.isEmpty {
                        Text(design.details)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 12)
                    }

                    // When the post has both images and a video, the images are the hero
                    // and the video gets its own section here.
                    if hasVideo && !galleryImages.isEmpty {
                        videoSection
                    }

                    if !design.orderedCrew.isEmpty {
                        creditsSection
                    }

                    if UserDefaults.standard.bool(forKey: "isModeratorMode"), ModeratorAccess.isModerator {
                        Text("Submitted by \(design.submittedBy)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if canEditOrDelete {
                        OwnerActionButtons(
                            onEdit: { showEditSheet = true },
                            onDelete: { showDeleteConfirmation = true }
                        )
                        .padding(.top, 24)
                        .padding(.bottom)
                    }
                }
                .padding()
            }
        }
        .ignoresSafeArea(edges: .top)
        // Hide the grabber bar so the artwork runs to the top edge; swipe-down to dismiss
        // still works.
        .presentationDragIndicator(.hidden)
        .task { loadGallery() }
        .onAppear { PostAnalytics.shared.record(.open, for: design) }
        .sheet(item: $selectedPortfolioName) { person in
            PersonProfileView(name: person.name)
                .onAppear { PostAnalytics.shared.record(.profileVisit, for: design) }
        }
        .sheet(isPresented: $showSendMessage) {
            SendPostMessageView(post: design)
                .onAppear { PostAnalytics.shared.record(.message, for: design) }
        }
        .sheet(isPresented: $showReportSheet) {
            ReportContentView(post: design)
        }
        .sheet(isPresented: $showEditSheet) {
            DesignEditView(submission: design) { updated in
                store.update(updated)
                loadGallery()
                resolvedVideoURL = updated.videoURL
                streamStatus = nil
                videoReloadToken += 1
            }
        }
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerView(post: design)
        }
        .alert("Delete Design?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                store.delete(design)
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    /// The top of the page: the images when there are any, otherwise the video (a
    /// video-only post), otherwise a tinted placeholder.
    @ViewBuilder
    private var hero: some View {
        if !galleryImages.isEmpty {
            gallery
        } else if hasVideo {
            videoPlayer
        } else {
            ZStack {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .clipped()
        }
    }

    /// Swipeable, paged gallery of the post's images.
    private var gallery: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentIndex) {
                ForEach(Array(galleryImages.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .tag(index)
                }
            }
            // The page dots sit beneath the artwork (below) instead of over it.
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity)
            // Size the gallery to the current image's own aspect ratio so it displays at the
            // same shape it was submitted — no letterboxing / black bars.
            .aspectRatio(currentAspectRatio, contentMode: .fit)
            .animation(.default, value: currentIndex)

            GalleryPageDots(count: galleryImages.count, currentIndex: currentIndex)
        }
    }

    /// The video with a heading, shown below the description when the post also has
    /// images (so the images stay the hero).
    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Video")
                .font(.title2)
                .fontWeight(.bold)
            videoPlayer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
    }

    /// The inline player, or an exact placeholder explaining why the video can't play.
    @ViewBuilder
    private var videoPlayer: some View {
        if let videoURL = resolvedVideoURL {
            CustomVideoPlayerView(
                submission: design,
                videoURL: videoURL,
                thumbnailData: design.thumbnailData,
                tintColor: tintColor
            )
            // Recreate the player after an edit replaces the video.
            .id(videoReloadToken)
            // Size the player to the video's real shape rather than forcing 16:9.
            .aspectRatio(videoAspectRatio ?? (16.0 / 9.0), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()
            .task(id: videoReloadToken) {
                if let ratio = await VideoAspectCache.shared.learn(design, from: AVURLAsset(url: videoURL)) {
                    videoAspectRatio = ratio
                }
            }
        } else if let streamStatus {
            VideoUnavailableView(status: streamStatus, tintColor: tintColor, detail: streamDebug, thumbnailData: design.thumbnailData)
        } else {
            VideoStreamingLoadingView(tintColor: tintColor, aspectRatio: videoAspectRatio ?? (16.0 / 9.0))
                .task { await resolveVideo() }
        }
    }

    /// Aspect ratio (width / height) of the currently displayed image, so the gallery
    /// frame matches the artwork instead of a fixed size.
    private var currentAspectRatio: CGFloat {
        guard galleryImages.indices.contains(currentIndex) else { return 4.0 / 3.0 }
        let size = galleryImages[currentIndex].size
        guard size.width > 0, size.height > 0 else { return 4.0 / 3.0 }
        return size.width / size.height
    }

    /// Credited people in the shared detail-card format: a bold section header with each
    /// person's roles on the left and their name (tappable for Nexus members) mirrored
    /// right. Shown only when any credits exist.
    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Credits")
                .font(.title2)
                .fontWeight(.bold)

            ForEach(consolidatedCrew(design.orderedCrew), id: \.name) { consolidated in
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
    }

    /// Groups repeat names into one row with their roles joined, matching the other
    /// detail cards.
    private func consolidatedCrew(_ crew: [OrderedEntry]) -> [(name: String, roles: [String])] {
        var grouped: [String: [String]] = [:]
        var order: [String] = []

        for entry in crew {
            if grouped[entry.name] == nil {
                order.append(entry.name)
                grouped[entry.name] = []
            }
            grouped[entry.name]?.append(entry.role)
        }

        return order.map { name in
            (name: name, roles: grouped[name] ?? [])
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            Button {
                store.toggleLike(for: design)
            } label: {
                Image(systemName: store.isLiked(design) ? "heart.fill" : "heart")
                    .font(.system(size: 20))
                    .foregroundStyle(store.isLiked(design) ? .red : .primary)
                    .frame(minWidth: 30, minHeight: 32)
            }

            Button {
                showCollectionPicker = true
            } label: {
                Image(systemName: store.isInAnyCollection(design) ? "bookmark.fill" : "bookmark")
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

    /// Resolves the playable video. Uses a local copy when one is already on disk;
    /// otherwise streams from a range-supporting CDN URL (never downloaded to the
    /// device). On any non-playable outcome, `streamStatus` records the exact reason.
    private func resolveVideo() async {
        if let local = design.videoURL {
            if await FilmDetailView.hasVideoTrack(local) {
                resolvedVideoURL = local
            } else {
                streamStatus = .unreadable
            }
            return
        }
        guard resolvedVideoURL == nil else { return }

        let (resolution, debug) = await CloudKitManager.shared.streamResolutionDetailed(
            submissionID: design.id, type: .design
        )
        streamDebug = debug
        switch resolution {
        case .streaming(let streamURL):
            resolvedVideoURL = streamURL
        case .assetMissing:
            streamStatus = hasVideo ? .fileNonExistent : .comingSoon
        case .recordNotFound:
            streamStatus = .recordNotFound
        case .noDownloadURL:
            streamStatus = .noDownloadURL
        case .lookupError(let code):
            streamStatus = .errorStreaming(code)
        case .notConfigured:
            streamStatus = .notConfigured
        }
    }

    /// Loads the images from disk; falls back to the thumbnail data if the image files
    /// aren't present.
    private func loadGallery() {
        var loaded = design.designImageURLs.compactMap { UIImage(contentsOfFile: $0.path) }
        if loaded.isEmpty, !hasVideo, let data = design.thumbnailData, let image = UIImage(data: data) {
            loaded = [image]
        }
        galleryImages = loaded
    }
}

// MARK: - Previews

#Preview("Design Submission") {
    @Previewable @State var title = ""
    @Previewable @State var designDescription = ""
    @Previewable @State var releaseYear = "2026"
    @Previewable @State var images: [UIImage] = []
    @Previewable @State var videoURL: URL?
    @Previewable @State var videoFirstFrame: UIImage?
    @Previewable @State var credits = CrewInfo(orderedEntries: [])

    NavigationStack {
        DesignSubmissionView(
            title: $title,
            designDescription: $designDescription,
            releaseYear: $releaseYear,
            images: $images,
            videoURL: $videoURL,
            videoFirstFrame: $videoFirstFrame,
            credits: $credits
        )
        .navigationTitle("Design")
        .navigationBarTitleDisplayMode(.inline)
    }
}
