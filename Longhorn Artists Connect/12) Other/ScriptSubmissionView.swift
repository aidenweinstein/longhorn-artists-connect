//
//  ScriptSubmissionView.swift
//  Longhorn Artists Connect
//
//  Submits a script to the Script Collection (see `ScriptsCollectionView`).
//  Not reachable from the tab bar since Agent mode was removed on 2026-10-16;
//  the collection's own + button still presents it.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import CloudKit

/// Project statuses a script can be tagged with (mirrors the collection's filter).
let scriptStatusOptions = ["Casting & Crewing", "Casting", "Crewing", "In Production", "In Post-Production", "Releasing"]

struct ScriptSubmissionView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var logline = ""
    @State private var authors = ""
    @State private var selectedGenres: Set<String> = []
    @State private var projectStatus = ""
    @State private var shootDates = ""
    @State private var fileURL: URL?
    @State private var pageCount = 0

    @State private var showFilePicker = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSubmitted = false

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !authorList.isEmpty
            && fileURL != nil
            && !isSubmitting
    }

    /// Writers entered as a comma-separated list.
    private var authorList: [String] {
        authors.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            // Same rule as the Share tab: new accounts verify a school email first.
            VerificationGate(
                action: "submit a script",
                bypass: StudentVerificationManager.accountPredatesVerification
            ) {
                form
            }
            .navigationTitle("Submit a Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Submit") { Task { await submit() } }
                            .fontWeight(.semibold)
                            .disabled(!canSubmit)
                    }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPicker(
                    contentTypes: [.pdf, .plainText, .rtf, .rtfd],
                    onSelect: { url in
                        fileURL = url
                        pageCount = PDFDocument(url: url)?.pageCount ?? 0
                        showFilePicker = false
                    },
                    onCancel: { showFilePicker = false }
                )
            }
            .alert("Script Submitted", isPresented: $showSubmitted) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your script is now in the Script Collection.")
            }
            .alert("Couldn't Submit", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private var form: some View {
        Form {
            Section {
                Button {
                    showFilePicker = true
                } label: {
                    HStack {
                        Image(systemName: fileURL == nil ? "doc.badge.plus" : "doc.text.fill")
                            .foregroundStyle(Color.brandOrange)
                        Text(fileURL?.lastPathComponent ?? "Select script")
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        if pageCount > 0 {
                            Text("\(pageCount) pages")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Script")
            }

            Section("Details") {
                TextField("Title", text: $title, axis: .vertical)
                TextField("Writer(s), separated by commas", text: $authors, axis: .vertical)
                TextField("Logline", text: $logline, axis: .vertical)
                    .lineLimit(2...5)
            }

            Section("Genres") {
                ForEach(projectScriptGenres, id: \.self) { genre in
                    Button {
                        if selectedGenres.contains(genre) {
                            selectedGenres.remove(genre)
                        } else {
                            selectedGenres.insert(genre)
                        }
                    } label: {
                        HStack {
                            Text(genre)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedGenres.contains(genre) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.brandOrange)
                            }
                        }
                    }
                }
            }

            Section("Production") {
                Picker("Status", selection: $projectStatus) {
                    Text("None").tag("")
                    ForEach(scriptStatusOptions, id: \.self) { Text($0).tag($0) }
                }
                TextField("Shoot dates (optional)", text: $shootDates, axis: .vertical)
            }
        }
        .disabled(isSubmitting)
    }

    private func submit() async {
        guard let fileURL else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let defaults = UserDefaults.standard
        let submitter = "\(defaults.string(forKey: "userFirstName") ?? "") \(defaults.string(forKey: "userLastName") ?? "")"
            .trimmingCharacters(in: .whitespaces)
        let userID = CloudKitManager.shared.userRecordID?.recordName
            ?? defaults.string(forKey: ModeratorAccess.currentUserRecordNameKey)
            ?? ""

        let script = Script(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            logline: logline.trimmingCharacters(in: .whitespacesAndNewlines),
            // Keep the genres in the list's order rather than tap order.
            genres: projectScriptGenres.filter(selectedGenres.contains),
            authors: authorList,
            pageCount: pageCount,
            projectStatus: projectStatus,
            shootDates: shootDates.trimmingCharacters(in: .whitespacesAndNewlines),
            submittedBy: submitter,
            submittedByUserID: userID
        )

        do {
            try await ScriptManager.shared.submit(script, fileURL: fileURL)
            showSubmitted = true
        } catch {
            errorMessage = "\(error.localizedDescription)\n\nMake sure the \(CloudKitRecordTypes.script) record type exists in CloudKit (\(CloudKitEnvironmentDetector.current))."
        }
    }
}

#Preview {
    ScriptSubmissionView()
}
