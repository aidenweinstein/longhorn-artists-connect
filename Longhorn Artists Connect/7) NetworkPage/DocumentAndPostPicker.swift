//
//  DocumentAndPostPicker.swift
//  Longhorn Artists Connect
//
//  The two attachment pickers used when adding content to a NetworkView
//  conversation: `NetworkDocumentPicker` (a UIDocumentPickerViewController
//  bridge for files) and `SavedPostsPickerView` (pick one of your own posts).
//  Split out of NetworkView.swift to keep that file (and its preview) lightweight.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Network Document Picker

struct NetworkDocumentPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .data, .pdf, .image, .movie], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: NetworkDocumentPicker
        
        init(_ parent: NetworkDocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            print("📄 File selected: \(url.lastPathComponent)")
            // TODO: Send the file in a message
            parent.dismiss()
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

// MARK: - Saved Posts Picker View

struct SavedPostsPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @State private var selectedSubmission: Submission?
    
    // Get the "Liked" collection
    private var likedCollection: PostCollection? {
        store.collections.first { $0.isSystemCollection && $0.name == "Liked" }
    }
    
    // Get all saved submissions
    private var savedSubmissions: [Submission] {
        guard let likedCollection = likedCollection else { return [] }
        return store.getSubmissions(for: likedCollection)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Title
                Text("Saved Posts")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(.bottom, 8)
                
                Divider()
                
                if savedSubmissions.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Spacer()
                        
                        Image(systemName: "bookmark")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                        
                        Text("No Saved Posts")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Text("Like posts to save them and share in messages")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Spacer()
                    }
                } else {
                    // List of saved posts
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(savedSubmissions) { submission in
                                Button {
                                    selectedSubmission = submission
                                } label: {
                                    SavedPostRow(submission: submission)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled(false)
        }
        .alert("Send Post?", isPresented: Binding(
            get: { selectedSubmission != nil },
            set: { if !$0 { selectedSubmission = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                selectedSubmission = nil
            }
            Button("Send") {
                if let submission = selectedSubmission {
                    print("📤 Sending saved post: \(submission.title)")
                    // TODO: Actually send the post in a message
                    dismiss()
                }
            }
        } message: {
            if let submission = selectedSubmission {
                Text("Share \"\(submission.title)\" in this conversation?")
            }
        }
    }
}

// MARK: - Saved Post Row

struct SavedPostRow: View {
    let submission: Submission
    
    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(submission.title.hashValue)
        return colors[hash % colors.count]
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumbnailData = submission.thumbnailData,
               let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: submission.type == .film ? "film" : submission.type == .music ? "music.note" : "star.fill")
                            .foregroundStyle(.white.opacity(0.8))
                    )
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(submission.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                Text("by \(submission.submittedBy)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                // Type badge
                Text(submission.type.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tintColor.opacity(0.2))
                    .foregroundStyle(tintColor)
                    .clipShape(Capsule())
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
