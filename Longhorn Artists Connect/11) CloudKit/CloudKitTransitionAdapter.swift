//
//  CloudKitTransitionAdapter.swift
//  Longhorn Artists Connect
//
//  Adapter to gradually transition from old to new CloudKit structure
//  This allows you to migrate without breaking existing code
//

import Foundation
import CloudKit
import SwiftUI
import Combine

/// Adapter that works with both old and new CloudKit implementations
/// Use this during the transition period
@MainActor
class CloudKitTransitionAdapter: ObservableObject {
    static let shared = CloudKitTransitionAdapter()
    
    @Published var isUsingNewSystem = false
    @Published var migrationComplete = false
    
    private let oldManager = CloudKitManager.shared
    private let newManager = CloudKitManager.shared
    
    private init() {
        // Check if migration has been completed
        migrationComplete = UserDefaults.standard.bool(forKey: "cloudkit_migration_complete")
        
        // 🔥 FORCE NEW SYSTEM - Your CloudKit schema uses separate record types
        // (FilmSubmission, MusicSubmission, etc.) so we MUST use the new system
        isUsingNewSystem = true
        
        print("🔧 ========================================")
        print("🔧 CloudKitTransitionAdapter Initialized")
        print("🔧 ========================================")
        print("🔧 Using new system: \(isUsingNewSystem)")
        print("🔧 Migration complete: \(migrationComplete)")
        print("🔧 ")
        print("🔧 Record types in use:")
        print("🔧 - FilmSubmission")
        print("🔧 - MusicSubmission")
        print("🔧 - ReelSubmission")
        print("🔧 - ProjectSubmission")
        print("🔧 - EventSubmission")
        print("🔧 ")
        print("🔧 ❌ NOT using old 'Submission' record type")
        print("🔧 ========================================")
    }
    
    // MARK: - Save Operations
    
    /// Save a submission using the appropriate system.
    ///
    /// `preservingOwner` is for writing a post this account didn't create (a moderator
    /// editing someone else's submission): it keeps the record's `userID` unwritten so
    /// the save doesn't reassign the post to the editor.
    func saveSubmission(_ submission: Submission, preservingOwner: Bool = false) async throws {
        if isUsingNewSystem {
            // Use new system - convert to specific type
            switch submission.type {
            case .film:
                let film = convertSubmissionToFilm(submission)
                try await newManager.saveFilm(film, preservingOwner: preservingOwner)
            case .music:
                let music = convertSubmissionToMusic(submission)
                try await newManager.saveMusic(music, preservingOwner: preservingOwner)
            case .reel:
                let reel = convertSubmissionToReel(submission)
                try await newManager.saveReel(reel, preservingOwner: preservingOwner)
            case .project:
                let project = convertSubmissionToProject(submission)
                try await newManager.saveProject(project, preservingOwner: preservingOwner)
            case .event:
                let event = convertSubmissionToEvent(submission)
                try await newManager.saveEvent(event, preservingOwner: preservingOwner)
            case .photography:
                let photography = convertSubmissionToPhotography(submission)
                try await newManager.savePhotography(photography, preservingOwner: preservingOwner)
            case .design:
                let design = convertSubmissionToDesign(submission)
                try await newManager.saveDesign(design, preservingOwner: preservingOwner)
            }
        } else {
            // Use old system
            try await oldManager.saveSubmission(submission)
        }
    }
    
    // MARK: - Fetch Operations
    
