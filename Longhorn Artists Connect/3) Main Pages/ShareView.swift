//
//  ShareView.swift
//  Longhorn Artists Connect
//
//  Main view for creating and editing submissions (Films, Music, Reels, Projects, Events)
//
//  This file contains:
//  - Helper views for video/image picking and thumbnail selection
//  - ShareView_3: Main submission creation view
//  - ContentTypeSelectorPage: the "What are you sharing?" category chooser
//  - SubmissionTypeSubtitles: the tagline copy for each submission type
//
//  Note: Editing existing submissions is handled per-category by the *EditView types
//  co-located with each form (FilmEditView, MusicEditView, ReelEditView, ProjectEditView,
//  EventEditView). Shared types (CastInfo, CrewInfo, etc.) are in SharedSubmissionTypes.swift
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import MapKit

// MARK: - Video Thumbnail Generator
struct VideoThumbnailGenerator {
    static func generateThumbnail(from url: URL, at time: Double) async -> UIImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let timeValue = CMTime(seconds: time, preferredTimescale: 600)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: timeValue, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("Error generating thumbnail: \(error)")
            return nil
        }
    }
}

// MARK: - Video Transferable
struct VideoTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return VideoTransferable(url: tempURL)
        }
    }
}

// MARK: - Video Picker with iCloud Support
struct VideoPickerWithiCloudSupport: UIViewControllerRepresentable {
    let completion: (Result<URL, Error>) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .videos
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: (Result<URL, Error>) -> Void
        /// Keeps the KVO observation of the item provider's download `Progress` alive
        /// while the (possibly iCloud-hosted) video is pulled to the device.
        private var progressObservation: NSKeyValueObservation?

        init(completion: @escaping (Result<URL, Error>) -> Void) {
            self.completion = completion
        }

        /// The single exit point for a load attempt: tears down progress tracking,
        /// clears the download indicator, and delivers the result on the main thread.
        private func finishLoading(_ result: Result<URL, Error>) {
            DispatchQueue.main.async {
                self.progressObservation?.invalidate()
                self.progressObservation = nil
                MediaDownloadCenter.shared.finish()
                self.completion(result)
            }
        }

        /// Observe the download fraction of an item-provider load so the form can show
        /// a determinate "Downloading from iCloud…" ring.
        private func observeDownloadProgress(_ progress: Progress) {
            progressObservation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { prog, _ in
                let fraction = prog.fractionCompleted
                DispatchQueue.main.async {
                    MediaDownloadCenter.shared.update(fraction)
                }
            }
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let result = results.first else {
                completion(.failure(NSError(domain: "VideoPicker", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cancelled"])))
                return
            }

            // Show the download ring right away — for an iCloud-only video the pull
            // below can take a while, and the picker sheet has already dismissed.
            DispatchQueue.main.async {
                MediaDownloadCenter.shared.begin()
            }

            let itemProvider = result.itemProvider
            
            // First, check what type identifiers are actually available
            print("📋 Available type identifiers:")
            for identifier in itemProvider.registeredTypeIdentifiers {
                print("   - \(identifier)")
            }
            
            // Load video using file representation directly
            print("🎬 Loading video using file representation")
            self.loadVideoFileRepresentation(from: itemProvider)
        }
        
        private func loadVideoFileRepresentation(from itemProvider: NSItemProvider) {
            // Preferred video type identifiers to try, in order
            let preferredVideoTypes = [
                UTType.movie.identifier,           // public.movie
                UTType.video.identifier,           // public.video
                UTType.mpeg4Movie.identifier,      // public.mpeg-4
                UTType.quickTimeMovie.identifier,  // com.apple.quicktime-movie
            ]
            
            // Find the first available type that the item provider can load
            var typeToLoad: String?
            for preferredType in preferredVideoTypes {
                if itemProvider.hasItemConformingToTypeIdentifier(preferredType) {
                    typeToLoad = preferredType
                    print("✅ Found compatible type: \(preferredType)")
                    break
                }
            }
            
            // If none of the preferred types are available, use the first registered identifier
            if typeToLoad == nil {
                typeToLoad = itemProvider.registeredTypeIdentifiers.first
                print("⚠️ Using first registered type: \(typeToLoad ?? "none")")
            }
            
            guard let finalType = typeToLoad else {
                self.finishLoading(.failure(NSError(domain: "VideoPicker", code: -3, userInfo: [NSLocalizedDescriptionKey: "No video type identifier found"])))
                return
            }
            
            // Load the video file
            self.loadVideoFile(from: itemProvider, typeIdentifier: finalType)
        }
        
        private func loadVideoFile(from itemProvider: NSItemProvider, typeIdentifier: String) {
            print("🎬 Loading video with type: \(typeIdentifier)")
            
            // Strategy: Try multiple approaches in order
            // 1. Try data representation (most reliable for all sources)
            // 2. Try loadInPlaceFileRepresentation (good for iCloud)
            // 3. Try regular loadFileRepresentation (fallback)
            
            self.tryDataRepresentation(from: itemProvider, typeIdentifier: typeIdentifier)
        }
        
        private func tryDataRepresentation(from itemProvider: NSItemProvider, typeIdentifier: String) {
            print("🎬 Attempting loadDataRepresentation")

            // This is the call that triggers the iCloud download; observe its progress
            // so the form can show a determinate ring while the file transfers.
            let progress = itemProvider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error = error {
                    print("⚠️ loadDataRepresentation failed: \(error.localizedDescription)")
                    // Try next approach
                    self.tryInPlaceFileRepresentation(from: itemProvider, typeIdentifier: typeIdentifier)
                    return
                }

                guard let data = data else {
                    print("⚠️ No data returned from loadDataRepresentation")
                    // Try next approach
                    self.tryInPlaceFileRepresentation(from: itemProvider, typeIdentifier: typeIdentifier)
                    return
                }

                print("✅ Successfully loaded video data (\(data.count) bytes)")

                // Save data to temp file
                let fileExtension = self.fileExtension(for: typeIdentifier, originalURL: URL(fileURLWithPath: "temp.mov"))
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(fileExtension)

                do {
                    try data.write(to: tempURL)
                    print("✅ Video data written to temp location: \(tempURL.lastPathComponent)")
                    self.finishLoading(.success(tempURL))
                } catch {
                    print("❌ Failed to write video data: \(error.localizedDescription)")
                    // Try next approach
                    self.tryInPlaceFileRepresentation(from: itemProvider, typeIdentifier: typeIdentifier)
                }
            }
            observeDownloadProgress(progress)
        }
        
        private func tryInPlaceFileRepresentation(from itemProvider: NSItemProvider, typeIdentifier: String) {
            print("🎬 Attempting loadInPlaceFileRepresentation")
            
            guard itemProvider.hasItemConformingToTypeIdentifier(typeIdentifier) else {
                print("⚠️ Type identifier not available for loadInPlaceFileRepresentation")
                self.tryFileRepresentation(from: itemProvider, typeIdentifier: typeIdentifier)
                return
            }
            
            itemProvider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, inPlace, error in
                if let error = error {
                    print("⚠️ loadInPlaceFileRepresentation failed: \(error.localizedDescription)")
                    self.tryFileRepresentation(from: itemProvider, typeIdentifier: typeIdentifier)
                    return
                }
                
                guard let url = url else {
                    print("❌ No URL returned from loadInPlaceFileRepresentation")
                    self.tryFileRepresentation(from: itemProvider, typeIdentifier: typeIdentifier)
                    return
                }
                
                print("✅ Successfully loaded video from: \(url.lastPathComponent) (inPlace: \(inPlace))")
                self.copyVideoToTemp(from: url, typeIdentifier: typeIdentifier)
            }
        }
        
        private func tryFileRepresentation(from itemProvider: NSItemProvider, typeIdentifier: String) {
            print("🎬 Attempting loadFileRepresentation (last resort)")
            
            let progress = itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error = error {
                    print("❌ All loading methods failed. Final error: \(error.localizedDescription)")
                    self.finishLoading(.failure(error))
                    return
                }

                guard let url = url else {
                    print("❌ No URL returned from loadFileRepresentation")
                    self.finishLoading(.failure(NSError(domain: "VideoPicker", code: -2, userInfo: [NSLocalizedDescriptionKey: "Video URL not found"])))
                    return
                }

                print("✅ Successfully loaded video from: \(url.lastPathComponent)")
                self.copyVideoToTemp(from: url, typeIdentifier: typeIdentifier)
            }
            observeDownloadProgress(progress)
        }
        
        private func copyVideoToTemp(from url: URL, typeIdentifier: String) {
            let fileExtension = self.fileExtension(for: typeIdentifier, originalURL: url)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            
            do {
                try? FileManager.default.removeItem(at: tempURL)
                
                // Start accessing security-scoped resource if needed
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                try FileManager.default.copyItem(at: url, to: tempURL)

                print("✅ Video copied to temp location: \(tempURL.lastPathComponent)")
                self.finishLoading(.success(tempURL))
            } catch {
                print("❌ Failed to copy video file: \(error.localizedDescription)")
                self.finishLoading(.failure(error))
            }
        }
        
        private func fileExtension(for typeIdentifier: String, originalURL: URL) -> String {
            // First, try to use the original file extension if it's a video format
            let originalExtension = originalURL.pathExtension.lowercased()
            let validExtensions = ["mov", "mp4", "m4v", "avi", "mpg", "mpeg", "3gp", "mkv"]
            if validExtensions.contains(originalExtension) {
                return originalExtension
            }
            
            // Otherwise, determine from type identifier
            switch typeIdentifier {
            case UTType.movie.identifier, UTType.quickTimeMovie.identifier:
                return "mov"
            case UTType.mpeg4Movie.identifier:
                return "mp4"
            case UTType.mpeg2Video.identifier:
                return "mpg"
            default:
                return "mov" // Default fallback
            }
        }
    }
}

// MARK: - Thumbnail Picker View
struct ThumbnailPickerView: View {
    let videoURL: URL
    @Binding var selectedThumbnail: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    @State private var thumbnails: [UIImage] = []
    @State private var isLoading = true
    @State private var selectedTab = 0 // 0 = Video Frames, 1 = Upload
    @State private var sliderValue: Double = 0
    @State private var currentFrameThumbnail: UIImage?
    @State private var videoDuration: Double = 0
    @State private var isGeneratingFrame = false
    
