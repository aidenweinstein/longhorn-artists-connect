//
//  UserProfileModel-6)Models.swift
//  Longhorn Artists Connect
//
//  Backend logic for user profile management
//  Handles user data, validation, and persistence
//

import SwiftUI
import PhotosUI
import Combine
import CloudKit

// MARK: - Name Normalization

extension String {
    /// Cleans up a person's name for display and storage: trims surrounding
    /// whitespace, collapses any run of internal whitespace into a single space,
    /// and capitalizes the first letter of each word. Interior capitalization is
    /// left untouched so names like "McDonald" or "O'Brien" survive intact.
    var normalizedName: String {
        split(whereSeparator: { $0.isWhitespace })
            .map { word in word.first.map { $0.uppercased() + word.dropFirst() } ?? "" }
            .joined(separator: " ")
    }
}

// MARK: - Profile Image Cropping

/// Bakes the profile photo's pan/zoom crop into a standalone square image so
/// the framing "travels" with the photo — through CloudKit to the directory
/// and other users — instead of living only in this device's `@AppStorage`
/// (`profileImageScale` / `profileImageOffsetX` / `profileImageOffsetY`).
enum ProfileImageCropper {
    /// Side length (points) of the adjuster's circular preview. Saved offsets
    /// are expressed in this space; mirrors `ImageAdjustmentView.previewSize`.
    static let referenceSize: CGFloat = 300