    /// Fetch all submissions (pending and approved) using the appropriate system
    func fetchAllSubmissions() async throws -> [Submission] {
        if isUsingNewSystem {
            // Fetch ALL items from new system (not just approved). Each type is
            // tolerated independently so one type's schema gap can't empty the
            // whole feed — see `FeedFetch.tolerating`.
            async let allFilms = FeedFetch.tolerating("Film") { try await newManager.fetchAllFilms() }
            async let allMusic = FeedFetch.tolerating("Music") { try await newManager.fetchAllMusic() }
            async let allReels = FeedFetch.tolerating("Reel") { try await newManager.fetchAllReels() }
            async let allProjects = FeedFetch.tolerating("Project") { try await newManager.fetchAllProjects() }
            async let allEvents = FeedFetch.tolerating("Event") { try await newManager.fetchAllEvents() }
            async let allPhotography = FeedFetch.tolerating("Photography") { try await newManager.fetchAllPhotography() }
            async let allDesign = FeedFetch.tolerating("Design") { try await newManager.fetchAllDesign() }

            let (films, music, reels, projects, events, photography, design) = await (allFilms, allMusic, allReels, allProjects, allEvents, allPhotography, allDesign)

            var submissions: [Submission] = []
            submissions += films.map { convertFilmToSubmission($0) }
            submissions += music.map { convertMusicToSubmission($0) }
            submissions += reels.map { convertReelToSubmission($0) }
            submissions += projects.map { convertProjectToSubmission($0) }
            submissions += events.map { convertEventToSubmission($0) }
            submissions += photography.map { convertPhotographyToSubmission($0) }
            submissions += design.map { convertDesignToSubmission($0) }

            // Sort by date
            submissions.sort { $0.createdDate > $1.createdDate }

            return submissions
        } else {
            // Use old system
            return try await oldManager.fetchAllSubmissions()
        }
    }
    
    /// Fetch all approved submissions using the appropriate system
    func fetchAllApprovedSubmissions() async throws -> [Submission] {
        if isUsingNewSystem {
            // Fetch from new system and convert back to Submission
            let (films, music, reels, projects, events, photography, design) = await newManager.fetchAllApprovedItems()

            var submissions: [Submission] = []
            submissions += films.map { convertFilmToSubmission($0) }
            submissions += music.map { convertMusicToSubmission($0) }
            submissions += reels.map { convertReelToSubmission($0) }
            submissions += projects.map { convertProjectToSubmission($0) }
            submissions += events.map { convertEventToSubmission($0) }
            submissions += photography.map { convertPhotographyToSubmission($0) }
            submissions += design.map { convertDesignToSubmission($0) }

            // Sort by date
            submissions.sort { $0.createdDate > $1.createdDate }

            return submissions
        } else {
            // Use old system
            return try await oldManager.fetchAllApprovedSubmissions()
        }
    }
    
    // MARK: - Delete Operations
    
    /// Delete a submission using the appropriate system
    func deleteSubmission(_ submission: Submission) async throws {
        if isUsingNewSystem {
            switch submission.type {
            case .film:
                let film = convertSubmissionToFilm(submission)
                try await newManager.deleteFilm(film)
            case .music:
                let music = convertSubmissionToMusic(submission)
                try await newManager.deleteMusic(music)
            case .reel:
                let reel = convertSubmissionToReel(submission)
                try await newManager.deleteReel(reel)
            case .project:
                let project = convertSubmissionToProject(submission)
                try await newManager.deleteProject(project)
            case .event:
                let event = convertSubmissionToEvent(submission)
                try await newManager.deleteEvent(event)
            case .photography:
                let photography = convertSubmissionToPhotography(submission)
                try await newManager.deletePhotography(photography)
            case .design:
                let design = convertSubmissionToDesign(submission)
                try await newManager.deleteDesign(design)
            }
        } else {
            try await oldManager.deleteSubmission(submission)
        }
    }
    
    // MARK: - Existence Check

    /// Whether a record currently exists in CloudKit. See `CloudKitManager.recordExists`
    /// for the meaning of the three-way result. Record IDs are the submission's UUID
    /// regardless of type, so a single lookup works for every media kind.
    func recordExists(id: UUID) async -> Bool? {
        await (isUsingNewSystem ? newManager : oldManager).recordExists(id: id)
    }

    // MARK: - Migration Control
    
    /// Mark migration as complete and switch to new system
    func completeMigration() {
        UserDefaults.standard.set(true, forKey: "cloudkit_migration_complete")
        isUsingNewSystem = true
        migrationComplete = true
        print("✅ Migration marked as complete - now using new CloudKit system")
    }
    
    /// Revert to old system (rollback)
    func revertToOldSystem() {
        UserDefaults.standard.set(false, forKey: "cloudkit_migration_complete")
        isUsingNewSystem = false
        migrationComplete = false
        print("⚠️ Reverted to old CloudKit system")
    }
    
    /// Check if CloudKit is available
    func checkAvailability() async {
        if isUsingNewSystem {
            await newManager.checkAvailability()
        } else {
            await oldManager.checkAvailability()
        }
    }
    
    var isAvailable: Bool {
        isUsingNewSystem ? newManager.isAvailable : oldManager.isAvailable
    }
    
