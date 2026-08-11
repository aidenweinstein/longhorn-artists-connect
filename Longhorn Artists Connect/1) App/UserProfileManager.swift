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
    let firstName: String
    let lastName: String
    let major: String
    let graduationYear: String
    let userTypes: [String] // Parsed from comma-separated string
    let bio: String
    let instagramHandle: String
    let profileImageData: Data? // Cached thumbnail
    /// False for Guest (non-UT) accounts. Defaults to true so older cached
    /// entries decode as UT students.
    var isUTStudent: Bool = true

    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }
    
    var displayName: String {
        fullName.isEmpty ? "Unknown User" : fullName
    }
    
    var rolesString: String {
        userTypes.joined(separator: ", ")
    }
    
    var initials: String {
        let first = firstName.first.map(String.init) ?? ""
        let last = lastName.first.map(String.init) ?? ""
        return "\(first)\(last)".uppercased()
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
    
    // Cache to avoid redundant fetches
    private let cacheKey = "cachedDirectoryUsers"
    private let cacheTimestampKey = "lastUserFetchTimestamp"
    
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
        
        guard await CloudKitManager.shared.isAvailable else {
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

            let (matchResults, _) = try await database.records(matching: query)
            
            var users: [DirectoryUser] = []
            
            for (recordID, result) in matchResults {
                switch result {
                case .success(let record):
                    if let user = parseUserProfile(from: record) {
                        users.append(user)
                        print("✅ Loaded user: \(user.fullName)")
                    }
                case .failure(let error):
                    print("❌ Failed to fetch user \(recordID.recordName): \(error.localizedDescription)")
                }
            }
            
            // Sort by last name
            users.sort { $0.lastName < $1.lastName }
            
            await MainActor.run {
                allUsers = users
                lastSyncDate = Date()
                isLoading = false

                // Save to cache
                saveToCache(users)
                
                print("✅ Fetched \(users.count) user profiles from CloudKit")
            }
            
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
    
    /// Get current user (from local storage)
    func getCurrentUser() -> DirectoryUser? {
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUserName = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        
        return findUser(byName: currentUserName)
    }
    
    // MARK: - Cache Management
    
    private func saveToCache(_ users: [DirectoryUser]) {
        if let encoded = try? JSONEncoder().encode(users) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
            print("💾 Cached \(users.count) user profiles")
        }
    }
    
    private func loadFromCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let users = try? JSONDecoder().decode([DirectoryUser].self, from: data) else {
            print("ℹ️ No cached user profiles found")
            return
        }
        
        allUsers = users
        lastSyncDate = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date
        
        print("📱 Loaded \(users.count) user profiles from cache")
    }
    
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
        allUsers = []
        lastSyncDate = nil
        print("🗑️ Cleared user profile cache")
    }
    
    // MARK: - CloudKit Parsing
    
    private func parseUserProfile(from record: CKRecord) -> DirectoryUser? {
        let firstName = record["firstName"] as? String ?? ""
        let lastName = record["lastName"] as? String ?? ""
        
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
        
        // Parse user types from comma-separated string
        let userTypes = userTypesString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // Extract profile image data (as thumbnail)
        var profileImageData: Data?
        if let asset = record["profileImage"] as? CKAsset,
           let fileURL = asset.fileURL,
           let imageData = try? Data(contentsOf: fileURL) {
            // Compress for directory view
            if let image = UIImage(data: imageData),
               let thumbnailData = image.jpegData(compressionQuality: 0.3) {
                profileImageData = thumbnailData
            }
        }
        
        return DirectoryUser(
            id: record.recordID.recordName,
            firstName: firstName,
            lastName: lastName,
            major: major,
            graduationYear: graduationYear,
            userTypes: userTypes,
            bio: bio,
            instagramHandle: instagramHandle,
            profileImageData: profileImageData,
            isUTStudent: isUTStudent
        )
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
