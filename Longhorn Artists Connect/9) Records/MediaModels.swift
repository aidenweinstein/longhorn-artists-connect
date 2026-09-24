//
//  MediaModels.swift
//  Longhorn Artists Connect
//
//  Separate models for each media type (Film, Music, Reel, Project, Event)
//

import Foundation
import CloudKit
import CoreLocation  // For CLGeocoder and CLLocation
import AVFoundation  // For reading a video's duration
import UIKit         // For downscaling thumbnails before upload

/// Writes a downscaled JPEG copy of an image file to a temp URL for upload, capping the
/// longest edge at `maxDimension` px. Uploaded images are downloaded by every viewer, so
/// shrinking them here cuts both upload and (repeated) download bandwidth dramatically
/// with no visible quality loss at the sizes these images are actually displayed. Returns
/// the original URL unchanged if the image can't be decoded or re-encoded.
func downscaledImageForUpload(at sourceURL: URL, maxDimension: CGFloat, quality: CGFloat = 0.7, tempName: String) -> URL {
    guard let image = UIImage(contentsOfFile: sourceURL.path) else { return sourceURL }

    let longestEdge = max(image.size.width, image.size.height)
    let ratio = longestEdge > maxDimension ? maxDimension / longestEdge : 1
    let targetSize = CGSize(width: (image.size.width * ratio).rounded(),
                            height: (image.size.height * ratio).rounded())

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1  // targetSize is already in pixels; don't multiply by screen scale
    let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: targetSize))
    }

    guard let data = resized.jpegData(compressionQuality: quality) else { return sourceURL }
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(tempName)
    do {
        try? FileManager.default.removeItem(at: tempURL)
        try data.write(to: tempURL)
        return tempURL
    } catch {
        return sourceURL
    }
}

// MARK: - Asset Upload Guard

/// A file a record's `CKAsset` needs isn't on disk any more.
///
/// `CKAsset` accepts any URL and only discovers the file is gone when the save runs, and
/// what it reports then is a dump of the whole `CKDModifyRecordsOperation` ending in
/// "whose fileURL … is inaccessible" — which the upload banner shows verbatim. Checking
/// before the save lets the banner say which piece of media went missing and what to do.
nonisolated enum MediaUploadError: LocalizedError {
    case missingAssetFile(field: String, fileName: String)

    var errorDescription: String? {
        switch self {
        case .missingAssetFile(let field, _):
            return "This post's \(Self.describe(field)) is no longer on this device, so it can't be uploaded. Re-select it from the post's Edit screen, then post again."
        }
    }

    /// Plain-English name for a CloudKit asset field, for the message above.
    private static func describe(_ field: String) -> String {
        switch field {
        case "filmVideo", "reelVideo", "designVideo": return "video"
        case "filmTrailer":                         return "trailer"
        case "musicAudio":                          return "audio track"
        case "musicVideo":                          return "music video"
        case "filmThumbnail", "reelThumbnail",
             "photographyThumbnail", "designThumbnail": return "cover image"
        case "musicCover":                          return "cover art"
        case "filmBTS":                             return "behind-the-scenes photo"
        case "filmStills":                          return "still"
        case "photographyImages":                   return "photo"
        case "designImages":                        return "image"
        default:                                    return "media file"
        }
    }
}

/// Builds the `CKAsset` for `field`, confirming first that the file is actually readable
/// and non-empty. Throws `MediaUploadError.missingAssetFile` when it isn't, rather than
/// handing CloudKit a path it can't open.
func uploadAsset(at url: URL, field: String) throws -> CKAsset {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    guard let size = attributes?[.size] as? Int64, size > 0 else {
        print("❌ \(field): upload file missing or empty at \(url.path)")
        throw MediaUploadError.missingAssetFile(field: field, fileName: url.lastPathComponent)
    }
    return CKAsset(fileURL: url)
}

/// Reads the credited person's profile ID at `index` from a parallel, index-aligned
/// IDs array stored alongside the "role: name" credit strings. Empty means "no ID".
func creditProfileID(from ids: [String]?, at index: Int) -> String? {
    guard let ids, index < ids.count else { return nil }
    let value = ids[index]
    return value.isEmpty ? nil : value
}

// MARK: - Protocol for Common Fields

/// Protocol that all media types conform to
protocol MediaItem: Identifiable, Codable, Equatable {
    var id: UUID { get }
    var title: String { get set }
    var details: String { get set }
    var isApproved: Bool { get set }
    var submittedBy: String { get set }
    var createdDate: Date { get set }
    var lastEditedDate: Date? { get set }
    var thumbnailFileName: String? { get set }  // ✅ Changed from thumbnailData to thumbnailFileName
    var thumbnailURL: URL? { get }  // ✅ Added computed property requirement
    var mediaType: MediaType { get }
    
    // CloudKit conversion
    func toCloudKitRecord(userRecordID: CKRecord.ID?) async throws -> CKRecord
    static func fromCloudKitRecord(_ record: CKRecord) -> Self?
}

// MARK: - Film Model

struct Film: MediaItem {
    let id: UUID
    var title: String
    var details: String
    var isApproved: Bool = false
    var submittedBy: String = ""
    var createdDate: Date = Date()
    var lastEditedDate: Date?
    var thumbnailFileName: String?  // ✅ Changed from thumbnailData to thumbnailFileName
    
    var mediaType: MediaType { .film }
    
    // Computed property to get thumbnail URL from file system
    var thumbnailURL: URL? {
        guard let fileName = thumbnailFileName else { return nil }
        guard let documentsDir = FileManager.default.documentsDirectory else { return nil }
        let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
        let url = thumbnailsDir.appendingPathComponent(fileName)
        guard FileManager.default.fileExistsAndIsAccessible(at: url) else {
            return nil
        }
        return url
    }
    
    // Film-specific fields
    var logline: String = ""
    var ageRating: String = ""
    var genres: [String] = []
    var explicit: Bool = false
    /// When true the film is "festival-bound": kept private (hidden from the public feed,
    /// shown only on a credited person's profile or when sent directly).
    var festivalBound: Bool = false
    
    // Cast & Crew
    var orderedCast: [OrderedEntry] = []
    var orderedCrew: [OrderedEntry] = []
    
    // Studio
    var studio: String = ""
    
    // Media files
    var videoFileName: String?

    /// Video length in seconds. Synced so the duration badge shows on every device.
    var videoDuration: Double?

    // Film extras — a separate trailer video plus any number of BTS photos / stills.
    // Stored as deterministic file names (resolved via `mediaFileURL`), like `videoFileName`.
    var trailerFileName: String?
    var btsImageFileNames: [String] = []
    var stillImageFileNames: [String] = []

    // Computed property to get video URL
    var videoURL: URL? {
        guard let videoFileName = videoFileName else { return nil }
        return FileManager.default.mediaFileURL(named: videoFileName)
    }

    /// Local URL of the trailer video, if on disk.
    var trailerURL: URL? {
        guard let trailerFileName else { return nil }
        return FileManager.default.mediaFileURL(named: trailerFileName)
    }

    /// Local URLs of the BTS photos / stills currently on disk (missing files skipped).
    var btsImageURLs: [URL] {
        btsImageFileNames.compactMap { FileManager.default.mediaFileURL(named: $0) }
    }
    var stillImageURLs: [URL] {
        stillImageFileNames.compactMap { FileManager.default.mediaFileURL(named: $0) }
    }

    // MARK: - CloudKit Conversion