    // MARK: - Conversion from Media Types to Submission
    
    private func convertFilmToSubmission(_ film: Film) -> Submission {
        var submission = Submission(
            id: film.id,
            type: .film,
            title: film.title,
            details: film.details
        )
        submission.isApproved = film.isApproved
        submission.submittedBy = film.submittedBy
        submission.createdDate = film.createdDate
        submission.lastEditedDate = film.lastEditedDate
        submission.schoolID = film.schoolID
        
        // Convert thumbnailFileName to thumbnailData if needed
        if let thumbnailURL = film.thumbnailURL,
           let thumbnailData = try? Data(contentsOf: thumbnailURL) {
            submission.thumbnailData = thumbnailData
        }
        
        submission.logline = film.logline
        submission.ageRating = film.ageRating
        submission.genres = film.genres
        submission.explicit = film.explicit
        submission.orderedCast = film.orderedCast
        submission.orderedCrew = film.orderedCrew
        submission.studio = film.studio
        submission.releaseYear = film.releaseYear
        submission.videoFileName = film.videoFileName
        submission.videoDuration = film.videoDuration
        submission.videoCrop = film.videoCrop
        submission.festivalBound = film.festivalBound
        submission.trailerFileName = film.trailerFileName
        submission.btsImageFileNames = film.btsImageFileNames
        submission.stillImageFileNames = film.stillImageFileNames

        return submission
    }
    
    private func convertMusicToSubmission(_ music: Music) -> Submission {
        var submission = Submission(
            id: music.id,
            type: .music,
            title: music.title,
            details: music.details
        )
        submission.isApproved = music.isApproved
        submission.submittedBy = music.submittedBy
        submission.createdDate = music.createdDate
        submission.lastEditedDate = music.lastEditedDate
        submission.schoolID = music.schoolID
        
        // Convert thumbnailFileName to thumbnailData if needed
        if let thumbnailURL = music.thumbnailURL,
           let thumbnailData = try? Data(contentsOf: thumbnailURL) {
            submission.thumbnailData = thumbnailData
        }
        
        submission.artist = music.artist
        submission.genres = music.genres
        submission.explicit = music.explicit
        submission.orderedRecording = music.orderedRecording
        submission.orderedProduction = music.orderedProduction
        submission.spotifyLink = music.spotifyLink
        submission.appleMusicLink = music.appleMusicLink
        submission.amazonMusicLink = music.amazonMusicLink
        submission.youtubeMusicLink = music.youtubeMusicLink
        submission.soundcloudLink = music.soundcloudLink
        submission.lyrics = music.lyrics
        submission.musicCategory = music.category
        submission.releaseYear = music.releaseYear
        submission.audioFileName = music.audioFileName
        submission.musicTrackFileNames = music.trackFileNames.isEmpty ? nil : music.trackFileNames
        // Carry the audio length in the shared `videoDuration` cache so the feed's
        // duration badge shows for music the same way it does for film.
        submission.videoDuration = music.audioDuration

        return submission
    }
    
    private func convertReelToSubmission(_ reel: Reel) -> Submission {
        var submission = Submission(
            id: reel.id,
            type: .reel,
            title: reel.title,
            details: reel.details
        )
        submission.isApproved = reel.isApproved
        submission.submittedBy = reel.submittedBy
        submission.createdDate = reel.createdDate
        submission.lastEditedDate = reel.lastEditedDate
        submission.schoolID = reel.schoolID
        
        // Convert thumbnailFileName to thumbnailData if needed
        if let thumbnailURL = reel.thumbnailURL,
           let thumbnailData = try? Data(contentsOf: thumbnailURL) {
            submission.thumbnailData = thumbnailData
        }
        
        submission.reelType = reel.reelType
        submission.reelDescription = reel.reelDescription
        submission.orderedCast = reel.orderedCast
        submission.orderedCrew = reel.orderedCrew
        submission.videoFileName = reel.videoFileName
        submission.videoDuration = reel.videoDuration
        submission.videoCrop = reel.videoCrop
        submission.featuredWorkIDs = reel.featuredWorkIDs
        submission.featuredWorkManual = reel.featuredWorkManual
        submission.artist = reel.artist
        submission.releaseYear = reel.releaseYear
        submission.stillImageFileNames = reel.stillImageFileNames

        return submission
    }
    
