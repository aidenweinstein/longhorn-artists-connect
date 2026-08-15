import Combine
import SwiftUI
import CloudKit

// MARK: - MediaType Definition

enum MediaType: String, Codable, CaseIterable, Identifiable {
    case reel = "Reel"
    case project = "Project"
    case event = "Event"
    case film = "Film"
    case music = "Music"
    
    var id: String { rawValue }
}

// MARK: - Helper Structs

// Helper struct for ordered entries
struct OrderedEntry: Codable, Equatable, Identifiable {
    let id: UUID
    var role: String
    var name: String
    /// CloudKit record name of the credited person's profile, when they were
    /// picked from the directory. `nil` for free-typed names. Lets a credit link
    /// to the exact person even if two people share a name.
    var profileID: String?

    init(id: UUID = UUID(), role: String = "", name: String = "", profileID: String? = nil) {
        self.id = id
        self.role = role
        self.name = name
        self.profileID = profileID
    }
}

// Collection for saving posts
struct PostCollection: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var submissionIds: [UUID]
    let createdAt: Date
    var isSystemCollection: Bool // For "Liked" collection
    
    init(id: UUID = UUID(), name: String, submissionIds: [UUID] = [], createdAt: Date = Date(), isSystemCollection: Bool = false) {
        self.id = id
        self.name = name
        self.submissionIds = submissionIds
        self.createdAt = createdAt
        self.isSystemCollection = isSystemCollection
    }
}

// History entry for tracking edits and approvals
struct HistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let action: HistoryAction
    let timestamp: Date
    let submissionId: UUID
    let submissionTitle: String
    let submissionType: MediaType
    let performedBy: String
    
    init(id: UUID = UUID(), action: HistoryAction, timestamp: Date = Date(), submissionId: UUID, submissionTitle: String, submissionType: MediaType, performedBy: String) {
        self.id = id
        self.action = action
        self.timestamp = timestamp
        self.submissionId = submissionId
        self.submissionTitle = submissionTitle
        self.submissionType = submissionType
        self.performedBy = performedBy
    }
}

enum HistoryAction: String, Codable {
    case submitted = "Submitted"
    case approved = "Approved"
    case edited = "Edited"
    case denied = "Denied"
    case deleted = "Deleted"
}

struct Submission: Identifiable, Equatable, Codable {
    let id: UUID
    let type: MediaType
    var title: String
    var details: String
    var isApproved: Bool = false
    var submittedBy: String = ""
    var createdDate: Date = Date()
    var lastEditedDate: Date?
    
    // Parsed fields for display
    var logline: String = ""
    var ageRating: String = ""
    var genres: [String] = []
    var cast: [String: String] = [:]
    var crew: [String: String] = [:]
    
    // Ordered arrays to preserve input order
    var orderedCast: [OrderedEntry] = []
    var orderedCrew: [OrderedEntry] = []
    
    var explicit: Bool = false
    
    // Media file names (not full URLs to survive app reinstalls)
    var videoFileName: String?
    var audioFileName: String?
    var thumbnailData: Data?
    var scriptFileName: String?
    
    // Event-specific fields
    var eventStartDate: Date?
    var eventEndDate: Date?
    var eventLocation: String?
    var eventHost: String = ""
    var eventTicketsURL: String?
    
    // Project-specific fields
    var shootDates: String = ""
    var expectedReleaseDate: String = ""
    var castNeeded: [String] = []
    var crewNeeded: [String] = []
    
    // Film-specific fields
    var studio: String = ""
    
    // Music-specific fields
    var artist: String = "" // Artist name for music submissions
    var musicians: String = ""
    var writers: String = ""
    var mixers: String = ""
    
    // Music credits - ordered arrays
    var orderedRecording: [OrderedEntry] = [] // Recording credits (musicians, vocalists, etc.)
    var orderedProduction: [OrderedEntry] = [] // Production credits (producers, engineers, mixers, etc.)
    
    // Music streaming links
    var spotifyLink: String = ""
    var appleMusicLink: String = ""
    var amazonMusicLink: String = ""
    var youtubeMusicLink: String = ""
    var soundcloudLink: String = ""
    
    // Talent Reel-specific fields
    var reelType: String = ""
    var reelDescription: String = ""
    var reelExperience: String = ""
    var reelSpecificSkills: String = ""
    
    // MARK: - Initializer
    
    init(
        id: UUID,
        type: MediaType,
        title: String,
        details: String,
        isApproved: Bool = false,
        submittedBy: String = "",
        createdDate: Date = Date(),
        lastEditedDate: Date? = nil,
        logline: String = "",
        ageRating: String = "",
        genres: [String] = [],
        cast: [String: String] = [:],
        crew: [String: String] = [:],
        orderedCast: [OrderedEntry] = [],
        orderedCrew: [OrderedEntry] = [],
        explicit: Bool = false,
        videoFileName: String? = nil,
        audioFileName: String? = nil,
        thumbnailData: Data? = nil,
        scriptFileName: String? = nil,
        eventStartDate: Date? = nil,
        eventEndDate: Date? = nil,
        eventLocation: String? = nil,
        eventHost: String = "",
        eventTicketsURL: String? = nil,
        shootDates: String = "",
        expectedReleaseDate: String = "",
        castNeeded: [String] = [],
        crewNeeded: [String] = [],
        studio: String = "",
        artist: String = "",
        musicians: String = "",
        writers: String = "",
        mixers: String = "",
        orderedRecording: [OrderedEntry] = [],
        orderedProduction: [OrderedEntry] = [],
        spotifyLink: String = "",
        appleMusicLink: String = "",
        amazonMusicLink: String = "",
        youtubeMusicLink: String = "",
        soundcloudLink: String = "",
        reelType: String = "",
        reelDescription: String = "",
        reelExperience: String = "",
        reelSpecificSkills: String = ""
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.details = details
        self.isApproved = isApproved
        self.submittedBy = submittedBy
        self.createdDate = createdDate
        self.lastEditedDate = lastEditedDate
        self.logline = logline
        self.ageRating = ageRating
        self.genres = genres
        self.cast = cast
        self.crew = crew
        self.orderedCast = orderedCast
        self.orderedCrew = orderedCrew
        self.explicit = explicit
        self.videoFileName = videoFileName
        self.audioFileName = audioFileName
        self.thumbnailData = thumbnailData
        self.scriptFileName = scriptFileName
        self.eventStartDate = eventStartDate
        self.eventEndDate = eventEndDate
        self.eventLocation = eventLocation
        self.eventHost = eventHost
        self.eventTicketsURL = eventTicketsURL
        self.shootDates = shootDates
        self.expectedReleaseDate = expectedReleaseDate
        self.castNeeded = castNeeded
        self.crewNeeded = crewNeeded
        self.studio = studio
        self.artist = artist
        self.musicians = musicians
        self.writers = writers
        self.mixers = mixers
        self.orderedRecording = orderedRecording
        self.orderedProduction = orderedProduction
        self.spotifyLink = spotifyLink
        self.appleMusicLink = appleMusicLink
        self.amazonMusicLink = amazonMusicLink
        self.youtubeMusicLink = youtubeMusicLink
        self.soundcloudLink = soundcloudLink
        self.reelType = reelType
        self.reelDescription = reelDescription
        self.reelExperience = reelExperience
        self.reelSpecificSkills = reelSpecificSkills
    }
    
