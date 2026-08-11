//  DirectoryView.swift
//  Longhorn Artists Connect
//
//  Created by Feature Implementation from Sketches
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
         classOf: String = "") {
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
            classOf: user.graduationYear
        )
    }
}