    private func convertPhotographyToSubmission(_ photography: Photography) -> Submission {
        var submission = Submission(
            id: photography.id,
            type: .photography,
            title: photography.title,
            details: photography.details
        )
        submission.isApproved = photography.isApproved
        submission.submittedBy = photography.submittedBy
        submission.createdDate = photography.createdDate
        submission.lastEditedDate = photography.lastEditedDate
        submission.schoolID = photography.schoolID

        // Convert thumbnailFileName to thumbnailData if needed
        if let thumbnailURL = photography.thumbnailURL,
           let thumbnailData = try? Data(contentsOf: thumbnailURL) {
            submission.thumbnailData = thumbnailData
        }

        submission.artist = photography.artist
        submission.releaseYear = photography.releaseYear
        submission.photoImageFileNames = photography.photoImageFileNames
        submission.equipment = photography.equipment
        submission.orderedCrew = photography.orderedCrew

        return submission
    }

    private func convertDesignToSubmission(_ design: Design) -> Submission {
        var submission = Submission(
            id: design.id,
            type: .design,
            title: design.title,
            details: design.details
        )
        submission.isApproved = design.isApproved
        submission.submittedBy = design.submittedBy
        submission.createdDate = design.createdDate
        submission.lastEditedDate = design.lastEditedDate
        submission.schoolID = design.schoolID

        // Convert thumbnailFileName to thumbnailData if needed
        if let thumbnailURL = design.thumbnailURL,
           let thumbnailData = try? Data(contentsOf: thumbnailURL) {
            submission.thumbnailData = thumbnailData
        }

        submission.designCategory = design.category
        submission.releaseYear = design.releaseYear
        submission.designImageFileNames = design.imageFileNames
        submission.videoFileName = design.videoFileName
        submission.videoDuration = design.videoDuration
        submission.videoCrop = design.videoCrop
        submission.orderedCrew = design.orderedCrew

        return submission
    }

    private func convertProjectToSubmission(_ project: Project) -> Submission {
        var submission = Submission(
            id: project.id,
            type: .project,
            title: project.title,
            details: project.details
        )
        submission.isApproved = project.isApproved
        submission.submittedBy = project.submittedBy
        submission.createdDate = project.createdDate
        submission.lastEditedDate = project.lastEditedDate
        submission.schoolID = project.schoolID
        
        // Convert thumbnailFileName to thumbnailData if needed
        if let thumbnailURL = project.thumbnailURL,
           let thumbnailData = try? Data(contentsOf: thumbnailURL) {
            submission.thumbnailData = thumbnailData
        }
        
        // Projects persist their description in `details` (projectDescription), but the
        // UI reads `logline` — bridge it back so the saved description shows on reload.
        submission.logline = project.details
        submission.shootDates = project.shootDates
        submission.expectedReleaseDate = project.expectedReleaseDate
        submission.genres = project.genres
        submission.castNeeded = project.castNeeded
        submission.crewNeeded = project.crewNeeded
        // Assembled cast/crew live in `orderedCast`/`orderedCrew` in the app; the Project
        // model calls them `castAssembled`/`crewAssembled`. Bridge them so they survive.
        submission.orderedCast = project.castAssembled
        submission.orderedCrew = project.crewAssembled
        // Nil rather than an empty array for a project with no slides, so the detail
        // view falls back to the plain poster (see `Submission.projectSlideFileNames`).
        submission.projectSlideFileNames = project.slideImageFileNames.isEmpty ? nil : project.slideImageFileNames
        submission.projectAuditionURL = project.auditionURL.isEmpty ? nil : project.auditionURL
        submission.projectContacts = project.contacts.isEmpty ? nil : project.contacts
        submission.studio = project.studio

        return submission
    }