    func toCloudKitRecord(userRecordID: CKRecord.ID?) async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: "FilmSubmission", recordID: recordID)
        
        // Basic fields - using schema field names
        record["filmTitle"] = title as CKRecordValue
        record["filmDescription"] = details as CKRecordValue
        record["isApproved"] = (isApproved ? 1 : 0) as CKRecordValue
        record["submittedBy"] = submittedBy as CKRecordValue
        record["createdDate"] = createdDate as CKRecordValue
        
        if let lastEditedDate = lastEditedDate {
            record["lastEditedDate"] = lastEditedDate as CKRecordValue
        }
        
        if let userID = userRecordID?.recordName {
            record["userID"] = userID as CKRecordValue
        }
        
        // Film-specific fields - using schema field names
        record["filmLogline"] = logline as CKRecordValue
        record["filmAgeRating"] = ageRating as CKRecordValue
        record["filmStudio"] = studio as CKRecordValue
        record["filmExplicit"] = (explicit ? 1 : 0) as CKRecordValue
        record["filmFestivalBound"] = (festivalBound ? 1 : 0) as CKRecordValue
        
        // Always write, even when empty, so an edit that clears a field overwrites the
        // server value. The save uses a blind `.allKeys` policy (no fetch-merge), which
        // only overwrites keys present on the record — so omitting a key leaves the old
        // server value in place. Writing empty arrays keeps edits fully in sync.
        record["filmGenres"] = genres as CKRecordValue

        // Cast & Crew as arrays (not JSON) - schema uses filmCast and filmCrew.
        // Profile IDs are stored in a parallel, index-aligned array so the visible
        // "role: name" strings stay clean for older app versions.
        record["filmCast"] = orderedCast.map { "\($0.role): \($0.name)" } as CKRecordValue
        record["filmCastIDs"] = orderedCast.map { $0.profileID ?? "" } as CKRecordValue
        record["filmCrew"] = orderedCrew.map { "\($0.role): \($0.name)" } as CKRecordValue
        record["filmCrewIDs"] = orderedCrew.map { $0.profileID ?? "" } as CKRecordValue
        
        // Video asset - using schema field name
        if let videoURL = videoURL {
            // Persist the video's length (from the original, pre-compression file)
            // so the duration badge shows on devices that haven't downloaded the
            // video. Prefer an already-known value; otherwise read it now.
            var durationSeconds = videoDuration
            if durationSeconds == nil,
               let loaded = try? await AVURLAsset(url: videoURL).load(.duration) {
                durationSeconds = loaded.seconds
            }
            if let durationSeconds, durationSeconds.isFinite, durationSeconds > 0 {
                record["filmVideoDuration"] = durationSeconds as CKRecordValue
            }

            do {
                let tempVideoURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(id.uuidString)
                    .appendingPathExtension("mp4")  // Use .mp4 for compressed output

                // Compress video if needed (automatically handles size check)
                let finalVideoURL = try await VideoCompressionHelper.compressVideoIfNeeded(
                    inputURL: videoURL,
                    outputURL: tempVideoURL
                ) { progress in
                    print("📊 Film compression progress: \(Int(progress * 100))%")
                }

                let videoAsset = try uploadAsset(at: finalVideoURL, field: "filmVideo")
                record["filmVideo"] = videoAsset
                print("✅ Film video asset prepared for upload")
            } catch {
                print("❌ Failed to prepare film video asset: \(error.localizedDescription)")
                throw error
            }
        }
        
        // Thumbnail - using schema field name (downscaled before upload)
        if let thumbnailURL = thumbnailURL {
            let uploadURL = downscaledImageForUpload(
                at: thumbnailURL, maxDimension: 1000, tempName: id.uuidString + "_thumb.jpg"
            )
            record["filmThumbnail"] = try uploadAsset(at: uploadURL, field: "filmThumbnail")
        }

        // Trailer video — a second, compressed video asset alongside the feature film.
        if let trailerURL = trailerURL {
            do {
                let tempTrailerURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(id.uuidString + "_trailer")
                    .appendingPathExtension("mp4")
                let finalTrailerURL = try await VideoCompressionHelper.compressVideoIfNeeded(
                    inputURL: trailerURL,
                    outputURL: tempTrailerURL
                ) { progress in
                    print("📊 Film trailer compression progress: \(Int(progress * 100))%")
                }
                record["filmTrailer"] = try uploadAsset(at: finalTrailerURL, field: "filmTrailer")
            } catch {
                print("❌ Failed to prepare film trailer asset: \(error.localizedDescription)")
                throw error
            }
        }

        // BTS photos & stills — CloudKit Asset List fields (each image downscaled before
        // upload). Assets live outside the record, so arrays of any length are safe.
        let btsAssets = try btsImageURLs.enumerated().map { index, url in
            try uploadAsset(at: downscaledImageForUpload(
                at: url, maxDimension: 2000, tempName: "\(id.uuidString)_bts_\(index).jpg"
            ), field: "filmBTS")
        }
        if !btsAssets.isEmpty { record["filmBTS"] = btsAssets as CKRecordValue }

        let stillAssets = try stillImageURLs.enumerated().map { index, url in
            try uploadAsset(at: downscaledImageForUpload(
                at: url, maxDimension: 2000, tempName: "\(id.uuidString)_still_\(index).jpg"
            ), field: "filmStills")
        }
        if !stillAssets.isEmpty { record["filmStills"] = stillAssets as CKRecordValue }

        return record
    }
    
    static func fromCloudKitRecord(_ record: CKRecord) -> Film? {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        
        // Using schema field names
        let title = record.getString("filmTitle") ?? "Untitled"
        let details = record.getString("filmDescription") ?? ""
        
        var film = Film(id: id, title: title, details: details)
        
        film.isApproved = (record.getInt("isApproved") ?? 0) == 1
        film.submittedBy = record.getString("submittedBy") ?? "Anonymous"
        film.createdDate = record.getDate("createdDate") ?? Date()
        film.lastEditedDate = record.getDate("lastEditedDate")
        
        // Film-specific fields - using schema field names
        film.logline = record.getString("filmLogline") ?? ""
        film.ageRating = record.getString("filmAgeRating") ?? ""
        film.explicit = (record.getInt("filmExplicit") ?? 0) == 1
        film.festivalBound = (record.getInt("filmFestivalBound") ?? 0) == 1
        film.studio = record.getString("filmStudio") ?? ""
        
        // Genres - using schema field name
        if let genresArray = record["filmGenres"] as? [String] {
            film.genres = genresArray
        }
        
        // Cast & Crew - parse from string arrays
        if let castArray = record["filmCast"] as? [String] {
            let ids = record["filmCastIDs"] as? [String]
            film.orderedCast = castArray.enumerated().compactMap { index, entry in
                let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return OrderedEntry(role: parts[0].trimmingCharacters(in: .whitespaces),
                                   name: parts[1].trimmingCharacters(in: .whitespaces),
                                   profileID: creditProfileID(from: ids, at: index))
            }
        }

        if let crewArray = record["filmCrew"] as? [String] {
            let ids = record["filmCrewIDs"] as? [String]
            film.orderedCrew = crewArray.enumerated().compactMap { index, entry in
                let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return OrderedEntry(role: parts[0].trimmingCharacters(in: .whitespaces),
                                   name: parts[1].trimmingCharacters(in: .whitespaces),
                                   profileID: creditProfileID(from: ids, at: index))
            }
        }
        
        film.videoDuration = record.getDouble("filmVideoDuration")

        // Download video (or reuse an already-downloaded copy if this fetch didn't
        // include the asset — see `persistCloudKitAsset`).
        film.videoFileName = FileManager.default.persistCloudKitAsset(
            record.getAsset("filmVideo"),
            fileName: "\(id.uuidString)_video.mov",
            baseDirectory: FileManager.default.mediaCacheDirectory
        )

        // Download thumbnail into the thumbnails directory (with the same reuse fallback).
        film.thumbnailFileName = FileManager.default.persistCloudKitAsset(
            record.getAsset("filmThumbnail"),
            fileName: "\(id.uuidString)_thumb.jpg",
            subdirectory: "thumbnails"
        )

        // Film extras. The feed omits these heavy keys (see FeedKeys), so they're only
        // populated when the full record is fetched (e.g. `downloadFilmExtras`). Reuse an
        // already-downloaded copy if the asset is absent from this fetch.
        film.trailerFileName = FileManager.default.persistCloudKitAsset(
            record.getAsset("filmTrailer"),
            fileName: "\(id.uuidString)_trailer.mov",
            baseDirectory: FileManager.default.mediaCacheDirectory
        )
        if let btsAssets = record["filmBTS"] as? [CKAsset] {
            film.btsImageFileNames = btsAssets.enumerated().compactMap { index, asset in
                FileManager.default.persistCloudKitAsset(
                    asset, fileName: "\(id.uuidString)_bts_\(index).jpg",
                    baseDirectory: FileManager.default.mediaCacheDirectory
                )
            }
        }
        if let stillAssets = record["filmStills"] as? [CKAsset] {
            film.stillImageFileNames = stillAssets.enumerated().compactMap { index, asset in
                FileManager.default.persistCloudKitAsset(
                    asset, fileName: "\(id.uuidString)_still_\(index).jpg",
                    baseDirectory: FileManager.default.mediaCacheDirectory
                )
            }
        }

        return film
    }
}

// MARK: - Music Model

struct Music: MediaItem {
    let id: UUID
    var title: String
    var details: String
    var isApproved: Bool = false
    var submittedBy: String = ""
    var createdDate: Date = Date()
    var lastEditedDate: Date?
    var thumbnailFileName: String?  // ✅ Changed from thumbnailData to thumbnailFileName
    
    var mediaType: MediaType { .music }
    
    // Computed property to get thumbnail URL from file system
    var thumbnailURL: URL? {
        guard let fileName = thumbnailFileName else { return nil }
        guard let documentsDir = FileManager.default.documentsDirectory else { return nil }
        let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
        let url = thumbnailsDir.appendingPathComponent(fileName)
        guard FileManager.default.fileExistsAndIsAccessible(at: url) else {
            return nil
        }
        return url
    }
    
    // Music-specific fields
    var artist: String = ""
    /// What kind of release this is — "Song", "EP", "Album" or "Performance".
    /// Empty on records created before the category picker existed.
    var category: String = ""
    var genres: [String] = []
    var explicit: Bool = false
    
    // Credits
    var orderedRecording: [OrderedEntry] = [] // Musicians, vocalists, etc.
    var orderedProduction: [OrderedEntry] = [] // Producers, engineers, mixers, etc.
    
    // Streaming links
    var spotifyLink: String = ""
    var appleMusicLink: String = ""
    var amazonMusicLink: String = ""
    var youtubeMusicLink: String = ""
    var soundcloudLink: String = ""

    // Song lyrics, shown at the bottom of the music card below the streaming links.
    var lyrics: String = ""

    // Media files
    var audioFileName: String?
    /// EP/Album posts: the additional audio tracks beyond `audioFileName` (track 1), in
    /// running order. Empty for singles and performances.
    var trackFileNames: [String] = []
    var videoFileName: String?  // For music video

    /// Audio track length in seconds, captured at upload and synced via CloudKit so the
    /// duration badge can show on every device — even ones that haven't downloaded the
    /// audio file yet. Nil for older records.
    var audioDuration: Double?

    // Computed property to get audio URL
    var audioURL: URL? {
        guard let audioFileName = audioFileName else { return nil }
        return FileManager.default.mediaFileURL(named: audioFileName)
    }

    /// The additional EP/Album tracks that are actually present on disk, in order.
    var trackURLs: [URL] {
        trackFileNames.compactMap { FileManager.default.mediaFileURL(named: $0) }
    }

    // Computed property to get video URL
    var videoURL: URL? {
        guard let videoFileName = videoFileName else { return nil }
        return FileManager.default.mediaFileURL(named: videoFileName)
    }
    
    // MARK: - CloudKit Conversion
    
