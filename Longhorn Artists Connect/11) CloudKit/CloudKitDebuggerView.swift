//
//  CloudKitDebuggerView.swift
//  Longhorn Artists Connect
//
//  CloudKit debugging and diagnostic tool
//

import SwiftUI
import CloudKit
import Combine

// MARK: - CloudKit Debugger View

struct CloudKitDebuggerView: View {
    @StateObject private var debugger = CloudKitDebugger()

    var body: some View {
        NavigationStack {
            List {
                // MARK: - The Story Behind "Nexus"
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("The name \"Nexus\" was inspired by an action-RPG video game from 2009 called \"Demon's Souls.\" In it, the main hub that connects you between all areas of the game is called the Nexus. There, you can upgrade weapons and gear, level up your stats using souls, and prepare yourself for the next battle.")

                        Text("Although we don't live in a dark fantasy kingdom rampant with monsters, it can feel like a daunting quest to break into the entertainment space. And so, we need our own Nexus. A safe space to experiment and collaborate and inspire, separate from the outside world.")

                        Text("So take advantage of it. Upgrade your weapons. Level up your stats. Build your team. If you do, you'll be ready for any obstacle that comes your way.")

                        Text("— Aiden Weinstein")
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.callout)
                    .padding(.vertical, 4)
                }

                // MARK: - Diagnostics
                Section("Diagnostics") {
                    if let userID = debugger.userRecordID {
                        StatusRow(label: "User ID", value: userID)
                            .textSelection(.enabled)
                    }
                    StatusRow(label: "Version", value: AppInfo.version)
                    StatusRow(label: "iPhone Model", value: DeviceInfo.modelName)
                    StatusRow(label: "Database", value: "Public")
                    StatusRow(label: "Environment", value: debugger.environment)
                }

                // MARK: - CloudKit Schema
                Section("CloudKit Schema") {
                    SchemaGapReportView()
                }

                // MARK: - Storage
                Section("Storage") {
                    StorageDiagnostics()
                }
            }
            .navigationTitle("Secret Page 1/5")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await debugger.loadDiagnostics()
            }
        }
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Storage Diagnostics

/// Breakdown of what the app occupies inside its container, plus a button to run the
/// same reclaim the app performs at launch and when it backgrounds.
///
/// `Documents & Data` in iOS Settings is a single opaque number covering Documents,
/// Library (including every cache) and tmp together, so it can't be attributed from
/// the outside. This is the only way to see the breakdown on a TestFlight build, where
/// the Xcode console isn't available — the largest-files list names the submission and
/// kind, and re-measuring after a reclaim shows whether the space comes back or is
/// immediately re-downloaded.
private struct StorageDiagnostics: View {
    @State private var report = "Measuring…"
    @State private var isWorking = false

    var body: some View {
        Text(report)
            .font(.system(.caption2, design: .monospaced))
            .textSelection(.enabled)

        Button("Reclaim Disk Space") {
            Task { await reclaim() }
        }
        .disabled(isWorking)
        .task { await refresh() }
    }

    /// Re-measures off the main thread — the walk touches every file in the container.
    private func refresh() async {
        report = await Task.detached(priority: .utility) {
            FileManager.default.storageReport()
        }.value
    }

    private func reclaim() async {
        isWorking = true
        await Task.detached(priority: .utility) {
            FileManager.default.reclaimDiskSpace()
        }.value
        await refresh()
        isWorking = false
    }
}

// MARK: - Status Row Component

private struct StatusRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - App Info Helper

private enum AppInfo {
    /// The marketing version and build number, e.g. "1.2 (34)".
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

// MARK: - Device Info Helper

private enum DeviceInfo {
    /// The hardware model identifier, e.g. "iPhone17,1". On the simulator this
    /// reads the simulated device from the environment instead of the host Mac.
    static var modelIdentifier: String {
        if let simID = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simID
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier += String(UnicodeScalar(UInt8(value)))
        }
    }

    /// A human-readable marketing name mapped from the identifier, falling back
    /// to the raw identifier for models not in the table.
    static var modelName: String {
        marketingNames[modelIdentifier] ?? modelIdentifier
    }

