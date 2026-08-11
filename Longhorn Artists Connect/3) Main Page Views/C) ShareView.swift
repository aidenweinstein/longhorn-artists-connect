//
//  CreateView.swift
//  Longhorn Artists Connect
//
//  Main view for creating and editing submissions (Films, Music, Reels, Projects, Events)
//
//  This file contains:
//  - Helper views for video/image picking and thumbnail selection
//  - ShareView_3: Main submission creation view
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
        
        init(completion: @escaping (Result<URL, Error>) -> Void) {
            self.completion = completion
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let result = results.first else {
                completion(.failure(NSError(domain: "VideoPicker", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cancelled"])))
                return
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
                DispatchQueue.main.async {
                    self.completion(.failure(NSError(domain: "VideoPicker", code: -3, userInfo: [NSLocalizedDescriptionKey: "No video type identifier found"])))
                }
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
            
            itemProvider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
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
                    
                    DispatchQueue.main.async {
                        self.completion(.success(tempURL))
                    }
                } catch {
                    print("❌ Failed to write video data: \(error.localizedDescription)")
                    // Try next approach
                    self.tryInPlaceFileRepresentation(from: itemProvider, typeIdentifier: typeIdentifier)
                }
            }
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
            
            itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error = error {
                    print("❌ All loading methods failed. Final error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.completion(.failure(error))
                    }
                    return
                }
                
                guard let url = url else {
                    print("❌ No URL returned from loadFileRepresentation")
                    DispatchQueue.main.async {
                        self.completion(.failure(NSError(domain: "VideoPicker", code: -2, userInfo: [NSLocalizedDescriptionKey: "Video URL not found"])))
                    }
                    return
                }
                
                print("✅ Successfully loaded video from: \(url.lastPathComponent)")
                self.copyVideoToTemp(from: url, typeIdentifier: typeIdentifier)
            }
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
                
                DispatchQueue.main.async {
                    self.completion(.success(tempURL))
                }
            } catch {
                print("❌ Failed to copy video file: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.completion(.failure(error))
                }
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

// MARK: - Reel Experience View
struct ReelExperienceView: View {
    @Binding var experiences: [ReelExperience]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            ForEach($experiences) { $exp in
                VStack(alignment: .leading) {
                    TextField("Project", text: $exp.project)
                    HStack {
                        Picker("Month", selection: $exp.month) {
                            ForEach(1...12, id: \.self) { month in
                                Text("\(month)").tag(month)
                            }
                        }
                        Picker("Year", selection: $exp.year) {
                            ForEach(2000...2030, id: \.self) { year in
                                Text("\(year)").tag(year)
                            }
                        }
                    }
                }
            }
            .onDelete { indexSet in
                experiences.remove(atOffsets: indexSet)
            }
            
            Button("Add Experience") {
                experiences.append(ReelExperience())
            }
        }
        .navigationTitle("Experience")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Reel Skills View
struct ReelSkillsView: View {
    @Binding var skills: [ReelSkill]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            ForEach($skills) { $skill in
                VStack(alignment: .leading) {
                    TextField("Skill", text: $skill.skill)
                    HStack {
                        Picker("Month", selection: $skill.month) {
                            ForEach(1...12, id: \.self) { month in
                                Text("\(month)").tag(month)
                            }
                        }
                        Picker("Year", selection: $skill.year) {
                            ForEach(2000...2030, id: \.self) { year in
                                Text("\(year)").tag(year)
                            }
                        }
                    }
                }
            }
            .onDelete { indexSet in
                skills.remove(atOffsets: indexSet)
            }
            
            Button("Add Skill") {
                skills.append(ReelSkill())
            }
        }
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
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
                        Button {
                            onResume(draft)
                            dismiss()
                        } label: {
                            DraftRow(draft: draft)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            store.deleteDraft(store.drafts[index])
                        }
                    }
                }
            }
            .navigationTitle("Drafts")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false) // Allow pull to dismiss
    }
}

// MARK: - Draft Row

