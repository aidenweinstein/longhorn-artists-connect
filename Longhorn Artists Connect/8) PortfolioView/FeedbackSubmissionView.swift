//
//  FeedbackSubmissionView.swift
//  Longhorn Artists Connect
//
//  Feedback submission view for users to send suggestions/bug reports
//

import SwiftUI

struct FeedbackSubmissionView: View {
    @State private var feedbackText = ""
    @State private var feedbackCategory: FeedbackCategory = .general
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    
    enum FeedbackCategory: String, CaseIterable, Identifiable {
        case bug = "Bug Report"
        case feature = "Feature Request"
        case general = "General Feedback"
        case question = "Question"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .bug: return "ladybug"
            case .feature: return "lightbulb"
            case .general: return "bubble.left.and.bubble.right"
            case .question: return "questionmark.circle"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Share your thoughts")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Tell us about bugs, feature requests, or general feedback. Your input helps us improve Nexus!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Category picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Category")
                            .font(.headline)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(FeedbackCategory.allCases) { category in
                                    Button {
                                        feedbackCategory = category
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: category.icon)
                                                .font(.subheadline)
                                            Text(category.rawValue)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                        }
                                        .foregroundStyle(feedbackCategory == category ? .white : .primary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(
                                            Capsule()
                                                .fill(feedbackCategory == category ? Color.brandOrange : Color.secondary.opacity(0.15))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    
                    // Feedback text editor
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Feedback")
                            .font(.headline)
                        
                        ZStack(alignment: .topLeading) {
                            if feedbackText.isEmpty {
                                Text("Share your thoughts here...")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            
                            TextEditor(text: $feedbackText)
                                .frame(minHeight: 200)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    
                    // Info text
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Your feedback will be sent to the moderators. We read every submission!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
                .padding()
            }
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        submitFeedback()
                    }
                    .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func submitFeedback() {
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let userName = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        
        // Create a feedback entry
        // For now, we can add this to the history as a special type
        // In a real implementation, you'd want a separate feedback storage system
        let feedbackEntry = HistoryEntry(
            action: .submitted, // Using submitted as placeholder
            submissionId: UUID(), // Dummy ID
            submissionTitle: "[\(feedbackCategory.rawValue)] \(feedbackText.prefix(50))...",
            submissionType: .project, // Placeholder type
            performedBy: userName
        )
        
        // TODO: Implement proper feedback storage
        // For now, just dismiss
        // You could add to a separate feedbackSubmissions array in SubmissionStore
        
        print("📝 Feedback submitted by \(userName):")
        print("   Category: \(feedbackCategory.rawValue)")
        print("   Feedback: \(feedbackText)")
        
        dismiss()
    }
}

#Preview {
    FeedbackSubmissionView()
}