    /// Screen size in points, e.g. "393 × 852 pt".
    static var screenPointSize: String {
        let size = UIScreen.main.bounds.size
        return "\(Int(size.width)) × \(Int(size.height)) pt"
    }

    /// Screen size in native pixels, e.g. "1179 × 2556 px".
    static var screenPixelSize: String {
        let size = UIScreen.main.nativeBounds.size
        return "\(Int(size.width)) × \(Int(size.height)) px"
    }

    /// Screen scale, e.g. "@3x".
    static var screenScaleText: String {
        "@\(Int(UIScreen.main.scale))x"
    }

    private static let marketingNames: [String: String] = [
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e"
    ]
}

// MARK: - CloudKit Environment Detection

/// Determines the *actual* CloudKit environment the running app is using, rather
/// than guessing from the `DEBUG` compile flag. `#if DEBUG` only reflects how the
/// binary was compiled — an archive built with the Debug configuration will report
/// "Development" even after it's uploaded to the App Store, which is misleading.
///
/// CloudKit resolves to the **Development** environment only for builds signed with
/// a *development* provisioning profile (one that permits debugging via
/// `get-task-allow`, i.e. a build run from Xcode). Ad-Hoc, Enterprise, TestFlight,
/// and App Store builds all talk to the **Production** environment.
enum CloudKitEnvironmentDetector {
    /// Whether this build's native `CKContainer` talks to the Development environment.
    /// Resolved once — the provisioning profile can't change while the app runs.
    static let isDevelopment: Bool = current == "Development"

    /// Prefix for every on-device cache of CloudKit data. Development gets its own
    /// namespace so a Debug build never shows posts cached by a TestFlight/App Store
    /// build on the same device (and vice versa); Production keeps the unprefixed
    /// names so existing installs keep their caches.
    static var localCachePrefix: String { isDevelopment ? "dev_" : "" }

    /// "Development" or "Production", based on the embedded provisioning profile.
    static var current: String {
        #if targetEnvironment(simulator)
        // Simulator builds always run against the Development environment.
        return "Development"
        #else
        guard let allowsDebugging = embeddedProfileAllowsDebugging() else {
            // No embedded provisioning profile means the binary was re-signed by
            // Apple for distribution (TestFlight / App Store) → Production.
            return "Production"
        }
        // A development profile permits debugging and maps to the CloudKit
        // Development environment; everything else uses Production.
        return allowsDebugging ? "Development" : "Production"
        #endif
    }

    /// Reads `get-task-allow` from the bundle's `embedded.mobileprovision`.
    /// Returns `nil` when no profile is embedded (App Store / TestFlight builds).
    private static func embeddedProfileAllowsDebugging() -> Bool? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        // The profile is a CMS/PKCS7 blob, but the embedded entitlements plist is
        // plain text inside it. ISO Latin-1 decodes any byte sequence losslessly.
        guard let raw = String(data: data, encoding: .isoLatin1),
              let start = raw.range(of: "<plist"),
              let end = raw.range(of: "</plist>") else {
            return nil
        }

        let plistString = String(raw[start.lowerBound..<end.upperBound])
        guard let plistData = plistString.data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else {
            return nil
        }

        return entitlements["get-task-allow"] as? Bool ?? false
    }
}

// MARK: - CloudKit Debugger Logic

@MainActor
class CloudKitDebugger: ObservableObject {
    @Published var isAvailable = false
    @Published var accountStatusText = "Checking..."
    @Published var userRecordID: String?
    @Published var containerIdentifier = ""
    @Published var teamID: String?
    @Published var environment = ""
    @Published var totalSubmissions = 0
    @Published var yourSubmissions = 0
    @Published var otherUsersSubmissions = 0
    @Published var uniqueUsers: [UserInfo] = []
    @Published var recentSubmissions: [Submission] = []
    @Published var logs: [String] = []
    @Published var isLoading = false
    
    private let container = CKContainer.default()
    private var database: CKDatabase {
        container.publicCloudDatabase
    }
    
