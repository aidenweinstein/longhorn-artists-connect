//
//  MediaModels.swift
//  Longhorn Artists Connect
//
//  Separate models for each media type (Film, Music, Reel, Project, Event)
//

import Foundation
import CloudKit
import CoreLocation  // For CLGeocoder and CLLocation

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
    
    // Cast & Crew
    var orderedCast: [OrderedEntry] = []
    var orderedCrew: [OrderedEntry] = []
    
    // Studio
    var studio: String = ""
    
    // Media files
    var videoFileName: String?
    
    // Computed property to get video URL
    var videoURL: URL? {
        guard let videoFileName = videoFileName else { return nil }
        guard let documentsDir = FileManager.default.documentsDirectory else { return nil }
        let url = documentsDir.appendingPathComponent(videoFileName)
        guard FileManager.default.fileExistsAndIsAccessible(at: url) else {
            return nil
        }
        return url
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
        
        // Only save genres if not empty (CloudKit needs to know the type)
        if !genres.isEmpty {
            record["filmGenres"] = genres as CKRecordValue
        }
        
        // Cast & Crew as arrays (not JSON) - schema uses filmCast and filmCrew.
        // Profile IDs are stored in a parallel, index-aligned array so the visible
        // "role: name" strings stay clean for older app versions.
        if !orderedCast.isEmpty {
            let castStrings = orderedCast.map { "\($0.role): \($0.name)" }
            record["filmCast"] = castStrings as CKRecordValue
            record["filmCastIDs"] = orderedCast.map { $0.profileID ?? "" } as CKRecordValue
        }

        if !orderedCrew.isEmpty {
            let crewStrings = orderedCrew.map { "\($0.role): \($0.name)" }
            record["filmCrew"] = crewStrings as CKRecordValue
            record["filmCrewIDs"] = orderedCrew.map { $0.profileID ?? "" } as CKRecordValue
        }
        
        // Video asset - using schema field name
        if let videoURL = videoURL {
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
                
                let videoAsset = CKAsset(fileURL: finalVideoURL)
                record["filmVideo"] = videoAsset
                print("✅ Film video asset prepared for upload")
            } catch {
                print("❌ Failed to prepare film video asset: \(error.localizedDescription)")
                throw error
            }
        }
        
        // Thumbnail - using schema field name
        if let thumbnailURL = thumbnailURL,
           let thumbnailData = try? Data(contentsOf: thumbnailURL) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(id.uuidString + "_thumb.jpg")
            try thumbnailData.write(to: tempURL)
            let asset = CKAsset(fileURL: tempURL)
            record["filmThumbnail"] = asset
        }
        
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
        
        // Download video - using schema field name
        if let videoAsset = record.getAsset("filmVideo"),
           let videoSourceURL = videoAsset.fileURL,
           let documentsDir = FileManager.default.documentsDirectory {
            
            let videoFileName = "\(id.uuidString)_video.mov"
            let destinationURL = documentsDir.appendingPathComponent(videoFileName)
            
            do {
                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.copyItem(at: videoSourceURL, to: destinationURL)
                film.videoFileName = videoFileName
            } catch {
                print("❌ Failed to download video: \(error)")
            }
        }
        
        // Download thumbnail - using schema field name and save to file system
        if let asset = record.getAsset("filmThumbnail"),
           let fileURL = asset.fileURL,
           let data = try? Data(contentsOf: fileURL),
           let documentsDir = FileManager.default.documentsDirectory {
            
            // Ensure thumbnails directory exists
            let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
            
            let thumbnailFileName = "\(id.uuidString)_thumb.jpg"
            let thumbnailDestination = thumbnailsDir.appendingPathComponent(thumbnailFileName)
            
            do {
                try? FileManager.default.removeItem(at: thumbnailDestination)
                try data.write(to: thumbnailDestination)
                film.thumbnailFileName = thumbnailFileName
                print("✅ Saved thumbnail to file: \(thumbnailFileName)")
            } catch {
                print("❌ Failed to save thumbnail: \(error)")
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
    
    // Media files
    var audioFileName: String?
    var videoFileName: String?  // For music video
    
    // Computed property to get audio URL
    var audioURL: URL? {
        guard let audioFileName = audioFileName else { return nil }
        guard let documentsDir = FileManager.default.documentsDirectory else { return nil }
        let url = documentsDir.appendingPathComponent(audioFileName)
        guard FileManager.default.fileExistsAndIsAccessible(at: url) else {
            return nil
        }
        return url
    }
    
    // Computed property to get video URL
    var videoURL: URL? {
        guard let videoFileName = videoFileName else { return nil }
        guard let documentsDir = FileManager.default.documentsDirectory else { return nil }
        let url = documentsDir.appendingPathComponent(videoFileName)
        guard FileManager.default.fileExistsAndIsAccessible(at: url) else {
            return nil
        }
        return url
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
        record["musicExplicit"] = (explicit ? 1 : 0) as CKRecordValue
        
        // Only save genres if not empty (CloudKit needs to know the type)
        if !genres.isEmpty {
            record["musicGenres"] = genres as CKRecordValue
        }
        
        // Streaming links - using schema field names
        record["musicSpotifyLink"] = spotifyLink as CKRecordValue
        record["musicAppleMusicLink"] = appleMusicLink as CKRecordValue
        // Note: schema doesn't have Amazon or YouTube Music, using custom fields
        if !amazonMusicLink.isEmpty {
            record["amazonMusicLink"] = amazonMusicLink as CKRecordValue
        }
        if !youtubeMusicLink.isEmpty {
            record["youtubeMusicLink"] = youtubeMusicLink as CKRecordValue
        }
        if !soundcloudLink.isEmpty {
            record["soundcloudLink"] = soundcloudLink as CKRecordValue
        }
        
        // Credits as arrays - using schema field names (profile IDs in parallel arrays)
        if !orderedRecording.isEmpty {
            let recordingStrings = orderedRecording.map { "\($0.role): \($0.name)" }
            record["musicRecording"] = recordingStrings as CKRecordValue
            record["musicRecordingIDs"] = orderedRecording.map { $0.profileID ?? "" } as CKRecordValue
        }

        if !orderedProduction.isEmpty {
            let productionStrings = orderedProduction.map { "\($0.role): \($0.name)" }
            record["musicProduction"] = productionStrings as CKRecordValue
            record["musicProductionIDs"] = orderedProduction.map { $0.profileID ?? "" } as CKRecordValue
        }
        
        // Audio asset - using schema field name
        if let audioURL = audioURL {
            let tempAudioURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(id.uuidString)
                .appendingPathExtension("m4a")
            
            try? FileManager.default.removeItem(at: tempAudioURL)
            try FileManager.default.copyItem(at: audioURL, to: tempAudioURL)
            
            let audioAsset = CKAsset(fileURL: tempAudioURL)
            record["musicAudio"] = audioAsset
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
                
                let videoAsset = CKAsset(fileURL: finalVideoURL)
                record["musicVideo"] = videoAsset
                print("✅ Music video asset prepared for upload")
            } catch {
                print("❌ Failed to prepare music video: \(error.localizedDescription)")
                throw error
            }
        }
        
        // Thumbnail (cover art) - using schema field name
        if let thumbnailURL = thumbnailURL,
           let thumbnailData = try? Data(contentsOf: thumbnailURL) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(id.uuidString + "_cover.jpg")
            try thumbnailData.write(to: tempURL)
            let asset = CKAsset(fileURL: tempURL)
            record["musicCover"] = asset
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
        
        // Download audio - using schema field name
        if let audioAsset = record.getAsset("musicAudio"),
           let audioSourceURL = audioAsset.fileURL,
           let documentsDir = FileManager.default.documentsDirectory {
            
            let audioFileName = "\(id.uuidString)_audio.m4a"
            let destinationURL = documentsDir.appendingPathComponent(audioFileName)
            
            do {
                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.copyItem(at: audioSourceURL, to: destinationURL)
                music.audioFileName = audioFileName
            } catch {
                print("❌ Failed to download audio: \(error)")
            }
        }
        
        // Download music video - using custom field name
        if let videoAsset = record.getAsset("musicVideo"),
           let videoSourceURL = videoAsset.fileURL,
           let documentsDir = FileManager.default.documentsDirectory {
            
            let videoFileName = "\(id.uuidString)_video.mov"
            let destinationURL = documentsDir.appendingPathComponent(videoFileName)
            
            do {
                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.copyItem(at: videoSourceURL, to: destinationURL)
                music.videoFileName = videoFileName
                print("✅ Downloaded music video: \(videoFileName)")
            } catch {
                print("❌ Failed to download music video: \(error)")
            }
        }
        
        // Download cover art - using schema field name and save to file system
        if let asset = record.getAsset("musicCover"),
           let fileURL = asset.fileURL,
           let data = try? Data(contentsOf: fileURL),
           let documentsDir = FileManager.default.documentsDirectory {
            
            // Ensure thumbnails directory exists
            let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
            
            let thumbnailFileName = "\(id.uuidString)_cover.jpg"
            let thumbnailDestination = thumbnailsDir.appendingPathComponent(thumbnailFileName)
            
            do {
                try? FileManager.default.removeItem(at: thumbnailDestination)
                try data.write(to: thumbnailDestination)
                music.thumbnailFileName = thumbnailFileName
                print("✅ Saved music cover to file: \(thumbnailFileName)")
            } catch {
                print("❌ Failed to save music cover: \(error)")
            }
        }
        
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
    
    // Crew credits
    var orderedCrew: [OrderedEntry] = []
    
    // Media files
    var videoFileName: String?
    
    var videoURL: URL? {
        guard let videoFileName = videoFileName else { return nil }
        guard let documentsDir = FileManager.default.documentsDirectory else { return nil }
        let url = documentsDir.appendingPathComponent(videoFileName)
        guard FileManager.default.fileExistsAndIsAccessible(at: url) else {
            return nil
        }
        return url
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
        
        // Crew as array (if not empty), with profile IDs in a parallel array
        if !orderedCrew.isEmpty {
            let crewStrings = orderedCrew.map { "\($0.role): \($0.name)" }
            record["orderedCrew"] = crewStrings as CKRecordValue
            record["orderedCrewIDs"] = orderedCrew.map { $0.profileID ?? "" } as CKRecordValue
        }
        
        // Video asset - using schema field name
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
                    print("📊 Reel compression progress: \(Int(progress * 100))%")
                }
                
                let videoAsset = CKAsset(fileURL: finalVideoURL)
                record["reelVideo"] = videoAsset
                print("✅ Reel video asset prepared for upload")
            } catch {
                print("❌ Failed to prepare reel video: \(error.localizedDescription)")
                throw error
            }
        }
        
        if let thumbnailURL = thumbnailURL,
           let thumbnailData = try? Data(contentsOf: thumbnailURL) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(id.uuidString + "_thumb.jpg")
            try thumbnailData.write(to: tempURL)
            let asset = CKAsset(fileURL: tempURL)
            record["reelThumbnail"] = asset
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
        
        // Download video - using schema field name
        if let videoAsset = record.getAsset("reelVideo"),
           let videoSourceURL = videoAsset.fileURL,
           let documentsDir = FileManager.default.documentsDirectory {
            
            let videoFileName = "\(id.uuidString)_video.mov"
            let destinationURL = documentsDir.appendingPathComponent(videoFileName)
            
            do {
                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.copyItem(at: videoSourceURL, to: destinationURL)
                reel.videoFileName = videoFileName
            } catch {
                print("❌ Failed to download reel video: \(error)")
            }
        }
        
        // Download thumbnail - using schema field name and save to file system
        if let asset = record.getAsset("reelThumbnail"),
           let fileURL = asset.fileURL,
           let data = try? Data(contentsOf: fileURL),
           let documentsDir = FileManager.default.documentsDirectory {
            
            // Ensure thumbnails directory exists
            let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
            
            let thumbnailFileName = "\(id.uuidString)_thumb.jpg"
            let thumbnailDestination = thumbnailsDir.appendingPathComponent(thumbnailFileName)
            
            do {
                try? FileManager.default.removeItem(at: thumbnailDestination)
                try data.write(to: thumbnailDestination)
                reel.thumbnailFileName = thumbnailFileName
                print("✅ Saved reel thumbnail to file: \(thumbnailFileName)")
            } catch {
                print("❌ Failed to save reel thumbnail: \(error)")
            }
        }
        
        return reel
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
        
        // Only save arrays if not empty (CloudKit needs to know the type)
        if !castNeeded.isEmpty {
            record["projectCastNeeded"] = castNeeded as CKRecordValue
        }
        if !crewNeeded.isEmpty {
            record["projectCrewNeeded"] = crewNeeded as CKRecordValue
        }
        
        // Assembled cast & crew (profile IDs in parallel arrays)
        if !castAssembled.isEmpty {
            let castStrings = castAssembled.map { "\($0.role): \($0.name)" }
            record["projectCastAssembled"] = castStrings as CKRecordValue
            record["projectCastAssembledIDs"] = castAssembled.map { $0.profileID ?? "" } as CKRecordValue
        }
        if !crewAssembled.isEmpty {
            let crewStrings = crewAssembled.map { "\($0.role): \($0.name)" }
            record["projectCrewAssembled"] = crewStrings as CKRecordValue
            record["projectCrewAssembledIDs"] = crewAssembled.map { $0.profileID ?? "" } as CKRecordValue
        }
        // Note: genres not in Project schema, skipping
        
        // Thumbnail - using schema field name
        if let thumbnailURL = thumbnailURL,
           let thumbnailData = try? Data(contentsOf: thumbnailURL) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(id.uuidString + "_poster.jpg")
            try thumbnailData.write(to: tempURL)
            let asset = CKAsset(fileURL: tempURL)
            record["projectPoster"] = asset
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
        // projectShootStart is TIMESTAMP type in CloudKit, but we store as String locally
        if let shootDate = record.getDate("projectShootStart") {
            // Convert Date back to string format "Mar 15, 2025"
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d, yyyy"
            project.shootDates = dateFormatter.string(from: shootDate)
        } else {
            project.shootDates = ""
        }
        
        // projectExpectedReleaseDate is TIMESTAMP type in CloudKit (new field name)
        if let releaseDate = record.getDate("projectExpectedReleaseDate") {
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
        
        // Thumbnail - using schema field name and save to file system
        if let asset = record.getAsset("projectPoster"),
           let fileURL = asset.fileURL,
           let data = try? Data(contentsOf: fileURL),
           let documentsDir = FileManager.default.documentsDirectory {
            
            // Ensure thumbnails directory exists
            let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
            
            let thumbnailFileName = "\(id.uuidString)_poster.jpg"
            let thumbnailDestination = thumbnailsDir.appendingPathComponent(thumbnailFileName)
            
            do {
                try? FileManager.default.removeItem(at: thumbnailDestination)
                try data.write(to: thumbnailDestination)
                project.thumbnailFileName = thumbnailFileName
                print("✅ Saved project poster to file: \(thumbnailFileName)")
            } catch {
                print("❌ Failed to save project poster: \(error)")
            }
        }
        
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
        
        if let eventLocation = eventLocation, !eventLocation.isEmpty {
            // CloudKit schema expects LOCATION type (CLLocation with coordinates)
            // We need to geocode the address string to get coordinates
            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.geocodeAddressString(eventLocation)
                if let location = placemarks.first?.location {
                    // Save as CLLocation (LOCATION type in CloudKit)
                    record["eventLocation"] = location as CKRecordValue
                    print("✅ Geocoded '\(eventLocation)' to coordinates: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                } else {
                    print("⚠️ Could not geocode location: \(eventLocation)")
                    // Fallback: Don't set eventLocation field if geocoding fails
                    // You may want to add a separate STRING field for the address text
                }
            } catch {
                print("❌ Geocoding failed for '\(eventLocation)': \(error.localizedDescription)")
                // Fallback: Don't set eventLocation field if geocoding fails
            }
        }
        
        record["eventHost"] = eventHost as CKRecordValue
        
        if let ticketsURL = ticketsURL {
            record["eventTicketsURL"] = ticketsURL as CKRecordValue
        }
        
        // Thumbnail - using schema field name
        if let thumbnailURL = thumbnailURL,
           let thumbnailData = try? Data(contentsOf: thumbnailURL) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(id.uuidString + "_flyer.jpg")
            try thumbnailData.write(to: tempURL)
            let asset = CKAsset(fileURL: tempURL)
            record["eventFlyer"] = asset
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
        
        // Location: Read as string (requires CloudKit schema to be STRING type)
        event.eventLocation = record.getString("eventLocation")
        
        /* 
        // TO READ LOCATION TYPE FROM CLOUDKIT:
        // If your CloudKit schema uses LOCATION type, uncomment this:
        
        if let location = record["eventLocation"] as? CLLocation {
            // Convert CLLocation back to readable string for display
            let geocoder = CLGeocoder()
            Task {
                do {
                    let placemarks = try await geocoder.reverseGeocodeLocation(location)
                    if let placemark = placemarks.first {
                        let components = [
                            placemark.name,
                            placemark.locality,
                            placemark.administrativeArea
                        ].compactMap { $0 }
                        event.eventLocation = components.joined(separator: ", ")
                    }
                } catch {
                    // Fallback to coordinates
                    event.eventLocation = "\(location.coordinate.latitude), \(location.coordinate.longitude)"
                }
            }
        } else {
            // Fallback: try reading as string
            event.eventLocation = record.getString("eventLocationString")
        }
        */
        
        event.eventHost = record.getString("eventHost") ?? ""
        event.ticketsURL = record.getString("eventTicketsURL")
        
        // Thumbnail - using schema field name and save to file system
        if let asset = record.getAsset("eventFlyer"),
           let fileURL = asset.fileURL,
           let data = try? Data(contentsOf: fileURL),
           let documentsDir = FileManager.default.documentsDirectory {
            
            // Ensure thumbnails directory exists
            let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
            
            let thumbnailFileName = "\(id.uuidString)_flyer.jpg"
            let thumbnailDestination = thumbnailsDir.appendingPathComponent(thumbnailFileName)
            
            do {
                try? FileManager.default.removeItem(at: thumbnailDestination)
                try data.write(to: thumbnailDestination)
                event.thumbnailFileName = thumbnailFileName
                print("✅ Saved event flyer to file: \(thumbnailFileName)")
            } catch {
                print("❌ Failed to save event flyer: \(error)")
            }
        }
        
        return event
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
