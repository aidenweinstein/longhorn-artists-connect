//
//  MockCloudKitManager.swift
//  Longhorn Artists Connect
//
//  Created for Preview Testing
//

import CloudKit
import SwiftUI
import Observation

#if DEBUG

/// A mock CloudKit manager for SwiftUI previews and testing
@MainActor
@Observable
class MockCloudKitManager {
    static let shared = MockCloudKitManager()
    
    var isAvailable = true
    var userRecordID: CKRecord.ID? = CKRecord.ID(recordName: "mock_user_123")
    
    // In-memory storage for testing
    private var mockRecords: [String: [CKRecord]] = [:]
    private var mockSubmissions: [Submission] = []
    
    private init() {
        // Pre-populate with sample data
        setupMockData()
    }
    
    // MARK: - Mock Setup
    
    private func setupMockData() {
        // Create some sample submissions
        var filmSubmission = Submission(
            id: UUID(),
            type: .film,
            title: "Short Film: The Journey",
            details: "A heartwarming story about finding yourself."
        )
        filmSubmission.isApproved = true
        filmSubmission.submittedBy = "Test User"
        filmSubmission.logline = "A college student discovers the true meaning of friendship."
        filmSubmission.genres = ["Drama", "Coming of Age"]
        
        var musicSubmission = Submission(
            id: UUID(),
            type: .music,
            title: "New Single: Sunset Dreams",
            details: "My latest track, inspired by Austin sunsets."
        )
        musicSubmission.isApproved = true
        musicSubmission.submittedBy = "Music Artist"
        musicSubmission.artist = "DJ Longhorn"
        
        var eventSubmission = Submission(
            id: UUID(),
            type: .event,
            title: "Film Screening @ Texas Union",
            details: "Join us for a screening of student films."
        )
        eventSubmission.isApproved = true
        eventSubmission.submittedBy = "Event Organizer"
        eventSubmission.eventStartDate = Date().addingTimeInterval(86400 * 7) // 1 week from now
        eventSubmission.eventLocation = "Texas Union Theater, 2201 Guadalupe St, Austin, TX 78705"
        eventSubmission.eventHost = "UT Film Society"
        eventSubmission.eventTicketsURL = "https://utexas.edu/tickets"
        eventSubmission.logline = "An evening celebrating the best student films of the semester with Q&A sessions featuring the filmmakers."
        
        var projectSubmission = Submission(
            id: UUID(),
            type: .project,
            title: "Indie Feature: Breaking Dawn",
            details: "A psychological thriller about identity and memory."
        )
        projectSubmission.isApproved = true
        projectSubmission.submittedBy = "Director Jane Smith"
        projectSubmission.logline = "When a neuroscientist wakes up with no memory, she must piece together clues from her fragmented past before time runs out."
        projectSubmission.shootDates = "August 15-30, 2026"
        projectSubmission.expectedReleaseDate = "Spring 2027"
        projectSubmission.castNeeded = ["Lead Actor (20s-30s)", "Supporting Actor (40s-50s)"]
        projectSubmission.crewNeeded = ["Director of Photography", "Sound Designer", "Production Assistant"]
        
        mockSubmissions = [filmSubmission, musicSubmission, eventSubmission, projectSubmission]
        print("✅ MockCloudKitManager initialized with \(mockSubmissions.count) sample submissions")
    }
    
    // MARK: - Mock Methods
    
    func checkAvailability() async {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        isAvailable = true
        print("✅ [MOCK] CloudKit available")
    }
    
    func save(record: CKRecord) async throws {
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        print("✅ [MOCK] Saved record: \(record.recordType)")
    }
    
    func fetchRecords(ofType recordType: String, sortBy sortKey: String? = nil) async throws -> [CKRecord] {
        try? await Task.sleep(nanoseconds: 300_000_000)
        print("✅ [MOCK] Fetched records of type: \(recordType)")
        return []
    }
    
    func fetchRecord(withID recordID: CKRecord.ID) async throws -> CKRecord {
        try? await Task.sleep(nanoseconds: 200_000_000)
        let record = CKRecord(recordType: "Submission", recordID: recordID)
        return record
    }
    
    func delete(recordID: CKRecord.ID) async throws {
        try? await Task.sleep(nanoseconds: 200_000_000)
        mockSubmissions.removeAll { $0.id.uuidString == recordID.recordName }
        print("✅ [MOCK] Deleted record: \(recordID.recordName)")
    }
    
    func fetchRecords(ofType recordType: String, matching predicate: NSPredicate, sortBy sortKey: String? = nil) async throws -> [CKRecord] {
        try? await Task.sleep(nanoseconds: 300_000_000)
        print("✅ [MOCK] Fetched records with predicate")
        return []
    }
    
    func subscribeToRecordType(_ recordType: String, subscriptionID: String) async throws {
        print("✅ [MOCK] Subscribed to \(recordType)")
    }
    
    func setupAutomaticSync() async {
        print("✅ [MOCK] Automatic sync enabled")
    }
    
    // MARK: - Submission Methods
    
    func saveSubmission(_ submission: Submission) async throws {
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Add to mock storage
        if let index = mockSubmissions.firstIndex(where: { $0.id == submission.id }) {
            mockSubmissions[index] = submission
            print("✅ [MOCK] Updated submission: \(submission.title)")
        } else {
            mockSubmissions.append(submission)
            print("✅ [MOCK] Saved new submission: \(submission.title)")
        }
    }
    
    func fetchAllApprovedSubmissions() async throws -> [Submission] {
        try? await Task.sleep(nanoseconds: 400_000_000)
        let approved = mockSubmissions.filter { $0.isApproved }
        print("✅ [MOCK] Fetched \(approved.count) approved submissions")
        return approved
    }
    
    func fetchAllSubmissions() async throws -> [Submission] {
        try? await Task.sleep(nanoseconds: 400_000_000)
        print("✅ [MOCK] Fetched \(mockSubmissions.count) total submissions")
        return mockSubmissions
    }
    
    func updateSubmissionApproval(submissionId: String, isApproved: Bool) async throws {
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        if let index = mockSubmissions.firstIndex(where: { $0.id.uuidString == submissionId }) {
            mockSubmissions[index].isApproved = isApproved
            print("✅ [MOCK] Updated approval status for: \(mockSubmissions[index].title)")
        }
    }
    
    func deleteSubmission(_ submission: Submission) async throws {
        try? await Task.sleep(nanoseconds: 300_000_000)
        mockSubmissions.removeAll { $0.id == submission.id }
        print("✅ [MOCK] Deleted submission: \(submission.title)")
    }
    
    // MARK: - Test Helpers
    
    /// Add a submission directly to mock storage (for testing)
    func addMockSubmission(_ submission: Submission) {
        mockSubmissions.append(submission)
    }
    
    /// Clear all mock data
    func clearMockData() {
        mockSubmissions.removeAll()
        mockRecords.removeAll()
    }
    
    /// Reset to initial state
    func resetMockData() {
        clearMockData()
        setupMockData()
    }
}

#endif
