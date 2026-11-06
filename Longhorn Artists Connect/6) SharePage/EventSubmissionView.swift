//
//  EventSubmissionView.swift
//  Longhorn Artists Connect
//
//  Event submission form - flyer, host, description, one or more showings, location,
//  lineup and links.
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
    case screening = "Screening"
    case artistMixer = "Artist Mixer"
    case infoSession = "Info Session"
    case speaker = "Speaker"

    /// Theatre Performance uses a list of showings (a date with start/end times each);
    /// every other category uses a single date with start/end times.
    var usesDateTime: Bool { self != .theatrePerformance }
    /// Theatre runs play more than once, so the date/time fields repeat: one group per
    /// showing instead of a single date.
    var usesShowings: Bool { self == .theatrePerformance }

    /// Label for the freeform "lineup" field, or `nil` when the category has none.
    var lineupLabel: String? {
        switch self {
        case .concert:            return "Artists"
        case .actorShowcase:      return "Actors"
        case .theatrePerformance: return "Cast"
        case .filmFestival:       return "Films"
        case .screening:          return "Films"
        case .speaker:            return "Speakers"
        default:                  return nil
        }
    }

    /// SF Symbol used as the card's per-category accent icon, so each category reads
    /// differently at a glance.
    var accentIcon: String {
        switch self {
        case .infoSession:         return "info.circle.fill"
        case .concert:             return "music.mic"
        case .actorShowcase:       return "theatermasks.fill"
        case .theatrePerformance:  return "theatermask.and.paintbrush.fill"
        case .filmFestival:        return "popcorn"
        case .screening:           return "film"
        case .artistMixer:         return "party.popper.fill"
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
    @Binding var eventStartDate: Date
    @Binding var eventEndDate: Date
    @Binding var eventLocation: String
    @Binding var ticketsURL: String
    @Binding var eventExpectations: String
    @Binding var eventApplicationURL: String
    @Binding var eventRSVPURL: String
    @Binding var eventWebsiteURL: String
    @Binding var eventLineup: String
    /// The event's showings: every event has at least one, and can run over several days.
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
    /// The open flyer crop editor, if any.
    @State private var cropRequest: MediaCropRequest?

    /// Up to 4 organizations whose name contains the typed text, matching how profile-name
    /// credits suggest people. Nothing shows until 2+ characters are typed, and the list
    /// hides once the field already holds an exact org name (i.e. a suggestion was chosen).
    private var hostSuggestions: [Organization] {
        let query = eventHost.trimmingCharacters(in: .whitespaces).lowercased()
        guard query.count >= 2 else { return [] }
        if orgStore.organizations.contains(where: { $0.name.lowercased() == query }) { return [] }
        return Array(
            orgStore.organizations
                .filter { $0.name.lowercased().contains(query) }
                .sorted { $0.name.lowercased() < $1.name.lowercased() }
                .prefix(4)
        )
    }

    /// Whether the typed host exactly matches a known organization, meaning the event
    /// will link to that org's page.
    private var hostIsConfirmed: Bool {
        let query = eventHost.trimmingCharacters(in: .whitespaces).lowercased()
        return !query.isEmpty && orgStore.organizations.contains { $0.name.lowercased() == query }
    }

    /// Host text field plus an organization autocomplete card, styled to match
    /// `CreditNameField`. Each suggestion shows the org's logo and name; picking one
    /// fills in the org's exact name so the host can be linked to its page on the
    /// event's detail view.
    private var hostField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Host", text: $eventHost, axis: .vertical)
                    .focused($hostFieldFocused)
                if hostIsConfirmed {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.brandOrange)
                        .font(.caption)
                }
            }

            if hostFieldFocused && !hostSuggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(hostSuggestions) { org in
                        Button {
                            eventHost = org.name
                            hostFieldFocused = false
                        } label: {
                            HStack(spacing: 8) {
                                OrgAvatar(imageData: org.profileImageData, diameter: 28,
                                          tint: .secondary, assetName: org.profileAssetName)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(org.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    if !org.displayDescription.isEmpty {
                                        Text(org.displayDescription)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if org.id != hostSuggestions.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemBackground))
                )
            }
        }
    }

    var body: some View {
        List {
            Section("Upload") { uploadSection }

            Section("Details") {
                TextField("Title", text: $title, axis: .vertical)

                hostField

                // Open-ended: starts three lines tall and keeps growing with the
                // text instead of capping out and scrolling inside the row, so a
                // long event description stays fully visible while it's written.
                TextField("Description", text: $eventDetails, axis: .vertical)
                    .lineLimit(3...)

                showingsFields

                TextField("Location", text: $eventLocation, axis: .vertical)

                TextField("Artists", text: $eventLineup, axis: .vertical)
                    .lineLimit(1...4)
            }

            // Optional links. Each one that's filled in becomes its own button on the
            // event's detail page.
            Section("Other") {
                linkField("Ticket Link", text: $ticketsURL)
                linkField("RSVP Link", text: $eventRSVPURL)
                linkField("Website Link", text: $eventWebsiteURL)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGray6))
        .mediaCropper($cropRequest)
        // Every event has at least one showing; seed the first from the form's dates so
        // the editor never opens on an empty list (older posts have only those dates).
        .onAppear { if eventShowings.isEmpty { addShowing() } }
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
                UploadPickerButtons(
                    hasSelection: selectedEventImageData != nil,
                    onPhotos: { showEventImagePicker = true },
                    onFiles: { showEventImageDocumentPicker = true },
                    onCrop: selectedEventImageData.flatMap(UIImage.init).map { image in
                        {
                            cropRequest = .image(image) { cropped in
                                if let data = cropped.jpegData(compressionQuality: 0.9) {
                                    selectedEventImageData = data
                                }
                            }
                        }
                    },
                    onRemove: { selectedEventImageData = nil }
                )
            }
        }
    }

    /// A URL entry row. `axis: .vertical` keeps iOS 26's single-line field box away.
    private func linkField(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text, axis: .vertical)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
    }

    // MARK: - Showings

    /// The Showings editor: one row per showing, each a "Showing N" header over a single
    /// Date / Start "to" End line, so an event that runs several days is one post with a
    /// list of dates rather than one post per day. Rows can be removed down to the last
    /// one (an event with no date isn't worth posting), and "Add Showing" appends another.
    @ViewBuilder
    private var showingsFields: some View {
        ForEach($eventShowings) { $showing in
            // Header and pickers share one row so no separator falls between them.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Day \(showingNumber(of: showing))")
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

                // Date, then start "to" end. The Date picker moves both of this
                // showing's timestamps onto the chosen day (see `EventShowing.day`), so
                // date and times can't fall out of step.
                HStack(spacing: 6) {
                    DatePicker("Date", selection: $showing.day, displayedComponents: .date)
                        .labelsHidden()
                    Spacer(minLength: 0)
                    DatePicker("Start Time", selection: $showing.start, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("to")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                    DatePicker("End Time", selection: $showing.end, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
        }

        Button {
            addShowing()
        } label: {
            Label("Add Day", systemImage: "plus.circle.fill")
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

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { edited.eventStartDate ?? Date().roundedToNearestHour() },
            set: { edited.eventStartDate = $0 }
        )
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { edited.eventEndDate ?? edited.eventStartDate ?? Date().roundedToNearestHour() },
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

    private var rsvpBinding: Binding<String> {
        Binding(
            get: { edited.eventRSVPURL ?? "" },
            set: { edited.eventRSVPURL = $0.isEmpty ? nil : $0 }
        )
    }

    private var websiteBinding: Binding<String> {
        Binding(
            get: { edited.eventWebsiteURL ?? "" },
            set: { edited.eventWebsiteURL = $0.isEmpty ? nil : $0 }
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
                eventStartDate: startDateBinding,
                eventEndDate: endDateBinding,
                eventLocation: locationBinding,
                ticketsURL: ticketsBinding,
                eventExpectations: expectationsBinding,
                eventApplicationURL: applicationBinding,
                eventRSVPURL: rsvpBinding,
                eventWebsiteURL: websiteBinding,
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
    @Previewable @State var eventStartDate = Date()
    @Previewable @State var eventEndDate = Date().addingTimeInterval(3 * 60 * 60)
    @Previewable @State var eventLocation = ""
    @Previewable @State var ticketsURL = ""
    @Previewable @State var eventExpectations = ""
    @Previewable @State var eventApplicationURL = ""
    @Previewable @State var eventRSVPURL = ""
    @Previewable @State var eventWebsiteURL = ""
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
            eventStartDate: $eventStartDate,
            eventEndDate: $eventEndDate,
            eventLocation: $eventLocation,
            ticketsURL: $ticketsURL,
            eventExpectations: $eventExpectations,
            eventApplicationURL: $eventApplicationURL,
            eventRSVPURL: $eventRSVPURL,
            eventWebsiteURL: $eventWebsiteURL,
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