    /// Renders `scaledToFill` + `scaleEffect(scale)` + `offset(offsetX, offsetY)`
    /// — the exact transform shown in the adjuster — into a square image.
    /// - Parameters:
    ///   - offsetX/offsetY: pan in the 300pt reference space (as stored).
    ///   - output: pixel dimensions of the resulting square image.
    static func bakedImage(from image: UIImage,
                           scale: CGFloat,
                           offsetX: CGFloat,
                           offsetY: CGFloat,
                           output: CGFloat = 600) -> UIImage {
        let side = output
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { _ in
            let imgSize = image.size
            guard imgSize.width > 0, imgSize.height > 0 else {
                image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
                return
            }
            // scaledToFill: cover the square, preserving aspect ratio.
            let fill = max(side / imgSize.width, side / imgSize.height)
            let drawScale = fill * max(scale, 1.0)
            let drawSize = CGSize(width: imgSize.width * drawScale,
                                  height: imgSize.height * drawScale)
            // Center, then apply the pan scaled from reference space to output.
            let offScale = side / referenceSize
            let origin = CGPoint(
                x: (side - drawSize.width) / 2 + offsetX * offScale,
                y: (side - drawSize.height) / 2 + offsetY * offScale
            )
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}

// MARK: - User Type Enum

enum UserType: String, CaseIterable, Identifiable, Codable {
    case actor = "Actor"
    case director = "Director"
    case producer = "Producer"
    case writer = "Writer"
    case editor = "Editor"
    case cinematographer = "Cinematographer"
    case photographer = "Photographer"
    case composer = "Composer"
    case soundMixer = "Sound Mixer"
    case animator = "Animator"
    case vfxArtist = "VFX Artist"
    case graphicDesigner = "Graphic Designer"
    case gameDesigner = "Game Designer"
    case painter = "Painter"
    case dancer = "Dancer"
    case singer = "Singer"
    case musician = "Musician"
    case manager = "Manager"
    case agent = "Agent"
    case enthusiast = "Enthusiast"
    
    var id: String { self.rawValue }
}

// MARK: - User Profile Model

@MainActor
class UserProfileModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var major: String = ""
    @Published var minor: String = ""
    @Published var certificate: String = ""
    /// Industry-professional fields (used only when `isIndustryProfessional` is true).
    /// `industry` replaces Major, `company` replaces Class, and `companyRole` is new.
    @Published var industry: String = ""
    @Published var company: String = ""
    @Published var companyRole: String = ""
    @Published var graduationYear: String = "2026"
    @Published var userTypes: Set<UserType> = []
    @Published var profileImage: UIImage?
    @Published var emailPrefix: String = ""
    @Published var isUTStudent: Bool = true
    /// The school the user attends. Defaults to UT; non-UT students pick their school
    /// during onboarding (UMich, Cal Poly SLO, USC, or a generic "Other").
    @Published var school: String = UserProfileModel.utSchoolName
    /// True only when the account was created via the explicit "I am a Guest User" flow.
    /// Distinct from `isUTStudent` so a student from another school is a full user.
    @Published var isGuest: Bool = false
    /// True when the account was created via the "I'm an Industry Professional" flow.
    /// These accounts are restricted like guests (no sharing) but keep a real profile
    /// and portfolio. Distinct from the tag-based `isIndustryPro` computed property.
    @Published var isIndustryProfessional: Bool = false
    @Published var bio: String = ""
    @Published var instagramHandle: String = ""
    @Published var websiteURL: String = ""
    
    // MARK: - AppStorage Bindings
    
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("userFirstName") var storedFirstName: String = ""
    @AppStorage("userLastName") var storedLastName: String = ""
    @AppStorage("userMajor") var storedMajor: String = ""
    @AppStorage("userMinor") var storedMinor: String = ""
    @AppStorage("userCertificate") var storedCertificate: String = ""
    @AppStorage("userGraduationYear") var storedGraduationYear: String = ""
    @AppStorage("userType") var storedUserType: String = ""
    @AppStorage("profileImagePath") var profileImagePath: String = ""
    @AppStorage("userEmail") var userEmail: String = ""
    @AppStorage("userBio") var storedBio: String = ""
    @AppStorage("userInstagram") var storedInstagram: String = ""
    @AppStorage("userWebsite") var storedWebsite: String = ""
    @AppStorage("userSchool") var storedSchool: String = ""
    /// True when the account was created via the Guest flow (not a student of any school).
    @AppStorage("isGuestUser") var isGuestUser: Bool = false
    @AppStorage("userIndustry") var storedIndustry: String = ""
    @AppStorage("userCompany") var storedCompany: String = ""
    @AppStorage("userCompanyRole") var storedCompanyRole: String = ""
    /// True when the account was created via the Industry Professional flow.
    @AppStorage("isIndustryProfessional") var isIndustryProfessionalStored: Bool = false

    // MARK: - Schools

    /// The canonical UT school name used as the default.
    static let utSchoolName = "The University of Texas at Austin"
    /// Selectable schools for the "I'm from another school" onboarding path.
    /// "Other" is the generic bucket chosen via "Add School".
    ///
    /// Anything added here also needs a registry slug in `SchoolScope`, a row in
    /// the verification service's D1 `schools` table, and a `school_domains` row
    /// for its email domain — otherwise the school can be picked but never
    /// verified, and its posts land in the wrong feed.
    static let otherSchools = ["University of California, Berkeley", "University of Michigan",
                               "Cal Poly SLO", "USC", "NYU", "DePaul", "Other"]
    
    // MARK: - Computed Properties
    
    /// Full name (first + last)
    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }
    
    /// Complete email address
    var completeEmail: String {
        guard !emailPrefix.isEmpty else { return "" }
        return "\(emailPrefix)@utexas.edu"
    }
    
    /// Check if profile is complete enough to proceed
    var isValid: Bool {
        let hasName = !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
                      !lastName.trimmingCharacters(in: .whitespaces).isEmpty
        
        // Email is required only for UT students
        let hasEmail = !isUTStudent || !emailPrefix.trimmingCharacters(in: .whitespaces).isEmpty
        
        return hasName && hasEmail
    }
    
    /// Check if user has at least one role selected
    var hasRoles: Bool {
        !userTypes.isEmpty
    }
    
    /// Get comma-separated role names
    var rolesString: String {
        userTypes.map { $0.rawValue }.sorted().joined(separator: ", ")
    }
    
    // MARK: - Initialization
    
    init() {
        loadFromStorage()
    }
    
    // MARK: - Save Functions
    
