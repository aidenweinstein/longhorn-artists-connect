//
//  CreativeProfileStore.swift
//  Longhorn Artists Connect
//
//  The extra profile details your tags unlock (see CreativeGroup.swift) — an actor's
//  Actors Access sheet and headshot, a musician's streaming links, a filmmaker's
//  specialties — in CloudKit, plus the signed-in user's own copy and audition list.
//
//  One public-database record type (create it in CloudKit Dashboard, in BOTH
//  environments, then deploy — see the schema table in CloudKitRecordTypes.swift):
//
//  • `CreativeProfile` — one per person, written only by that person.
//      record name  "CreativeProfile_<userRecordID>"
//      details      STRING   JSON of `CreativeDetails`
//      headshot     ASSET    actors' headshot (optional)
//      updatedAt    DATE/TIME
//
//  Fetched with a match-all query, so it needs a QUERYABLE index on `recordName`
//  (same as the other types here).
//
//  Which sections a profile shows is decided by the person's role tags (on their
//  `UserProfile`), not by anything here. Auditions are kept on this device only.
//

import SwiftUI
import CloudKit
import UIKit
import Combine

// MARK: - Auditions

enum AuditionStatus: String, Codable, CaseIterable, Identifiable {
    case submitted = "Submitted"
    case callback = "Callback"
    case booked = "Booked"
    case notSelected = "Not selected"

    var id: String { rawValue }
}

/// A role the actor auditioned for.
struct AuditionEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var projectID: UUID
    var projectTitle: String
    var role: String
    var date: Date = Date()
    var status: AuditionStatus = .submitted
}

// MARK: - Store

@MainActor
final class CreativeProfileStore: ObservableObject {
    static let shared = CreativeProfileStore()

    static let profileRecordType = "CreativeProfile"

    // MARK: Mine

    @Published private(set) var myDetails = CreativeDetails()
    @Published private(set) var myHeadshot: UIImage?
    @Published private(set) var auditions: [AuditionEntry] = []
    /// Set while saving to CloudKit, so the editor can show progress.
    @Published private(set) var isSaving = false

    // MARK: Everyone

    /// Every synced profile, keyed by raw user record name.
    @Published private(set) var profiles: [String: CreativeProfile] = [:]
    @Published private(set) var isLoading = false
    /// Last CloudKit problem.
    @Published var lastError: String?

    private var lastFetch: Date?

    private let defaults = UserDefaults.standard
    private var detailsKey: String { "creativeDetails" }
    private var auditionsKey: String { "\(CloudKitEnvironmentDetector.localCachePrefix)auditions" }

    private init() {
        if let json = defaults.string(forKey: detailsKey) {
            myDetails = CreativeDetails.decode(json)
        }
        if let data = try? Data(contentsOf: Self.myHeadshotURL) {
            myHeadshot = UIImage(data: data)
        }
        if let data = defaults.data(forKey: auditionsKey),
           let saved = try? JSONDecoder().decode([AuditionEntry].self, from: data) {
            auditions = saved
        }
    }

    // MARK: - Identity

    /// The signed-in user's raw iCloud record name.
    static var myUserID: String? {
        CloudKitManager.shared.userRecordID?.recordName
            ?? UserDefaults.standard.string(forKey: ModeratorAccess.currentUserRecordNameKey)
    }

    /// Strips `UserProfile_` / `CreativeProfile_` so any form of the ID compares equal.
    static func rawUserID(_ id: String?) -> String? {
        guard var id = id?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { return nil }
        for prefix in ["UserProfile_", "CreativeProfile_"] where id.hasPrefix(prefix) {
            id = String(id.dropFirst(prefix.count))
        }
        return id
    }