    // Computed property to get the actual video URL
    var videoURL: URL? {
        guard let videoFileName = videoFileName else { return nil }
        guard let documentsDir = FileManager.default.documentsDirectory else { return nil }
        let url = documentsDir.appendingPathComponent(videoFileName)
        
        // Verify the file actually exists
        guard FileManager.default.fileExistsAndIsAccessible(at: url) else {
            print("⚠️ Video file not found: \(videoFileName)")
            return nil
        }
        
        return url
    }
    
    // Computed property to get the actual audio URL
    var audioURL: URL? {
        guard let audioFileName = audioFileName else { return nil }
        guard let documentsDir = FileManager.default.documentsDirectory else { return nil }
        let url = documentsDir.appendingPathComponent(audioFileName)
        
        // Verify the file actually exists
        guard FileManager.default.fileExistsAndIsAccessible(at: url) else {
            print("⚠️ Audio file not found: \(audioFileName)")
            return nil
        }
        
        return url
    }
    
    // Computed property to get the actual script URL
    var scriptURL: URL? {
        guard let scriptFileName = scriptFileName else { return nil }
        guard let documentsDir = FileManager.default.documentsDirectory else { return nil }
        let url = documentsDir.appendingPathComponent(scriptFileName)
        
        // Verify the file actually exists
        guard FileManager.default.fileExistsAndIsAccessible(at: url) else {
            print("⚠️ Script file not found: \(scriptFileName)")
            return nil
        }
        
        return url
    }
    
    // MARK: - CloudKit Conversion
    
    func toCloudKitRecord(userRecordID: CKRecord.ID?) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: "Submission", recordID: recordID)
        
        // Basic fields
        record["title"] = title as CKRecordValue
        record["details"] = details as CKRecordValue
        record["type"] = type.rawValue as CKRecordValue
        record["isApproved"] = (isApproved ? 1 : 0) as CKRecordValue
        record["submittedBy"] = submittedBy as CKRecordValue
        record["createdDate"] = createdDate as CKRecordValue
        
        if let lastEditedDate = lastEditedDate {
            record["lastEditedDate"] = lastEditedDate as CKRecordValue
        }
        
        if let userID = userRecordID?.recordName {
            record["userID"] = userID as CKRecordValue
        }
        
        // Type-specific fields
        record["logline"] = logline as CKRecordValue
        record["ageRating"] = ageRating as CKRecordValue
        record["studio"] = studio as CKRecordValue
        record["artist"] = artist as CKRecordValue
        record["explicit"] = (explicit ? 1 : 0) as CKRecordValue
        
        // Talent Reel fields
        record["reelType"] = reelType as CKRecordValue
        record["reelDescription"] = reelDescription as CKRecordValue
        record["reelExperience"] = reelExperience as CKRecordValue
        record["reelSpecificSkills"] = reelSpecificSkills as CKRecordValue
        
        if !genres.isEmpty {
            record["genres"] = genres as CKRecordValue
        }
        
        // Event fields
        if let eventStartDate = eventStartDate {
            record["eventStartDate"] = eventStartDate as CKRecordValue
        }
        if let eventEndDate = eventEndDate {
            record["eventEndDate"] = eventEndDate as CKRecordValue
        }
        if let eventLocation = eventLocation {
            record["eventLocation"] = eventLocation as CKRecordValue
        }
        record["eventHost"] = eventHost as CKRecordValue
        if let eventTicketsURL = eventTicketsURL {
            record["eventTicketsURL"] = eventTicketsURL as CKRecordValue
        }
        
        // Project fields
        record["shootDates"] = shootDates as CKRecordValue
        record["expectedReleaseDate"] = expectedReleaseDate as CKRecordValue
        if !castNeeded.isEmpty {
            record["castNeeded"] = castNeeded as CKRecordValue
        }
        if !crewNeeded.isEmpty {
            record["crewNeeded"] = crewNeeded as CKRecordValue
        }
        
        // Thumbnail
        if let thumbnailData = thumbnailData {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(id.uuidString + "_thumbnail.jpg")
            try thumbnailData.write(to: tempURL)
            let asset = CKAsset(fileURL: tempURL)
            record["thumbnail"] = asset
        }
        
        return record
    }
    
    static func fromCloudKitRecord(_ record: CKRecord) -> Submission? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let typeString = record["type"] as? String,
              let type = MediaType(rawValue: typeString) else {
            return nil
        }
        
        let title = (record["title"] as? String) ?? "Untitled"
        let details = (record["details"] as? String) ?? ""
        
        var submission = Submission(id: id, type: type, title: title, details: details)
        
        submission.isApproved = ((record["isApproved"] as? Int) ?? 0) == 1
        submission.submittedBy = (record["submittedBy"] as? String) ?? "Anonymous"
        submission.createdDate = (record["createdDate"] as? Date) ?? Date()
        submission.lastEditedDate = record["lastEditedDate"] as? Date
        
        // Type-specific fields
        submission.logline = (record["logline"] as? String) ?? ""
        submission.ageRating = (record["ageRating"] as? String) ?? ""
        submission.studio = (record["studio"] as? String) ?? ""
        submission.artist = (record["artist"] as? String) ?? ""
        submission.explicit = ((record["explicit"] as? Int) ?? 0) == 1
        
        // Talent Reel fields
        submission.reelType = (record["reelType"] as? String) ?? ""
        submission.reelDescription = (record["reelDescription"] as? String) ?? ""
        submission.reelExperience = (record["reelExperience"] as? String) ?? ""
        submission.reelSpecificSkills = (record["reelSpecificSkills"] as? String) ?? ""
        
        if let genres = record["genres"] as? [String] {
            submission.genres = genres
        }
        
        // Event fields
        submission.eventStartDate = record["eventStartDate"] as? Date
        submission.eventEndDate = record["eventEndDate"] as? Date
        submission.eventLocation = record["eventLocation"] as? String
        submission.eventHost = (record["eventHost"] as? String) ?? ""
        submission.eventTicketsURL = record["eventTicketsURL"] as? String
        
        // Project fields
        submission.shootDates = (record["shootDates"] as? String) ?? ""
        submission.expectedReleaseDate = (record["expectedReleaseDate"] as? String) ?? ""
        if let castNeeded = record["castNeeded"] as? [String] {
            submission.castNeeded = castNeeded
        }
        if let crewNeeded = record["crewNeeded"] as? [String] {
            submission.crewNeeded = crewNeeded
        }
        
        // Thumbnail
        if let asset = record["thumbnail"] as? CKAsset,
           let fileURL = asset.fileURL,
           let data = try? Data(contentsOf: fileURL) {
            submission.thumbnailData = data
        }
        
        return submission
    }
}

// MARK: - FileManager Extension

extension FileManager {
    var documentsDirectory: URL? {
        // This returns the app's Documents directory which persists across app updates
        // Note: In development, reinstalling the app creates a new container, so files will be lost
        // In production/TestFlight, files persist correctly across app updates
        urls(for: .documentDirectory, in: .userDomainMask).first
    }
    
    /// Check if a file exists and is accessible
    func fileExistsAndIsAccessible(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }
}

@MainActor
class SubmissionStore_3_2: ObservableObject {
    static let shared = SubmissionStore_3_2()
    // Use CloudKitTransitionAdapter to properly save videos/audio
    private let cloudKitAdapter = CloudKitTransitionAdapter.shared
    // MARK: - Published Properties

    @Published var submissions: [Submission] = []
    @Published var approvedSubmissions: [Submission] = []