    func toCloudKitRecord(userRecordID: CKRecord.ID?) async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: "MusicSubmission", recordID: recordID)
        
        // Basic fields - using schema field names
        record["musicTitle"] = title as CKRecordValue
        record["musicDescription"] = details as CKRecordValue
        record["isApproved"] = (isApproved ? 1 : 0) as CKRecordValue
        record["submittedBy"] = submittedBy as CKRecordValue
        record["createdDate"] = createdDate as CKRecordValue
        
        if let lastEditedDate = lastEditedDate {
            record["lastEditedDate"] = lastEditedDate as CKRecordValue
        }
        
        if let userID = userRecordID?.recordName {
            record["userID"] = userID as CKRecordValue
        }
        
        // Music-specific fields - using schema field names
        record["musicArtist"] = artist as CKRecordValue
        // `musicCategory` does not exist in the deployed MusicSubmission schema in
        // either environment, and one unknown field fails the whole atomic save — the
        // same gap that sank photography credits and the event lineup fields. Writing
        // it only when set means a category-less track saves first try instead of
        // leaning on the drop-and-retry rescue in `CloudKitManager.save`.
        //
        // Trade-off: clearing the category on an edit no longer overwrites the server
        // value (an omitted key keeps its stale value under `.allKeys`). That's moot
        // while the field doesn't exist server-side; once it's added in CloudKit
        // Dashboard and deployed, switch this back to the always-written form.
        if !category.isEmpty {
            record["musicCategory"] = category as CKRecordValue
        }
        record["musicExplicit"] = (explicit ? 1 : 0) as CKRecordValue
        
        // Always write every editable field, even when empty, so an edit that clears a
        // value overwrites the server. The blind `.allKeys` save only overwrites keys
        // present on the record, so a conditionally-omitted key would keep its stale
        // server value.
        record["musicGenres"] = genres as CKRecordValue

        // Streaming links - using schema field names
        record["musicSpotifyLink"] = spotifyLink as CKRecordValue
        record["musicAppleMusicLink"] = appleMusicLink as CKRecordValue
        // Note: schema doesn't have Amazon or YouTube Music, using custom fields
        record["amazonMusicLink"] = amazonMusicLink as CKRecordValue
        record["youtubeMusicLink"] = youtubeMusicLink as CKRecordValue
        record["soundcloudLink"] = soundcloudLink as CKRecordValue
        record["lyrics"] = lyrics as CKRecordValue

        // Credits as arrays - using schema field names (profile IDs in parallel arrays)
        record["musicRecording"] = orderedRecording.map { "\($0.role): \($0.name)" } as CKRecordValue
        record["musicRecordingIDs"] = orderedRecording.map { $0.profileID ?? "" } as CKRecordValue
        record["musicProduction"] = orderedProduction.map { "\($0.role): \($0.name)" } as CKRecordValue
        record["musicProductionIDs"] = orderedProduction.map { $0.profileID ?? "" } as CKRecordValue
        
        // Audio asset - using schema field name
        if let audioURL = audioURL {
            let tempAudioURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(id.uuidString)
                .appendingPathExtension("m4a")
            
            try? FileManager.default.removeItem(at: tempAudioURL)
            try FileManager.default.copyItem(at: audioURL, to: tempAudioURL)

            let audioAsset = try uploadAsset(at: tempAudioURL, field: "musicAudio")
            record["musicAudio"] = audioAsset
            // Record the real container extension so other devices can save the
            // downloaded track with a name AVPlayer can decode (it keys off the
            // extension). Without this a downloaded mp3 saved as .m4a won't play.
            let ext = audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension
            record["musicAudioExt"] = ext as CKRecordValue

            // Persist the track length so the duration badge shows on devices that
            // haven't downloaded the audio. Prefer an already-known value; otherwise
            // read it from the file now.
            var durationSeconds = audioDuration
            if durationSeconds == nil,
               let loaded = try? await AVURLAsset(url: audioURL).load(.duration) {
                durationSeconds = loaded.seconds
            }
            if let durationSeconds, durationSeconds.isFinite, durationSeconds > 0 {
                record["musicAudioDuration"] = durationSeconds as CKRecordValue
            }
        }

        // Additional EP/Album tracks, as a parallel asset list + extension list.
        //
        // Written only when the post actually has extra tracks, for the same reason as
        // `musicCategory` above: `musicTracks` / `musicTrackExts` don't exist in the
        // deployed MusicSubmission schema yet, and one unknown field fails the whole
        // atomic save. Singles and performances are therefore unaffected. Once the
        // fields are added in CloudKit Dashboard and deployed, this can be written
        // unconditionally so clearing a tracklist on an edit overwrites the server.
        let extraTrackURLs = trackURLs
        if !extraTrackURLs.isEmpty {
            var assets: [CKAsset] = []
            var exts: [String] = []
            for (index, trackURL) in extraTrackURLs.enumerated() {
                let ext = trackURL.pathExtension.isEmpty ? "m4a" : trackURL.pathExtension
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(id.uuidString)_track\(index + 1)")
                    .appendingPathExtension(ext)
                try? FileManager.default.removeItem(at: tempURL)
                try FileManager.default.copyItem(at: trackURL, to: tempURL)
                assets.append(try uploadAsset(at: tempURL, field: "musicTracks"))
                exts.append(ext)
            }
            record["musicTracks"] = assets as CKRecordValue
            record["musicTrackExts"] = exts as CKRecordValue
        }


        // Video asset (music video) - using custom field name
        if let videoURL = videoURL {
            do {
                let tempVideoURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(id.uuidString)
                    .appendingPathExtension("mp4")  // Use .mp4 for compressed output
                
                // Compress video if needed
                let finalVideoURL = try await VideoCompressionHelper.compressVideoIfNeeded(
                    inputURL: videoURL,
                    outputURL: tempVideoURL
                ) { progress in
                    print("📊 Music video compression progress: \(Int(progress * 100))%")
                }
                
                let videoAsset = try uploadAsset(at: finalVideoURL, field: "musicVideo")
                record["musicVideo"] = videoAsset
                print("✅ Music video asset prepared for upload")
            } catch {
                print("❌ Failed to prepare music video: \(error.localizedDescription)")
                throw error
            }
        }
        
        // Thumbnail (cover art) - using schema field name (downscaled before upload)
        if let thumbnailURL = thumbnailURL {
            let uploadURL = downscaledImageForUpload(
                at: thumbnailURL, maxDimension: 1000, tempName: id.uuidString + "_cover.jpg"
            )
            record["musicCover"] = try uploadAsset(at: uploadURL, field: "musicCover")
        }
        
        return record
    }
    
    static func fromCloudKitRecord(_ record: CKRecord) -> Music? {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        
        // Using schema field names
        let title = record.getString("musicTitle") ?? "Untitled"
        let details = record.getString("musicDescription") ?? ""
        
        var music = Music(id: id, title: title, details: details)
        
        music.isApproved = (record.getInt("isApproved") ?? 0) == 1
        music.submittedBy = record.getString("submittedBy") ?? "Anonymous"
        music.createdDate = record.getDate("createdDate") ?? Date()
        music.lastEditedDate = record.getDate("lastEditedDate")
        
        // Music-specific fields - using schema field names
        music.artist = record.getString("musicArtist") ?? ""
        music.explicit = (record.getInt("musicExplicit") ?? 0) == 1
        
        // Genres - using schema field name
        if let genresArray = record["musicGenres"] as? [String] {
            music.genres = genresArray
        }
        
        // Streaming links - using schema field names
        music.spotifyLink = record.getString("musicSpotifyLink") ?? ""
        music.appleMusicLink = record.getString("musicAppleMusicLink") ?? ""
        music.amazonMusicLink = record.getString("amazonMusicLink") ?? ""
        music.youtubeMusicLink = record.getString("youtubeMusicLink") ?? ""
        music.soundcloudLink = record.getString("soundcloudLink") ?? ""
        music.lyrics = record.getString("lyrics") ?? ""
        music.category = record.getString("musicCategory") ?? ""

        music.audioDuration = record.getDouble("musicAudioDuration")

        // Credits - parse from string arrays (profile IDs from parallel arrays)
        if let recordingArray = record["musicRecording"] as? [String] {
            let ids = record["musicRecordingIDs"] as? [String]
            music.orderedRecording = recordingArray.enumerated().compactMap { index, entry in
                let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return OrderedEntry(role: parts[0].trimmingCharacters(in: .whitespaces),
                                   name: parts[1].trimmingCharacters(in: .whitespaces),
                                   profileID: creditProfileID(from: ids, at: index))
            }
        }

        if let productionArray = record["musicProduction"] as? [String] {
            let ids = record["musicProductionIDs"] as? [String]
            music.orderedProduction = productionArray.enumerated().compactMap { index, entry in
                let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return OrderedEntry(role: parts[0].trimmingCharacters(in: .whitespaces),
                                   name: parts[1].trimmingCharacters(in: .whitespaces),
                                   profileID: creditProfileID(from: ids, at: index))
            }
        }
        
        // Download audio / music video / cover art, each reusing an already-downloaded
        // copy if this fetch didn't include the asset (see `persistCloudKitAsset`).
        music.audioFileName = FileManager.default.persistAudioAsset(
            record.getAsset("musicAudio"),
            submissionID: id.uuidString,
            preferredExtension: record.getString("musicAudioExt")
        )

        // Additional EP/Album tracks. Absent on singles, on performances, and on every
        // record saved before the `musicTracks` field existed — all of which read back
        // as an empty tracklist.
        if let trackAssets = record["musicTracks"] as? [CKAsset] {
            let exts = record["musicTrackExts"] as? [String] ?? []
            music.trackFileNames = trackAssets.enumerated().compactMap { index, asset in
                let ext = index < exts.count && !exts[index].isEmpty ? exts[index] : "m4a"
                return FileManager.default.persistCloudKitAsset(
                    asset,
                    fileName: "\(id.uuidString)_track\(index + 1).\(ext)",
                    baseDirectory: FileManager.default.mediaCacheDirectory
                )
            }
        }

        music.videoFileName = FileManager.default.persistCloudKitAsset(
            record.getAsset("musicVideo"),
            fileName: "\(id.uuidString)_video.mov",
            baseDirectory: FileManager.default.mediaCacheDirectory
        )

        music.thumbnailFileName = FileManager.default.persistCloudKitAsset(
            record.getAsset("musicCover"),
            fileName: "\(id.uuidString)_cover.jpg",
            subdirectory: "thumbnails"
        )

        return music
    }
}

// MARK: - Reel Model

struct Reel: MediaItem {
    let id: UUID
    var title: String
    var details: String
    var isApproved: Bool = false
    var submittedBy: String = ""
    var createdDate: Date = Date()
    var lastEditedDate: Date?
    var thumbnailFileName: String?  // ✅ Changed from thumbnailData to thumbnailFileName
    
    var mediaType: MediaType { .reel }
    
    // Computed property to get thumbnail URL from file system
    var thumbnailURL: URL? {
        guard let fileName = thumbnailFileName else { return nil }
        guard let documentsDir = FileManager.default.documentsDirectory else { return nil }
        let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
        let url = thumbnailsDir.appendingPathComponent(fileName)
        guard FileManager.default.fileExistsAndIsAccessible(at: url) else {
            return nil
        }
        return url
    }
    
    // Reel-specific fields
    var reelType: String = "" // e.g., "Acting", "Directing", "Editing"
    var reelDescription: String = ""

