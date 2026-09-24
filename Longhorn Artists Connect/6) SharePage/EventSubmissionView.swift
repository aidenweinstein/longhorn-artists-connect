//
//  EventSubmissionView.swift
//  Longhorn Artists Connect
//
//  Event submission form - the Category field dictates which detail fields appear.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Event Category

/// The event categories. Each one dictates which detail fields the form shows (and,
/// at display time, which fields the card/detail page surface). Every category also
/// carries a Host and a Description.
enum EventCategoryKind: String, CaseIterable {
    case concert = "Concert"
    case actorShowcase = "Showcase"
    case theatrePerformance = "Theatre Performance"
    case filmFestival = "Film Festival"
    case artistMixer = "Artist Mixer"
    case recruitmentSchedule = "Recruitment Schedule"
    case infoSession = "Info Session"
    case speaker = "Speaker"

    /// Recruitment uses a Start/End DATE range (no times); Theatre Performance uses a
    /// list of showings (a date with start/end times each); every other category uses a
    /// single date with start/end times.
    var usesDateRange: Bool { self == .recruitmentSchedule }
    var usesDateTime: Bool { self != .recruitmentSchedule && self != .theatrePerformance }
    /// Theatre runs play more than once, so the date/time fields repeat: one group per
    /// showing instead of a single date.
    var usesShowings: Bool { self == .theatrePerformance }
    var showsLocation: Bool { self != .recruitmentSchedule }
    var showsExpectations: Bool { self == .recruitmentSchedule }
    var showsApplicationLink: Bool { self == .recruitmentSchedule }
    var showsTicketLink: Bool { self == .concert || self == .theatrePerformance }

    /// Label for the freeform "lineup" field, or `nil` when the category has none.
    var lineupLabel: String? {
        switch self {
        case .concert:            return "Artists"
        case .actorShowcase:      return "Actors"
        case .theatrePerformance: return "Cast"
        case .filmFestival:       return "Films"
        case .speaker:            return "Speakers"
        default:                  return nil
        }
    }

    /// SF Symbol used as the card's per-category accent icon, so each category reads
    /// differently at a glance.
    var accentIcon: String {
        switch self {
        case .recruitmentSchedule: return "calendar.badge.clock"
        case .infoSession:         return "info.circle.fill"
        case .concert:             return "music.mic"
        case .actorShowcase:       return "theatermasks.fill"
        case .theatrePerformance:  return "theatermask.and.paintbrush.fill"
        case .filmFestival:        return "popcorn"
        case .artistMixer:         return "person.2.fill"
        case .speaker:             return "person.wave.2.fill"
        }
    }
}

// MARK: - Showings → Post Dates

extension Submission {

    /// Brings `eventStartDate` / `eventEndDate` in line with the post's showings, so a
    /// multi-showing event starts at its first showing and ends at its last.
    ///
    /// Everything outside the Theatre Performance form still reads those two dates — the
    /// feed's sort order, the past-event filter, the card's date box — so keeping them
    /// bracketed around the run is what lets showings be additive rather than a second
    /// date system. Also sorts the showings, since they're entered in whatever order the
    /// dates were picked. No-op for a post with no showings.
    mutating func syncEventDatesToShowings() {
        guard let showings = eventShowings, !showings.isEmpty else { return }
        let sorted = showings.sorted { $0.start < $1.start }
        eventShowings = sorted
        eventStartDate = sorted.first?.start
        eventEndDate = sorted.map(\.end).max()
    }
}

struct EventSubmissionView: View {
    @Binding var title: String
    @Binding var eventDetails: String
    @Binding var eventHost: String
    @Binding var eventCategory: String
    @Binding var eventStartDate: Date
    @Binding var eventEndDate: Date
    @Binding var eventLocation: String
    @Binding var ticketsURL: String
    @Binding var eventExpectations: String
    @Binding var eventApplicationURL: String
    @Binding var eventLineup: String
    /// Theatre Performance: the run's showings. Ignored by every other category.
    @Binding var eventShowings: [EventShowing]
    @Binding var selectedEventImageData: Data?
    @Binding var showEventImagePicker: Bool
    @Binding var showEventImageDocumentPicker: Bool

    /// Live CloudKit upload state, set once the post is submitted.
    var uploadPhase: MediaUploadPhase? = nil
    var onRetryUpload: () -> Void = {}

    /// When true this form is editing an existing post: the flyer stays visible but can't
    /// be replaced, so its picker buttons are hidden. Every other field behaves exactly as
    /// it does when creating a post.
    var isEditing: Bool = false

