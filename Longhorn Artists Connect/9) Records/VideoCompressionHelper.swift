//
//  VideoCompressionHelper.swift
//  Longhorn Artists Connect
//
//  Helper for transcoding oversized videos. Videos within the app's 10 GB
//  upload ceiling are uploaded at original quality (no compression).
//

import AVFoundation
import Foundation

actor VideoCompressionHelper {
    
    /// Threshold above which we transcode. This is NOT a CloudKit limit — CKAsset
    /// supports multi-GB files. It matches the app's 10 GB upload ceiling so that
    /// any video the user is allowed to submit is uploaded at ORIGINAL quality;
    /// videos are effectively never compressed. Compression only remains as a
    /// safety net for pathological files at/above the ceiling.
    static let maxFileSizeMB: Double = 10240  // 10 GB
    static let maxFileSizeBytes: Int64 = Int64(maxFileSizeMB * 1024 * 1024)
    
    /// Compress a video only if it exceeds the upload ceiling (`maxFileSizeMB`)
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
        
        // If under limit, don't re-encode — but still remux to a "fast start" layout
        // (moov atom at the front) so the file streams over HTTP range requests and
        // playback can begin before the whole file downloads.
        if fileSize < maxFileSizeBytes {
            print("✅ Video is under \(Int(maxFileSizeMB))MB limit, no compression needed")
            return await fastStartRemux(inputURL: inputURL, outputURL: outputURL)
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

    /// Remux the video without re-encoding (passthrough), placing the moov atom at the
    /// front so the file is "fast start" — streamable over HTTP range requests without
    /// downloading the whole file first. Quality and codec are preserved. Falls back to a
    /// plain byte copy if a passthrough export can't be created or fails, so uploads never
    /// break.
    ///
    /// Every return value is a file this function has verified exists and is non-empty.
    /// If neither the remux nor the copy produces one (a passthrough export the source's
    /// tracks don't allow, no free disk space for a second full-size copy), it returns
    /// `inputURL` — the caller already confirmed that file is readable, so the upload
    /// proceeds at original quality without the fast-start layout. Returning an output
    /// path that was never written is what produced CloudKit's "may not save a record
    /// with asset … whose fileURL … is inaccessible" failure.
    private static func fastStartRemux(inputURL: URL, outputURL: URL) async -> URL {
        let asset = AVURLAsset(url: inputURL)
        guard let export = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            return plainCopy(inputURL: inputURL, outputURL: outputURL)
        }

        try? FileManager.default.removeItem(at: outputURL)
        export.outputURL = outputURL
        // Match the container to the output extension callers chose (.mp4 today).
        export.outputFileType = outputURL.pathExtension.lowercased() == "mov" ? .mov : .mp4
        export.shouldOptimizeForNetworkUse = true

        print("🎬 Remuxing video for fast-start streaming (no re-encode)…")
        await export.export()

        // A `.completed` status without a readable file on disk shouldn't happen, but the
        // cost of checking is one stat() against the cost of an unexplainable upload failure.
        if export.status == .completed, isReadableNonEmptyFile(at: outputURL) {
            print("✅ Fast-start remux complete")
            return outputURL
        }

        print("⚠️ Fast-start remux failed (\(export.error?.localizedDescription ?? "unknown")); copying original")
        return plainCopy(inputURL: inputURL, outputURL: outputURL)
    }

    /// Plain byte-for-byte copy fallback when remuxing isn't possible. Falls back to the
    /// original file if the copy fails (most often: not enough free space for a second
    /// copy of a large video) so callers always receive a path that exists.
    private static func plainCopy(inputURL: URL, outputURL: URL) -> URL {
        try? FileManager.default.removeItem(at: outputURL)
        do {
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
        } catch {
            print("⚠️ Couldn't stage a copy for upload (\(error.localizedDescription)); uploading the original file")
            return inputURL
        }
        guard isReadableNonEmptyFile(at: outputURL) else {
            print("⚠️ Staged copy is missing or empty; uploading the original file")
            return inputURL
        }
        return outputURL
    }

    /// True when `url` points at a regular file with at least one byte — the minimum for
    /// `CKAsset` to be able to upload it.
    private static func isReadableNonEmptyFile(at url: URL) -> Bool {
        guard let size = try? getFileSize(at: url) else { return false }
        return size > 0
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