    private func convertEventToSubmission(_ event: Event) -> Submission {
        var submission = Submission(
            id: event.id,
            type: .event,
            title: event.title,
            details: event.details
        )
        submission.isApproved = event.isApproved
        submission.submittedBy = event.submittedBy
        submission.createdDate = event.createdDate
        submission.lastEditedDate = event.lastEditedDate
        submission.schoolID = event.schoolID
        
        // Convert thumbnailFileName to thumbnailData if needed
        if let thumbnailURL = event.thumbnailURL,
           let thumbnailData = try? Data(contentsOf: thumbnailURL) {
            submission.thumbnailData = thumbnailData
        }
        
        // The event's description is authored into `logline` throughout the app, but the
        // Event model carries it in `details`. Restore it so the feed/detail can show it.
        submission.logline = event.details
        submission.eventStartDate = event.eventStartDate
        submission.eventEndDate = event.eventEndDate
        submission.eventLocation = event.eventLocation
        submission.eventHost = event.eventHost
        submission.eventTicketsURL = event.ticketsURL
        submission.eventExpectations = event.eventExpectations
        submission.eventApplicationURL = event.eventApplicationURL
        submission.eventRSVPURL = event.eventRSVPURL
        submission.eventWebsiteURL = event.eventWebsiteURL
        submission.eventLineup = event.eventLineup
        submission.eventShowings = event.eventShowings.isEmpty ? nil : event.eventShowings
        // Category is stored in the submission's `genres` throughout the app.
        submission.genres = event.eventCategory.isEmpty ? [] : [event.eventCategory]

        return submission
    }
    
    // MARK: - Conversion from Submission to Media Types
    
    private func convertSubmissionToFilm(_ submission: Submission) -> Film {
        var film = Film(
            id: submission.id,
            title: submission.title,
            details: submission.details,
            isApproved: submission.isApproved,
            submittedBy: submission.submittedBy,
            createdDate: submission.createdDate,
            lastEditedDate: submission.lastEditedDate,
            thumbnailFileName: nil,  // Will be set below if thumbnailData exists
            logline: submission.logline,
            ageRating: submission.ageRating,
            genres: submission.genres,
            explicit: submission.explicit,
            orderedCast: submission.orderedCast,
            orderedCrew: submission.orderedCrew,
            studio: submission.studio,
            videoFileName: submission.videoFileName,
            videoDuration: submission.videoDuration
        )
        film.festivalBound = submission.festivalBound
        film.trailerFileName = submission.trailerFileName
        film.btsImageFileNames = submission.btsImageFileNames
        film.stillImageFileNames = submission.stillImageFileNames
        film.releaseYear = submission.releaseYear
        film.videoCrop = submission.videoCrop

        // Convert thumbnailData to thumbnailFileName if needed
        if let thumbnailData = submission.thumbnailData,
           let documentsDir = FileManager.default.documentsDirectory {
            let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
            
            let thumbnailFileName = "\(submission.id.uuidString)_thumb.jpg"
            let thumbnailURL = thumbnailsDir.appendingPathComponent(thumbnailFileName)
            
            do {
                try? FileManager.default.removeItem(at: thumbnailURL)
                try thumbnailData.write(to: thumbnailURL)
                film.thumbnailFileName = thumbnailFileName
            } catch {
                print("❌ Failed to save thumbnail: \(error)")
            }
        }
        
        return film
    }
    
    private func convertSubmissionToMusic(_ submission: Submission) -> Music {
        var music = Music(
            id: submission.id,
            title: submission.title,
            details: submission.details,
            isApproved: submission.isApproved,
            submittedBy: submission.submittedBy,
            createdDate: submission.createdDate,
            lastEditedDate: submission.lastEditedDate,
            thumbnailFileName: nil,  // Will be set below if thumbnailData exists
            artist: submission.artist,
            genres: submission.genres,
            explicit: submission.explicit,
            orderedRecording: submission.orderedRecording,
            orderedProduction: submission.orderedProduction,
            spotifyLink: submission.spotifyLink,
            appleMusicLink: submission.appleMusicLink,
            amazonMusicLink: submission.amazonMusicLink,
            youtubeMusicLink: submission.youtubeMusicLink,
            soundcloudLink: submission.soundcloudLink,
            lyrics: submission.lyrics,
            audioFileName: submission.audioFileName
        )
        music.category = submission.musicCategory
        music.releaseYear = submission.releaseYear
        music.trackFileNames = submission.musicTrackFileNames ?? []
        // Bridge the audio length back from the shared `videoDuration` cache.
        music.audioDuration = submission.videoDuration

        // Convert thumbnailData to thumbnailFileName if needed
        if let thumbnailData = submission.thumbnailData,
           let documentsDir = FileManager.default.documentsDirectory {
            let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)

            let thumbnailFileName = "\(submission.id.uuidString)_cover.jpg"
            let thumbnailURL = thumbnailsDir.appendingPathComponent(thumbnailFileName)
            
            do {
                try? FileManager.default.removeItem(at: thumbnailURL)
                try thumbnailData.write(to: thumbnailURL)
                music.thumbnailFileName = thumbnailFileName
            } catch {
                print("❌ Failed to save music cover: \(error)")
            }
        }
        