    /// UUID strings of other posts referenced as "Featured Work" on this reel.
    var featuredWorkIDs: [String] = []
    /// Hand-typed "Featured Work" entries (project + director) that aren't posts on the
    /// app. Each element is a JSON-encoded `ManualFeaturedWork`.
    var featuredWorkManual: [String] = []

    /// The reel's headline artist/creator, shown under the title (mirrors music's Artist).
    var artist: String = ""

    // Crew credits
    var orderedCrew: [OrderedEntry] = []

    // Media files
    var videoFileName: String?
    /// The reel video's length in seconds, persisted so the duration badge shows on the
    /// feed even on devices that haven't downloaded the video (mirrors film/music).
    var videoDuration: Double?

    var videoURL: URL? {
        guard let videoFileName = videoFileName else { return nil }
        return FileManager.default.mediaFileURL(named: videoFileName)
    }

    // MARK: - CloudKit Conversion

    func toCloudKitRecord(userRecordID: CKRecord.ID?) async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: "ReelSubmission", recordID: recordID)
        
        // Using schema field names
        record["reelTitle"] = title as CKRecordValue
        record["reelDescription"] = details as CKRecordValue
        record["isApproved"] = (isApproved ? 1 : 0) as CKRecordValue
        record["submittedBy"] = submittedBy as CKRecordValue
        record["createdDate"] = createdDate as CKRecordValue
        
        if let lastEditedDate = lastEditedDate {
            record["lastEditedDate"] = lastEditedDate as CKRecordValue
        }
        
        if let userID = userRecordID?.recordName {
            record["userID"] = userID as CKRecordValue
        }
        
        // Reel-specific fields - using schema field names
        record["reelType"] = reelType as CKRecordValue
        record["reelDescription"] = reelDescription as CKRecordValue
        
        // Crew as array, with profile IDs in a parallel array. Always written (even
        // empty) so clearing the crew during an edit overwrites the server — the blind
        // `.allKeys` save leaves omitted keys at their stale server value.
        record["orderedCrew"] = orderedCrew.map { "\($0.role): \($0.name)" } as CKRecordValue
        record["orderedCrewIDs"] = orderedCrew.map { $0.profileID ?? "" } as CKRecordValue

        // Featured Work post IDs. Always written (even empty) so removing the last one
        // during an edit overwrites the server — the blind `.allKeys` save leaves omitted
        // keys at their stale value.
        record["featuredWork"] = featuredWorkIDs as CKRecordValue
        // Hand-typed Featured Work entries (JSON strings). Always written for the same
        // overwrite-on-edit reason.
        record["featuredWorkManual"] = featuredWorkManual as CKRecordValue

        record["reelArtist"] = artist as CKRecordValue

        // Video asset - using schema field name
        if let videoURL = videoURL {
            // Persist the video's length (from the original, pre-compression file) so the
            // duration badge shows on devices that haven't downloaded the video. Prefer an
            // already-known value; otherwise read it now.
            var durationSeconds = videoDuration
            if durationSeconds == nil,
               let loaded = try? await AVURLAsset(url: videoURL).load(.duration) {
                durationSeconds = loaded.seconds
            }
            if let durationSeconds, durationSeconds.isFinite, durationSeconds > 0 {
                record["reelVideoDuration"] = durationSeconds as CKRecordValue
            }

            do {
                let tempVideoURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(id.uuidString)
                    .appendingPathExtension("mp4")  // Use .mp4 for compressed output

                // Compress video if needed
                let finalVideoURL = try await VideoCompressionHelper.compressVideoIfNeeded(
                    inputURL: videoURL,
                    outputURL: tempVideoURL
                ) { progress in
                    print("📊 Reel compression progress: \(Int(progress * 100))%")
                }

                let videoAsset = try uploadAsset(at: finalVideoURL, field: "reelVideo")
                record["reelVideo"] = videoAsset
                print("✅ Reel video asset prepared for upload")
            } catch {
                print("❌ Failed to prepare reel video: \(error.localizedDescription)")
                throw error
            }
        }
        
        // Thumbnail - downscaled before upload
        if let thumbnailURL = thumbnailURL {
            let uploadURL = downscaledImageForUpload(
                at: thumbnailURL, maxDimension: 1000, tempName: id.uuidString + "_thumb.jpg"
            )
            record["reelThumbnail"] = try uploadAsset(at: uploadURL, field: "reelThumbnail")
        }
        
        return record
    }
    
    static func fromCloudKitRecord(_ record: CKRecord) -> Reel? {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        
        // Using schema field names
        let title = record.getString("reelTitle") ?? "Untitled"
        let details = record.getString("reelDescription") ?? ""
        
        var reel = Reel(id: id, title: title, details: details)
        
        reel.isApproved = (record.getInt("isApproved") ?? 0) == 1
        reel.submittedBy = record.getString("submittedBy") ?? "Anonymous"
        reel.createdDate = record.getDate("createdDate") ?? Date()
        reel.lastEditedDate = record.getDate("lastEditedDate")
        
        reel.reelType = record.getString("reelType") ?? ""
        reel.reelDescription = record.getString("reelDescription") ?? ""
        reel.featuredWorkIDs = record["featuredWork"] as? [String] ?? []
        reel.featuredWorkManual = record["featuredWorkManual"] as? [String] ?? []
        reel.artist = record.getString("reelArtist") ?? ""
        reel.videoDuration = record.getDouble("reelVideoDuration")

        // Parse crew from string array (profile IDs from parallel array)
        if let crewArray = record["orderedCrew"] as? [String] {
            let ids = record["orderedCrewIDs"] as? [String]
            reel.orderedCrew = crewArray.enumerated().compactMap { index, entry in
                let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return OrderedEntry(role: parts[0].trimmingCharacters(in: .whitespaces),
                                   name: parts[1].trimmingCharacters(in: .whitespaces),
                                   profileID: creditProfileID(from: ids, at: index))
            }
        }
        
        // Download video and thumbnail, each reusing an already-downloaded copy if this
        // fetch didn't include the asset (see `persistCloudKitAsset`).
        reel.videoFileName = FileManager.default.persistCloudKitAsset(
            record.getAsset("reelVideo"),
            fileName: "\(id.uuidString)_video.mov",
            baseDirectory: FileManager.default.mediaCacheDirectory
        )

        reel.thumbnailFileName = FileManager.default.persistCloudKitAsset(
            record.getAsset("reelThumbnail"),
            fileName: "\(id.uuidString)_thumb.jpg",
            subdirectory: "thumbnails"
        )

        return reel
    }
}

// MARK: - Photography Model

struct Photography: MediaItem {
    let id: UUID
    var title: String
    var details: String
    var isApproved: Bool = false
    var submittedBy: String = ""
    var createdDate: Date = Date()
    var lastEditedDate: Date?
    var thumbnailFileName: String?

    var mediaType: MediaType { .photography }

    // Computed property to get thumbnail URL from file system
    var thumbnailURL: URL? {
        guard let fileName = thumbnailFileName else { return nil }
        guard let documentsDir = FileManager.default.documentsDirectory else { return nil }
        let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
        let url = thumbnailsDir.appendingPathComponent(fileName)
        guard FileManager.default.fileExistsAndIsAccessible(at: url) else {
            return nil
        }
        return url
    }

    // Photography-specific fields
    /// The photographer, shown under the title (mirrors music's Artist).
    var artist: String = ""
    /// Year the photos were taken/released (4-digit string, empty if unset).
    var releaseYear: String = ""
    /// The gallery of photos. The first image doubles as the thumbnail.
    var photoImageFileNames: [String] = []

    /// The gear used for the shoot (camera, lens, lighting, etc.). Blank when unset.
    var equipment: EquipmentInfo = EquipmentInfo()

    /// People credited on the shoot (models, stylists, assistants, etc.), each a
    /// role + name (with an optional linked profile). Empty when none were added.
    var orderedCrew: [OrderedEntry] = []

    /// Local URLs of the gallery images currently on disk (missing files skipped).
    var photoImageURLs: [URL] {
        photoImageFileNames.compactMap { FileManager.default.mediaFileURL(named: $0) }
    }

    // MARK: - CloudKit Conversion