    // Locally-saved drafts (never uploaded to CloudKit or shown in feeds)
    @Published var drafts: [Submission] = []
    
    // Shared properties
    @Published var history: [HistoryEntry] = []
    @Published var collections: [PostCollection] = []
    @Published var likedSubmissionIds: Set<UUID> = []
    // Not @Published on purpose: playback positions are read imperatively during
    // player setup and never observed by any view. Publishing them caused a crash
    // when savePlaybackPosition() mutated the dict during SwiftUI view teardown
    // (dismantleUIViewController → objectWillChange re-entered GraphHost.invalidate).
    var videoPlaybackPositions: [UUID: Double] = [:]

    /// Record IDs that have been confirmed present in CloudKit at least once
    /// (either fetched back or successfully uploaded). Lets sync tell apart a post
    /// that's "created locally and still uploading" (keep) from one that "existed
    /// in CloudKit and was deleted there" (remove locally). Persisted, not published.
    private var syncedRecordIDs: Set<UUID> = []

    /// IDs of posts whose upload to CloudKit hasn't been confirmed yet. Added the
    /// moment a post is created (`add`) and removed once a save succeeds. Drives the
    /// feed's "hide until uploaded" behavior (`visibleApprovedSubmissions`). Persisted
    /// so a post shown mid-upload stays hidden across a relaunch.
    @Published private var pendingUploadIDs: Set<UUID> = []

    /// IDs of posts created (or explicitly retried) *in this app session* that still
    /// need uploading. This is deliberately **in-memory only**: it's the sole signal
    /// that authorizes re-uploading a post CloudKit doesn't have. CloudKit is the
    /// master copy, so on a fresh launch/build this set is empty and any locally-cached
    /// post the server doesn't have is dropped rather than resurrected — a post deleted
    /// from CloudKit stays deleted, instead of a stale local copy re-uploading itself
    /// forever. Genuine offline/failed uploads are still retried within the session
    /// that created them.
    private var sessionUploadIDs: Set<UUID> = []

    /// Approved posts that are safe to show in the browse feeds: everything whose
    /// CloudKit upload has confirmed. A post is withheld while it's still uploading
    /// (its ID is in `pendingUploadIDs`) so a half-uploaded post never appears on the
    /// main pages — the Home upload banner surfaces its progress in the meantime.
    var visibleApprovedSubmissions: [Submission] {
        approvedSubmissions.filter { !pendingUploadIDs.contains($0.id) }
    }

    /// IDs of posts the user has soft-deleted in the app. They're hidden from the
    /// Home and Discover feeds but kept in the moderator "Deleted" section. This is
    /// a local, persisted list so hiding works even for posts this account can't
    /// modify/delete in CloudKit (public-DB records are only writable by their
    /// creator) — the feeds always respect it regardless of the cloud state.
    private var hiddenSubmissionIDs: Set<UUID> = []
    
    // MARK: - Beta Testing Support
    // Key prefix to support migration from beta to production
    private let keyPrefix: String
    private static let betaModeKey = "isBetaMode"
    
    private init() {
        // Determine if this is a beta build
        let isBeta = UserDefaults.standard.bool(forKey: Self.betaModeKey)
        self.keyPrefix = isBeta ? "beta_" : ""
        
        // Load data asynchronously for better performance
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.loadAllData()

            // 🌐 Sync with CloudKit after loading local data
            await self?.syncWithCloudKit()
            
            // 🔔 Setup automatic sync for real-time updates
            await self?.setupAutomaticSync()
        }
        
