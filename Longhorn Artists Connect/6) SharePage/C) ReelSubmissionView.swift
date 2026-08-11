//
//  ReelSubmissionView.swift
//  Longhorn Artists Connect
//
//  Reel submission form - showcase reels with video, experience, and skills
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ReelSubmissionView: View {
    @Binding var title: String
    @Binding var reelType: String
    @Binding var reelDescription: String
    @Binding var selectedReelVideoURL: URL?
    @Binding var reelVideoThumbnail: UIImage?
    @Binding var reelVideoLoadError: Bool
    @Binding var isUploadingReelVideo: Bool
    @Binding var showReelVideoPicker: Bool
    @Binding var showReelDocumentPicker: Bool
    @Binding var showReelThumbnailPicker: Bool

    /// Live CloudKit upload state, set once the post is submitted.
    var uploadPhase: MediaUploadPhase? = nil
    var onRetryUpload: () -> Void = {}

    @State private var showThumbnailPhotoPicker = false
    @State private var thumbnailPhotoItem: PhotosPickerItem?
    @State private var showThumbnailDocumentPicker = false
    
    var body: some View {
        List {
            Section("Upload") {
                reelUploadSection
            }
            
            Section("Details") {
                TextField("Title", text: $title, axis: .vertical)

                TextField("Description", text: $reelDescription, axis: .vertical)
                    .lineLimit(4, reservesSpace: true)

                Menu {
                    ForEach(["Acting", "Cinematography", "Editing", "Directing", "Music/Sound", "Other"], id: \.self) { type in
                        Button {
                            reelType = type
                        } label: {
                            HStack {
                                Text(type)
                                if reelType == type {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Type")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(reelType.isEmpty ? "Select" : reelType)
                            .foregroundStyle(Color.brandOrange)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(Color.brandOrange)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGray6))
        .photosPicker(isPresented: $showThumbnailPhotoPicker, selection: $thumbnailPhotoItem, matching: .images)
        .onChange(of: thumbnailPhotoItem) { _, newItem in
            loadThumbnail(from: newItem)
        }
        .sheet(isPresented: $showThumbnailDocumentPicker) {
            DocumentPicker(contentTypes: [.image]) { url in
                loadThumbnail(from: url)
            } onCancel: {
                showThumbnailDocumentPicker = false
            }
        }
    }
    
    @ViewBuilder
    private var reelUploadSection: some View {
        if let uploadPhase {
            MediaUploadStatusView(phase: uploadPhase, onRetry: onRetryUpload)
        } else if reelVideoLoadError {
            VideoErrorStateView(
                videoLoadError: $reelVideoLoadError,
                showVideoPicker: $showReelVideoPicker,
                showDocumentPicker: $showReelDocumentPicker
            )
        } else if isUploadingReelVideo {
            HStack {
                ProgressView()
                    .padding(.trailing, 8)
                Text("Uploading...")
                    .foregroundStyle(.secondary)
            }
        } else {
            videoSelectionRow
            thumbnailSelectionRow
        }
    }

    // MARK: - Upload Rows

    /// "Select video" row: film-strip icon, label, and Photos/Files pickers.
    private var videoSelectionRow: some View {
        HStack {
            Image(systemName: "film")
                .foregroundStyle(.secondary)
            Text(selectedReelVideoURL == nil ? "Select video" : "Video selected")
                .foregroundStyle(.primary)
            if selectedReelVideoURL != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
            Spacer()
            HStack(spacing: 12) {
                Button {
                    showReelVideoPicker = true
                } label: {
                    Label("Photos", systemImage: "photo.stack")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.primary)

                Button {
                    showReelDocumentPicker = true
                } label: {
                    Label("Files", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
            }
        }
    }

    /// "Select thumbnail" row: thumbnail icon (or chosen image preview), label,
    /// and Photos/Files pickers. Chosen independently of the video.
    private var thumbnailSelectionRow: some View {
        HStack {
            if let thumbnail = reelVideoThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
            Text(reelVideoThumbnail == nil ? "Select thumbnail" : "Thumbnail selected")
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 12) {
                Button {
                    showThumbnailPhotoPicker = true
                } label: {
                    Label("Photos", systemImage: "photo.stack")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.primary)

                Button {
                    showThumbnailDocumentPicker = true
                } label: {
                    Label("Files", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
            }
        }
    }

    // MARK: - Thumbnail Loading

    /// Load a chosen photo (from the Photos picker) as the thumbnail.
    private func loadThumbnail(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run { reelVideoThumbnail = image }
            }
        }
    }

    /// Load a chosen image file (from the Files picker) as the thumbnail.
    private func loadThumbnail(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            reelVideoThumbnail = image
        }
        showThumbnailDocumentPicker = false
    }
}

// MARK: - Reel Edit View

/// Metadata-only edit screen for an existing reel submission. The reel video cannot be
/// replaced here — co-located with the reel creation form for consistency.
struct ReelEditView: View {
    let submission: Submission
    let onSave: (Submission) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edited: Submission

    init(submission: Submission, onSave: @escaping (Submission) -> Void) {
        self.submission = submission
        self.onSave = onSave
        _edited = State(initialValue: submission)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $edited.title)

                    TextField("Description", text: $edited.reelDescription, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)

                    Picker("Type", selection: $edited.reelType) {
                        Text("Select Type").tag("")
                        Text("Acting").tag("Acting")
                        Text("Cinematography").tag("Cinematography")
                        Text("Editing").tag("Editing")
                        Text("Directing").tag("Directing")
                        Text("Music/Sound").tag("Music/Sound")
                        Text("Other").tag("Other")
                    }
                }

                Section {
                    Text("The reel video can't be changed when editing. To replace it, delete this post and create a new one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Reel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(edited.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        guard !edited.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onSave(edited)
        dismiss()
    }
}

#Preview {
    @Previewable @State var title = ""
    @Previewable @State var reelType = ""
    @Previewable @State var reelDescription = ""
    @Previewable @State var selectedReelVideoURL: URL? = nil
    @Previewable @State var reelVideoThumbnail: UIImage? = nil
    @Previewable @State var reelVideoLoadError = false
    @Previewable @State var isUploadingReelVideo = false
    @Previewable @State var showReelVideoPicker = false
    @Previewable @State var showReelDocumentPicker = false
    @Previewable @State var showReelThumbnailPicker = false
    
    NavigationStack {
        ReelSubmissionView(
            title: $title,
            reelType: $reelType,
            reelDescription: $reelDescription,
            selectedReelVideoURL: $selectedReelVideoURL,
            reelVideoThumbnail: $reelVideoThumbnail,
            reelVideoLoadError: $reelVideoLoadError,
            isUploadingReelVideo: $isUploadingReelVideo,
            showReelVideoPicker: $showReelVideoPicker,
            showReelDocumentPicker: $showReelDocumentPicker,
            showReelThumbnailPicker: $showReelThumbnailPicker
        )
        .navigationTitle("Reel")
        .navigationBarTitleDisplayMode(.inline)
    }
}