/// A single saved draft displayed in the Drafts list.
private struct DraftRow: View {
    let draft: Submission

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(Color.brandOrange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title.isEmpty ? "Untitled \(draft.type.rawValue)" : draft.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(draft.type.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                        title: "It's About Creating",
                        text: "There are no likes or comments here. Art shouldn't be judged by a number; all that matters is your work."
                    )

                    InfoSection(
                        title: "Every Credit Counts",
                        text: "If you're credited on a project, it shows up on your portfolio — no matter how big or small your role was. Every contribution is part of your story."
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
        .presentationDragIndicator(.visible)
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

    @State private var crewInfo: CrewInfo = CrewInfo()
    @State private var castInfo: CastInfo = CastInfo()

    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    @State private var selectedAgeRating: AgeRating = .general
    
    private let allGenres = ["Comedy", "Drama", "Horror", "Adventure", "Fantasy", "Thriller", "Coming-Of-Age", "Sci-Fi", "Documentary", "Mystery"]
    @State private var selectedGenres: Set<String> = []
    
    // Video picker states
    // Note: Film owns its own video/document/thumbnail pickers inside FilmSubmissionView
    @State private var selectedVideoURL: URL?
    @State private var videoThumbnail: UIImage?
    @State private var videoLoadError: Bool = false
    @State private var isUploadingVideo: Bool = false

    // Audio picker states
    // Note: Music owns its own audio picker inside MusicSubmissionView
    @State private var selectedAudioURL: URL?
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
    @State private var reelVideoLoadError: Bool = false
    @State private var isUploadingReelVideo: Bool = false
    @State private var showReelVideoPicker = false
    @State private var showReelDocumentPicker = false
    @State private var showReelThumbnailPicker = false
    
    // Talent Reel-specific states
    @State private var reelType: String = ""
    @State private var reelDescription: String = ""
    
    // Project-specific states
    @State private var shootStartDate: Date = Date()
    @State private var shootEndDate: Date = Date()
    @State private var projectReleaseDate: Date = Date()
    @State private var castNeeded: [String] = []
    @State private var crewNeeded: [String] = []
    @State private var selectedProjectScriptURL: URL?
    @State private var showProjectScriptPicker: Bool = false
    
    // Film-specific states
    @State private var selectedStudio: String = "Independent"
    private let availableStudios = ["Collective", "Incubator", "Beyond Frame Productions", "DKA", "Black Lens", "Independent"]
    
    // Music-specific states
    // Note: Music owns its own album-cover and music-video pickers inside MusicSubmissionView
    @State private var artist: String = ""
    @State private var selectedAlbumCoverData: Data?
    @State private var selectedMusicVideoURL: URL?
    @State private var musicVideoThumbnail: UIImage?
    @State private var selectedMusicGenres: Set<String> = []
    @State private var musicRecordingCredits: [OrderedEntry] = []
    @State private var musicProductionCredits: [OrderedEntry] = []
    @State private var musicSpotifyLink: String = ""
    @State private var musicAppleMusicLink: String = ""
    @State private var musicYouTubeMusicLink: String = ""

    // Draft states
    @State private var showDraftsSheet = false
    @State private var showInfoSheet = false
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
                showInfoSheet: $showInfoSheet
            )
            // Keep this page anchored when a submission sheet's keyboard appears —
            // otherwise the content behind the sheet lifts to avoid the keyboard.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .sheet(item: $selectedContentType, onDismiss: {
                // Clear all inputs when the form is dismissed (e.g. swiped away).
                // Posting and saving a draft persist their data first, so nothing
                // is lost — this just prevents fields from carrying over to the
                // next content type.
                resetForm()
            }) { contentType in
                // Show the form as a bottom sheet
                contentFormSheet(for: contentType)
            }
            .sheet(isPresented: $showDraftsSheet, onDismiss: resumePendingDraftIfNeeded) {
                DraftsView(onResume: { draft in
                    pendingDraftToResume = draft
                })
            }
            .sheet(isPresented: $showInfoSheet) {
                InfoSheetView()
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
        .presentationDragIndicator(.visible)
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
            .navigationTitle(contentType.rawValue)
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
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            selectedProjectImageData = data
                            selectedProjectImageItem = nil
                        }
                    }
                }
            } 
            .photosPicker(isPresented: $showEventImagePicker, selection: $selectedEventImageItem, matching: .images)
            .onChange(of: selectedEventImageItem) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            selectedEventImageData = data
                            selectedEventImageItem = nil
                        }
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
                reelVideoThumbnail = thumbnail
            }
        }
    }
    
    private func generateThumbnail(from url: URL) {
        Task {
            let thumbnail = await VideoThumbnailGenerator.generateThumbnail(from: url, at: 0)
            await MainActor.run {
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
            reelType: $reelType,
            reelDescription: $reelDescription,
            selectedReelVideoURL: $selectedReelVideoURL,
            reelVideoThumbnail: $reelVideoThumbnail,
            reelVideoLoadError: $reelVideoLoadError,
            isUploadingReelVideo: $isUploadingReelVideo,
            showReelVideoPicker: $showReelVideoPicker,
            showReelDocumentPicker: $showReelDocumentPicker,
            showReelThumbnailPicker: $showReelThumbnailPicker,
            uploadPhase: currentUploadPhase,
            onRetryUpload: retryUpload
        )
    }
    
    @ViewBuilder
    private var projectFormContent: some View {
        ProjectSubmissionView(
            title: $title,
            logline: $logline,
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
            selectedAgeRating: $selectedAgeRating,
            castInfo: $castInfo,
            crewInfo: $crewInfo,
            selectedStudio: $selectedStudio,
            selectedVideoURL: $selectedVideoURL,
            videoThumbnail: $videoThumbnail,
            videoLoadError: $videoLoadError,
            isUploadingVideo: $isUploadingVideo,
            onVideoPickerResult: handleVideoPickerResult,
            onGenerateThumbnail: generateThumbnail,
            uploadPhase: currentUploadPhase,
            onRetryUpload: retryUpload
        )
    }
    
    @ViewBuilder
    private var musicFormContent: some View {
        MusicSubmissionView(
            title: $title,
            artist: $artist,
            selectedGenres: $selectedMusicGenres,
            explicitRating: $explicitRating,
            recordingCredits: $musicRecordingCredits,
            productionCredits: $musicProductionCredits,
            spotifyLink: $musicSpotifyLink,
            appleMusicLink: $musicAppleMusicLink,
            youtubeMusicLink: $musicYouTubeMusicLink,
            selectedAudioURL: $selectedAudioURL,
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
        
        if let videoURL = selectedReelVideoURL {
            let fileName = "video_\(submission.id.uuidString).\(videoURL.pathExtension)"
            if let documentsURL = FileManager.default.documentsDirectory {
                let destinationURL = documentsURL.appendingPathComponent(fileName)
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
        submission.shootDates = formatDate(shootStartDate) + " - " + formatDate(shootEndDate)
        submission.expectedReleaseDate = formatDate(projectReleaseDate)
        submission.castNeeded = castNeeded.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        submission.crewNeeded = crewNeeded.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        if let imageData = selectedProjectImageData {
            submission.thumbnailData = imageData
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
        submission.eventStartDate = eventStartDate
        submission.eventEndDate = eventEndDate
        submission.eventLocation = eventLocation
        submission.eventTicketsURL = eventTicketsURL.isEmpty ? nil : eventTicketsURL
        submission.genres = [eventCategory]
        
        if let imageData = selectedEventImageData {
            submission.thumbnailData = imageData
        }
    }
    
    private func configureFilmSubmission(_ submission: inout Submission) {
        submission.logline = logline
        submission.genres = Array(selectedGenres)
        submission.ageRating = selectedAgeRating.rawValue
        submission.studio = selectedStudio
        
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
            if let documentsURL = FileManager.default.documentsDirectory {
                let destinationURL = documentsURL.appendingPathComponent(fileName)
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
    }
    
    private func configureMusicSubmission(_ submission: inout Submission) {
        submission.artist = artist
        submission.genres = Array(selectedMusicGenres)
        submission.explicit = explicitRating
        submission.orderedRecording = musicRecordingCredits
        submission.orderedProduction = musicProductionCredits
        submission.spotifyLink = normalizedLink(musicSpotifyLink)
        submission.appleMusicLink = normalizedLink(musicAppleMusicLink)
        submission.youtubeMusicLink = normalizedLink(musicYouTubeMusicLink)

        if let audioURL = selectedAudioURL {
            let fileName = "audio_\(submission.id.uuidString).\(audioURL.pathExtension)"
            if let documentsURL = FileManager.default.documentsDirectory {
                let destinationURL = documentsURL.appendingPathComponent(fileName)
                do {
                    try? FileManager.default.removeItem(at: destinationURL)
                    try FileManager.default.copyItem(at: audioURL, to: destinationURL)
                    submission.audioFileName = fileName
                } catch {
                    print("Error copying audio: \(error)")
                }
            }
        }

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
        var crewDict: [String: String] = [:]
        var orderedCrew: [OrderedEntry] = []
        
        // (fieldKey, display role, value). `fieldKey` matches CrewInfo.profileIDs keys.
        let crewRoles: [(fieldKey: String, role: String, value: String)] = [
            ("director", "Director", crewInfo.director),
            ("producer", "Producer", crewInfo.producer),
            ("writer", "Writer", crewInfo.writer),
            ("editor", "Editor", crewInfo.editor),
            ("composer", "Composer", crewInfo.composer),
            ("directorOfPhotography", "Director of Photography", crewInfo.directorOfPhotography),
            ("firstAC", "1st Assistant Camera", crewInfo.firstAC),
            ("secondAC", "2nd Assistant Camera", crewInfo.secondAC),
            ("gaffer", "Gaffer", crewInfo.gaffer),
            ("keyGrip", "Key Grip", crewInfo.keyGrip),
            ("grip", "Grip", crewInfo.grip),
            ("bbe", "BBE", crewInfo.bbe),
            ("onSetMixer", "On-Set Mixer", crewInfo.onSetMixer),
            ("soundMixer", "Sound Mixer", crewInfo.soundMixer),
            ("boomOperator", "Boom Operator", crewInfo.boomOperator),
            ("sfxDesigner", "SFX Designer", crewInfo.sfxDesigner),
            ("productionAssistant", "Production Assistant", crewInfo.productionAssistant),
            ("productionDesigner", "Production Designer", crewInfo.productionDesigner),
            ("wardrobe", "Wardrobe", crewInfo.wardrobe),
            ("hairAndMakeup", "Hair and Makeup", crewInfo.hairAndMakeup),
            ("setDresser", "Set Dresser", crewInfo.setDresser),
            ("colorist", "Colorist", crewInfo.colorist),
            ("stuntCoordinator", "Stunt Coordinator", crewInfo.stuntCoordinator)
        ]

        for (fieldKey, role, name) in crewRoles where !name.isEmpty {
            crewDict[role] = name
            orderedCrew.append(OrderedEntry(role: role, name: name, profileID: crewInfo.profileIDs[fieldKey]))
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
        videoLoadError = false
        isUploadingVideo = false
        selectedGenres = []
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

        // Talent Reel fields
        selectedReelVideoURL = nil
        reelVideoThumbnail = nil
        reelVideoLoadError = false
        isUploadingReelVideo = false
        reelType = ""
        reelDescription = ""

        // Project fields
        shootStartDate = Date()
        shootEndDate = Date()
        projectReleaseDate = Date()
        castNeeded = []
        crewNeeded = []
        selectedProjectScriptURL = nil

        // Film fields
        selectedStudio = "Independent"

        // Music fields
        artist = ""
        selectedMusicGenres = []
        musicRecordingCredits = []
        musicProductionCredits = []
        musicSpotifyLink = ""
        musicAppleMusicLink = ""
        musicYouTubeMusicLink = ""
        selectedAlbumCoverData = nil
        selectedMusicVideoURL = nil
        musicVideoThumbnail = nil
    }
    
    // MARK: - Submission Logic
    
    /// Builds a fully-configured `Submission` from the current form state.
    /// Shared by both posting and saving a draft.
    private func buildSubmission() -> Submission? {
        guard let contentType = selectedContentType else { return nil }

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
        selectedContentType = nil
        resetForm()

        // Show a brief "Draft Saved!" confirmation on the Share page.
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
            selectedReelVideoURL = draft.videoURL
            if let data = draft.thumbnailData { reelVideoThumbnail = UIImage(data: data) }
        case .project:
            castNeeded = draft.castNeeded
            crewNeeded = draft.crewNeeded
            selectedProjectImageData = draft.thumbnailData
            selectedProjectScriptURL = draft.scriptURL
            castInfo = makeCastInfo(from: draft.orderedCast)
            crewInfo = makeCrewInfo(from: draft.orderedCrew)
        case .event:
            eventStartDate = draft.eventStartDate ?? Date()
            eventEndDate = draft.eventEndDate ?? Date().addingTimeInterval(3600)
            eventLocation = draft.eventLocation ?? ""
            eventTicketsURL = draft.eventTicketsURL ?? ""
            eventCategory = draft.genres.first ?? ""
            eventHost = draft.eventHost
            selectedEventImageData = draft.thumbnailData
        case .film:
            selectedGenres = Set(draft.genres)
            selectedAgeRating = AgeRating(rawValue: draft.ageRating) ?? .general
            selectedStudio = draft.studio.isEmpty ? "Independent" : draft.studio
            selectedVideoURL = draft.videoURL
            if let data = draft.thumbnailData { videoThumbnail = UIImage(data: data) }
            castInfo = makeCastInfo(from: draft.orderedCast)
            crewInfo = makeCrewInfo(from: draft.orderedCrew)
        case .music:
            artist = draft.artist
            selectedMusicGenres = Set(draft.genres)
            explicitRating = draft.explicit
            musicRecordingCredits = draft.orderedRecording
            musicProductionCredits = draft.orderedProduction
            musicSpotifyLink = draft.spotifyLink
            musicAppleMusicLink = draft.appleMusicLink
            musicYouTubeMusicLink = draft.youtubeMusicLink
            selectedAudioURL = draft.audioURL
            selectedAlbumCoverData = draft.thumbnailData
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

    /// Rebuilds a `CrewInfo` from stored entries by mapping each role back to its field.
    private func makeCrewInfo(from entries: [OrderedEntry]) -> CrewInfo {
        var crew = CrewInfo()
        for entry in entries {
            let fieldKey: String?
            switch entry.role {
            case "Director": crew.director = entry.name; fieldKey = "director"
            case "Producer": crew.producer = entry.name; fieldKey = "producer"
            case "Writer": crew.writer = entry.name; fieldKey = "writer"
            case "Editor": crew.editor = entry.name; fieldKey = "editor"
            case "Composer": crew.composer = entry.name; fieldKey = "composer"
            case "Director of Photography": crew.directorOfPhotography = entry.name; fieldKey = "directorOfPhotography"
            case "1st Assistant Camera": crew.firstAC = entry.name; fieldKey = "firstAC"
            case "2nd Assistant Camera": crew.secondAC = entry.name; fieldKey = "secondAC"
            case "Gaffer": crew.gaffer = entry.name; fieldKey = "gaffer"
            case "Key Grip": crew.keyGrip = entry.name; fieldKey = "keyGrip"
            case "Grip": crew.grip = entry.name; fieldKey = "grip"
            case "BBE": crew.bbe = entry.name; fieldKey = "bbe"
            case "On-Set Mixer": crew.onSetMixer = entry.name; fieldKey = "onSetMixer"
            case "Sound Mixer": crew.soundMixer = entry.name; fieldKey = "soundMixer"
            case "Boom Operator": crew.boomOperator = entry.name; fieldKey = "boomOperator"
            case "SFX Designer": crew.sfxDesigner = entry.name; fieldKey = "sfxDesigner"
            case "Production Assistant": crew.productionAssistant = entry.name; fieldKey = "productionAssistant"
            case "Production Designer": crew.productionDesigner = entry.name; fieldKey = "productionDesigner"
            case "Wardrobe": crew.wardrobe = entry.name; fieldKey = "wardrobe"
            case "Hair and Makeup": crew.hairAndMakeup = entry.name; fieldKey = "hairAndMakeup"
            case "Set Dresser": crew.setDresser = entry.name; fieldKey = "setDresser"
            case "Colorist": crew.colorist = entry.name; fieldKey = "colorist"
            case "Stunt Coordinator": crew.stuntCoordinator = entry.name; fieldKey = "stuntCoordinator"
            default: fieldKey = nil
            }
            if let fieldKey, let pid = entry.profileID {
                crew.profileIDs[fieldKey] = pid
            }
        }
        return crew
    }
}

#Preview("Share") {
    ShareView_3()
}
// MARK: - Helper Views for Video Upload States
// Note: VideoErrorStateView, VideoSuccessStateView, VideoPickerView, 
// DocumentPickerView, and ThumbnailSelectionView are now defined in SharedSubmissionTypes.swift