    func toCloudKitRecord(userRecordID: CKRecord.ID?) async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: "PhotographySubmission", recordID: recordID)

        record["photographyTitle"] = title as CKRecordValue
        record["photographyDescription"] = details as CKRecordValue
        record["isApproved"] = (isApproved ? 1 : 0) as CKRecordValue
        record["submittedBy"] = submittedBy as CKRecordValue
        record["createdDate"] = createdDate as CKRecordValue

        if let lastEditedDate = lastEditedDate {
            record["lastEditedDate"] = lastEditedDate as CKRecordValue
        }

        if let userID = userRecordID?.recordName {
            record["userID"] = userID as CKRecordValue
        }

        record["photographyArtist"] = artist as CKRecordValue
        record["photographyReleaseYear"] = releaseYear as CKRecordValue

        // Equipment (JSON blob; omitted when nothing was entered)
        let equipmentJSON = equipment.jsonString
        if !equipmentJSON.isEmpty {
            record["photographyEquipment"] = equipmentJSON as CKRecordValue
        }

        // Credits — stored as parallel "role: name" and profile-ID string arrays,
        // matching how reels persist their crew.
        //
        // Written ONLY when there are credits. Writing an empty list still names the
        // field on the record, and `orderedCrew`/`orderedCrewIDs` are not part of the
        // PhotographySubmission schema in the production environment (an empty list
        // has no inferable element type, so Development never auto-created them to be
        // deployed). Production rejects the whole save with an unknown-field error, so
        // every photography post silently failed to upload: it stayed in
        // `pendingUploadIDs`, flashed in the feed at launch before that set loaded, and
        // was then reaped by `reconcileMissingLocalSubmission` as "absent from CloudKit".
        if !orderedCrew.isEmpty {
            record["orderedCrew"] = orderedCrew.map { "\($0.role): \($0.name)" } as CKRecordValue
            record["orderedCrewIDs"] = orderedCrew.map { $0.profileID ?? "" } as CKRecordValue
        }

        // Gallery images — a CloudKit Asset List field (each image downscaled before
        // upload). Assets live outside the record, so arrays of any length are safe.
        let assets = try photoImageURLs.enumerated().map { index, url in
            try uploadAsset(at: downscaledImageForUpload(
                at: url, maxDimension: 2000, tempName: "\(id.uuidString)_photo_\(index).jpg"
            ), field: "photographyImages")
        }
        if !assets.isEmpty { record["photographyImages"] = assets as CKRecordValue }

        // Thumbnail (first image, downscaled smaller).
        if let thumbnailURL = thumbnailURL {
            let uploadURL = downscaledImageForUpload(
                at: thumbnailURL, maxDimension: 1000, tempName: id.uuidString + "_thumb.jpg"
            )
            record["photographyThumbnail"] = try uploadAsset(at: uploadURL, field: "photographyThumbnail")
        }

        return record
    }

    static func fromCloudKitRecord(_ record: CKRecord) -> Photography? {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }

        let title = record.getString("photographyTitle") ?? "Untitled"
        let details = record.getString("photographyDescription") ?? ""

        var photo = Photography(id: id, title: title, details: details)

        photo.isApproved = (record.getInt("isApproved") ?? 0) == 1
        photo.submittedBy = record.getString("submittedBy") ?? "Anonymous"
        photo.createdDate = record.getDate("createdDate") ?? Date()
        photo.lastEditedDate = record.getDate("lastEditedDate")
        photo.artist = record.getString("photographyArtist") ?? ""
        photo.releaseYear = record.getString("photographyReleaseYear") ?? ""
        if let equipmentJSON = record.getString("photographyEquipment") {
            photo.equipment = EquipmentInfo(jsonString: equipmentJSON)
        }

        // Parse credits from the parallel "role: name" / profile-ID string arrays.
        if let crewArray = record["orderedCrew"] as? [String] {
            let ids = record["orderedCrewIDs"] as? [String]
            photo.orderedCrew = crewArray.enumerated().compactMap { index, entry in
                let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return OrderedEntry(role: parts[0].trimmingCharacters(in: .whitespaces),
                                    name: parts[1].trimmingCharacters(in: .whitespaces),
                                    profileID: creditProfileID(from: ids, at: index))
            }
        }

        // Download gallery images, each reusing an already-downloaded copy if this fetch
        // didn't include the asset (see `persistCloudKitAsset`).
        if let assets = record["photographyImages"] as? [CKAsset] {
            photo.photoImageFileNames = assets.enumerated().compactMap { index, asset in
                FileManager.default.persistCloudKitAsset(
                    asset, fileName: "\(id.uuidString)_photo_\(index).jpg",
                    baseDirectory: FileManager.default.mediaCacheDirectory
                )
            }
        } else {
            // The asset LIST itself is missing from this fetch (a partial failure, or a
            // query that didn't request it), which is different from "this post has no
            // photos". Blanking the gallery here is what made a photography post lose its
            // images on a refresh, so instead reuse whatever was already downloaded —
            // the same fallback `persistCloudKitAsset` gives every other asset. File
            // names are deterministic, so walking the indices recovers the full gallery.
            var cached: [String] = []
            var index = 0
            while let fileName = FileManager.default.persistCloudKitAsset(
                nil, fileName: "\(id.uuidString)_photo_\(index).jpg",
                baseDirectory: FileManager.default.mediaCacheDirectory
            ) {
                cached.append(fileName)
                index += 1
            }
            photo.photoImageFileNames = cached
        }

        photo.thumbnailFileName = FileManager.default.persistCloudKitAsset(
            record.getAsset("photographyThumbnail"),
            fileName: "\(id.uuidString)_thumb.jpg",
            subdirectory: "thumbnails"
        )

        return photo
    }
}

// MARK: - Design Model

/// A design post: artwork or a design piece (graphic, magazine, drawing, painting, or
/// modeling) shown as a gallery of images and/or a single video, with a description,
/// release year and credits.
struct Design: MediaItem {
    let id: UUID
    var title: String
    var details: String
    var isApproved: Bool = false
    var submittedBy: String = ""
    var createdDate: Date = Date()
    var lastEditedDate: Date?
    var thumbnailFileName: String?

    var mediaType: MediaType { .design }

    // Computed property to get thumbnail URL from file system
    var thumbnailURL: URL? {
        guard let fileName = thumbnailFileName else { return nil }
        guard let documentsDir = FileManager.default.documentsDirectory else { return nil }
        let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
        let url = thumbnailsDir.appendingPathComponent(fileName)
        guard FileManager.default.fileExistsAndIsAccessible(at: url) else {
            return nil
        }
        return url
    }

    // Design-specific fields
    /// Which kind of design this is — one of `DesignCategory`. Empty when unset.
    var category: String = ""
    /// Year the piece was made/released (4-digit string, empty if unset).
    var releaseYear: String = ""
    /// The uploaded images. The first doubles as the thumbnail.
    var imageFileNames: [String] = []
    /// An optional single video, for motion/3D work.
    var videoFileName: String?

    /// Video length in seconds, captured at upload and synced so other devices know the
    /// post HAS a video without the (heavy) asset riding along with the feed fetch.
    /// Nil / zero means "no video".
    var videoDuration: Double?

    /// People credited on the piece, each a role + name (with an optional linked
    /// profile). Empty when none were added.
    var orderedCrew: [OrderedEntry] = []

    /// Local URLs of the images currently on disk (missing files skipped).
    var imageURLs: [URL] {
        imageFileNames.compactMap { FileManager.default.mediaFileURL(named: $0) }
    }

    /// Local URL of the video, if one is on disk.
    var videoURL: URL? {
        guard let videoFileName else { return nil }
        return FileManager.default.mediaFileURL(named: videoFileName)
    }

    // MARK: - CloudKit Conversion

    func toCloudKitRecord(userRecordID: CKRecord.ID?) async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: "DesignSubmission", recordID: recordID)

        record["designTitle"] = title as CKRecordValue
        record["designDescription"] = details as CKRecordValue
        record["isApproved"] = (isApproved ? 1 : 0) as CKRecordValue
        record["submittedBy"] = submittedBy as CKRecordValue
        record["createdDate"] = createdDate as CKRecordValue

        if let lastEditedDate = lastEditedDate {
            record["lastEditedDate"] = lastEditedDate as CKRecordValue
        }

        if let userID = userRecordID?.recordName {
            record["userID"] = userID as CKRecordValue
        }

        record["designCategory"] = category as CKRecordValue
        record["designReleaseYear"] = releaseYear as CKRecordValue

        // Credits — parallel "role: name" and profile-ID string arrays, like photography.
        //
        // Written ONLY when there are credits: an empty string list has no inferable
        // element type, so Development never auto-creates the field to be deployed, and
        // Production then rejects the whole atomic save as an unknown field. That gap is
        // what silently sank every photography post (see `Photography.toCloudKitRecord`).
        if !orderedCrew.isEmpty {
            record["orderedCrew"] = orderedCrew.map { "\($0.role): \($0.name)" } as CKRecordValue
            record["orderedCrewIDs"] = orderedCrew.map { $0.profileID ?? "" } as CKRecordValue
        }

        // Images — a CloudKit Asset List field (each downscaled before upload). Assets
        // live outside the record, so arrays of any length are safe.
        let assets = try imageURLs.enumerated().map { index, url in
            try uploadAsset(at: downscaledImageForUpload(
                at: url, maxDimension: 2000, tempName: "\(id.uuidString)_design_\(index).jpg"
            ), field: "designImages")
        }
        if !assets.isEmpty { record["designImages"] = assets as CKRecordValue }

        // Video (compressed first, like the film/reel videos).
        if let videoURL = videoURL {
            // Persist the length so other devices know this post has a video — the
            // asset itself is too heavy to ride along with the feed fetch.
            var durationSeconds = videoDuration
            if durationSeconds == nil,
               let loaded = try? await AVURLAsset(url: videoURL).load(.duration) {
                durationSeconds = loaded.seconds
            }
            if let durationSeconds, durationSeconds.isFinite, durationSeconds > 0 {
                record["designVideoDuration"] = durationSeconds as CKRecordValue
            }

            do {
                let tempVideoURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(id.uuidString)
                    .appendingPathExtension("mp4")
                let finalVideoURL = try await VideoCompressionHelper.compressVideoIfNeeded(
                    inputURL: videoURL,
                    outputURL: tempVideoURL
                ) { progress in
                    print("📊 Design video compression progress: \(Int(progress * 100))%")
                }
                record["designVideo"] = try uploadAsset(at: finalVideoURL, field: "designVideo")
            } catch {
                print("❌ Failed to prepare design video asset: \(error.localizedDescription)")
                throw error
            }
        }

        // Thumbnail (first image, downscaled smaller).
        if let thumbnailURL = thumbnailURL {
            let uploadURL = downscaledImageForUpload(
                at: thumbnailURL, maxDimension: 1000, tempName: id.uuidString + "_thumb.jpg"
            )
            record["designThumbnail"] = try uploadAsset(at: uploadURL, field: "designThumbnail")
        }

        return record
    }

    static func fromCloudKitRecord(_ record: CKRecord) -> Design? {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }

        let title = record.getString("designTitle") ?? "Untitled"
        let details = record.getString("designDescription") ?? ""

        var design = Design(id: id, title: title, details: details)

        design.isApproved = (record.getInt("isApproved") ?? 0) == 1
        design.submittedBy = record.getString("submittedBy") ?? "Anonymous"
        design.createdDate = record.getDate("createdDate") ?? Date()
        design.lastEditedDate = record.getDate("lastEditedDate")
        design.category = record.getString("designCategory") ?? ""
        design.releaseYear = record.getString("designReleaseYear") ?? ""
        design.videoDuration = record.getDouble("designVideoDuration")

        // Parse credits from the parallel "role: name" / profile-ID string arrays.
        if let crewArray = record["orderedCrew"] as? [String] {
            let ids = record["orderedCrewIDs"] as? [String]
            design.orderedCrew = crewArray.enumerated().compactMap { index, entry in
                let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return OrderedEntry(role: parts[0].trimmingCharacters(in: .whitespaces),
                                    name: parts[1].trimmingCharacters(in: .whitespaces),
                                    profileID: creditProfileID(from: ids, at: index))
            }
        }

        // Download the images, each reusing an already-downloaded copy if this fetch
        // didn't include the asset (see `persistCloudKitAsset`).
        if let assets = record["designImages"] as? [CKAsset] {
            design.imageFileNames = assets.enumerated().compactMap { index, asset in
                FileManager.default.persistCloudKitAsset(
                    asset, fileName: "\(id.uuidString)_design_\(index).jpg",
                    baseDirectory: FileManager.default.mediaCacheDirectory
                )
            }
        } else {
            // The asset LIST itself is missing from this fetch (a partial failure, or a
            // query that didn't request it), which is different from "this post has no
            // images". Blanking the gallery here is what made photography posts lose
            // their images on a refresh, so instead recover whatever was already
            // downloaded — the file names are deterministic, so walking the indices
            // rebuilds the full set.
            var cached: [String] = []
            var index = 0
            while let fileName = FileManager.default.persistCloudKitAsset(
                nil, fileName: "\(id.uuidString)_design_\(index).jpg",
                baseDirectory: FileManager.default.mediaCacheDirectory
            ) {
                cached.append(fileName)
                index += 1
            }
            design.imageFileNames = cached
        }

        design.videoFileName = FileManager.default.persistCloudKitAsset(
            record.getAsset("designVideo"),
            fileName: "\(id.uuidString)_video.mov",
            baseDirectory: FileManager.default.mediaCacheDirectory
        )

        design.thumbnailFileName = FileManager.default.persistCloudKitAsset(
            record.getAsset("designThumbnail"),
            fileName: "\(id.uuidString)_thumb.jpg",
            subdirectory: "thumbnails"
        )

        return design
    }
}

