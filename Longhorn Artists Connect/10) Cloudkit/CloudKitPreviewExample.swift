//
//  CloudKitPreviewExample.swift
//  Longhorn Artists Connect
//
//  Example view showing how to test CloudKit functionality in Canvas
//

import SwiftUI
import CloudKit

#if DEBUG

/// Example view for testing CloudKit operations in Canvas
struct CloudKitPreviewExample: View {
    @StateObject private var mockManager = MockCloudKitManager.shared
    @State private var submissions: [Submission] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            List {
                Section("CloudKit Status") {
                    HStack {
                        Text("Available")
                        Spacer()
                        Image(systemName: mockManager.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(mockManager.isAvailable ? .green : .red)
                    }
                    
                    if let userID = mockManager.userRecordID?.recordName {
                        Text("User ID: \(userID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Actions") {
                    Button("Fetch Approved Submissions") {
                        Task {
                            await fetchApprovedSubmissions()
                        }
                    }
                    
                    Button("Fetch All Submissions") {
                        Task {
                            await fetchAllSubmissions()
                        }
                    }
                    
                    Button("Create Test Submission") {
                        Task {
                            await createTestSubmission()
                        }
                    }
                    
                    Button("Reset Mock Data") {
                        mockManager.resetMockData()
                        submissions = []
                    }
                }
                
                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                
                if let error = errorMessage {
                    Section("Error") {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                
                Section("Results (\(submissions.count))") {
                    if submissions.isEmpty {
                        Text("No submissions loaded")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(submissions) { submission in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(submission.title)
                                    .font(.headline)
                                
                                HStack {
                                    Text(submission.type.rawValue)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.brandOrange.opacity(0.2))
                                        .clipShape(Capsule())
                                    
                                    if submission.isApproved {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .font(.caption)
                                    } else {
                                        Image(systemName: "clock.fill")
                                            .foregroundStyle(.orange)
                                            .font(.caption)
                                    }
                                    
                                    Spacer()
                                }
                                
                                Text(submission.submittedBy)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("CloudKit Testing")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - CloudKit Test Methods
    
    private func fetchApprovedSubmissions() async {
        isLoading = true
        errorMessage = nil
        
        do {
            submissions = try await mockManager.fetchAllApprovedSubmissions()
            print("✅ Fetched \(submissions.count) approved submissions")
        } catch {
            errorMessage = "Failed to fetch: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func fetchAllSubmissions() async {
        isLoading = true
        errorMessage = nil
        
        do {
            submissions = try await mockManager.fetchAllSubmissions()
            print("✅ Fetched \(submissions.count) total submissions")
        } catch {
            errorMessage = "Failed to fetch: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func createTestSubmission() async {
        isLoading = true
        errorMessage = nil
        
        do {
            var newSubmission = Submission(
                id: UUID(),
                type: .film,
                title: "Test Film \(Date().formatted(date: .omitted, time: .shortened))",
                details: "This is a test submission created in Canvas preview."
            )
            newSubmission.isApproved = false
            newSubmission.submittedBy = "Canvas Tester"
            
            try await mockManager.saveSubmission(newSubmission)
            
            // Refresh the list
            submissions = try await mockManager.fetchAllSubmissions()
            print("✅ Created test submission: \(newSubmission.title)")
        } catch {
            errorMessage = "Failed to create: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

// MARK: - Preview

#Preview("CloudKit Testing") {
    CloudKitPreviewExample()
}

#Preview("With Dark Mode") {
    CloudKitPreviewExample()
        .preferredColorScheme(.dark)
}

#Preview("Multiple Submissions") {
    CloudKitPreviewExample()
        .onAppear {
            // Pre-populate with sample data
            let mock = MockCloudKitManager.shared
            mock.resetMockData()
            
            // Add extra submissions
            for i in 1...5 {
                var submission = Submission(
                    id: UUID(),
                    type: [MediaType.film, .music, .event, .project, .reel].randomElement()!,
                    title: "Sample Submission \(i)",
                    details: "Details for sample \(i)"
                )
                submission.isApproved = Bool.random()
                submission.submittedBy = "Preview User \(i)"
                mock.addMockSubmission(submission)
            }
        }
}

#endif