    // Image picker states
    @State private var showImagePicker = false
    @State private var showDocumentPicker = false
    @State private var selectedImageItem: PhotosPickerItem?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Source", selection: $selectedTab) {
                    Text("Video Frame").tag(0)
                    Text("Upload Image").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if selectedTab == 0 {
                    videoFrameTab
                } else {
                    uploadImageTab
                }
            }
            .navigationTitle("Select Thumbnail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if selectedTab == 0 {
                            selectedThumbnail = currentFrameThumbnail
                        }
                        dismiss()
                    }
                    .disabled(selectedTab == 0 && currentFrameThumbnail == nil)
                }
            }
        }
        .task {
            await loadVideo()
        }
        .photosPicker(isPresented: $showImagePicker, selection: $selectedImageItem, matching: .images)
        .onChange(of: selectedImageItem) { oldValue, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        selectedThumbnail = image
                        selectedImageItem = nil
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker(contentTypes: [.image, .jpeg, .png]) { url in
                if let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    selectedThumbnail = image
                    dismiss()
                }
                showDocumentPicker = false
            } onCancel: {
                showDocumentPicker = false
            }
        }
    }
    
    // MARK: - Video Frame Tab
    
    @ViewBuilder
    private var videoFrameTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Current frame preview
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading video...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 250)
                } else if let thumbnail = currentFrameThumbnail {
                    VStack(spacing: 12) {
                        Text("Preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 250)
                            .background(Color.black)
                            .cornerRadius(12)
                            .overlay {
                                if isGeneratingFrame {
                                    ProgressView()
                                        .scaleEffect(1.5)
                                        .tint(.white)
                                }
                            }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 250)
                        .overlay {
                            VStack {
                                Image(systemName: "video")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.secondary)
                                Text("Move slider to select frame")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
                
                // Slider for frame selection
                VStack(spacing: 8) {
                    HStack {
                        Text("Time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatTime(sliderValue))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Slider(value: $sliderValue, in: 0...max(videoDuration, 1))
                        .tint(Color.brandOrange)
                        .disabled(isLoading)
                        .onChange(of: sliderValue) { oldValue, newValue in
                            Task {
                                await generateFrameAtTime(newValue)
                            }
                        }
                    
                    HStack {
                        Text("0:00")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text(formatTime(videoDuration))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                // Quick frame selection (grid of 6 frames)
                VStack(spacing: 12) {
                    Text("Quick Select")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if thumbnails.isEmpty {
                        ProgressView("Generating previews...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, image in
                                Button {
                                    currentFrameThumbnail = image
                                    let time = Double(index) * (videoDuration / Double(thumbnails.count))
                                    sliderValue = time
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 80)
                                            .cornerRadius(8)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(
                                                        currentFrameThumbnail == image ? Color.brandOrange : Color.clear,
                                                        lineWidth: 3
                                                    )
                                            }
                                        
                                        Text(formatTime(Double(index) * (videoDuration / Double(thumbnails.count))))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Upload Image Tab
    
    @ViewBuilder
    private var uploadImageTab: some View {
        VStack(spacing: 20) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.brandOrange.opacity(0.6))
                
                Text("Upload Custom Thumbnail")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Choose an image from your photos or files to use as the thumbnail for this video")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            
            VStack(spacing: 12) {
                Button {
                    showImagePicker = true
                } label: {
                    Label("Choose from Photos", systemImage: "photo.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandOrange)
                
                Button {
                    showDocumentPicker = true
                } label: {
                    Label("Choose from Files", systemImage: "folder.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.bordered)
                .tint(Color.brandOrange)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadVideo() async {
        let asset = AVAsset(url: videoURL)
        
        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = duration.seconds
            
            await MainActor.run {
                videoDuration = durationSeconds
                sliderValue = 0
            }
            
            // Generate initial frame at 0 seconds
            await generateFrameAtTime(0)
            
            // Generate quick select thumbnails
            await generateQuickSelectThumbnails()
            
            await MainActor.run {
                isLoading = false
            }
        } catch {
            print("Error loading video: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func generateQuickSelectThumbnails() async {
        var images: [UIImage] = []
        
        for i in 0..<6 {
            let time = Double(i) * (videoDuration / 6.0)
            if let thumbnail = await VideoThumbnailGenerator.generateThumbnail(from: videoURL, at: time) {
                images.append(thumbnail)
            }
        }
        
        await MainActor.run {
            thumbnails = images
        }
    }
    
    private func generateFrameAtTime(_ time: Double) async {
        await MainActor.run {
            isGeneratingFrame = true
        }
        
        if let thumbnail = await VideoThumbnailGenerator.generateThumbnail(from: videoURL, at: time) {
            await MainActor.run {
                currentFrameThumbnail = thumbnail
                isGeneratingFrame = false
            }
        } else {
            await MainActor.run {
                isGeneratingFrame = false
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Drafts View
struct DraftsView: View {
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @Environment(\.dismiss) private var dismiss
    /// Called when a draft is tapped so the caller can reopen it in the form.
    var onResume: (Submission) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            List {
                if store.drafts.isEmpty {
                    Text("No drafts yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.drafts) { draft in
                        DraftRow(draft: draft) {
                            store.deleteDraft(draft)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onResume(draft)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Drafts")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(false) // Allow pull to dismiss
    }
}

// MARK: - Draft Row

/// A single saved draft displayed in the Drafts list.
private struct DraftRow: View {
    let draft: Submission
    /// Deletes this draft. Tapping the row itself resumes the draft; this button is
    /// isolated (borderless) so its tap deletes without also triggering the row tap.
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(Color.brandOrange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title.isEmpty ? "Untitled \(draft.type.displayName)" : draft.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(draft.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Info Sheet View
struct InfoSheetView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    InfoSection(
                        title: "One Post for All",
                        text: "It doesn't matter who actually creates the post, whether it be director, producer, editor, etc...if you're in the credits, it'll show up in your portfolio, no matter how big or small your role was."
                    )
                    
                    InfoSection(
                        title: "Just Create & Enjoy",
                        text: "There are no public likes or comments here. Instead of preemptively judging a work based on a number, we want people to view each other's work completely unbiased."

                    )

                    InfoSection(
                        title: "You Own Everything",
                        text: "Posting on the app never forfeits any rights to your content. You made it, so you own it."
                    )

                    InfoSection(
                        title: "Respect the Community",
                        text: "Stealing another artist's work or intentionally discrediting people is not a joke. Doing so will lead to a temporary or permanent ban from uploading."
                    )
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Information")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(false) // Allow pull to dismiss
    }
}

// MARK: - Help Sheet

/// Explains common reasons an upload might fail and how to resolve them.
/// Presented from the Help button in the Share page toolbar.
struct HelpSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    InfoSection(
                        title: "Check Your Connection",
                        text: "Uploads need a stable internet connection. If you're on weak Wi-Fi or cellular, move to a stronger signal and try again. Large videos in particular can fail on spotty connections."

                    )

                    InfoSection(
                        title: "Supported File Types",
                        text: "Make sure your file is a supported format — common video (MP4, MOV), audio, and image types. Unusual or corrupted files may be rejected."
                    )

                    InfoSection(
                        title: "Fill Out Required Fields",
                        text: "Posts won't submit if a required field is empty. Double-check that every required box (like title and media) is filled in before tapping Post."
                    )

                    InfoSection(
                        title: "Keep the App Open",
                        text: "Leave the form open while an upload is in progress. Closing the app or switching away mid-upload can interrupt it. If a post fails, use Retry rather than starting over."
                    )

                    InfoSection(
                        title: "Still Not Working?",
                        text: "Try saving your work as a draft, fully closing and reopening the app, then resuming the draft. If problems continue, restart your device and check that the app is up to date."
                    )
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(false) // Allow pull to dismiss
    }
}

// MARK: - Info Section

/// A single titled paragraph block used on the Information sheet.
private struct InfoSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

struct ShareView_3: View {
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    
    @State private var selectedContentType: MediaType? = nil
    @State private var title: String = ""
    @State private var logline: String = ""
    @State private var explicitRating: Bool = false


    // Event-specific states
    @State private var eventCategory: String = ""
    @State private var eventStartDate: Date = Date()
    @State private var eventEndDate: Date = Date().addingTimeInterval(3600) // 1 hour later
    @State private var eventLocation: String = ""
    @State private var eventHost: String = ""
    @State private var eventTicketsURL: String = ""
    @State private var eventExpectations: String = ""
    @State private var eventApplicationURL: String = ""
    @State private var eventLineup: String = ""
    /// Theatre Performance: the run's showings, each a date with start/end times.
    @State private var eventShowings: [EventShowing] = []

    @State private var crewInfo: CrewInfo = CrewInfo()
    @State private var castInfo: CastInfo = CastInfo()

    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    @State private var selectedAgeRating: AgeRating = .general
    
    private let allGenres = ["Comedy", "Drama", "Horror", "Adventure", "Fantasy", "Thriller", "Coming-Of-Age", "Sci-Fi", "Documentary", "Mystery"]
    @State private var selectedGenres: Set<String> = []
    @State private var filmReleaseYear = ""
    
    // Video picker states
    // Note: Film owns its own video/document/thumbnail pickers inside FilmSubmissionView
    @State private var selectedVideoURL: URL?
    @State private var videoThumbnail: UIImage?
    /// The selected video's first frame, kept separate from `videoThumbnail` so choosing a
    /// custom poster doesn't change the preview shown in the "video" row.
    @State private var videoFirstFrame: UIImage?
    /// True once the user picks their own thumbnail, so the auto-generated first-frame
    /// thumbnail (which finishes asynchronously) never overwrites their choice.
    @State private var videoThumbnailIsCustom: Bool = false
    @State private var videoLoadError: Bool = false
    @State private var isUploadingVideo: Bool = false
    /// Films only: keeps the post private (festival-bound) when true.
    @State private var filmFestivalBound: Bool = false

    // Film extras (films only): a separate trailer video + any number of BTS photos / stills.
    @State private var selectedTrailerURL: URL?
    @State private var trailerFirstFrame: UIImage?
    @State private var filmBTSImages: [UIImage] = []
    @State private var filmStillImages: [UIImage] = []

    // Audio picker states
    // Note: Music owns its own audio picker inside MusicSubmissionView
    @State private var selectedAudioURL: URL?
    /// EP/Album releases only: the tracks after the first. `selectedAudioURL` stays
    /// track 1 so the existing single-audio upload path is unchanged.
    @State private var additionalAudioURLs: [URL] = []
    @State private var isUploadingAudio: Bool = false
    
    // Image picker states for Projects
    @State private var selectedProjectImageItem: PhotosPickerItem?
    @State private var selectedProjectImageData: Data?
    @State private var showProjectImagePicker = false
    @State private var showProjectImageDocumentPicker = false
    
    // Image picker states for Events
    @State private var selectedEventImageItem: PhotosPickerItem?
    @State private var selectedEventImageData: Data?
    @State private var showEventImagePicker = false
    @State private var showEventImageDocumentPicker = false
    
    // Talent Reel video states
    @State private var selectedReelVideoURL: URL?
    @State private var reelVideoThumbnail: UIImage?
    /// The selected reel video's first frame, kept separate from `reelVideoThumbnail` so a
    /// custom poster doesn't change the preview shown in the "video" row.
    @State private var reelVideoFirstFrame: UIImage?
    /// True once the user picks their own reel thumbnail, so the auto-generated
    /// first-frame thumbnail never overwrites their choice.
    @State private var reelVideoThumbnailIsCustom: Bool = false
    @State private var reelVideoLoadError: Bool = false
    @State private var isUploadingReelVideo: Bool = false
    @State private var showReelVideoPicker = false
    @State private var showReelDocumentPicker = false
    @State private var showReelThumbnailPicker = false
    
    // Talent Reel-specific states
    @State private var reelType: String = ""
    @State private var reelDescription: String = ""
    /// UUID strings of posts referenced as "Featured Work" on the reel being composed.
    @State private var reelFeaturedWorkIDs: [String] = []
    /// Hand-typed "Featured Work" entries (project + director) on the reel being composed,
    /// each a JSON-encoded `ManualFeaturedWork`.
    @State private var reelFeaturedWorkManual: [String] = []
    /// The reel's release year.
    @State private var reelReleaseYear = ""
    
    // Project-specific states
    @State private var projectCategory: String = ""   // ProjectType raw value
    @State private var projectWriters: String = ""     // Script / In-Development writer(s)
    @State private var projectGenre: String = ""       // Script genre
    @State private var shootStartDate: Date = Date()
    @State private var shootEndDate: Date = Date()
    @State private var projectReleaseDate: Date = Date()
    @State private var castNeeded: [String] = []
    @State private var crewNeeded: [String] = []
    @State private var selectedProjectScriptURL: URL?
    @State private var showProjectScriptPicker: Bool = false
    /// The project's slideshow images, in the order they were picked.
    @State private var projectSlides: [UIImage] = []
    
    // Film-specific states
    /// Empty until the film's Category is picked; "Independent" once the user chooses
    /// Independent Project, otherwise the chosen studio or class.
    @State private var selectedStudio: String = ""
    private let availableStudios = ["Collective", "Incubator", "Beyond Frame Productions", "DKA", "Black Lens", "Independent"]
    
    // Music-specific states
    // Note: Music owns its own album-cover and music-video pickers inside MusicSubmissionView
    @State private var artist: String = ""
    @State private var selectedAlbumCoverData: Data?
    @State private var selectedMusicVideoURL: URL?
    @State private var musicVideoThumbnail: UIImage?
    @State private var selectedMusicGenres: Set<String> = []
    @State private var musicCategory = ""
    @State private var musicReleaseYear = ""
    @State private var musicRecordingCredits: [OrderedEntry] = []
    @State private var musicProductionCredits: [OrderedEntry] = []
    @State private var musicSpotifyLink: String = ""
    @State private var musicAppleMusicLink: String = ""
    @State private var musicYouTubeMusicLink: String = ""
    @State private var musicSoundcloudLink: String = ""
    @State private var musicLyrics: String = ""

    // Photography-specific states (reuses the shared `title` and `artist`)
    @State private var photographyImages: [UIImage] = []
    @State private var photographyDescription: String = ""
    @State private var photographyReleaseYear: String = ""
    @State private var photographyEquipment = EquipmentInfo()
    @State private var photographyCredits = CrewInfo(orderedEntries: [])

    // Design-specific states (reuses the shared `title`)
    @State private var designImages: [UIImage] = []
    @State private var designDescription: String = ""
    @State private var designCategory: String = ""
    @State private var designReleaseYear: String = ""
    @State private var designVideoURL: URL?
    @State private var designVideoFirstFrame: UIImage?
    @State private var designCredits = CrewInfo(orderedEntries: [])

    // Draft states
    @State private var showDraftsSheet = false
    @State private var showInfoSheet = false
    @State private var showHelpSheet = false
    // When resuming a draft, this holds its ID so posting/saving updates the
    // existing draft instead of creating a duplicate.
    @State private var editingDraftID: UUID? = nil

    // MARK: - Live Upload Progress
    @ObservedObject private var uploadCenter = UploadProgressCenter.shared
    /// The submission currently uploading; while set, the form stays open showing
    /// its progress wheel instead of dismissing on Post.
    @State private var activeUploadID: UUID? = nil
    /// Retained so a failed upload can be retried from the form.
    @State private var lastSubmittedSubmission: Submission? = nil
    @State private var showPostedToast = false

    /// Live upload phase for the in-flight post, or `nil` while filling out the form.
    private var currentUploadPhase: MediaUploadPhase? {
        guard let id = activeUploadID else { return nil }
        return uploadCenter.phase(for: id)
    }
    // Set by the Drafts sheet on tap; opened after that sheet finishes dismissing.
    @State private var pendingDraftToResume: Submission? = nil
    // Shows a brief "Draft Saved!" confirmation toast after saving a draft.
    @State private var showDraftSavedToast = false

    // MARK: - Auto-Draft
    // When a form opens (fresh or resumed) we stamp the time and type so that
    // swiping the sheet away after more than two minutes of work — with at least
    // two fields filled — auto-saves a draft instead of discarding the work.
    @State private var formOpenedAt: Date? = nil
    @State private var activeFormType: MediaType? = nil
    // Set by Post and the manual Draft button so their dismissal doesn't also
    // trigger an auto-draft (they've already persisted the work).
    @State private var suppressAutoDraft = false

    // Toolbar items
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Draft") {
                saveDraft()
            }
            // Can't save a draft once the post is uploading.
            .disabled(activeUploadID != nil)
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("Post") {
                submitPost()
            }
            // While an upload is in flight (or just finished / failed), the form shows
            // the progress wheel; re-posting is blocked (use Retry on failure).
            .disabled(activeUploadID != nil)
        }
    }

    /// Whether the in-flight post is actively transferring (as opposed to finished or
    /// failed). Used to keep the sheet from being swiped away mid-upload.
    private var isUploadingNow: Bool {
        if case .uploading = currentUploadPhase { return true }
        return false
    }
    
    var body: some View {
        NavigationStack {
            ContentTypeSelectorPage(
                selectedType: $selectedContentType,
                showDraftsSheet: $showDraftsSheet,
                showInfoSheet: $showInfoSheet,
                showHelpSheet: $showHelpSheet
            )
            // Keep this page anchored when a submission sheet's keyboard appears —
            // otherwise the content behind the sheet lifts to avoid the keyboard.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .sheet(item: $selectedContentType, onDismiss: {
                // A genuine swipe-away auto-saves a draft when the form was worked
                // on for over two minutes with at least two fields filled. Posting
                // and the manual Draft button persist first and suppress this.
                // Clearing the inputs afterwards prevents fields from carrying over
                // to the next content type.
                autoSaveDraftIfNeeded()
                resetForm()
            }) { contentType in
                // Show the form as a bottom sheet
                contentFormSheet(for: contentType)
            }
            // Start the auto-draft timer the moment a form opens (fresh or resumed).
            .onChange(of: selectedContentType) { _, newValue in
                if let newValue {
                    activeFormType = newValue
                    formOpenedAt = Date()
                }
            }
            .sheet(isPresented: $showDraftsSheet, onDismiss: resumePendingDraftIfNeeded) {
                DraftsView(onResume: { draft in
                    pendingDraftToResume = draft
                })
            }
            .sheet(isPresented: $showInfoSheet) {
                InfoSheetView()
            }
            .sheet(isPresented: $showHelpSheet) {
                HelpSheetView()
            }
        }
        // Hard-anchor the whole Share tab so a submission sheet's keyboard can never
        // push this page up or down.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(alignment: .top) {
            if showDraftSavedToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Draft Saved!")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.brandOrange, in: Capsule())
                .shadow(radius: 4, y: 2)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if showPostedToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Posted!")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.brandOrange, in: Capsule())
                .shadow(radius: 4, y: 2)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    @ViewBuilder
    private func contentFormSheet(for contentType: MediaType) -> some View {
        NavigationStack {
            formSheetBody(for: contentType)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        // Don't let the user swipe the sheet away while media is actively uploading.
        .interactiveDismissDisabled(isUploadingNow)
        // Tap anywhere outside a field to dismiss the keyboard; also ends editing
        // when tapping a button that pushes a sub-page (Streaming Links, Credits, …)
        // so the keyboard doesn't reappear on return.
        .endEditingOnTap()
    }

    /// Builds the form plus all its attached picker sheets in sequential steps.
    /// Kept out of a single nested expression so the type-checker (and the
    /// SwiftUI preview canvas) can resolve it quickly.
    private func formSheetBody(for contentType: MediaType) -> some View {
        let base = contentFormView(for: contentType)
            .navigationTitle(contentType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
        let withDocuments = attachDocumentSheets(to: base)
        let withVideo = attachVideoPickerSheets(to: withDocuments)
        let withPhotos = attachPhotosPickers(to: withVideo)
        return attachImageDocumentSheets(to: withPhotos)
    }

    private func attachDocumentSheets<V: View>(to base: V) -> some View {
        base
            .sheet(isPresented: $showReelDocumentPicker) { reelDocumentPickerSheet }
            .sheet(isPresented: $showReelThumbnailPicker) { reelThumbnailPickerSheet }
    }

    private func attachVideoPickerSheets<V: View>(to base: V) -> some View {
        base
            .sheet(isPresented: $showReelVideoPicker) {
                VideoPickerWithiCloudSupport { result in
                    handleReelVideoPickerResult(result)
                }
            }
    }

    private func attachPhotosPickers<V: View>(to base: V) -> some View {
        base
            .photosPicker(isPresented: $showProjectImagePicker, selection: $selectedProjectImageItem, matching: .images)
            .onChange(of: selectedProjectImageItem) { _, newValue in
                guard newValue != nil else { return }
                MediaDownloadCenter.shared.beginImageLoad()
                Task {
                    let data = try? await newValue?.loadTransferable(type: Data.self)
                    await MainActor.run {
                        if let data { selectedProjectImageData = data }
                        selectedProjectImageItem = nil
                        MediaDownloadCenter.shared.finishImageLoad()
                    }
                }
            }
            .photosPicker(isPresented: $showEventImagePicker, selection: $selectedEventImageItem, matching: .images)
            .onChange(of: selectedEventImageItem) { _, newValue in
                guard newValue != nil else { return }
                MediaDownloadCenter.shared.beginImageLoad()
                Task {
                    let data = try? await newValue?.loadTransferable(type: Data.self)
                    await MainActor.run {
                        if let data { selectedEventImageData = data }
                        selectedEventImageItem = nil
                        MediaDownloadCenter.shared.finishImageLoad()
                    }
                }
            }
    }

    private func attachImageDocumentSheets<V: View>(to base: V) -> some View {
        base
            .sheet(isPresented: $showProjectImageDocumentPicker) { projectImageDocumentPickerSheet }
            .sheet(isPresented: $showEventImageDocumentPicker) { eventImageDocumentPickerSheet }
    }
    
    @ViewBuilder
    private func contentFormView(for contentType: MediaType) -> some View {
        Group {
            if contentType == .reel {
                reelFormContent
            } else if contentType == .project {
                projectFormContent
            } else if contentType == .event {
                eventFormContent
            } else if contentType == .film {
                filmFormContent
            } else if contentType == .photography {
                photographyFormContent
            } else if contentType == .design {
                designFormContent
            } else {
                musicFormContent
            }
        }
        .alert("Submission Posted!", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) {
                selectedContentType = nil
                resetForm()
            }
        }
        .alert("Upload Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        // When the upload finishes, show the checkmark briefly, then auto-dismiss.
        .onChange(of: currentUploadPhase) { _, newPhase in
            guard newPhase == .finished else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if currentUploadPhase == .finished {
                    finishUploadAndDismiss()
                }
            }
        }
    }
    
    private func handleVideoPickerResult(_ result: Result<URL, Error>) {
        Task {
            await MainActor.run {
                isUploadingVideo = true
            }

            switch result {
            case .success(let url):
                print("✅ Video picker SUCCESS: \(url.lastPathComponent)")
                await MainActor.run {
                    selectedVideoURL = url
                    videoLoadError = false
                    generateThumbnail(from: url)
                    isUploadingVideo = false
                }
            case .failure(let error):
                print("❌ Video picker FAILURE: \(error.localizedDescription)")
                await MainActor.run {
                    videoLoadError = true
                    isUploadingVideo = false
                    errorMessage = "Failed to load video: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
    }
    
    /// Handles a picked trailer video (Photos or Files): keeps the source URL and generates
    /// a first-frame preview for the trailer row. The file is copied into the media cache at
    /// submit time (see `configureFilmSubmission`).
    private func handleTrailerPickerResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            selectedTrailerURL = url
            Task {
                let frame = await VideoThumbnailGenerator.generateThumbnail(from: url, at: 0)
                await MainActor.run { trailerFirstFrame = frame }
            }
        case .failure(let error):
            errorMessage = "Failed to load trailer: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func handleReelVideoPickerResult(_ result: Result<URL, Error>) {
        Task {
            await MainActor.run {
                isUploadingReelVideo = true
                showReelVideoPicker = false
            }
            
            switch result {
            case .success(let url):
                print("✅ Reel video picker SUCCESS: \(url.lastPathComponent)")
                await MainActor.run {
                    selectedReelVideoURL = url
                    reelVideoLoadError = false
                    generateReelThumbnail(from: url)
                    isUploadingReelVideo = false
                }
                print("✅ Reel video URL set successfully")
            case .failure(let error):
                print("❌ Reel video picker FAILURE: \(error.localizedDescription)")
                await MainActor.run {
                    reelVideoLoadError = true
                    isUploadingReelVideo = false
                    errorMessage = "Failed to load reel video: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
    }
    
    private func handleMusicVideoPickerResult(_ result: Result<URL, Error>) {
        Task {
            switch result {
            case .success(let url):
                await MainActor.run {
                    selectedMusicVideoURL = url
                    generateMusicVideoThumbnail(from: url)
                }
            case .failure(let error):
                await MainActor.run {
                    print("❌ Music video picker error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @ViewBuilder
    private var projectImageDocumentPickerSheet: some View {
        DocumentPicker(contentTypes: [.image, .jpeg, .png]) { url in
            MediaDownloadCenter.shared.beginImageLoad()
            defer { MediaDownloadCenter.shared.finishImageLoad() }
            if let data = try? Data(contentsOf: url) {
                selectedProjectImageData = data
            }
            showProjectImageDocumentPicker = false
        } onCancel: {
            showProjectImageDocumentPicker = false
        }
    }
    
    @ViewBuilder
    private var eventImageDocumentPickerSheet: some View {
        DocumentPicker(contentTypes: [.image, .jpeg, .png]) { url in
            MediaDownloadCenter.shared.beginImageLoad()
            defer { MediaDownloadCenter.shared.finishImageLoad() }
            if let data = try? Data(contentsOf: url) {
                selectedEventImageData = data
            }
            showEventImageDocumentPicker = false
        } onCancel: {
            showEventImageDocumentPicker = false
        }
    }

    @ViewBuilder
    private var reelDocumentPickerSheet: some View {
        DocumentPicker(contentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie]) { url in
            Task {
                await MainActor.run {
                    isUploadingReelVideo = true
                    showReelDocumentPicker = false
                    reelVideoLoadError = false
                }
                
                // Small delay to ensure UI updates
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                
                await MainActor.run {
                    selectedReelVideoURL = url
                    // Generate thumbnail from first frame for document picker videos
                    generateReelThumbnail(from: url)
                    isUploadingReelVideo = false
                }
            }
        } onCancel: {
            showReelDocumentPicker = false
        }
    }
    
    @ViewBuilder
    private var reelThumbnailPickerSheet: some View {
        if let videoURL = selectedReelVideoURL {
            ThumbnailPickerView(videoURL: videoURL, selectedThumbnail: $reelVideoThumbnail)
        }
    }
    
    private func generateReelThumbnail(from url: URL) {
        Task {
            let thumbnail = await VideoThumbnailGenerator.generateThumbnail(from: url, at: 0)
            await MainActor.run {
                // Don't clobber a thumbnail the user picked themselves. Generation is
                // async, so the user may have chosen one while this was running.
                // The video row always shows the true first frame.
                reelVideoFirstFrame = thumbnail
                guard !reelVideoThumbnailIsCustom else { return }
                reelVideoThumbnail = thumbnail
            }
        }
    }

    private func generateThumbnail(from url: URL) {
        Task {
            let thumbnail = await VideoThumbnailGenerator.generateThumbnail(from: url, at: 0)
            await MainActor.run {
                // The video row always shows the true first frame.
                videoFirstFrame = thumbnail
                // Don't clobber a thumbnail the user picked themselves. Generation is
                // async, so the user may have chosen one while this was running.
                guard !videoThumbnailIsCustom else { return }
                videoThumbnail = thumbnail
            }
        }
    }

    private func generateMusicVideoThumbnail(from url: URL) {
        Task {
            let thumbnail = await VideoThumbnailGenerator.generateThumbnail(from: url, at: 0)
            await MainActor.run {
                musicVideoThumbnail = thumbnail
            }
        }
    }
    
    // MARK: - Form Content Helper Views
    
    @ViewBuilder
    private var reelFormContent: some View {
        ReelSubmissionView(
            title: $title,
            artist: $artist,
            reelType: $reelType,
            reelDescription: $reelDescription,
            releaseYear: $reelReleaseYear,
            selectedReelVideoURL: $selectedReelVideoURL,
            reelVideoFirstFrame: $reelVideoFirstFrame,
            reelVideoThumbnail: $reelVideoThumbnail,
            reelVideoThumbnailIsCustom: $reelVideoThumbnailIsCustom,
            reelVideoLoadError: $reelVideoLoadError,
            isUploadingReelVideo: $isUploadingReelVideo,
            showReelVideoPicker: $showReelVideoPicker,
            showReelDocumentPicker: $showReelDocumentPicker,
            showReelThumbnailPicker: $showReelThumbnailPicker,
            featuredWorkIDs: $reelFeaturedWorkIDs,
            featuredWorkManual: $reelFeaturedWorkManual,
            uploadPhase: currentUploadPhase,
            onRetryUpload: retryUpload
        )
    }

    @ViewBuilder
    private var projectFormContent: some View {
        ProjectSubmissionView(
            title: $title,
            logline: $logline,
            projectCategory: $projectCategory,
            writers: $projectWriters,
            projectGenre: $projectGenre,
            shootStartDate: $shootStartDate,
            shootEndDate: $shootEndDate,
            projectReleaseDate: $projectReleaseDate,
            castNeeded: $castNeeded,
            crewNeeded: $crewNeeded,
            castInfo: $castInfo,
            crewInfo: $crewInfo,
            selectedProjectImageData: $selectedProjectImageData,
            selectedProjectScriptURL: $selectedProjectScriptURL,
            showProjectImagePicker: $showProjectImagePicker,
            showProjectImageDocumentPicker: $showProjectImageDocumentPicker,
            showProjectScriptPicker: $showProjectScriptPicker,
            slides: $projectSlides,
            uploadPhase: currentUploadPhase,
            onRetryUpload: retryUpload
        )
        .sheet(isPresented: $showProjectScriptPicker) {
            DocumentPicker(
                contentTypes: [.pdf, .plainText, .rtf, .rtfd],
                onSelect: { url in
                    selectedProjectScriptURL = url
                    showProjectScriptPicker = false
                },
                onCancel: {
                    showProjectScriptPicker = false
                }
            )
        }
    }
    
    @ViewBuilder
    private var eventFormContent: some View {
        EventSubmissionView(
            title: $title,
            eventDetails: $logline,
            eventHost: $eventHost,
            eventCategory: $eventCategory,
            eventStartDate: $eventStartDate,
            eventEndDate: $eventEndDate,
            eventLocation: $eventLocation,
            ticketsURL: $eventTicketsURL,
            eventExpectations: $eventExpectations,
            eventApplicationURL: $eventApplicationURL,
            eventLineup: $eventLineup,
            eventShowings: $eventShowings,
            selectedEventImageData: $selectedEventImageData,
            showEventImagePicker: $showEventImagePicker,
            showEventImageDocumentPicker: $showEventImageDocumentPicker,
            uploadPhase: currentUploadPhase,
            onRetryUpload: retryUpload
        )
    }
    
    @ViewBuilder
    private var filmFormContent: some View {
        FilmSubmissionView(
            title: $title,
            logline: $logline,
            selectedGenres: $selectedGenres,
            releaseYear: $filmReleaseYear,
            selectedAgeRating: $selectedAgeRating,
            castInfo: $castInfo,
            crewInfo: $crewInfo,
            selectedStudio: $selectedStudio,
            selectedVideoURL: $selectedVideoURL,
            videoFirstFrame: $videoFirstFrame,
            videoThumbnail: $videoThumbnail,
            videoThumbnailIsCustom: $videoThumbnailIsCustom,
            videoLoadError: $videoLoadError,
            isUploadingVideo: $isUploadingVideo,
            festivalBound: $filmFestivalBound,
            selectedTrailerURL: $selectedTrailerURL,
            trailerFirstFrame: $trailerFirstFrame,
            btsImages: $filmBTSImages,
            stillImages: $filmStillImages,
            onVideoPickerResult: handleVideoPickerResult,
            onGenerateThumbnail: generateThumbnail,
            onTrailerPickerResult: handleTrailerPickerResult,
            uploadPhase: currentUploadPhase,
            onRetryUpload: retryUpload
        )
    }

    @ViewBuilder
    private var musicFormContent: some View {
        MusicSubmissionView(
            title: $title,
            artist: $artist,
            category: $musicCategory,
            selectedGenres: $selectedMusicGenres,
            releaseYear: $musicReleaseYear,
            explicitRating: $explicitRating,
            recordingCredits: $musicRecordingCredits,
            productionCredits: $musicProductionCredits,
            spotifyLink: $musicSpotifyLink,
            appleMusicLink: $musicAppleMusicLink,
            youtubeMusicLink: $musicYouTubeMusicLink,
            soundcloudLink: $musicSoundcloudLink,
            lyrics: $musicLyrics,
            selectedAudioURL: $selectedAudioURL,
            additionalAudioURLs: $additionalAudioURLs,
            selectedAlbumCoverData: $selectedAlbumCoverData,
            selectedMusicVideoURL: $selectedMusicVideoURL,
            musicVideoThumbnail: $musicVideoThumbnail,
            isUploadingAudio: $isUploadingAudio,
            onAudioPickerResult: handleAudioPickerResult,
            onAlbumCoverSelected: { data in selectedAlbumCoverData = data },
            onMusicVideoSelected: handleMusicVideoPickerResult,
            uploadPhase: currentUploadPhase,
            onRetryUpload: retryUpload
        )
    }

    @ViewBuilder
    private var photographyFormContent: some View {
        PhotographySubmissionView(
            title: $title,
            artist: $artist,
            photoDescription: $photographyDescription,
            releaseYear: $photographyReleaseYear,
            images: $photographyImages,
            equipment: $photographyEquipment,
            credits: $photographyCredits,
            uploadPhase: currentUploadPhase,
            onRetryUpload: retryUpload
        )
    }

    @ViewBuilder
    private var designFormContent: some View {
        DesignSubmissionView(
            title: $title,
            designDescription: $designDescription,
            category: $designCategory,
            releaseYear: $designReleaseYear,
            images: $designImages,
            videoURL: $designVideoURL,
            videoFirstFrame: $designVideoFirstFrame,
            credits: $designCredits,
            uploadPhase: currentUploadPhase,
            onRetryUpload: retryUpload
        )
    }

    private func handleAudioPickerResult(_ result: Result<URL, Error>) {
        Task {
            await MainActor.run {
                isUploadingAudio = true
            }

            switch result {
            case .success(let url):
                await MainActor.run {
                    selectedAudioURL = url
                    isUploadingAudio = false
                }
            case .failure(let error):
                await MainActor.run {
                    isUploadingAudio = false
                    errorMessage = "Failed to load audio: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
    }
    
    // MARK: - Configuration Methods
    
    private func configureReelSubmission(_ submission: inout Submission) {
        submission.reelType = reelType
        submission.reelDescription = reelDescription
        submission.artist = artist
        submission.releaseYear = reelReleaseYear
        submission.featuredWorkIDs = reelFeaturedWorkIDs
        submission.featuredWorkManual = reelFeaturedWorkManual

        if let videoURL = selectedReelVideoURL {
            let fileName = "video_\(submission.id.uuidString).\(videoURL.pathExtension)"
            // Outgoing upload copy lives in the media cache (bounded, backup-excluded);
            // it's deleted once the CloudKit upload confirms (see `saveSubmissionToCloudKit`).
            if let mediaDir = FileManager.default.mediaCacheDirectory {
                let destinationURL = mediaDir.appendingPathComponent(fileName)
                do {
                    try? FileManager.default.removeItem(at: destinationURL)
                    try FileManager.default.copyItem(at: videoURL, to: destinationURL)
                    submission.videoFileName = fileName
                } catch {
                    print("Error copying video: \(error)")
                }
            }
        }

        if let thumbnail = reelVideoThumbnail {
            submission.thumbnailData = thumbnail.jpegData(compressionQuality: 0.7)
        }
    }
    
    private func configureProjectSubmission(_ submission: inout Submission) {
        submission.logline = logline
        submission.projectType = projectCategory
        submission.writers = projectWriters
        // `genres` holds the Script genre only; the type lives in `projectType`.
        submission.genres = (ProjectType(rawValue: projectCategory) == .script && !projectGenre.isEmpty) ? [projectGenre] : []
        submission.shootDates = formatDate(shootStartDate) + " - " + formatDate(shootEndDate)
        submission.expectedReleaseDate = formatDate(projectReleaseDate)
        submission.castNeeded = castNeeded.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        submission.crewNeeded = crewNeeded.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        if let imageData = selectedProjectImageData {
            submission.thumbnailData = imageData
        }

        // Persist the picked slides to the media cache under the deterministic names the
        // CloudKit upload/parse expect (`<id>_slide_<n>.jpg`). The poster stays the
        // thumbnail — the slideshow only replaces it on the detail view.
        submission.projectSlideFileNames = projectSlides.isEmpty
            ? nil
            : persistFilmExtraImages(projectSlides, submissionID: submission.id, kind: "slide")

        // Script projects use the script's first page as the thumbnail and record its
        // page count (overrides any poster, which Script doesn't collect).
        if ProjectType(rawValue: projectCategory) == .script, let scriptURL = selectedProjectScriptURL {
            let (thumb, pages) = ScriptThumbnail.make(from: scriptURL)
            if let thumb { submission.thumbnailData = thumb }
            submission.scriptPageCount = pages
        }

        // Save script file if uploaded
        if let scriptURL = selectedProjectScriptURL {
            let fileName = "script_\(submission.id.uuidString).\(scriptURL.pathExtension)"
            if let documentsURL = FileManager.default.documentsDirectory {
                let destinationURL = documentsURL.appendingPathComponent(fileName)
                do {
                    try? FileManager.default.removeItem(at: destinationURL)
                    try FileManager.default.copyItem(at: scriptURL, to: destinationURL)
                    submission.scriptFileName = fileName
                    print("✅ Script saved: \(fileName)")
                } catch {
                    print("❌ Error copying script: \(error.localizedDescription)")
                }
            }
        }
        
        // Add cast and crew
        var orderedCast: [OrderedEntry] = []
        for entry in castInfo.primaries + castInfo.secondaries + castInfo.extras {
            if !entry.performer.isEmpty && !entry.role.isEmpty {
                orderedCast.append(OrderedEntry(role: entry.role, name: entry.performer, profileID: entry.profileID))
            }
        }
        submission.orderedCast = orderedCast
        
        let (_, orderedCrew) = createOrderedCrewData()
        submission.orderedCrew = orderedCrew
    }
    
    private func configureEventSubmission(_ submission: inout Submission) {
        submission.logline = logline
        submission.eventHost = eventHost
        submission.eventStartDate = eventStartDate
        submission.eventEndDate = eventEndDate
        submission.eventLocation = eventLocation
        submission.eventTicketsURL = eventTicketsURL.isEmpty ? nil : eventTicketsURL
        submission.eventExpectations = eventExpectations.isEmpty ? nil : eventExpectations
        submission.eventApplicationURL = eventApplicationURL.isEmpty ? nil : eventApplicationURL
        submission.eventLineup = eventLineup.isEmpty ? nil : eventLineup
        submission.genres = [eventCategory]

        // Showings belong to Theatre Performance only, so anything entered before the
        // category was switched away is dropped rather than saved invisibly. For a
        // theatre run the showings also set the post's start/end dates, which is what
        // every other date-aware screen reads.
        if EventCategoryKind(rawValue: eventCategory)?.usesShowings == true, !eventShowings.isEmpty {
            submission.eventShowings = eventShowings
            submission.syncEventDatesToShowings()
        } else {
            submission.eventShowings = nil
        }

        if let imageData = selectedEventImageData {
            submission.thumbnailData = imageData
        }
    }
    
    private func configureFilmSubmission(_ submission: inout Submission) {
        submission.logline = logline
        submission.genres = Array(selectedGenres)
        submission.releaseYear = filmReleaseYear
        submission.ageRating = selectedAgeRating.rawValue
        submission.studio = selectedStudio
        submission.festivalBound = filmFestivalBound
        
        // Add cast
        var orderedCast: [OrderedEntry] = []
        for entry in castInfo.primaries + castInfo.secondaries + castInfo.extras {
            if !entry.performer.isEmpty && !entry.role.isEmpty {
                orderedCast.append(OrderedEntry(role: entry.role, name: entry.performer, profileID: entry.profileID))
            }
        }
        submission.orderedCast = orderedCast
        
        // Add crew
        let (_, orderedCrew) = createOrderedCrewData()
        submission.orderedCrew = orderedCrew
        
        // Add video
        if let videoURL = selectedVideoURL {
            let fileName = "video_\(submission.id.uuidString).\(videoURL.pathExtension)"
            // Outgoing upload copy lives in the media cache (bounded, backup-excluded);
            // it's deleted once the CloudKit upload confirms (see `saveSubmissionToCloudKit`).
            if let mediaDir = FileManager.default.mediaCacheDirectory {
                let destinationURL = mediaDir.appendingPathComponent(fileName)
                do {
                    try? FileManager.default.removeItem(at: destinationURL)
                    try FileManager.default.copyItem(at: videoURL, to: destinationURL)
                    submission.videoFileName = fileName
                } catch {
                    print("Error copying video: \(error)")
                }
            }
        }
        
        if let thumbnail = videoThumbnail {
            submission.thumbnailData = thumbnail.jpegData(compressionQuality: 0.7)
        }

        // Trailer video: copy the picked file into the media cache under the deterministic
        // name the upload (`Film.toCloudKitRecord`) and on-demand download expect.
        if let trailerURL = selectedTrailerURL {
            let fileName = "\(submission.id.uuidString)_trailer.mov"
            if let mediaDir = FileManager.default.mediaCacheDirectory {
                let destinationURL = mediaDir.appendingPathComponent(fileName)
                let didAccess = trailerURL.startAccessingSecurityScopedResource()
                defer { if didAccess { trailerURL.stopAccessingSecurityScopedResource() } }
                do {
                    try? FileManager.default.removeItem(at: destinationURL)
                    try FileManager.default.copyItem(at: trailerURL, to: destinationURL)
                    submission.trailerFileName = fileName
                } catch {
                    print("❌ Error copying trailer: \(error.localizedDescription)")
                }
            }
        }

        // BTS photos & stills: write each picked image to the media cache and store the
        // resulting file names on the submission.
        submission.btsImageFileNames = persistFilmExtraImages(filmBTSImages, submissionID: submission.id, kind: "bts")
        submission.stillImageFileNames = persistFilmExtraImages(filmStillImages, submissionID: submission.id, kind: "still")
    }

    private func configurePhotographySubmission(_ submission: inout Submission) {
        submission.artist = artist
        submission.releaseYear = photographyReleaseYear
        // Photography's description round-trips through `details` (the Photography model
        // stores it as `photographyDescription`).
        submission.details = photographyDescription
        submission.equipment = photographyEquipment
        submission.orderedCrew = photographyCredits.toOrderedEntries()

        // Persist the picked gallery images to the media cache under the deterministic
        // names the CloudKit upload/parse expect (`<id>_photo_<n>.jpg`).
        submission.photoImageFileNames = persistFilmExtraImages(photographyImages, submissionID: submission.id, kind: "photo")

        // The first image doubles as the post's thumbnail.
        if let first = photographyImages.first {
            submission.thumbnailData = first.jpegData(compressionQuality: 0.7)
        }
    }

    private func configureDesignSubmission(_ submission: inout Submission) {
        submission.designCategory = designCategory
        submission.releaseYear = designReleaseYear
        // Design's description round-trips through `details` (the Design model stores it
        // as `designDescription`).
        submission.details = designDescription
        submission.orderedCrew = designCredits.toOrderedEntries()

        // Persist the picked images to the media cache under the deterministic names the
        // CloudKit upload/parse expect (`<id>_design_<n>.jpg`).
        submission.designImageFileNames = persistFilmExtraImages(designImages, submissionID: submission.id, kind: "design")

        // The optional video: copied into the media cache as the outgoing upload copy
        // (deleted once the CloudKit upload confirms, like the film/reel videos).
        if let videoURL = designVideoURL {
            let fileName = "video_\(submission.id.uuidString).\(videoURL.pathExtension)"
            if let mediaDir = FileManager.default.mediaCacheDirectory {
                let destinationURL = mediaDir.appendingPathComponent(fileName)
                do {
                    try? FileManager.default.removeItem(at: destinationURL)
                    try FileManager.default.copyItem(at: videoURL, to: destinationURL)
                    submission.videoFileName = fileName
                } catch {
                    print("Error copying design video: \(error)")
                }
            }
        }

        // The first image doubles as the post's thumbnail; a video-only post uses the
        // video's first frame instead.
        if let first = designImages.first {
            submission.thumbnailData = first.jpegData(compressionQuality: 0.7)
        } else if let frame = designVideoFirstFrame {
            submission.thumbnailData = frame.jpegData(compressionQuality: 0.7)
        }
    }

    private func configureMusicSubmission(_ submission: inout Submission) {
        submission.artist = artist
        submission.musicCategory = musicCategory
        submission.genres = Array(selectedMusicGenres)
        submission.releaseYear = musicReleaseYear
        submission.explicit = explicitRating
        // Drop the pre-seeded role rows the credits form fills in — an entry with no
        // name isn't a real credit and shouldn't be saved or shown on the card.
        submission.orderedRecording = musicRecordingCredits.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        submission.orderedProduction = musicProductionCredits.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        submission.spotifyLink = normalizedLink(musicSpotifyLink)
        submission.appleMusicLink = normalizedLink(musicAppleMusicLink)
        submission.youtubeMusicLink = normalizedLink(musicYouTubeMusicLink)
        submission.soundcloudLink = normalizedLink(musicSoundcloudLink)
        submission.lyrics = musicLyrics.trimmingCharacters(in: .whitespacesAndNewlines)

        if let audioURL = selectedAudioURL {
            let ext = audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension
            // Match the download naming (`<id>_audio.<ext>`) so this local copy is reused
            // after a reload instead of being re-fetched from CloudKit.
            let fileName = "\(submission.id.uuidString)_audio.\(ext)"
            // Outgoing upload copy lives in the media cache (bounded, backup-excluded);
            // it's deleted once the CloudKit upload confirms (see `saveSubmissionToCloudKit`).
            if let mediaDir = FileManager.default.mediaCacheDirectory {
                let destinationURL = mediaDir.appendingPathComponent(fileName)
                // The source may be a security-scoped Files URL (audio can only be
                // picked from Files); open access before copying or the copy silently
                // fails and the post uploads with no `musicAudio` asset — no player.
                let didAccess = audioURL.startAccessingSecurityScopedResource()
                defer { if didAccess { audioURL.stopAccessingSecurityScopedResource() } }
                do {
                    try? FileManager.default.removeItem(at: destinationURL)
                    try FileManager.default.copyItem(at: audioURL, to: destinationURL)
                    submission.audioFileName = fileName
                } catch {
                    print("❌ Error copying audio: \(error.localizedDescription)")
                }
            }
        }

        // EP/Album tracks beyond the first. Copied into the media cache under the
        // deterministic `<id>_track<n>.<ext>` names the upload and download both expect.
        let trackNames = persistMusicTracks(additionalAudioURLs, submissionID: submission.id)
        submission.musicTrackFileNames = trackNames.isEmpty ? nil : trackNames

        if let coverData = selectedAlbumCoverData {
            submission.thumbnailData = coverData
        }
    }
    
    /// Normalizes a user-entered streaming link: trims whitespace and prepends
    /// "https://" if no scheme is present, so the card's `Link` opens in the browser.
    private func normalizedLink(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    private func createOrderedCrewData() -> ([String: String], [OrderedEntry]) {
        // The crew form is now a grouped model (roles → people), so flatten it directly.
        // Multiple people can share a role (e.g. two producers); each becomes its own
        // ordered entry, in the order shown.
        let orderedCrew = crewInfo.toOrderedEntries()
        var crewDict: [String: String] = [:]
        for entry in orderedCrew {
            crewDict[entry.role] = entry.name
        }
        return (crewDict, orderedCrew)
    }
    
    // MARK: - Helper Functions
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day, .year], from: date)
        let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        
        guard let month = components.month,
              let day = components.day,
              let year = components.year else {
            return ""
        }
        
        return "\(monthNames[month - 1]) \(day), \(year)"
    }
    
    private func resetForm() {
        editingDraftID = nil
        title = ""
        logline = ""
        explicitRating = false
        crewInfo = CrewInfo()
        castInfo = CastInfo()
        selectedVideoURL = nil
        selectedAudioURL = nil
        videoThumbnail = nil
        videoFirstFrame = nil
        videoThumbnailIsCustom = false
        videoLoadError = false
        isUploadingVideo = false
        filmFestivalBound = false
        selectedTrailerURL = nil
        trailerFirstFrame = nil
        filmBTSImages = []
        filmStillImages = []
        selectedGenres = []
        filmReleaseYear = ""
        selectedAgeRating = .general
        selectedProjectImageData = nil
        selectedProjectImageItem = nil
        selectedEventImageData = nil
        selectedEventImageItem = nil
        eventCategory = ""
        eventStartDate = Date()
        eventEndDate = Date().addingTimeInterval(3600)
        eventLocation = ""
        eventHost = ""
        eventTicketsURL = ""
        eventExpectations = ""
        eventApplicationURL = ""
        eventLineup = ""
        eventShowings = []

        // Talent Reel fields
        selectedReelVideoURL = nil
        reelVideoThumbnail = nil
        reelVideoFirstFrame = nil
        reelVideoThumbnailIsCustom = false
        reelVideoLoadError = false
        isUploadingReelVideo = false
        reelType = ""
        reelDescription = ""
        reelFeaturedWorkIDs = []
        reelFeaturedWorkManual = []
        reelReleaseYear = ""

        // Project fields
        projectCategory = ""
        projectWriters = ""
        projectGenre = ""
        shootStartDate = Date()
        shootEndDate = Date()
        projectReleaseDate = Date()
        castNeeded = []
        crewNeeded = []
        selectedProjectScriptURL = nil
        projectSlides = []

        // Film fields
        selectedStudio = ""

        // Music fields
        artist = ""
        selectedMusicGenres = []
        musicCategory = ""
        musicReleaseYear = ""
        musicRecordingCredits = []
        musicProductionCredits = []
        musicSpotifyLink = ""
        musicAppleMusicLink = ""
        musicYouTubeMusicLink = ""
        musicSoundcloudLink = ""
        musicLyrics = ""
        additionalAudioURLs = []
        selectedAlbumCoverData = nil
        selectedMusicVideoURL = nil
        musicVideoThumbnail = nil

        // Photography fields
        photographyImages = []
        photographyDescription = ""
        photographyReleaseYear = ""
        photographyEquipment = EquipmentInfo()
        photographyCredits = CrewInfo(orderedEntries: [])

        // Design fields
        designImages = []
        designDescription = ""
        designCategory = ""
        designReleaseYear = ""
        designVideoURL = nil
        designVideoFirstFrame = nil
        designCredits = CrewInfo(orderedEntries: [])
    }
    
    // MARK: - Submission Logic
    
    /// Builds a fully-configured `Submission` from the current form state.
    /// Shared by both posting and saving a draft.
    private func buildSubmission(type contentTypeOverride: MediaType? = nil) -> Submission? {
        guard let contentType = contentTypeOverride ?? selectedContentType else { return nil }

        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let submittedBy = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)

        var submission = Submission(
            id: editingDraftID ?? UUID(),
            type: contentType,
            title: title,
            details: "",
            isApproved: true,
            submittedBy: submittedBy.isEmpty ? "Anonymous" : submittedBy
        )

        switch contentType {
        case .reel:
            configureReelSubmission(&submission)
        case .project:
            configureProjectSubmission(&submission)
        case .event:
            configureEventSubmission(&submission)
        case .film:
            configureFilmSubmission(&submission)
        case .music:
            configureMusicSubmission(&submission)
        case .photography:
            configurePhotographySubmission(&submission)
        case .design:
            configureDesignSubmission(&submission)
        }

        return submission
    }

    private func submitPost() {
        guard let submission = buildSubmission() else { return }

        // `add` returns nil on success, or the reason it was rejected. It also kicks
        // off the CloudKit upload (with progress tracking) in the background.
        if let error = store.add(submission) {
            errorMessage = error
            showErrorAlert = true
            return
        }

        // If this post came from a resumed draft, remove that draft now that it's posted.
        if editingDraftID != nil {
            store.deleteDraft(submission)
        }

        // Keep the form open and show a live upload wheel. Begin immediately so the
        // wheel appears without waiting for the first CloudKit progress packet; the
        // form auto-dismisses once the upload finishes (see onChange in the form).
        lastSubmittedSubmission = submission
        uploadCenter.begin(submission.id, title: submission.title, type: submission.type)
        activeUploadID = submission.id
    }

    /// Re-runs a failed upload, keeping the progress wheel live.
    private func retryUpload() {
        guard let submission = lastSubmittedSubmission else { return }
        store.retryUpload(submission)
    }

    /// Called once the in-flight upload finishes: stop tracking, close the form,
    /// reset it, and show a brief "Posted!" toast.
    private func finishUploadAndDismiss() {
        if let id = activeUploadID { uploadCenter.clear(id) }
        activeUploadID = nil
        lastSubmittedSubmission = nil
        // The post is done; the impending dismissal shouldn't auto-draft it.
        suppressAutoDraft = true
        selectedContentType = nil   // dismisses the sheet (onDismiss resets the form)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showPostedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.25)) {
                showPostedToast = false
            }
        }
    }

    /// Saves the current form as a local draft, then closes the form and resets it.
    private func saveDraft() {
        guard let submission = buildSubmission() else { return }
        store.saveDraft(submission)
        // We've already saved; don't let the dismissal auto-draft a second copy.
        suppressAutoDraft = true
        selectedContentType = nil
        resetForm()
        showDraftSavedToastBriefly()
    }

    /// Auto-saves the current form as a draft when the sheet is swiped away after
    /// more than two minutes of work with at least two fields filled. Skipped when
    /// Post or the manual Draft button already persisted the work. Runs from the
    /// sheet's `onDismiss`, before `resetForm()`, so the field state is still intact;
    /// `selectedContentType` is already `nil` by then, so `activeFormType` supplies
    /// the type.
    private func autoSaveDraftIfNeeded() {
        defer {
            suppressAutoDraft = false
            formOpenedAt = nil
            activeFormType = nil
        }
        guard !suppressAutoDraft,
              let contentType = activeFormType,
              let openedAt = formOpenedAt,
              Date().timeIntervalSince(openedAt) > 120,
              filledFieldCount(for: contentType) >= 2,
              let submission = buildSubmission(type: contentType) else { return }
        store.saveDraft(submission)
        showDraftSavedToastBriefly()
    }

    /// Counts how many meaningful fields the user filled in for `type`, used to
    /// decide whether an abandoned form is worth auto-drafting. Mirrors the fields
    /// restored in `loadDraft`.
    private func filledFieldCount(for type: MediaType) -> Int {
        func filled(_ s: String) -> Bool {
            !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var flags: [Bool] = [filled(title)]
        switch type {
        case .reel:
            flags += [
                filled(reelType),
                filled(reelDescription),
                filled(artist),
                filled(reelReleaseYear),
                !reelFeaturedWorkIDs.isEmpty || !reelFeaturedWorkManual.isEmpty,
                selectedReelVideoURL != nil
            ]
        case .project:
            flags += [
                filled(logline),
                filled(projectCategory),
                filled(projectWriters),
                filled(projectGenre),
                !castNeeded.isEmpty,
                !crewNeeded.isEmpty,
                selectedProjectImageData != nil,
                selectedProjectScriptURL != nil,
                !projectSlides.isEmpty
            ]
        case .event:
            flags += [
                filled(eventCategory),
                filled(eventLocation),
                filled(eventHost),
                filled(eventTicketsURL),
                filled(eventExpectations),
                filled(eventApplicationURL),
                filled(eventLineup),
                selectedEventImageData != nil
            ]
        case .film:
            flags += [
                filled(logline),
                !selectedGenres.isEmpty,
                filled(filmReleaseYear),
                selectedAgeRating != .general,
                filled(selectedStudio) && selectedStudio != "Independent",
                filmFestivalBound,
                selectedVideoURL != nil,
                !castInfo.toOrderedEntries().isEmpty,
                !crewInfo.toOrderedEntries().isEmpty
            ]
        case .music:
            flags += [
                filled(artist),
                filled(musicCategory),
                !selectedMusicGenres.isEmpty,
                filled(musicReleaseYear),
                explicitRating,
                !musicRecordingCredits.isEmpty,
                !musicProductionCredits.isEmpty,
                filled(musicSpotifyLink) || filled(musicAppleMusicLink)
                    || filled(musicYouTubeMusicLink) || filled(musicSoundcloudLink),
                filled(musicLyrics),
                selectedAudioURL != nil,
                selectedAlbumCoverData != nil,
                selectedMusicVideoURL != nil
            ]
        case .photography:
            flags += [
                filled(artist),
                filled(photographyDescription),
                filled(photographyReleaseYear),
                !photographyImages.isEmpty
            ]
        case .design:
            flags += [
                filled(designDescription),
                filled(designCategory),
                filled(designReleaseYear),
                !designImages.isEmpty || designVideoURL != nil
            ]
        }
        return flags.filter { $0 }.count
    }

    /// Shows the "Draft Saved!" confirmation toast for two seconds. Shared by the
    /// manual Draft button and the auto-draft-on-dismiss path.
    private func showDraftSavedToastBriefly() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showDraftSavedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.25)) {
                showDraftSavedToast = false
            }
        }
    }

    // MARK: - Draft Resume

    /// Called after the Drafts sheet fully dismisses so we can open the form sheet
    /// cleanly (presenting one sheet while another dismisses is unreliable).
    private func resumePendingDraftIfNeeded() {
        guard let draft = pendingDraftToResume else { return }
        pendingDraftToResume = nil
        loadDraft(draft)
    }

    /// Populates the form's state from a saved draft and opens the matching form.
    /// Note: project shoot/release dates are stored as display strings and reset to
    /// today on resume; cast entries are restored under "Primary".
    private func loadDraft(_ draft: Submission) {
        resetForm()
        editingDraftID = draft.id
        title = draft.title
        logline = draft.logline

        switch draft.type {
        case .reel:
            reelType = draft.reelType
            reelDescription = draft.reelDescription
            artist = draft.artist
            reelReleaseYear = draft.releaseYear
            reelFeaturedWorkIDs = draft.featuredWorkIDs
            reelFeaturedWorkManual = draft.featuredWorkManual
            selectedReelVideoURL = draft.videoURL
            if let data = draft.thumbnailData {
                reelVideoThumbnail = UIImage(data: data)
                reelVideoThumbnailIsCustom = true
            }
            // Regenerate the video's first frame for the video row (won't overwrite a
            // custom poster — generateReelThumbnail respects reelVideoThumbnailIsCustom).
            if let videoURL = draft.videoURL {
                generateReelThumbnail(from: videoURL)
            }
        case .project:
            projectCategory = draft.projectType
            projectWriters = draft.writers
            projectGenre = draft.genres.first ?? ""
            castNeeded = draft.castNeeded
            crewNeeded = draft.crewNeeded
            selectedProjectImageData = draft.thumbnailData
            selectedProjectScriptURL = draft.scriptURL
            // Restore the slideshow from its persisted media-cache copies.
            projectSlides = draft.projectSlideURLs.compactMap { UIImage(contentsOfFile: $0.path) }
            castInfo = makeCastInfo(from: draft.orderedCast)
            crewInfo = makeCrewInfo(from: draft.orderedCrew)
        case .event:
            eventStartDate = draft.eventStartDate ?? Date()
            eventEndDate = draft.eventEndDate ?? Date().addingTimeInterval(3600)
            eventLocation = draft.eventLocation ?? ""
            eventTicketsURL = draft.eventTicketsURL ?? ""
            eventCategory = draft.genres.first ?? ""
            eventHost = draft.eventHost
            eventExpectations = draft.eventExpectations ?? ""
            eventApplicationURL = draft.eventApplicationURL ?? ""
            eventLineup = draft.eventLineup ?? ""
            eventShowings = draft.eventShowings ?? []
            selectedEventImageData = draft.thumbnailData
        case .film:
            selectedGenres = Set(draft.genres)
            filmReleaseYear = draft.releaseYear
            selectedAgeRating = AgeRating(rawValue: draft.ageRating) ?? .general
            // Empty means the draft was saved before a Category was picked, so the form
            // reopens on the Category step.
            selectedStudio = draft.studio
            filmFestivalBound = draft.festivalBound
            selectedVideoURL = draft.videoURL
            if let data = draft.thumbnailData {
                videoThumbnail = UIImage(data: data)
                videoThumbnailIsCustom = true
            }
            // Regenerate the video's first frame for the video row (won't overwrite a
            // custom poster — generateThumbnail respects videoThumbnailIsCustom).
            if let videoURL = draft.videoURL {
                generateThumbnail(from: videoURL)
            }
            castInfo = makeCastInfo(from: draft.orderedCast)
            crewInfo = makeCrewInfo(from: draft.orderedCrew)
        case .music:
            artist = draft.artist
            musicCategory = draft.musicCategory
            selectedMusicGenres = Set(draft.genres)
            musicReleaseYear = draft.releaseYear
            explicitRating = draft.explicit
            musicRecordingCredits = draft.orderedRecording
            musicProductionCredits = draft.orderedProduction
            musicSpotifyLink = draft.spotifyLink
            musicAppleMusicLink = draft.appleMusicLink
            musicYouTubeMusicLink = draft.youtubeMusicLink
            musicSoundcloudLink = draft.soundcloudLink
            musicLyrics = draft.lyrics
            selectedAudioURL = draft.audioURL
            additionalAudioURLs = (draft.musicTrackFileNames ?? [])
                .compactMap { FileManager.default.mediaFileURL(named: $0) }
            selectedAlbumCoverData = draft.thumbnailData
        case .photography:
            artist = draft.artist
            photographyDescription = draft.details
            photographyReleaseYear = draft.releaseYear
            photographyEquipment = draft.equipment
            photographyCredits = CrewInfo(orderedEntries: draft.orderedCrew)
            // Restore the gallery images from their persisted media-cache copies.
            photographyImages = draft.photoImageURLs.compactMap { UIImage(contentsOfFile: $0.path) }
        case .design:
            designDescription = draft.details
            designCategory = draft.designCategory
            designReleaseYear = draft.releaseYear
            designCredits = CrewInfo(orderedEntries: draft.orderedCrew)
            designVideoURL = draft.videoURL
            // Restore the images from their persisted media-cache copies.
            designImages = draft.designImageURLs.compactMap { UIImage(contentsOfFile: $0.path) }
        }

        selectedContentType = draft.type
    }

    /// Rebuilds a `CastInfo` from stored entries. The original primary/secondary/
    /// extra grouping isn't persisted, so everything is restored under "Primary".
    private func makeCastInfo(from entries: [OrderedEntry]) -> CastInfo {
        var cast = CastInfo()
        cast.primaries = entries.map { CastEntry(performer: $0.name, role: $0.role, profileID: $0.profileID) }
        return cast
    }

    /// Rebuilds a `CrewInfo` from stored entries, grouping people by role.
    private func makeCrewInfo(from entries: [OrderedEntry]) -> CrewInfo {
        CrewInfo(orderedEntries: entries)
    }
}

#Preview("Share") {
    ShareView_3()
}
// MARK: - Helper Views for Video Upload States
// Note: VideoErrorStateView, VideoSuccessStateView, VideoPickerView, 
// DocumentPickerView, and ThumbnailSelectionView are now defined in SharedSubmissionTypes.swift


// =====================================================================
// MARK: - Content Type Selector (merged from ContentTypeSelectorPage.swift)
// =====================================================================
//
//  The "What are you sharing?" category chooser shown at the top of the Share tab.
//

// MARK: - Content Type Selector Page
struct ContentTypeSelectorPage: View {
    @Binding var selectedType: MediaType?
    @Binding var showDraftsSheet: Bool
    @Binding var showInfoSheet: Bool
    @Binding var showHelpSheet: Bool

    // MARK: - Toolbar Format Per Screen Size
    /// Tunable toolbar item sizes and positions for the Share page.
    /// - `draftsWidth/pillHeight/draftsFontSize`: size of the Drafts pill.
    /// - `infoWidth/infoFontSize`: size of the info button pill.
    /// - `pillOffsetX/Y`: nudges both pills from their default spot.
    /// - `logoHeight`: height of the Share logo image.
    private struct ToolbarFormat {
        var draftsWidth: CGFloat
        var draftsFontSize: CGFloat
        var infoWidth: CGFloat
        var infoFontSize: CGFloat
        var pillHeight: CGFloat
        var pillOffsetX: CGFloat
        var pillOffsetY: CGFloat
        var logoHeight: CGFloat
        // iPad-only knobs (default to no-ops so iPhone layout is unaffected):
        /// Extra horizontal/vertical nudge applied to the logo.
        var logoOffsetX: CGFloat = 0
        var logoOffsetY: CGFloat = 0
        /// Fixed length (width) of the Drafts pill. `nil` falls back to `draftsWidth`.
        var pillLength: CGFloat? = nil
        /// How far down the orange toolbar bar extends.
        var barHeight: CGFloat = 60

        /// Returns a copy with every size (logo, both pills, fonts, bar height, pill
        /// length) multiplied by `k`. Positions/offsets are left unchanged.
        func scaled(by k: CGFloat) -> ToolbarFormat {
            guard k != 1 else { return self }
            var f = self
            f.draftsWidth *= k
            f.draftsFontSize *= k
            f.infoWidth *= k
            f.infoFontSize *= k
            f.pillHeight *= k
            f.logoHeight *= k
            f.barHeight *= k
            if let p = f.pillLength { f.pillLength = p * k }
            return f
        }
    }

    /// Universal toolbar resizer: one knob that scales every toolbar element (logo, pills,
    /// fonts, bar height) across ALL screen sizes at once, keeping the per-device
    /// proportions tuned below. 1.0 = current size; 1.2 = 20% larger; 0.85 = 15% smaller.
    /// Positions and offsets are untouched.
    private var toolbarSizeMultiplier: CGFloat { 1.0 }

    // MARK: - Per-Element Toolbar Tuning
    private var shareSize: CGFloat { 1.7 }       // size
    private var shareOffsetX: CGFloat { 0 }      // + = right
    private var shareOffsetY: CGFloat { 0 }      // + = down

    private var draftsSize: CGFloat { 1.1 }
    private var draftsOffsetX: CGFloat { 0 }      // + = right
    private var draftsOffsetY: CGFloat { -4 }      // + = down
    
    private var infoHelpSize: CGFloat { 1.1 }
    private var infoHelpOffsetX: CGFloat { 1 }
    private var infoHelpOffsetY: CGFloat { -4 }
    private var infoHelpPadding: CGFloat { 0 }    // space reserved around each

    /// The per-device format, universally scaled by `toolbarSizeMultiplier`, with the
    /// Share asset additionally scaled by `shareSize`.
    private var toolbarFormat: ToolbarFormat {
        var f = baseToolbarFormat.scaled(by: toolbarSizeMultiplier)
        f.logoHeight *= shareSize
        return f
    }

    /// Adjust the values in each case to tune the toolbar for that screen size.
    private var baseToolbarFormat: ToolbarFormat {
        switch ScreenSizeFormat.current {
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return ToolbarFormat(draftsWidth: 60, draftsFontSize: 14, infoWidth: 50, infoFontSize: 18, pillHeight: 40, pillOffsetX: 0, pillOffsetY: 0, logoHeight: 29, barHeight: 50)
        case .size402x874: // iPhone 16 Pro, 17
            return ToolbarFormat(draftsWidth: 61, draftsFontSize: 14, infoWidth: 51, infoFontSize: 18, pillHeight: 41, pillOffsetX: 0, pillOffsetY: 0, logoHeight: 30, barHeight: 50)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return ToolbarFormat(draftsWidth: 66, draftsFontSize: 15, infoWidth: 55, infoFontSize: 20, pillHeight: 44, pillOffsetX: 0, pillOffsetY: 0, logoHeight: 32, barHeight: 52)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return ToolbarFormat(draftsWidth: 67, draftsFontSize: 16, infoWidth: 56, infoFontSize: 20, pillHeight: 45, pillOffsetX: 0, pillOffsetY: 0, logoHeight: 33, barHeight: 53)
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return ToolbarFormat(draftsWidth: 90, draftsFontSize: 20, infoWidth: 74, infoFontSize: 26, pillHeight: 56, pillOffsetX: 0, pillOffsetY: 0, logoHeight: 41, logoOffsetX: 0, logoOffsetY: 0, pillLength: nil, barHeight: 66)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return ToolbarFormat(draftsWidth: 104, draftsFontSize: 23, infoWidth: 84, infoFontSize: 30, pillHeight: 64, pillOffsetX: -30, pillOffsetY: -10, logoHeight: 47, logoOffsetX: 30, logoOffsetY: -10, pillLength: nil, barHeight: 72)
        }
    }

    // MARK: - Feed Format Per Screen Size
    /// Tunable sizing for the main feed (the title and content type cards).
    /// - `titleFontSize`: size of the "What are you sharing?" title.
    /// - `cardSpacing`: vertical gap between the content type cards.
    /// - `horizontalPadding`: insets the title and cards from the screen edges.
    /// - `cardIconSize`: size of the orange icon square in each card (the
    ///   image inside scales with it).
    /// - `cardVerticalPadding`: space above/below a card's contents. Together with
    ///   `cardIconSize` this sets how tall each card is — kept tight on iPhone so
    ///   all seven types fit on screen without scrolling.
    private struct FeedFormat {
        var titleFontSize: CGFloat
        var cardSpacing: CGFloat
        var horizontalPadding: CGFloat
        var cardIconSize: CGFloat
        var cardVerticalPadding: CGFloat
    }

    /// Adjust the values in each case to tune the feed for that screen size.
    private var feedFormat: FeedFormat {
        switch ScreenSizeFormat.current {
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return FeedFormat(titleFontSize: 34, cardSpacing: 12, horizontalPadding: 20, cardIconSize: 54, cardVerticalPadding: 11)
        case .size402x874: // iPhone 16 Pro, 17
            return FeedFormat(titleFontSize: 34, cardSpacing: 12, horizontalPadding: 20, cardIconSize: 55, cardVerticalPadding: 11)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return FeedFormat(titleFontSize: 36, cardSpacing: 13, horizontalPadding: 22, cardIconSize: 59, cardVerticalPadding: 12)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return FeedFormat(titleFontSize: 37, cardSpacing: 13, horizontalPadding: 22, cardIconSize: 61, cardVerticalPadding: 12)
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return FeedFormat(titleFontSize: 48, cardSpacing: 18, horizontalPadding: 80, cardIconSize: 82, cardVerticalPadding: 14)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return FeedFormat(titleFontSize: 56, cardSpacing: 20, horizontalPadding: 140, cardIconSize: 95, cardVerticalPadding: 15)
        }
    }

    // ORANGE HEADER
    private var topBar: some View {
        HStack(spacing: 1) {
            Image("Share")
                .resizable()
                .scaledToFit()
                .frame(height: toolbarFormat.logoHeight)
                .offset(x: -4, y: -2)
                .offset(x: toolbarFormat.logoOffsetX, y: toolbarFormat.logoOffsetY)
                .offset(x: shareOffsetX, y: shareOffsetY)
            Spacer(minLength: 8)
            filterPill
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // Orange fills the bar and bleeds up behind the status bar / Dynamic Island.
        .frame(maxWidth: .infinity, minHeight: toolbarFormat.barHeight, maxHeight: toolbarFormat.barHeight)
        .background(Color.brandOrange, ignoresSafeAreaEdges: .top)
    }

    // TOOLBAR PILLS (distinct buttons with space between them)
    private var filterPill: some View {
        HStack(spacing: 10) {
            // Drafts button
            Button {
                showDraftsSheet = true
            } label: {
                Text("Drafts")
                    .font(.system(size: toolbarFormat.draftsFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: toolbarFormat.pillLength ?? toolbarFormat.draftsWidth, height: toolbarFormat.pillHeight)
                    .padding(.horizontal, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(Color.pillActive))
            .scaleEffect(draftsSize)
            .offset(x: draftsOffsetX, y: draftsOffsetY)

            // Info button
            Button {
                showInfoSheet = true
            } label: {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: toolbarFormat.infoFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: toolbarFormat.infoWidth, height: toolbarFormat.pillHeight)
                    .padding(.horizontal,-2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(Color.pillActive))
            .padding(infoHelpPadding)
            .scaleEffect(infoHelpSize)
            .offset(x: infoHelpOffsetX, y: infoHelpOffsetY)

            // Help button
            Button {
                showHelpSheet = true
            } label: {
                Image(systemName: "questionmark.diamond.fill")
                    .font(.system(size: toolbarFormat.infoFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: toolbarFormat.infoWidth, height: toolbarFormat.pillHeight)
                    .padding(.horizontal,-2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(Color.pillActive))
            .padding(infoHelpPadding)
            .scaleEffect(infoHelpSize)
            .offset(x: infoHelpOffsetX, y: infoHelpOffsetY)
        }
        .offset(x: toolbarFormat.pillOffsetX, y: toolbarFormat.pillOffsetY)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    topBar

                Spacer() // Balance space above the cards so they center vertically

                // Content type cards - non-scrollable, stacked vertically
                VStack(spacing: feedFormat.cardSpacing) {
                    ContentTypeCard(
                        imageName: "Film",
                        title: "Film",
                        subtitle: SubmissionTypeSubtitles.subtitle(for: .film),
                        color: .black,
                        iconSize: feedFormat.cardIconSize,
                        verticalPadding: feedFormat.cardVerticalPadding
                    ) {
                        selectedType = .film
                    }

                    ContentTypeCard(
                        imageName: "Music",
                        title: "Music",
                        subtitle: SubmissionTypeSubtitles.subtitle(for: .music),
                        color: .black,
                        iconSize: feedFormat.cardIconSize,
                        verticalPadding: feedFormat.cardVerticalPadding
                    ) {
                        selectedType = .music
                    }

                    ContentTypeCard(
                        imageName: "Performance",
                        title: MediaType.reel.displayName,
                        subtitle: SubmissionTypeSubtitles.subtitle(for: .reel),
                        color: .black,
                        iconSize: feedFormat.cardIconSize,
                        verticalPadding: feedFormat.cardVerticalPadding
                    ) {
                        selectedType = .reel
                    }

                    ContentTypeCard(
                        imageName: "Photography",
                        title: "Photography",
                        subtitle: SubmissionTypeSubtitles.subtitle(for: .photography),
                        color: .black,
                        iconSize: feedFormat.cardIconSize,
                        verticalPadding: feedFormat.cardVerticalPadding
                    ) {
                        selectedType = .photography
                    }

                    ContentTypeCard(
                        imageName: "Design",
                        title: "Design",
                        subtitle: SubmissionTypeSubtitles.subtitle(for: .design),
                        color: .black,
                        iconSize: feedFormat.cardIconSize,
                        verticalPadding: feedFormat.cardVerticalPadding
                    ) {
                        selectedType = .design
                    }

                    ContentTypeCard(
                        imageName: "Project",
                        title: "Project",
                        subtitle: SubmissionTypeSubtitles.subtitle(for: .project),
                        color: .black,
                        iconSize: feedFormat.cardIconSize,
                        verticalPadding: feedFormat.cardVerticalPadding
                    ) {
                        selectedType = .project
                    }

                    ContentTypeCard(
                        imageName: "Event",
                        title: "Event",
                        subtitle: SubmissionTypeSubtitles.subtitle(for: .event),
                        color: .black,
                        iconSize: feedFormat.cardIconSize,
                        verticalPadding: feedFormat.cardVerticalPadding
                    ) {
                        selectedType = .event
                    }
                }
                .padding(.horizontal, feedFormat.horizontalPadding)

                Spacer() // Balance space below the cards so they center vertically
            }
            // Lock the content to the (keyboard-independent) container size so it can
            // never shift up or down when a submission sheet's keyboard appears.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Content Type Card
struct ContentTypeCard: View {
    /// Named image asset for the icon (e.g. "Film"). Use `systemImageName` instead for
    /// types without a bundled asset.
    var imageName: String? = nil
    /// SF Symbol name for the icon, used when there's no bundled image asset.
    var systemImageName: String? = nil
    let title: String
    /// One-line tagline shown under the title. Copy lives in `SubmissionTypeSubtitles`.
    var subtitle: String? = nil
    let color: Color
    var iconSize: CGFloat = 60
    /// Space above/below the card's contents; the main lever on the card's height.
    var verticalPadding: CGFloat = 16
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon (the inner image keeps its original proportion of the square)
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.brandOrange)
                        .frame(width: iconSize, height: iconSize)

                    if let systemImageName {
                        Image(systemName: systemImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: iconSize * 34 / 60, height: iconSize * 34 / 60)
                            .foregroundColor(.white)
                    } else if let imageName {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: iconSize * 43.75 / 60, height: iconSize * 43.75 / 60)
                            .foregroundColor(.white)
                    }
                }

                // Text content — the type name with its tagline underneath.
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, verticalPadding)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(ContentTypeCardButtonStyle())
        .tint(.primary) // Uses primary color (black/white based on scheme) for any tint
    }
}

/// Presses the entire card (rectangle + icon) as one cohesive unit: a subtle
/// scale-down and darken on press instead of the default per-content opacity fade.
struct ContentTypeCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("Category Selector") {
    ContentTypeSelectorPage(
        selectedType: .constant(nil),
        showDraftsSheet: .constant(false),
        showInfoSheet: .constant(false),
        showHelpSheet: .constant(false)
    )
}

// MARK: - Screen Size Previews

#if DEBUG

#Preview("Share 393 × 852", traits: .fixedLayout(width: 393, height: 852)) {
    let _ = (ScreenSizeFormat.previewOverride = .size393x852)
    ContentTypeSelectorPage(
        selectedType: .constant(nil),
        showDraftsSheet: .constant(false),
        showInfoSheet: .constant(false),
        showHelpSheet: .constant(false)
    )
}

#Preview("Share 402 × 874", traits: .fixedLayout(width: 402, height: 874)) {
    let _ = (ScreenSizeFormat.previewOverride = .size402x874)
    ContentTypeSelectorPage(
        selectedType: .constant(nil),
        showDraftsSheet: .constant(false),
        showInfoSheet: .constant(false),
        showHelpSheet: .constant(false)
    )
}

#Preview("Share 430 × 932", traits: .fixedLayout(width: 430, height: 932)) {
    let _ = (ScreenSizeFormat.previewOverride = .size430x932)
    ContentTypeSelectorPage(
        selectedType: .constant(nil),
        showDraftsSheet: .constant(false),
        showInfoSheet: .constant(false),
        showHelpSheet: .constant(false)
    )
}

#Preview("Share 440 × 956") {
    let _ = (ScreenSizeFormat.previewOverride = .size440x956)
    ContentTypeSelectorPage(
        selectedType: .constant(nil),
        showDraftsSheet: .constant(false),
        showInfoSheet: .constant(false),
        showHelpSheet: .constant(false)
    )
    .previewDevice("iPhone 16 Pro Max")
}

#endif


// =====================================================================
// MARK: - Submission Type Subtitles (merged from SubmissionTypeSubtitles.swift)
// =====================================================================
//
//  The one-line taglines that sit under each submission type name on the Share
//  page cards. Kept together so the copy can be edited in one place.
//

// MARK: - Submission Type Subtitles

/// Tagline copy for each submission type, keyed by `MediaType`.
///
/// Used by the Share cards in `ContentTypeSelectorPage`, and available anywhere else
/// a one-line description of a submission type is wanted.
enum SubmissionTypeSubtitles {

    /// The tagline for every submission type, in the order the Share page lists them.
    static let byType: [MediaType: String] = [
        .film:        "Frame your vision",
        .music:       "Sound that resonates",
        .reel:        "Take center stage",
        .photography: "Capture the moment",
        .design:      "Paint the walls",
        .project:     "Building something bigger",
        .event:       "Gather your people"
    ]

    /// The tagline for `type`, or an empty string if none is defined.
    static func subtitle(for type: MediaType) -> String {
        byType[type] ?? ""
    }
}