// MARK: - Project Model

struct Project: MediaItem {
    let id: UUID
    var title: String
    var details: String
    var isApproved: Bool = false
    var submittedBy: String = ""
    var createdDate: Date = Date()
    var lastEditedDate: Date?
    var thumbnailFileName: String?  // ✅ Changed from thumbnailData to thumbnailFileName
    
    var mediaType: MediaType { .project }
    
    // Computed property to get thumbnail URL from file system
    var thumbnailURL: URL? {
        guard let fileName = thumbnailFileName else { return nil }
        guard let documentsDir = FileManager.default.documentsDirectory else { return nil }
        let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
        let url = thumbnailsDir.appendingPathComponent(fileName)
        guard FileManager.default.fileExistsAndIsAccessible(at: url) else {
            return nil
        }
        return url
    }
    
    // Project-specific fields
    var shootDates: String = ""
    var expectedReleaseDate: String = ""
    var genres: [String] = []
    
    // Needed positions
    var castNeeded: [String] = []
    var crewNeeded: [String] = []
    
    // Assembled team members
    var castAssembled: [OrderedEntry] = []
    var crewAssembled: [OrderedEntry] = []

    /// The slideshow images shown in place of the poster on the detail view, in order.
    /// The poster stays the feed thumbnail and is shown last, after these.
    var slideImageFileNames: [String] = []

    /// Local URLs of the slideshow images currently on disk (missing files skipped).
    var slideImageURLs: [URL] {
        slideImageFileNames.compactMap { FileManager.default.mediaFileURL(named: $0) }
    }

    // MARK: - CloudKit Conversion
    
    func toCloudKitRecord(userRecordID: CKRecord.ID?) async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: "ProjectSubmission", recordID: recordID)
        
        // Using schema field names
        record["projectTitle"] = title as CKRecordValue
        record["projectDescription"] = details as CKRecordValue
        record["isApproved"] = (isApproved ? 1 : 0) as CKRecordValue
        record["submittedBy"] = submittedBy as CKRecordValue
        record["createdDate"] = createdDate as CKRecordValue
        
        if let lastEditedDate = lastEditedDate {
            record["lastEditedDate"] = lastEditedDate as CKRecordValue
        }
        
        if let userID = userRecordID?.recordName {
            record["userID"] = userID as CKRecordValue
        }
        
        // Project-specific fields - using schema field names
        // CloudKit schema expects TIMESTAMP for projectShootStart, but we store it as String
        // We need to convert the string to a Date
        
        if !shootDates.isEmpty {
            // Try to parse the shootDates string as a date
            // Expected formats from ProjectDate.dateString: "Mar 15, 2025" or "March 15, 2025"
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")  // Consistent parsing
            
            // Try short month format first: "Mar 15, 2025"
            dateFormatter.dateFormat = "MMM d, yyyy"
            if let date = dateFormatter.date(from: shootDates) {
                record["projectShootStart"] = date as CKRecordValue
                print("✅ Converted shoot date '\(shootDates)' to timestamp")
            } else {
                // Try full month format: "March 15, 2025"
                dateFormatter.dateFormat = "MMMM d, yyyy"
                if let date = dateFormatter.date(from: shootDates) {
                    record["projectShootStart"] = date as CKRecordValue
                    print("✅ Converted shoot date '\(shootDates)' to timestamp")
                } else {
                    // Try numeric format: "03/15/2025"
                    dateFormatter.dateFormat = "MM/dd/yyyy"
                    if let date = dateFormatter.date(from: shootDates) {
                        record["projectShootStart"] = date as CKRecordValue
                        print("✅ Converted shoot date '\(shootDates)' to timestamp")
                    } else {
                        print("⚠️ Could not parse shoot date '\(shootDates)' - skipping field")
                    }
                }
            }
        }
        
        // Same for expectedReleaseDate
        // Expected formats from ProjectReleaseDate.dateString: "Mar 2025" or "Mar 15, 2025"
        if !expectedReleaseDate.isEmpty {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            
            // Try short month with day: "Mar 15, 2025"
            dateFormatter.dateFormat = "MMM d, yyyy"
            if let date = dateFormatter.date(from: expectedReleaseDate) {
                record["projectExpectedReleaseDate"] = date as CKRecordValue  // Changed to projectExpectedReleaseDate
                print("✅ Converted release date '\(expectedReleaseDate)' to timestamp")
            } else {
                // Try full month with day: "March 15, 2025"
                dateFormatter.dateFormat = "MMMM d, yyyy"
                if let date = dateFormatter.date(from: expectedReleaseDate) {
                    record["projectExpectedReleaseDate"] = date as CKRecordValue  // Changed to projectExpectedReleaseDate
                    print("✅ Converted release date '\(expectedReleaseDate)' to timestamp")
                } else {
                    // Try short month only: "Mar 2025"
                    dateFormatter.dateFormat = "MMM yyyy"
                    if let date = dateFormatter.date(from: expectedReleaseDate) {
                        record["projectExpectedReleaseDate"] = date as CKRecordValue  // Changed to projectExpectedReleaseDate
                        print("✅ Converted release date '\(expectedReleaseDate)' to timestamp")
                    } else {
                        // Try full month only: "March 2025"
                        dateFormatter.dateFormat = "MMMM yyyy"
                        if let date = dateFormatter.date(from: expectedReleaseDate) {
                            record["projectExpectedReleaseDate"] = date as CKRecordValue  // Changed to projectExpectedReleaseDate
                            print("✅ Converted release date '\(expectedReleaseDate)' to timestamp")
                        } else {
                            print("⚠️ Could not parse release date '\(expectedReleaseDate)' - skipping field")
                        }
                    }
                }
            }
        }
        
        // Also store the raw date strings verbatim. The TIMESTAMP fields above only
        // survive dates that match the fixed formats — a range ("Mar 15 – 20, 2025")
        // or a loose value ("Summer 2025") fails to parse and would otherwise be lost
        // on the next sync. These text fields are the source of truth for display and
        // round-trip losslessly regardless of format.
        // Always write the raw text (even empty) so an edit that clears a date
        // overwrites the server. The blind `.allKeys` save only overwrites keys present
        // on the record, so an omitted key would keep its stale server value.
        record["projectShootDatesText"] = shootDates as CKRecordValue
        record["projectReleaseDateText"] = expectedReleaseDate as CKRecordValue

        // Roles-needed arrays — always written (empty overwrites the server).
        record["projectCastNeeded"] = castNeeded as CKRecordValue
        record["projectCrewNeeded"] = crewNeeded as CKRecordValue

        // Assembled cast & crew (profile IDs in parallel arrays) — always written.
        record["projectCastAssembled"] = castAssembled.map { "\($0.role): \($0.name)" } as CKRecordValue
        record["projectCastAssembledIDs"] = castAssembled.map { $0.profileID ?? "" } as CKRecordValue
        record["projectCrewAssembled"] = crewAssembled.map { "\($0.role): \($0.name)" } as CKRecordValue
        record["projectCrewAssembledIDs"] = crewAssembled.map { $0.profileID ?? "" } as CKRecordValue
        // Genres — always written (empty overwrites the server on edit).
        record["projectGenres"] = genres as CKRecordValue
        
        // Slideshow images — a CloudKit Asset List field (each image downscaled before
        // upload). Assets live outside the record, so arrays of any length are safe.
        //
        // Written ONLY when the project has slides: an empty list still names the field
        // on the record, and an unknown field fails the whole atomic save (the same trap
        // PhotographySubmission's `orderedCrew` hit). A poster-only project therefore
        // never mentions `projectSlides` and uploads fine even where the field hasn't
        // been added to the schema yet.
        let slideAssets = try slideImageURLs.enumerated().map { index, url in
            try uploadAsset(at: downscaledImageForUpload(
                at: url, maxDimension: 2000, tempName: "\(id.uuidString)_slide_\(index).jpg"
            ), field: "projectSlides")
        }
        if !slideAssets.isEmpty { record["projectSlides"] = slideAssets as CKRecordValue }

        // Thumbnail - using schema field name
        if let thumbnailURL = thumbnailURL,
           let thumbnailData = try? Data(contentsOf: thumbnailURL) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(id.uuidString + "_poster_orig.jpg")
            try thumbnailData.write(to: tempURL)
            let uploadURL = downscaledImageForUpload(
                at: tempURL, maxDimension: 1600, tempName: id.uuidString + "_poster.jpg"
            )
            record["projectPoster"] = CKAsset(fileURL: uploadURL)
        }
        
        return record
    }
    
    static func fromCloudKitRecord(_ record: CKRecord) -> Project? {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        
        // Using schema field names
        let title = record.getString("projectTitle") ?? "Untitled"
        let details = record.getString("projectDescription") ?? ""
        
        var project = Self(id: id, title: title, details: details)
        
        project.isApproved = (record.getInt("isApproved") ?? 0) == 1
        project.submittedBy = record.getString("submittedBy") ?? "Anonymous"
        project.createdDate = record.getDate("createdDate") ?? Date()
        project.lastEditedDate = record.getDate("lastEditedDate")
        
        // Project-specific fields - using schema field names
        // Prefer the verbatim text field (lossless for any format). Fall back to the
        // legacy TIMESTAMP field for records saved before the text field existed.
        if let shootDatesText = record.getString("projectShootDatesText") {
            project.shootDates = shootDatesText
        } else if let shootDate = record.getDate("projectShootStart") {
            // Convert Date back to string format "Mar 15, 2025"
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d, yyyy"
            project.shootDates = dateFormatter.string(from: shootDate)
        } else {
            project.shootDates = ""
        }

        // Same precedence for the release date: verbatim text first, legacy Date second.
        if let releaseDateText = record.getString("projectReleaseDateText") {
            project.expectedReleaseDate = releaseDateText
        } else if let releaseDate = record.getDate("projectExpectedReleaseDate") {
            // Convert Date back to string format "Mar 2025" or "Mar 15, 2025"
            let dateFormatter = DateFormatter()
            
            // Check if it has a meaningful day component
            let calendar = Calendar.current
            let day = calendar.component(.day, from: releaseDate)
            
            if day > 1 {
                // Has specific day: "Mar 15, 2025"
                dateFormatter.dateFormat = "MMM d, yyyy"
            } else {
                // Just month/year: "Mar 2025"
                dateFormatter.dateFormat = "MMM yyyy"
            }
            project.expectedReleaseDate = dateFormatter.string(from: releaseDate)
        } else {
            project.expectedReleaseDate = ""
        }
        
        // Arrays - using schema field names
        if let castArray = record["projectCastNeeded"] as? [String] {
            project.castNeeded = castArray
        }
        
        if let crewArray = record["projectCrewNeeded"] as? [String] {
            project.crewNeeded = crewArray
        }

        if let genresArray = record["projectGenres"] as? [String] {
            project.genres = genresArray
        }

        // Parse assembled cast & crew from string arrays (profile IDs from parallel arrays)
        if let castAssembledArray = record["projectCastAssembled"] as? [String] {
            let ids = record["projectCastAssembledIDs"] as? [String]
            project.castAssembled = castAssembledArray.enumerated().compactMap { index, entry in
                let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return OrderedEntry(role: parts[0].trimmingCharacters(in: .whitespaces),
                                   name: parts[1].trimmingCharacters(in: .whitespaces),
                                   profileID: creditProfileID(from: ids, at: index))
            }
        }

        if let crewAssembledArray = record["projectCrewAssembled"] as? [String] {
            let ids = record["projectCrewAssembledIDs"] as? [String]
            project.crewAssembled = crewAssembledArray.enumerated().compactMap { index, entry in
                let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return OrderedEntry(role: parts[0].trimmingCharacters(in: .whitespaces),
                                   name: parts[1].trimmingCharacters(in: .whitespaces),
                                   profileID: creditProfileID(from: ids, at: index))
            }
        }
        
        // Slideshow images, each reusing an already-downloaded copy if this fetch didn't
        // include the asset (see `persistCloudKitAsset`).
        if let slideAssets = record["projectSlides"] as? [CKAsset] {
            project.slideImageFileNames = slideAssets.enumerated().compactMap { index, asset in
                FileManager.default.persistCloudKitAsset(
                    asset, fileName: "\(id.uuidString)_slide_\(index).jpg",
                    baseDirectory: FileManager.default.mediaCacheDirectory
                )
            }
        } else {
            // The asset LIST itself is missing from this fetch (a partial failure, or a
            // query that didn't request it), which is different from "this project has
            // no slides" — blanking the slideshow here is what made photography posts
            // lose their images on a refresh. Reuse whatever was already downloaded
            // instead; the file names are deterministic, so walking the indices
            // recovers the full slideshow.
            var cached: [String] = []
            var index = 0
            while let fileName = FileManager.default.persistCloudKitAsset(
                nil, fileName: "\(id.uuidString)_slide_\(index).jpg",
                baseDirectory: FileManager.default.mediaCacheDirectory
            ) {
                cached.append(fileName)
                index += 1
            }
            project.slideImageFileNames = cached
        }

        // Poster (reusing an already-downloaded copy if this fetch didn't include the
        // asset — see `persistCloudKitAsset`).
        project.thumbnailFileName = FileManager.default.persistCloudKitAsset(
            record.getAsset("projectPoster"),
            fileName: "\(id.uuidString)_poster.jpg",
            subdirectory: "thumbnails"
        )

        return project
    }
}

