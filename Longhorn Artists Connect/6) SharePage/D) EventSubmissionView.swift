//
//  EventSubmissionView.swift
//  Longhorn Artists Connect
//
//  Event submission form - for community events with dates, location, and tickets
//

import SwiftUI

struct EventSubmissionView: View {
    @Binding var title: String
    @Binding var eventDetails: String
    @Binding var eventHost: String
    @Binding var eventCategory: String
    @Binding var eventStartDate: Date
    @Binding var eventEndDate: Date
    @Binding var eventLocation: String
    @Binding var ticketsURL: String
    @Binding var selectedEventImageData: Data?
    @Binding var showEventImagePicker: Bool
    @Binding var showEventImageDocumentPicker: Bool

    /// Live CloudKit upload state, set once the post is submitted.
    var uploadPhase: MediaUploadPhase? = nil
    var onRetryUpload: () -> Void = {}

    var body: some View {
        List {
            Section("Upload") {
                if let uploadPhase {
                    MediaUploadStatusView(phase: uploadPhase, onRetry: onRetryUpload)
                } else {
                HStack {
                    Image(systemName: "richtext.page")
                        .foregroundStyle(.secondary)
                    Text("Select flyer")
                        .foregroundStyle(.primary)
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

                if let imageData = selectedEventImageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                }
                }
            }

            Section("Details") {
                TextField("Title", text: $title, axis: .vertical)
                TextField("Host", text: $eventHost, axis: .vertical)
                TextField("Description", text: $eventDetails, axis: .vertical)
                    .lineLimit(3...6)

                Menu {
                    ForEach(["Party", "Concert", "Info Session", "Film Festival", "Screening"], id: \.self) { category in
                        Button {
                            eventCategory = category
                        } label: {
                            HStack {
                                Text(category)
                                if eventCategory == category {
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

                DatePicker("Start Time", selection: $eventStartDate)
                DatePicker("End Time", selection: $eventEndDate, in: eventStartDate...)

                TextField("Location", text: $eventLocation, axis: .vertical)
                TextField("Tickets URL", text: $ticketsURL, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGray6))
    }
}

// MARK: - Event Edit View

/// Metadata-only edit screen for an existing event submission. The flyer cannot be
/// replaced here — co-located with the event creation form for consistency.
struct EventEditView: View {
    let submission: Submission
    let onSave: (Submission) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edited: Submission

    init(submission: Submission, onSave: @escaping (Submission) -> Void) {
        self.submission = submission
        self.onSave = onSave
        _edited = State(initialValue: submission)
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $edited.title)
                    TextField("Description", text: $edited.logline, axis: .vertical)
                        .lineLimit(3...6)

                    Picker("Category", selection: categoryBinding) {
                        Text("Select Category").tag("")
                        Text("Party").tag("Party")
                        Text("Concert").tag("Concert")
                        Text("Info Session").tag("Info Session")
                        Text("Film Festival").tag("Film Festival")
                        Text("Screening").tag("Screening")
                    }

                    TextField("Tickets URL", text: ticketsBinding)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }

                Section("Date & Time") {
                    DatePicker("Start", selection: startDateBinding)
                    DatePicker("End", selection: endDateBinding, in: startDateBinding.wrappedValue...)
                }

                Section("Location") {
                    TextField("Location", text: locationBinding)
                    TextField("Host", text: $edited.eventHost)
                }

                Section {
                    Text("The flyer can't be changed when editing. To replace it, delete this post and create a new one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Event")
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
    }

    private func save() {
        guard !edited.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
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
            selectedEventImageData: $selectedEventImageData,
            showEventImagePicker: $showEventImagePicker,
            showEventImageDocumentPicker: $showEventImageDocumentPicker
        )
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
    }
}
