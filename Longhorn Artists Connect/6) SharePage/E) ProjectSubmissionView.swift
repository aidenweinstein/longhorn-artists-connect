//
//  ProjectSubmissionView.swift
//  Longhorn Artists Connect
//
//  Project submission form - for casting calls and crew hiring
//

import SwiftUI
import UniformTypeIdentifiers

struct ProjectSubmissionView: View {
    @Binding var title: String
    @Binding var logline: String
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

    /// Live CloudKit upload state, set once the post is submitted.
    var uploadPhase: MediaUploadPhase? = nil
    var onRetryUpload: () -> Void = {}

    @State private var showCastNeededForm: Bool = false
    @State private var showCrewNeededForm: Bool = false
    @State private var showCastAssembledForm: Bool = false
    @State private var showCrewAssembledForm: Bool = false

    var body: some View {
        List {
            Section("Upload") {
                if let uploadPhase {
                    MediaUploadStatusView(phase: uploadPhase, onRetry: onRetryUpload)
                } else {
                HStack {
                    // Show a tiny preview of the chosen poster in place of the icon,
                    // so the user can confirm they picked the right one.
                    if let data = selectedProjectImageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: "richtext.page")
                            .foregroundStyle(.secondary)
                    }
                    Text("Select poster")
                        .foregroundStyle(.primary)
                    // Green check once a poster is loaded.
                    if selectedProjectImageData != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    HStack(spacing:12) {
                        Button {
                            showProjectImagePicker = true
                        }label: {Label("Photos", systemImage: "photo.stack")
                            .labelStyle(.iconOnly)}
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                    
                    Button {
                        showProjectImageDocumentPicker = true
                    } label: {
                        Label("Files", systemImage: "folder")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                    
                    }

                HStack {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text("Select script")
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        showProjectScriptPicker = true
                    } label: {
                        Label("Files", systemImage: "folder")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }
                }
                }

            Section("Details") {
                TextField("Title", text: $title, axis: .vertical)
                TextField("Logline", text: $logline, axis: .vertical)
                    .lineLimit(3...6)

                DatePicker("Shoot Start", selection: $shootStartDate, displayedComponents: .date)

                DatePicker("Shoot End", selection: $shootEndDate, displayedComponents: .date)

                DatePicker("Expected Release", selection: $projectReleaseDate, displayedComponents: .date)

            }

            Section("Team Needed") {
                Button {
                    showCastNeededForm = true
                } label: {
                    HStack {
                        Text("Cast Needed")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(castNeeded.isEmpty ? "Add" : "\(castNeeded.count) role\(castNeeded.count == 1 ? "" : "s")")
                            .foregroundStyle(Color.brandOrange)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.brandOrange)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    showCrewNeededForm = true
                } label: {
                    HStack {
                        Text("Crew Needed")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(crewNeeded.isEmpty ? "Add" : "\(crewNeeded.count) role\(crewNeeded.count == 1 ? "" : "s")")
                            .foregroundStyle(Color.brandOrange)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.brandOrange)
                    }
                }
                .buttonStyle(.plain)
            }

            Section("Assembled Team") {
                Button {
                    showCastAssembledForm = true
                } label: {
                    HStack {
                        Text("Cast Assembled")
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
                    showCrewAssembledForm = true
                } label: {
                    HStack {
                        Text("Crew Assembled")
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

// MARK: - ProjectRolesFormView

struct ProjectRolesFormView: View {
    @Binding var roles: [ProjectRole]
    let roleType: String
    let roleFieldPlaceholder: String

    @Environment(\.dismiss) private var dismiss
    @State private var newRoleName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($roles) { $role in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Role", text: $role.roleName)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            HStack {
                                TextField("Assigned to (leave empty if available)", text: $role.assignedName)
                                    .font(.subheadline)

                                if !role.assignedName.isEmpty {
                                    Button {
                                        role.assignedName = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if role.assignedName.isEmpty {
                                HStack {
                                    Image(systemName: "circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text("Available")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        roles.remove(atOffsets: indexSet)
                    }

                    HStack {
                        TextField(roleFieldPlaceholder, text: $newRoleName)
                            .submitLabel(.done)
                            .onSubmit {
                                addRole()
                            }

                        Button {
                            addRole()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.brandOrange)
                        }
                        .disabled(newRoleName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("\(roleType) Roles")
                } footer: {
                    Text("Add roles and assign names as they're filled. Leave the name empty to mark a role as available.")
                        .font(.caption)
                }
            }
            .navigationTitle(roleType)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func addRole() {
        let trimmed = newRoleName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        roles.append(ProjectRole(roleName: trimmed))
        newRoleName = ""
    }
}

// MARK: - Project Edit View

/// Metadata-only edit screen for an existing project submission. The poster and script
/// cannot be replaced here — co-located with the project creation form for consistency.
struct ProjectEditView: View {
    let submission: Submission
    let onSave: (Submission) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edited: Submission
    @State private var castInfo: CastInfo
    @State private var crewInfo: CrewInfo
    @State private var showCastAssembledForm = false
    @State private var showCrewAssembledForm = false

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
                    TextField("Description", text: $edited.logline, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Shoot Dates", text: $edited.shootDates)
                    TextField("Expected Release", text: $edited.expectedReleaseDate)
                }

                Section("Cast Needed") {
                    ForEach(edited.castNeeded.indices, id: \.self) { index in
                        TextField("Role", text: $edited.castNeeded[index])
                    }
                    .onDelete { indexSet in
                        edited.castNeeded.remove(atOffsets: indexSet)
                    }

                    Button("Add Role") {
                        edited.castNeeded.append("")
                    }
                }

                Section("Crew Needed") {
                    ForEach(edited.crewNeeded.indices, id: \.self) { index in
                        TextField("Position", text: $edited.crewNeeded[index])
                    }
                    .onDelete { indexSet in
                        edited.crewNeeded.remove(atOffsets: indexSet)
                    }

                    Button("Add Position") {
                        edited.crewNeeded.append("")
                    }
                }

                Section("Assembled Team") {
                    Button {
                        showCastAssembledForm = true
                    } label: {
                        HStack {
                            Text("Cast Assembled")
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
                        showCrewAssembledForm = true
                    } label: {
                        HStack {
                            Text("Crew Assembled")
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
                    Text("The poster and script can't be changed when editing. To replace media, delete this post and create a new one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showCastAssembledForm) {
                CastFormView(cast: $castInfo)
            }
            .navigationDestination(isPresented: $showCrewAssembledForm) {
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

    private func save() {
        // Drop empty role/position rows before saving.
        edited.castNeeded.removeAll { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        edited.crewNeeded.removeAll { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        edited.orderedCast = castInfo.toOrderedEntries()
        edited.orderedCrew = crewInfo.toOrderedEntries()
        guard !edited.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onSave(edited)
        dismiss()
    }
}

// MARK: - Previews

#Preview {
    @Previewable @State var title = ""
    @Previewable @State var logline = ""
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

    NavigationStack {
        ProjectSubmissionView(
            title: $title,
            logline: $logline,
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
            showProjectScriptPicker: $showProjectScriptPicker
        )
        .navigationTitle("Project")
        .navigationBarTitleDisplayMode(.inline)
    }
}
