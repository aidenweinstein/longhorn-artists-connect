//
//  CollectionPickerView-9)Supporting.swift
//  Longhorn Artists Connect
//
//  View for adding submissions to collections
//

import SwiftUI

// MARK: - Collection Picker View

struct CollectionPickerView: View {
    let post: Submission
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var showNewCollectionSheet = false
    @State private var newCollectionName = ""
    
    // Convenience initializer to support different parameter names
    init(post: Submission) {
        self.post = post
    }
    
    init(submission: Submission) {
        self.post = submission
    }
    
    var body: some View {
        NavigationStack {
            List {
                let userCollections = store.collections.filter { !$0.isSystemCollection }
                ForEach(userCollections) { collection in
                    Button {
                        toggleCollection(collection)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) { // ⚙️ Collection info spacing
                                Text(collection.name)
                                    .font(.headline) // ⚙️ Collection name font
                                    .foregroundStyle(.primary) // ⚙️ Collection name color
                                Text("\(collection.submissionIds.count) items") // ⚙️ Item count format
                                    .font(.caption) // ⚙️ Item count font
                                    .foregroundStyle(.secondary) // ⚙️ Item count color
                            }
                            
                            Spacer()
                            
                            if collection.submissionIds.contains(post.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.brandOrange) // ⚙️ Selected collection color
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary) // ⚙️ Unselected collection color
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            store.deleteCollection(collection)
                        } label: {
                            Label("Delete", systemImage: "trash") // ⚙️ Delete button label
                        }
                    }
                }
                
                Button {
                    showNewCollectionSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.brandOrange) // ⚙️ New collection icon color
                        Text("New Collection") // ⚙️ New collection button text
                            .foregroundStyle(Color.brandOrange) // ⚙️ New collection text color
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGray6))
            .navigationTitle("Save") // ⚙️ Navigation title
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("New Collection", isPresented: $showNewCollectionSheet) { // ⚙️ Alert title
            TextField("Collection Name", text: $newCollectionName) // ⚙️ TextField placeholder
            Button("Cancel", role: .cancel) { // ⚙️ Cancel button text
                newCollectionName = ""
            }
            Button("Create") { // ⚙️ Create button text
                if !newCollectionName.isEmpty {
                    let collection = store.createCollection(name: newCollectionName)
                    store.addToCollection(submissionId: post.id, collectionId: collection.id)
                    newCollectionName = ""
                }
            }
        } message: {
            Text("Enter a name for your new collection") // ⚙️ Alert message
        }
        .presentationDetents([.medium, .large]) // ⚙️ Sheet sizes
    }
    
    private func toggleCollection(_ collection: PostCollection) {
        if collection.submissionIds.contains(post.id) {
            store.removeFromCollection(submissionId: post.id, collectionId: collection.id)
        } else {
            store.addToCollection(submissionId: post.id, collectionId: collection.id)
        }
    }
}

// MARK: - Preview

#Preview {
    CollectionPickerView(
        post: Submission(id: UUID(), type: .film, title: "Sample Film", details: "A great movie")
    )
}
