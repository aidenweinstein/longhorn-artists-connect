//
//  UserProfileManager.swift
//  Longhorn Artists Connect
//
//  Manages fetching and caching user profiles from CloudKit
//

import Foundation
import CloudKit
import SwiftUI
import Combine

// MARK: - Simplified User Profile for Directory

/// Lightweight user profile for directory listings
struct DirectoryUser: Identifiable, Hashable, Codable {
    let id: String // CloudKit record name
    /// Names are kept in normalized form (capitalized words, no stray extra
    /// spaces) — see `normalizeNames()`. `var` so records fetched or decoded
    /// before that cleanup existed can be tidied in place.
    var firstName: String
    var lastName: String
    let major: String
    let graduationYear: String
    let userTypes: [String] // Parsed from comma-separated string
    let bio: String
    let instagramHandle: String
    var profileImageData: Data? // Cached thumbnail (streamed in after the list loads)
    /// False for Guest (non-UT) accounts. Defaults to true so older cached
    /// entries decode as UT students.
    var isUTStudent: Bool = true
    /// The owner's chosen ordering of their portfolio posts, as submission-UUID
    /// strings. Empty means "no custom order" (fall back to newest-first). Defaults
    /// to empty so older cached entries decode cleanly.
    var portfolioOrder: [String] = []
    /// The member's school, used to theme their credit-name chip. Empty falls back
    /// to the app brand. Defaults so older cached entries decode cleanly.
    var school: String = ""
    /// True for accounts created via the "I'm an Industry Professional" flow. These
    /// are listed in their own directory section. Defaults false for cache back-compat.
    var isIndustryProfessional: Bool = false
    /// Industry-professional fields (industry replaces major, company replaces class,
    /// companyRole is new). Empty for student/guest accounts.
    var industry: String = ""
    var company: String = ""
    var companyRole: String = ""
    /// Artist / Enthusiast (`AccountKind` raw value). Empty for accounts that
    /// predate the choice. May still read "Agent" for accounts that haven't
    /// launched the app since Agent mode was removed (2026-10-16).
    var accountKind: String = ""
    /// Left over from the removed Agent flow, which uploaded agents' emails. New
    /// saves clear the field, so this is empty for everyone once they relaunch.
    var email: String = ""

    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }
    
    var displayName: String {
        fullName.isEmpty ? "Unknown User" : fullName
    }
    
    var rolesString: String {
        userTypes.joined(separator: ", ")
    }

    /// The raw iCloud user-record id used for messaging, matching what
    /// `CKContainer.userRecordID().recordName` returns for that user. Directory
    /// records are named `"UserProfile_<userRecordID>"`, so we strip that prefix.
    /// Messaging identifies "self" by the raw id, so the "other user" must use the
    /// same raw form or the two devices never resolve to the same conversation.
    var messagingUserID: String {
        let prefix = "UserProfile_"
        return id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id
    }
    
    var initials: String {
        let first = firstName.first.map(String.init) ?? ""
        let last = lastName.first.map(String.init) ?? ""
        return "\(first)\(last)".uppercased()
    }

    /// Cleans up the stored name (capitalizes each word, collapses extra spaces).
    /// Applied to every profile as it comes out of CloudKit or the on-disk cache,
    /// so profiles saved before sign-up normalization existed still *display*
    /// correctly even when their CloudKit record hasn't been rewritten yet.
    mutating func normalizeNames() {
        firstName = firstName.normalizedName
        lastName = lastName.normalizedName
    }
}

// MARK: - User Profile Manager

@MainActor
class UserProfileManager: ObservableObject {
    static let shared = UserProfileManager()
    
    @Published var allUsers: [DirectoryUser] = []
    @Published var isLoading = false
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?
    
    private let container = CKContainer.default()
    private var database: CKDatabase {
        container.publicCloudDatabase
    }
    
    // Cache to avoid redundant fetches. The user blob (which embeds a profile-photo
    // thumbnail per user) is written to a file — NOT UserDefaults — because it easily
    // exceeds the 4 MB NSUserDefaults limit and would otherwise be silently dropped.
    private let cacheKey = "cachedDirectoryUsers"        // legacy UserDefaults key (migrated off)
    private let cacheTimestampKey = "\(CloudKitEnvironmentDetector.localCachePrefix)lastUserFetchTimestamp"

