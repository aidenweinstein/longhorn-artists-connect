//
//  ReportContentView-9)Supporting.swift
//  Longhorn Artists Connect
//
//  View for flagging/reporting content, plus the Flag model and store. Flags are
//  saved to the CloudKit public database so they reach the moderator regardless of
//  which device they were submitted from, and are only surfaced on the moderator page.
//

import SwiftUI
import CloudKit
import Combine

// MARK: - Flag Reason

/// The single reason a user picks when flagging a post. Shared by the flag form
/// (ReportContentView) and the moderator viewer (FlagsListView).
enum FlagReason: String, CaseIterable, Identifiable, Codable {
    case credits = "Incorrect/Incomplete Credits"
    case viewing = "Trouble Viewing Content"
    case inappropriate = "Report for Inappropriate Content"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .credits:       return "person.text.rectangle"
        case .viewing:       return "play.slash"
        case .inappropriate: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Flag Model

struct Flag: Identifiable, Codable, Equatable {
    let id: UUID
    let reason: String          // FlagReason rawValue (stored as String for forward-compat)
    let reasoning: String
    let postID: String          // Flagged submission's id
    let postTitle: String
    let postType: String        // MediaType rawValue
    let submittedBy: String     // Display name at submission time
    let submittedByUserID: String
    let createdDate: Date

    init(
        id: UUID = UUID(),
        reason: FlagReason,
        reasoning: String,
        postID: String,
        postTitle: String,
        postType: String,
        submittedBy: String,
        submittedByUserID: String,
        createdDate: Date = Date()
    ) {
        self.id = id
        self.reason = reason.rawValue
        self.reasoning = reasoning
        self.postID = postID
        self.postTitle = postTitle
        self.postType = postType
        self.submittedBy = submittedBy
        self.submittedByUserID = submittedByUserID
        self.createdDate = createdDate
    }

    /// The reason as an enum, falling back to `.inappropriate` for unknown values.
    var reasonValue: FlagReason { FlagReason(rawValue: reason) ?? .inappropriate }
}

// MARK: - Flag Store

@MainActor
final class FlagStore: ObservableObject {
    static let shared = FlagStore()

    /// All flags known to this device, newest first. Populated from the local cache
    /// immediately and refreshed from CloudKit when the moderator opens the list.
    @Published private(set) var flags: [Flag] = []
    @Published var isLoading = false
    @Published var lastErrorMessage: String?

    private let container = CKContainer.default()
    private var database: CKDatabase { container.publicCloudDatabase }
    private let cacheKey = "cachedFlags"
    private static let recordType = "Flag"

    private init() {
        loadCache()
    }

    // MARK: - Submit

    /// Submits a flag against a post. Returns `true` on a confirmed CloudKit save.
    /// `reasoning` is expected to already be trimmed and non-empty.
    @discardableResult
    func submit(reason: FlagReason, reasoning: String, post: Submission) async -> Bool {
        let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)

        // Best-effort user ID; the flag is still valid without it.
        let userID = (try? await container.userRecordID().recordName) ?? ""

        let item = Flag(
            reason: reason,
            reasoning: reasoning,
            postID: post.id.uuidString,
            postTitle: post.title,
            postType: post.type.rawValue,
            submittedBy: name.isEmpty ? "Anonymous" : name,
            submittedByUserID: userID
        )

        do {
            _ = try await database.save(item.toCloudKitRecord())
            // Reflect locally so the moderator sees their own test flags too.
            flags.insert(item, at: 0)
            saveCache()
            lastErrorMessage = nil
            print("✅ Flag submitted: \(item.id)")
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            print("❌ Failed to submit flag: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Fetch (moderator)

    /// Fetches all flags from CloudKit. Called when the moderator opens the viewer.
    func fetchAll() async {
        isLoading = true
        defer { isLoading = false }

        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdDate", ascending: false)]

        do {
            let results = try await database.records(matching: query).matchResults
            let fetched = results.compactMap { try? $0.1.get() }
                .compactMap { Flag.fromCloudKitRecord($0) }
                .sorted { $0.createdDate > $1.createdDate }
            flags = fetched
            saveCache()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            print("❌ Failed to fetch flags: \(error.localizedDescription)")
        }
    }

    // MARK: - Resolve

    /// Resolves (removes) a flag once the moderator has handled it. Deletes the
    /// CloudKit record and drops it locally.
    func resolve(_ flag: Flag) async {
        // Remove locally right away so the list updates immediately.
        flags.removeAll { $0.id == flag.id }
        saveCache()

        do {
            try await database.deleteRecord(withID: CKRecord.ID(recordName: flag.id.uuidString))
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            print("❌ Failed to resolve flag: \(error.localizedDescription)")
        }
    }

    // MARK: - Local Cache

    private func loadCache() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([Flag].self, from: data) {
            flags = decoded.sorted { $0.createdDate > $1.createdDate }
        }
    }

    private func saveCache() {
        if let encoded = try? JSONEncoder().encode(flags) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }
    }
}

// MARK: - CloudKit Conversion

extension Flag {
    func toCloudKitRecord() -> CKRecord {
        let record = CKRecord(
            recordType: "Flag",
            recordID: CKRecord.ID(recordName: id.uuidString)
        )
        record["reason"] = reason as CKRecordValue
        record["reasoning"] = reasoning as CKRecordValue
        record["postID"] = postID as CKRecordValue
        record["postTitle"] = postTitle as CKRecordValue
        record["postType"] = postType as CKRecordValue
        record["submittedBy"] = submittedBy as CKRecordValue
        record["submittedByUserID"] = submittedByUserID as CKRecordValue
        record["createdDate"] = createdDate as CKRecordValue
        return record
    }

