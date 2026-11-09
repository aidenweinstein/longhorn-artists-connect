//
//  ScriptsCollectionView.swift
//  Longhorn Artists Connect  
//
//  Script collection for agents and talent scouts
//

import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import Combine
import CloudKit

// MARK: - Script Model

struct Script: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var logline: String
    var genres: [String]
    var authors: [String]
    var pageCount: Int
    var projectStatus: String
    var shootDates: String
    /// The script file's extension ("pdf", "txt", …), so the downloaded copy opens
    /// in QuickLook.
    var fileExtension: String
    /// The downloaded copy on disk, or nil until `ScriptManager` fetches it.
    var fileURL: URL?
    var uploadDate: Date
    var submittedBy: String
    /// The submitter's CloudKit user record name.
    var submittedByUserID: String

    init(
        id: UUID = UUID(),
        title: String,
        logline: String = "",
        genres: [String] = [],
        authors: [String] = [],
        pageCount: Int = 0,
        projectStatus: String = "",
        shootDates: String = "",
        fileExtension: String = "pdf",
        fileURL: URL? = nil,
        uploadDate: Date = Date(),
        submittedBy: String = "",
        submittedByUserID: String = ""
    ) {
        self.id = id
        self.title = title
        self.logline = logline
        self.genres = genres
        self.authors = authors
        self.pageCount = pageCount
        self.projectStatus = projectStatus
        self.shootDates = shootDates
        self.fileExtension = fileExtension
        self.fileURL = fileURL
        self.uploadDate = uploadDate
        self.submittedBy = submittedBy
        self.submittedByUserID = submittedByUserID
    }
}

// MARK: - Scripts Collection View

struct ScriptsCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    /// False when shown as a tab, where there's nothing to dismiss.
    var showsCloseButton = true
    @StateObject private var scriptManager = ScriptManager.shared
    @State private var searchText = ""
    @State private var selectedGenreFilter: String = "All"
    @State private var selectedStatusFilter: String = "All"
    @State private var selectedScript: Script?
    @State private var showScriptDetail = false
    @State private var scriptToPreview: URL?
    /// Adds a script to the collection (presents `ScriptSubmissionView`).
    @State private var showAddScript = false

    private let genreOptions = ["All"] + projectScriptGenres
    private let statusOptions = ["All"] + scriptStatusOptions
    
    var filteredScripts: [Script] {
        var scripts = scriptManager.scripts
        
        // Filter by search text
        if !searchText.isEmpty {
            scripts = scripts.filter { script in
                script.title.localizedCaseInsensitiveContains(searchText) ||
                script.logline.localizedCaseInsensitiveContains(searchText) ||
                script.authors.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            }
        }
        
        // Filter by genre
        if selectedGenreFilter != "All" {
            scripts = scripts.filter { $0.genres.contains(selectedGenreFilter) }
        }
        
        // Filter by status
        if selectedStatusFilter != "All" {
            scripts = scripts.filter { $0.projectStatus == selectedStatusFilter }
        }
        
        return scripts.sorted { $0.uploadDate > $1.uploadDate }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filters
                VStack(spacing: 12) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search scripts, authors...", text: $searchText, axis: .vertical)
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.top, 12)
                    
                    // Filter pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // Genre filter
                            Menu {
                                ForEach(genreOptions, id: \.self) { genre in
                                    Button {
                                        selectedGenreFilter = genre
                                    } label: {
                                        HStack {
                                            Text(genre)
                                            if selectedGenreFilter == genre {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "film")
                                        .font(.caption)
                                    Text(selectedGenreFilter)
                                        .font(.subheadline)
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedGenreFilter == "All" ?
                                    Color.secondary.opacity(0.15) :
                                    Color.brandOrange
                                )
                                .foregroundStyle(selectedGenreFilter == "All" ? .primary : Color.white)
                                .clipShape(Capsule())
                            }
                            
                            // Status filter
                            Menu {
                                ForEach(statusOptions, id: \.self) { status in
                                    Button {
                                        selectedStatusFilter = status
                                    } label: {
                                        HStack {
                                            Text(status)
                                            if selectedStatusFilter == status {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chart.bar.doc.horizontal")
                                        .font(.caption)
                                    Text(selectedStatusFilter == "All" ? "Status" : selectedStatusFilter)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedStatusFilter == "All" ?
                                    Color.secondary.opacity(0.15) :
                                    Color.brandOrange
                                )
                                .foregroundStyle(selectedStatusFilter == "All" ? .primary : Color.white)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 8)
                }
                .background(Color(uiColor: .systemBackground))
                
                Divider()
                
                // Scripts list
                if scriptManager.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading scripts...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredScripts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: searchText.isEmpty && selectedGenreFilter == "All" && selectedStatusFilter == "All" ? "doc.text" : "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        
                        Text(searchText.isEmpty && selectedGenreFilter == "All" && selectedStatusFilter == "All" ? "No Scripts Available" : "No Results Found")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text(searchText.isEmpty && selectedGenreFilter == "All" && selectedStatusFilter == "All" ? (scriptManager.loadError ?? "Scripts submitted by artists will appear here") : "Try adjusting your filters or search terms")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(filteredScripts) { script in
                                ScriptCard(script: script) {
                                    selectedScript = script
                                    showScriptDetail = true
                                }
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        await scriptManager.refresh()
                    }
                }
            }
            .navigationTitle("Scripts Collection")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddScript = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Script")
                }
                if showsCloseButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showScriptDetail) {
                if let script = selectedScript {
                    ScriptDetailView(script: script)
                }
            }
            .sheet(isPresented: $showAddScript) {
                ScriptSubmissionView()
            }
        }
        .task {
            await scriptManager.refresh()
        }
    }
}

