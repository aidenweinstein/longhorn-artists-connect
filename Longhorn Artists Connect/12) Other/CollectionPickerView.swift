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
    
    @State private var newCollectionName = ""
    @FocusState private var newCollectionFieldFocused: Bool

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
                
                // Inline "New Collection" row: type a name right here and hit return (or
                // the Add button) to create the collection and add this post to it — no popup.
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.brandOrange) // ⚙️ New collection icon color
                    TextField("New Collection", text: $newCollectionName, axis: .vertical) // ⚙️ New collection placeholder
                        .textFieldStyle(.plain)
                        .focused($newCollectionFieldFocused)
                        .submitLabel(.done)
                        .onSubmit(createNewCollection)
                    if !newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Add", action: createNewCollection) // ⚙️ Add collection button
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.brandOrange) // ⚙️ Add collection button color
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGray6))
            .navigationTitle("Save") // ⚙️ Navigation title
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large]) // ⚙️ Sheet sizes
        .presentationDragIndicator(.hidden)
    }

    /// Creates a collection from the inline text field and adds the current post to it.
    private func createNewCollection() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let collection = store.createCollection(name: trimmed)
        store.addToCollection(submissionId: post.id, collectionId: collection.id)
        newCollectionName = ""
        newCollectionFieldFocused = false
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