    /// Save all user data to AppStorage
    func save() {
        // Clean up the entered name (capitalize words, remove stray extra spaces)
        // before persisting so it's consistent everywhere it's displayed.
        firstName = firstName.normalizedName
        lastName = lastName.normalizedName

        storedFirstName = firstName
        storedLastName = lastName
        storedMajor = major
        storedMinor = minor
        storedCertificate = certificate
        storedGraduationYear = graduationYear
        storedUserType = rolesString
        userEmail = isUTStudent ? completeEmail : ""
        storedBio = bio
        storedInstagram = instagramHandle
        storedWebsite = websiteURL
        storedSchool = school
        isGuestUser = isGuest
        storedIndustry = industry
        storedCompany = company
        storedCompanyRole = companyRole
        isIndustryProfessionalStored = isIndustryProfessional

        // Save profile image to documents directory
        if let profileImage {
            saveProfileImage(profileImage)
        }
        
        hasCompletedOnboarding = true
        
        print("✅ User profile saved: \(fullName)")
        
        // Save to CloudKit for cross-device sync and directory visibility
        Task {
            await saveToCloudKit()
        }
    }
    
    /// Update user profile (for editing after onboarding)
    func update() {
        save() // Same as save for now
        print("✅ User profile updated: \(fullName)")
    }
    
    /// Load user data from AppStorage
    func loadFromStorage() {
        firstName = storedFirstName
        lastName = storedLastName
        major = storedMajor
        minor = storedMinor
        certificate = storedCertificate
        graduationYear = storedGraduationYear
        emailPrefix = extractEmailPrefix(from: userEmail)
        bio = storedBio
        instagramHandle = storedInstagram
        websiteURL = storedWebsite
        school = storedSchool.isEmpty ? UserProfileModel.utSchoolName : storedSchool
        isGuest = isGuestUser
        industry = storedIndustry
        company = storedCompany
        companyRole = storedCompanyRole
        isIndustryProfessional = isIndustryProfessionalStored

        // Parse stored user types
        let types = storedUserType.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        userTypes = Set(types.compactMap { UserType(rawValue: $0) })
        
        // Load profile image
        loadProfileImage()
        
        print("📥 User profile loaded: \(fullName)")
    }
    
    /// Clear all user data (for logout/reset)
    func clearAll() {
        // Clear published properties
        firstName = ""
        lastName = ""
        major = ""
        minor = ""
        certificate = ""
        graduationYear = "2026"
        userTypes = []
        profileImage = nil
        emailPrefix = ""
        isUTStudent = true
        school = UserProfileModel.utSchoolName
        isGuest = false
        industry = ""
        company = ""
        companyRole = ""
        isIndustryProfessional = false
        bio = ""
        instagramHandle = ""
        websiteURL = ""

        // Clear AppStorage
        storedFirstName = ""
        storedLastName = ""
        storedMajor = ""
        storedMinor = ""
        storedCertificate = ""
        storedGraduationYear = ""
        storedUserType = ""
        profileImagePath = ""
        userEmail = ""
        storedBio = ""
        storedInstagram = ""
        storedWebsite = ""
        storedSchool = ""
        isGuestUser = false
        storedIndustry = ""
        storedCompany = ""
        storedCompanyRole = ""
        isIndustryProfessionalStored = false
        hasCompletedOnboarding = false
        
        // Delete profile image file
        deleteProfileImage()
        
        print("🗑️ User profile cleared")
    }
    
    // MARK: - Profile Image Management
    
    /// Save profile image to documents directory
    private func saveProfileImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            print("❌ Failed to convert profile image to JPEG")
            return
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imageURL = documentsPath.appendingPathComponent("profileImage.jpg")
        
