//
//  CreativeProfileStore.swift
//  Longhorn Artists Connect
//
//  Profile styles in CloudKit, and the signed-in user's own style, details,
//  headshot and audition list.
//
//  Two public-database record types (create both in CloudKit Dashboard, in BOTH
//  environments, then deploy — see the schema table in CloudKitRecordTypes.swift):
//
//  • `CreativeProfile` — one per person, written only by that person.
//      record name  "CreativeProfile_<userRecordID>"
//      style        STRING   "Filmmaker" / "Actor" / "Musician"
//      details      STRING   JSON of `CreativeDetails`
//      headshot     ASSET    actors' headshot (optional)
//      updatedAt    DATE/TIME
//
//  • `DirectoryListing` — one per person, written only by the moderator. Puts a
//    profile on (or keeps it off) its style's public page.
//      record name  "listing_<userRecordID>"
//      userID       STRING
//      style        STRING
//      status       STRING   "approved" / "declined"
//      modifiedAt   DATE/TIME
//
//  Both are fetched with a match-all query, so each needs a QUERYABLE index on
//  `recordName` (same as the other types here).
//
//  Auditions are kept on this device only for now.
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
    static let listingRecordType = "DirectoryListing"

    // MARK: Mine

    /// The signed-in user's style. Nil until they pick one.
    @Published private(set) var myStyle: ProfileStyle?
    @Published private(set) var myDetails = CreativeDetails()
    @Published private(set) var myHeadshot: UIImage?
    @Published private(set) var auditions: [AuditionEntry] = []
    /// Set while saving to CloudKit, so the editor can show progress.
    @Published private(set) var isSaving = false

    // MARK: Everyone

    /// Every synced profile, keyed by raw user record name.
    @Published private(set) var profiles: [String: CreativeProfile] = [:]
    /// Every moderator decision, keyed by raw user record name.
    @Published private(set) var listings: [String: DirectoryListing] = [:]
    @Published private(set) var isLoading = false
    /// Last CloudKit problem, shown on the moderator's review page.
    @Published var lastError: String?

    private var lastFetch: Date?

    private let defaults = UserDefaults.standard
    private var detailsKey: String { "creativeDetails" }
    private var auditionsKey: String { "\(CloudKitEnvironmentDetector.localCachePrefix)auditions" }

    private init() {
        myStyle = ProfileStyle.current
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
        for prefix in ["UserProfile_", "CreativeProfile_", "listing_"] where id.hasPrefix(prefix) {
            id = String(id.dropFirst(prefix.count))
        }
        return id
    }

    private static var myHeadshotURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("creativeHeadshot.jpg")
    }

    // MARK: - Editing my profile

    /// Saves the user's choices on this device right away, then uploads them.
    func update(style: ProfileStyle, details: CreativeDetails, headshot: UIImage?) {
        myStyle = style
        myDetails = details
        defaults.set(style.rawValue, forKey: ProfileStyle.storageKey)
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

    /// Forgets the signed-in user's style, details, headshot and auditions on this
    /// device (logout / reset). Their CloudKit record is left for account deletion.
    func clearMine() {
        myStyle = nil
        myDetails = CreativeDetails()
        myHeadshot = nil
        auditions = []
        defaults.removeObject(forKey: ProfileStyle.storageKey)
        defaults.removeObject(forKey: detailsKey)
        defaults.removeObject(forKey: auditionsKey)
        try? FileManager.default.removeItem(at: Self.myHeadshotURL)
    }

    /// Uploads the user's `CreativeProfile`. Safe to call repeatedly.
    func saveMine() async {
        guard let style = myStyle else { return }
        guard CloudKitManager.shared.isAvailable, let userID = Self.myUserID else {
            print("⚠️ Profile style saved on this device only — CloudKit isn't available")
            return
        }

        isSaving = true
        defer { isSaving = false }

        let record = CKRecord(recordType: Self.profileRecordType,
                              recordID: CKRecord.ID(recordName: "CreativeProfile_\(userID)"))
        record["style"] = style.rawValue as CKRecordValue
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
            profiles[userID] = CreativeProfile(userID: userID, style: style, details: myDetails,
                                               headshotFileURL: myHeadshot == nil ? nil : Self.myHeadshotURL,
                                               updatedAt: now)
            print("✅ Saved \(style.rawValue) profile style")
        } catch {
            lastError = "Couldn't save your profile style: \(error.localizedDescription)"
            print("❌ \(lastError ?? "")")
        }
    }

    // MARK: - Reading everyone's profiles

    /// Fetches every `CreativeProfile` and `DirectoryListing`. Throttled to once every
    /// two minutes unless forced.
    func refresh(force: Bool = false) async {
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < 120 { return }
        guard CloudKitManager.shared.isAvailable else { return }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }
        let database = CKContainer.default().publicCloudDatabase
        var problems: [String] = []

        do {
            let records = try await Self.fetchAll(recordType: Self.profileRecordType, in: database)
            var map: [String: CreativeProfile] = [:]
            for record in records {
                if let profile = Self.parseProfile(record) { map[profile.userID] = profile }
            }
            profiles = map

            // A style picked during onboarding (before iCloud was ready) or saved on a
            // bad connection may never have reached CloudKit. Push it now so the
            // moderator's queue and the public pages see it.
            if myStyle != nil, let me = Self.myUserID, map[me] == nil {
                await saveMine()
            }
        } catch {
            problems.append("\(Self.profileRecordType): \(error.localizedDescription)")
        }

        do {
            let records = try await Self.fetchAll(recordType: Self.listingRecordType, in: database)
            var map: [String: DirectoryListing] = [:]
            for record in records {
                if let listing = Self.parseListing(record) { map[listing.userID] = listing }
            }
            listings = map
        } catch {
            problems.append("\(Self.listingRecordType): \(error.localizedDescription)")
        }

        lastError = problems.isEmpty ? nil : "Couldn't load " + problems.joined(separator: "; ")
        if let lastError { print("⚠️ \(lastError)") }
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
        guard let userID = rawUserID(record.recordID.recordName),
              let style = ProfileStyle(rawValue: record["style"] as? String ?? "") else { return nil }

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
            style: style,
            details: CreativeDetails.decode(record["details"] as? String),
            headshotFileURL: headshotURL,
            updatedAt: (record["updatedAt"] as? Date) ?? record.modificationDate ?? .distantPast
        )
    }

    private static func parseListing(_ record: CKRecord) -> DirectoryListing? {
        guard let userID = rawUserID((record["userID"] as? String) ?? record.recordID.recordName),
              let style = ProfileStyle(rawValue: record["style"] as? String ?? ""),
              let status = DirectoryListing.Status(rawValue: record["status"] as? String ?? "") else { return nil }
        return DirectoryListing(userID: userID, style: style, status: status,
                                modifiedAt: (record["modifiedAt"] as? Date) ?? record.modificationDate ?? .distantPast)
    }

    // MARK: - Lookups

    /// A person's profile style by any form of their directory ID. For the signed-in
    /// user this is their local copy, so edits show before the upload lands.
    func profile(forUserID id: String?) -> CreativeProfile? {
        guard let raw = Self.rawUserID(id) else { return nil }
        if raw == Self.myUserID, let mine = myProfile { return mine }
        return profiles[raw]
    }

    /// The signed-in user's profile built from local state.
    var myProfile: CreativeProfile? {
        guard let style = myStyle else { return nil }
        return CreativeProfile(userID: Self.myUserID ?? "me", style: style, details: myDetails,
                               headshotFileURL: myHeadshot == nil ? nil : Self.myHeadshotURL,
                               updatedAt: profiles[Self.myUserID ?? ""]?.updatedAt ?? Date())
    }

    /// Whether a profile is on its style's public page.
    func isListed(_ profile: CreativeProfile) -> Bool {
        guard let listing = listings[profile.userID] else { return false }
        return listing.status == .approved && listing.style == profile.style
    }

    /// Profiles waiting for a moderator: never reviewed, reviewed under another style,
    /// or declined and edited since.
    var pendingProfiles: [CreativeProfile] {
        profiles.values.filter { profile in
            guard let listing = listings[profile.userID], listing.style == profile.style else { return true }
            return listing.status == .declined && profile.updatedAt > listing.modifiedAt
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    var listedProfiles: [CreativeProfile] {
        profiles.values.filter(isListed).sorted { $0.updatedAt > $1.updatedAt }
    }

    var declinedProfiles: [CreativeProfile] {
        profiles.values.filter { profile in
            guard let listing = listings[profile.userID] else { return false }
            return listing.style == profile.style && listing.status == .declined
                && profile.updatedAt <= listing.modifiedAt
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Listed people for one style's public page, paired with their directory entry.
    func listedPeople(for style: ProfileStyle, in directory: [DirectoryUser]) -> [(user: DirectoryUser, profile: CreativeProfile)] {
        let byID = Dictionary(directory.map { ($0.messagingUserID, $0) }, uniquingKeysWith: { first, _ in first })
        return profiles.values
            .filter { $0.style == style && isListed($0) }
            .compactMap { profile in byID[profile.userID].map { (user: $0, profile: profile) } }
            .sorted { $0.user.lastName < $1.user.lastName }
    }

    /// What the signed-in user's listing looks like, for the status line on Now.
    var myListingStatus: String? {
        guard let style = myStyle else { return nil }
        guard let me = Self.myUserID, let listing = listings[me], listing.style == style else {
            return "Waiting for a moderator to add you to the \(style.plural) page"
        }
        switch listing.status {
        case .approved: return "Listed on the \(style.plural) page"
        case .declined: return "Not listed on the \(style.plural) page. Edit your profile to send it back for review."
        }
    }

    // MARK: - Moderation

    /// Moderator action: puts a profile on its style's page, or keeps it off.
    func setListing(for profile: CreativeProfile, status: DirectoryListing.Status) async {
        let record = CKRecord(recordType: Self.listingRecordType,
                              recordID: CKRecord.ID(recordName: "listing_\(profile.userID)"))
        let now = Date()
        record["userID"] = profile.userID as CKRecordValue
        record["style"] = profile.style.rawValue as CKRecordValue
        record["status"] = status.rawValue as CKRecordValue
        record["modifiedAt"] = now as CKRecordValue
        do {
            try await CloudKitManager.shared.save(record: record)
            listings[profile.userID] = DirectoryListing(userID: profile.userID, style: profile.style,
                                                        status: status, modifiedAt: now)
        } catch {
            lastError = "Couldn't save that decision: \(error.localizedDescription)"
        }
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