// MARK: - Event Model

struct Event: MediaItem {
    let id: UUID
    var title: String
    var details: String
    var isApproved: Bool = false
    var submittedBy: String = ""
    var createdDate: Date = Date()
    var lastEditedDate: Date?
    var thumbnailFileName: String?  // ✅ Changed from thumbnailData to thumbnailFileName
    
    var mediaType: MediaType { .event }
    
    // Computed property to get thumbnail URL from file system
    var thumbnailURL: URL? {
        guard let fileName = thumbnailFileName else { return nil }
        guard let documentsDir = FileManager.default.documentsDirectory else { return nil }
        let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
        let url = thumbnailsDir.appendingPathComponent(fileName)
        guard FileManager.default.fileExistsAndIsAccessible(at: url) else {
            return nil
        }
        return url
    }
    
    // Event-specific fields
    var eventStartDate: Date?
    var eventEndDate: Date?
    var eventLocation: String?
    var eventHost: String = ""
    var ticketsURL: String?
    /// Event category (Party, Concert, Info Session, …). Stored in the submission's
    /// `genres`, carried here so it round-trips through CloudKit.
    var eventCategory: String = ""
    /// Recruitment Schedule: expectations text.
    var eventExpectations: String?
    /// Recruitment Schedule: application link.
    var eventApplicationURL: String?
    /// Category lineup — Artists / Actors / Films depending on the category. Held as one
    /// freeform line (that's how the form collects it) and split into entries for
    /// CloudKit, where the field is a String list.
    var eventLineup: String?
    /// Theatre Performance: every showing in the run. Stored in CloudKit as a String list
    /// of `"<start>|<end>"` entries (see `EventShowing.wireEntries`). `eventStartDate` /
    /// `eventEndDate` still bracket the run, so anything that only knows about a single
    /// start/end — sorting, the expiry filter — keeps working.
    var eventShowings: [EventShowing] = []

    /// Splits the freeform lineup line into the entries stored in CloudKit's String list
    /// field. Commas and newlines both separate entries, since the field is a vertical
    /// TextField and people use either.
    private static func lineupEntries(from lineup: String?) -> [String] {
        guard let lineup else { return [] }
        return lineup
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - CloudKit Conversion
    
    func toCloudKitRecord(userRecordID: CKRecord.ID?) async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: "EventSubmission", recordID: recordID)
        
        // Using schema field names
        record["eventTitle"] = title as CKRecordValue
        record["eventDescription"] = details as CKRecordValue
        record["isApproved"] = (isApproved ? 1 : 0) as CKRecordValue
        record["submittedBy"] = submittedBy as CKRecordValue
        record["createdDate"] = createdDate as CKRecordValue
        
        if let lastEditedDate = lastEditedDate {
            record["lastEditedDate"] = lastEditedDate as CKRecordValue
        }
        
        if let userID = userRecordID?.recordName {
            record["userID"] = userID as CKRecordValue
        }
        
        // Event-specific fields - using schema field names
        // Note: Schema uses eventStartTime/eventEndTime, not eventStartDate/eventEndDate
        if let eventStartDate = eventStartDate {
            record["eventStartTime"] = eventStartDate as CKRecordValue
        }
        
        if let eventEndDate = eventEndDate {
            record["eventEndTime"] = eventEndDate as CKRecordValue
        }
        
        // Store the address as plain text. The app displays this string and hands it to
        // Maps, so a dedicated STRING field (`eventLocationText`) is used instead of the
        // CloudKit LOCATION type — a geocoded CLLocation can't be read back as text.
        // Always written (empty when cleared) so an edit that removes it overwrites the
        // stale server value.
        record["eventLocationText"] = (eventLocation ?? "") as CKRecordValue

        record["eventHost"] = eventHost as CKRecordValue
        record["eventCategory"] = eventCategory as CKRecordValue

        // Always written (empty when cleared) so an edit that removes the tickets link
        // overwrites the server. The blind `.allKeys` save leaves omitted keys at their
        // stale server value.
        record["eventTicketsURL"] = (ticketsURL ?? "") as CKRecordValue

        // Category-specific fields. All three now exist in the deployed schema (verified
        // in both the development and production environments), so they're written
        // unconditionally — an empty string overwrites the server value when an edit
        // clears the field, which an omitted key would not do under `.allKeys`.
        record["eventExpectations"] = (eventExpectations ?? "") as CKRecordValue
        record["eventApplicationURL"] = (eventApplicationURL ?? "") as CKRecordValue

        // `eventLineup` is a String LIST server-side, while the form collects one
        // freeform line of names — so the text is split into entries here and rejoined
        // in `fromCloudKitRecord`. Writing the raw String is a type mismatch that fails
        // the whole atomic save, which is what kept every event with a lineup out of
        // CloudKit. An empty list clears the field on an edit.
        record["eventLineup"] = Self.lineupEntries(from: eventLineup) as CKRecordValue

        // Theatre Performance showings, as a String list of "<start>|<end>" entries.
        // Written unconditionally (an empty list clears the field on an edit that removed
        // a showing). `eventShowtimes` is a newer field than the rest of this record, so
        // a deployed schema that lacks it rejects the save — the manager's schema-gap
        // rescue then drops this one key and retries, publishing the post without its
        // showings rather than losing it (see `CloudKitManager.nonCoreKeys`).
        record["eventShowtimes"] = EventShowing.wireEntries(from: eventShowings) as CKRecordValue

