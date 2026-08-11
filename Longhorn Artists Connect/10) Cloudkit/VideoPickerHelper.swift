//
//  VideoPickerHelper.swift
//  Longhorn Artists Connect
//
//  Helper for picking videos from Photos with iCloud support
//

import SwiftUI
import PhotosUI
import Photos
import AVFoundation

/// A helper class to pick videos from the photo library with iCloud download support
struct VideoPickerHelper: UIViewControllerRepresentable {
    let completion: (Result<URL, Error>) -> Void
    @Environment(\.dismiss) private var dismiss
    
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
                completion(.failure(VideoPickerError.cancelled))
                return
            }
            
            // Check if we have an asset identifier (from Photos library)
            if let assetIdentifier = result.assetIdentifier {
                handlePhotosLibraryVideo(assetIdentifier: assetIdentifier)
            } else {
                // Fall back to loading from item provider
                handleItemProviderVideo(result: result)
            }
        }
        
        /// Handle video from Photos library (supports iCloud download)
        private func handlePhotosLibraryVideo(assetIdentifier: String) {
            // Fetch the PHAsset
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
            guard let asset = fetchResult.firstObject else {
                completion(.failure(VideoPickerError.assetNotFound))
                return
            }
            
            // Request video with iCloud download support
            let options = PHVideoRequestOptions()
            
            // 🔑 KEY: Allow downloading from iCloud!
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            
            // Progress handler (optional - for showing progress to user)
            options.progressHandler = { progress, error, stop, info in
                DispatchQueue.main.async {
                    print("⬇️ Downloading video from iCloud: \(Int(progress * 100))%")
                }
                
                if let error = error {
                    print("❌ iCloud download error: \(error.localizedDescription)")
                }
            }
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, audioMix, info in
                guard let self = self else { return }
                
                // Check for errors
                if let error = info?[PHImageErrorKey] as? Error {
                    DispatchQueue.main.async {
                        self.completion(.failure(error))
                    }
                    return
                }
                
                guard let urlAsset = avAsset as? AVURLAsset else {
                    DispatchQueue.main.async {
                        self.completion(.failure(VideoPickerError.invalidAsset))
                    }
                    return
                }
                
                // Copy video to app's temp directory
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
                
                do {
                    // Remove any existing file
                    try? FileManager.default.removeItem(at: tempURL)
                    
                    // Copy the video
                    try FileManager.default.copyItem(at: urlAsset.url, to: tempURL)
                    
                    // Check file size
                    let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                    if let fileSize = attributes[.size] as? Int64 {
                        let fileSizeMB = Double(fileSize) / 1024.0 / 1024.0
                        print("📹 Video file size: \(String(format: "%.2f", fileSizeMB)) MB")
                        
                        // Warn if too large
                        if fileSizeMB > 250 {
                            print("⚠️ Warning: Video exceeds CloudKit 250MB limit")
                            DispatchQueue.main.async {
                                self.completion(.failure(VideoPickerError.fileTooLarge(sizeMB: fileSizeMB)))
                            }
                            return
                        }
                    }
                    
                    DispatchQueue.main.async {
                        print("✅ Video ready: \(tempURL.lastPathComponent)")
                        self.completion(.success(tempURL))
                    }
                } catch {
                    print("❌ Failed to copy video: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.completion(.failure(error))
                    }
                }
            }
        }
        
        /// Fallback: Handle video from item provider (for non-Photos sources)
        private func handleItemProviderVideo(result: PHPickerResult) {
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.completion(.failure(error))
                    }
                    return
                }
                
                guard let url = url else {
                    DispatchQueue.main.async {
                        self.completion(.failure(VideoPickerError.urlNotFound))
                    }
                    return
                }
                
                // Copy to temp directory
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
                
                do {
                    try? FileManager.default.removeItem(at: tempURL)
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    
                    DispatchQueue.main.async {
                        self.completion(.success(tempURL))
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.completion(.failure(error))
                    }
                }
            }
        }
    }
}

// MARK: - Error Types

enum VideoPickerError: LocalizedError {
    case cancelled
    case assetNotFound
    case invalidAsset
    case urlNotFound
    case fileTooLarge(sizeMB: Double)
    
    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Video selection cancelled"
        case .assetNotFound:
            return "Could not find the selected video"
        case .invalidAsset:
            return "The selected file is not a valid video"
        case .urlNotFound:
            return "Could not access the video file"
        case .fileTooLarge(let sizeMB):
            return "Video file is too large (\(String(format: "%.0f", sizeMB))MB). Maximum is 250MB."
        }
    }
}

// MARK: - Usage Example in SwiftUI

struct VideoPickerExample: View {
    @State private var selectedVideoURL: URL?
    @State private var showingPicker = false
    @State private var isLoadingVideo = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Button("Select Video") {
                showingPicker = true
            }
            
            if isLoadingVideo {
                ProgressView("Loading video...")
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            
            if let url = selectedVideoURL {
                Text("Video ready: \(url.lastPathComponent)")
                    .foregroundColor(.green)
                
                Button("Upload to CloudKit") {
                    uploadVideo(url)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .sheet(isPresented: $showingPicker) {
            VideoPickerHelper { result in
                isLoadingVideo = false
                
                switch result {
                case .success(let url):
                    selectedVideoURL = url
                    errorMessage = nil
                    print("✅ Video selected: \(url)")
                    
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    print("❌ Video selection failed: \(error.localizedDescription)")
                }
            }
        }
        .onChange(of: showingPicker) { newValue in
            if newValue {
                isLoadingVideo = true
                errorMessage = nil
            }
        }
    }
    
    func uploadVideo(_ url: URL) {
        Task {
            do {
                // Create your Film/Music/Reel object
                var film = Film(id: UUID(), title: "My Film", details: "Description")
                
                // Set the video URL
                // The video is already in temp directory, so you can reference it
                film.videoFileName = url.lastPathComponent
                
                // Save to CloudKit
                try await CloudKitManager.shared.saveFilm(film)
                
                print("✅ Film uploaded successfully!")
            } catch {
                print("❌ Upload failed: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Add to Info.plist

/*
 Add this to your Info.plist:
 
 <key>NSPhotoLibraryUsageDescription</key>
 <string>We need access to your photo library to select videos for upload</string>
 */