    /// On-disk location of the directory cache (Caches dir; safe to be evicted).
    private var cacheFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("\(CloudKitEnvironmentDetector.localCachePrefix)cachedDirectoryUsers.json")
    }

    /// The lightweight fields fetched first so the directory list appears immediately.
    /// The heavy `profileImage` asset is streamed in afterwards (see `hydrateProfileImages`).
    private static let metadataKeys: [CKRecord.FieldKey] = [
        "firstName", "lastName", "major", "graduationYear", "userTypes", "bio",
        "instagramHandle", "isUTStudent", "portfolioOrder", "school",
        "isIndustryProfessional", "industry", "company", "companyRole", "accountKind",
        "userEmail"
    ]
    
    private init() {
        // Load from cache immediately
        loadFromCache()

        // Then fetch fresh data in background
        Task {
            await fetchAllUsers()
        }
    }

    // MARK: - Public Methods
    
    /// Fetch all user profiles from CloudKit
    func fetchAllUsers(forceRefresh: Bool = false) async {
        // Don't fetch if we recently synced (unless forced)
        if !forceRefresh, let lastSync = lastSyncDate,
           Date().timeIntervalSince(lastSync) < 300 { // 5 minutes
            print("📱 Using cached user profiles (last sync: \(lastSync))")
            return
        }
        
        guard CloudKitManager.shared.isAvailable else {
            errorMessage = "CloudKit not available"
            print("⚠️ CloudKit not available - using cached users")
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        print("🔄 Fetching user profiles from CloudKit...")
        
        do {
            // NOTE: no server-side sort descriptor. A `lastName` sort requires that
            // field to be marked *Sortable* in the CloudKit schema for the current
            // environment; if it isn't (e.g. schema not deployed to Production), the
            // whole query throws and the directory silently comes back empty. We sort
            // client-side below instead, which can't fail.
            let query = CKQuery(recordType: "UserProfile", predicate: NSPredicate(value: true))

            // PASS 1 — names/metadata only (no image assets) so the list appears fast.
            // Any thumbnail we already have cached is kept so photos show immediately on
            // repeat opens; fresh ones stream in during PASS 2.
            let cachedImages = Dictionary(allUsers.map { ($0.id, $0.profileImageData) },
                                          uniquingKeysWith: { first, _ in first })
            var users: [DirectoryUser] = []

            // Page through EVERY result — a single query only returns one batch, so
            // without following the cursor the directory loads partially and "fills in"
            // on a later refresh (the missing-people symptom).
            var response = try await database.records(matching: query, desiredKeys: Self.metadataKeys)
            while true {
                for (recordID, result) in response.matchResults {
                    switch result {
                    case .success(let record):
                        if var user = parseUserMetadata(from: record) {
                            user.profileImageData = cachedImages[user.id] ?? nil
                            users.append(user)
                        }
                    case .failure(let error):
                        print("❌ Failed to fetch user \(recordID.recordName): \(error.localizedDescription)")
                    }
                }
                guard let cursor = response.queryCursor else { break }
                response = try await database.records(continuingMatchFrom: cursor, desiredKeys: Self.metadataKeys)
            }

            // Sort by last name
            users.sort { $0.lastName < $1.lastName }

            allUsers = users
            lastSyncDate = Date()
            isLoading = false
            saveToCache(users)
            print("✅ Fetched \(users.count) user profiles from CloudKit")

            // PASS 2 — stream in profile thumbnails without blocking the list.
            await hydrateProfileImages(query: query)

        } catch {
            await MainActor.run {
                let env = CloudKitEnvironmentDetector.current
                errorMessage = "Couldn't load the directory from CloudKit (\(env)): \(error.localizedDescription)"
                isLoading = false
                print("❌ Failed to fetch users [\(env)]: \(error)")
            }
        }
    }
    
    /// Deletes a user's `UserProfile` record from CloudKit (moderator action).
    /// Returns `nil` on success, or a user-facing error message.
    ///
    /// Note: in the CloudKit **public** database a record can normally only be
    /// deleted by the iCloud account that created it, so this may fail with a
    /// permission error for profiles created by other users.
    @discardableResult
    func deleteUserProfile(_ user: DirectoryUser) async -> String? {
        let recordID = CKRecord.ID(recordName: user.id)
        do {
            try await database.deleteRecord(withID: recordID)
            allUsers.removeAll { $0.id == user.id }
            saveToCache(allUsers)
            print("✅ Deleted user profile: \(user.displayName) (\(user.id))")
            return nil
        } catch let error as CKError where error.code == .permissionFailure || error.code == .notAuthenticated {
            return "This profile was created by a different iCloud account, so CloudKit won't let the app delete it. Remove it from the CloudKit Console instead."
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone from CloudKit — clean it up locally.
            allUsers.removeAll { $0.id == user.id }
            saveToCache(allUsers)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Moderator action: moves a profile between the UT-student and Guest
    /// categories by updating its `isUTStudent` flag in CloudKit. Guest profiles
    /// (`isUTStudent == false`) are hidden from the directory.
    /// Returns `nil` on success, or a user-facing error message.
    @discardableResult
    func setGuestStatus(_ user: DirectoryUser, isGuest: Bool) async -> String? {
        let recordID = CKRecord.ID(recordName: user.id)
        do {
            let record = try await database.record(for: recordID)
            record["isUTStudent"] = (isGuest ? 0 : 1) as CKRecordValue
            _ = try await database.save(record)

            // Reflect the change locally so the directory/moderation lists update.
            if let index = allUsers.firstIndex(where: { $0.id == user.id }) {
                allUsers[index].isUTStudent = !isGuest
                saveToCache(allUsers)
            }
            print("✅ Set \(user.displayName) to \(isGuest ? "Guest" : "UT Student")")
            return nil
        } catch let error as CKError where error.code == .permissionFailure || error.code == .notAuthenticated {
            return "This profile was created by a different iCloud account, so CloudKit won't let the app modify it. Change it from the CloudKit Console instead."
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Name Cleanup Migration

    /// Outcome of a `normalizeAllUserNames()` run, for reporting back to the moderator.
    struct NameCleanupResult {
        var scanned = 0
        var fixed = 0
        /// Records that needed fixing but couldn't be written — almost always
        /// because CloudKit's public database only lets the creating iCloud
        /// account modify a record.
        var skipped = 0
        /// First error encountered, if any.
        var errorMessage: String?

        var summary: String {
            if let errorMessage, fixed == 0, skipped == 0 {
                return "Couldn't run the cleanup: \(errorMessage)"
            }
            var text = "Scanned \(scanned) profile\(scanned == 1 ? "" : "s"), fixed \(fixed)."
            if skipped > 0 {
                text += " \(skipped) couldn't be rewritten — CloudKit only lets a profile's own iCloud account modify it, so fix those in the CloudKit Console. They still display correctly in the app."
            }
            if let errorMessage, skipped > 0 || fixed > 0 {
                text += " Last error: \(errorMessage)"
            }
            return text
        }
    }

    /// Moderator action: one-time cleanup of the names already in CloudKit.
    /// Walks every `UserProfile` record, applies `String.normalizedName`
    /// (capitalize each word, collapse stray extra spaces) and saves back only
    /// the records whose name actually changes. New sign-ups are normalized at
    /// save time, so this exists purely to fix the older profiles.
    ///
    /// Two caveats worth knowing before running it:
    /// - The public database normally only allows a record's creating iCloud
    ///   account to modify it, so other people's profiles may come back as
    ///   `skipped`. Those still *display* normalized (see `parseUserMetadata`)
    ///   and self-heal the next time that user opens the app, because `save()`
    ///   normalizes before pushing to CloudKit.
    /// - A Debug build talks to the Development environment; run this from a
    ///   TestFlight/App Store build to fix the Production records.
    @discardableResult
    func normalizeAllUserNames() async -> NameCleanupResult {
        var result = NameCleanupResult()
        let query = CKQuery(recordType: "UserProfile", predicate: NSPredicate(value: true))
        let nameKeys: [CKRecord.FieldKey] = ["firstName", "lastName"]

        print("🔤 Starting name cleanup across UserProfile records…")

        do {
            // Page through every result — one query only returns a single batch.
            var response = try await database.records(matching: query, desiredKeys: nameKeys)
            while true {
                for (recordID, matchResult) in response.matchResults {
                    guard case .success(let record) = matchResult else { continue }
                    result.scanned += 1

                    let firstName = record["firstName"] as? String ?? ""
                    let lastName = record["lastName"] as? String ?? ""
                    let cleanFirst = firstName.normalizedName
                    let cleanLast = lastName.normalizedName
                    guard cleanFirst != firstName || cleanLast != lastName else { continue }

                    do {
                        // Re-fetch the complete record before saving: the queried copy
                        // only carries the two name fields, and writing a partial record
                        // risks dropping the rest of the profile.
                        let fullRecord = try await database.record(for: recordID)
                        fullRecord["firstName"] = cleanFirst as CKRecordValue
                        fullRecord["lastName"] = cleanLast as CKRecordValue
                        _ = try await database.save(fullRecord)
                        result.fixed += 1
                        print("✏️ \"\(firstName) \(lastName)\" → \"\(cleanFirst) \(cleanLast)\"")
                    } catch let error as CKError where error.code == .permissionFailure || error.code == .notAuthenticated {
                        result.skipped += 1
                        print("⚠️ No permission to rewrite \(recordID.recordName)")
                    } catch {
                        result.skipped += 1
                        result.errorMessage = error.localizedDescription
                        print("❌ Failed to rewrite \(recordID.recordName): \(error.localizedDescription)")
                    }
                }
                guard let cursor = response.queryCursor else { break }
                response = try await database.records(continuingMatchFrom: cursor, desiredKeys: nameKeys)
            }
        } catch {
            result.errorMessage = error.localizedDescription
            print("❌ Name cleanup query failed: \(error.localizedDescription)")
            return result
        }

        print("✅ Name cleanup finished — scanned \(result.scanned), fixed \(result.fixed), skipped \(result.skipped)")

        if result.fixed > 0 {
            await fetchAllUsers(forceRefresh: true)
        }
        return result
    }

    /// Search users by name or role
    func searchUsers(_ query: String) -> [DirectoryUser] {
        guard !query.isEmpty else { return allUsers }
        
        let lowercaseQuery = query.lowercased()
        
        return allUsers.filter { user in
            user.fullName.lowercased().contains(lowercaseQuery) ||
            user.firstName.lowercased().contains(lowercaseQuery) ||
            user.lastName.lowercased().contains(lowercaseQuery) ||
            user.userTypes.contains { $0.lowercased().contains(lowercaseQuery) } ||
            user.major.lowercased().contains(lowercaseQuery)
        }
    }
    
    /// Find user by full name (for backwards compatibility with existing code)
    func findUser(byName name: String) -> DirectoryUser? {
        allUsers.first { $0.fullName == name }
    }

    /// Find user by ID (used to resolve message participants).
    ///
    /// Message/conversation participants are stored as the raw CloudKit user
    /// record name, whereas a `UserProfile` record's name is
    /// `"UserProfile_<userRecordName>"`. Normalize both sides so either form
    /// resolves to the same person.
    func findUser(byID id: String) -> DirectoryUser? {
        let normalized = Self.normalizedUserID(id)
        return allUsers.first { Self.normalizedUserID($0.id) == normalized }
    }

    /// Strips the `UserProfile_` prefix so a profile record name and a raw user
    /// record name compare equal.
    private static func normalizedUserID(_ id: String) -> String {
        let prefix = "UserProfile_"
        return id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id
    }
    
    /// Find users by graduation year
    func findUsers(byGraduationYear year: String) -> [DirectoryUser] {
        allUsers.filter { $0.graduationYear == year }
    }
    
    /// Find users by role
    func findUsers(byRole role: String) -> [DirectoryUser] {
        allUsers.filter { $0.userTypes.contains(role) }
    }
    
    /// Updates the cached portfolio ordering for a profile (by its record name, i.e.
    /// `UserProfile_<userRecordID>`) so views reading from the directory cache reflect a
    /// just-saved reorder immediately, without waiting for the next full CloudKit sync.
    func updateCachedPortfolioOrder(_ order: [String], for recordName: String) {
        guard let index = allUsers.firstIndex(where: { $0.id == recordName }) else { return }
        allUsers[index].portfolioOrder = order
        saveToCache(allUsers)
    }

    /// Get current user (from local storage)
    func getCurrentUser() -> DirectoryUser? {
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUserName = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        
        return findUser(byName: currentUserName)
    }
    
    // MARK: - Cache Management
    
    private func saveToCache(_ users: [DirectoryUser]) {
        guard let url = cacheFileURL, let encoded = try? JSONEncoder().encode(users) else { return }
        do {
            try encoded.write(to: url, options: .atomic)
            UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
            // Drop any legacy oversized blob that used to live in UserDefaults.
            UserDefaults.standard.removeObject(forKey: cacheKey)
            print("💾 Cached \(users.count) user profiles")
        } catch {
            print("⚠️ Failed to write user profile cache: \(error.localizedDescription)")
        }
    }

    private func loadFromCache() {
        // One-time cleanup: an older build stored this (>4 MB) blob in UserDefaults,
        // which is invalid and gets dropped. Remove it so it can't be re-read or re-warn.
        UserDefaults.standard.removeObject(forKey: cacheKey)

        guard let url = cacheFileURL,
              let data = try? Data(contentsOf: url),
              var users = try? JSONDecoder().decode([DirectoryUser].self, from: data) else {
            print("ℹ️ No cached user profiles found")
            return
        }

        // Entries cached by an older build can hold un-normalized names.
        for index in users.indices { users[index].normalizeNames() }

        allUsers = users
        lastSyncDate = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date

        print("📱 Loaded \(users.count) user profiles from cache")
    }

    func clearCache() {
        if let url = cacheFileURL { try? FileManager.default.removeItem(at: url) }
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
        allUsers = []
        lastSyncDate = nil
        print("🗑️ Cleared user profile cache")
    }
    
    // MARK: - CloudKit Parsing
    
    /// Builds a directory entry from the lightweight metadata fields only (no image).
    /// The `profileImage` asset is fetched separately and streamed in by
    /// `hydrateProfileImages` so the list can appear without waiting on downloads.
    private func parseUserMetadata(from record: CKRecord) -> DirectoryUser? {
        // Normalize on the way in so older profiles (saved before sign-up
        // normalization) display the same as new ones, whether or not their
        // CloudKit record has been rewritten by `normalizeAllUserNames()`.
        let firstName = (record["firstName"] as? String ?? "").normalizedName
        let lastName = (record["lastName"] as? String ?? "").normalizedName

        // Skip if no name (invalid profile)
        guard !firstName.isEmpty || !lastName.isEmpty else {
            print("⚠️ Skipping user profile with no name: \(record.recordID.recordName)")
            return nil
        }

        let major = record["major"] as? String ?? ""
        let graduationYear = record["graduationYear"] as? String ?? ""
        let userTypesString = record["userTypes"] as? String ?? ""
        let bio = record["bio"] as? String ?? ""
        let instagramHandle = record["instagramHandle"] as? String ?? ""
        let isUTStudent = ((record["isUTStudent"] as? Int) ?? 1) == 1
        let portfolioOrder = record["portfolioOrder"] as? [String] ?? []
        let school = record["school"] as? String ?? ""
        let isIndustryProfessional = ((record["isIndustryProfessional"] as? Int) ?? 0) == 1
        let industry = record["industry"] as? String ?? ""
        let company = record["company"] as? String ?? ""
        let companyRole = record["companyRole"] as? String ?? ""

        // Parse user types from comma-separated string
        let userTypes = userTypesString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return DirectoryUser(
            id: record.recordID.recordName,
            firstName: firstName,
            lastName: lastName,
            major: major,
            graduationYear: graduationYear,
            userTypes: userTypes,
            bio: bio,
            instagramHandle: instagramHandle,
            profileImageData: nil,   // streamed in later
            isUTStudent: isUTStudent,
            portfolioOrder: portfolioOrder,
            school: school,
            isIndustryProfessional: isIndustryProfessional,
            industry: industry,
            company: company,
            companyRole: companyRole,
            accountKind: record["accountKind"] as? String ?? "",
            email: record["userEmail"] as? String ?? ""
        )
    }

    /// Second pass: fetches only the `profileImage` asset for every profile, decodes and
    /// downscales it OFF the main thread, and patches each user's thumbnail into
    /// `allUsers` as it arrives — so photos pop in without blocking (or re-loading) the
    /// list. Persists the updated cache once finished.
    private func hydrateProfileImages(query: CKQuery) async {
        guard var response = try? await database.records(matching: query, desiredKeys: ["profileImage"]) else { return }
        while true {
            for (recordID, result) in response.matchResults {
                guard case .success(let record) = result,
                      let asset = record["profileImage"] as? CKAsset,
                      let fileURL = asset.fileURL else { continue }
                let id = recordID.recordName
                // Read + downscale off the main actor (heavy work).
                let thumbnail = await Task.detached(priority: .utility) { () -> Data? in
                    guard let raw = try? Data(contentsOf: fileURL),
                          let image = UIImage(data: raw) else { return nil }
                    return image.jpegData(compressionQuality: 0.3)
                }.value
                if let thumbnail, let index = allUsers.firstIndex(where: { $0.id == id }) {
                    allUsers[index].profileImageData = thumbnail
                }
            }
            guard let cursor = response.queryCursor,
                  let next = try? await database.records(continuingMatchFrom: cursor, desiredKeys: ["profileImage"]) else { break }
            response = next
        }
        saveToCache(allUsers)
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension UserProfileManager {
    /// Seeds the shared directory with two dummy profiles ("Test 1" and "Test 2")
    /// so credit-name suggestions can be exercised in Xcode previews / Canvas.
    /// DEBUG-only — never used by the shipping app.
    static func seedPreviewUsers() {
        shared.allUsers = [
            DirectoryUser(
                id: "preview-test-1",
                firstName: "Test",
                lastName: "1",
                major: "Radio-Television-Film",
                graduationYear: "2027",
                userTypes: ["Director", "Editor"],
                bio: "",
                instagramHandle: "",
                profileImageData: nil
            ),
            DirectoryUser(
                id: "preview-test-2",
                firstName: "Test",
                lastName: "2",
                major: "Music",
                graduationYear: "2026",
                userTypes: ["Composer", "Sound Mixer"],
                bio: "",
                instagramHandle: "",
                profileImageData: nil
            )
        ]
    }

    static var preview: UserProfileManager {
        let manager = UserProfileManager()
        
        // Add sample users
        manager.allUsers = [
            DirectoryUser(
                id: "sample1",
                firstName: "John",
                lastName: "Doe",
                major: "Radio-Television-Film",
                graduationYear: "2026",
                userTypes: ["Director", "Cinematographer"],
                bio: "Aspiring filmmaker",
                instagramHandle: "johndoe_films",
                profileImageData: nil
            ),
            DirectoryUser(
                id: "sample2",
                firstName: "Jane",
                lastName: "Smith",
                major: "Computer Science",
                graduationYear: "2025",
                userTypes: ["Editor", "VFX Artist"],
                bio: "Post-production specialist",
                instagramHandle: "janesmith",
                profileImageData: nil
            ),
            DirectoryUser(
                id: "sample3",
                firstName: "Alex",
                lastName: "Johnson",
                major: "Music",
                graduationYear: "2026",
                userTypes: ["Composer", "Sound Mixer"],
                bio: "Audio engineer and composer",
                instagramHandle: "alexjmusic",
                profileImageData: nil
            )
        ]
        
        return manager
    }
}
#endif