    struct UserInfo: Identifiable, Hashable {
        let id = UUID()
        let userRecordID: String
        let displayName: String
        let submissionCount: Int
        let isCurrentUser: Bool
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(userRecordID)
        }
        
        static func == (lhs: UserInfo, rhs: UserInfo) -> Bool {
            lhs.userRecordID == rhs.userRecordID
        }
    }
    
    // Simple struct for display purposes
    struct Submission: Identifiable {
        let id: UUID
        let type: MediaType
        let title: String
        let details: String
        let isApproved: Bool
        let submittedBy: String
        let createdDate: Date
    }
    
    enum MediaType: String {
        case film = "Film"
        case music = "Music"
        case reel = "Reel"
        case project = "Project"
        case event = "Event"
    }
    
    /// Lightweight load for the Secret Menu: only resolves the values it displays
    /// (the user's record ID and the CloudKit environment) without fetching the
    /// full submission set.
    func loadDiagnostics() async {
        await checkAvailability()
        await getContainerInfo()
    }

    func initialize() async {
        isLoading = true
        addLog("🔧 Initializing CloudKit debugger...")

        // Check availability
        await checkAvailability()

        // Get container info
        await getContainerInfo()

        // Fetch submissions
        await refresh()

        isLoading = false
    }
    
    func checkAvailability() async {
        do {
            let status = try await container.accountStatus()
            
            await MainActor.run {
                isAvailable = (status == .available)
                
                switch status {
                case .available:
                    accountStatusText = "✅ Available"
                case .noAccount:
                    accountStatusText = "❌ No iCloud Account"
                case .restricted:
                    accountStatusText = "⚠️ Restricted"
                case .couldNotDetermine:
                    accountStatusText = "❓ Could Not Determine"
                case .temporarilyUnavailable:
                    accountStatusText = "⏳ Temporarily Unavailable"
                @unknown default:
                    accountStatusText = "❓ Unknown"
                }
                
                addLog("CloudKit Status: \(accountStatusText)")
            }
            
            if isAvailable {
                let recordID = try await container.userRecordID()
                await MainActor.run {
                    userRecordID = recordID.recordName
                    addLog("Your UserID: \(recordID.recordName)")
                }
            }
        } catch {
            await MainActor.run {
                accountStatusText = "❌ Error: \(error.localizedDescription)"
                addLog("Error checking availability: \(error)")
            }
        }
    }
    
    func getContainerInfo() async {
        await MainActor.run {
            containerIdentifier = container.containerIdentifier ?? "Unknown"
            
            // Try to extract team ID from container identifier
            // Format is usually: iCloud.com.teamid.appname
            let components = containerIdentifier.split(separator: ".")
            if components.count >= 3 {
                teamID = String(components[2])
            }
            
            // Determine the *actual* CloudKit environment from how the app was
            // signed, not from the DEBUG compile flag (which only reflects how the
            // binary was compiled). See CloudKitEnvironmentDetector.
            environment = CloudKitEnvironmentDetector.current
            
            addLog("Container: \(containerIdentifier)")
            addLog("Environment: \(environment)")
        }
    }
    
    func refresh() async {
        isLoading = true
        addLog("🔄 Fetching submissions from CloudKit...")
        
        do {
            // ⚠️ IMPORTANT: Check legacy "Submission" record type first!
            // This is where current submissions are being saved
            let legacySubmissions = try await fetchRecords(recordType: "Submission")
            
            // Fetch all submissions from new specialized record types
            let films = try await fetchRecords(recordType: "FilmSubmission")
            let music = try await fetchRecords(recordType: "MusicSubmission")
            let reels = try await fetchRecords(recordType: "ReelSubmission")
            let projects = try await fetchRecords(recordType: "ProjectSubmission")
            let events = try await fetchRecords(recordType: "EventSubmission")
            
            let allRecords = legacySubmissions + films + music + reels + projects + events
            
            await MainActor.run {
                totalSubmissions = allRecords.count
                addLog("Found \(totalSubmissions) total submissions")
                addLog("📦 Universal Submission records: \(legacySubmissions.count)")
                addLog("  Specialized Films: \(films.count)")
                addLog("  Specialized Music: \(music.count)")
                addLog("  Specialized Reels: \(reels.count)")
                addLog("  Specialized Projects: \(projects.count)")
                addLog("  Specialized Events: \(events.count)")
                
                if legacySubmissions.count > 0 && (films.count + music.count + reels.count + projects.count + events.count) == 0 {
                    addLog("✅ Using unified Submission record type")
                    addLog("ℹ️ This is the recommended approach for your app architecture")
                } else if legacySubmissions.count > 0 && (films.count + music.count + reels.count + projects.count + events.count) > 0 {
                    addLog("⚠️ WARNING: Mixed record types detected!")
                    addLog("⚠️ You have both unified and specialized records")
                    addLog("⚠️ Consider standardizing on one approach")
                }
                
                // Count your submissions vs others
                yourSubmissions = allRecords.filter { record in
                    guard let submitterID = record["userID"] as? String else { return false }
                    return submitterID == userRecordID
                }.count
                
                otherUsersSubmissions = totalSubmissions - yourSubmissions
                
                // Extract unique users
                extractUniqueUsers(from: allRecords)
                
                // Convert records to simplified submissions for display
                recentSubmissions = allRecords
                    .sorted { 
                        let date1 = $0.creationDate ?? Date.distantPast
                        let date2 = $1.creationDate ?? Date.distantPast
                        return date1 > date2
                    }
                    .prefix(10)
                    .compactMap { record in
                        submissionFromRecord(record)
                    }
                
                addLog("Your posts: \(yourSubmissions)")
                addLog("Other users' posts: \(otherUsersSubmissions)")
                addLog("Unique users: \(uniqueUsers.count)")
            }
        } catch {
            await MainActor.run {
                addLog("❌ Error fetching submissions: \(error.localizedDescription)")
            }
        }
        
        isLoading = false
    }
    
    func checkDashboard() async {
        isLoading = true
        addLog("🌐 Checking CloudKit Dashboard records...")
        
        do {
            // Query all record types - CHECK LEGACY FIRST!
            let recordTypes = ["Submission", "FilmSubmission", "MusicSubmission", "ReelSubmission", 
                              "ProjectSubmission", "EventSubmission"]
            
            var totalFound = 0
            
            for recordType in recordTypes {
                let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
                
                let (matchResults, _) = try await database.records(matching: query)
                
                if !matchResults.isEmpty {
                    await MainActor.run {
                        let emoji = recordType == "Submission" ? "⚠️" : "📊"
                        addLog("\(emoji) \(recordType): \(matchResults.count) record(s)")
                        totalFound += matchResults.count
                        
                        for (recordID, result) in matchResults.prefix(3) {
                            switch result {
                            case .success(let record):
                                let title = getTitleFromRecord(record) ?? "Untitled"
                                let submitter = record["submittedBy"] as? String ?? "Unknown"
                                addLog("  • \(title) by \(submitter)")
                            case .failure(let error):
                                addLog("  ❌ Error: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
            
            await MainActor.run {
                if totalFound == 0 {
                    addLog("⚠️ NO RECORDS FOUND IN CLOUDKIT!")
                    addLog("This means:")
                    addLog("  1. Posts are being saved locally only")
                    addLog("  2. CloudKit save is failing silently")
                    addLog("  3. Wrong database or container")
                } else {
                    addLog("✅ Total records found: \(totalFound)")
                }
            }
        } catch {
            await MainActor.run {
                addLog("❌ Dashboard check failed: \(error.localizedDescription)")
            }
        }
        
        isLoading = false
    }
    
    private func fetchRecords(recordType: String) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let (matchResults, _) = try await database.records(matching: query)
        
        var records: [CKRecord] = []
        for (_, result) in matchResults {
            if let record = try? result.get() {
                records.append(record)
            }
        }
        
        return records
    }
    
    private func getTitleFromRecord(_ record: CKRecord) -> String? {
        // Different record types have different title field names
        if let title = record["filmTitle"] as? String { return title }
        if let title = record["musicTitle"] as? String { return title }
        if let title = record["reelTitle"] as? String { return title }
        if let title = record["projectTitle"] as? String { return title }
        if let title = record["eventTitle"] as? String { return title }
        if let title = record["title"] as? String { return title } // Legacy
        return nil
    }
    
    private func getTypeFromRecord(_ record: CKRecord) -> MediaType {
        switch record.recordType {
        case "FilmSubmission": return .film
        case "MusicSubmission": return .music
        case "ReelSubmission": return .reel
        case "ProjectSubmission": return .project
        case "EventSubmission": return .event
        default:
            // Try to get from type field (legacy)
            if let typeString = record["type"] as? String,
               let type = MediaType(rawValue: typeString) {
                return type
            }
            return .film // Default
        }
    }
    
    private func submissionFromRecord(_ record: CKRecord) -> Submission? {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        
        let type = getTypeFromRecord(record)
        let title = getTitleFromRecord(record) ?? "Untitled"
        let details = getDetailsFromRecord(record) ?? ""
        let isApproved = (record["isApproved"] as? Int) == 1
        let submittedBy = record["submittedBy"] as? String ?? "Anonymous"
        let createdDate = record.creationDate ?? Date()
        
        return Submission(
            id: id,
            type: type,
            title: title,
            details: details,
            isApproved: isApproved,
            submittedBy: submittedBy,
            createdDate: createdDate
        )
    }
    
    private func getDetailsFromRecord(_ record: CKRecord) -> String? {
        // Different record types have different description field names
        if let details = record["filmDescription"] as? String { return details }
        if let details = record["musicDescription"] as? String { return details }
        if let details = record["reelDescription"] as? String { return details }
        if let details = record["projectDescription"] as? String { return details }
        if let details = record["eventDescription"] as? String { return details }
        if let details = record["details"] as? String { return details } // Legacy
        return nil
    }
    
    private func extractUniqueUsers(from records: [CKRecord]) {
        var userMap: [String: (name: String, count: Int)] = [:]
        
        for record in records {
            let userID = record["userID"] as? String ?? "Unknown"
            let submitter = record["submittedBy"] as? String ?? "Anonymous"
            
            if let existing = userMap[userID] {
                userMap[userID] = (existing.name, existing.count + 1)
            } else {
                userMap[userID] = (submitter, 1)
            }
        }
        
        uniqueUsers = userMap.map { key, value in
            UserInfo(
                userRecordID: key,
                displayName: value.name,
                submissionCount: value.count,
                isCurrentUser: key == userRecordID
            )
        }.sorted { $0.submissionCount > $1.submissionCount }
    }
    
    func deleteAllRecords() async {
        isLoading = true
        addLog("🗑️ Deleting all CloudKit records...")
        
        do {
            // CHECK LEGACY RECORDS FIRST!
            let recordTypes = ["Submission", "FilmSubmission", "MusicSubmission", "ReelSubmission", 
                              "ProjectSubmission", "EventSubmission"]
            
            var totalDeleted = 0
            
            for recordType in recordTypes {
                let records = try await fetchRecords(recordType: recordType)
                
                for record in records {
                    do {
                        _ = try await database.deleteRecord(withID: record.recordID)
                        let title = getTitleFromRecord(record) ?? "Untitled"
                        addLog("Deleted: \(title)")
                        totalDeleted += 1
                    } catch {
                        let title = getTitleFromRecord(record) ?? "Untitled"
                        addLog("Failed to delete \(title): \(error.localizedDescription)")
                    }
                }
            }
            
            await MainActor.run {
                addLog("✅ Deletion complete. Deleted \(totalDeleted) record(s)")
            }
            
            await refresh()
        } catch {
            await MainActor.run {
                addLog("❌ Deletion failed: \(error.localizedDescription)")
            }
        }
        
        isLoading = false
    }
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.insert("[\(timestamp)] \(message)", at: 0)
        
        // Keep only last 50 logs
        if logs.count > 50 {
            logs = Array(logs.prefix(50))
        }
        
        // Also print to console
        print("📱 CloudKit Debugger: \(message)")
    }
}
