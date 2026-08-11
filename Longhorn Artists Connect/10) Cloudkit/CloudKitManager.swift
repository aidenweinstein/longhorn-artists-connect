//
//  CloudKitManager.swift
//  Longhorn Artists Connect
//
//  CloudKit manager supporting separate record types
//

import CloudKit
import SwiftUI
import Combine

/// CloudKit manager that handles Film, Music, Reel, Project, Event as separate record types
@MainActor
class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()
    
    private let container = CKContainer.default()
    
    // Use private database for user-specific data, or public for shared data
    private var database: CKDatabase {
        // Change this to .privateCloudDatabase if data should be private per user
        container.publicCloudDatabase
    }
    
    @Published var isAvailable = false
    @Published var userRecordID: CKRecord.ID?
    
    private init() {
        Task {
            await checkAvailability()
        }
    }
    
    /// Check if CloudKit is available and user is signed in
    func checkAvailability() async {
        do {
            let status = try await container.accountStatus()
            isAvailable = (status == .available)
            
            if isAvailable {
                userRecordID = try await container.userRecordID()
                print("✅ CloudKit ready. User ID: \(userRecordID?.recordName ?? "unknown")")
            }
        } catch {
            print("❌ CloudKit availability check failed: \(error)")
            isAvailable = false
        }
    }
    
    // MARK: - Generic Save/Delete
    
    /// Save a record to CloudKit.
    ///
    /// Uses a long-lived `CKModifyRecordsOperation` tuned for large asset uploads
    /// (extended timeouts, background-friendly) rather than the convenience
    /// `database.save`, which can time out on big video files over slow networks.
    /// A `.allKeys` save policy overwrites any existing record with the same ID, so
    /// edits and re-uploads work without a separate fetch-and-merge conflict step.
    /// Transient failures are retried automatically.
    func save(record: CKRecord) async throws {
        try await saveWithRetry(record: record, attemptsRemaining: 3)
    }

    private func saveWithRetry(record: CKRecord, attemptsRemaining: Int) async throws {
        do {
            try await performModify(record: record)
            print("✅ Saved record: \(record.recordType) - \(record.recordID.recordName)")
        } catch let error as CKError {
            if attemptsRemaining > 1, let retryAfter = Self.retryDelay(for: error) {
                print("⏳ Transient CloudKit error (\(error.code.rawValue)); retrying in \(retryAfter)s…")
                try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                try await saveWithRetry(record: record, attemptsRemaining: attemptsRemaining - 1)
                return
            }
            print("❌ SAVE FAILED for record: \(record.recordID.recordName)")
            print("❌ Error: \(error)")
            throw error
        }
    }

    /// Runs a single modify operation configured for large uploads.
    private func performModify(record: CKRecord) async throws {
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = .allKeys   // overwrite existing record with same ID
        operation.isAtomic = true

        let config = CKOperation.Configuration()
        config.qualityOfService = .utility
        config.isLongLived = true                       // survive app suspension
        config.timeoutIntervalForRequest = 300          // 5 min between packets
        config.timeoutIntervalForResource = 60 * 60 * 24 * 7  // up to 7 days for the whole transfer
        operation.configuration = config

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Report byte-level upload progress to the progress center. CloudKit
            // invokes this on a background queue, so hop to the main actor. The
            // record name is the submission's UUID; non-submission saves (e.g. user
            // profiles) are ignored by the center.
            operation.perRecordProgressBlock = { record, progress in
                let recordName = record.recordID.recordName
                Task { @MainActor in
                    UploadProgressCenter.shared.report(recordName: recordName, fraction: progress)
                }
            }
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    /// Seconds to wait before retrying a transient CloudKit error, or nil if the
    /// error isn't worth retrying.
    private static func retryDelay(for error: CKError) -> Double? {
        if let retryAfter = error.retryAfterSeconds { return retryAfter }
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy,
             .serverResponseLost:
            // `.serverResponseLost` is transient and common on large asset uploads
            // (the connection drops mid-transfer). The others are the usual network /
            // throttling hiccups. Non-transient errors (schema mismatch, asset write
            // failure, quota, etc.) return nil so we surface them instead of looping.
            return 3
        default:
            return nil
        }
    }
    
    /// Delete a record from CloudKit
    func delete(recordID: CKRecord.ID) async throws {
        _ = try await database.deleteRecord(withID: recordID)
        print("✅ Deleted record: \(recordID.recordName)")
    }

    // MARK: - Paginated Fetch

    /// Fetches EVERY record matching `query`, following CloudKit's pagination cursor
    /// until it's exhausted.
    ///
    /// `database.records(matching:)` only returns a single server-sized page and a
    /// cursor for the rest. Since these records carry video/audio/thumbnail assets,
    /// that first page can be small — so ignoring the cursor silently drops every
    /// record past it. The sync layer then misreads those missing records as
    /// server-side deletes and removes them locally, which is what makes posts
    /// appear/disappear and diverge between devices. Looping on the cursor here
    /// guarantees callers see the complete server state.
    private func fetchAllRecords(matching query: CKQuery) async throws -> [CKRecord] {
        var records: [CKRecord] = []

        var (matchResults, cursor) = try await database.records(matching: query)
        records.append(contentsOf: matchResults.compactMap { try? $0.1.get() })

        while let currentCursor = cursor {
            (matchResults, cursor) = try await database.records(continuingMatchFrom: currentCursor)
            records.append(contentsOf: matchResults.compactMap { try? $0.1.get() })
        }

        return records
    }

    // MARK: - Film Operations
    
    func saveFilm(_ film: Film) async throws {
        print("🔵 Saving Film: \(film.title)")
        let record = try await film.toCloudKitRecord(userRecordID: userRecordID)
        try await save(record: record)
    }
    
    func fetchAllFilms() async throws -> [Film] {
        let query = CKQuery(recordType: "FilmSubmission", predicate: NSPredicate(value: true))
        // Use CloudKit's built-in timestamp field (with three underscores)
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]

        let films = try await fetchAllRecords(matching: query).compactMap(Film.fromCloudKitRecord)

        print("✅ Fetched \(films.count) films")
        return films
    }
    
    func fetchApprovedFilms() async throws -> [Film] {
        let predicate = NSPredicate(format: "isApproved == 1")
        let query = CKQuery(recordType: "FilmSubmission", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let films = try await fetchAllRecords(matching: query).compactMap(Film.fromCloudKitRecord)

        print("✅ Fetched \(films.count) approved films")
        return films
    }
    
    func deleteFilm(_ film: Film) async throws {
        let recordID = CKRecord.ID(recordName: film.id.uuidString)
        try await delete(recordID: recordID)
    }
    
    // MARK: - Music Operations
    
    func saveMusic(_ music: Music) async throws {
        print("🔵 Saving Music: \(music.title)")
        let record = try await music.toCloudKitRecord(userRecordID: userRecordID)
        try await save(record: record)
    }
    
    func fetchAllMusic() async throws -> [Music] {
        let query = CKQuery(recordType: "MusicSubmission", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let musicItems = try await fetchAllRecords(matching: query).compactMap(Music.fromCloudKitRecord)

        print("✅ Fetched \(musicItems.count) music items")
        return musicItems
    }
    
    func fetchApprovedMusic() async throws -> [Music] {
        let predicate = NSPredicate(format: "isApproved == 1")
        let query = CKQuery(recordType: "MusicSubmission", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let musicItems = try await fetchAllRecords(matching: query).compactMap(Music.fromCloudKitRecord)

        print("✅ Fetched \(musicItems.count) approved music items")
        return musicItems
    }
    
    func deleteMusic(_ music: Music) async throws {
        let recordID = CKRecord.ID(recordName: music.id.uuidString)
        try await delete(recordID: recordID)
    }
    
    // MARK: - Reel Operations
    
    func saveReel(_ reel: Reel) async throws {
        print("🔵 Saving Reel: \(reel.title)")
        let record = try await reel.toCloudKitRecord(userRecordID: userRecordID)
        try await save(record: record)
    }
    
    func fetchAllReels() async throws -> [Reel] {
        let query = CKQuery(recordType: "ReelSubmission", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let reels = try await fetchAllRecords(matching: query).compactMap(Reel.fromCloudKitRecord)

        print("✅ Fetched \(reels.count) reels")
        return reels
    }
    
    func fetchApprovedReels() async throws -> [Reel] {
        let predicate = NSPredicate(format: "isApproved == 1")
        let query = CKQuery(recordType: "ReelSubmission", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let reels = try await fetchAllRecords(matching: query).compactMap(Reel.fromCloudKitRecord)

        print("✅ Fetched \(reels.count) approved reels")
        return reels
    }
    
    func deleteReel(_ reel: Reel) async throws {
        let recordID = CKRecord.ID(recordName: reel.id.uuidString)
        try await delete(recordID: recordID)
    }
    
    // MARK: - Project Operations
    
    func saveProject(_ project: Project) async throws {
        print("🔵 Saving Project: \(project.title)")
        let record = try await project.toCloudKitRecord(userRecordID: userRecordID)
        try await save(record: record)
    }
    
    func fetchAllProjects() async throws -> [Project] {
        let query = CKQuery(recordType: "ProjectSubmission", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let projects = try await fetchAllRecords(matching: query).compactMap(Project.fromCloudKitRecord)

        print("✅ Fetched \(projects.count) projects")
        return projects
    }
    
    func fetchApprovedProjects() async throws -> [Project] {
        let predicate = NSPredicate(format: "isApproved == 1")
        let query = CKQuery(recordType: "ProjectSubmission", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let projects = try await fetchAllRecords(matching: query).compactMap(Project.fromCloudKitRecord)

        print("✅ Fetched \(projects.count) approved projects")
        return projects
    }
    
    func deleteProject(_ project: Project) async throws {
        let recordID = CKRecord.ID(recordName: project.id.uuidString)
        try await delete(recordID: recordID)
    }
    
    // MARK: - Event Operations
    
    func saveEvent(_ event: Event) async throws {
        print("🔵 Saving Event: \(event.title)")
        let record = try await event.toCloudKitRecord(userRecordID: userRecordID)
        try await save(record: record)
    }
    
    func fetchAllEvents() async throws -> [Event] {
        let query = CKQuery(recordType: "EventSubmission", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let events = try await fetchAllRecords(matching: query).compactMap(Event.fromCloudKitRecord)

        print("✅ Fetched \(events.count) events")
        return events
    }
    
    func fetchApprovedEvents() async throws -> [Event] {
        let predicate = NSPredicate(format: "isApproved == 1")
        let query = CKQuery(recordType: "EventSubmission", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let events = try await fetchAllRecords(matching: query).compactMap(Event.fromCloudKitRecord)

        print("✅ Fetched \(events.count) approved events")
        return events
    }
    
    func deleteEvent(_ event: Event) async throws {
        let recordID = CKRecord.ID(recordName: event.id.uuidString)
        try await delete(recordID: recordID)
    }
    
    // MARK: - Fetch All Approved (Combined)
    
    /// Fetch all approved items across all types
    /// Returns them as a tuple that you can process individually
    func fetchAllApprovedItems() async throws -> (films: [Film], music: [Music], reels: [Reel], projects: [Project], events: [Event]) {
        async let films = fetchApprovedFilms()
        async let music = fetchApprovedMusic()
        async let reels = fetchApprovedReels()
        async let projects = fetchApprovedProjects()
        async let events = fetchApprovedEvents()
        
        return try await (films, music, reels, projects, events)
    }
    
    // MARK: - Generic Record Operations (Protocol Conformance)
    
    /// Fetch records of a specific type with optional sorting
    func fetchRecords(ofType recordType: String, sortBy sortKey: String?) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        if let sortKey = sortKey {
            query.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: false)]
        }
        
        let records = try await fetchAllRecords(matching: query)

        print("✅ Fetched \(records.count) records of type: \(recordType)")
        return records
    }
    
    /// Fetch records matching a predicate with optional sorting
    func fetchRecords(ofType recordType: String, matching predicate: NSPredicate, sortBy sortKey: String?) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: predicate)
        if let sortKey = sortKey {
            query.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: false)]
        }
        
        let records = try await fetchAllRecords(matching: query)

        print("✅ Fetched \(records.count) records of type: \(recordType) with predicate")
        return records
    }
    
    /// Fetch a single record by ID
    func fetchRecord(withID recordID: CKRecord.ID) async throws -> CKRecord {
        let record = try await database.record(for: recordID)
        print("✅ Fetched record: \(recordID.recordName)")
        return record
    }

    /// Checks whether a record with this ID currently exists in CloudKit.
    ///
    /// Used as a safety net during sync reconciliation: `syncedRecordIDs` is a local
    /// heuristic that can drift, so before re-uploading a post the app thinks is
    /// missing we verify against the server directly. The result distinguishes three
    /// cases so callers never resurrect a deleted post *or* silently drop a genuine
    /// offline-created one:
    ///   - `true`  → the record is on the server (our fetch just missed it).
    ///   - `false` → confirmed absent (`.unknownItem`): deleted or never uploaded.
    ///   - `nil`   → couldn't determine (network/other error); caller should wait.
    func recordExists(id: UUID) async -> Bool? {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        do {
            _ = try await database.record(for: recordID)
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return false
        } catch {
            print("⚠️ recordExists check inconclusive for \(id): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Submission Operations (Legacy Support)
    
    /// Save a submission (for backwards compatibility)
    func saveSubmission(_ submission: Submission) async throws {
        print("🔵 Saving legacy Submission: \(submission.title)")
        let record = try submission.toCloudKitRecord(userRecordID: userRecordID)
        try await save(record: record)
    }
    
    /// Fetch all approved submissions (legacy)
    func fetchAllApprovedSubmissions() async throws -> [Submission] {
        let predicate = NSPredicate(format: "isApproved == 1")
        let query = CKQuery(recordType: "Submission", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let submissions = try await fetchAllRecords(matching: query).compactMap(Submission.fromCloudKitRecord)

        print("✅ Fetched \(submissions.count) approved submissions")
        return submissions
    }
    
    /// Fetch all submissions (legacy)
    func fetchAllSubmissions() async throws -> [Submission] {
        let query = CKQuery(recordType: "Submission", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let submissions = try await fetchAllRecords(matching: query).compactMap(Submission.fromCloudKitRecord)

        print("✅ Fetched \(submissions.count) total submissions")
        return submissions
    }
    
    /// Update submission approval status (legacy)
    func updateSubmissionApproval(submissionId: String, isApproved: Bool) async throws {
        let recordID = CKRecord.ID(recordName: submissionId)
        let record = try await fetchRecord(withID: recordID)
        record["isApproved"] = isApproved ? 1 : 0
        try await save(record: record)
        print("✅ Updated approval status for: \(submissionId)")
    }
    
    /// Delete a submission (legacy)
    func deleteSubmission(_ submission: Submission) async throws {
        let recordID = CKRecord.ID(recordName: submission.id.uuidString)
        try await delete(recordID: recordID)
    }
    
    // MARK: - Subscriptions
    
    /// Subscribe to all media types for real-time updates
    func setupAutomaticSync() async {
        do {
            try await subscribeToRecordType("FilmSubmission", subscriptionID: "film-changes")
            try await subscribeToRecordType("MusicSubmission", subscriptionID: "music-changes")
            try await subscribeToRecordType("ReelSubmission", subscriptionID: "reel-changes")
            try await subscribeToRecordType("ProjectSubmission", subscriptionID: "project-changes")
            try await subscribeToRecordType("EventSubmission", subscriptionID: "event-changes")
            print("✅ Automatic sync enabled for all media types")
        } catch {
            print("❌ Failed to setup automatic sync: \(error)")
        }
    }
    
    func subscribeToRecordType(_ recordType: String, subscriptionID: String) async throws {
        // Check if subscription already exists
        do {
            _ = try await database.subscription(for: subscriptionID)
            print("ℹ️ Subscription already exists: \(subscriptionID)")
            return
        } catch {
            print("📝 Creating new subscription: \(subscriptionID)")
        }
        
        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        notificationInfo.alertBody = "New \(recordType.lowercased()) available"
        notificationInfo.soundName = "default"
        subscription.notificationInfo = notificationInfo
        
        _ = try await database.save(subscription)
        print("✅ Subscribed to \(recordType) changes")
    }
}