        do {
            try data.write(to: imageURL)
            profileImagePath = imageURL.path
            print("✅ Profile image saved to: \(imageURL.path)")
        } catch {
            print("❌ Failed to save profile image: \(error.localizedDescription)")
        }
    }
    
    /// Load profile image from documents directory
    private func loadProfileImage() {
        guard !profileImagePath.isEmpty else {
            print("ℹ️ No profile image path stored")
            return
        }
        
        let url = URL(fileURLWithPath: profileImagePath)
        
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            print("❌ Failed to load profile image from: \(profileImagePath)")
            return
        }
        
        profileImage = image
        print("✅ Profile image loaded from: \(profileImagePath)")
    }
    
    /// Delete profile image from documents directory
    private func deleteProfileImage() {
        guard !profileImagePath.isEmpty else { return }
        
        let url = URL(fileURLWithPath: profileImagePath)
        
        do {
            try FileManager.default.removeItem(at: url)
            print("✅ Profile image deleted")
        } catch {
            print("❌ Failed to delete profile image: \(error.localizedDescription)")
        }
        
        profileImagePath = ""
    }
    
    // MARK: - Validation Helpers
    
    /// Validate email format
    func validateEmail() -> Bool {
        guard !emailPrefix.isEmpty else { return false }
        
        // Basic validation: alphanumeric and common characters
        let emailRegex = "^[A-Za-z0-9._-]+$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: emailPrefix)
    }
    
    /// Extract email prefix from full email
    private func extractEmailPrefix(from email: String) -> String {
        guard email.contains("@") else { return email }
        return String(email.split(separator: "@").first ?? "")
    }
    
    /// Validate Instagram handle
    func validateInstagram() -> Bool {
        guard !instagramHandle.isEmpty else { return true } // Optional field
        
        // Instagram usernames: 1-30 characters, letters, numbers, periods, underscores
        let instagramRegex = "^[A-Za-z0-9._]{1,30}$"
        let instagramPredicate = NSPredicate(format: "SELF MATCHES %@", instagramRegex)
        return instagramPredicate.evaluate(with: instagramHandle)
    }
    
    /// Validate website URL
    func validateWebsite() -> Bool {
        guard !websiteURL.isEmpty else { return true } // Optional field
        
        if let url = URL(string: websiteURL) {
            return url.scheme != nil && url.host != nil
        }
        return false
    }
    
    // MARK: - User Projects
    
    /// Find all submissions associated with this user
    /// - Parameter store: Submission store to search
    /// - Returns: Array of submissions where user is credited
    func findUserProjects(in store: SubmissionStore_3_2) -> [Submission] {
        var projects: [Submission] = []
        let name = fullName
        
        guard !name.isEmpty else { return [] }
        
        // Search through all submissions (approved and pending)
        let allSubmissions = store.approvedSubmissions + store.submissions
        
        for submission in allSubmissions {
            // Check if name appears in submittedBy
            if submission.submittedBy == name {
                projects.append(submission)
                continue
            }
            
            // Check cast
            for entry in submission.orderedCast where entry.name == name {
                if !projects.contains(where: { $0.id == submission.id }) {
                    projects.append(submission)
                }
                break
            }
            
            // Check crew
            for entry in submission.orderedCrew where entry.name == name {
                if !projects.contains(where: { $0.id == submission.id }) {
                    projects.append(submission)
                }
                break
            }
            
            // Check recording (music)
            for entry in submission.orderedRecording where entry.name == name {
                if !projects.contains(where: { $0.id == submission.id }) {
                    projects.append(submission)
                }
                break
            }
            
            // Check production (music)
            for entry in submission.orderedProduction where entry.name == name {
                if !projects.contains(where: { $0.id == submission.id }) {
                    projects.append(submission)
                }
                break
            }
        }
        
        return projects
    }
    
    // MARK: - CloudKit Sync
    
    /// Save user profile to CloudKit
    func saveToCloudKit() async {
        print("🌐 ========================================")
        print("🌐 USER PROFILE CLOUDKIT SAVE")
        print("🌐 ========================================")
        print("🌐 User: \(fullName)")
        print("🌐 Roles: \(rolesString)")
        print("🌐 CloudKit Available: \(CloudKitManager.shared.isAvailable)")
        
        guard CloudKitManager.shared.isAvailable else {
            print("❌ ========================================")
            print("❌ CLOUDKIT NOT AVAILABLE")
            print("❌ ========================================")
            print("❌ Profile saved LOCALLY ONLY")
            print("❌ Other users will NOT see your profile")
            print("❌ ")
            print("❌ Possible reasons:")
            print("❌ 1. Not signed into iCloud")
            print("❌    → Go to Settings > [Your Name] > iCloud")
            print("❌ 2. No internet connection")
            print("❌ 3. CloudKit container not configured")
            print("❌ 4. iCloud Drive not enabled for this app")
            print("❌ ========================================")
            return
        }
        
        do {
            print("🔄 Creating CloudKit record...")
            let record = try await toCloudKitRecord()
            print("✅ Record created: \(record.recordID.recordName)")
            print("📤 Uploading to CloudKit...")
            try await CloudKitManager.shared.save(record: record)
            print("✅ ========================================")
            print("✅ USER PROFILE SAVED TO CLOUDKIT")
            print("✅ ========================================")
            print("✅ User: \(fullName)")
            print("✅ Record ID: \(record.recordID.recordName)")
            print("✅ Your profile is now visible to others")
            print("✅ ========================================")
        } catch let error as CKError {
            print("❌ ========================================")
            print("❌ CLOUDKIT ERROR")
            print("❌ ========================================")
            print("❌ User: \(fullName)")
            print("❌ Error Code: \(error.errorCode)")
            print("❌ Error: \(error.localizedDescription)")
            print("❌ ")
            
            switch error.code {
            case .networkUnavailable, .networkFailure:
                print("❌ Network issue - check internet connection")
            case .notAuthenticated:
                print("❌ Not signed into iCloud")
                print("❌ → Go to Settings > [Your Name] > iCloud")
            case .quotaExceeded:
                print("❌ iCloud storage quota exceeded")
            case .serverRecordChanged:
                print("❌ Record was modified elsewhere - retrying with update...")
                // Retry by fetching existing record and updating it
                await retryUpdateExistingRecord()
            case .unknownItem:
                print("❌ SCHEMA MISSING!")
                print("❌ → Create 'UserProfile' record type in CloudKit Dashboard")
                print("❌ → Add all required fields (firstName, lastName, etc.)")
            case .invalidArguments:
                print("❌ Invalid data in profile")
                print("❌ → Check that all fields are valid")
            default:
                print("❌ Unknown CloudKit error")
            }
            
            print("❌ ")
            print("❌ Profile saved locally only")
            print("❌ ========================================")
        } catch {
            print("❌ ========================================")
            print("❌ UNEXPECTED ERROR")
            print("❌ ========================================")
            print("❌ User: \(fullName)")
            print("❌ Error Type: \(type(of: error))")
            print("❌ Error: \(error.localizedDescription)")
            print("❌ Full Error: \(error)")
            print("❌ ========================================")
        }
    }
    
    /// Retry saving by updating existing record instead of creating new one
    private func retryUpdateExistingRecord() async {
        print("🔄 Attempting to update existing record...")
        
        do {
            guard let userRecordID = CloudKitManager.shared.userRecordID else {
                print("❌ No user record ID available for retry")
                return
            }
            
            let recordID = CKRecord.ID(recordName: "UserProfile_\(userRecordID.recordName)")
            let container = CKContainer.default()
            let database = container.publicCloudDatabase
            
            // Fetch existing record
            let existingRecord = try await database.record(for: recordID)
            
            // Update fields
            existingRecord["firstName"] = firstName as CKRecordValue
            existingRecord["lastName"] = lastName as CKRecordValue
            existingRecord["major"] = major as CKRecordValue
            existingRecord["minor"] = minor as CKRecordValue
            existingRecord["certificate"] = certificate as CKRecordValue
            existingRecord["graduationYear"] = graduationYear as CKRecordValue
            existingRecord["userTypes"] = rolesString as CKRecordValue
            existingRecord["bio"] = bio as CKRecordValue
            existingRecord["instagramHandle"] = instagramHandle as CKRecordValue
            existingRecord["websiteURL"] = websiteURL as CKRecordValue
            existingRecord["isUTStudent"] = (isUTStudent ? 1 : 0) as CKRecordValue
            existingRecord["school"] = school as CKRecordValue
            existingRecord["industry"] = industry as CKRecordValue
            existingRecord["company"] = company as CKRecordValue
            existingRecord["companyRole"] = companyRole as CKRecordValue
            existingRecord["isIndustryProfessional"] = (isIndustryProfessional ? 1 : 0) as CKRecordValue

            // Update profile image if exists
            if let profileImage = profileImage,
               let imageData = profileImage.jpegData(compressionQuality: 0.8) {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("profile_\(userRecordID.recordName).jpg")
                try imageData.write(to: tempURL)
                let asset = CKAsset(fileURL: tempURL)
                existingRecord["profileImage"] = asset
            }
            
            // Save updated record
            try await CloudKitManager.shared.save(record: existingRecord)
            
            print("✅ ========================================")
            print("✅ USER PROFILE UPDATED IN CLOUDKIT")
            print("✅ ========================================")
            print("✅ User: \(fullName)")
            print("✅ Record ID: \(existingRecord.recordID.recordName)")
            print("✅ Your profile is now visible to others")
            print("✅ ========================================")
        } catch {
            print("❌ Failed to update existing record: \(error.localizedDescription)")
        }
    }
    
    /// Load user profile from CloudKit
    func loadFromCloudKit() async {
        guard CloudKitManager.shared.isAvailable else {
            print("⚠️ CloudKit not available")
            return
        }
        
        do {
            // Fetch the user's profile using their record ID
            guard let userRecordID = CloudKitManager.shared.userRecordID else {
                print("⚠️ No user record ID available")
                return
            }
            
            let recordID = CKRecord.ID(recordName: "UserProfile_\(userRecordID.recordName)")
            let container = CKContainer.default()
            let database = container.publicCloudDatabase
            
            let record = try await database.record(for: recordID)
            await fromCloudKitRecord(record)
            
            print("✅ User profile loaded from CloudKit: \(fullName)")
        } catch {
            print("❌ Failed to load profile from CloudKit: \(error.localizedDescription)")
        }
    }
    
    /// Delete user profile from CloudKit
    func deleteFromCloudKit() async {
        guard CloudKitManager.shared.isAvailable else {
            print("⚠️ CloudKit not available")
            return
        }
        
        do {
            guard let userRecordID = CloudKitManager.shared.userRecordID else {
                print("⚠️ No user record ID available")
                return
            }
            
            let recordID = CKRecord.ID(recordName: "UserProfile_\(userRecordID.recordName)")
            try await CloudKitManager.shared.delete(recordID: recordID)
            
            print("✅ User profile deleted from CloudKit")
        } catch {
            print("❌ Failed to delete profile from CloudKit: \(error.localizedDescription)")
        }
    }
    
    // MARK: - CloudKit Conversion
    
    private func toCloudKitRecord() async throws -> CKRecord {
        guard let userRecordID = CloudKitManager.shared.userRecordID else {
            throw NSError(domain: "UserProfile", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user record ID"])
        }
        
        let recordID = CKRecord.ID(recordName: "UserProfile_\(userRecordID.recordName)")
        let record = CKRecord(recordType: "UserProfile", recordID: recordID)
        
        // Basic fields
        record["firstName"] = firstName as CKRecordValue
        record["lastName"] = lastName as CKRecordValue
        record["major"] = major as CKRecordValue
        record["minor"] = minor as CKRecordValue
        record["certificate"] = certificate as CKRecordValue
        record["graduationYear"] = graduationYear as CKRecordValue
        record["userTypes"] = rolesString as CKRecordValue
        record["bio"] = bio as CKRecordValue
        record["instagramHandle"] = instagramHandle as CKRecordValue
        record["websiteURL"] = websiteURL as CKRecordValue
        record["isUTStudent"] = (isUTStudent ? 1 : 0) as CKRecordValue
        record["school"] = school as CKRecordValue
        record["industry"] = industry as CKRecordValue
        record["company"] = company as CKRecordValue
        record["companyRole"] = companyRole as CKRecordValue
        record["isIndustryProfessional"] = (isIndustryProfessional ? 1 : 0) as CKRecordValue

        // Profile image
        if let profileImage = profileImage,
           let imageData = profileImage.jpegData(compressionQuality: 0.8) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("profile_\(userRecordID.recordName).jpg")
            try imageData.write(to: tempURL)
            let asset = CKAsset(fileURL: tempURL)
            record["profileImage"] = asset
        }
        
        return record
    }
    
    private func fromCloudKitRecord(_ record: CKRecord) async {
        await MainActor.run {
            firstName = (record["firstName"] as? String) ?? ""
            lastName = (record["lastName"] as? String) ?? ""
            major = (record["major"] as? String) ?? ""
            minor = (record["minor"] as? String) ?? ""
            certificate = (record["certificate"] as? String) ?? ""
            graduationYear = (record["graduationYear"] as? String) ?? "2026"
            bio = (record["bio"] as? String) ?? ""
            instagramHandle = (record["instagramHandle"] as? String) ?? ""
            websiteURL = (record["websiteURL"] as? String) ?? ""
            isUTStudent = ((record["isUTStudent"] as? Int) ?? 1) == 1
            school = (record["school"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UserProfileModel.utSchoolName
            industry = (record["industry"] as? String) ?? ""
            company = (record["company"] as? String) ?? ""
            companyRole = (record["companyRole"] as? String) ?? ""
            isIndustryProfessional = ((record["isIndustryProfessional"] as? Int) ?? 0) == 1

            // Parse user types
            let types = (record["userTypes"] as? String ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            userTypes = Set(types.compactMap { UserType(rawValue: $0) })
            
            // Load profile image
            if let asset = record["profileImage"] as? CKAsset,
               let fileURL = asset.fileURL,
               let imageData = try? Data(contentsOf: fileURL),
               let image = UIImage(data: imageData) {
                profileImage = image
                saveProfileImage(image)
            }
            
            // Update AppStorage
            save()
        }
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension UserProfileModel {
    /// Create a sample user profile for previews
    static var sample: UserProfileModel {
        let model = UserProfileModel()
        model.firstName = "John"
        model.lastName = "Doe"
        model.major = "Radio-Television-Film"
        model.minor = "Business"
        model.graduationYear = "2026"
        model.userTypes = [.director, .cinematographer, .editor]
        model.emailPrefix = "johndoe"
        model.bio = "Aspiring filmmaker with a passion for storytelling."
        model.instagramHandle = "johndoe_films"
        return model
    }
    
    /// Create an empty user profile for testing
    static var empty: UserProfileModel {
        UserProfileModel()
    }
}
#endif

// MARK: - Extensions

extension UserProfileModel {
    /// Get user's primary role (first selected role)
    var primaryRole: UserType? {
        userTypes.first
    }
    
    /// Check if user is a creator (has creative roles)
    var isCreator: Bool {
        let creativeRoles: Set<UserType> = [
            .director, .producer, .writer, .editor, .cinematographer,
            .photographer, .composer, .soundMixer, .animator, .vfxArtist,
            .graphicDesigner, .gameDesigner, .painter
        ]
        return !userTypes.intersection(creativeRoles).isEmpty
    }
    
    /// Check if user is a performer
    var isPerformer: Bool {
        let performerRoles: Set<UserType> = [.actor, .dancer, .singer, .musician]
        return !userTypes.intersection(performerRoles).isEmpty
    }
    
    /// Check if user is industry professional
    var isIndustryPro: Bool {
        let industryRoles: Set<UserType> = [.manager, .agent]
        return !userTypes.intersection(industryRoles).isEmpty
    }
    
    /// Check if user is enthusiast only
    var isEnthusiastOnly: Bool {
        userTypes == [.enthusiast]
    }
}