        // Thumbnail - using schema field name
        if let thumbnailURL = thumbnailURL,
           let thumbnailData = try? Data(contentsOf: thumbnailURL) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(id.uuidString + "_flyer_orig.jpg")
            try thumbnailData.write(to: tempURL)
            let uploadURL = downscaledImageForUpload(
                at: tempURL, maxDimension: 1600, tempName: id.uuidString + "_flyer.jpg"
            )
            record["eventFlyer"] = CKAsset(fileURL: uploadURL)
        }
        
        return record
    }
    
    static func fromCloudKitRecord(_ record: CKRecord) -> Event? {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        
        // Using schema field names
        let title = record.getString("eventTitle") ?? "Untitled"
        let details = record.getString("eventDescription") ?? ""
        
        var event = Self(id: id, title: title, details: details)
        
        event.isApproved = (record.getInt("isApproved") ?? 0) == 1
        event.submittedBy = record.getString("submittedBy") ?? "Anonymous"
        event.createdDate = record.getDate("createdDate") ?? Date()
        event.lastEditedDate = record.getDate("lastEditedDate")
        
        // Event-specific fields - using schema field names
        event.eventStartDate = record.getDate("eventStartTime")
        event.eventEndDate = record.getDate("eventEndTime")
        
        // Location is stored as plain text in `eventLocationText`. Fall back to a legacy
        // `eventLocation` string field for any records saved before the switch.
        event.eventLocation = record.getString("eventLocationText") ?? record.getString("eventLocation")

        event.eventHost = record.getString("eventHost") ?? ""
        event.eventCategory = record.getString("eventCategory") ?? ""
        event.ticketsURL = record.getString("eventTicketsURL")
        // Empty strings (written to clear a field) map back to nil so display guards work.
        event.eventExpectations = record.getString("eventExpectations").flatMap { $0.isEmpty ? nil : $0 }
        event.eventApplicationURL = record.getString("eventApplicationURL").flatMap { $0.isEmpty ? nil : $0 }
        // Stored as a String list (see `lineupEntries`); rejoined into the single line the
        // form and the cards display. `getString` covers any record written before the
        // switch to the list field.
        let lineupEntries = record.getStringArray("eventLineup") ?? record.getString("eventLineup").map { [$0] } ?? []
        let lineup = lineupEntries.joined(separator: ", ")
        event.eventLineup = lineup.isEmpty ? nil : lineup
        event.eventShowings = EventShowing.showings(
            fromWireEntries: record.getStringArray("eventShowtimes") ?? []
        )
        
        // Flyer (reusing an already-downloaded copy if this fetch didn't include the
        // asset — see `persistCloudKitAsset`).
        event.thumbnailFileName = FileManager.default.persistCloudKitAsset(
            record.getAsset("eventFlyer"),
            fileName: "\(id.uuidString)_flyer.jpg",
            subdirectory: "thumbnails"
        )

        return event
    }
}

// MARK: - Asset Persistence Helper

extension FileManager {

    /// Persists a CloudKit asset to a stable file under Documents (optionally inside a
    /// subdirectory) and returns the file name to store on the model.
    ///
    /// The important part is the fallback: the feed query downloads the full assets, so
    /// a single fetch can arrive with an asset field empty (a transient asset-download
    /// failure, or the record materialized without it). When that happens we must NOT
    /// blank out media we already downloaded on a previous sync — doing so is what left
    /// posts showing an empty thumbnail / no playable video after a reload. So if the
    /// asset isn't present in this fetch but a previously-saved copy already exists on
    /// disk at the deterministic file name, we keep that existing copy.
    ///
    /// Returns `nil` only when the asset is absent *and* nothing is cached locally.
    /// `baseDirectory` selects where the file lives; it defaults to Documents (used by
    /// thumbnails, which pass a `subdirectory`). Heavy media (video) passes the media
    /// cache directory so large files stay in the purgeable, backup-excluded cache.
    func persistCloudKitAsset(_ asset: CKAsset?, fileName: String, subdirectory: String? = nil, baseDirectory: URL? = nil) -> String? {
        guard let base = baseDirectory ?? documentsDirectory else { return nil }

        let targetDir: URL
        if let subdirectory {
            targetDir = base.appendingPathComponent(subdirectory)
            try? createDirectory(at: targetDir, withIntermediateDirectories: true)
        } else {
            targetDir = base
        }
        let destination = targetDir.appendingPathComponent(fileName)

        if let sourceURL = asset?.fileURL {
            do {
                try? removeItem(at: destination)
                try copyItem(at: sourceURL, to: destination)
                return fileName
            } catch {
                print("❌ Failed to persist CloudKit asset \(fileName): \(error)")
                // Fall through: keep any existing on-disk copy rather than losing it.
            }
        }

        // Asset absent from this fetch (or the copy failed): reuse the existing local
        // copy if we downloaded it before.
        return fileExistsAndIsAccessible(at: destination) ? fileName : nil
    }

    /// Whether a cached thumbnail needs to be (re)downloaded. Returns true when no local
    /// copy exists, or when the local copy predates the record's `lastEdited` date (so
    /// replaced artwork refreshes). The feed queries no longer request image assets, so
    /// this drives a one-time hydration: a warm, up-to-date cache does zero network.
    func cachedThumbnailNeedsRefresh(fileName: String, subdirectory: String?, lastEdited: Date?) -> Bool {
        guard let documentsDir = documentsDirectory else { return true }
        let dir = subdirectory.map { documentsDir.appendingPathComponent($0) } ?? documentsDir
        let path = dir.appendingPathComponent(fileName)
        guard fileExistsAndIsAccessible(at: path) else { return true }   // never downloaded
        guard let lastEdited else { return false }                       // never edited: cache is fine
        let modDate = (try? attributesOfItem(atPath: path.path))?[.modificationDate] as? Date
        guard let modDate else { return false }
        return modDate < lastEdited                                      // stale: artwork was replaced
    }

    /// Detects an audio container from its magic bytes. `AVPlayer` decodes local files
    /// by their extension, so a downloaded track saved with the wrong extension (e.g.
    /// mp3 bytes in a `.m4a` file) reports `isPlayable == false` and won't play. This
    /// lets the download path pick a correct extension even when the original file name
    /// wasn't recorded. Falls back to `m4a` when the format is unrecognized.
    func sniffAudioExtension(at url: URL, default fallback: String = "m4a") -> String {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return fallback }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 12), data.count >= 12 else { return fallback }
        let b = [UInt8](data)
        // MP3: "ID3" tag or an MPEG audio frame sync.
        if b[0] == 0x49, b[1] == 0x44, b[2] == 0x33 { return "mp3" }
        if b[0] == 0xFF, (b[1] & 0xE0) == 0xE0 { return "mp3" }
        // WAV: "RIFF"
        if b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46 { return "wav" }
        // AIFF: "FORM"
        if b[0] == 0x46, b[1] == 0x4F, b[2] == 0x52, b[3] == 0x4D { return "aiff" }
        // FLAC: "fLaC"
        if b[0] == 0x66, b[1] == 0x4C, b[2] == 0x61, b[3] == 0x43 { return "flac" }
        // CAF: "caff"
        if b[0] == 0x63, b[1] == 0x61, b[2] == 0x66, b[3] == 0x66 { return "caf" }
        // MP4/M4A: "ftyp" box at offset 4.
        if b[4] == 0x66, b[5] == 0x74, b[6] == 0x79, b[7] == 0x70 { return "m4a" }
        return fallback
    }

    /// Finds an already-saved audio copy for this submission regardless of extension
    /// (e.g. `<id>_audio.mp3`). Returns the file name, or nil if none is cached.
    func existingAudioFileName(forSubmissionID id: String) -> String? {
        let prefix = "\(id)_audio."
        // Media cache first, then Documents (legacy copies from older builds).
        for dir in [mediaCacheDirectory, documentsDirectory].compactMap({ $0 }) {
            let names = (try? contentsOfDirectory(atPath: dir.path)) ?? []
            if let match = names.first(where: { $0.hasPrefix(prefix) }) { return match }
        }
        return nil
    }

    /// Persists (or reuses) a submission's audio asset under a stable, correctly-typed
    /// file name `<id>_audio.<ext>`. The extension is taken from `preferredExtension`
    /// when known (recorded at upload), otherwise sniffed from the asset's bytes. When
    /// the asset is absent (the light feed fetch skips heavy media) any previously
    /// downloaded copy is reused instead of blanking the reference.
    func persistAudioAsset(_ asset: CKAsset?, submissionID id: String, preferredExtension: String?) -> String? {
        guard let mediaDir = mediaCacheDirectory else { return nil }

        if let sourceURL = asset?.fileURL {
            let ext: String
            if let preferredExtension, !preferredExtension.isEmpty {
                ext = preferredExtension
            } else {
                ext = sniffAudioExtension(at: sourceURL)
            }
            let fileName = "\(id)_audio.\(ext)"
            let destination = mediaDir.appendingPathComponent(fileName)
            do {
                // Drop any stale copy (including a previously wrong-extension one), in
                // either the cache or a legacy Documents location.
                if let stale = existingAudioFileName(forSubmissionID: id) {
                    removeMediaFile(named: stale)
                }
                try copyItem(at: sourceURL, to: destination)
                return fileName
            } catch {
                print("❌ Failed to persist audio asset \(fileName): \(error)")
            }
        }

        // Asset absent from this fetch (or the copy failed): reuse a cached copy.
        return existingAudioFileName(forSubmissionID: id)
    }
}

// MARK: - CKRecord Helper Extension

extension CKRecord {
    
    /// Safely get a String value from a CKRecord field
    func getString(_ key: String) -> String? {
        return self[key] as? String
    }
    
    /// Safely get an Int value from a CKRecord field
    func getInt(_ key: String) -> Int? {
        return self[key] as? Int
    }
    
    /// Safely get a Date value from a CKRecord field
    func getDate(_ key: String) -> Date? {
        return self[key] as? Date
    }
    
    /// Safely get a CKAsset value from a CKRecord field
    func getAsset(_ key: String) -> CKAsset? {
        return self[key] as? CKAsset
    }
    
    /// Safely get a Bool value from a CKRecord field
    func getBool(_ key: String) -> Bool? {
        if let intValue = self[key] as? Int {
            return intValue == 1
        }
        return self[key] as? Bool
    }
    
    /// Safely get an array of Strings from a CKRecord field
    func getStringArray(_ key: String) -> [String]? {
        return self[key] as? [String]
    }
    
    /// Safely get a Double value from a CKRecord field
    func getDouble(_ key: String) -> Double? {
        return self[key] as? Double
    }
}