    private static var myHeadshotURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("creativeHeadshot.jpg")
    }

    // MARK: - Editing my details

    /// Whether the signed-in user has typed anything (or picked a headshot), so there's
    /// something worth uploading.
    var hasMyDetails: Bool {
        myHeadshot != nil || myDetails != CreativeDetails()
    }

    /// Saves the user's details on this device right away, then uploads them.
    func update(details: CreativeDetails, headshot: UIImage?) {
        myDetails = details
        defaults.set(details.jsonString, forKey: detailsKey)

        if let headshot {
            let resized = Self.downscaled(headshot, maxSide: 1400)
            myHeadshot = resized
            if let data = resized.jpegData(compressionQuality: 0.85) {
                try? data.write(to: Self.myHeadshotURL)
            }
        } else {
            myHeadshot = nil
            try? FileManager.default.removeItem(at: Self.myHeadshotURL)
        }

        Task { await saveMine() }
    }

    /// Forgets the signed-in user's details, headshot and auditions on this device
    /// (logout / reset). Their CloudKit record is left for account deletion.
    func clearMine() {
        myDetails = CreativeDetails()
        myHeadshot = nil
        auditions = []
        defaults.removeObject(forKey: detailsKey)
        defaults.removeObject(forKey: auditionsKey)
        try? FileManager.default.removeItem(at: Self.myHeadshotURL)
    }

    /// Uploads the user's `CreativeProfile`. Safe to call repeatedly.
    func saveMine() async {
        guard CloudKitManager.shared.isAvailable, let userID = Self.myUserID else {
            print("⚠️ Profile details saved on this device only — CloudKit isn't available")
            return
        }

        isSaving = true
        defer { isSaving = false }

        let record = CKRecord(recordType: Self.profileRecordType,
                              recordID: CKRecord.ID(recordName: "CreativeProfile_\(userID)"))
        record["details"] = myDetails.jsonString as CKRecordValue
        let now = Date()
        record["updatedAt"] = now as CKRecordValue
        if myHeadshot != nil, FileManager.default.fileExists(atPath: Self.myHeadshotURL.path) {
            record["headshot"] = CKAsset(fileURL: Self.myHeadshotURL)
        } else {
            // Clears a headshot the user removed.
            record["headshot"] = nil
        }

        do {
            try await CloudKitManager.shared.save(record: record)
            profiles[userID] = CreativeProfile(userID: userID, details: myDetails,
                                               headshotFileURL: myHeadshot == nil ? nil : Self.myHeadshotURL,
                                               updatedAt: now)
            print("✅ Saved profile details")
        } catch {
            lastError = "Couldn't save your profile details: \(error.localizedDescription)"
            print("❌ \(lastError ?? "")")
        }
    }

    // MARK: - Reading everyone's details

    /// Fetches every `CreativeProfile`. Throttled to once every two minutes unless forced.
    func refresh(force: Bool = false) async {
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < 120 { return }
        guard CloudKitManager.shared.isAvailable else { return }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }
        let database = CKContainer.default().publicCloudDatabase

        do {
            let records = try await Self.fetchAll(recordType: Self.profileRecordType, in: database)
            var map: [String: CreativeProfile] = [:]
            for record in records {
                if let profile = Self.parseProfile(record) { map[profile.userID] = profile }
            }
            profiles = map
            lastError = nil

            // Details saved before iCloud was ready, or on a bad connection, may never
            // have reached CloudKit. Push them now.
            if hasMyDetails, let me = Self.myUserID, map[me] == nil {
                await saveMine()
            }
        } catch {
            lastError = "Couldn't load profile details: \(error.localizedDescription)"
            print("⚠️ \(lastError ?? "")")
        }
        lastFetch = Date()
    }

    private static func fetchAll(recordType: String, in database: CKDatabase) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        var records: [CKRecord] = []
        var response = try await database.records(matching: query)
        while true {
            for (_, result) in response.matchResults {
                if case .success(let record) = result { records.append(record) }
            }
            guard let cursor = response.queryCursor else { break }
            response = try await database.records(continuingMatchFrom: cursor)
        }
        return records
    }

    private static func parseProfile(_ record: CKRecord) -> CreativeProfile? {
        guard let userID = rawUserID(record.recordID.recordName) else { return nil }

        // CloudKit's downloaded asset file can be purged, so keep our own copy.
        var headshotURL: URL?
        if let asset = record["headshot"] as? CKAsset, let source = asset.fileURL,
           let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let target = caches.appendingPathComponent("creativeHeadshot_\(userID).jpg")
            try? FileManager.default.removeItem(at: target)
            if (try? FileManager.default.copyItem(at: source, to: target)) != nil {
                headshotURL = target
            }
        }

        return CreativeProfile(
            userID: userID,
            details: CreativeDetails.decode(record["details"] as? String),
            headshotFileURL: headshotURL,
            updatedAt: (record["updatedAt"] as? Date) ?? record.modificationDate ?? .distantPast
        )
    }

    // MARK: - Lookups

    /// A person's details by any form of their directory ID. For the signed-in user
    /// this is their local copy, so edits show before the upload lands.
    func profile(forUserID id: String?) -> CreativeProfile? {
        guard let raw = Self.rawUserID(id) else { return nil }
        if raw == Self.myUserID { return myProfile }
        return profiles[raw]
    }

    /// The signed-in user's details built from local state. Always non-nil — an
    /// empty sheet is still a sheet the tags unlocked.
    var myProfile: CreativeProfile {
        CreativeProfile(userID: Self.myUserID ?? "me", details: myDetails,
                        headshotFileURL: myHeadshot == nil ? nil : Self.myHeadshotURL,
                        updatedAt: profiles[Self.myUserID ?? ""]?.updatedAt ?? Date())
    }

    /// The headshot to show for a directory user: their uploaded headshot, else nil.
    func headshot(forUserID id: String?) -> UIImage? {
        guard let profile = profile(forUserID: id) else { return nil }
        if profile.userID == Self.myUserID, let mine = myHeadshot { return mine }
        guard let url = profile.headshotFileURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    // MARK: - Auditions

    func hasAuditioned(projectID: UUID, role: String) -> Bool {
        auditions.contains { $0.projectID == projectID && $0.role == role }
    }

    func recordAudition(project: Submission, role: String) {
        guard !hasAuditioned(projectID: project.id, role: role) else { return }
        auditions.insert(AuditionEntry(projectID: project.id, projectTitle: project.title, role: role), at: 0)
        saveAuditions()
    }

    func setStatus(_ status: AuditionStatus, for entry: AuditionEntry) {
        guard let index = auditions.firstIndex(where: { $0.id == entry.id }) else { return }
        auditions[index].status = status
        saveAuditions()
    }

    func removeAudition(_ entry: AuditionEntry) {
        auditions.removeAll { $0.id == entry.id }
        saveAuditions()
    }

    private func saveAuditions() {
        if let data = try? JSONEncoder().encode(auditions) {
            defaults.set(data, forKey: auditionsKey)
        }
    }

    // MARK: - Helpers

    private static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
