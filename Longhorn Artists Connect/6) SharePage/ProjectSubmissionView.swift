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
/// - `inPostProduction`: same fields as `inDevelopment`, for a project that's been shot.
enum ProjectType: String, CaseIterable {
    case castCrewCall = "Cast & Crew Call"
    case script = "Script"
    case inDevelopment = "In-Development"
    case inPostProduction = "In-Post-Production"
}

// A project's "Class or Org" field offers the same studios and production classes the
// film form does, and stores the pick in `Submission.studio` exactly as films do.

/// Stored in `shootDates` / `expectedReleaseDate` when the poster hasn't settled on a
/// date yet. The schedule and release-date parsers don't recognise it, so it falls
/// through every display path as the literal text "TBD".
let projectDateTBDText = "TBD"

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
    /// The organization or production class behind the project, stored in
    /// `Submission.studio` exactly as films do. Empty for an independent project.
    @Binding var studio: String
    /// The shoot schedule: specific days, each with its own call and wrap time.
    @Binding var shootDays: [ShootDay]
    /// True when the shoot dates aren't set yet; the day editor is hidden and the post
    /// stores "TBD" (see `projectDateTBDText`).
    @Binding var shootDatesTBD: Bool
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
    /// Where to sign up for an audition (Cast & Crew Call).
    @Binding var auditionURL: String
    /// Who to reach out to, one free-form line each (every project type).
    @Binding var contacts: [String]

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
    @State private var showContactsForm: Bool = false

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
    /// The open poster crop editor, if any.
    @State private var cropRequest: MediaCropRequest?

    /// Studios offered for an Org Project — the same list the film form shows.
    private let availableStudios = ["Collective", "Incubator", "Beyond Frame Productions", "DKA", "Black Lens"]

    var body: some View {
        List {
            Section("Upload") {
                if let uploadPhase {
                    MediaUploadStatusView(phase: uploadPhase, onRetry: onRetryUpload)
                } else {
                    posterRow(label: "poster")
                    scriptRow
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
                detailsSection
                teamNeededSection
                assembledTeamSection
                contactsSection
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
        .navigationDestination(isPresented: $showContactsForm) {
            ProjectContactsFormView(contacts: $contacts)
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
        .mediaCropper($cropRequest)
    }

    // MARK: - Per-Type Sections

    /// Title, logline, class/org, and the shoot schedule.
    private var detailsSection: some View {
        Section("Details") {
            TextField("Title", text: $title, axis: .vertical)
            TextField("Logline/Description", text: $logline, axis: .vertical)
                .lineLimit(3...6)
            studioOrClassMenu
            // The day editor gives way to a TBD switch when the shoot isn't scheduled.
            Toggle("Shoot Dates TBD", isOn: $shootDatesTBD)
                .tint(Color.brandOrange)
            if !shootDatesTBD {
                shootDayFields
            }
        }
    }

    // MARK: - Shoot Days

    /// The shoot schedule editor: one row per shoot day, each a "Shoot Day N" header over
    /// a single Date / Start "to" End line, in the same shape as the event form's
    /// Showings. Any row can be removed (a call with no dates set yet is still worth
    /// posting), and "Add Shoot Day" appends another.
    @ViewBuilder
    private var shootDayFields: some View {
        ForEach($shootDays) { $day in
            // Header and pickers share one row so no separator falls between them.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Shoot Day \(dayNumber(of: day))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        shootDays.removeAll { $0.id == day.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }

                // Date, then start "to" end. The Date picker moves both of this day's
                // timestamps onto the chosen day (see `ShootDay.day`), so date and times
                // can't fall out of step.
                HStack(spacing: 6) {
                    DatePicker("Date", selection: $day.day, displayedComponents: .date)
                        .labelsHidden()
                    Spacer(minLength: 0)
                    DatePicker("Start Time", selection: $day.date, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("to")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                    DatePicker("End Time", selection: $day.end, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
        }

        Button {
            addShootDay()
        } label: {
            Label("Add Shoot Day", systemImage: "plus.circle.fill")
                .foregroundStyle(Color.brandOrange)
        }
        .buttonStyle(.plain)
    }

    /// The day's 1-based position in the schedule, for its header. Looked up by id rather
    /// than captured as an index so removing a row can't leave a stale number behind.
    private func dayNumber(of day: ShootDay) -> Int {
        (shootDays.firstIndex { $0.id == day.id } ?? 0) + 1
    }

    /// Appends a shoot day. The first defaults to today, 8:00 AM to 4:00 PM; each one
    /// after that is the previous day plus one, at the same start and end times — the
    /// usual shape of a shoot, so adding a day is a single tap.
    private func addShootDay() {
        let calendar = Calendar.current
        guard let last = shootDays.last else {
            let firstCall = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
            shootDays.append(ShootDay(date: firstCall))
            return
        }
        let next = calendar.date(byAdding: .day, value: 1, to: last.date) ?? last.date
        let nextEnd = calendar.date(byAdding: .day, value: 1, to: last.end) ?? last.end
        shootDays.append(ShootDay(date: next, end: nextEnd))
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
                    UploadPickerButtons(
                        hasSelection: selectedProjectImageData != nil,
                        onPhotos: { showProjectImagePicker = true },
                        onFiles: { showProjectImageDocumentPicker = true },
                        onCrop: selectedProjectImageData.flatMap(UIImage.init).map { image in
                            {
                                cropRequest = .image(image) { cropped in
                                    if let data = cropped.jpegData(compressionQuality: 0.9) {
                                        selectedProjectImageData = data
                                    }
                                }
                            }
                        },
                        onRemove: { selectedProjectImageData = nil }
                    )
                }
            }
        }
    }

    /// "Select slides" row: label, count, and the Photos + Files pickers — the same
    /// two-button layout as the poster row above, but multi-select.
    private var slidePickerRow: some View {
        HStack {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundStyle(.secondary)
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
            Text(selectedProjectScriptURL == nil ? "Select script" : "Script attached")
                .foregroundStyle(.primary)
            if selectedProjectScriptURL != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
            Spacer()
            UploadPickerButtons(
                hasSelection: selectedProjectScriptURL != nil,
                onFiles: { showProjectScriptPicker = true },
                onRemove: { selectedProjectScriptURL = nil }
            )
        }
    }

    /// The "Class or Org" menu: the organizations and production classes the film form
    /// offers, in two sections, plus "None" for an independent project. The pick becomes
    /// the card's badge and the "Class" / "Org" Details row.
    private var studioOrClassMenu: some View {
        Menu {
            Section("Organizations") {
                ForEach(availableStudios, id: \.self) { option in studioOption(option) }
            }
            Section("Classes") {
                ForEach(ProductionClassCatalog.names, id: \.self) { option in studioOption(option) }
            }
            Button("None") { studio = "" }
        } label: {
            HStack {
                Text("Class/Org").foregroundStyle(.primary)
                Spacer()
                Text(studio.isEmpty ? "None" : studio)
                    .lineLimit(1)
                    .foregroundStyle(Color.brandOrange)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
        }
        .buttonStyle(.plain)
    }

    /// One row of the Class or Org menu, checked when it's the current pick.
    private func studioOption(_ option: String) -> some View {
        Button {
            studio = option
        } label: {
            HStack {
                Text(option)
                if studio == option { Image(systemName: "checkmark") }
            }
        }
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

            // Audition sign-up link (Cast & Crew Call) — lives with the roles it's for.
            TextField("Audition Link", text: $auditionURL, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        }
    }

    /// Who to reach out to — pushed to its own page like Cast/Crew Needed.
    private var contactsSection: some View {
        Section("Contact") {
            Button {
                showContactsForm = true
            } label: {
                HStack {
                    Text("Contacts").foregroundStyle(.primary)
                    Spacer()
                    Text(contacts.isEmpty ? "Add" : "\(contacts.count) contact\(contacts.count == 1 ? "" : "s")")
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
    @State private var shootDays: [ShootDay]
    @State private var shootDatesTBD: Bool
    @State private var selectedProjectImageData: Data?
    @State private var selectedProjectScriptURL: URL?
    @State private var slides: [UIImage]
    @State private var auditionURL: String
    @State private var contacts: [String]

    init(submission: Submission, onSave: @escaping (Submission) -> Void) {
        self.submission = submission
        self.onSave = onSave
        _edited = State(initialValue: submission)
        _castInfo = State(initialValue: CastInfo(orderedEntries: submission.orderedCast))
        _crewInfo = State(initialValue: CrewInfo(orderedEntries: submission.orderedCrew))

        // Rebuild the shoot-day rows from the stored schedule. A post from before the
        // day list existed carries a "start - end" range; that becomes two rows (or one
        // when start and end were the same day) so it can be edited into real days.
        let shootDays: [ShootDay]
        switch submission.shootSchedule {
        case .days(let days)?:
            // A day stored before wrap times existed gets the default end.
            shootDays = days.map { ShootDay(date: $0.start, end: $0.end) }
        case .range(let start, let end)?:
            let dates = (end.map { Calendar.current.isDate($0, inSameDayAs: start) } ?? true) ? [start] : [start, end ?? start]
            shootDays = dates.map { ShootDay(date: $0) }
        case nil:
            shootDays = []
        }
        _shootDays = State(initialValue: shootDays)
        _shootDatesTBD = State(initialValue: submission.shootDates == projectDateTBDText)

        _selectedProjectImageData = State(initialValue: submission.thumbnailData)
        _selectedProjectScriptURL = State(initialValue: submission.scriptURL)
        // Restore the slideshow from its persisted media-cache copies.
        _slides = State(initialValue: submission.projectSlideURLs.compactMap { UIImage(contentsOfFile: $0.path) })
        _auditionURL = State(initialValue: submission.projectAuditionURL ?? "")
        _contacts = State(initialValue: submission.projectContacts ?? [])
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
                studio: $edited.studio,
                shootDays: $shootDays,
                shootDatesTBD: $shootDatesTBD,
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
                auditionURL: $auditionURL,
                contacts: $contacts,
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
        edited.shootDates = shootDatesTBD ? projectDateTBDText : ShootSchedule.text(from: shootDays)
        // The form no longer edits the expected release, so an older post keeps its value.
        // Drop empty role/position rows before saving.
        edited.castNeeded.removeAll { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        edited.crewNeeded.removeAll { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        let trimmedAudition = auditionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.projectAuditionURL = trimmedAudition.isEmpty ? nil : trimmedAudition
        let filledContacts = contacts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        edited.projectContacts = filledContacts.isEmpty ? nil : filledContacts
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
    @Previewable @State var shootDays: [ShootDay] = []
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
    @Previewable @State var auditionURL = ""
    @Previewable @State var contacts: [String] = []
    @Previewable @State var studio = ""
    @Previewable @State var shootDatesTBD = false

    NavigationStack {
        ProjectSubmissionView(
            title: $title,
            logline: $logline,
            studio: $studio,
            shootDays: $shootDays,
            shootDatesTBD: $shootDatesTBD,
            castNeeded: $castNeeded,
            crewNeeded: $crewNeeded,
            castInfo: $castInfo,
            crewInfo: $crewInfo,
            selectedProjectImageData: $selectedProjectImageData,
            selectedProjectScriptURL: $selectedProjectScriptURL,
            showProjectImagePicker: $showProjectImagePicker,
            showProjectImageDocumentPicker: $showProjectImageDocumentPicker,
            showProjectScriptPicker: $showProjectScriptPicker,
            slides: $slides,
            auditionURL: $auditionURL,
            contacts: $contacts
        )
        .navigationTitle("Project")
        .navigationBarTitleDisplayMode(.inline)
    }
}
