//
//  PhotographySubmissionView.swift
//  Longhorn Artists Connect
//
//  Photography submission form — a gallery of photos with a photographer, description,
//  and year. Also hosts the owner edit form and the feed detail (gallery) view.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Photography Submission Form

struct PhotographySubmissionView: View {
    @Binding var title: String
    /// The photographer, shown under the title (mirrors music's Artist).
    @Binding var artist: String
    @Binding var photoDescription: String
    /// The year the photos were taken/released.
    @Binding var releaseYear: String
    /// The picked gallery images. The first doubles as the post thumbnail.
    @Binding var images: [UIImage]
    /// The gear used for the shoot (camera, lens, etc.). Edited on a pushed subpage.
    @Binding var equipment: EquipmentInfo
    /// People credited on the shoot (models, stylists, assistants, etc.). Edited on a
    /// pushed subpage and stored as the post's crew credits.
    @Binding var credits: CrewInfo

    /// Live CloudKit upload state, set once the post is submitted.
    var uploadPhase: MediaUploadPhase? = nil
    var onRetryUpload: () -> Void = {}

    /// When true this form is editing an existing post; behaves the same, it's only used
    /// to label the picker.
    var isEditing: Bool = false

    @State private var pickerItems: [PhotosPickerItem] = []
    /// Picker batches still loading. Library photos can take seconds to come down from
    /// iCloud, so more than one batch can be in flight at once.
    @State private var loadingBatchCount = 0
    /// The most recently enqueued batch. Each new batch waits on this one before it
    /// appends, so photos land in the order they were picked rather than the order they
    /// happened to finish loading.
    @State private var lastLoad: Task<Void, Never>?
    /// Camera-roll (Photos) and Files pickers for the gallery, mirroring the other
    /// submission views' two-button layout.
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    /// Drives the pushed Equipment subpage.
    @State private var showEquipmentForm = false
    /// Drives the pushed Credits subpage.
    @State private var showCreditsForm = false
    /// Drives the pushed Reorder subpage.
    @State private var showReorderForm = false

    private var isLoadingImages: Bool { loadingBatchCount > 0 }

