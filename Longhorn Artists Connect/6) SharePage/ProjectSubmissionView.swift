//
//  ProjectSubmissionView.swift
//  Longhorn Artists Connect
//
//  Project submission form - for casting calls and crew hiring
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PDFKit

// MARK: - Project Type

/// The three kinds of project post. Each shows its own fields, thumbnail, and Discover
/// description:
/// - `castCrewCall`: poster + logline + shoot dates + cast/crew needed + assembled team.
/// - `script`: a script PDF + genre + writer (+ optional logline). Thumbnail = first page.
/// - `inDevelopment`: a flyer + writers + current cast & crew (no script).
enum ProjectType: String, CaseIterable {
    case castCrewCall = "Cast & Crew Call"
    case script = "Script"
    case inDevelopment = "In-Development"
}

/// Genres offered for a Script project (mirrors the Scripts collection's list).
let projectScriptGenres = ["Action", "Comedy", "Drama", "Horror", "Mystery", "Romance", "Sci-Fi", "Thriller", "Western", "Documentary"]

/// Renders the first page of a script PDF to JPEG data and reports its page count, for
/// use as a Script project's thumbnail. Returns `(nil, 0)` for non-PDF or unreadable files.
enum ScriptThumbnail {
    static func make(from url: URL, maxWidth: CGFloat = 500) -> (image: Data?, pageCount: Int) {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return (nil, 0) }
        let bounds = page.bounds(for: .mediaBox)
        let scale = bounds.width > 0 ? maxWidth / bounds.width : 1
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = page.thumbnail(of: size, for: .mediaBox)
        return (image.jpegData(compressionQuality: 0.8), doc.pageCount)
    }
}

struct ProjectSubmissionView: View {
    @Binding var title: String
    @Binding var logline: String
    /// The selected `ProjectType` raw value.
    @Binding var projectCategory: String
    /// Writer(s) — used by Script and In-Development.
    @Binding var writers: String
    /// Genre — used by Script (stored in the submission's `genres`).
    @Binding var projectGenre: String
    @Binding var shootStartDate: Date
    @Binding var shootEndDate: Date
    @Binding var projectReleaseDate: Date
    @Binding var castNeeded: [String]
    @Binding var crewNeeded: [String]
    @Binding var castInfo: CastInfo
    @Binding var crewInfo: CrewInfo
    @Binding var selectedProjectImageData: Data?
    @Binding var selectedProjectScriptURL: URL?
    @Binding var showProjectImagePicker: Bool
    @Binding var showProjectImageDocumentPicker: Bool
    @Binding var showProjectScriptPicker: Bool
    /// The slideshow images, in the order they were picked. When any are chosen they
    /// replace the poster on the post's detail view and the poster is shown last, after
    /// them; the Discover feed still previews the poster.
    @Binding var slides: [UIImage]

    /// Live CloudKit upload state, set once the post is submitted.
    var uploadPhase: MediaUploadPhase? = nil
    var onRetryUpload: () -> Void = {}

    /// When true this form is editing an existing post: the poster/script stay visible but
    /// can't be replaced, so their picker buttons are hidden. Every other field behaves
    /// exactly as it does when creating a post.
    var isEditing: Bool = false

    /// Live progress of pulling the picked poster out of Photos/Files. Images expose
    /// no progress, so this drives an indeterminate spinner while it loads.
    @ObservedObject private var downloadCenter = MediaDownloadCenter.shared

    @State private var showCastNeededForm: Bool = false
    @State private var showCrewNeededForm: Bool = false
    @State private var showCastAssembledForm: Bool = false
    @State private var showCrewAssembledForm: Bool = false

