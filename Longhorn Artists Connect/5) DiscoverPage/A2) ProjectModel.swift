//
//  ProjectModel.swift
//  Longhorn Artists Connect
//
//  Created by Aiden Weinstein on 2/12/26.
//
//  Backend logic for project submissions - handles cast/crew calls, applications, and project management
//

import Foundation
import SwiftUI
import Combine

@MainActor
class ProjectModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isLoading = true
    @Published var contentLoaded = false
    @Published var showFullScreenPoster = false
    @Published var selectedCastRole: String?
    @Published var selectedCrewRole: String?
    @Published var showAuditionSheet = false
    @Published var showApplySheet = false
    
    // MARK: - Dependencies
    let project: Submission
    let store: SubmissionStore_3_2
    
    // MARK: - Initialization
    init(project: Submission, store: SubmissionStore_3_2 = .shared) {
        self.project = project
        self.store = store
    }
    
    // MARK: - Permissions
    
    /// Check if the current user can edit or delete this project
    var canEditOrDelete: Bool {
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        let isUserCreator = !currentUser.isEmpty && currentUser == project.submittedBy
        
        let isModeratorMode = UserDefaults.standard.bool(forKey: "isModeratorMode")
        let isAidenWeinstein = currentUser == "Aiden Weinstein"
        let canUseModerator = isModeratorMode && isAidenWeinstein
        
        return isUserCreator || canUseModerator
    }
    
    /// Check if moderator info should be shown
    var shouldShowModeratorInfo: Bool {
        guard UserDefaults.standard.bool(forKey: "isModeratorMode") else { return false }
        
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        
        return currentUser == "Aiden Weinstein"
    }
    
    // MARK: - Project Status
    
    /// Check if project has open cast positions
    var hasCastCallOpen: Bool {
        !project.castNeeded.isEmpty
    }
    
    /// Check if project has open crew positions
    var hasCrewCallOpen: Bool {
        !project.crewNeeded.isEmpty
    }
    
    /// Check if any positions are open
    var hasOpenPositions: Bool {
        hasCastCallOpen || hasCrewCallOpen
    }
    
    /// Check if cast and crew are fully assembled
    var isFullyAssembled: Bool {
        !hasOpenPositions
    }
    
    /// Get total number of open positions
    var openPositionsCount: Int {
        project.castNeeded.count + project.crewNeeded.count
    }
    
    /// Get status message for project
    var statusMessage: String {
        if isFullyAssembled {
            return "Cast & Crew Assembled"
        } else if hasCastCallOpen && hasCrewCallOpen {
            return "Cast & Crew Needed"
        } else if hasCastCallOpen {
            return "Cast Needed"
        } else if hasCrewCallOpen {
            return "Crew Needed"
        } else {
            return "Open Project"
        }
    }
    
    // MARK: - Date Handling
    
    /// Get formatted shoot dates (without year)
    var formattedShootDates: String {
        guard !project.shootDates.isEmpty else { return "" }
        return removeYear(from: project.shootDates)
    }
    
    /// Remove year from date string
    private func removeYear(from dateString: String) -> String {
        var result = dateString
        let yearPattern = try? NSRegularExpression(pattern: "\\b\\d{4}\\b", options: [])
        if let pattern = yearPattern {
            let range = NSRange(dateString.startIndex..., in: dateString)
            result = pattern.stringByReplacingMatches(in: dateString, range: range, withTemplate: "")
        }
        // Clean up extra spaces, commas, and dashes
        result = result.replacingOccurrences(of: "  ", with: " ")
        result = result.replacingOccurrences(of: ", ,", with: "")
        result = result.replacingOccurrences(of: ",,", with: "")
        result = result.replacingOccurrences(of: ", -", with: " -")
        result = result.replacingOccurrences(of: "- ", with: "-")
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: ", -"))
        return result
    }
    
    /// Check if shoot dates are in the past
    var hasShootDatePassed: Bool {
        // TODO: Implement proper date parsing when shoot dates are stored as Date objects
        return false
    }
    
    // MARK: - Cast & Crew Management
    
    /// Get list of all cast roles (both open and filled)
    var allCastRoles: [String] {
        var roles: [String] = []
        roles.append(contentsOf: project.castNeeded)
        roles.append(contentsOf: project.orderedCast.map { $0.role })
        return roles
    }
    
    /// Get list of all crew roles (both open and filled)
    var allCrewRoles: [String] {
        var roles: [String] = []
        roles.append(contentsOf: project.crewNeeded)
        roles.append(contentsOf: project.orderedCrew.map { $0.role })
        return roles
    }
    
    /// Consolidate crew members who have multiple roles
    func consolidatedCrew(_ crew: [OrderedEntry]) -> [(name: String, roles: [String])] {
        var grouped: [String: [String]] = [:]
        var order: [String] = []
        
        for entry in crew {
            if grouped[entry.name] == nil {
                order.append(entry.name)
                grouped[entry.name] = []
            }
            grouped[entry.name]?.append(entry.role)
        }
        
        return order.map { name in
            (name: name, roles: grouped[name] ?? [])
        }
    }
    
    /// Get consolidated crew for display
    var consolidatedProjectCrew: [(name: String, roles: [String])] {
        consolidatedCrew(project.orderedCrew)
    }
    
    // MARK: - Application Handling
    
    /// Apply for a cast role
    func applyForCastRole(_ role: String) {
        selectedCastRole = role
        showAuditionSheet = true
    }
    
    /// Apply for a crew role
    func applyForCrewRole(_ role: String) {
        selectedCrewRole = role
        showApplySheet = true
    }
    
    /// Submit audition application
    func submitAudition(roleName: String, message: String) {
        // TODO: Implement backend submission to project creator
        print("📬 Audition submitted for \(project.title)")
        print("   Role: \(roleName)")
        print("   Message: \(message)")
        
        // Close the sheet
        showAuditionSheet = false
        selectedCastRole = nil
    }
    
    /// Submit crew application
    func submitCrewApplication(roleName: String, message: String) {
        // TODO: Implement backend submission to project creator
        print("📬 Crew application submitted for \(project.title)")
        print("   Position: \(roleName)")
        print("   Message: \(message)")
        
        // Close the sheet
        showApplySheet = false
        selectedCrewRole = nil
    }
    
    // MARK: - User Interactions
    
    /// Toggle like status for this project
    func toggleLike() {
        store.toggleLike(for: project)
    }
    
    /// Check if this project is liked
    func isLiked() -> Bool {
        store.isLiked(project)
    }
    
    /// Check if this project is in any collection
    func isInAnyCollection() -> Bool {
        store.isInAnyCollection(project)
    }
    
    /// Delete this project
    func delete() {
        store.delete(project)
    }
    
    /// Update this project
    func update(_ updated: Submission) {
        store.update(updated)
    }
    
    // MARK: - Portfolio/Invite
    
    /// Show portfolio or invite for a user
    func showPortfolioOrInvite(for name: String) {
        // TODO: Check if user exists in the system
        // For now, show an alert with invite option
        let alert = UIAlertController(
            title: "Invite \(name) to Nexus",
            message: "Would you like to invite \(name) to join Nexus?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Invite", style: .default) { _ in
            // TODO: Send invitation
            print("Inviting \(name) to Nexus")
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    // MARK: - Sharing
    
    /// Get shareable project info
    func getShareableInfo() -> String {
        var info = project.title
        
        if !project.logline.isEmpty {
            info += "\n\(project.logline)"
        }
        
        if !project.shootDates.isEmpty {
            info += "\nShooting: \(project.shootDates)"
        }
        
        if !project.expectedReleaseDate.isEmpty {
            info += "\nRelease: \(project.expectedReleaseDate)"
        }
        
        if hasOpenPositions {
            info += "\n\nLooking for:"
            if hasCastCallOpen {
                info += "\nCast: \(project.castNeeded.joined(separator: ", "))"
            }
            if hasCrewCallOpen {
                info += "\nCrew: \(project.crewNeeded.joined(separator: ", "))"
            }
        }
        
        return info
    }
    
    /// Share project via iOS share sheet
    func shareProject() {
        let shareText = getShareableInfo()
        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
    
    // MARK: - Loading State
    
    /// Simulate loading with delay
    func simulateLoading(delay: TimeInterval = 0.3) async {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        isLoading = false
        contentLoaded = true
    }
    
    // MARK: - Color Utilities
    
    /// Generate a consistent tint color based on title hash
    var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(project.title.hashValue)
        return colors[hash % colors.count]
    }
    
    // MARK: - Project Type Info
    
    /// Get project type/genre display text
    var genreDisplay: String {
        guard !project.genres.isEmpty else { return "" }
        return project.genres.joined(separator: ", ")
    }
    
    /// Check if project has age rating
    var hasAgeRating: Bool {
        !project.ageRating.isEmpty
    }
    
    /// Check if project has poster/thumbnail
    var hasPoster: Bool {
        project.thumbnailData != nil
    }
}
