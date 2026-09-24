//
//  PlaceholderData.swift
//  Longhorn Artists Connect
//
//  Created for UI development and testing
//  Contains comprehensive placeholder data for all post types
//

import SwiftUI

extension Submission {

    // MARK: - Placeholder Identification

    /// The fixed record IDs used by the placeholder posts that shipped in an early
    /// build. They were accidentally uploaded to the public CloudKit database, so
    /// the app permanently filters them out (and can purge them) by these IDs.
    static let placeholderIDs: Set<UUID> = Set((1...5).compactMap {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))
    })

    /// Whether this submission is one of the legacy placeholder posts.
    var isPlaceholder: Bool { Submission.placeholderIDs.contains(id) }

    /// Filename for the sample script attached to the Sunset Boulevard placeholder.
    static let sunsetScriptFileName = "placeholder_sunset_boulevard_script.pdf"

    /// Writes a small sample screenplay PDF into the documents directory (used by the
    /// Sunset Boulevard placeholder) so its "Read Script" button appears and opens.
    static func ensurePlaceholderScriptExists() {
        guard let documentsDir = FileManager.default.documentsDirectory else { return }
        let url = documentsDir.appendingPathComponent(sunsetScriptFileName)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }

        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @ 72dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { context in
            context.beginPage()

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22)
            ]
            "SUNSET BOULEVARD".draw(at: CGPoint(x: 72, y: 72), withAttributes: titleAttributes)

            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Courier", size: 13) ?? UIFont.systemFont(ofSize: 13)
            ]
            let body = """
            Written by Casey Anderson

            FADE IN:

            INT. DOWNTOWN AUSTIN ART GALLERY - NIGHT

            Rain streaks the tall windows. DETECTIVE RAY MERCER (30s)
            studies an empty frame where a painting used to hang.

            RAY
            Third heist this month. Same signature,
            same empty frame. Somebody's telling a story.

            GALLERY OWNER
            Or covering one up.

            Ray turns, catching his reflection in the glass.

            RAY (V.O.)
            In this city, every canvas hides a confession.
            You just have to know where to look.

            CUT TO:

            EXT. CONGRESS AVENUE - CONTINUOUS

            Neon smears across wet pavement as Ray steps into the night.

            FADE OUT.
            """
            let bodyRect = CGRect(x: 72, y: 120, width: 468, height: 620)
            body.draw(in: bodyRect, withAttributes: bodyAttributes)
        }

        do {
            try data.write(to: url)
        } catch {
            print("⚠️ Failed to write placeholder script: \(error.localizedDescription)")
        }
    }

    // MARK: - Film Placeholder
    
    static let placeholderFilmV2 = Submission(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        type: .film,
        title: "The Midnight Garden",
        details: """
        type: Film
        logline: A botanist discovers her grandmother's garden holds the key to communicating with parallel dimensions, but each visit costs her a memory from this world.
        ageRating: PG-13
        genres: Sci-Fi, Drama, Mystery
        cast:
        Director of Photography - Sarah Chen
        Lead Actress - Emma Rodriguez
        Supporting Actor - James Mitchell
        crew:
        Director - Alex Thompson
        Producer - Marcus Williams
        Cinematographer - Sarah Chen
        Editor - Rachel Park
        Sound Designer - David Kim
        studio: Moonlight Pictures
        explicit: false
        """,
        isApproved: true,
        submittedBy: "Alex Thompson",
        createdDate: Date().addingTimeInterval(-60*60*24*14), // 14 days ago
        lastEditedDate: nil,
        logline: "A botanist discovers her grandmother's garden holds the key to communicating with parallel dimensions, but each visit costs her a memory from this world.",
        ageRating: "PG-13",
        genres: ["Sci-Fi", "Drama", "Mystery"],
        cast: [:], // Using ordered arrays instead
        crew: [:], // Using ordered arrays instead
        orderedCast: [
            OrderedEntry(role: "Lead Actress", name: "Emma Rodriguez"),
            OrderedEntry(role: "Supporting Actor", name: "James Mitchell"),
            OrderedEntry(role: "Supporting Actress", name: "Maya Patel")
        ],
        orderedCrew: [
            OrderedEntry(role: "Director", name: "Alex Thompson"),
            OrderedEntry(role: "Producer", name: "Marcus Williams"),
            OrderedEntry(role: "Director of Photography", name: "Sarah Chen"),
            OrderedEntry(role: "Editor", name: "Rachel Park"),
            OrderedEntry(role: "Sound Designer", name: "David Kim"),
            OrderedEntry(role: "Production Designer", name: "Lisa Chang")
        ],
        explicit: false,
        videoFileName: nil, // Set to actual video file if available
        audioFileName: nil,
        thumbnailData: nil, // Set to actual image data if available
        scriptFileName: nil,
        eventStartDate: nil,
        eventEndDate: nil,
        eventLocation: nil,
        eventHost: "",
        eventTicketsURL: nil,
        shootDates: "",
        expectedReleaseDate: "",
        castNeeded: [],
        crewNeeded: [],
        studio: "Moonlight Pictures",
        artist: "",
        musicians: "",
        writers: "",
        mixers: "",
        orderedRecording: [],
        orderedProduction: [],
        spotifyLink: "",
        appleMusicLink: "",
        amazonMusicLink: "",
        youtubeMusicLink: "",
        soundcloudLink: "",
        reelType: "",
        reelDescription: "",
        reelExperience: "",
        reelSpecificSkills: ""
    )
    
    // MARK: - Music Placeholder
    
    static let placeholderMusicV2 = Submission(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        type: .music,
        title: "Neon Dreams",
        details: """
        type: Music
        artist: The Velvet Echoes
        logline: An atmospheric synthwave journey through memories of a city that never sleeps, blending nostalgic 80s sounds with modern production.
        genres: Synthwave, Electronic, Indie
        explicit: false
        orderedRecording:
        Vocals - Jordan Lee
        Synthesizers - Alex Rivera
        Bass - Sam Torres
        Drums - Casey Morgan
        orderedProduction:
        Producer - Alex Rivera
        Mix Engineer - Taylor Kim
        Mastering Engineer - Chris Anderson
        spotifyLink: https://open.spotify.com/track/example
        appleMusicLink: https://music.apple.com/us/album/example
        youtubeMusicLink: https://music.youtube.com/watch?v=example
        soundcloudLink: https://soundcloud.com/example
        """,
        isApproved: true,
        submittedBy: "Jordan Lee",
        createdDate: Date().addingTimeInterval(-60*60*24*7), // 7 days ago
        lastEditedDate: nil,
        logline: "An atmospheric synthwave journey through memories of a city that never sleeps, blending nostalgic 80s sounds with modern production.",
        ageRating: "",
        genres: ["Synthwave", "Electronic", "Indie"],
        cast: [:],
        crew: [:],
        orderedCast: [],
        orderedCrew: [],
        explicit: false,
        videoFileName: nil,
        audioFileName: nil, // Set to actual audio file if available
        thumbnailData: nil, // Set to album artwork if available
        scriptFileName: nil,
        eventStartDate: nil,
        eventEndDate: nil,
        eventLocation: nil,
        eventHost: "",
        eventTicketsURL: nil,
        shootDates: "",
        expectedReleaseDate: "",
        castNeeded: [],
        crewNeeded: [],
        studio: "",
        artist: "The Velvet Echoes",
        musicians: "",
        writers: "",
        mixers: "",
        orderedRecording: [
            OrderedEntry(role: "Vocals", name: "Jordan Lee"),
            OrderedEntry(role: "Synthesizers", name: "Alex Rivera"),
            OrderedEntry(role: "Bass", name: "Sam Torres"),
            OrderedEntry(role: "Drums", name: "Casey Morgan"),
            OrderedEntry(role: "Guitar", name: "Riley Chen")
        ],
        orderedProduction: [
            OrderedEntry(role: "Producer", name: "Alex Rivera"),
            OrderedEntry(role: "Mix Engineer", name: "Taylor Kim"),
            OrderedEntry(role: "Mastering Engineer", name: "Chris Anderson"),
            OrderedEntry(role: "Recording Engineer", name: "Jamie Walsh")
        ],
        spotifyLink: "https://open.spotify.com/track/example",
        appleMusicLink: "https://music.apple.com/us/album/example",
        amazonMusicLink: "https://music.amazon.com/albums/example",
        youtubeMusicLink: "https://music.youtube.com/watch?v=example",
        soundcloudLink: "https://soundcloud.com/example",
        reelType: "",
        reelDescription: "",
        reelExperience: "",
        reelSpecificSkills: ""
    )
    
    // MARK: - Reel (Talent) Placeholder
    
    static let placeholderReelV2 = Submission(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        type: .reel,
        title: "Morgan Taylor - Acting Reel 2026",
        details: """
        type: Reel
        reelType: Acting
        logline: Versatile actor with range from comedy to intense drama. Trained at UT Austin's Department of Theatre & Dance with focus on method acting and character development.
        reelExperience: 5+ years professional experience including lead roles in independent films, theater productions, and commercial work. Recent credits include 'The Last Summer' (Lead), 'Downtown Dreams' (Supporting), and 'Coffee Shop Chronicles' (Ensemble).
        reelSpecificSkills: Stage Combat (SCA Certified), Dialects (British RP, Southern, New York), Improvisation, Classical Training, Voice Acting, Physical Theater
        orderedCrew:
        Lead Actor - The Last Summer
        Supporting Actor - Downtown Dreams
        Ensemble - Coffee Shop Chronicles
        """,
        isApproved: true,
        submittedBy: "Morgan Taylor",
        createdDate: Date().addingTimeInterval(-60*60*24*3), // 3 days ago
        lastEditedDate: nil,
        logline: "Versatile actor with range from comedy to intense drama. Trained at UT Austin's Department of Theatre & Dance with focus on method acting and character development.",
        ageRating: "",
        genres: [],
        cast: [:],
        crew: [:],
        orderedCast: [],
        orderedCrew: [
            OrderedEntry(role: "Lead Actor", name: "The Last Summer"),
            OrderedEntry(role: "Supporting Actor", name: "Downtown Dreams"),
            OrderedEntry(role: "Ensemble", name: "Coffee Shop Chronicles"),
            OrderedEntry(role: "Lead", name: "Austin Shakespeare Festival"),
            OrderedEntry(role: "Featured", name: "Dell Commercial 2025")
        ],
        explicit: false,
        videoFileName: nil, // Set to reel video if available
        audioFileName: nil,
        thumbnailData: nil, // Set to headshot if available
        scriptFileName: nil,
        eventStartDate: nil,
        eventEndDate: nil,
        eventLocation: nil,
        eventHost: "",
        eventTicketsURL: nil,
        shootDates: "",
        expectedReleaseDate: "",
        castNeeded: [],
        crewNeeded: [],
        studio: "",
        artist: "",
        musicians: "",
        writers: "",
        mixers: "",
        orderedRecording: [],
        orderedProduction: [],
        spotifyLink: "",
        appleMusicLink: "",
        amazonMusicLink: "",
        youtubeMusicLink: "",
        soundcloudLink: "",
        reelType: "Acting",
        reelDescription: "",
        reelExperience: "5+ years professional experience including lead roles in independent films, theater productions, and commercial work. Recent credits include 'The Last Summer' (Lead), 'Downtown Dreams' (Supporting), and 'Coffee Shop Chronicles' (Ensemble).",
        reelSpecificSkills: "Stage Combat (SCA Certified), Dialects (British RP, Southern, New York), Improvisation, Classical Training, Voice Acting, Physical Theater"
    )
    
    // MARK: - Project Placeholder
    
    static let placeholderProjectV2 = Submission(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        type: .project,
        title: "Sunset Boulevard",
        details: """
        type: Project
        logline: A neo-noir thriller about a detective who uncovers a conspiracy while investigating a series of art heists in downtown Austin.
        genres: Thriller, Mystery, Crime
        shootDates: June 15, 2026 - July 20, 2026
        expectedReleaseDate: Fall 2026
        castNeeded:
        Lead Detective (Male, 30-40)
        Art Gallery Owner (Female, 40-50)
        Mysterious Informant (Any, 25-35)
        crewNeeded:
        Director of Photography
        Gaffer
        Key Grip
        Sound Mixer
        Production Assistant
        orderedCrew:
        Director - Jamie Martinez
        Producer - Sam Rodriguez
        Writer - Casey Anderson
        """,
        isApproved: true,
        submittedBy: "Jamie Martinez",
        createdDate: Date().addingTimeInterval(-60*60*24*5), // 5 days ago
        lastEditedDate: nil,
        logline: "A neo-noir thriller about a detective who uncovers a conspiracy while investigating a series of art heists in downtown Austin.",
        ageRating: "",
        genres: ["Thriller", "Mystery", "Crime"],
        cast: [:],
        crew: [:],
        orderedCast: [],
        orderedCrew: [
            OrderedEntry(role: "Director", name: "Jamie Martinez"),
            OrderedEntry(role: "Producer", name: "Sam Rodriguez"),
            OrderedEntry(role: "Writer", name: "Casey Anderson"),
            OrderedEntry(role: "Production Designer", name: "Taylor Brooks")
        ],
        explicit: false,
        videoFileName: nil,
        audioFileName: nil,
        thumbnailData: nil, // Set to project poster/concept art if available
        scriptFileName: Submission.sunsetScriptFileName, // Generated sample PDF (see ensurePlaceholderScriptExists)
        eventStartDate: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15)), // Shoot start date
        eventEndDate: Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 20)), // Shoot end date
        eventLocation: nil,
        eventHost: "",
        eventTicketsURL: nil,
        shootDates: "June 15, 2026 - July 20, 2026",
        expectedReleaseDate: "Fall 2026",
        castNeeded: [
            "Lead Detective (Male, 30-40)",
            "Art Gallery Owner (Female, 40-50)",
            "Mysterious Informant (Any, 25-35)",
            "Police Chief (Any, 45-55)"
        ],
        crewNeeded: [
            "Director of Photography",
            "Gaffer",
            "Key Grip",
            "Sound Mixer",
            "Production Assistant",
            "Script Supervisor"
        ],
        studio: "",
        artist: "",
        musicians: "",
        writers: "",
        mixers: "",
        orderedRecording: [],
        orderedProduction: [],
        spotifyLink: "",
        appleMusicLink: "",
        amazonMusicLink: "",
        youtubeMusicLink: "",
        soundcloudLink: "",
        reelType: "",
        reelDescription: "",
        reelExperience: "",
        reelSpecificSkills: ""
    )
    
    // MARK: - Event Placeholder
    
    static let placeholderEventV2 = Submission(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        type: .event,
        title: "Austin Film Festival: Student Showcase",
        details: """
        type: Event
        eventHost: Austin Film Society
        logline: Join us for an evening celebrating student filmmakers from across Texas. Featuring 10 short films, Q&A with directors, and networking reception with industry professionals.
        eventStartDate: 2026-06-20T19:00:00Z
        eventEndDate: 2026-06-20T22:30:00Z
        eventLocation: The Paramount Theatre, 713 Congress Ave, Austin, TX 78701
        eventTicketsURL: https://austinfilmfestival.com/tickets/student-showcase
        """,
        isApproved: true,
        submittedBy: "Austin Film Society",
        createdDate: Date().addingTimeInterval(-60*60*24*10), // 10 days ago
        lastEditedDate: nil,
        logline: "Join us for an evening celebrating student filmmakers from across Texas. Featuring 10 short films, Q&A with directors, and networking reception with industry professionals.",
        ageRating: "",
        genres: [],
        cast: [:],
        crew: [:],
        orderedCast: [],
        orderedCrew: [],
        explicit: false,
        videoFileName: nil,
        audioFileName: nil,
        thumbnailData: nil, // Set to event poster if available
        scriptFileName: nil,
        eventStartDate: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 19, minute: 0)),
        eventEndDate: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 22, minute: 30)),
        eventLocation: "The Paramount Theatre, 713 Congress Ave, Austin, TX 78701",
        eventHost: "Austin Film Society",
        eventTicketsURL: "https://austinfilmfestival.com/tickets/student-showcase",
        shootDates: "",
        expectedReleaseDate: "",
        castNeeded: [],
        crewNeeded: [],
        studio: "",
        artist: "",
        musicians: "",
        writers: "",
        mixers: "",
        orderedRecording: [],
        orderedProduction: [],
        spotifyLink: "",
        appleMusicLink: "",
        amazonMusicLink: "",
        youtubeMusicLink: "",
        soundcloudLink: "",
        reelType: "",
        reelDescription: "",
        reelExperience: "",
        reelSpecificSkills: ""
    )
    
    // MARK: - All Placeholders Array
    
    static let allPlaceholdersV2: [Submission] = [
        placeholderFilmV2,
        placeholderMusicV2,
        placeholderReelV2,
        placeholderProjectV2,
        placeholderEventV2
    ]
    
    // MARK: - Load Placeholders into Store
    
    /// Loads all placeholder data into the submission store
    /// This is called automatically on app launch to provide sample content for all users
    /// Uses stable UUIDs to prevent duplicates across app restarts
    static func loadPlaceholdersV2(into store: SubmissionStore_3_2) {
        print("📝 Loading placeholder data...")

        // Make sure the Sunset Boulevard sample script exists on disk.
        ensurePlaceholderScriptExists()
        
        // Check if placeholders are already loaded to avoid duplicates
        let existingIDs = Set(store.approvedSubmissions.map { $0.id })
        let placeholdersToAdd = allPlaceholdersV2.filter { !existingIDs.contains($0.id) }
        
        if placeholdersToAdd.isEmpty {
            print("✅ Placeholders already loaded (\(allPlaceholdersV2.count) items)")
            return
        }
        
        // Add only new placeholders
        store.approvedSubmissions.append(contentsOf: placeholdersToAdd)
        
        print("✅ Loaded \(placeholdersToAdd.count) placeholder submissions:")
        for submission in placeholdersToAdd {
            print("   - \(submission.type.rawValue): \(submission.title)")
        }
    }
}

// MARK: - Preview Helper

#if DEBUG
extension SubmissionStore_3_2 {
    static var preview: SubmissionStore_3_2 {
        let store = SubmissionStore_3_2.shared
        
        // Clear existing submissions for clean preview
        store.submissions = Submission.allPlaceholdersV2
        
        return store
    }
}
#endif