    // Slide pickers (Photos + Files). Unlike the poster's, these are hosted here rather
    // than by the parent, so the create and edit forms both get them for free.
    @State private var slidePickerItems: [PhotosPickerItem] = []
    @State private var showSlidePhotoPicker: Bool = false
    @State private var showSlideFilePicker: Bool = false
    /// Drives the pushed Reorder subpage.
    @State private var showSlideReorderForm: Bool = false
    /// Picker batches still loading. Library photos can take seconds to come down from
    /// iCloud, so more than one batch can be in flight at once.
    @State private var loadingSlideBatches = 0
    /// The most recently enqueued batch. Each new batch waits on this one before it
    /// appends, so slides land in the order they were picked rather than the order they
    /// happened to finish loading.
    @State private var lastSlideLoad: Task<Void, Never>?

    private var projectType: ProjectType? { ProjectType(rawValue: projectCategory) }

    /// Category selector — its own section; the rest of the form stays hidden until a
    /// category is chosen.
    private var typeMenu: some View {
        Menu {
            ForEach(ProjectType.allCases, id: \.self) { kind in
                Button {
                    projectCategory = kind.rawValue
                } label: {
                    HStack {
                        Text(kind.rawValue)
                        if projectCategory == kind.rawValue {
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
                Text(projectCategory.isEmpty ? "Select Category" : projectCategory)
                    .foregroundStyle(Color.brandOrange)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        List {
            // Category first, and on its own until it's chosen: the rest of the form
            // stays hidden until then.
            Section("Category") { typeMenu }

            if let type = projectType {
                Section("Upload") {
                    if let uploadPhase {
                        MediaUploadStatusView(phase: uploadPhase, onRetry: onRetryUpload)
                    } else {
                        posterRow(label: "poster")
                        slideStrip
                        slidePickerRow
                        if loadingSlideBatches > 0 {
                            HStack {
                                ProgressView().padding(.trailing, 8)
                                Text("Loading slides…").foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if uploadPhase == nil {
                    switch type {
                    case .castCrewCall:  castCrewCallSections
                    case .script:        scriptSections
                    case .inDevelopment: inDevelopmentSections
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGray6))
        // Push these to the side (like the Film cast/crew pages) rather than
        // presenting them as bottom sheets.
        .navigationDestination(isPresented: $showCastNeededForm) {
            ProjectCastNeededFormView(castNeeded: $castNeeded)
        }
        .navigationDestination(isPresented: $showCrewNeededForm) {
            ProjectCrewNeededFormView(crewNeeded: $crewNeeded)
        }
        .navigationDestination(isPresented: $showCastAssembledForm) {
            CastFormView(cast: $castInfo)
        }
        .navigationDestination(isPresented: $showCrewAssembledForm) {
            CrewFormView(crew: $crewInfo)
        }
        .navigationDestination(isPresented: $showSlideReorderForm) {
            PhotoReorderView(images: $slides, navigationTitle: "Reorder Slides")
        }
        // `.ordered` numbers the picks and hands them back in tap order, so the numbered
        // selection order becomes the slideshow's order. `nil` is the documented way to
        // ask for the system maximum (0 isn't a defined value).
        .photosPicker(isPresented: $showSlidePhotoPicker, selection: $slidePickerItems,
                      maxSelectionCount: nil, selectionBehavior: .ordered, matching: .images)
        .onChange(of: slidePickerItems) { _, newItems in
            loadSlides(from: newItems)
        }
        .sheet(isPresented: $showSlideFilePicker) {
            MultiImageDocumentPicker { picked in
                appendSlidesInPickOrder(picked)
                showSlideFilePicker = false
            } onCancel: {
                showSlideFilePicker = false
            }
        }
    }

    // MARK: - Per-Type Sections

    @ViewBuilder private var castCrewCallSections: some View {
        Section("Details") {
            TextField("Title", text: $title, axis: .vertical)
            TextField("Logline", text: $logline, axis: .vertical)
                .lineLimit(3...6)
            DatePicker("Shoot Start", selection: $shootStartDate, displayedComponents: .date)
            DatePicker("Shoot End", selection: $shootEndDate, displayedComponents: .date)
            DatePicker("Expected Release", selection: $projectReleaseDate, displayedComponents: .date)
        }
        teamNeededSection
        assembledTeamSection
    }

    @ViewBuilder private var scriptSections: some View {
        Section("Details") {
            TextField("Title", text: $title, axis: .vertical)
            scriptRow
            genreMenu
            TextField("Writer", text: $writers, axis: .vertical)
            TextField("Logline (optional)", text: $logline, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    @ViewBuilder private var inDevelopmentSections: some View {
        Section("Details") {
            TextField("Title", text: $title, axis: .vertical)
            TextField("Writers", text: $writers, axis: .vertical)
            TextField("Logline (optional)", text: $logline, axis: .vertical)
                .lineLimit(3...6)
        }
        assembledTeamSection
    }

    // MARK: - Reusable Rows

    /// Poster/flyer picker row (Photos + Files). `label` is the noun shown ("poster"/"flyer").
    private func posterRow(label: String) -> some View {
        Group {
            if downloadCenter.isLoadingImage {
                ImagePullRow()
            } else {
                HStack {
                    UploadRowThumbnail(image: selectedProjectImageData.flatMap(UIImage.init),
                                       placeholderSystemName: "richtext.page")
                    Text(selectedProjectImageData == nil ? "Select \(label)" : "\(label.capitalized) selected")
                        .foregroundStyle(.primary)
                    if selectedProjectImageData != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.brandOrange)
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Button { showProjectImagePicker = true } label: {
                            Label("Photos", systemImage: "photo.stack").labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)

                        Button { showProjectImageDocumentPicker = true } label: {
                            Label("Files", systemImage: "folder").labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                    }
                }
            }
        }
    }

    /// "Select slides" row: label, count, and the Photos + Files pickers — the same
    /// two-button layout as the poster row above, but multi-select.
    private var slidePickerRow: some View {
        HStack {
            Text(slides.isEmpty ? "Select slides" : "Add more slides")
                .foregroundStyle(.primary)
            if !slides.isEmpty {
                Text("\(slides.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandOrange)
            }
            Spacer()
            HStack(spacing: 12) {
                Button { showSlidePhotoPicker = true } label: {
                    Label("Photos", systemImage: "photo.stack").labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.primary)

                Button { showSlideFilePicker = true } label: {
                    Label("Files", systemImage: "folder").labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
            }
        }
    }

    /// Horizontal strip of the chosen slides, each shown at its real aspect ratio,
    /// numbered in slideshow order at the top-left and removable at the top-right.
    /// Reordering is done on a dedicated pushed screen via the "Reorder" button, since
    /// drag-to-reorder doesn't work reliably in a horizontal strip inside a `List`.
    @ViewBuilder
    private var slideStrip: some View {
        if !slides.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Keyed by the UIImage instance (a reference type) so identity is
                        // stable across reorders, letting the move animate smoothly.
                        ForEach(Array(slides.enumerated()), id: \.element) { index, image in
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
                                        slides.remove(at: index)
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

                if slides.count > 1 {
                    Button {
                        showSlideReorderForm = true
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

    /// Loads the picked slides, appending to any already chosen — always in the order
    /// they were picked. `.ordered` hands the items back in tap order; they're decoded
    /// into index-aligned slots so one that fails to load can't shift the rest; and the
    /// batch waits on any batch still in flight, so a slow iCloud download picked first
    /// still lands ahead of a quick one picked afterwards.
    private func loadSlides(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        loadingSlideBatches += 1
        let previous = lastSlideLoad
        lastSlideLoad = Task {
            await previous?.value

            var loaded = [UIImage?](repeating: nil, count: items.count)
            for (index, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    loaded[index] = UIImage(data: data)
                }
            }

            await MainActor.run {
                slides.append(contentsOf: loaded.compactMap { $0 })
                slidePickerItems = []
                loadingSlideBatches -= 1
            }
        }
    }

    /// Appends slides that are already decoded (the Files picker hands back finished
    /// `UIImage`s) behind any batch still loading, so a Files pick can't jump ahead of
    /// library photos that were picked first and are still downloading.
    private func appendSlidesInPickOrder(_ picked: [UIImage]) {
        guard !picked.isEmpty else { return }
        guard let previous = lastSlideLoad else {
            slides.append(contentsOf: picked)
            return
        }

        loadingSlideBatches += 1
        lastSlideLoad = Task {
            await previous.value
            await MainActor.run {
                slides.append(contentsOf: picked)
                loadingSlideBatches -= 1
            }
        }
    }

    /// Script PDF picker row (Script projects).
    private var scriptRow: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(selectedProjectScriptURL == nil ? "Select script (PDF)" : "Script attached")
                .foregroundStyle(.primary)
            if selectedProjectScriptURL != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
            Spacer()
            Button { showProjectScriptPicker = true } label: {
                Label("Files", systemImage: "folder").labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .tint(.primary)
        }
    }

    /// Genre menu (Script projects).
    private var genreMenu: some View {
        Menu {
            ForEach(projectScriptGenres, id: \.self) { g in
                Button {
                    projectGenre = g
                } label: {
                    HStack {
                        Text(g)
                        if projectGenre == g { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack {
                Text("Genre").foregroundStyle(.primary)
                Spacer()
                Text(projectGenre.isEmpty ? "Select Genre" : projectGenre)
                    .foregroundStyle(Color.brandOrange)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
        }
        .buttonStyle(.plain)
    }

    private var teamNeededSection: some View {
        Section("Team Needed") {
            Button {
                showCastNeededForm = true
            } label: {
                HStack {
                    Text("Cast Needed").foregroundStyle(.primary)
                    Spacer()
                    Text(castNeeded.isEmpty ? "Add" : "\(castNeeded.count) role\(castNeeded.count == 1 ? "" : "s")")
                        .foregroundStyle(Color.brandOrange)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.brandOrange)
                }
            }
            .buttonStyle(.plain)

            Button {
                showCrewNeededForm = true
            } label: {
                HStack {
                    Text("Crew Needed").foregroundStyle(.primary)
                    Spacer()
                    Text(crewNeeded.isEmpty ? "Add" : "\(crewNeeded.count) role\(crewNeeded.count == 1 ? "" : "s")")
                        .foregroundStyle(Color.brandOrange)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.brandOrange)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var assembledTeamSection: some View {
        Section("Assembled Team") {
            Button {
                showCastAssembledForm = true
            } label: {
                HStack {
                    Text("Cast Assembled").foregroundStyle(.primary)
                    Spacer()
                    Text(castInfo.summary.isEmpty ? "Add" : "Edited").foregroundStyle(Color.brandOrange)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.brandOrange)
                }
            }
            .buttonStyle(.plain)

            Button {
                showCrewAssembledForm = true
            } label: {
                HStack {
                    Text("Crew Assembled").foregroundStyle(.primary)
                    Spacer()
                    Text(crewInfo.summary.isEmpty ? "Add" : "Edited").foregroundStyle(Color.brandOrange)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.brandOrange)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - ProjectRole Model

struct ProjectRole: Identifiable, Codable, Equatable {
    let id: UUID
    var roleName: String
    var assignedName: String

    init(id: UUID = UUID(), roleName: String = "", assignedName: String = "") {
        self.id = id
        self.roleName = roleName
        self.assignedName = assignedName
    }
}

// MARK: - Project Edit View

/// Edit screen for an existing project submission. Reuses `ProjectSubmissionView` so the
/// form is identical to creating a project; only the already-submitted poster/script is
/// shown read-only and can't be replaced.
struct ProjectEditView: View {
    let submission: Submission
    let onSave: (Submission) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edited: Submission
    @State private var castInfo: CastInfo
    @State private var crewInfo: CrewInfo
    @State private var shootStartDate: Date
    @State private var shootEndDate: Date
    @State private var projectReleaseDate: Date
    @State private var selectedProjectImageData: Data?
    @State private var selectedProjectScriptURL: URL?
    @State private var slides: [UIImage]

    /// Matches the "MMM d, yyyy" format the creation form writes into `shootDates` /
    /// `expectedReleaseDate` so re-editing round-trips consistently.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    /// Parses one "MMM d, yyyy" date, defaulting to now for loose/legacy values.
    private static func parseDate(_ string: String) -> Date {
        dateFormatter.date(from: string.trimmingCharacters(in: .whitespaces)) ?? Date()
    }

    init(submission: Submission, onSave: @escaping (Submission) -> Void) {
        self.submission = submission
        self.onSave = onSave
        _edited = State(initialValue: submission)
        _castInfo = State(initialValue: CastInfo(orderedEntries: submission.orderedCast))
        _crewInfo = State(initialValue: CrewInfo(orderedEntries: submission.orderedCrew))

        // `shootDates` is stored as "start - end"; split it back into the two pickers.
        let parts = submission.shootDates.components(separatedBy: " - ")
        _shootStartDate = State(initialValue: Self.parseDate(parts.first ?? ""))
        _shootEndDate = State(initialValue: Self.parseDate(parts.count > 1 ? parts[1] : (parts.first ?? "")))
        _projectReleaseDate = State(initialValue: Self.parseDate(submission.expectedReleaseDate))

        _selectedProjectImageData = State(initialValue: submission.thumbnailData)
        _selectedProjectScriptURL = State(initialValue: submission.scriptURL)
        // Restore the slideshow from its persisted media-cache copies.
        _slides = State(initialValue: submission.projectSlideURLs.compactMap { UIImage(contentsOfFile: $0.path) })
    }

    /// The project type is stored in `projectType`.
    private var categoryBinding: Binding<String> {
        Binding(
            get: { edited.projectType },
            set: { edited.projectType = $0 }
        )
    }

    /// Script genre is stored in the submission's `genres`.
    private var genreBinding: Binding<String> {
        Binding(
            get: { edited.genres.first ?? "" },
            set: { edited.genres = $0.isEmpty ? [] : [$0] }
        )
    }

    // The poster/script pickers are presented by the parent in the create flow, so the
    // edit screen hosts them itself.
    @State private var showProjectImagePicker = false
    @State private var showProjectImageDocumentPicker = false
    @State private var showProjectScriptPicker = false
    @State private var projectImageItem: PhotosPickerItem?
    /// True once the user picks a new script, so `save()` copies/re-uploads it.
    @State private var scriptWasReplaced = false

    var body: some View {
        NavigationStack {
            ProjectSubmissionView(
                title: $edited.title,
                logline: $edited.logline,
                projectCategory: categoryBinding,
                writers: $edited.writers,
                projectGenre: genreBinding,
                shootStartDate: $shootStartDate,
                shootEndDate: $shootEndDate,
                projectReleaseDate: $projectReleaseDate,
                castNeeded: $edited.castNeeded,
                crewNeeded: $edited.crewNeeded,
                castInfo: $castInfo,
                crewInfo: $crewInfo,
                selectedProjectImageData: $selectedProjectImageData,
                selectedProjectScriptURL: $selectedProjectScriptURL,
                showProjectImagePicker: $showProjectImagePicker,
                showProjectImageDocumentPicker: $showProjectImageDocumentPicker,
                showProjectScriptPicker: $showProjectScriptPicker,
                slides: $slides,
                isEditing: true
            )
            .navigationTitle("Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .photosPicker(isPresented: $showProjectImagePicker, selection: $projectImageItem, matching: .images)
            .onChange(of: projectImageItem) { _, newItem in
                guard let newItem else { return }
                MediaDownloadCenter.shared.beginImageLoad()
                Task {
                    let data = try? await newItem.loadTransferable(type: Data.self)
                    await MainActor.run {
                        if let data { selectedProjectImageData = data }
                        projectImageItem = nil
                        MediaDownloadCenter.shared.finishImageLoad()
                    }
                }
            }
            .sheet(isPresented: $showProjectImageDocumentPicker) {
                DocumentPicker(contentTypes: [.image, .jpeg, .png]) { url in
                    if let data = try? Data(contentsOf: url) { selectedProjectImageData = data }
                    showProjectImageDocumentPicker = false
                } onCancel: {
                    showProjectImageDocumentPicker = false
                }
            }
            .sheet(isPresented: $showProjectScriptPicker) {
                DocumentPicker(contentTypes: [.pdf, .plainText, .rtf, .rtfd]) { url in
                    selectedProjectScriptURL = url
                    scriptWasReplaced = true
                    showProjectScriptPicker = false
                } onCancel: {
                    showProjectScriptPicker = false
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

    private func save() {
        guard !edited.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // Fold the pickers back into the stored string fields, matching the creation form.
        edited.shootDates = Self.dateFormatter.string(from: shootStartDate) + " - " + Self.dateFormatter.string(from: shootEndDate)
        edited.expectedReleaseDate = Self.dateFormatter.string(from: projectReleaseDate)
        // Drop empty role/position rows before saving.
        edited.castNeeded.removeAll { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        edited.crewNeeded.removeAll { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        edited.orderedCast = castInfo.toOrderedEntries()
        edited.orderedCrew = crewInfo.toOrderedEntries()

        // Poster art is stored as the submission's thumbnail data.
        edited.thumbnailData = selectedProjectImageData

        // Re-persist the (possibly added to / removed from) slideshow under the
        // deterministic names the upload and parse expect.
        edited.projectSlideFileNames = slides.isEmpty
            ? nil
            : persistFilmExtraImages(slides, submissionID: edited.id, kind: "slide")

        // Persist a replaced script into Documents so it re-uploads to CloudKit, and
        // refresh the first-page thumbnail + page count from the new PDF.
        if scriptWasReplaced, let url = selectedProjectScriptURL {
            let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
            if let name = persistEditedMediaFile(from: url, as: "script_\(edited.id.uuidString).\(ext)") {
                edited.scriptFileName = name
            }
            let (thumb, pages) = ScriptThumbnail.make(from: url)
            if let thumb { edited.thumbnailData = thumb }
            edited.scriptPageCount = pages
        }

        onSave(edited)
        dismiss()
    }
}

// MARK: - Previews

#Preview {
    @Previewable @State var title = ""
    @Previewable @State var logline = ""
    @Previewable @State var projectCategory = ""
    @Previewable @State var writers = ""
    @Previewable @State var projectGenre = ""
    @Previewable @State var shootStartDate = Date()
    @Previewable @State var shootEndDate = Date().addingTimeInterval(7 * 24 * 60 * 60)
    @Previewable @State var projectReleaseDate = Date()
    @Previewable @State var castNeeded: [String] = []
    @Previewable @State var crewNeeded: [String] = []
    @Previewable @State var castInfo = CastInfo()
    @Previewable @State var crewInfo = CrewInfo()
    @Previewable @State var selectedProjectImageData: Data?
    @Previewable @State var selectedProjectScriptURL: URL?
    @Previewable @State var showProjectImagePicker = false
    @Previewable @State var showProjectImageDocumentPicker = false
    @Previewable @State var showProjectScriptPicker = false
    @Previewable @State var slides: [UIImage] = []

    NavigationStack {
        ProjectSubmissionView(
            title: $title,
            logline: $logline,
            projectCategory: $projectCategory,
            writers: $writers,
            projectGenre: $projectGenre,
            shootStartDate: $shootStartDate,
            shootEndDate: $shootEndDate,
            projectReleaseDate: $projectReleaseDate,
            castNeeded: $castNeeded,
            crewNeeded: $crewNeeded,
            castInfo: $castInfo,
            crewInfo: $crewInfo,
            selectedProjectImageData: $selectedProjectImageData,
            selectedProjectScriptURL: $selectedProjectScriptURL,
            showProjectImagePicker: $showProjectImagePicker,
            showProjectImageDocumentPicker: $showProjectImageDocumentPicker,
            showProjectScriptPicker: $showProjectScriptPicker,
            slides: $slides
        )
        .navigationTitle("Project")
        .navigationBarTitleDisplayMode(.inline)
    }
}