    var body: some View {
        List {
            // Photography has no category picker, so the form opens straight on Upload.
            Section("Upload") {
                if let uploadPhase {
                    MediaUploadStatusView(phase: uploadPhase, onRetry: onRetryUpload)
                } else {
                    photoGallery
                    photoPickerRow
                    if isLoadingImages {
                        HStack {
                            ProgressView().padding(.trailing, 8)
                            Text("Loading photos…").foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if uploadPhase == nil {
                Section("Details") {
                    TextField("Title", text: $title, axis: .vertical)
                    // Photographer can be credited to a registered user.
                    CreditNameField(placeholder: "Photographer", text: $artist)

                    TextField("Description", text: $photoDescription, axis: .vertical)
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

                    Button {
                        showEquipmentForm = true
                    } label: {
                        HStack {
                            Text("Equipment")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(equipment.isEmpty ? "Add" : "Edited")
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
        // Navigation destination lives on the List, not on a row inside it: rows in a
        // lazy container may not exist yet, so a destination declared there can be missed.
        .navigationDestination(isPresented: $showEquipmentForm) {
            EquipmentFormView(equipment: $equipment)
        }
        .navigationDestination(isPresented: $showCreditsForm) {
            CrewFormView(
                crew: $credits,
                navigationTitle: "Credits",
                sectionTitle: "Credits",
                addButtonTitle: "Add Credit"
            )
        }
        .navigationDestination(isPresented: $showReorderForm) {
            PhotoReorderView(images: $images)
        }
        // `.ordered` numbers the picks and hands them back in tap order, so the numbered
        // selection order becomes the order they appear in the post. `nil` is the
        // documented way to ask for the system maximum (0 isn't a defined value).
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItems,
                      maxSelectionCount: nil, selectionBehavior: .ordered, matching: .images)
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
    }

    /// "Select photos" header row: label, count, and Photos + Files pickers — matching the
    /// two-button layout used by the film/reel submission views.
    private var photoPickerRow: some View {
        HStack {
            Label(images.isEmpty ? "Select photos" : "Add more photos", systemImage: "camera")
                .foregroundStyle(.primary)
            if !images.isEmpty {
                Text("\(images.count)")
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

    /// Horizontal strip of chosen photos, each shown at its real aspect ratio (fixed
    /// height, variable width), numbered at the top-left, and removable at the top-right.
    /// Reordering is done on a dedicated pushed screen via the "Reorder" button, since
    /// drag-to-reorder doesn't work reliably inside this `List`-hosted horizontal strip.
    @ViewBuilder
    private var photoGallery: some View {
        if !images.isEmpty {
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

    /// Loads the picked photos into `images`, appending to any already chosen — always in
    /// the order they were picked.
    ///
    /// Three things keep that order: `.ordered` hands the items back in tap order; they're
    /// decoded into index-aligned slots so one that fails to load can't shift the rest;
    /// and the batch waits on any batch still in flight, so a slow iCloud download picked
    /// first still lands ahead of a quick one picked afterwards.
    private func loadImages(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        loadingBatchCount += 1
        let previous = lastLoad
        lastLoad = Task {
            await previous?.value

            var loaded = [UIImage?](repeating: nil, count: items.count)
            for (index, item) in items.enumerated() {
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
    /// photos that were picked from the library first and are still downloading.
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

// MARK: - Photo Reorder View

/// Dedicated pushed screen for reordering the gallery photos. Uses a vertical `List` with
/// `.onMove` in always-on edit mode so each row shows a drag handle — the standard,
/// reliable way to reorder, avoiding the drag issues of the horizontal strip inside a
/// `List`. Edits the shared `images` binding directly, so changes apply immediately.
///
/// Also used by the project form's slideshow, which is why the title is a parameter.
struct PhotoReorderView: View {
    @Binding var images: [UIImage]
    var navigationTitle: String = "Reorder Photos"

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
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Photography Edit View

/// Edit screen for an existing photography submission. Reuses `PhotographySubmissionView`
/// so the form is identical to creating a post.
struct PhotographyEditView: View {
    let submission: Submission
    let onSave: (Submission) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edited: Submission
    @State private var images: [UIImage]
    @State private var credits: CrewInfo

    init(submission: Submission, onSave: @escaping (Submission) -> Void) {
        self.submission = submission
        self.onSave = onSave
        _edited = State(initialValue: submission)
        _images = State(initialValue: submission.photoImageURLs.compactMap { UIImage(contentsOfFile: $0.path) })
        _credits = State(initialValue: CrewInfo(orderedEntries: submission.orderedCrew))
    }

    var body: some View {
        NavigationStack {
            PhotographySubmissionView(
                title: $edited.title,
                artist: $edited.artist,
                photoDescription: $edited.details,
                releaseYear: $edited.releaseYear,
                images: $images,
                equipment: $edited.equipment,
                credits: $credits,
                isEditing: true
            )
            .navigationTitle("Edit Photography")
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
        // Re-persist the (possibly reordered/added/removed) gallery under the deterministic
        // names the upload/parse expect, and refresh the thumbnail from the first image.
        edited.photoImageFileNames = persistFilmExtraImages(images, submissionID: edited.id, kind: "photo")
        if let first = images.first {
            edited.thumbnailData = first.jpegData(compressionQuality: 0.7)
        }
        edited.orderedCrew = credits.toOrderedEntries()
        onSave(edited)
        dismiss()
    }
}

// MARK: - Photography Detail View

/// Feed detail view for a photography post: a swipeable gallery plus title, photographer,
/// year, and description. Mirrors `ReelDetailView`'s action buttons and owner controls.
struct PhotographyDetailView: View {
    private let passedPhotography: Submission
    @Binding var liked: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: SubmissionStore_3_2 = .shared

    /// The live version from the store (falling back to the passed-in copy), so edits
    /// appear without reopening the detail.
    private var photography: Submission {
        store.approvedSubmissions.first { $0.id == passedPhotography.id }
            ?? store.submissions.first { $0.id == passedPhotography.id }
            ?? passedPhotography
    }

    init(photography: Submission, liked: Binding<Bool>) {
        self.passedPhotography = photography
        self._liked = liked
    }

    @State private var galleryImages: [UIImage] = []
    @State private var currentIndex = 0
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
        let hash = abs(photography.title.hashValue)
        return colors[hash % colors.count]
    }

    private var canEditOrDelete: Bool {
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        let isUserCreator = !currentUser.isEmpty && currentUser == photography.submittedBy

        let isModeratorMode = UserDefaults.standard.bool(forKey: "isModeratorMode")
        let canUseModerator = isModeratorMode && ModeratorAccess.isModerator

        return isUserCreator || canUseModerator
    }

    /// Whether this post is one of Collective's magazines (matched by title against the
    /// hardcoded catalog). Those are identified by volume, not by a release year.
    private var isCollectiveMagazine: Bool {
        let key = CollectiveStudios.normalize(photography.title)
        return OrgProjectCatalog.projects(orgSlug: "collective", section: .magazines)
            .contains { CollectiveStudios.normalize($0.title) == key }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                gallery

                // Title and action buttons
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(photography.title)
                                .font(.system(size: 28, weight: .bold))
                                .minimumScaleFactor(0.6)
                                .lineLimit(2)

                            // Category and release year, the year pinned to the row's
                            // right edge — except for Collective's magazines, which read
                            // "Collective" there instead. (Photography has no category
                            // picker yet, so the left side is usually empty for now.)
                            GenreReleaseYearRow(
                                genres: photography.genres.joined(separator: " • "),
                                releaseYear: isCollectiveMagazine ? "Collective" : photography.releaseYear
                            )
                        }
                        // No Spacer here: the genre/year row above is full-width, so the
                        // info column already pushes the buttons right — and a Spacer
                        // would split the leftover width, pulling the year off the edge.

                        actionButtons
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Description
                VStack(alignment: .leading, spacing: 12) {
                    if !photography.details.isEmpty {
                        Text(photography.details)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 12)
                    }

                    if !allCredits.isEmpty {
                        creditsSection
                    }

                    if !photography.equipment.isEmpty {
                        equipmentSection
                    }

                    if UserDefaults.standard.bool(forKey: "isModeratorMode"), ModeratorAccess.isModerator {
                        Text("Submitted by \(photography.submittedBy)")
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
        // Hide the grabber bar so the photo runs to the top edge; swipe-down to dismiss
        // still works.
        .presentationDragIndicator(.hidden)
        .task { loadGallery() }
        .sheet(item: $selectedPortfolioName) { person in
            PersonProfileView(name: person.name)
        }
        .sheet(isPresented: $showSendMessage) {
            SendPostMessageView(post: photography)
        }
        .sheet(isPresented: $showReportSheet) {
            ReportContentView(post: photography)
        }
        .sheet(isPresented: $showEditSheet) {
            PhotographyEditView(submission: photography) { updated in
                store.update(updated)
                loadGallery()
            }
        }
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerView(post: photography)
        }
        .alert("Delete Photography?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                store.delete(photography)
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    /// Swipeable, paged gallery of the post's photos. Falls back to the thumbnail (or a
    /// gradient placeholder) if the gallery hasn't resolved yet.
    @ViewBuilder
    private var gallery: some View {
        if galleryImages.isEmpty {
            ZStack {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                Image(systemName: "camera")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .clipped()
        } else {
            TabView(selection: $currentIndex) {
                ForEach(Array(galleryImages.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: galleryImages.count > 1 ? .automatic : .never))
            .frame(maxWidth: .infinity)
            // Size the gallery to the current photo's own aspect ratio so it displays at
            // the same shape it was submitted — no letterboxing / black bars.
            .aspectRatio(currentAspectRatio, contentMode: .fit)
            .animation(.default, value: currentIndex)
        }
    }

    /// Aspect ratio (width / height) of the currently displayed gallery image, so the
    /// gallery frame matches the photo instead of a fixed size.
    private var currentAspectRatio: CGFloat {
        guard galleryImages.indices.contains(currentIndex) else { return 4.0 / 3.0 }
        let size = galleryImages[currentIndex].size
        guard size.width > 0, size.height > 0 else { return 4.0 / 3.0 }
        return size.width / size.height
    }

    /// The post's credits, led by the photographer so they're listed alongside everyone
    /// else rather than standing alone under the title.
    private var allCredits: [OrderedEntry] {
        let photographer = photography.artist.trimmingCharacters(in: .whitespaces)
        var entries: [OrderedEntry] = []
        if !photographer.isEmpty {
            entries.append(OrderedEntry(role: "Photographer", name: photographer))
        }
        entries.append(contentsOf: photography.orderedCrew)
        return entries
    }

    /// Credited people in the shared detail-card format: a bold section header with each
    /// person's roles on the left and their name (tappable for Nexus members) mirrored
    /// right. Shown only when any credits exist.
    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Credits")
                .font(.title2)
                .fontWeight(.bold)

            ForEach(consolidatedCrew(allCredits), id: \.name) { consolidated in
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

    /// Read-only list of the gear used, shown only when the photographer entered any.
    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Equipment")
                .font(.headline)

            ForEach(photography.equipment.labeledEntries, id: \.label) { entry in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(entry.label):")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(entry.value)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            Button {
                store.toggleLike(for: photography)
            } label: {
                Image(systemName: store.isLiked(photography) ? "heart.fill" : "heart")
                    .font(.system(size: 20))
                    .foregroundStyle(store.isLiked(photography) ? .red : .primary)
                    .frame(minWidth: 30, minHeight: 32)
            }

            Button {
                showCollectionPicker = true
            } label: {
                Image(systemName: store.isInAnyCollection(photography) ? "bookmark.fill" : "bookmark")
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

    /// Loads the gallery images from disk; falls back to the thumbnail data if the gallery
    /// files aren't present.
    private func loadGallery() {
        var loaded = photography.photoImageURLs.compactMap { UIImage(contentsOfFile: $0.path) }
        if loaded.isEmpty, let data = photography.thumbnailData, let image = UIImage(data: data) {
            loaded = [image]
        }
        galleryImages = loaded
    }
}

// MARK: - Equipment Form

/// Pushed subpage for entering the gear used on a shoot. Each field is optional and
/// freeform; blank fields are simply omitted when the post is displayed.
struct EquipmentFormView: View {
    @Binding var equipment: EquipmentInfo

    var body: some View {
        List {
            Section("Camera") {
                TextField("e.g., Canon EOS R5", text: $equipment.camera, axis: .vertical)
            }
            Section("Lens") {
                TextField("e.g., RF 24-70mm f/2.8", text: $equipment.lens, axis: .vertical)
            }
            Section("Lighting") {
                TextField("e.g., Godox AD200, natural light", text: $equipment.lighting, axis: .vertical)
            }
            Section("Filters") {
                TextField("e.g., Polarizer, ND1000", text: $equipment.filters, axis: .vertical)
            }
            Section("Support") {
                TextField("e.g., Tripod, gimbal, monopod", text: $equipment.support, axis: .vertical)
            }
            Section {
                TextField("e.g., Drone, editing software", text: $equipment.accessories, axis: .vertical)
            } header: {
                Text("Other Equipment")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGray6))
        .navigationTitle("Equipment")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview("Photography Submission") {
    @Previewable @State var title = ""
    @Previewable @State var artist = ""
    @Previewable @State var photoDescription = ""
    @Previewable @State var releaseYear = "2026"
    @Previewable @State var images: [UIImage] = []
    @Previewable @State var equipment = EquipmentInfo()
    @Previewable @State var credits = CrewInfo(orderedEntries: [])

    NavigationStack {
        PhotographySubmissionView(
            title: $title,
            artist: $artist,
            photoDescription: $photoDescription,
            releaseYear: $releaseYear,
            images: $images,
            equipment: $equipment,
            credits: $credits
        )
        .navigationTitle("Photography")
        .navigationBarTitleDisplayMode(.inline)
    }
}
