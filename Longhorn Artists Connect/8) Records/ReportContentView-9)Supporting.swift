//
//  ReportContentView-9)Supporting.swift
//  Longhorn Artists Connect
//
//  View for reporting inappropriate content
//

import SwiftUI

// MARK: - Report Content View

struct ReportContentView: View {
    let post: Submission
    @Environment(\.dismiss) private var dismiss
    
    @State private var reasoningText: String = ""
    @State private var showSuccessAlert = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section("Reasoning") { // ⚙️ Section title
                        TextEditor(text: $reasoningText)
                            .frame(height: 150) // ⚙️ Fixed reasoning editor height
                    }
                }
                .scrollContentBackground(.hidden)

                Button {
                    submitReport()
                } label: {
                    Label("Submit", systemImage: "flag.fill") // ⚙️ Submit button text
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(reasoningText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal)
                .padding(.vertical)
            }
            .background(Color(.systemGray6))
            .navigationTitle("Flag") // ⚙️ Navigation title
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium]) // ⚙️ Sheet size - locked to half page
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
        .alert("Flag Submitted", isPresented: $showSuccessAlert) { // ⚙️ Success alert title
            Button("OK", role: .cancel) { // ⚙️ Alert button text
                dismiss()
            }
        } message: {
            Text("Thank you for helping keep our community safe. We will review this report.") // ⚙️ Success message
        }
    }
    
    private func submitReport() {
        let trimmedReasoning = reasoningText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReasoning.isEmpty else { return }
        
        // TODO: Send report to backend/moderation system
        print("Report submitted for post: \(post.title)")
        print("Reasoning: \(trimmedReasoning)")
        
        showSuccessAlert = true
    }
}

// MARK: - Preview

#Preview {
    ReportContentView(
        post: Submission(id: UUID(), type: .film, title: "Sample Film", details: "A great movie")
    )
}
