//
//  VideoCompressionHelper.swift
//  Longhorn Artists Connect
//
//  Helper for compressing videos to meet CloudKit 250MB limit
//

import AVFoundation
import Foundation

actor VideoCompressionHelper {
    
    /// Upper bound for uploads. This is NOT a CloudKit limit — CKAsset supports
    /// multi-GB files — it's the ceiling above which we transcode to keep uploads
    /// and downloads reasonable. Files under this are uploaded at original quality.
    static let maxFileSizeMB: Double = 2048  // 2 GB
    static let maxFileSizeBytes: Int64 = Int64(maxFileSizeMB * 1024 * 1024)
    
    /// Compress a video if it exceeds CloudKit's 250MB limit
    /// - Parameters:
    ///   - inputURL: The original video URL
    ///   - outputURL: Where to save the compressed video
    ///   - progressHandler: Optional callback for progress updates (0.0 to 1.0)
    /// - Returns: The URL of the compressed video (same as outputURL)
    /// - Throws: Error if compression fails
    static func compressVideoIfNeeded(
        inputURL: URL,
        outputURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> URL {
        
        // Check if compression is needed
        let fileSize = try getFileSize(at: inputURL)
        let fileSizeMB = Double(fileSize) / 1024.0 / 1024.0
        
        print("📹 Original video size: \(String(format: "%.2f", fileSizeMB)) MB")
        
        // If under limit, just copy the file
        if fileSize < maxFileSizeBytes {
            print("✅ Video is under \(Int(maxFileSizeMB))MB limit, no compression needed")
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
            return outputURL
        }

        print("🔄 Video exceeds \(Int(maxFileSizeMB))MB, compressing...")
        
        // Compress the video
        return try await compressVideo(
            inputURL: inputURL,
            outputURL: outputURL,
            progressHandler: progressHandler
        )
    }
    
    /// Get file size in bytes
    private static func getFileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    /// Compress video using AVAssetExportSession
    private static func compressVideo(
        inputURL: URL,
        outputURL: URL,
        progressHandler: ((Double) -> Void)?
    ) async throws -> URL {
        
        let asset = AVURLAsset(url: inputURL)
        
        // Use medium quality preset for good balance of size/quality
        // Other options: AVAssetExportPresetLowQuality, AVAssetExportPresetHighestQuality
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetMediumQuality
        ) else {
            throw CompressionError.exportSessionCreationFailed
        }
        
        // Clean up any existing output file
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4  // Use MP4 for better compression
        exportSession.shouldOptimizeForNetworkUse = true  // Optimize for streaming
        
        // Start export
        print("🎬 Starting video compression...")
        
        // Monitor progress
        let progressTask = Task {
            while !Task.isCancelled {
                let progress = exportSession.progress
                await MainActor.run {
                    progressHandler?(Double(progress))
                }
                print("📊 Compression progress: \(Int(progress * 100))%")
                try? await Task.sleep(nanoseconds: 500_000_000) // Check every 0.5 seconds
            }
        }
        
        // Perform export
        await exportSession.export()
        progressTask.cancel()
        
        // Check result
        switch exportSession.status {
        case .completed:
            let compressedSize = try getFileSize(at: outputURL)
            let compressedSizeMB = Double(compressedSize) / 1024.0 / 1024.0
            
            print("✅ Compression complete!")
            print("   Original: \(String(format: "%.2f", Double(try getFileSize(at: inputURL)) / 1024.0 / 1024.0)) MB")
            print("   Compressed: \(String(format: "%.2f", compressedSizeMB)) MB")
            print("   Reduction: \(String(format: "%.1f", (1.0 - Double(compressedSize) / Double(try getFileSize(at: inputURL))) * 100))%")
            
            // Check if still too large
            if compressedSize > maxFileSizeBytes {
                print("⚠️ Warning: Compressed video still exceeds 250MB")
                print("⚠️ Consider using AVAssetExportPresetLowQuality for more compression")
                
                // Try again with low quality if still too big
                print("🔄 Retrying with low quality preset...")
                return try await compressVideoWithLowQuality(
                    inputURL: inputURL,
                    outputURL: outputURL,
                    progressHandler: progressHandler
                )
            }
            
            return outputURL
            
        case .failed:
            let error = exportSession.error ?? CompressionError.exportFailed
            print("❌ Compression failed: \(error.localizedDescription)")
            throw error
            
        case .cancelled:
            throw CompressionError.exportCancelled
            
        default:
            throw CompressionError.unknownError
        }
    }
    
    /// Fallback compression with low quality for very large files
    private static func compressVideoWithLowQuality(
        inputURL: URL,
        outputURL: URL,
        progressHandler: ((Double) -> Void)?
    ) async throws -> URL {
        
        let asset = AVURLAsset(url: inputURL)
        
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetLowQuality  // More aggressive compression
        ) else {
            throw CompressionError.exportSessionCreationFailed
        }
        
        // Clean up any existing output file
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        print("🎬 Starting low-quality compression...")
        
        // Monitor progress
        let progressTask = Task {
            while !Task.isCancelled {
                let progress = exportSession.progress
                await MainActor.run {
                    progressHandler?(Double(progress))
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        
        await exportSession.export()
        progressTask.cancel()
        
        switch exportSession.status {
        case .completed:
            let compressedSize = try getFileSize(at: outputURL)
            let compressedSizeMB = Double(compressedSize) / 1024.0 / 1024.0
            
            print("✅ Low-quality compression complete: \(String(format: "%.2f", compressedSizeMB)) MB")
            
            // If STILL too large, we have to give up
            if compressedSize > maxFileSizeBytes {
                throw CompressionError.fileTooLargeEvenAfterCompression(sizeMB: compressedSizeMB)
            }
            
            return outputURL
            
        case .failed:
            throw exportSession.error ?? CompressionError.exportFailed
            
        case .cancelled:
            throw CompressionError.exportCancelled
            
        default:
            throw CompressionError.unknownError
        }
    }
}

// MARK: - Compression Errors

enum CompressionError: LocalizedError {
    case exportSessionCreationFailed
    case exportFailed
    case exportCancelled
    case unknownError
    case fileTooLargeEvenAfterCompression(sizeMB: Double)
    
    var errorDescription: String? {
        switch self {
        case .exportSessionCreationFailed:
            return "Failed to create video export session"
        case .exportFailed:
            return "Video compression failed"
        case .exportCancelled:
            return "Video compression was cancelled"
        case .unknownError:
            return "An unknown error occurred during compression"
        case .fileTooLargeEvenAfterCompression(let sizeMB):
            return "Video is too large (\(String(format: "%.0f", sizeMB))MB) even after maximum compression. Please use a shorter video or lower resolution source."
        }
    }
}
