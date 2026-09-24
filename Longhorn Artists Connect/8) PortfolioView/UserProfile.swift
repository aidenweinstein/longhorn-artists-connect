//
//  UserProfile.swift
//  Longhorn Artists Connect
//
//  The directory-facing user profile model, built from a CloudKit `DirectoryUser`
//  (see `UserProfileManager`). Consumed by the Portfolio, Home and Network pages.
//  Was previously misfiled in DirectoryView.swift, which declared no view.
//

import SwiftUI
import Combine

// MARK: - User Profile Model

struct UserProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var firstName: String
    var lastName: String
    var role: String // e.g., "Radio-Television-Film '25"
    var tags: [String] // Skills/interests
    var bio: String
    var major: String
    var minor: String
    var certificate: String
    var graduationYear: String
    var profileImageData: Data?
    var classOf: String // e.g., "2025"
    /// True for accounts created via the "I'm an Industry Professional" flow. These
    /// show Company Role • Company • Industry instead of academics.
    var isIndustryProfessional: Bool
    /// Industry-professional fields (industry replaces major, company replaces class,
    /// companyRole is new). Empty for student/guest accounts.
    var industry: String
    var company: String
    var companyRole: String

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    init(id: UUID = UUID(),
         firstName: String = "",
         lastName: String = "",
         role: String = "",
         tags: [String] = [],
         bio: String = "",
         major: String = "",
         minor: String = "",
         certificate: String = "",
         graduationYear: String = "",
         profileImageData: Data? = nil,
         classOf: String = "",
         isIndustryProfessional: Bool = false,
         industry: String = "",
         company: String = "",
         companyRole: String = "") {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.role = role
        self.tags = tags
        self.bio = bio
        self.major = major
        self.minor = minor
        self.certificate = certificate
        self.graduationYear = graduationYear
        self.profileImageData = profileImageData
        self.classOf = classOf
        self.isIndustryProfessional = isIndustryProfessional
        self.industry = industry
        self.company = company
        self.companyRole = companyRole
    }
}

extension UserProfile {
    /// Builds a directory `UserProfile` from a CloudKit `DirectoryUser` (the live
    /// directory model from `UserProfileManager`). Minor/certificate aren't carried
    /// on `DirectoryUser`, so they're left empty.
    init(directoryUser user: DirectoryUser) {
        self.init(
            id: UUID(uuidString: user.id) ?? UUID(),
            firstName: user.firstName,
            lastName: user.lastName,
            role: "\(user.major) '\(user.graduationYear)",
            tags: user.userTypes,
            bio: user.bio,
            major: user.major,
            minor: "",
            certificate: "",
            graduationYear: user.graduationYear,
            profileImageData: user.profileImageData,
            classOf: user.graduationYear,
            isIndustryProfessional: user.isIndustryProfessional,
            industry: user.industry,
            company: user.company,
            companyRole: user.companyRole
        )
    }
}