    /// Live progress of pulling the picked flyer out of Photos/Files. Images expose
    /// no progress, so this drives an indeterminate spinner while it loads.
    @ObservedObject private var downloadCenter = MediaDownloadCenter.shared

    /// Known organizations, used to autofill the Host field so an event can be attributed
    /// to an org (e.g. "Longhorn Artists Connect"). Picking a suggestion stores the org's
    /// exact name, which lets the detail page later link the host to that org's page.
    @ObservedObject private var orgStore = OrganizationStore.shared
    @FocusState private var hostFieldFocused: Bool

    private var categoryKind: EventCategoryKind? { EventCategoryKind(rawValue: eventCategory) }

    /// Organizations to suggest under the Host field. Filtered by the current text; hidden
    /// once the field already holds an exact org name (i.e. a suggestion was chosen).
    private var hostSuggestions: [Organization] {
        let trimmed = eventHost.trimmingCharacters(in: .whitespaces)
        if orgStore.organizations.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return []
        }
        guard !trimmed.isEmpty else { return orgStore.organizations }
        return orgStore.organizations.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        List {
            // Category first, and on its own until it's chosen: the rest of the form
            // stays hidden until then.
            Section("Category") { categoryMenu }

            if let kind = categoryKind {
                Section("Upload") { uploadSection }

                Section("Details") {
                    TextField("Title", text: $title, axis: .vertical)

                    TextField("Host", text: $eventHost, axis: .vertical)
                        .focused($hostFieldFocused)

                    // Org autofill: while the Host field is focused, suggest matching
                    // organizations. Picking one fills in the org's exact name so the host
                    // can be linked to its page on the event's detail view.
                    if hostFieldFocused {
                        ForEach(hostSuggestions) { org in
                            Button {
                                eventHost = org.name
                                hostFieldFocused = false
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "building.2.crop.circle.fill")
                                        .foregroundStyle(Color.brandOrange)
                                    Text(org.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Open-ended: starts three lines tall and keeps growing with the
                    // text instead of capping out and scrolling inside the row, so a
                    // long event description stays fully visible while it's written.
                    TextField("Description", text: $eventDetails, axis: .vertical)
                        .lineLimit(3...)

                    categoryFields(for: kind)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGray6))
    }

    // MARK: - Upload

    /// Flyer upload row. Always available, independent of the chosen category.
    @ViewBuilder
    private var uploadSection: some View {
        if let uploadPhase {
            MediaUploadStatusView(phase: uploadPhase, onRetry: onRetryUpload)
        } else if downloadCenter.isLoadingImage {
            ImagePullRow()
        } else {
            HStack {
                // Show the chosen flyer (aspect ratio preserved, bounded so it
                // can't overflow the row) in place of the icon.
                UploadRowThumbnail(image: selectedEventImageData.flatMap(UIImage.init),
                                   placeholderSystemName: "richtext.page")
                Text(selectedEventImageData == nil ? "Select flyer" : "Flyer selected")
                    .foregroundStyle(.primary)
                if selectedEventImageData != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.brandOrange)
                }
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        showEventImagePicker = true
                    } label: {
                        Label("Photos", systemImage: "photo")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)

                    Button {
                        showEventImageDocumentPicker = true
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

    // MARK: - Category Selector

    private var categoryMenu: some View {
        Menu {
            ForEach(EventCategoryKind.allCases, id: \.self) { kind in
                Button {
                    eventCategory = kind.rawValue
                    // Seed the first showing so the Showings editor isn't an empty list
                    // the moment the category is picked.
                    if kind.usesShowings && eventShowings.isEmpty { addShowing() }
                } label: {
                    HStack {
                        Text(kind.rawValue)
                        if eventCategory == kind.rawValue {
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
                Text(eventCategory.isEmpty ? "Select Category" : eventCategory)
                    .foregroundStyle(Color.brandOrange)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category-specific fields

    @ViewBuilder
    private func categoryFields(for kind: EventCategoryKind) -> some View {
        if kind.usesDateRange {
            DatePicker("Start Date", selection: $eventStartDate, displayedComponents: .date)
            DatePicker("End Date", selection: $eventEndDate, in: eventStartDate..., displayedComponents: .date)
        }

        if kind.usesDateTime {
            DatePicker("Date", selection: eventDayBinding, displayedComponents: .date)
            DatePicker("Start Time", selection: $eventStartDate, displayedComponents: .hourAndMinute)
            DatePicker("End Time", selection: $eventEndDate, displayedComponents: .hourAndMinute)
        }

        if kind.usesShowings {
            showingsFields
        }

        if kind.showsLocation {
            TextField("Location", text: $eventLocation, axis: .vertical)
        }

        if let lineupLabel = kind.lineupLabel {
            TextField(lineupLabel, text: $eventLineup, axis: .vertical)
                .lineLimit(1...4)
        
        }

        if kind.showsApplicationLink {
            TextField("Application Link", text: $eventApplicationURL, axis: .vertical)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        }

        if kind.showsTicketLink {
            TextField("Ticket Link", text: $ticketsURL, axis: .vertical)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        }
    }

    // MARK: - Showings (Theatre Performance)

    /// The Showings editor: one "Showing N" header plus a Date / Start Time / End Time
    /// group per performance, so a run that plays several nights is one post with a list
    /// of dates rather than one post per night. Rows can be removed down to the last one
    /// (a performance with no date isn't worth posting), and "Add Showing" appends
    /// another.
    @ViewBuilder
    private var showingsFields: some View {
        ForEach($eventShowings) { $showing in
            HStack {
                Text("Showing \(showingNumber(of: showing))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if eventShowings.count > 1 {
                    Button {
                        eventShowings.removeAll { $0.id == showing.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            // The Date picker moves both of this showing's timestamps onto the chosen
            // day (see `EventShowing.day`), so date and times can't fall out of step.
            DatePicker("Date", selection: $showing.day, displayedComponents: .date)
            DatePicker("Start Time", selection: $showing.start, displayedComponents: .hourAndMinute)
            DatePicker("End Time", selection: $showing.end, displayedComponents: .hourAndMinute)
        }

        Button {
            addShowing()
        } label: {
            Label("Add Showing", systemImage: "plus.circle.fill")
                .foregroundStyle(Color.brandOrange)
        }
        .buttonStyle(.plain)
    }

    /// The showing's 1-based position in the run, for its header. Looked up by id rather
    /// than captured as an index so removing a row can't leave a stale number behind.
    private func showingNumber(of showing: EventShowing) -> Int {
        (eventShowings.firstIndex { $0.id == showing.id } ?? 0) + 1
    }

    /// Appends a showing. The first one takes the form's current date and times; each one
    /// after that is the previous showing a day later at the same times — the usual shape
    /// of a theatre run, so adding a night is a single tap.
    private func addShowing() {
        guard let last = eventShowings.last else {
            eventShowings.append(EventShowing(start: eventStartDate, end: eventEndDate))
            return
        }
        let calendar = Calendar.current
        let nextStart = calendar.date(byAdding: .day, value: 1, to: last.start) ?? last.start
        let nextEnd = calendar.date(byAdding: .day, value: 1, to: last.end) ?? last.end
        eventShowings.append(EventShowing(start: nextStart, end: nextEnd))
    }

    /// The shared calendar day for time-based categories. Editing it moves both the
    /// start and end timestamps onto that day while preserving each one's time — so the
    /// single "Date" picker and the two time pickers stay in sync on one date.
    private var eventDayBinding: Binding<Date> {
        Binding(
            get: { eventStartDate },
            set: { newDay in
                let calendar = Calendar.current
                let dayComponents = calendar.dateComponents([.year, .month, .day], from: newDay)
                func applyDay(to date: Date) -> Date {
                    let time = calendar.dateComponents([.hour, .minute], from: date)
                    var combined = dayComponents
                    combined.hour = time.hour
                    combined.minute = time.minute
                    return calendar.date(from: combined) ?? date
                }
                eventStartDate = applyDay(to: eventStartDate)
                eventEndDate = applyDay(to: eventEndDate)
            }
        )
    }
}

// MARK: - Event Edit View

/// Edit screen for an existing event submission. Reuses `EventSubmissionView` so the form
/// is identical to creating an event; only the already-submitted flyer is shown read-only
/// and can't be replaced.
struct EventEditView: View {
    let submission: Submission
    let onSave: (Submission) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edited: Submission
    @State private var selectedEventImageData: Data?
    // The flyer pickers are presented by the parent in the create flow, so the edit
    // screen hosts them itself.
    @State private var showEventImagePicker = false
    @State private var showEventImageDocumentPicker = false
    @State private var eventImageItem: PhotosPickerItem?

    init(submission: Submission, onSave: @escaping (Submission) -> Void) {
        self.submission = submission
        self.onSave = onSave
        _edited = State(initialValue: submission)
        _selectedEventImageData = State(initialValue: submission.thumbnailData)
    }

    private var categoryBinding: Binding<String> {
        Binding(
            get: { edited.genres.first ?? "" },
            set: { edited.genres = $0.isEmpty ? [] : [$0] }
        )
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { edited.eventStartDate ?? Date() },
            set: { edited.eventStartDate = $0 }
        )
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { edited.eventEndDate ?? edited.eventStartDate ?? Date() },
            set: { edited.eventEndDate = $0 }
        )
    }

    private var locationBinding: Binding<String> {
        Binding(
            get: { edited.eventLocation ?? "" },
            set: { edited.eventLocation = $0 }
        )
    }

    private var ticketsBinding: Binding<String> {
        Binding(
            get: { edited.eventTicketsURL ?? "" },
            set: { edited.eventTicketsURL = $0.isEmpty ? nil : $0 }
        )
    }

    private var expectationsBinding: Binding<String> {
        Binding(
            get: { edited.eventExpectations ?? "" },
            set: { edited.eventExpectations = $0.isEmpty ? nil : $0 }
        )
    }

    private var applicationBinding: Binding<String> {
        Binding(
            get: { edited.eventApplicationURL ?? "" },
            set: { edited.eventApplicationURL = $0.isEmpty ? nil : $0 }
        )
    }

    private var lineupBinding: Binding<String> {
        Binding(
            get: { edited.eventLineup ?? "" },
            set: { edited.eventLineup = $0.isEmpty ? nil : $0 }
        )
    }

    private var showingsBinding: Binding<[EventShowing]> {
        Binding(
            get: { edited.eventShowings ?? [] },
            set: { edited.eventShowings = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        NavigationStack {
            EventSubmissionView(
                title: $edited.title,
                eventDetails: $edited.logline,
                eventHost: $edited.eventHost,
                eventCategory: categoryBinding,
                eventStartDate: startDateBinding,
                eventEndDate: endDateBinding,
                eventLocation: locationBinding,
                ticketsURL: ticketsBinding,
                eventExpectations: expectationsBinding,
                eventApplicationURL: applicationBinding,
                eventLineup: lineupBinding,
                eventShowings: showingsBinding,
                selectedEventImageData: $selectedEventImageData,
                showEventImagePicker: $showEventImagePicker,
                showEventImageDocumentPicker: $showEventImageDocumentPicker,
                isEditing: true
            )
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .photosPicker(isPresented: $showEventImagePicker, selection: $eventImageItem, matching: .images)
            .onChange(of: eventImageItem) { _, newItem in
                guard let newItem else { return }
                MediaDownloadCenter.shared.beginImageLoad()
                Task {
                    let data = try? await newItem.loadTransferable(type: Data.self)
                    await MainActor.run {
                        if let data { selectedEventImageData = data }
                        eventImageItem = nil
                        MediaDownloadCenter.shared.finishImageLoad()
                    }
                }
            }
            .sheet(isPresented: $showEventImageDocumentPicker) {
                DocumentPicker(contentTypes: [.image, .jpeg, .png]) { url in
                    if let data = try? Data(contentsOf: url) { selectedEventImageData = data }
                    showEventImageDocumentPicker = false
                } onCancel: {
                    showEventImageDocumentPicker = false
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
        edited.thumbnailData = selectedEventImageData
        // A theatre run's post dates come from its showings (first start, last end).
        edited.syncEventDatesToShowings()
        onSave(edited)
        dismiss()
    }
}

// MARK: - Previews

#Preview("Empty Form") {
    @Previewable @State var title = ""
    @Previewable @State var eventDetails = ""
    @Previewable @State var eventHost = ""
    @Previewable @State var eventCategory = ""
    @Previewable @State var eventStartDate = Date()
    @Previewable @State var eventEndDate = Date().addingTimeInterval(3 * 60 * 60)
    @Previewable @State var eventLocation = ""
    @Previewable @State var ticketsURL = ""
    @Previewable @State var eventExpectations = ""
    @Previewable @State var eventApplicationURL = ""
    @Previewable @State var eventLineup = ""
    @Previewable @State var eventShowings: [EventShowing] = []
    @Previewable @State var selectedEventImageData: Data? = nil
    @Previewable @State var showEventImagePicker = false
    @Previewable @State var showEventImageDocumentPicker = false

    NavigationStack {
        EventSubmissionView(
            title: $title,
            eventDetails: $eventDetails,
            eventHost: $eventHost,
            eventCategory: $eventCategory,
            eventStartDate: $eventStartDate,
            eventEndDate: $eventEndDate,
            eventLocation: $eventLocation,
            ticketsURL: $ticketsURL,
            eventExpectations: $eventExpectations,
            eventApplicationURL: $eventApplicationURL,
            eventLineup: $eventLineup,
            eventShowings: $eventShowings,
            selectedEventImageData: $selectedEventImageData,
            showEventImagePicker: $showEventImagePicker,
            showEventImageDocumentPicker: $showEventImageDocumentPicker
        )
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
    }
}