    static func fromCloudKitRecord(_ record: CKRecord) -> Flag? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let reason = record["reason"] as? String else {
            return nil
        }
        return Flag(
            id: id,
            reason: FlagReason(rawValue: reason) ?? .inappropriate,
            reasoning: (record["reasoning"] as? String) ?? "",
            postID: (record["postID"] as? String) ?? "",
            postTitle: (record["postTitle"] as? String) ?? "Untitled",
            postType: (record["postType"] as? String) ?? "",
            submittedBy: (record["submittedBy"] as? String) ?? "Anonymous",
            submittedByUserID: (record["submittedByUserID"] as? String) ?? "",
            createdDate: (record["createdDate"] as? Date) ?? Date()
        )
    }
}

// MARK: - Report Content View

struct ReportContentView: View {
    /// Maximum length of the free-text reasoning.
    private static let maxReasoningLength = 5000

    let post: Submission
    @Environment(\.dismiss) private var dismiss

    @State private var selectedReason: FlagReason?
    @State private var reasoningText: String = ""
    @State private var isSubmitting = false
    @State private var showSuccessAlert = false

    private var canSubmit: Bool {
        selectedReason != nil &&
        !reasoningText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSubmitting
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // A single "Reason" section holding both the reason choices and the
                // reasoning text, so the sheet stays compact. Built as a plain VStack
                // (not a Form) so it never scrolls, never resizes when the keyboard
                // appears, and keeps a fixed card color instead of the Form's
                // gray→white shift.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reason")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)

                    VStack(spacing: 0) {
                        ForEach(FlagReason.allCases) { reason in // ⚙️ Pick exactly one reason
                            Button {
                                selectedReason = reason
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: reason.icon)
                                        .foregroundStyle(Color.brandOrange)
                                        .frame(width: 24)
                                    Text(reason.rawValue)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedReason == reason {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.brandOrange)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 16)
                        }

                        // Reasoning input, kept in the same section. Fixed height so
                        // the field never grows when focused.
                        ZStack(alignment: .topLeading) {
                            if reasoningText.isEmpty {
                                Text("Add your reasoning…")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }
                            TextEditor(text: $reasoningText)
                                .scrollContentBackground(.hidden)
                                .frame(height: 96)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                // Cap the reasoning length; the editor scrolls internally
                                // for longer text so the field stays a fixed height.
                                .onChange(of: reasoningText) { _, newValue in
                                    if newValue.count > Self.maxReasoningLength {
                                        reasoningText = String(newValue.prefix(Self.maxReasoningLength))
                                    }
                                }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                }
                .padding(.horizontal)
                .padding(.top, 16)

                Spacer(minLength: 0)

                // Matches the app's primary-action buttons (e.g. Buy Ticket / audition
                // submit): grey while disabled, brand orange once a reason and reasoning
                // are provided.
                Button {
                    submitReport()
                } label: {
                    Label("Submit", systemImage: "flag.fill") // ⚙️ Submit button text
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSubmit ? Color.brandOrange : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canSubmit)
                .padding(.horizontal)
                .padding(.vertical)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Flag") // ⚙️ Navigation title
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large]) // half-page by default; draggable to full
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(false)
        .alert("Flag Submitted", isPresented: $showSuccessAlert) { // ⚙️ Success alert title
            Button("OK", role: .cancel) { // ⚙️ Alert button text
                dismiss()
            }
        } message: {
            Text("Thank you for helping keep our community safe. We will review this report.") // ⚙️ Success message
        }
    }

    private func submitReport() {
        guard let selectedReason else { return }
        let trimmedReasoning = reasoningText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReasoning.isEmpty else { return }

        isSubmitting = true
        Task {
            await FlagStore.shared.submit(reason: selectedReason, reasoning: trimmedReasoning, post: post)
            await MainActor.run {
                isSubmitting = false
                showSuccessAlert = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ReportContentView(
        post: Submission(id: UUID(), type: .film, title: "Sample Film", details: "A great movie")
    )
}