        return music
    }
    
    private func convertSubmissionToReel(_ submission: Submission) -> Reel {
        var reel = Reel(
            id: submission.id,
            title: submission.title,
            details: submission.details,
            isApproved: submission.isApproved,
            submittedBy: submission.submittedBy,
            createdDate: submission.createdDate,
            lastEditedDate: submission.lastEditedDate,
            thumbnailFileName: nil,  // Will be set below if thumbnailData exists
            reelType: submission.reelType,
            reelDescription: submission.reelDescription,
            orderedCrew: submission.orderedCrew,
            videoFileName: submission.videoFileName
        )
        reel.featuredWorkIDs = submission.featuredWorkIDs
        reel.featuredWorkManual = submission.featuredWorkManual
        reel.artist = submission.artist
        reel.releaseYear = submission.releaseYear
        reel.stillImageFileNames = submission.stillImageFileNames
        reel.orderedCast = submission.orderedCast
        reel.videoDuration = submission.videoDuration
        reel.videoCrop = submission.videoCrop

        // Convert thumbnailData to thumbnailFileName if needed
        if let thumbnailData = submission.thumbnailData,
           let documentsDir = FileManager.default.documentsDirectory {
            let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
            
            let thumbnailFileName = "\(submission.id.uuidString)_thumb.jpg"
            let thumbnailURL = thumbnailsDir.appendingPathComponent(thumbnailFileName)
            
            do {
                try? FileManager.default.removeItem(at: thumbnailURL)
                try thumbnailData.write(to: thumbnailURL)
                reel.thumbnailFileName = thumbnailFileName
            } catch {
                print("❌ Failed to save reel thumbnail: \(error)")
            }
        }
        
        return reel
    }
    
    private func convertSubmissionToPhotography(_ submission: Submission) -> Photography {
        var photography = Photography(
            id: submission.id,
            title: submission.title,
            details: submission.details,
            isApproved: submission.isApproved,
            submittedBy: submission.submittedBy,
            createdDate: submission.createdDate,
            lastEditedDate: submission.lastEditedDate,
            thumbnailFileName: nil  // Will be set below if thumbnailData exists
        )
        photography.artist = submission.artist
        photography.releaseYear = submission.releaseYear
        photography.photoImageFileNames = submission.photoImageFileNames
        photography.equipment = submission.equipment
        photography.orderedCrew = submission.orderedCrew

        // Convert thumbnailData to thumbnailFileName if needed
        if let thumbnailData = submission.thumbnailData,
           let documentsDir = FileManager.default.documentsDirectory {
            let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)

            let thumbnailFileName = "\(submission.id.uuidString)_thumb.jpg"
            let thumbnailURL = thumbnailsDir.appendingPathComponent(thumbnailFileName)

            do {
                try? FileManager.default.removeItem(at: thumbnailURL)
                try thumbnailData.write(to: thumbnailURL)
                photography.thumbnailFileName = thumbnailFileName
            } catch {
                print("❌ Failed to save photography thumbnail: \(error)")
            }
        }

        return photography
    }

    private func convertSubmissionToDesign(_ submission: Submission) -> Design {
        var design = Design(
            id: submission.id,
            title: submission.title,
            details: submission.details,
            isApproved: submission.isApproved,
            submittedBy: submission.submittedBy,
            createdDate: submission.createdDate,
            lastEditedDate: submission.lastEditedDate,
            thumbnailFileName: nil  // Will be set below if thumbnailData exists
        )
        design.category = submission.designCategory
        design.releaseYear = submission.releaseYear
        design.imageFileNames = submission.designImageFileNames
        design.videoFileName = submission.videoFileName
        design.videoDuration = submission.videoDuration
        design.videoCrop = submission.videoCrop
        design.orderedCrew = submission.orderedCrew

        // Convert thumbnailData to thumbnailFileName if needed
        if let thumbnailData = submission.thumbnailData,
           let documentsDir = FileManager.default.documentsDirectory {
            let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)

            let thumbnailFileName = "\(submission.id.uuidString)_thumb.jpg"
            let thumbnailURL = thumbnailsDir.appendingPathComponent(thumbnailFileName)

            do {
                try? FileManager.default.removeItem(at: thumbnailURL)
                try thumbnailData.write(to: thumbnailURL)
                design.thumbnailFileName = thumbnailFileName
            } catch {
                print("❌ Failed to save design thumbnail: \(error)")
            }
        }

        return design
    }

    private func convertSubmissionToProject(_ submission: Submission) -> Project {
        var project = Project(
            id: submission.id,
            // Projects store their description in `logline` in-memory (that's what the
            // card/edit form use), but the persisted/CloudKit field is `details`
            // (projectDescription). Bridge them so edits survive a reload.
            title: submission.title,
            details: submission.logline,
            isApproved: submission.isApproved,
            submittedBy: submission.submittedBy,
            createdDate: submission.createdDate,
            lastEditedDate: submission.lastEditedDate,
            thumbnailFileName: nil,  // Will be set below if thumbnailData exists
            shootDates: submission.shootDates,
            expectedReleaseDate: submission.expectedReleaseDate,
            genres: submission.genres,
            castNeeded: submission.castNeeded,
            crewNeeded: submission.crewNeeded
        )
        // Carry the assembled team through so edits (and creation) persist. Without this
        // the `.allKeys` save writes empty arrays and wipes them on the server.
        project.castAssembled = submission.orderedCast
        project.crewAssembled = submission.orderedCrew
        project.slideImageFileNames = submission.projectSlideFileNames ?? []
        project.auditionURL = submission.projectAuditionURL ?? ""
        project.contacts = submission.projectContacts ?? []
        project.studio = submission.studio

        // Convert thumbnailData to thumbnailFileName if needed
        if let thumbnailData = submission.thumbnailData,
           let documentsDir = FileManager.default.documentsDirectory {
            let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)

            let thumbnailFileName = "\(submission.id.uuidString)_poster.jpg"
            let thumbnailURL = thumbnailsDir.appendingPathComponent(thumbnailFileName)
            
            do {
                try? FileManager.default.removeItem(at: thumbnailURL)
                try thumbnailData.write(to: thumbnailURL)
                project.thumbnailFileName = thumbnailFileName
            } catch {
                print("❌ Failed to save project poster: \(error)")
            }
        }
        
        return project
    }
    
    private func convertSubmissionToEvent(_ submission: Submission) -> Event {
        var event = Event(
            id: submission.id,
            title: submission.title,
            // The event description lives in `logline`; fall back to `details` for safety.
            details: submission.logline.isEmpty ? submission.details : submission.logline,
            isApproved: submission.isApproved,
            submittedBy: submission.submittedBy,
            createdDate: submission.createdDate,
            lastEditedDate: submission.lastEditedDate,
            thumbnailFileName: nil,  // Will be set below if thumbnailData exists
            eventStartDate: submission.eventStartDate,
            eventEndDate: submission.eventEndDate,
            eventLocation: submission.eventLocation,
            eventHost: submission.eventHost,
            ticketsURL: submission.eventTicketsURL
        )
        // Category is authored into the submission's `genres`.
        event.eventCategory = submission.genres.first ?? ""
        event.eventExpectations = submission.eventExpectations
        event.eventApplicationURL = submission.eventApplicationURL
        event.eventRSVPURL = submission.eventRSVPURL
        event.eventWebsiteURL = submission.eventWebsiteURL
        event.eventLineup = submission.eventLineup
        event.eventShowings = submission.eventShowings ?? []

        // Convert thumbnailData to thumbnailFileName if needed
        if let thumbnailData = submission.thumbnailData,
           let documentsDir = FileManager.default.documentsDirectory {
            let thumbnailsDir = documentsDir.appendingPathComponent("thumbnails")
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
            
            let thumbnailFileName = "\(submission.id.uuidString)_flyer.jpg"
            let thumbnailURL = thumbnailsDir.appendingPathComponent(thumbnailFileName)
            
            do {
                try? FileManager.default.removeItem(at: thumbnailURL)
                try thumbnailData.write(to: thumbnailURL)
                event.thumbnailFileName = thumbnailFileName
            } catch {
                print("❌ Failed to save event flyer: \(error)")
            }
        }
        
        return event
    }
}