// MARK: - Script Card

struct ScriptCard: View {
    let script: Script
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with title and status
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(script.title)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        
                        if !script.authors.isEmpty {
                            Text("by \(script.authors.joined(separator: ", "))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if !script.projectStatus.isEmpty {
                        Text(script.projectStatus)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.brandOrange)
                            .clipShape(Capsule())
                    }
                }
                
                // Logline
                if !script.logline.isEmpty {
                    Text(script.logline)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                
                // Genres
                if !script.genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(script.genres, id: \.self) { genre in
                                Text(genre)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.brandOrange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.brandOrange.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                
                Divider()
                
                // Footer info
                HStack {
                    if script.pageCount > 0 {
                        Label("\(script.pageCount) pages", systemImage: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if !script.shootDates.isEmpty {
                        Label(script.shootDates, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Script Detail View

struct ScriptDetailView: View {
    let script: Script
    @Environment(\.dismiss) private var dismiss
    @State private var showQuickLook = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(script.title)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        if !script.authors.isEmpty {
                            Text("Written by \(script.authors.joined(separator: ", "))")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        
                        if !script.submittedBy.isEmpty {
                            Text("Submitted by \(script.submittedBy)")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    // Status badge
                    if !script.projectStatus.isEmpty {
                        HStack {
                            Label(script.projectStatus, systemImage: "chart.bar.doc.horizontal")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.brandOrange)
                                .clipShape(Capsule())
                            
                            Spacer()
                        }
                    }
                    
                    Divider()
                    
                    // Logline
                    if !script.logline.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Logline")
                                .font(.headline)
                            Text(script.logline)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Genres
                    if !script.genres.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Genres")
                                .font(.headline)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(script.genres, id: \.self) { genre in
                                    Text(genre)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.brandOrange)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.brandOrange.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    
                    // Details grid
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Details")
                            .font(.headline)
                        
                        VStack(spacing: 12) {
                            if script.pageCount > 0 {
                                DetailRow(icon: "doc.text", label: "Page Count", value: "\(script.pageCount) pages")
                            }
                            
                            if !script.shootDates.isEmpty {
                                DetailRow(icon: "calendar", label: "Shoot Dates", value: script.shootDates)
                            }
                            
                            DetailRow(icon: "clock", label: "Uploaded", value: formatDate(script.uploadDate))
                        }
                    }
                    
                    // Action buttons
                    VStack(spacing: 12) {
                        if script.fileURL != nil {
                            Button {
                                showQuickLook = true
                            } label: {
                                Label("Read Script", systemImage: "book.pages")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.brandOrange)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.slash")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("Script file not available")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showQuickLook) {
                if let url = script.fileURL {
                    QuickLookView(url: url)
                }
            }
        }
        .presentationDragIndicator(.hidden)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.brandOrange)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = calculateLayout(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = calculateLayout(in: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    private func calculateLayout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var positions: [CGPoint] = []
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
        
        return (CGSize(width: width, height: currentY + lineHeight), positions)
    }
}

// MARK: - QuickLook View

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        
        let navController = UINavigationController(rootViewController: controller)
        return navController
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, dismiss: dismiss)
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let url: URL
        let dismiss: DismissAction
        
        init(url: URL, dismiss: DismissAction) {
            self.url = url
            self.dismiss = dismiss
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return url as QLPreviewItem
        }
        
        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            dismiss()
        }
    }
}

// MARK: - Script Manager

/// The shared script database: every script added from the Script Collection,
/// stored as `Script` records in the public CloudKit database.
///
/// Reading is gated on the client only — this is not a security control. The
/// collection has had no entry point from the tab bar since Agent mode was
/// removed on 2026-10-16.
///
/// ⚠️ CloudKit: the `Script` record type must be created in BOTH environments with
/// `title`, `logline`, `projectStatus`, `shootDates`, `scriptFileExt`, `submittedBy`,
/// `submittedByUserID` (STRING), `genres`, `authors` (STRING LIST), `pageCount`
/// (INT64), `uploadDate` (DATE/TIME), `scriptFile` (ASSET), plus a Queryable index
/// on `recordName` (the collection lists every record).
@MainActor
final class ScriptManager: ObservableObject {
    static let shared = ScriptManager()

    @Published private(set) var scripts: [Script] = []
    @Published private(set) var isLoading = false
    /// The last fetch failure, shown in the collection's empty state.
    @Published private(set) var loadError: String?

    /// Every field except the file itself, so a refresh doesn't re-download PDFs
    /// that are already on disk.
    private static let metadataKeys = [
        "title", "logline", "genres", "authors", "pageCount", "projectStatus",
        "shootDates", "scriptFileExt", "submittedBy", "submittedByUserID", "uploadDate",
    ]

    private var database: CKDatabase { CKContainer.default().publicCloudDatabase }

    /// Env-prefixed like every other CloudKit cache (see `localCachePrefix`).
    private var cacheKey: String { CloudKitEnvironmentDetector.localCachePrefix + "scriptCollectionCache" }

    /// Downloaded script files, kept so QuickLook can open them offline.
    private var filesDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(CloudKitEnvironmentDetector.localCachePrefix + "Scripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([Script].self, from: data) {
            scripts = cached.map { withLocalFile($0) }
        }
    }

    /// Re-reads the collection from CloudKit, then downloads any script files that
    /// aren't on disk yet. Keeps the cached list when CloudKit can't be reached.
    func refresh() async {
        isLoading = scripts.isEmpty
        defer { isLoading = false }
        do {
            let records = try await CloudKitManager.shared.fetchRecords(
                ofType: CloudKitRecordTypes.script,
                matching: NSPredicate(value: true),
                sortBy: nil
            )
            loadError = nil
            scripts = records.compactMap(Self.script(from:)).map { withLocalFile($0) }
            saveCache()
            await downloadMissingFiles()
        } catch {
            print("⚠️ Couldn't load scripts: \(error.localizedDescription)")
            loadError = "Couldn't load scripts. Make sure the \(CloudKitRecordTypes.script) record type exists in CloudKit (\(CloudKitEnvironmentDetector.current))."
        }
    }

    /// Uploads a script to the collection. `fileURL` must be a local copy (the
    /// `DocumentPicker` hands back one in the temp directory).
    func submit(_ script: Script, fileURL: URL) async throws {
        let record = CKRecord(recordType: CloudKitRecordTypes.script, recordID: Self.recordID(for: script.id))
        record["title"] = script.title as CKRecordValue
        record["logline"] = script.logline as CKRecordValue
        record["genres"] = script.genres as CKRecordValue
        record["authors"] = script.authors as CKRecordValue
        record["pageCount"] = script.pageCount as CKRecordValue
        record["projectStatus"] = script.projectStatus as CKRecordValue
        record["shootDates"] = script.shootDates as CKRecordValue
        record["submittedBy"] = script.submittedBy as CKRecordValue
        record["submittedByUserID"] = script.submittedByUserID as CKRecordValue
        record["uploadDate"] = script.uploadDate as CKRecordValue
        let ext = fileURL.pathExtension.isEmpty ? "pdf" : fileURL.pathExtension.lowercased()
        record["scriptFileExt"] = ext as CKRecordValue
        record["scriptFile"] = CKAsset(fileURL: fileURL)

        try await CloudKitManager.shared.save(record: record)

        // Keep a copy so the submitter sees it in the collection immediately.
        let local = localFileURL(for: script.id, ext: ext)
        try? FileManager.default.removeItem(at: local)
        try? FileManager.default.copyItem(at: fileURL, to: local)
        var saved = script
        saved.fileExtension = ext
        scripts.removeAll { $0.id == script.id }
        scripts.append(withLocalFile(saved))
        saveCache()
    }

    // MARK: - Files

    private func downloadMissingFiles() async {
        let missing = scripts.filter { $0.fileURL == nil }
        guard !missing.isEmpty else { return }
        do {
            let results = try await database.records(
                for: missing.map { Self.recordID(for: $0.id) },
                desiredKeys: ["scriptFile"]
            )
            for script in missing {
                guard case .success(let record)? = results[Self.recordID(for: script.id)],
                      let assetURL = (record["scriptFile"] as? CKAsset)?.fileURL else { continue }
                // The asset lives in CloudKit's own cache, without an extension —
                // QuickLook needs the extension to know how to render it.
                let local = localFileURL(for: script.id, ext: script.fileExtension)
                try? FileManager.default.removeItem(at: local)
                try? FileManager.default.copyItem(at: assetURL, to: local)
            }
            scripts = scripts.map { withLocalFile($0) }
        } catch {
            print("⚠️ Couldn't download script files: \(error.localizedDescription)")
        }
    }

    private func localFileURL(for id: UUID, ext: String) -> URL {
        filesDirectory.appendingPathComponent(id.uuidString).appendingPathExtension(ext)
    }

    /// Points `fileURL` at the downloaded copy, or nil if it isn't on disk yet.
    private func withLocalFile(_ script: Script) -> Script {
        var script = script
        let local = localFileURL(for: script.id, ext: script.fileExtension)
        script.fileURL = FileManager.default.fileExists(atPath: local.path) ? local : nil
        return script
    }

    private func saveCache() {
        if let encoded = try? JSONEncoder().encode(scripts) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }
    }

    // MARK: - Records

    private static func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "Script_\(id.uuidString)")
    }

    private static func script(from record: CKRecord) -> Script? {
        let name = record.recordID.recordName
        guard name.hasPrefix("Script_"),
              let id = UUID(uuidString: String(name.dropFirst("Script_".count))),
              let title = record["title"] as? String else { return nil }
        return Script(
            id: id,
            title: title,
            logline: record["logline"] as? String ?? "",
            genres: record["genres"] as? [String] ?? [],
            authors: record["authors"] as? [String] ?? [],
            pageCount: (record["pageCount"] as? Int64).map(Int.init) ?? 0,
            projectStatus: record["projectStatus"] as? String ?? "",
            shootDates: record["shootDates"] as? String ?? "",
            fileExtension: record["scriptFileExt"] as? String ?? "pdf",
            uploadDate: record["uploadDate"] as? Date ?? record.creationDate ?? Date(),
            submittedBy: record["submittedBy"] as? String ?? "",
            submittedByUserID: record["submittedByUserID"] as? String ?? ""
        )
    }
}


// MARK: - Preview

#Preview("Scripts Collection") {
    ScriptsCollectionView()
}

#Preview("Script Detail") {
    ScriptDetailView(script: Script(
        title: "The Last Stand",
        logline: "A gripping thriller about a detective's final case before retirement takes an unexpected turn into a web of corruption and betrayal.",
        genres: ["Thriller", "Crime", "Drama"],
        authors: ["Jane Doe", "John Smith"],
        pageCount: 112,
        projectStatus: "Casting & Crewing",
        shootDates: "May 1 - May 15, 2026",
        submittedBy: "Jane Doe"
    ))
}