        ensureLikedCollectionExists()
    }
    
    // MARK: - Beta Migration Support
    /// Call this when transitioning from beta to production
    static func migrateBetaToProduction() {
        let defaults = UserDefaults.standard
        
        // Copy all beta data to production keys
        let betaKeys = [
            "beta_pendingSubmissions",
            "beta_approvedSubmissions",
            "beta_moderationHistory",
            "beta_postCollections",
            "beta_likedSubmissions",
            "beta_videoPlaybackPositions"
        ]
        
        for key in betaKeys {
            if let data = defaults.data(forKey: key) {
                let prodKey = key.replacingOccurrences(of: "beta_", with: "")
                defaults.set(data, forKey: prodKey)
            }
        }
        
        // Also migrate user profile data
        let profileKeys = [
            "userFirstName", "userLastName", "userMajor", "userMinor",
            "userCertificate", "userGraduationYear", "userType",
            "profileImagePath", "hasCompletedOnboarding"
        ]
        
        // Profile data doesn't need beta prefix as it's user-specific
        // Just ensure it persists (it already does via UserDefaults)
        
        // Mark as no longer in beta mode
        defaults.set(false, forKey: betaModeKey)
        defaults.synchronize()
    }
    
    /// Enable beta mode (typically set at build configuration)
    static func enableBetaMode() {
        UserDefaults.standard.set(true, forKey: betaModeKey)
    }
    
    // MARK: - Async Data Loading
    private func loadAllData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadSubmissionsAsync() }
            group.addTask { await self.loadDraftsAsync() }
            group.addTask { await self.loadHistoryAsync() }
            group.addTask { await self.loadCollectionsAsync() }
            group.addTask { await self.loadLikedSubmissionsAsync() }
            group.addTask { await self.loadVideoPlaybackPositionsAsync() }
            group.addTask { await self.loadSyncedRecordIDsAsync() }
            group.addTask { await self.loadHiddenSubmissionIDsAsync() }
            group.addTask { await self.loadPendingUploadIDsAsync() }
        }
    }

    private func loadPendingUploadIDsAsync() async {
        let key = "\(keyPrefix)pendingUploadIDs"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            await MainActor.run {
                self.pendingUploadIDs = Set(decoded)
            }
        }
    }

    private func loadHiddenSubmissionIDsAsync() async {
        let key = "\(keyPrefix)hiddenSubmissionIDs"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            await MainActor.run {
                self.hiddenSubmissionIDs = Set(decoded)
            }
        }
    }

    private func loadSyncedRecordIDsAsync() async {
        let key = "\(keyPrefix)syncedRecordIDs"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            await MainActor.run {
                self.syncedRecordIDs = Set(decoded)
            }
            return
        }

        // First launch on a build with this tracking: seed the set from the posts
        // already cached locally. Those all originated from CloudKit, so treating
        // them as "previously synced" lets the next sync clean up any that were
        // already deleted server-side (instead of resurrecting them).
        var seeded = Set<UUID>()
        for cacheKey in ["\(keyPrefix)pendingSubmissions", "\(keyPrefix)approvedSubmissions"] {
            if let data = UserDefaults.standard.data(forKey: cacheKey),
               let decoded = try? JSONDecoder().decode([Submission].self, from: data) {
                seeded.formUnion(decoded.map { $0.id })
            }
        }
        await MainActor.run {
            self.syncedRecordIDs = seeded
        }
        saveSyncedRecordIDs()
    }
    
    private func loadSubmissionsAsync() async {
        let pendingKey = "\(keyPrefix)pendingSubmissions"
        let approvedKey = "\(keyPrefix)approvedSubmissions"
        
        if let data = UserDefaults.standard.data(forKey: pendingKey),
           let decoded = try? JSONDecoder().decode([Submission].self, from: data) {
            await MainActor.run {
                // Drop legacy placeholder posts that an early build persisted locally.
                self.submissions = decoded.filter { !$0.isPlaceholder }
            }
        }

        if let data = UserDefaults.standard.data(forKey: approvedKey),
           let decoded = try? JSONDecoder().decode([Submission].self, from: data) {
            await MainActor.run {
                self.approvedSubmissions = decoded.filter { !$0.isPlaceholder }
            }
        }
    }
    
    private func loadDraftsAsync() async {
        let key = "\(keyPrefix)drafts"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Submission].self, from: data) {
            await MainActor.run {
                self.drafts = decoded
            }
        }
    }

    private func loadHistoryAsync() async {
        let key = "\(keyPrefix)moderationHistory"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            await MainActor.run {
                self.history = decoded
            }
        }
    }
    
    private func loadCollectionsAsync() async {
        let key = "\(keyPrefix)postCollections"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([PostCollection].self, from: data) {
            await MainActor.run {
                self.collections = decoded
            }
        }
    }
    
    private func loadLikedSubmissionsAsync() async {
        let key = "\(keyPrefix)likedSubmissions"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            await MainActor.run {
                self.likedSubmissionIds = Set(decoded)
            }
        }
    }
    
    private func loadVideoPlaybackPositionsAsync() async {
        let key = "\(keyPrefix)videoPlaybackPositions"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UUID: Double].self, from: data) {
            await MainActor.run {
                self.videoPlaybackPositions = decoded
            }
        }
    }
    
    /// Adds a submission. Returns `nil` on success, or a user-facing error message
    /// explaining why it was rejected (so the UI can show it instead of a false success).
    @discardableResult
    func add(_ submission: Submission) -> String? {
        print("📝 ===== STARTING NEW SUBMISSION =====")
        print("📝 Title: \(submission.title)")
        print("📝 Type: \(submission.type.rawValue)")
        print("📝 ID: \(submission.id.uuidString)")
        print("📝 Submitted by: \(submission.submittedBy)")
        
        // 🔒 SECURITY: Rate limit check
        let userID = CloudKitManager.shared.userRecordID?.recordName ?? ""
        guard SecurityManager.shared.checkWriteRateLimit(userID: userID) else {
            print("❌ RATE LIMIT: Too many submissions. Please wait before submitting again.")
            SecurityManager.shared.logSecurityEvent(
                .rateLimitExceeded,
                userID: userID,
                details: ["action": "submission", "type": submission.type.rawValue]
            )
            return "You're posting too quickly. Please wait a moment and try again."
        }

        // 🔒 SECURITY: Input validation
        let validationResult = SecurityManager.shared.validateSubmission(
            title: submission.title,
            details: submission.details,
            type: submission.type,
            additionalFields: [
                "ageRating": submission.ageRating,
                "artist": submission.artist,
                "eventStartDate": submission.eventStartDate as Any,
                "eventLocation": submission.eventLocation as Any,
                "shootDates": submission.shootDates,
                "reelType": submission.reelType
            ]
        )
        
        guard validationResult.isValid else {
            print("❌ VALIDATION FAILED: \(validationResult.errors.joined(separator: ", "))")
            SecurityManager.shared.logSecurityEvent(
                .invalidInput,
                userID: userID,
                details: ["errors": validationResult.errors, "type": submission.type.rawValue]
            )
            return "Your post couldn't be posted: \(validationResult.errors.joined(separator: ", "))."
        }
        
        // 🔒 SECURITY: File validation
        if let videoURL = submission.videoURL {
            let fileValidation = SecurityManager.shared.validateFileUpload(
                url: videoURL,
                allowedExtensions: SecurityConstants.AllowedExtensions.video,
                maxSizeBytes: SecurityConstants.FileSizeLimits.video
            )
            
            guard fileValidation.isValid else {
                print("❌ VIDEO VALIDATION FAILED: \(fileValidation.error ?? "Unknown error")")
                SecurityManager.shared.logSecurityEvent(
                    .fileUploadRejected,
                    userID: userID,
                    details: ["error": fileValidation.error ?? "unknown", "type": "video"]
                )
                return fileValidation.error ?? "The video couldn't be uploaded."
            }
        }
        
        if let audioURL = submission.audioURL {
            let fileValidation = SecurityManager.shared.validateFileUpload(
                url: audioURL,
                allowedExtensions: SecurityConstants.AllowedExtensions.audio,
                maxSizeBytes: SecurityConstants.FileSizeLimits.audio
            )
            
            guard fileValidation.isValid else {
                print("❌ AUDIO VALIDATION FAILED: \(fileValidation.error ?? "Unknown error")")
                SecurityManager.shared.logSecurityEvent(
                    .fileUploadRejected,
                    userID: userID,
                    details: ["error": fileValidation.error ?? "unknown", "type": "audio"]
                )
                return fileValidation.error ?? "The audio couldn't be uploaded."
            }
        }
        
        // 🔍 DIAGNOSTIC: Check for duplicate IDs
        if approvedSubmissions.contains(where: { $0.id == submission.id }) {
            print("⚠️⚠️⚠️ WARNING: Duplicate ID detected!")
            print("⚠️⚠️⚠️ This submission ID already exists in approvedSubmissions!")
            print("⚠️⚠️⚠️ This will cause CloudKit to OVERWRITE the old post!")
            print("⚠️⚠️⚠️ Existing posts with this ID:")
            for existing in approvedSubmissions.filter({ $0.id == submission.id }) {
                print("⚠️⚠️⚠️   - \(existing.title) (created: \(existing.createdDate))")
            }
        }
        
        // Auto-approve all submissions
        var approvedSubmission = submission
        approvedSubmission.isApproved = true // Ensure it's marked as approved
        approvedSubmissions.append(approvedSubmission)
        
        print("✅ Added to local approvedSubmissions array (count: \(approvedSubmissions.count))")
        print("✅ All submission IDs in array:")
        for sub in approvedSubmissions.suffix(5) {  // Show last 5
            print("   - \(sub.title): \(sub.id.uuidString)")
        }
        
        // Add history entry
        let entry = HistoryEntry(
            action: HistoryAction.submitted,
            submissionId: approvedSubmission.id,
            submissionTitle: approvedSubmission.title,
            submissionType: approvedSubmission.type,
            performedBy: approvedSubmission.submittedBy
        )
        history.append(entry)
        
        print("📋 Added history entry")
        
        saveSubmissions()
        saveHistory()
        
        print("💾 Saved to local storage")

        // Mark as awaiting upload. This survives app relaunch, so if the upload never
        // confirms (offline, crash, etc.) the next sync knows to retry it rather than
        // mistaking its absence from CloudKit for a server-side deletion. Cleared once
        // the save is confirmed in `saveSubmissionToCloudKit`.
        pendingUploadIDs.insert(approvedSubmission.id)
        savePendingUploadIDs()
        // Authorize re-upload retries for this post, but only for the current session —
        // so it's never resurrected on a later launch if it ends up absent from CloudKit.
        sessionUploadIDs.insert(approvedSubmission.id)

        // 🌐 Save to CloudKit for sharing with all users, tracking progress so the
        // submission form can show a live upload wheel → checkmark.
        Task {
            print("🌐 Starting CloudKit upload task...")
            await saveSubmissionToCloudKit(approvedSubmission, trackProgress: true)
        }

        return nil // success
    }

    // MARK: - Drafts

    /// Save (or update) a draft locally. Drafts are kept only on-device and are
    /// never uploaded to CloudKit or surfaced in any feed.
    func saveDraft(_ submission: Submission) {
        var draft = submission
        draft.isApproved = false
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index] = draft
        } else {
            drafts.append(draft)
        }
        saveDrafts()
    }

    func deleteDraft(_ submission: Submission) {
        drafts.removeAll { $0.id == submission.id }
        saveDrafts()
    }

    private func saveDrafts() {
        let key = "\(keyPrefix)drafts"
        let draftsToSave = drafts

        Task.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(draftsToSave) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }

    func approve(_ submission: Submission) {
        if let index = submissions.firstIndex(where: { $0.id == submission.id }) {
            var approvedSubmission = submissions.remove(at: index)
            approvedSubmission.isApproved = true
            approvedSubmissions.append(approvedSubmission)
            
            // Add history entry
            let entry = HistoryEntry(
                action: HistoryAction.approved,
                submissionId: approvedSubmission.id,
                submissionTitle: approvedSubmission.title,
                submissionType: approvedSubmission.type,
                performedBy: "Moderator"
            )
            history.append(entry)
            
            saveSubmissions()
            saveHistory()
            
            // 🌐 Update in CloudKit
            Task {
                await saveSubmissionToCloudKit(approvedSubmission)
            }
        }
    }
    
    func deny(_ submission: Submission) {
        submissions.removeAll { $0.id == submission.id }
        
        // Add history entry
        let entry = HistoryEntry(
            action: HistoryAction.denied,
            submissionId: submission.id,
            submissionTitle: submission.title,
            submissionType: submission.type,
            performedBy: "Moderator"
        )
        history.append(entry)
        
        saveSubmissions()
        saveHistory()
    }
    
    /// Soft-deletes a post: it's hidden from the Home and Discover feeds but kept
    /// in the moderator "Deleted" section (and can be restored). Uses a persisted
    /// local `hiddenSubmissionIDs` list so it works even for posts this account
    /// can't modify in CloudKit — those simply stay hidden on this device.
    func delete(_ submission: Submission) {
        hiddenSubmissionIDs.insert(submission.id)

        // Move it out of the feeds and into the deleted bucket.
        approvedSubmissions.removeAll { $0.id == submission.id }
        var hidden = submission
        hidden.isApproved = false
        if let index = submissions.firstIndex(where: { $0.id == submission.id }) {
            submissions[index] = hidden
        } else {
            submissions.append(hidden)
        }

        // Add history entry
        let entry = HistoryEntry(
            action: HistoryAction.deleted,
            submissionId: submission.id,
            submissionTitle: submission.title,
            submissionType: submission.type,
            performedBy: submission.submittedBy
        )
        history.append(entry)

        saveSubmissions()
        saveHistory()
        saveHiddenSubmissionIDs()

        // Propagate the hide to CloudKit so the post disappears for everyone, not just
        // this device. We re-save the record with `isApproved = false` (the same
        // mechanism as `softDelete`) instead of deleting it, so it stays recoverable
        // via `restore`. `hiddenSubmissionIDs` still tracks it locally as a fallback:
        // if this account can't modify the record in CloudKit (e.g. another user
        // created it) the save fails harmlessly and the post simply stays hidden here.
        Task {
            await saveSubmissionToCloudKit(hidden)
        }
    }
    
    // MARK: - Soft Delete (Moderation)

    /// Posts a moderator has hidden. They stay in CloudKit as non-approved so they
    /// remain hidden for every user, but are still visible in the moderator's
    /// "Deleted Posts" page. (The app auto-approves on submit, so the non-approved
    /// bucket is used exclusively for moderator-hidden posts.)
    var deletedSubmissions: [Submission] { submissions }

    /// Hides a post from all users WITHOUT removing it from CloudKit. The hidden
    /// state syncs via the existing `isApproved` field, so it disappears from every
    /// user's feed on their next sync.
    func softDelete(_ submission: Submission) {
        guard let index = approvedSubmissions.firstIndex(where: { $0.id == submission.id }) else { return }
        var hidden = approvedSubmissions.remove(at: index)
        hidden.isApproved = false
        if !submissions.contains(where: { $0.id == hidden.id }) {
            submissions.append(hidden)
        }

        // Record the hide locally so it survives even if the CloudKit write below never
        // sticks (the record belongs to another account, or the save errors). Without
        // this, the next sync sees the server copy still approved and repopulates it.
        hiddenSubmissionIDs.insert(submission.id)

        let entry = HistoryEntry(
            action: HistoryAction.deleted,
            submissionId: hidden.id,
            submissionTitle: hidden.title,
            submissionType: hidden.type,
            performedBy: "Moderator"
        )
        history.append(entry)

        saveSubmissions()
        saveHistory()
        saveHiddenSubmissionIDs()

        // Sync the hidden state so the post disappears for everyone.
        Task {
            await saveSubmissionToCloudKit(hidden)
        }
    }

    /// Restores a hidden post so users can see it again.
    func restore(_ submission: Submission) {
        hiddenSubmissionIDs.remove(submission.id)
        saveHiddenSubmissionIDs()

        submissions.removeAll { $0.id == submission.id }
        var restored = submission
        restored.isApproved = true
        if !approvedSubmissions.contains(where: { $0.id == restored.id }) {
            approvedSubmissions.append(restored)
        }

        let entry = HistoryEntry(
            action: HistoryAction.approved,
            submissionId: restored.id,
            submissionTitle: restored.title,
            submissionType: restored.type,
            performedBy: "Moderator"
        )
        history.append(entry)

        saveSubmissions()
        saveHistory()

        Task {
            await saveSubmissionToCloudKit(restored)
        }
    }

    /// Permanently removes a post from local storage AND CloudKit (irreversible).
    func permanentlyDelete(_ submission: Submission) {
        submissions.removeAll { $0.id == submission.id }
        approvedSubmissions.removeAll { $0.id == submission.id }

        // Keep it in the hidden set for now. We only clear that safety net once CloudKit
        // confirms the record is gone — otherwise a delete that can't go through (the
        // record belongs to another account, or CloudKit is offline) would let the next
        // sync pull the still-approved server copy right back into the feed.
        hiddenSubmissionIDs.insert(submission.id)
        // Don't let the session's re-upload path resurrect it either.
        sessionUploadIDs.remove(submission.id)

        let entry = HistoryEntry(
            action: HistoryAction.deleted,
            submissionId: submission.id,
            submissionTitle: submission.title,
            submissionType: submission.type,
            performedBy: "Moderator"
        )
        history.append(entry)

        saveSubmissions()
        saveHistory()
        saveHiddenSubmissionIDs()

        Task {
            let deleted = await deleteSubmissionFromCloudKit(submission)
            if deleted {
                // Server copy is gone, so the local hide flag is no longer needed.
                hiddenSubmissionIDs.remove(submission.id)
                syncedRecordIDs.remove(submission.id)
                saveHiddenSubmissionIDs()
                saveSyncedRecordIDs()
            }
        }
    }

    func update(_ updatedSubmission: Submission) {
        // Update in approved submissions
        if let index = approvedSubmissions.firstIndex(where: { $0.id == updatedSubmission.id }) {
            var updated = updatedSubmission
            updated.lastEditedDate = Date()
            approvedSubmissions[index] = updated
            
            // Add history entry
            let entry = HistoryEntry(
                action: HistoryAction.edited,
                submissionId: updated.id,
                submissionTitle: updated.title,
                submissionType: updated.type,
                performedBy: updated.submittedBy
            )
            history.append(entry)
            
            saveSubmissions()
            saveHistory()
            
            // 🌐 Update in CloudKit
            Task {
                await saveSubmissionToCloudKit(updated)
            }
        }
    }
    
    // MARK: - Persistence (Optimized with batching)
    
    private func saveSubmissions() {
        let pendingKey = "\(keyPrefix)pendingSubmissions"
        let approvedKey = "\(keyPrefix)approvedSubmissions"
        let submissionsToSave = submissions
        let approvedToSave = approvedSubmissions
        
        Task.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(submissionsToSave) {
                UserDefaults.standard.set(encoded, forKey: pendingKey)
            }
            if let encoded = try? JSONEncoder().encode(approvedToSave) {
                UserDefaults.standard.set(encoded, forKey: approvedKey)
            }
        }
    }
    
    /// Persist the set of record IDs known to exist in CloudKit.
    private func saveSyncedRecordIDs() {
        let key = "\(keyPrefix)syncedRecordIDs"
        let idsToSave = Array(syncedRecordIDs)
        Task.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(idsToSave) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }

    /// Persist the set of locally-created posts still awaiting a confirmed upload.
    private func savePendingUploadIDs() {
        let key = "\(keyPrefix)pendingUploadIDs"
        let idsToSave = Array(pendingUploadIDs)
        Task.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(idsToSave) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }

    /// Persist the set of soft-deleted (hidden) submission IDs.
    private func saveHiddenSubmissionIDs() {
        let key = "\(keyPrefix)hiddenSubmissionIDs"
        let idsToSave = Array(hiddenSubmissionIDs)
        Task.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(idsToSave) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }

    private func saveHistory() {
        let key = "\(keyPrefix)moderationHistory"
        let historyToSave = history
        
        Task.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(historyToSave) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }
    
    // MARK: - Collections Management
    
    private func ensureLikedCollectionExists() {
        // Check if "Liked" collection exists
        if !collections.contains(where: { $0.isSystemCollection && $0.name == "Liked" }) {
            let likedCollection = PostCollection(name: "Liked", isSystemCollection: true)
            collections.insert(likedCollection, at: 0)
            saveCollections()
        }
    }
    
    func toggleLike(for submission: Submission) {
        if likedSubmissionIds.contains(submission.id) {
            likedSubmissionIds.remove(submission.id)
            removeFromCollection(submissionId: submission.id, collectionName: "Liked")
        } else {
            likedSubmissionIds.insert(submission.id)
            addToCollection(submissionId: submission.id, collectionName: "Liked")
        }
        saveLikedSubmissions()
    }
    
    func isLiked(_ submission: Submission) -> Bool {
        likedSubmissionIds.contains(submission.id)
    }
    
    func createCollection(name: String) -> PostCollection {
        let collection = PostCollection(name: name)
        collections.append(collection)
        saveCollections()
        return collection
    }
    
    func deleteCollection(_ collection: PostCollection) {
        guard !collection.isSystemCollection else { return }
        collections.removeAll { $0.id == collection.id }
        saveCollections()
    }
    
    func addToCollection(submissionId: UUID, collectionId: UUID) {
        if let index = collections.firstIndex(where: { $0.id == collectionId }) {
            if !collections[index].submissionIds.contains(submissionId) {
                collections[index].submissionIds.append(submissionId)
                saveCollections()
            }
        }
    }
    
    func addToCollection(submissionId: UUID, collectionName: String) {
        if let index = collections.firstIndex(where: { $0.name == collectionName }) {
            if !collections[index].submissionIds.contains(submissionId) {
                collections[index].submissionIds.append(submissionId)
                saveCollections()
            }
        }
    }
    
    func removeFromCollection(submissionId: UUID, collectionId: UUID) {
        if let index = collections.firstIndex(where: { $0.id == collectionId }) {
            collections[index].submissionIds.removeAll { $0 == submissionId }
            saveCollections()
        }
    }
    
    func removeFromCollection(submissionId: UUID, collectionName: String) {
        if let index = collections.firstIndex(where: { $0.name == collectionName }) {
            collections[index].submissionIds.removeAll { $0 == submissionId }
            saveCollections()
        }
    }
    
    func getSubmissions(for collection: PostCollection) -> [Submission] {
        return approvedSubmissions.filter { collection.submissionIds.contains($0.id) }
    }
    
    func isInAnyCollection(_ submission: Submission) -> Bool {
        return collections.contains { $0.submissionIds.contains(submission.id) && !$0.isSystemCollection }
    }
    
    private func saveCollections() {
        let key = "\(keyPrefix)postCollections"
        let collectionsToSave = collections
        
        Task.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(collectionsToSave) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }
    
    private func saveLikedSubmissions() {
        let key = "\(keyPrefix)likedSubmissions"
        let likedArray = Array(likedSubmissionIds)
        
        Task.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(likedArray) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }
    
    // MARK: - Video Playback Position Management
    
    func savePlaybackPosition(for submissionId: UUID, position: Double) {
        videoPlaybackPositions[submissionId] = position
        // Debounce saves - only save every 5 seconds
        Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await self?.saveVideoPlaybackPositions()
        }
    }
    
    func getPlaybackPosition(for submissionId: UUID) -> Double? {
        return videoPlaybackPositions[submissionId]
    }
    
    nonisolated private func saveVideoPlaybackPositions() async {
        let key = "\(keyPrefix)videoPlaybackPositions"
        let positions = await videoPlaybackPositions
        if let encoded = try? JSONEncoder().encode(positions) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    // MARK: - CloudKit Integration
    
    /// Sync submissions from CloudKit (fetch all posts)
    ///
    /// **Architecture Note:**
    /// This app uses a UNIFIED approach with a single "Submission" CloudKit record type
    /// that handles all content types (Film, Music, Reel, Project, Event) via a `type` field.
    ///
    /// **Why unified instead of specialized?**
    /// - Simpler data model with single source of truth
    /// - All submissions have consistent fields and behavior
    /// - Easier to implement cross-type features (search, sorting, collections)
    /// - Type-specific fields are handled via optional properties
    ///
    /// **Alternative approach:**
    /// CloudKitManager also supports specialized record types (FilmSubmission, MusicSubmission, etc.)
    /// but this is NOT currently used. If you need type-specific indexes or queries in the future,
    /// you can migrate to specialized types using the helper methods in CloudKitManager.
    ///
    @MainActor
    func syncWithCloudKit() async {
        // 🔒 SECURITY: Rate limit check for sync operations
        let userID = CloudKitManager.shared.userRecordID?.recordName ?? ""
        guard SecurityManager.shared.checkReadRateLimit(userID: userID) else {
            print("⚠️ RATE LIMIT: Too many sync requests. Please wait.")
            return
        }
        
        // Check availability
        await cloudKitAdapter.checkAvailability()
        
        guard cloudKitAdapter.isAvailable else {
            print("⚠️ CloudKit not available - skipping sync")
            return
        }
        
        print("🔄 Starting CloudKit sync...")
        print("🔄 Local state before sync:")
        print("   - Pending: \(submissions.count)")
        print("   - Approved: \(approvedSubmissions.count)")
        
        do {
            // Fetch ALL submissions using CloudKitTransitionAdapter.
            // Ignore legacy placeholder posts so they never reappear or get re-uploaded,
            // regardless of whether they still linger in the public database.
            let cloudSubmissions = try await cloudKitAdapter.fetchAllSubmissions()
                .filter { !$0.isPlaceholder }

            print("📥 Fetched \(cloudSubmissions.count) submissions from CloudKit")
            if cloudSubmissions.isEmpty {
                print("⚠️⚠️⚠️ WARNING: CloudKit returned ZERO submissions!")
                print("⚠️⚠️⚠️ This means:")
                print("⚠️⚠️⚠️ 1. Records were deleted from CloudKit Dashboard, or")
                print("⚠️⚠️⚠️ 2. CloudKit query is not finding records, or")
                print("⚠️⚠️⚠️ 3. Schema field names don't match")
            }
            
            await MainActor.run {
                // Create a set to track which posts CloudKit currently has.
                let cloudSubmissionIDs = Set(cloudSubmissions.map { $0.id })

                // Everything CloudKit returned is now known-synced.
                syncedRecordIDs.formUnion(cloudSubmissionIDs)

                // Separate pending and approved submissions
                var updatedPending: [Submission] = []
                var updatedApproved: [Submission] = []
                
                // Add/update CloudKit submissions
                for cloudSubmission in cloudSubmissions {
                    // Locally soft-deleted posts stay hidden from the feeds even if the
                    // CloudKit copy is still approved (e.g. we couldn't write the hidden
                    // state because another account created it). Keep them in the
                    // deleted bucket so the moderator page can still show/restore them.
                    if hiddenSubmissionIDs.contains(cloudSubmission.id) {
                        var hidden = cloudSubmission
                        hidden.isApproved = false
                        if !updatedPending.contains(where: { $0.id == hidden.id }) {
                            updatedPending.append(hidden)
                        }
                        continue
                    }

                    if cloudSubmission.isApproved {
                        // Check if we already have this approved submission
                        if let existingIndex = updatedApproved.firstIndex(where: { $0.id == cloudSubmission.id }) {
                            print("🔄 Updating existing approved submission: \(cloudSubmission.title)")
                            updatedApproved[existingIndex] = cloudSubmission
                        } else {
                            print("📥 Adding new approved submission from CloudKit: \(cloudSubmission.title)")
                            updatedApproved.append(cloudSubmission)
                        }
                    } else {
                        // Check if we already have this pending submission
                        if let existingIndex = updatedPending.firstIndex(where: { $0.id == cloudSubmission.id }) {
                            print("🔄 Updating existing pending submission: \(cloudSubmission.title)")
                            updatedPending[existingIndex] = cloudSubmission
                        } else {
                            print("📥 Adding new pending submission from CloudKit: \(cloudSubmission.title)")
                            updatedPending.append(cloudSubmission)
                        }
                    }
                }
                
                // Reconcile local submissions that aren't in this fetch.
                //
                // A single fetch is NOT authoritative about what's been deleted: the
                // feed query pulls full video/audio assets, and a transient asset
                // download failure (or CloudKit's index lag right after a write, e.g.
                // just after deleting a post) silently drops otherwise-present records
                // from the result. Trusting that to declare a server-side delete is
                // exactly what made whole feeds vanish and then reappear on the next
                // sync. So for ANY locally-cached post missing from the fetch, we keep
                // it for now and verify it per-record with a lightweight `recordExists`
                // lookup (see `reconcileMissingLocalSubmission`), which is immune to the
                // query/asset issues above. Genuine deletes still stick — they just get
                // confirmed one cycle later instead of guessed.
                print("🔍 Reconciling local-only submissions...")
                for localSubmission in submissions {
                    if !cloudSubmissionIDs.contains(localSubmission.id) {
                        // Soft-deleted posts are kept locally (moderator "Deleted"
                        // section) and never re-uploaded, so a deletion can't resurrect.
                        if hiddenSubmissionIDs.contains(localSubmission.id) {
                            if !updatedPending.contains(where: { $0.id == localSubmission.id }) {
                                updatedPending.append(localSubmission)
                            }
                        } else {
                            updatedPending.append(localSubmission)
                            Task { await reconcileMissingLocalSubmission(localSubmission) }
                        }
                    }
                }

                for localApproved in approvedSubmissions {
                    if !cloudSubmissionIDs.contains(localApproved.id) {
                        // A soft-deleted post should never sit in the approved feed.
                        if hiddenSubmissionIDs.contains(localApproved.id) {
                            continue
                        } else {
                            updatedApproved.append(localApproved)
                            Task { await reconcileMissingLocalSubmission(localApproved) }
                        }
                    }
                }

                submissions = updatedPending
                approvedSubmissions = updatedApproved
                saveSubmissions()
                saveSyncedRecordIDs()
                
                print("✅ CloudKit sync complete!")
                print("   - Pending: \(submissions.count)")
                print("   - Approved: \(approvedSubmissions.count)")
                print("   - Total: \(submissions.count + approvedSubmissions.count)")
            }
        } catch {
            print("❌ CloudKit sync failed: \(error.localizedDescription)")
            print("❌ Full error: \(error)")
            print("⚠️  Local data preserved, will retry on next sync")
        }
    }

    /// Decides what to do with a locally-cached post that the CloudKit fetch didn't
    /// return and that `syncedRecordIDs` has no record of syncing.
    ///
    /// Instead of blindly re-uploading (which resurrects records deleted straight from
    /// the CloudKit Dashboard) we ask the server directly, then decide:
    ///   - present → it exists after all; record it as synced, no re-upload.
    ///   - absent + created/retried THIS session → a post we're actively trying to
    ///     upload that never finished (e.g. made offline); upload it.
    ///   - absent + not from this session → CloudKit is the master copy and doesn't
    ///     have it, so drop it locally. This covers a post deleted from CloudKit *and* a
    ///     stale local copy left over from a past session/build: neither is resurrected.
    ///   - unknown → couldn't reach CloudKit; leave it alone and let the next sync decide.
    @MainActor
    private func reconcileMissingLocalSubmission(_ submission: Submission) async {
        switch await cloudKitAdapter.recordExists(id: submission.id) {
        case .some(true):
            print("🔎 '\(submission.title)' already exists in CloudKit — marking synced, skipping re-upload")
            syncedRecordIDs.insert(submission.id)
            saveSyncedRecordIDs()
            if pendingUploadIDs.remove(submission.id) != nil {
                savePendingUploadIDs()
            }
        case .some(false):
            if sessionUploadIDs.contains(submission.id) {
                print("⚠️  Pending-upload submission confirmed absent, uploading: \(submission.title)")
                await saveSubmissionToCloudKit(submission)
            } else {
                print("🗑️  '\(submission.title)' is absent from CloudKit (deleted server-side or a stale local copy) — removing locally; CloudKit is the master copy")
                removeSubmissionLocally(submission.id)
            }
        case .none:
            print("⏳ Couldn't confirm '\(submission.title)' in CloudKit — leaving for next sync")
        }
    }

    /// Removes a submission from every local store and clears its tracking state.
    /// Used when reconciliation determines a post was deleted server-side.
    @MainActor
    private func removeSubmissionLocally(_ id: UUID) {
        submissions.removeAll { $0.id == id }
        approvedSubmissions.removeAll { $0.id == id }
        syncedRecordIDs.remove(id)
        sessionUploadIDs.remove(id)
        if pendingUploadIDs.remove(id) != nil {
            savePendingUploadIDs()
        }
        saveSubmissions()
        saveSyncedRecordIDs()
    }


    /// Save a submission to CloudKit.
    ///
    /// Pass `trackProgress: true` for interactive posts so the submission form can
    /// show a live upload wheel → checkmark (or an error + Retry). Background saves
    /// (approve/restore/hide/sync) leave it `false` and stay invisible.
    @MainActor
    func saveSubmissionToCloudKit(_ submission: Submission, trackProgress: Bool = false) async {
        if trackProgress {
            UploadProgressCenter.shared.begin(submission.id, title: submission.title, type: submission.type)
        }
        print("🌐 ========================================")
        print("🌐 CLOUDKIT SAVE DIAGNOSTICS")
        print("🌐 ========================================")
        print("🌐 Submission Title: \(submission.title)")
        print("🌐 Submission ID: \(submission.id)")
        print("🌐 Submission Type: \(submission.type.rawValue)")
        print("🌐 Is Approved: \(submission.isApproved)")
        print("🌐 Submitted By: \(submission.submittedBy)")
        print("🌐 Video File Name: \(submission.videoFileName ?? "none")")
        print("🌐 Audio File Name: \(submission.audioFileName ?? "none")")
        print("🌐 CloudKit Available: \(cloudKitAdapter.isAvailable)")
        
        guard cloudKitAdapter.isAvailable else {
            print("❌ ========================================")
            print("❌ CLOUDKIT NOT AVAILABLE")
            print("❌ ========================================")
            print("❌ Submission saved LOCALLY ONLY")
            print("❌ Other users will NOT see this post")
            print("❌ ")
            print("❌ Possible reasons:")
            print("❌ 1. Not signed into iCloud")
            print("❌    → Go to Settings > [Your Name] > iCloud")
            print("❌ 2. No internet connection")
            print("❌    → Check your network connection")
            print("❌ 3. CloudKit container not configured")
            print("❌    → Check Xcode project settings")
            print("❌ 4. CloudKit permissions not granted")
            print("❌    → Check app permissions in Settings")
            print("❌ ========================================")
            if trackProgress {
                UploadProgressCenter.shared.fail(submission.id, "iCloud isn't available. Make sure you're signed into iCloud and connected to the internet, then try again.")
            }
            return
        }

        print("✅ CloudKit is available, proceeding with save...")
        print("🚀 Calling cloudKitAdapter.saveSubmission()...")
        print("🎬 This will convert to typed model (\(submission.type.rawValue)) and upload media assets")
        
        do {
            try await cloudKitAdapter.saveSubmission(submission)
            // Confirmed in CloudKit — so if it later disappears from a fetch, we know
            // it was deleted server-side (not just still-uploading) and can remove it.
            syncedRecordIDs.insert(submission.id)
            saveSyncedRecordIDs()
            // Upload confirmed, so it's no longer awaiting one. (On failure we leave it
            // in the set so the current session retries instead of dropping it.)
            sessionUploadIDs.remove(submission.id)
            if pendingUploadIDs.remove(submission.id) != nil {
                savePendingUploadIDs()
            }
            if trackProgress {
                UploadProgressCenter.shared.finish(submission.id)
            }
            print("✅ ========================================")
            print("✅ CLOUDKIT SAVE SUCCESSFUL")
            print("✅ ========================================")
            print("✅ Submission: \(submission.title)")
            print("✅ Saved to CloudKit successfully")
            print("✅ Video/Audio assets uploaded")
            print("✅ Other users should now see this post")
            print("✅ ========================================")
        } catch {
            print("❌ ========================================")
            print("❌ CLOUDKIT SAVE FAILED")
            print("❌ ========================================")
            print("❌ Submission: \(submission.title)")
            print("❌ Error Type: \(type(of: error))")
            print("❌ Error Description: \(error.localizedDescription)")
            print("❌ Full Error: \(error)")
            print("❌ ")
            print("❌ Common causes:")
            print("❌ 1. Schema not created in CloudKit Dashboard")
            print("❌ 2. Missing required fields")
            print("❌ 3. Network connectivity issues")
            print("❌ 4. CloudKit quota exceeded")
            print("❌ 5. Video file too large (>250MB)")
            print("❌ ")
            print("❌ Action: Submission saved locally")
            print("❌ Will retry on next sync")
            print("❌ ========================================")
            if trackProgress {
                UploadProgressCenter.shared.fail(submission.id, "\(error.localizedDescription) Your post was saved on this device — tap Retry to upload it.")
            }
            // Submission is still saved locally, will retry on next sync
        }
    }

    /// Re-runs the CloudKit upload for a submission that failed mid-post, keeping the
    /// progress indicator live. The submission is already saved locally by `add`.
    @MainActor
    func retryUpload(_ submission: Submission) {
        // Flip the tracked state back to "uploading" immediately so the UI reacts
        // before the async save starts reporting progress.
        UploadProgressCenter.shared.begin(submission.id, title: submission.title, type: submission.type)
        // An explicit retry re-authorizes this post for upload in the current session.
        pendingUploadIDs.insert(submission.id)
        savePendingUploadIDs()
        sessionUploadIDs.insert(submission.id)
        Task {
            await saveSubmissionToCloudKit(submission, trackProgress: true)
        }
    }

    /// Retries a failed upload by submission ID (used by the Home-feed banner, which
    /// only knows the ID). No-op if the submission isn't found locally.
    @MainActor
    func retryUpload(id: UUID) {
        guard let submission = approvedSubmissions.first(where: { $0.id == id }) else { return }
        retryUpload(submission)
    }

    /// Delete a submission from CloudKit. Returns `true` if the record was removed
    /// server-side, `false` if CloudKit was unavailable or the delete failed (e.g. the
    /// record belongs to another account and can't be deleted from here).
    @MainActor
    @discardableResult
    func deleteSubmissionFromCloudKit(_ submission: Submission) async -> Bool {
        guard cloudKitAdapter.isAvailable else {
            print("⚠️ CloudKit not available")
            return false
        }

        do {
            try await cloudKitAdapter.deleteSubmission(submission)
            print("✅ Deleted submission from CloudKit: \(submission.title)")
            return true
        } catch {
            print("❌ Failed to delete from CloudKit: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Force a manual sync - useful for debugging or refresh actions
    @MainActor
    func forceSyncWithCloudKit() async {
        print("🔄 Force sync triggered by user")
        await syncWithCloudKit()
    }

    /// Purges the legacy placeholder posts from local storage and CloudKit.
    ///
    /// The app already filters these out on load/sync, but this actively deletes the
    /// records from the public database (best-effort — a record can only be deleted
    /// by the iCloud account that created it) so they're gone for everyone.
    /// Returns the number of records successfully deleted from CloudKit.
    @MainActor
    @discardableResult
    func removePlaceholderPosts() async -> Int {
        // Remove locally and persist so they disappear immediately.
        submissions.removeAll { $0.isPlaceholder }
        approvedSubmissions.removeAll { $0.isPlaceholder }
        saveSubmissions()

        // Delete each known placeholder record from CloudKit by its fixed ID.
        var deleted = 0
        for id in Submission.placeholderIDs {
            let recordID = CKRecord.ID(recordName: id.uuidString)
            do {
                try await CloudKitManager.shared.delete(recordID: recordID)
                deleted += 1
                print("✅ Purged placeholder \(id.uuidString) from CloudKit")
            } catch {
                print("⚠️ Could not purge placeholder \(id.uuidString): \(error.localizedDescription)")
            }
        }
        return deleted
    }
    
    /// Setup automatic background sync
    @MainActor
    private func setupAutomaticSync() async {
        await CloudKitManager.shared.setupAutomaticSync()
    }
    
    /// Called when receiving CloudKit notifications
    @MainActor
    func handleCloudKitNotification() async {
        print("🔔 CloudKit notification received - syncing...")
        await syncWithCloudKit()
    }
}

