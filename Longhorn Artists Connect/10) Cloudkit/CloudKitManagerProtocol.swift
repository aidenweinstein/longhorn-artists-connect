//
//  CloudKitManagerProtocol.swift
//  Longhorn Artists Connect
//
//  Protocol for CloudKit operations (supports both real and mock implementations)
//

import CloudKit
import SwiftUI
import Combine

/// Protocol that defines CloudKit operations
/// Implemented by both CloudKitManager and MockCloudKitManager
@MainActor
protocol CloudKitManagerProtocol: ObservableObject {
    var isAvailable: Bool { get set }
    var userRecordID: CKRecord.ID? { get set }
    
    // Core operations
    func checkAvailability() async
    func save(record: CKRecord) async throws
    func fetchRecords(ofType recordType: String, sortBy sortKey: String?) async throws -> [CKRecord]
    func fetchRecord(withID recordID: CKRecord.ID) async throws -> CKRecord
    func delete(recordID: CKRecord.ID) async throws
    func fetchRecords(ofType recordType: String, matching predicate: NSPredicate, sortBy sortKey: String?) async throws -> [CKRecord]
    func subscribeToRecordType(_ recordType: String, subscriptionID: String) async throws
    func setupAutomaticSync() async
    
    // Submission operations
    func saveSubmission(_ submission: Submission) async throws
    func fetchAllApprovedSubmissions() async throws -> [Submission]
    func fetchAllSubmissions() async throws -> [Submission]
    func updateSubmissionApproval(submissionId: String, isApproved: Bool) async throws
    func deleteSubmission(_ submission: Submission) async throws
}

// MARK: - CloudKitManager Conformance

extension CloudKitManager: CloudKitManagerProtocol {
    // Already implements all required methods
}

#if DEBUG
// MARK: - MockCloudKitManager Conformance

extension MockCloudKitManager: CloudKitManagerProtocol {
    // Already implements all required methods
}
#endif
