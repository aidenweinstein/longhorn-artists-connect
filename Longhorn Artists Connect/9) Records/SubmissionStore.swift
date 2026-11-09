import Combine
import SwiftUI
import CloudKit

// MARK: - MediaType Definition

enum MediaType: String, Codable, CaseIterable, Identifiable {
    case reel = "Reel"
    case project = "Project"
    case event = "Event"
    case film = "Film"
    case music = "Music"
    case photography = "Photography"
    case design = "Design"

    var id: String { rawValue }

    /// The name shown to users. Matches `rawValue` for every type except `.reel`,
    /// which is presented as "Performance" while its stored/CloudKit value stays
    /// "Reel" so existing drafts and records keep decoding.
    var displayName: String {
        switch self {
        case .reel: return "Performance"
        default: return rawValue
        }
    }
}

// MARK: - Helper Structs

// Helper struct for ordered entries
struct OrderedEntry: Codable, Equatable, Identifiable {
    let id: UUID
    var role: String
    var name: String
    /// CloudKit record name of the credited person's profile, when they were
    /// picked from the directory. `nil` for free-typed names. Lets a credit link
    /// to the exact person even if two people share a name.
    var profileID: String?

    init(id: UUID = UUID(), role: String = "", name: String = "", profileID: String? = nil) {
        self.id = id
        self.role = role
        self.name = name
        self.profileID = profileID
    }
}

// Collection for saving posts
struct PostCollection: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var submissionIds: [UUID]
    let createdAt: Date
    var isSystemCollection: Bool // For "Liked" collection
    
    init(id: UUID = UUID(), name: String, submissionIds: [UUID] = [], createdAt: Date = Date(), isSystemCollection: Bool = false) {
        self.id = id
        self.name = name
        self.submissionIds = submissionIds
        self.createdAt = createdAt
        self.isSystemCollection = isSystemCollection
    }
}

// History entry for tracking edits and approvals
struct HistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let action: HistoryAction
    let timestamp: Date
    let submissionId: UUID
    let submissionTitle: String
    let submissionType: MediaType
    let performedBy: String
    
    init(id: UUID = UUID(), action: HistoryAction, timestamp: Date = Date(), submissionId: UUID, submissionTitle: String, submissionType: MediaType, performedBy: String) {
        self.id = id
        self.action = action
        self.timestamp = timestamp
        self.submissionId = submissionId
        self.submissionTitle = submissionTitle
        self.submissionType = submissionType
        self.performedBy = performedBy
    }
}

enum HistoryAction: String, Codable {
    case submitted = "Submitted"
    case approved = "Approved"
    case edited = "Edited"
    case denied = "Denied"
    case deleted = "Deleted"
}

// MARK: - Event Showing

/// One showing of a multi-showing event (Theatre Performance): a date with a start and
/// an end time. A run is a list of these, so a play performed four nights is one post
/// rather than four.
///
/// Identity is a stable UUID so the submission form can edit rows in place, but equality
/// deliberately ignores it: a showing that round-trips through CloudKit (which carries
/// only the two timestamps) has to compare equal to the one that was posted, otherwise
/// every sync would register as an edit.
struct EventShowing: Identifiable, Codable, Hashable {
    var id: UUID
    var start: Date
    var end: Date

    init(id: UUID = UUID(), start: Date, end: Date) {
        self.id = id
        self.start = start
        self.end = end
    }

    static func == (lhs: EventShowing, rhs: EventShowing) -> Bool {
        lhs.start == rhs.start && lhs.end == rhs.end
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(start)
        hasher.combine(end)
    }

    /// The calendar day this showing sits on. Setting it moves both timestamps onto that
    /// day while preserving each one's time, so the form's single "Date" picker and its
    /// two time pickers stay in sync (the same trick single-date events use).
    var day: Date {
        get { start }
        set {
            let calendar = Calendar.current
            let dayComponents = calendar.dateComponents([.year, .month, .day], from: newValue)
            func applyDay(to date: Date) -> Date {
                let time = calendar.dateComponents([.hour, .minute], from: date)
                var combined = dayComponents
                combined.hour = time.hour
                combined.minute = time.minute
                return calendar.date(from: combined) ?? date
            }
            start = applyDay(to: start)
            end = applyDay(to: end)
        }
    }

    // MARK: - CloudKit Wire Format

    /// Showings travel to CloudKit as a String list, one `"<start>|<end>"` entry per
    /// showing in ISO 8601. A pair of dates has no native CloudKit type, and two parallel
    /// DATE_TIME lists can drift out of step with each other, so each showing is kept
    /// whole in a single entry.
    private static let wireFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func wireEntries(from showings: [EventShowing]) -> [String] {
        showings.map { "\(wireFormatter.string(from: $0.start))|\(wireFormatter.string(from: $0.end))" }
    }

    static func showings(fromWireEntries entries: [String]) -> [EventShowing] {
        entries.compactMap { entry in
            let parts = entry.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let start = wireFormatter.date(from: String(parts[0])),
                  let end = wireFormatter.date(from: String(parts[1]))
            else { return nil }
            return EventShowing(start: start, end: end)
        }
        .sorted { $0.start < $1.start }
    }
}

// MARK: - Shoot Schedule (Cast & Crew Calls)

/// One day of a shoot in the submission form: its date and call time (`date`) and its
/// wrap time (`end`). Only `end`'s hour and minute matter — it's written onto `date`'s
/// day when the schedule is stored, so the two pickers can't drift apart.
struct ShootDay: Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var end: Date

    /// `end` defaults to eight hours after the call time, a typical shoot day.
    init(date: Date, end: Date? = nil) {
        self.date = date
        self.end = end ?? ShootDay.defaultEnd(for: date)
    }

    static func defaultEnd(for start: Date) -> Date {
        Calendar.current.date(byAdding: .hour, value: 8, to: start) ?? start
    }

    /// The calendar day this shoot day sits on. Setting it moves both the call time and
    /// the wrap time onto that day while preserving each one's time, so the form's single
    /// "Date" picker and its two time pickers stay in sync (mirrors `EventShowing.day`).
    var day: Date {
        get { date }
        set {
            let calendar = Calendar.current
            let dayComponents = calendar.dateComponents([.year, .month, .day], from: newValue)
            func applyDay(to value: Date) -> Date {
                let time = calendar.dateComponents([.hour, .minute], from: value)
                var combined = dayComponents
                combined.hour = time.hour
                combined.minute = time.minute
                return calendar.date(from: combined) ?? value
            }
            date = applyDay(to: date)
            end = applyDay(to: end)
        }
    }
}

/// A Cast & Crew Call's shoot schedule: specific days, each with a call time and a wrap
/// time.
///
/// It travels in the project's existing `shootDates` text (CloudKit
/// `projectShootDatesText`) as one "MMM d, yyyy h:mm a - h:mm a" entry per day joined
/// by " · ", e.g. "Jun 15, 2026 7:00 AM - 5:00 PM · Jun 16, 2026 8:30 AM - 6:00 PM".
/// Reusing that field means no CloudKit schema change, and the value stays readable on
/// app versions that display the text verbatim. Entries written before wrap times
/// existed ("Jun 15, 2026 7:00 AM") still parse, with no end; and posts older than the
/// day list wrote a "start - end" range of dates, which `parse` also understands.
enum ShootSchedule {
    /// One parsed shoot day: its call time and, when stored, its wrap time.
    struct Day: Hashable {
        let start: Date
        let end: Date?
    }

    enum Parsed {
        /// Specific shoot days, soonest first. Never empty.
        case days([Day])
        /// A legacy "start - end" range (dates only; `end` is nil for a single date).
        case range(start: Date, end: Date?)
    }

    private static let separator = " · "
    /// Separates a day's call time from its wrap time inside one entry.
    private static let timeSeparator = " - "

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy h:mm a"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    /// Every format a legacy range's dates were written in across app versions.
    private static let legacyFormats = ["MMM d, yyyy", "MMMM d, yyyy", "MM/dd/yyyy"]

    /// The stored text for `days` (soonest first). Empty when there are no days. Only
    /// the wrap time's hour and minute are kept; it's read back onto the call's day.
    static func text(from days: [ShootDay]) -> String {
        days.sorted { $0.date < $1.date }
            .map { dayFormatter.string(from: $0.date) + timeSeparator + timeFormatter.string(from: $0.end) }
            .joined(separator: separator)
    }

    /// Parses stored `shootDates` text — the day list, or a legacy range. `nil` when the
    /// text is empty or in no recognizable form (e.g. "Summer 2026" or "TBD").
    static func parse(_ text: String) -> Parsed? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let entries = trimmed.components(separatedBy: separator)
        let days = entries.compactMap(parseDay)
        if !days.isEmpty, days.count == entries.count {
            return .days(days.sorted { $0.start < $1.start })
        }

        let parts = trimmed.components(separatedBy: timeSeparator)
        guard let first = parts.first, let start = legacyDate(first) else { return nil }
        let end = parts.count > 1 ? legacyDate(parts[1]) : nil
        return .range(start: start, end: end)
    }

    /// One entry: "Jun 15, 2026 7:00 AM - 5:00 PM", or the older "Jun 15, 2026 7:00 AM".
    /// The wrap time is placed on the call's day. A legacy date range ("Jun 15, 2026 -
    /// Jul 20, 2026") fails here — its first half has no time — and falls through to the
    /// range parser in `parse`.
    private static func parseDay(_ entry: String) -> Day? {
        let parts = entry.components(separatedBy: timeSeparator)
        guard let first = parts.first,
              let start = dayFormatter.date(from: first.trimmingCharacters(in: .whitespaces))
        else { return nil }

        var end: Date?
        if parts.count > 1, let wrap = timeFormatter.date(from: parts[1].trimmingCharacters(in: .whitespaces)) {
            let calendar = Calendar.current
            let time = calendar.dateComponents([.hour, .minute], from: wrap)
            end = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: start)
        }
        return Day(start: start, end: end)
    }

    /// The first shoot day, which the legacy `projectShootStart` timestamp carries.
    static func firstDate(in text: String) -> Date? {
        switch parse(text) {
        case .days(let days)?: return days.first?.start
        case .range(let start, _)?: return start
        case nil: return nil
        }
    }

    /// One pre-built formatter per legacy format. `parse` runs inside feed sorts and
    /// card bodies, and building a `DateFormatter` costs on the order of a millisecond,
    /// so allocating them per call made the Discover feed stutter on every render.
    private static let legacyFormatters: [DateFormatter] = legacyFormats.map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    private static func legacyDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        for formatter in legacyFormatters {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    // MARK: Display

    private static let dayTextFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    private static let dayTextWithYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d, yyyy"
        return formatter
    }()

    private static let timeTextFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter
    }()

    /// "Mon, Jun 15" — with the year added when the day isn't in the current year.
    static func dayText(_ date: Date) -> String {
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        return (sameYear ? dayTextFormatter : dayTextWithYearFormatter).string(from: date)
    }

    /// "7:00am" — lowercase meridiem, no space, matching how event times are shown.
    static func timeText(_ date: Date) -> String {
        timeTextFormatter.string(from: date).lowercased()
    }

    /// "7:00am - 5:00pm" for a day with a wrap time, or just "7:00am" without one.
    static func timeRangeText(_ day: Day) -> String {
        guard let end = day.end else { return timeText(day.start) }
        return "\(timeText(day.start)) - \(timeText(end))"
    }
}

extension Submission {
    /// The project's shoot schedule, parsed from `shootDates` (see `ShootSchedule`).
    var shootSchedule: ShootSchedule.Parsed? { ShootSchedule.parse(shootDates) }
}

struct Submission: Identifiable, Equatable, Codable {
    let id: UUID
    let type: MediaType
    var title: String
    var details: String
    var isApproved: Bool = false
    var submittedBy: String = ""
    var createdDate: Date = Date()
    var lastEditedDate: Date?

    /// Registry slug of the school this post belongs to ("ut-austin", "berkeley").
    /// Nil on records that predate stamping — `SchoolScope.isVisible` treats those
    /// as UT Austin. Optional so the on-disk cache written before this field still
    /// decodes (see `eventShowings`).
    var schoolID: String?

    // Parsed fields for display
    var logline: String = ""
    var ageRating: String = ""
    var genres: [String] = []
    var cast: [String: String] = [:]
    var crew: [String: String] = [:]
    
    // Ordered arrays to preserve input order
    var orderedCast: [OrderedEntry] = []
    var orderedCrew: [OrderedEntry] = []
    
    var explicit: Bool = false

    /// Films only: when true the post is "festival-bound" and kept private — hidden from
    /// the public home feed / search, and shown only on the profile of a credited person
    /// or when sent directly to someone.
    var festivalBound: Bool = false

    // Media file names (not full URLs to survive app reinstalls)
    var videoFileName: String?
    var audioFileName: String?
    var thumbnailData: Data?
    var scriptFileName: String?

    /// Music EP/Album posts: the *additional* audio tracks beyond `audioFileName`, which
    /// stays track 1. In running order. Empty/nil for singles and performances.
    ///
    /// Optional, not a defaulted array, on purpose — for the same reason as
    /// `eventShowings`: the on-disk `[Submission]` cache is decoded with the synthesized
    /// `init(from:)`, which throws on a missing key for a non-optional property, and that
    /// would drop the whole cached feed on the first launch after this update.
    var musicTrackFileNames: [String]?

    // Film extras (all optional). Like `videoFileName`, these store deterministic file
    // names (not full URLs) so they survive reinstalls and resolve via `mediaFileURL`.
    /// A single additional trailer video (separate from the feature `videoFileName`).
    var trailerFileName: String?
    /// Behind-the-scenes photos — any number, images only.
    var btsImageFileNames: [String] = []
    /// Promotional stills — any number, images only.
    var stillImageFileNames: [String] = []

    /// Photography posts: the gallery of photos (deterministic file names, resolved via
    /// `mediaFileURL`). The first image doubles as the post's thumbnail.
    var photoImageFileNames: [String] = []

    /// Photography posts: the gear used for the shoot (camera, lens, lighting, etc.).
    /// Empty for non-photography posts or when the photographer left it blank.
    var equipment: EquipmentInfo = EquipmentInfo()

    /// Design posts: the uploaded images (deterministic file names, resolved via
    /// `mediaFileURL`). The first image doubles as the post's thumbnail. A design post
    /// may instead (or additionally) carry a video, stored in `videoFileName`.
    var designImageFileNames: [String] = []

    /// Design posts: which kind of design this is — one of `DesignCategory`. Empty on
    /// posts created before the picker existed.
    var designCategory: String = ""

    /// Film video length in seconds, captured at upload and synced via CloudKit so
    /// the duration badge can show on every device — even ones that haven't
    /// downloaded the video file yet. Nil for non-film posts or older records.
    var videoDuration: Double?

    /// Film / Reel / Design: the crop applied to the post's video at playback, encoded by
    /// `VideoCrop` as normalized "x,y,w,h". The file itself is never re-encoded, so a
    /// streamed video can be cropped without downloading it. Nil = show the full frame.
    /// Optional so the on-disk `[Submission]` cache still decodes without it.
    var videoCrop: String?

    // Event-specific fields
    var eventStartDate: Date?
    var eventEndDate: Date?
    var eventLocation: String?
    var eventHost: String = ""
    var eventTicketsURL: String?
    /// Recruitment Schedule: what applicants should expect / commit to.
    var eventExpectations: String?
    /// Recruitment Schedule: link to the application.
    var eventApplicationURL: String?
    /// "Other" links, available on every category (alongside `eventTicketsURL`).
    var eventRSVPURL: String?
    var eventWebsiteURL: String?
    /// Freeform lineup for the category — Artists (Concert), Actors (Actor Showcase),
    /// or Films (Film Festival). The label is chosen by the category at display time.
    var eventLineup: String?
    /// Theatre Performance: every showing in the run (a date with start/end times).
    /// `eventStartDate`/`eventEndDate` are kept in step with the first and last showing
    /// so all the existing date sorting, filtering and expiry logic still applies.
    ///
    /// Optional, not a defaulted array, on purpose: the on-disk `[Submission]` cache is
    /// decoded with the synthesized `init(from:)`, which throws on a missing key for a
    /// non-optional property — that would drop the whole cached feed on the first launch
    /// after this update, until CloudKit re-synced.
    var eventShowings: [EventShowing]?

    // Project-specific fields
    var shootDates: String = ""
    var expectedReleaseDate: String = ""
    var castNeeded: [String] = []
    var crewNeeded: [String] = []
    /// Which kind of project post this is: "Cast & Crew Call", "Script",
    /// "In-Development", or "In-Post-Production". Empty for legacy projects (treated as
    /// Cast & Crew Call).
    var projectType: String = ""
    /// Page count of an attached script PDF (Script projects). 0 when not applicable.
    var scriptPageCount: Int = 0
    /// Project posts: the slideshow images, in order. When present they replace the
    /// poster on the detail view and the poster is shown last, after them; the Discover
    /// feed still previews the poster (`thumbnailData`).
    ///
    /// Optional, not a defaulted array, on purpose — same reason as `eventShowings`
    /// above: the on-disk `[Submission]` cache is decoded with the synthesized
    /// `init(from:)`, which throws on a missing key for a non-optional property, and
    /// that would drop the whole cached feed on the first launch after this update.
    var projectSlideFileNames: [String]?
    /// Project posts: where to sign up for an audition (Cast & Crew Calls). Nil when unset.
    var projectAuditionURL: String?
    /// Project posts: who to reach out to, one free-form line each (e.g. "Jamie Martinez —
    /// jamie@utexas.edu"). Emails, phone numbers and links in a line become tappable on
    /// the detail view. Optional for the same cache-decoding reason as above.
    var projectContacts: [String]?

    // Film-specific fields
    var studio: String = ""

    /// Film & Music: the year the work was released (4-digit string, empty if unset).
    var releaseYear: String = ""
    
    // Music-specific fields
    var artist: String = "" // Artist name for music submissions
    /// What kind of release this is — "Song", "EP", "Album" or "Performance".
    /// Empty on records created before the category picker existed.
    var musicCategory: String = ""
    var musicians: String = ""
    var writers: String = ""
    var mixers: String = ""
    
    // Music credits - ordered arrays
    var orderedRecording: [OrderedEntry] = [] // Recording credits (musicians, vocalists, etc.)
    var orderedProduction: [OrderedEntry] = [] // Production credits (producers, engineers, mixers, etc.)
    
    // Music streaming links
    var spotifyLink: String = ""
    var appleMusicLink: String = ""
    var amazonMusicLink: String = ""
    var youtubeMusicLink: String = ""
    var soundcloudLink: String = ""

    // Song lyrics, shown at the bottom of the music card below the streaming links.
    var lyrics: String = ""

    // Talent Reel-specific fields
    var reelType: String = ""
    var reelDescription: String = ""
    var reelExperience: String = ""
    var reelSpecificSkills: String = ""
    /// UUID strings of other posts this reel references as "Featured Work". Resolved
    /// against the store when displayed so the referenced posts appear on the reel card.
    var featuredWorkIDs: [String] = []
    /// Hand-typed "Featured Work" entries (a project + its director) that aren't posts on
    /// the app. Each element is a JSON-encoded `ManualFeaturedWork`.
    var featuredWorkManual: [String] = []

    // MARK: - Initializer
    
    init(
        id: UUID,
        type: MediaType,
        title: String,
        details: String,
        isApproved: Bool = false,
        submittedBy: String = "",
        createdDate: Date = Date(),
        lastEditedDate: Date? = nil,
        logline: String = "",
        ageRating: String = "",
        genres: [String] = [],
        cast: [String: String] = [:],
        crew: [String: String] = [:],
        orderedCast: [OrderedEntry] = [],
        orderedCrew: [OrderedEntry] = [],
        explicit: Bool = false,
        videoFileName: String? = nil,
        audioFileName: String? = nil,
        thumbnailData: Data? = nil,
        scriptFileName: String? = nil,
        eventStartDate: Date? = nil,
        eventEndDate: Date? = nil,
        eventLocation: String? = nil,
        eventHost: String = "",
        eventTicketsURL: String? = nil,
        shootDates: String = "",
        expectedReleaseDate: String = "",
        castNeeded: [String] = [],
        crewNeeded: [String] = [],
        projectType: String = "",
        scriptPageCount: Int = 0,
        studio: String = "",
        releaseYear: String = "",
        artist: String = "",
        musicians: String = "",
        writers: String = "",
        mixers: String = "",
        orderedRecording: [OrderedEntry] = [],
        orderedProduction: [OrderedEntry] = [],
        spotifyLink: String = "",
        appleMusicLink: String = "",
        amazonMusicLink: String = "",
        youtubeMusicLink: String = "",
        soundcloudLink: String = "",
        lyrics: String = "",
        musicCategory: String = "",
        reelType: String = "",
        reelDescription: String = "",
        reelExperience: String = "",
        reelSpecificSkills: String = "",
        featuredWorkIDs: [String] = [],
        featuredWorkManual: [String] = [],
        trailerFileName: String? = nil,
        btsImageFileNames: [String] = [],
        stillImageFileNames: [String] = [],
        photoImageFileNames: [String] = []
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.details = details
        self.isApproved = isApproved
        self.submittedBy = submittedBy
        self.createdDate = createdDate
        self.lastEditedDate = lastEditedDate
        self.logline = logline
        self.ageRating = ageRating
        self.genres = genres
        self.cast = cast
        self.crew = crew
        self.orderedCast = orderedCast
        self.orderedCrew = orderedCrew
        self.explicit = explicit
        self.videoFileName = videoFileName
        self.audioFileName = audioFileName
        self.thumbnailData = thumbnailData
        self.scriptFileName = scriptFileName
        self.eventStartDate = eventStartDate
        self.eventEndDate = eventEndDate
        self.eventLocation = eventLocation
        self.eventHost = eventHost
        self.eventTicketsURL = eventTicketsURL
        self.shootDates = shootDates
        self.expectedReleaseDate = expectedReleaseDate
        self.castNeeded = castNeeded
        self.crewNeeded = crewNeeded
        self.projectType = projectType
        self.scriptPageCount = scriptPageCount
        self.studio = studio
        self.releaseYear = releaseYear
        self.artist = artist
        self.musicians = musicians
        self.writers = writers
        self.mixers = mixers
        self.orderedRecording = orderedRecording
        self.orderedProduction = orderedProduction
        self.spotifyLink = spotifyLink
        self.appleMusicLink = appleMusicLink
        self.amazonMusicLink = amazonMusicLink
        self.youtubeMusicLink = youtubeMusicLink
        self.soundcloudLink = soundcloudLink
        self.lyrics = lyrics
        self.musicCategory = musicCategory
        self.reelType = reelType
        self.reelDescription = reelDescription
        self.reelExperience = reelExperience
        self.reelSpecificSkills = reelSpecificSkills
        self.featuredWorkIDs = featuredWorkIDs
        self.featuredWorkManual = featuredWorkManual
        self.trailerFileName = trailerFileName
        self.btsImageFileNames = btsImageFileNames
        self.stillImageFileNames = stillImageFileNames
        self.photoImageFileNames = photoImageFileNames
    }

    // Computed property to get the actual video URL
    var videoURL: URL? {
        guard let videoFileName = videoFileName else { return nil }
        let url = FileManager.default.mediaFileURL(named: videoFileName)
        if url == nil { print("⚠️ Video file not found: \(videoFileName)") }
        return url
    }

    // Computed property to get the actual audio URL
    var audioURL: URL? {
        guard let audioFileName = audioFileName else { return nil }
        let url = FileManager.default.mediaFileURL(named: audioFileName)
        if url == nil { print("⚠️ Audio file not found: \(audioFileName)") }
        return url
    }

    /// Every audio track on the post, in running order: `audioURL` first, then the
    /// additional EP/Album tracks. Tracks whose file isn't on disk are skipped, so a
    /// single always resolves to at most one URL.
    var musicTrackURLs: [URL] {
        var urls: [URL] = []
        if let audioURL { urls.append(audioURL) }
        for name in musicTrackFileNames ?? [] {
            if let url = FileManager.default.mediaFileURL(named: name) { urls.append(url) }
        }
        return urls
    }

    // MARK: - Film Extras URLs

    /// Local URL of the trailer video, if one is on disk (cache or Documents).
    var trailerURL: URL? {
        guard let trailerFileName else { return nil }
        return FileManager.default.mediaFileURL(named: trailerFileName)
    }

    /// Local URLs of the behind-the-scenes photos currently on disk (missing files are
    /// skipped — they re-download on demand).
    var btsImageURLs: [URL] {
        btsImageFileNames.compactMap { FileManager.default.mediaFileURL(named: $0) }
    }

    /// Local URLs of the stills currently on disk (missing files are skipped).
    var stillImageURLs: [URL] {
        stillImageFileNames.compactMap { FileManager.default.mediaFileURL(named: $0) }
    }

    /// Local URLs of the photography gallery images currently on disk (missing skipped).
    var photoImageURLs: [URL] {
        photoImageFileNames.compactMap { FileManager.default.mediaFileURL(named: $0) }
    }

    /// Local URLs of the design post's images currently on disk (missing skipped).
    var designImageURLs: [URL] {
        designImageFileNames.compactMap { FileManager.default.mediaFileURL(named: $0) }
    }

    /// Local URLs of the project's slideshow images currently on disk (missing skipped).
    var projectSlideURLs: [URL] {
        (projectSlideFileNames ?? []).compactMap { FileManager.default.mediaFileURL(named: $0) }
    }

    /// Whether `name` is this photography post's photographer. A photography post stores
    /// its photographer in `artist` rather than in the ordered credit lists, so the
    /// profile/portfolio "is this person credited?" checks have to test it explicitly —
    /// otherwise a photographer's own posts never appear on their profile.
    func isPhotographer(named name: String) -> Bool {
        guard type == .photography else { return false }
        let person = name.trimmingCharacters(in: .whitespaces)
        guard !person.isEmpty else { return false }
        return artist.trimmingCharacters(in: .whitespaces) == person
    }

    // Computed property to get the actual script URL
    var scriptURL: URL? {
        guard let scriptFileName = scriptFileName else { return nil }
        guard let documentsDir = FileManager.default.documentsDirectory else { return nil }
        let url = documentsDir.appendingPathComponent(scriptFileName)
        
        // Verify the file actually exists
        guard FileManager.default.fileExistsAndIsAccessible(at: url) else {
            print("⚠️ Script file not found: \(scriptFileName)")
            return nil
        }
        
        return url
    }
    
    // MARK: - CloudKit Conversion
    
    func toCloudKitRecord(userRecordID: CKRecord.ID?) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: "Submission", recordID: recordID)
        
        // Basic fields
        record["title"] = title as CKRecordValue
        record["details"] = details as CKRecordValue
        record["type"] = type.rawValue as CKRecordValue
        record["isApproved"] = (isApproved ? 1 : 0) as CKRecordValue
        record["submittedBy"] = submittedBy as CKRecordValue
        record["createdDate"] = createdDate as CKRecordValue
        
        if let lastEditedDate = lastEditedDate {
            record["lastEditedDate"] = lastEditedDate as CKRecordValue
        }
        
        if let userID = userRecordID?.recordName {
            record["userID"] = userID as CKRecordValue
        }
        
        // Type-specific fields
        record["logline"] = logline as CKRecordValue
        record["ageRating"] = ageRating as CKRecordValue
        record["studio"] = studio as CKRecordValue
        record["releaseYear"] = releaseYear as CKRecordValue
        record["artist"] = artist as CKRecordValue
        record["musicCategory"] = musicCategory as CKRecordValue
        record["explicit"] = (explicit ? 1 : 0) as CKRecordValue

        // Music streaming links
        record["spotifyLink"] = spotifyLink as CKRecordValue
        record["appleMusicLink"] = appleMusicLink as CKRecordValue
        record["amazonMusicLink"] = amazonMusicLink as CKRecordValue
        record["youtubeMusicLink"] = youtubeMusicLink as CKRecordValue
        record["soundcloudLink"] = soundcloudLink as CKRecordValue
        record["lyrics"] = lyrics as CKRecordValue

        // Talent Reel fields
        record["reelType"] = reelType as CKRecordValue
        record["reelDescription"] = reelDescription as CKRecordValue
        record["reelExperience"] = reelExperience as CKRecordValue
        record["reelSpecificSkills"] = reelSpecificSkills as CKRecordValue
        if !featuredWorkIDs.isEmpty {
            record["featuredWorkIDs"] = featuredWorkIDs as CKRecordValue
        }
        if !featuredWorkManual.isEmpty {
            record["featuredWorkManual"] = featuredWorkManual as CKRecordValue
        }

        if !genres.isEmpty {
            record["genres"] = genres as CKRecordValue
        }
        
        // Event fields
        if let eventStartDate = eventStartDate {
            record["eventStartDate"] = eventStartDate as CKRecordValue
        }
        if let eventEndDate = eventEndDate {
            record["eventEndDate"] = eventEndDate as CKRecordValue
        }
        if let eventLocation = eventLocation {
            record["eventLocation"] = eventLocation as CKRecordValue
        }
        record["eventHost"] = eventHost as CKRecordValue
        if let eventTicketsURL = eventTicketsURL {
            record["eventTicketsURL"] = eventTicketsURL as CKRecordValue
        }
        if let eventExpectations = eventExpectations {
            record["eventExpectations"] = eventExpectations as CKRecordValue
        }
        if let eventApplicationURL = eventApplicationURL {
            record["eventApplicationURL"] = eventApplicationURL as CKRecordValue
        }
        if let eventRSVPURL = eventRSVPURL {
            record["eventRSVPURL"] = eventRSVPURL as CKRecordValue
        }
        if let eventWebsiteURL = eventWebsiteURL {
            record["eventWebsiteURL"] = eventWebsiteURL as CKRecordValue
        }
        if let eventLineup = eventLineup {
            record["eventLineup"] = eventLineup as CKRecordValue
        }
        if let eventShowings, !eventShowings.isEmpty {
            record["eventShowtimes"] = EventShowing.wireEntries(from: eventShowings) as CKRecordValue
        }

        // Project fields
        record["shootDates"] = shootDates as CKRecordValue
        record["expectedReleaseDate"] = expectedReleaseDate as CKRecordValue
        record["projectType"] = projectType as CKRecordValue
        record["scriptPageCount"] = scriptPageCount as CKRecordValue
        record["writers"] = writers as CKRecordValue
        if !castNeeded.isEmpty {
            record["castNeeded"] = castNeeded as CKRecordValue
        }
        if !crewNeeded.isEmpty {
            record["crewNeeded"] = crewNeeded as CKRecordValue
        }
        
        // Photography equipment (JSON blob; omitted when nothing was entered)
        let equipmentJSON = equipment.jsonString
        if !equipmentJSON.isEmpty {
            record["photographyEquipment"] = equipmentJSON as CKRecordValue
        }

        // Thumbnail
        if let thumbnailData = thumbnailData {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(id.uuidString + "_thumbnail.jpg")
            try thumbnailData.write(to: tempURL)
            let asset = CKAsset(fileURL: tempURL)
            record["thumbnail"] = asset
        }
        
        return record
    }
    
    static func fromCloudKitRecord(_ record: CKRecord) -> Submission? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let typeString = record["type"] as? String,
              let type = MediaType(rawValue: typeString) else {
            return nil
        }
        
        let title = (record["title"] as? String) ?? "Untitled"
        let details = (record["details"] as? String) ?? ""
        
        var submission = Submission(id: id, type: type, title: title, details: details)
        
        submission.isApproved = ((record["isApproved"] as? Int) ?? 0) == 1
        submission.submittedBy = (record["submittedBy"] as? String) ?? "Anonymous"
        submission.createdDate = (record["createdDate"] as? Date) ?? Date()
        submission.lastEditedDate = record["lastEditedDate"] as? Date
        submission.schoolID = record["schoolID"] as? String

        // Type-specific fields
        submission.logline = (record["logline"] as? String) ?? ""
        submission.ageRating = (record["ageRating"] as? String) ?? ""
        submission.studio = (record["studio"] as? String) ?? ""
        submission.releaseYear = (record["releaseYear"] as? String) ?? ""
        submission.artist = (record["artist"] as? String) ?? ""
        submission.musicCategory = (record["musicCategory"] as? String) ?? ""
        submission.explicit = ((record["explicit"] as? Int) ?? 0) == 1

        // Music streaming links
        submission.spotifyLink = (record["spotifyLink"] as? String) ?? ""
        submission.appleMusicLink = (record["appleMusicLink"] as? String) ?? ""
        submission.amazonMusicLink = (record["amazonMusicLink"] as? String) ?? ""
        submission.youtubeMusicLink = (record["youtubeMusicLink"] as? String) ?? ""
        submission.soundcloudLink = (record["soundcloudLink"] as? String) ?? ""
        submission.lyrics = (record["lyrics"] as? String) ?? ""

        // Talent Reel fields
        submission.reelType = (record["reelType"] as? String) ?? ""
        submission.reelDescription = (record["reelDescription"] as? String) ?? ""
        submission.reelExperience = (record["reelExperience"] as? String) ?? ""
        submission.reelSpecificSkills = (record["reelSpecificSkills"] as? String) ?? ""
        if let featuredWorkIDs = record["featuredWorkIDs"] as? [String] {
            submission.featuredWorkIDs = featuredWorkIDs
        }
        if let featuredWorkManual = record["featuredWorkManual"] as? [String] {
            submission.featuredWorkManual = featuredWorkManual
        }

        if let genres = record["genres"] as? [String] {
            submission.genres = genres
        }
        
        // Event fields
        submission.eventStartDate = record["eventStartDate"] as? Date
        submission.eventEndDate = record["eventEndDate"] as? Date
        submission.eventLocation = record["eventLocation"] as? String
        submission.eventHost = (record["eventHost"] as? String) ?? ""
        submission.eventTicketsURL = record["eventTicketsURL"] as? String
        submission.eventExpectations = record["eventExpectations"] as? String
        submission.eventApplicationURL = record["eventApplicationURL"] as? String
        submission.eventRSVPURL = record["eventRSVPURL"] as? String
        submission.eventWebsiteURL = record["eventWebsiteURL"] as? String
        submission.eventLineup = record["eventLineup"] as? String
        if let showtimes = record["eventShowtimes"] as? [String] {
            let showings = EventShowing.showings(fromWireEntries: showtimes)
            submission.eventShowings = showings.isEmpty ? nil : showings
        }

        // Project fields
        submission.shootDates = (record["shootDates"] as? String) ?? ""
        submission.expectedReleaseDate = (record["expectedReleaseDate"] as? String) ?? ""
        submission.projectType = (record["projectType"] as? String) ?? ""
        submission.scriptPageCount = (record["scriptPageCount"] as? Int) ?? 0
        submission.writers = (record["writers"] as? String) ?? ""
        if let castNeeded = record["castNeeded"] as? [String] {
            submission.castNeeded = castNeeded
        }
        if let crewNeeded = record["crewNeeded"] as? [String] {
            submission.crewNeeded = crewNeeded
        }
        
        // Photography equipment
        if let equipmentJSON = record["photographyEquipment"] as? String {
            submission.equipment = EquipmentInfo(jsonString: equipmentJSON)
        }

        // Thumbnail
        if let asset = record["thumbnail"] as? CKAsset,
           let fileURL = asset.fileURL,
           let data = try? Data(contentsOf: fileURL) {
            submission.thumbnailData = data
        }
        
        return submission
    }
}

// MARK: - FileManager Extension

// These are pure disk-I/O helpers with no main-actor state. Marking the extension
// `nonisolated` opts it out of the project's default main-actor isolation so the
// launch-time cache maintenance can run on a background task (see AppView.init).
nonisolated extension FileManager {
    var documentsDirectory: URL? {
        // This returns the app's Documents directory which persists across app updates
        // Note: In development, reinstalling the app creates a new container, so files will be lost
        // In production/TestFlight, files persist correctly across app updates
        urls(for: .documentDirectory, in: .userDomainMask).first
    }
    
    /// Check if a file exists and is accessible
    func fileExistsAndIsAccessible(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    // MARK: - Media Cache

    /// Canonical on-disk home for heavy media — both downloaded playback copies and
    /// outgoing upload copies (`<id>_video.mov`, `<id>_audio.<ext>`, `video_<id>.<ext>`).
    /// Lives in Caches so iOS can reclaim it under storage pressure and it's never part
    /// of a device/iCloud backup. `trimMediaCache` bounds it further so this reuse cache
    /// can't grow without limit (opening posts used to persist full videos forever, which
    /// is what let Documents balloon to tens of GB).
    var mediaCacheDirectory: URL? {
        guard let base = urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Media", isDirectory: true)
        if !fileExists(atPath: dir.path) {
            try? createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Resolves a stored media file name to its on-disk URL if present. Checks the media
    /// cache first, then Documents so files written by older builds (before media moved
    /// to Caches) still resolve until they're purged and re-downloaded.
    func mediaFileURL(named fileName: String) -> URL? {
        for dir in [mediaCacheDirectory, documentsDirectory].compactMap({ $0 }) {
            let url = dir.appendingPathComponent(fileName)
            if fileExistsAndIsAccessible(at: url) { return url }
        }
        return nil
    }

    /// Deletes a media file (by stored name) from wherever it lives (cache or Documents).
    func removeMediaFile(named fileName: String) {
        for dir in [mediaCacheDirectory, documentsDirectory].compactMap({ $0 }) {
            try? removeItem(at: dir.appendingPathComponent(fileName))
        }
    }

    /// True when a file name is reclaimable heavy media left by an older build: a
    /// downloaded playback copy (`<id>_video.mov`, `<id>_audio.<ext>`, `<id>_trailer.mov`),
    /// an outgoing upload copy (`video_<id>.<ext>`), or a downloaded gallery image —
    /// photography (`<id>_photo_<n>.jpg`), design (`<id>_design_<n>.jpg`) or film extras
    /// (`<id>_bts_<n>.jpg`, `<id>_still_<n>.jpg`). Every one of these re-downloads or re-streams on demand, so
    /// deleting it costs only a refetch.
    ///
    /// Scripts (`script_*`), profile images (`profile_*`, `*_profileImage.jpg`), feed
    /// thumbnails and JSON caches are NOT matched.
    private func isReclaimableMedia(_ name: String) -> Bool {
        let lower = name.lowercased()
        // Downloaded playback copies and outgoing upload copies.
        if lower.contains("_video.") || lower.contains("_audio.") || lower.contains("_trailer.") { return true }
        if lower.hasPrefix("video_") { return true }
        // Galleries. These are full-resolution images, dozens per post — the biggest
        // category the original name check missed, and why Documents stayed large after
        // the first pass of this cleanup.
        if lower.contains("_photo_") || lower.contains("_bts_") || lower.contains("_still_") { return true }
        if lower.contains("_design_") { return true }
        return false
    }

    /// Reclaim for installs upgrading from the builds that stored media in Documents.
    /// Media now lives in the (backup-excluded, purgeable) media cache, so any heavy
    /// media still sitting in Documents is dead weight — delete it. Anything opened again
    /// just re-downloads into the cache. This is what frees the tens of GB that had
    /// accumulated under `Documents & Data`.
    ///
    /// The walk is recursive because older builds also wrote galleries into Documents
    /// subdirectories; `Messaging` (the user's own conversations and attachments — real
    /// data, not a cache) and `thumbnails` (small feed artwork) are skipped wholesale.
    @discardableResult
    func purgeLegacyDocumentsMedia() -> Int64 {
        guard let dir = documentsDirectory,
              let walker = enumerator(at: dir,
                                      includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                      options: [.skipsHiddenFiles])
        else { return 0 }

        let preserved: Set<String> = ["Messaging", "thumbnails"]
        var reclaimed: Int64 = 0
        for case let url as URL in walker {
            if preserved.contains(url.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            guard isReclaimableMedia(url.lastPathComponent),
                  let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  vals.isRegularFile == true
            else { continue }
            let size = Int64(vals.fileSize ?? 0)
            do {
                try removeItem(at: url)
                reclaimed += size
            } catch {
                print("⚠️ purgeLegacyDocumentsMedia: couldn't delete \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if reclaimed > 0 {
            print("🧹 purgeLegacyDocumentsMedia: reclaimed \(reclaimed / 1_048_576) MB from Documents")
        }
        return reclaimed
    }

    /// Deletes scratch files in the temporary directory older than `maxAge`.
    ///
    /// Nothing else in the app ever cleans `tmp`, and every media flow writes a
    /// full-size copy there: the video picker copies each picked original under a fresh
    /// UUID name (so successive picks accumulate rather than overwrite), and upload prep
    /// writes a compressed/remuxed copy per submission. iOS only clears `tmp` under
    /// storage pressure, which on a device with room to spare may be never — so on a
    /// heavy poster's phone these leftovers are hundreds of MB per post that never comes
    /// back, and they count toward `Documents & Data` just like Documents does.
    ///
    /// Age-gating rather than emptying wholesale protects work still in flight: CloudKit
    /// saves run as long-lived operations (`isLongLived`) that can outlive a suspension
    /// and still read their `CKAsset` source file, so a copy staged minutes ago may be an
    /// upload in progress.
    @discardableResult
    func purgeStaleScratchFiles(olderThan maxAge: TimeInterval = 60 * 60) -> Int64 {
        let tmp = temporaryDirectory
        guard let names = try? contentsOfDirectory(atPath: tmp.path) else { return 0 }

        let cutoff = Date().addingTimeInterval(-maxAge)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var reclaimed: Int64 = 0
        for name in names {
            let url = tmp.appendingPathComponent(name)
            guard let vals = try? url.resourceValues(forKeys: keys),
                  vals.isRegularFile == true,
                  let modified = vals.contentModificationDate,
                  modified < cutoff
            else { continue }
            let size = Int64(vals.fileSize ?? 0)
            do {
                try removeItem(at: url)
                reclaimed += size
            } catch {
                print("⚠️ purgeStaleScratchFiles: couldn't delete \(name): \(error.localizedDescription)")
            }
        }
        if reclaimed > 0 {
            print("🧹 purgeStaleScratchFiles: reclaimed \(reclaimed / 1_048_576) MB from tmp")
        }
        return reclaimed
    }

    /// Caps the media cache, deleting least-recently-used files once the total exceeds
    /// `maxBytes`. A trimmed post simply re-streams on demand next time it's opened.
    /// Safe to call often; a no-op when already under budget.
    ///
    /// Budget is intentionally small (512 MB): video/audio now stream from the CDN and are
    /// never downloaded for playback, so this cache only holds an uploader's own just-posted
    /// copies (and stragglers from older builds). LRU-by-access keeps the freshest — e.g. a
    /// copy still being uploaded — and evicts the rest so personal storage isn't filled.
    func trimMediaCache(maxBytes: Int64 = 512 * 1024 * 1024) {
        guard let dir = mediaCacheDirectory,
              let names = try? contentsOfDirectory(atPath: dir.path) else { return }

        struct Entry { let url: URL; let size: Int64; let accessed: Date }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentAccessDateKey,
                                         .contentModificationDateKey, .isRegularFileKey]
        var entries: [Entry] = []
        var total: Int64 = 0
        for name in names {
            let url = dir.appendingPathComponent(name)
            guard let vals = try? url.resourceValues(forKeys: keys),
                  vals.isRegularFile == true else { continue }
            let size = Int64(vals.fileSize ?? 0)
            // Use last-access when available (LRU); fall back to modification date.
            let accessed = vals.contentAccessDate ?? vals.contentModificationDate ?? .distantPast
            entries.append(Entry(url: url, size: size, accessed: accessed))
            total += size
        }

        guard total > maxBytes else { return }
        print("🧹 trimMediaCache: \(total / 1_048_576) MB cached, trimming to \(maxBytes / 1_048_576) MB")
        for entry in entries.sorted(by: { $0.accessed < $1.accessed }) {
            if total <= maxBytes { break }
            do {
                try removeItem(at: entry.url)
                total -= entry.size
            } catch {
                print("⚠️ trimMediaCache: couldn't delete \(entry.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    /// Every disk reclaim the app performs, in one call: legacy media stranded in
    /// Documents, abandoned scratch copies in `tmp`, and the media cache trimmed back to
    /// budget. Pure disk I/O — call it off the main thread.
    func reclaimDiskSpace() {
        purgeLegacyDocumentsMedia()
        purgeStaleScratchFiles()
        trimMediaCache()
    }

    // MARK: - Storage Diagnostics

    /// Total bytes of every regular file under `url`, recursively. Returns 0 for a path
    /// that doesn't exist.
    func recursiveByteSize(at url: URL) -> Int64 {
        guard let walker = enumerator(at: url,
                                      includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        else { return 0 }
        var total: Int64 = 0
        for case let child as URL in walker {
            guard let vals = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  vals.isRegularFile == true
            else { continue }
            total += Int64(vals.fileSize ?? 0)
        }
        return total
    }

    /// A breakdown of everything the app occupies inside its container, biggest area
    /// first, followed by the largest individual files.
    ///
    /// `Documents & Data` in iOS Settings is the whole container — Documents, Library
    /// (including Caches) and tmp — so a number there can't be attributed without this.
    /// It's what distinguishes "old downloads were never removed" (mass sitting in
    /// Documents or the media cache) from "new downloads keep arriving" (the same area
    /// refilling after a purge) from a sink outside the app's own bookkeeping, such as
    /// CloudKit's private asset cache under `Library/Caches/CloudKit`.
    func storageReport(topFileCount: Int = 12) -> String {
        guard let documents = documentsDirectory else { return "Storage report unavailable." }
        let container = documents.deletingLastPathComponent()

        // Top-level areas, plus one level deeper into the two that actually grow.
        var areas: [URL] = (try? contentsOfDirectory(at: container, includingPropertiesForKeys: nil)) ?? []
        for parent in [documents, container.appendingPathComponent("Library/Caches", isDirectory: true)] {
            for child in (try? contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                areas.append(child)
            }
        }

        func format(_ bytes: Int64) -> String {
            ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        // Path relative to the container, so lines read "Documents/Messaging" etc.
        func label(_ url: URL) -> String {
            url.path.replacingOccurrences(of: container.path + "/", with: "")
        }

        var lines = ["📦 Container total: \(format(recursiveByteSize(at: container)))"]
        for (url, size) in areas.map({ ($0, recursiveByteSize(at: $0)) })
            .sorted(by: { $0.1 > $1.1 }) where size > 0 {
            lines.append("   \(format(size).padding(toLength: 12, withPad: " ", startingAt: 0))\(label(url))")
        }

        // Largest individual files — names carry the submission id and kind, which is
        // usually enough to identify what's being kept.
        if let walker = enumerator(at: container,
                                   includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
            var files: [(String, Int64)] = []
            for case let url as URL in walker {
                guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      vals.isRegularFile == true
                else { continue }
                files.append((label(url), Int64(vals.fileSize ?? 0)))
            }
            let largest = files.sorted { $0.1 > $1.1 }.prefix(topFileCount)
            if !largest.isEmpty {
                lines.append("   — \(files.count) files, largest:")
                for (name, size) in largest {
                    lines.append("   \(format(size).padding(toLength: 12, withPad: " ", startingAt: 0))\(name)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}

@MainActor
class SubmissionStore_3_2: ObservableObject {
    static let shared = SubmissionStore_3_2()
    // Use CloudKitTransitionAdapter to properly save videos/audio
    private let cloudKitAdapter = CloudKitTransitionAdapter.shared
    // MARK: - Published Properties

    @Published var submissions: [Submission] = []
    @Published var approvedSubmissions: [Submission] = []

    // Locally-saved drafts (never uploaded to CloudKit or shown in feeds)
    @Published var drafts: [Submission] = []
    
    // Shared properties
    @Published var history: [HistoryEntry] = []
    @Published var collections: [PostCollection] = []
    @Published var likedSubmissionIds: Set<UUID> = []
    /// Cached CloudKit like counts, keyed by submission ID. Populated lazily as posts are
    /// shown (`refreshLikeCount`) and adjusted optimistically on toggle. Views read it via
    /// `likeCount(for:)`; a missing entry means "not fetched yet" and displays as 0.
    @Published var likeCounts: [UUID: Int] = [:]
    // Not @Published on purpose: playback positions are read imperatively during
    // player setup and never observed by any view. Publishing them caused a crash
    // when savePlaybackPosition() mutated the dict during SwiftUI view teardown
    // (dismantleUIViewController → objectWillChange re-entered GraphHost.invalidate).
    //
    // Deliberately **in-memory only** and never persisted: resume-where-you-left-off
    // applies within a single app session, but a fresh launch starts empty so every
    // video and song plays from the beginning again.
    var videoPlaybackPositions: [UUID: Double] = [:]

    /// Record IDs that have been confirmed present in CloudKit at least once
    /// (either fetched back or successfully uploaded). Lets sync tell apart a post
    /// that's "created locally and still uploading" (keep) from one that "existed
    /// in CloudKit and was deleted there" (remove locally). Persisted, not published.
    private var syncedRecordIDs: Set<UUID> = []

    /// IDs of posts whose upload to CloudKit hasn't been confirmed yet. Added the
    /// moment a post is created (`add`) and removed once a save succeeds. Drives the
    /// feed's "hide until uploaded" behavior (`visibleApprovedSubmissions`). Persisted
    /// so a post shown mid-upload stays hidden across a relaunch.
    @Published private var pendingUploadIDs: Set<UUID> = []

    /// IDs of posts created (or explicitly retried) *in this app session* that still
    /// need uploading. This is deliberately **in-memory only**: it's the sole signal
    /// that authorizes re-uploading a post CloudKit doesn't have. CloudKit is the
    /// master copy, so on a fresh launch/build this set is empty and any locally-cached
    /// post the server doesn't have is dropped rather than resurrected — a post deleted
    /// from CloudKit stays deleted, instead of a stale local copy re-uploading itself
    /// forever. Genuine offline/failed uploads are still retried within the session
    /// that created them.
    private var sessionUploadIDs: Set<UUID> = []

    /// IDs whose CloudKit save is running right now. A large video can take minutes to
    /// upload, and the record doesn't exist server-side until it finishes — so without
    /// this, a sync in the meantime sees "pending + absent" and starts a second,
    /// duplicate upload of the same post.
    private var inFlightUploadIDs: Set<UUID> = []

    /// Approved posts that are safe to show in the browse feeds: everything whose
    /// CloudKit upload has confirmed. A post is withheld while it's still uploading
    /// (its ID is in `pendingUploadIDs`) so a half-uploaded post never appears on the
    /// main pages — the Home upload banner surfaces its progress in the meantime.
    /// Also scoped to the schools this user sees (`SchoolScope.isVisible`).
    var visibleApprovedSubmissions: [Submission] {
        // Read the school scope once, not per post — it's several UserDefaults reads,
        // and views call this property many times per render.
        let visibleSchoolIDs = SchoolScope.visibleSchoolIDs
        return approvedSubmissions.filter {
            !pendingUploadIDs.contains($0.id)
                && SchoolScope.isVisible(schoolID: $0.schoolID, in: visibleSchoolIDs)
        }
    }

    /// Collapses duplicate IDs to their first occurrence, preserving order. A stray
    /// duplicate (a double-submit, or a race between an optimistic local append and a
    /// concurrent sync) otherwise renders the same post several times in the feed:
    /// SwiftUI's `ForEach` keys on `id`, so equal IDs pile up copies, and since they
    /// share the same like-count/seen state the recommender clusters them — which is
    /// how the same post ends up "stuck" at the top. Applied wherever these arrays are
    /// (re)populated so duplicates can neither enter nor survive in the persisted cache.
    private func dedupedByID(_ items: [Submission]) -> [Submission] {
        var seen = Set<UUID>()
        return items.filter { seen.insert($0.id).inserted }
    }

    /// Read-only snapshot of the feed pipeline counts, for the in-app CloudKit debugger.
    /// Lets you see on-device (e.g. in a TestFlight build with no Mac attached) whether an
    /// empty feed is caused by nothing being fetched vs. posts being hidden client-side.
    /// `moderationHidden` is how many currently-hidden posts came from cross-device
    /// moderation "remove" actions.
    struct FeedDiagnostics {
        let approved: Int
        let pending: Int
        let visible: Int
        let hidden: Int
        let pendingUpload: Int
    }
    var feedDiagnostics: FeedDiagnostics {
        FeedDiagnostics(
            approved: approvedSubmissions.count,
            pending: submissions.count,
            visible: visibleApprovedSubmissions.count,
            hidden: hiddenSubmissionIDs.count,
            pendingUpload: pendingUploadIDs.count
        )
    }

    /// IDs of posts the user has soft-deleted in the app. They're hidden from the
    /// Home and Discover feeds but kept in the moderator "Deleted" section. This is
    /// a local, persisted list so hiding works even for posts this account can't
    /// modify/delete in CloudKit (public-DB records are only writable by their
    /// creator) — the feeds always respect it regardless of the cloud state.
    private var hiddenSubmissionIDs: Set<UUID> = []
    
    // MARK: - Beta Testing Support
    // Key prefix to support migration from beta to production
    private let keyPrefix: String
    private static let betaModeKey = "isBetaMode"
    
    private init() {
        // Determine if this is a beta build
        let isBeta = UserDefaults.standard.bool(forKey: Self.betaModeKey)
        // The CloudKit environment prefix keeps development and production caches apart,
        // so a Debug build never shows posts cached by a release build (or vice versa).
        self.keyPrefix = CloudKitEnvironmentDetector.localCachePrefix + (isBeta ? "beta_" : "")
        
        // Load data asynchronously for better performance
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.loadAllData()

            // Create the system "Liked" collection only AFTER the saved collections have
            // been loaded. Running this before the async load finished would see an empty
            // `collections` array, insert a fresh Liked, and overwrite the persisted
            // `postCollections` key with just `[Liked]` — wiping every user collection.
            await self?.ensureLikedCollectionExists()

            // 🌐 Sync with CloudKit after loading local data
            await self?.syncWithCloudKit()

            // ❤️ Restore this user's likes from CloudKit (e.g. on a new device/reinstall).
            // Runs after syncWithCloudKit so the iCloud user record ID is available.
            await self?.syncMyLikes()

            // 🔔 Setup automatic sync for real-time updates
            await self?.setupAutomaticSync()
        }
    }
    
    // MARK: - Beta Migration Support
    /// Call this when transitioning from beta to production
    static func migrateBetaToProduction() {
        let defaults = UserDefaults.standard
        
        // Copy all beta data to production keys
        let betaKeys = [
            "beta_pendingSubmissions",
            "beta_approvedSubmissions",
            "beta_moderationHistory",
            "beta_postCollections",
            "beta_likedSubmissions",
            "beta_videoPlaybackPositions"
        ]
        
        for key in betaKeys {
            if let data = defaults.data(forKey: key) {
                let prodKey = key.replacingOccurrences(of: "beta_", with: "")
                defaults.set(data, forKey: prodKey)
            }
        }
        
        // Also migrate user profile data
        let profileKeys = [
            "userFirstName", "userLastName", "userMajor", "userMinor",
            "userCertificate", "userGraduationYear", "userType",
            "profileImagePath", "hasCompletedOnboarding"
        ]
        
        // Profile data doesn't need beta prefix as it's user-specific
        // Just ensure it persists (it already does via UserDefaults)
        
        // Mark as no longer in beta mode
        defaults.set(false, forKey: betaModeKey)
        defaults.synchronize()
    }
    
    /// Enable beta mode (typically set at build configuration)
    static func enableBetaMode() {
        UserDefaults.standard.set(true, forKey: betaModeKey)
    }
    
    // MARK: - Async Data Loading
    private func loadAllData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadSubmissionsAsync() }
            group.addTask { await self.loadDraftsAsync() }
            group.addTask { await self.loadHistoryAsync() }
            group.addTask { await self.loadCollectionsAsync() }
            group.addTask { await self.loadLikedSubmissionsAsync() }
            // Video playback positions are intentionally NOT loaded here: they're
            // session-only, so a fresh launch starts every video/song from the beginning.
            group.addTask { await self.loadSyncedRecordIDsAsync() }
            group.addTask { await self.loadHiddenSubmissionIDsAsync() }
            group.addTask { await self.loadPendingUploadIDsAsync() }
        }
    }

    private func loadPendingUploadIDsAsync() async {
        let key = "\(keyPrefix)pendingUploadIDs"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            await MainActor.run {
                self.pendingUploadIDs = Set(decoded)
            }
        }
    }

    private func loadHiddenSubmissionIDsAsync() async {
        let key = "\(keyPrefix)hiddenSubmissionIDs"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            await MainActor.run {
                self.hiddenSubmissionIDs = Set(decoded)
            }
        }
    }

    private func loadSyncedRecordIDsAsync() async {
        let key = "\(keyPrefix)syncedRecordIDs"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            await MainActor.run {
                self.syncedRecordIDs = Set(decoded)
            }
            return
        }

        // First launch on a build with this tracking: seed the set from the posts
        // already cached locally. Those all originated from CloudKit, so treating
        // them as "previously synced" lets the next sync clean up any that were
        // already deleted server-side (instead of resurrecting them).
        var seeded = Set<UUID>()
        for cacheName in ["pendingSubmissions", "approvedSubmissions"] {
            if let decoded = Self.loadSubmissionCache(cacheName, keyPrefix: keyPrefix) {
                seeded.formUnion(decoded.map { $0.id })
            }
        }
        await MainActor.run {
            self.syncedRecordIDs = seeded
        }
        saveSyncedRecordIDs()
    }
    
    private func loadSubmissionsAsync() async {
        if let decoded = Self.loadSubmissionCache("pendingSubmissions", keyPrefix: keyPrefix) {
            await MainActor.run {
                // Drop legacy placeholder posts that an early build persisted locally,
                // and heal any duplicate IDs a past build may have cached.
                self.submissions = self.dedupedByID(decoded.filter { !$0.isPlaceholder })
            }
        }

        if let decoded = Self.loadSubmissionCache("approvedSubmissions", keyPrefix: keyPrefix) {
            await MainActor.run {
                self.approvedSubmissions = self.dedupedByID(decoded.filter { !$0.isPlaceholder })
            }
        }
    }

    private func loadDraftsAsync() async {
        if let decoded = Self.loadSubmissionCache("drafts", keyPrefix: keyPrefix) {
            await MainActor.run {
                self.drafts = decoded
            }
        }
    }

    private func loadHistoryAsync() async {
        let key = "\(keyPrefix)moderationHistory"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            await MainActor.run {
                self.history = decoded
            }
        }
    }
    
    private func loadCollectionsAsync() async {
        let key = "\(keyPrefix)postCollections"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([PostCollection].self, from: data) {
            await MainActor.run {
                self.collections = decoded
            }
        }
    }
    
    private func loadLikedSubmissionsAsync() async {
        let key = "\(keyPrefix)likedSubmissions"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            await MainActor.run {
                self.likedSubmissionIds = Set(decoded)
            }
        }
    }
    
    /// Adds a submission. Returns `nil` on success, or a user-facing error message
    /// explaining why it was rejected (so the UI can show it instead of a false success).
    @discardableResult
    func add(_ submission: Submission) -> String? {
        print("📝 ===== STARTING NEW SUBMISSION =====")
        print("📝 Title: \(submission.title)")
        print("📝 Type: \(submission.type.rawValue)")
        print("📝 ID: \(submission.id.uuidString)")
        print("📝 Submitted by: \(submission.submittedBy)")
        
        // 🔒 SECURITY: Rate limit check
        let userID = CloudKitManager.shared.userRecordID?.recordName ?? ""
        guard SecurityManager.shared.checkWriteRateLimit(userID: userID) else {
            print("❌ RATE LIMIT: Too many submissions. Please wait before submitting again.")
            SecurityManager.shared.logSecurityEvent(
                .rateLimitExceeded,
                userID: userID,
                details: ["action": "submission", "type": submission.type.rawValue]
            )
            return "You're posting too quickly. Please wait a moment and try again."
        }

        // 🔒 SECURITY: Input validation
        let validationResult = SecurityManager.shared.validateSubmission(
            title: submission.title,
            details: submission.details,
            type: submission.type,
            additionalFields: [
                "ageRating": submission.ageRating,
                "artist": submission.artist,
                "eventStartDate": submission.eventStartDate as Any,
                "eventLocation": submission.eventLocation as Any,
                "shootDates": submission.shootDates,
                "reelType": submission.reelType,
                "logline": submission.logline,
                "reelDescription": submission.reelDescription
            ]
        )
        
        guard validationResult.isValid else {
            print("❌ VALIDATION FAILED: \(validationResult.errors.joined(separator: ", "))")
            SecurityManager.shared.logSecurityEvent(
                .invalidInput,
                userID: userID,
                details: ["errors": validationResult.errors, "type": submission.type.rawValue]
            )
            return "Your post couldn't be posted: \(validationResult.errors.joined(separator: ", "))."
        }
        
        // 🔒 SECURITY: File validation
        if let videoURL = submission.videoURL {
            let fileValidation = SecurityManager.shared.validateFileUpload(
                url: videoURL,
                allowedExtensions: SecurityConstants.AllowedExtensions.video,
                maxSizeBytes: SecurityConstants.FileSizeLimits.video
            )
            
            guard fileValidation.isValid else {
                print("❌ VIDEO VALIDATION FAILED: \(fileValidation.error ?? "Unknown error")")
                SecurityManager.shared.logSecurityEvent(
                    .fileUploadRejected,
                    userID: userID,
                    details: ["error": fileValidation.error ?? "unknown", "type": "video"]
                )
                return fileValidation.error ?? "The video couldn't be uploaded."
            }
        }
        
        if let audioURL = submission.audioURL {
            let fileValidation = SecurityManager.shared.validateFileUpload(
                url: audioURL,
                allowedExtensions: SecurityConstants.AllowedExtensions.audio,
                maxSizeBytes: SecurityConstants.FileSizeLimits.audio
            )
            
            guard fileValidation.isValid else {
                print("❌ AUDIO VALIDATION FAILED: \(fileValidation.error ?? "Unknown error")")
                SecurityManager.shared.logSecurityEvent(
                    .fileUploadRejected,
                    userID: userID,
                    details: ["error": fileValidation.error ?? "unknown", "type": "audio"]
                )
                return fileValidation.error ?? "The audio couldn't be uploaded."
            }
        }
        
        // 🔍 DIAGNOSTIC: Check for duplicate IDs
        if approvedSubmissions.contains(where: { $0.id == submission.id }) {
            print("⚠️⚠️⚠️ WARNING: Duplicate ID detected!")
            print("⚠️⚠️⚠️ This submission ID already exists in approvedSubmissions!")
            print("⚠️⚠️⚠️ This will cause CloudKit to OVERWRITE the old post!")
            print("⚠️⚠️⚠️ Existing posts with this ID:")
            for existing in approvedSubmissions.filter({ $0.id == submission.id }) {
                print("⚠️⚠️⚠️   - \(existing.title) (created: \(existing.createdDate))")
            }
        }
        
        // Auto-approve all submissions
        var approvedSubmission = submission
        approvedSubmission.isApproved = true // Ensure it's marked as approved
        // Upsert: if this ID already exists (e.g. a double-tap on Post), replace it
        // rather than appending a second copy that would render twice in the feed.
        if let existingIndex = approvedSubmissions.firstIndex(where: { $0.id == approvedSubmission.id }) {
            approvedSubmissions[existingIndex] = approvedSubmission
        } else {
            approvedSubmissions.append(approvedSubmission)
        }
        
        print("✅ Added to local approvedSubmissions array (count: \(approvedSubmissions.count))")
        print("✅ All submission IDs in array:")
        for sub in approvedSubmissions.suffix(5) {  // Show last 5
            print("   - \(sub.title): \(sub.id.uuidString)")
        }
        
        // Add history entry
        let entry = HistoryEntry(
            action: HistoryAction.submitted,
            submissionId: approvedSubmission.id,
            submissionTitle: approvedSubmission.title,
            submissionType: approvedSubmission.type,
            performedBy: approvedSubmission.submittedBy
        )
        history.append(entry)
        
        print("📋 Added history entry")
        
        saveSubmissions()
        saveHistory()
        
        print("💾 Saved to local storage")

        // Mark as awaiting upload. This survives app relaunch, so if the upload never
        // confirms (offline, crash, etc.) the next sync knows to retry it rather than
        // mistaking its absence from CloudKit for a server-side deletion. Cleared once
        // the save is confirmed in `saveSubmissionToCloudKit`.
        pendingUploadIDs.insert(approvedSubmission.id)
        savePendingUploadIDs()
        // Authorize re-upload retries for this post, but only for the current session —
        // so it's never resurrected on a later launch if it ends up absent from CloudKit.
        sessionUploadIDs.insert(approvedSubmission.id)

        // 🌐 Save to CloudKit for sharing with all users, tracking progress so the
        // submission form can show a live upload wheel → checkmark.
        Task {
            print("🌐 Starting CloudKit upload task...")
            await saveSubmissionToCloudKit(approvedSubmission, trackProgress: true)
        }

        return nil // success
    }

    // MARK: - Drafts

    /// Save (or update) a draft locally. Drafts are kept only on-device and are
    /// never uploaded to CloudKit or surfaced in any feed.
    func saveDraft(_ submission: Submission) {
        var draft = submission
        draft.isApproved = false
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index] = draft
        } else {
            drafts.append(draft)
        }
        saveDrafts()
    }

    func deleteDraft(_ submission: Submission) {
        drafts.removeAll { $0.id == submission.id }
        saveDrafts()
    }

    private func saveDrafts() {
        let draftsToSave = drafts
        let prefix = keyPrefix

        Task.detached(priority: .utility) {
            Self.writeSubmissionCache(draftsToSave, name: "drafts", keyPrefix: prefix)
        }
    }

    func approve(_ submission: Submission) {
        if let index = submissions.firstIndex(where: { $0.id == submission.id }) {
            var approvedSubmission = submissions.remove(at: index)
            approvedSubmission.isApproved = true
            approvedSubmissions.append(approvedSubmission)
            
            // Add history entry
            let entry = HistoryEntry(
                action: HistoryAction.approved,
                submissionId: approvedSubmission.id,
                submissionTitle: approvedSubmission.title,
                submissionType: approvedSubmission.type,
                performedBy: "Moderator"
            )
            history.append(entry)
            
            saveSubmissions()
            saveHistory()
            
            // 🌐 Update in CloudKit
            Task {
                await saveSubmissionToCloudKit(approvedSubmission)
            }
        }
    }
    
    func deny(_ submission: Submission) {
        submissions.removeAll { $0.id == submission.id }
        
        // Add history entry
        let entry = HistoryEntry(
            action: HistoryAction.denied,
            submissionId: submission.id,
            submissionTitle: submission.title,
            submissionType: submission.type,
            performedBy: "Moderator"
        )
        history.append(entry)
        
        saveSubmissions()
        saveHistory()
    }
    
    /// Permanently deletes a post the user owns (the card "Delete" action, whose alert
    /// already warns it can't be undone). Removes it from every local bucket AND hard-
    /// deletes the CloudKit record so it can never resync. A persisted local
    /// `hiddenSubmissionIDs` tombstone keeps it hidden until CloudKit confirms the
    /// delete — and permanently if the record belongs to another account (the delete
    /// fails harmlessly and the post simply stays hidden on this device). This replaces
    /// the old soft-hide, which could let a still-approved server copy repopulate the
    /// feed on the next sync.
    func delete(_ submission: Submission) {
        // Remove from the live feed and the moderator "Deleted" bucket alike.
        approvedSubmissions.removeAll { $0.id == submission.id }
        submissions.removeAll { $0.id == submission.id }

        // Local tombstone (persisted): survives relaunches and blocks any re-sync /
        // re-upload from resurrecting the post before/without the CloudKit delete.
        hiddenSubmissionIDs.insert(submission.id)
        sessionUploadIDs.remove(submission.id)

        // Add history entry
        let entry = HistoryEntry(
            action: HistoryAction.deleted,
            submissionId: submission.id,
            submissionTitle: submission.title,
            submissionType: submission.type,
            performedBy: submission.submittedBy
        )
        history.append(entry)

        saveSubmissions()
        saveHistory()
        saveHiddenSubmissionIDs()

        Task {
            let deleted = await deleteSubmissionFromCloudKit(submission)
            if deleted {
                // Server copy is gone, so the local hide flag is no longer needed.
                hiddenSubmissionIDs.remove(submission.id)
                syncedRecordIDs.remove(submission.id)
                saveHiddenSubmissionIDs()
                saveSyncedRecordIDs()
            }
        }
    }
    
    // MARK: - Soft Delete (Moderation)

    /// Posts a moderator has hidden. They stay in CloudKit as non-approved so they
    /// remain hidden for every user, but are still visible in the moderator's
    /// "Deleted Posts" page. (The app auto-approves on submit, so the non-approved
    /// bucket is used exclusively for moderator-hidden posts.)
    var deletedSubmissions: [Submission] { submissions }

    /// Hides a post from all users WITHOUT removing it from CloudKit. The hidden
    /// state syncs via the existing `isApproved` field, so it disappears from every
    /// user's feed on their next sync.
    func softDelete(_ submission: Submission) {
        guard let index = approvedSubmissions.firstIndex(where: { $0.id == submission.id }) else { return }
        var hidden = approvedSubmissions.remove(at: index)
        hidden.isApproved = false
        if !submissions.contains(where: { $0.id == hidden.id }) {
            submissions.append(hidden)
        }

        // Record the hide locally so it survives even if the CloudKit write below never
        // sticks (the record belongs to another account, or the save errors). Without
        // this, the next sync sees the server copy still approved and repopulates it.
        hiddenSubmissionIDs.insert(submission.id)

        let entry = HistoryEntry(
            action: HistoryAction.deleted,
            submissionId: hidden.id,
            submissionTitle: hidden.title,
            submissionType: hidden.type,
            performedBy: "Moderator"
        )
        history.append(entry)

        saveSubmissions()
        saveHistory()
        saveHiddenSubmissionIDs()

        // Sync the hidden state so the post disappears for everyone. The isApproved
        // write only sticks for posts this account created; the moderation action is
        // what actually hides another user's post on every device.
        Task {
            await saveSubmissionToCloudKit(hidden)
            await recordModeration(postID: submission.id, isRemoved: true)
        }
    }

    /// Restores a hidden post so users can see it again.
    func restore(_ submission: Submission) {
        hiddenSubmissionIDs.remove(submission.id)
        saveHiddenSubmissionIDs()

        submissions.removeAll { $0.id == submission.id }
        var restored = submission
        restored.isApproved = true
        if !approvedSubmissions.contains(where: { $0.id == restored.id }) {
            approvedSubmissions.append(restored)
        }

        let entry = HistoryEntry(
            action: HistoryAction.approved,
            submissionId: restored.id,
            submissionTitle: restored.title,
            submissionType: restored.type,
            performedBy: "Moderator"
        )
        history.append(entry)

        saveSubmissions()
        saveHistory()

        Task {
            await saveSubmissionToCloudKit(restored)
            // Clear the removal on every device, not just this one.
            await recordModeration(postID: submission.id, isRemoved: false)
        }
    }

    /// Permanently removes a post from local storage AND CloudKit (irreversible).
    func permanentlyDelete(_ submission: Submission) {
        submissions.removeAll { $0.id == submission.id }
        approvedSubmissions.removeAll { $0.id == submission.id }

        // Keep it in the hidden set for now. We only clear that safety net once CloudKit
        // confirms the record is gone — otherwise a delete that can't go through (the
        // record belongs to another account, or CloudKit is offline) would let the next
        // sync pull the still-approved server copy right back into the feed.
        hiddenSubmissionIDs.insert(submission.id)
        // Don't let the session's re-upload path resurrect it either.
        sessionUploadIDs.remove(submission.id)

        let entry = HistoryEntry(
            action: HistoryAction.deleted,
            submissionId: submission.id,
            submissionTitle: submission.title,
            submissionType: submission.type,
            performedBy: "Moderator"
        )
        history.append(entry)

        saveSubmissions()
        saveHistory()
        saveHiddenSubmissionIDs()

        Task {
            // Always publish a removal so every device hides it even when the delete
            // below can't go through (the record belongs to another account). This is
            // also a permanent tombstone that prevents any re-upload resurrection.
            await recordModeration(postID: submission.id, isRemoved: true)

            let deleted = await deleteSubmissionFromCloudKit(submission)
            if deleted {
                // Server copy is gone, so the local hide flag is no longer needed.
                hiddenSubmissionIDs.remove(submission.id)
                syncedRecordIDs.remove(submission.id)
                saveHiddenSubmissionIDs()
                saveSyncedRecordIDs()
            }
        }
    }

    // MARK: - Moderation Channel (cross-device)

    /// Publishes a moderator decision to CloudKit so the hide/restore reaches every
    /// device. Gated to the moderator account — only moderators can remove a post for
    /// everyone. Failures are non-fatal: the local hide still stands on this device.
    private func recordModeration(postID: UUID, isRemoved: Bool) async {
        guard ModeratorAccess.isModerator else { return }
        do {
            try await CloudKitManager.shared.saveModerationAction(postID: postID, isRemoved: isRemoved)
            print("✅ Moderation action synced: \(postID) removed=\(isRemoved)")
        } catch {
            print("❌ Failed to sync moderation action for \(postID): \(error.localizedDescription)")
        }
    }

    /// Merges server moderation decisions into the persisted hidden set so this device
    /// hides posts other moderators removed and un-hides ones they restored. Applied on
    /// every sync, on every device. There is one decision record per post, so the
    /// latest overwrite is authoritative.
    private func applyModerationActions(_ actions: [ModerationAction]) {
        guard !actions.isEmpty else { return }
        var changed = false
        for action in actions {
            if action.isRemoved {
                if hiddenSubmissionIDs.insert(action.postID).inserted { changed = true }
            } else if hiddenSubmissionIDs.remove(action.postID) != nil {
                changed = true
            }
        }
        if changed { saveHiddenSubmissionIDs() }
    }

    func update(_ updatedSubmission: Submission) {
        var updated = updatedSubmission
        updated.lastEditedDate = Date()

        // The post lives in exactly one of two arrays: `approvedSubmissions` (visible in
        // the feeds) or `submissions` (still pending moderation). Update it wherever it is
        // so edits to a not-yet-approved post stick too.
        if let index = approvedSubmissions.firstIndex(where: { $0.id == updated.id }) {
            approvedSubmissions[index] = updated
        } else if let index = submissions.firstIndex(where: { $0.id == updated.id }) {
            submissions[index] = updated
        } else {
            return
        }

        // Add history entry
        let entry = HistoryEntry(
            action: HistoryAction.edited,
            submissionId: updated.id,
            submissionTitle: updated.title,
            submissionType: updated.type,
            performedBy: updated.submittedBy
        )
        history.append(entry)

        saveSubmissions()
        saveHistory()

        // 🌐 Update in CloudKit. Owner or moderator, the edit is written straight to the
        // post record — a moderator editing someone else's post makes a REAL edit to
        // that post, not a separate override record layered on at sync time.
        //
        // The owner's media and identity survive it: `toCloudKitRecord` only attaches
        // assets the editor actually has on disk, `preservingOwner` drops the `userID`
        // key, and the save uses a blind `.allKeys` policy — which overwrites only the
        // keys present on the record and leaves omitted ones at their server value.
        //
        // This needs the submission record types to grant Write to authenticated users
        // in the CloudKit schema's security roles. Under the public database's default
        // (creator-only write) a moderator's save is rejected, which surfaces as an
        // upload-error banner with Retry rather than a silent revert.
        Task {
            if isCurrentUserOwner(of: updated) {
                await saveSubmissionToCloudKit(updated)
            } else if ModeratorAccess.isModerator {
                await saveSubmissionToCloudKit(updated, preservingOwner: true)
            }
        }
    }

    /// Whether the signed-in user created this post, matching the ownership check the
    /// cards use to gate the Edit/Delete controls (`canEditOrDelete`).
    private func isCurrentUserOwner(of submission: Submission) -> Bool {
        let first = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let last = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return !currentUser.isEmpty && currentUser == submission.submittedBy
    }

    /// The store's current copy of a post, falling back to the one passed in when the
    /// store no longer has it.
    ///
    /// Detail screens presented with `.sheet(item:)` are handed the snapshot taken when
    /// the row was tapped, and that value never changes — so a screen that edits a post
    /// has to look the post back up here, or it keeps displaying the pre-edit values.
    func currentCopy(of submission: Submission) -> Submission {
        approvedSubmissions.first { $0.id == submission.id }
            ?? submissions.first { $0.id == submission.id }
            ?? submission
    }

    // MARK: - Persistence (Optimized with batching)
    
    // MARK: - Large on-disk caches
    //
    // Submission arrays carry image `thumbnailData`, so the combined blob easily exceeds
    // the ~4 MB limit UserDefaults/CFPreferences enforces (which silently drops the write
    // and logs a "store >= 4194304 bytes ... is invalid" error). These caches therefore
    // live as JSON files in Documents instead, with a one-time fallback to the legacy
    // UserDefaults blob so existing installs migrate transparently.

    nonisolated private static func cacheFileURL(_ name: String, keyPrefix: String) -> URL? {
        FileManager.default.documentsDirectory?.appendingPathComponent("cache_\(keyPrefix)\(name).json")
    }

    /// Loads a `[Submission]` cache: on-disk file first, then the legacy UserDefaults blob.
    nonisolated private static func loadSubmissionCache(_ name: String, keyPrefix: String) -> [Submission]? {
        if let url = cacheFileURL(name, keyPrefix: keyPrefix),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Submission].self, from: data) {
            return decoded
        }
        if let data = UserDefaults.standard.data(forKey: "\(keyPrefix)\(name)"),
           let decoded = try? JSONDecoder().decode([Submission].self, from: data) {
            return decoded
        }
        return nil
    }

    /// Writes a `[Submission]` cache to disk and clears any legacy UserDefaults blob.
    nonisolated private static func writeSubmissionCache(_ value: [Submission], name: String, keyPrefix: String) {
        if let url = cacheFileURL(name, keyPrefix: keyPrefix),
           let encoded = try? JSONEncoder().encode(value) {
            try? encoded.write(to: url, options: .atomic)
        }
        UserDefaults.standard.removeObject(forKey: "\(keyPrefix)\(name)")
    }

    private func saveSubmissions() {
        let submissionsToSave = submissions
        let approvedToSave = approvedSubmissions
        let prefix = keyPrefix

        Task.detached(priority: .utility) {
            Self.writeSubmissionCache(submissionsToSave, name: "pendingSubmissions", keyPrefix: prefix)
            Self.writeSubmissionCache(approvedToSave, name: "approvedSubmissions", keyPrefix: prefix)
        }
    }
    
    /// Persist the set of record IDs known to exist in CloudKit.
    private func saveSyncedRecordIDs() {
        let key = "\(keyPrefix)syncedRecordIDs"
        let idsToSave = Array(syncedRecordIDs)
        Task.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(idsToSave) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }

    /// Persist the set of locally-created posts still awaiting a confirmed upload.
    private func savePendingUploadIDs() {
        let key = "\(keyPrefix)pendingUploadIDs"
        let idsToSave = Array(pendingUploadIDs)
        Task.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(idsToSave) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }

    /// Persist the set of soft-deleted (hidden) submission IDs.
    private func saveHiddenSubmissionIDs() {
        let key = "\(keyPrefix)hiddenSubmissionIDs"
        let idsToSave = Array(hiddenSubmissionIDs)
        Task.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(idsToSave) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }

    private func saveHistory() {
        let key = "\(keyPrefix)moderationHistory"
        let historyToSave = history
        
        Task.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(historyToSave) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }
    
    // MARK: - Collections Management
    
    private func ensureLikedCollectionExists() {
        // Check if "Liked" collection exists
        if !collections.contains(where: { $0.isSystemCollection && $0.name == "Liked" }) {
            let likedCollection = PostCollection(name: "Liked", isSystemCollection: true)
            collections.insert(likedCollection, at: 0)
            saveCollections()
        }
    }
    
    func toggleLike(for submission: Submission) {
        let id = submission.id
        let nowLiked = !likedSubmissionIds.contains(id)

        // Optimistically update local state + displayed count so the UI reacts instantly.
        if nowLiked {
            likedSubmissionIds.insert(id)
            addToCollection(submissionId: id, collectionName: "Liked")
        } else {
            likedSubmissionIds.remove(id)
            removeFromCollection(submissionId: id, collectionName: "Liked")
        }
        saveLikedSubmissions()

        let previousCount = likeCounts[id] ?? 0
        likeCounts[id] = max(0, previousCount + (nowLiked ? 1 : -1))

        // Persist the like to CloudKit so it counts across users/devices, then reconcile
        // with the authoritative server count. Roll everything back if the write fails.
        Task {
            do {
                try await CloudKitManager.shared.setLike(nowLiked, postID: id)
                await refreshLikeCount(for: id)
            } catch {
                if nowLiked {
                    likedSubmissionIds.remove(id)
                    removeFromCollection(submissionId: id, collectionName: "Liked")
                } else {
                    likedSubmissionIds.insert(id)
                    addToCollection(submissionId: id, collectionName: "Liked")
                }
                likeCounts[id] = previousCount
                saveLikedSubmissions()
            }
        }
    }

    func isLiked(_ submission: Submission) -> Bool {
        likedSubmissionIds.contains(submission.id)
    }

    /// The cached like count for a post (0 until fetched). Call `refreshLikeCount(for:)`
    /// to populate it from CloudKit.
    func likeCount(for submission: Submission) -> Int {
        likeCounts[submission.id] ?? 0
    }

    /// Fetches the authoritative like count for a post from CloudKit and caches it.
    /// Safe to call on `.onAppear`; silently leaves the cached value on failure.
    func refreshLikeCount(for id: UUID) async {
        if let count = try? await CloudKitManager.shared.fetchLikeCount(postID: id) {
            likeCounts[id] = count
        }
    }

    /// Restores the current user's likes from CloudKit (e.g. on a new device). No-op when
    /// the user isn't identified or CloudKit is unreachable, so local likes are preserved.
    /// Merges the server's likes into the local set rather than replacing it, so a like
    /// made offline (not yet pushed) isn't dropped. The trade-off is that an unlike made
    /// on another device won't propagate here until that record is re-fetched.
    func syncMyLikes() async {
        if let ids = try? await CloudKitManager.shared.fetchMyLikedPostIDs() {
            likedSubmissionIds.formUnion(ids)
            for id in ids {
                addToCollection(submissionId: id, collectionName: "Liked")
            }
            saveLikedSubmissions()
        }
    }
    
    func createCollection(name: String) -> PostCollection {
        let collection = PostCollection(name: name)
        collections.append(collection)
        saveCollections()
        return collection
    }
    
    func deleteCollection(_ collection: PostCollection) {
        guard !collection.isSystemCollection else { return }
        collections.removeAll { $0.id == collection.id }
        saveCollections()
    }
    
    func addToCollection(submissionId: UUID, collectionId: UUID) {
        if let index = collections.firstIndex(where: { $0.id == collectionId }) {
            if !collections[index].submissionIds.contains(submissionId) {
                collections[index].submissionIds.append(submissionId)
                saveCollections()
            }
        }
    }
    
    func addToCollection(submissionId: UUID, collectionName: String) {
        if let index = collections.firstIndex(where: { $0.name == collectionName }) {
            if !collections[index].submissionIds.contains(submissionId) {
                collections[index].submissionIds.append(submissionId)
                saveCollections()
            }
        }
    }
    
    func removeFromCollection(submissionId: UUID, collectionId: UUID) {
        if let index = collections.firstIndex(where: { $0.id == collectionId }) {
            collections[index].submissionIds.removeAll { $0 == submissionId }
            saveCollections()
        }
    }
    
    func removeFromCollection(submissionId: UUID, collectionName: String) {
        if let index = collections.firstIndex(where: { $0.name == collectionName }) {
            collections[index].submissionIds.removeAll { $0 == submissionId }
            saveCollections()
        }
    }
    
    func getSubmissions(for collection: PostCollection) -> [Submission] {
        return approvedSubmissions.filter { collection.submissionIds.contains($0.id) }
    }
    
    func isInAnyCollection(_ submission: Submission) -> Bool {
        return collections.contains { $0.submissionIds.contains(submission.id) && !$0.isSystemCollection }
    }
    
    private func saveCollections() {
        let key = "\(keyPrefix)postCollections"
        let collectionsToSave = collections
        
        Task.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(collectionsToSave) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }
    
    private func saveLikedSubmissions() {
        let key = "\(keyPrefix)likedSubmissions"
        let likedArray = Array(likedSubmissionIds)
        
        Task.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(likedArray) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }
    
    // MARK: - Video Playback Position Management
    
    /// Records where a video/song was left off, in-memory only. Kept for the current app
    /// session so reopening a post resumes where you stopped; intentionally not persisted,
    /// so the next launch starts everything from the beginning.
    func savePlaybackPosition(for submissionId: UUID, position: Double) {
        videoPlaybackPositions[submissionId] = position
    }

    func getPlaybackPosition(for submissionId: UUID) -> Double? {
        return videoPlaybackPositions[submissionId]
    }

    // MARK: - CloudKit Integration
    
    /// Sync submissions from CloudKit (fetch all posts)
    ///
    /// **Architecture Note:**
    /// This app uses a UNIFIED approach with a single "Submission" CloudKit record type
    /// that handles all content types (Film, Music, Reel, Project, Event) via a `type` field.
    ///
    /// **Why unified instead of specialized?**
    /// - Simpler data model with single source of truth
    /// - All submissions have consistent fields and behavior
    /// - Easier to implement cross-type features (search, sorting, collections)
    /// - Type-specific fields are handled via optional properties
    ///
    /// **Alternative approach:**
    /// CloudKitManager also supports specialized record types (FilmSubmission, MusicSubmission, etc.)
    /// but this is NOT currently used. If you need type-specific indexes or queries in the future,
    /// you can migrate to specialized types using the helper methods in CloudKitManager.
    ///
    /// The currently-running sync, if any. Used to coalesce overlapping requests.
    private var activeSyncTask: Task<Void, Never>?

    /// Runs a CloudKit sync, coalescing concurrent callers onto a single run.
    ///
    /// At launch alone the store's own init and (formerly) the launch screen both
    /// asked to sync, and the scene-becomes-active resync, push-notification resync,
    /// and pull-to-refresh can all overlap too. Each sync is a 5-query + thumbnail
    /// fetch, so letting them stack doubled the network/main-thread work at the worst
    /// possible moment and let their results race. If a sync is already in flight, new
    /// callers await that one instead of starting another.
    @MainActor
    func syncWithCloudKit() async {
        if let activeSyncTask {
            await activeSyncTask.value
            return
        }
        let task = Task { await performSync() }
        activeSyncTask = task
        await task.value
        activeSyncTask = nil
    }

    /// Performs one full CloudKit sync. Go through `syncWithCloudKit()` instead of
    /// calling this directly so overlapping requests are coalesced.
    @MainActor
    private func performSync() async {
        // 🔒 SECURITY: Rate limit check for sync operations
        let userID = CloudKitManager.shared.userRecordID?.recordName ?? ""
        guard SecurityManager.shared.checkReadRateLimit(userID: userID) else {
            print("⚠️ RATE LIMIT: Too many sync requests. Please wait.")
            return
        }
        
        // Check availability
        await cloudKitAdapter.checkAvailability()
        
        guard cloudKitAdapter.isAvailable else {
            print("⚠️ CloudKit not available - skipping sync")
            return
        }
        
        print("🔄 Starting CloudKit sync...")
        print("🔄 Local state before sync:")
        print("   - Pending: \(submissions.count)")
        print("   - Approved: \(approvedSubmissions.count)")
        
        do {
            // Fetch ALL submissions using CloudKitTransitionAdapter.
            // Ignore legacy placeholder posts so they never reappear or get re-uploaded,
            // regardless of whether they still linger in the public database.
            let cloudSubmissions = try await cloudKitAdapter.fetchAllSubmissions()
                .filter { !$0.isPlaceholder }

            // Cross-device moderation: pull every moderator decision so removals made
            // on another device hide the post here too (and restores un-hide it).
            // Missing record type (nothing moderated yet) is fine — treat as none.
            let moderationActions = (try? await CloudKitManager.shared.fetchModerationActions()) ?? []

            print("📥 Fetched \(cloudSubmissions.count) submissions from CloudKit")
            if cloudSubmissions.isEmpty {
                print("⚠️⚠️⚠️ WARNING: CloudKit returned ZERO submissions!")
                print("⚠️⚠️⚠️ This means:")
                print("⚠️⚠️⚠️ 1. Records were deleted from CloudKit Dashboard, or")
                print("⚠️⚠️⚠️ 2. CloudKit query is not finding records, or")
                print("⚠️⚠️⚠️ 3. Schema field names don't match")
            }
            
            await MainActor.run {
                // Fold in server moderation decisions BEFORE partitioning, so the
                // hidden-set checks below reflect removals/restores from every device.
                applyModerationActions(moderationActions)

                // Create a set to track which posts CloudKit currently has.
                let cloudSubmissionIDs = Set(cloudSubmissions.map { $0.id })

                // Everything CloudKit returned is now known-synced.
                syncedRecordIDs.formUnion(cloudSubmissionIDs)

                // Separate pending and approved submissions
                var updatedPending: [Submission] = []
                var updatedApproved: [Submission] = []

                // Add/update CloudKit submissions. Moderator edits are written to the
                // post records themselves, so what CloudKit returns already includes
                // them — there's nothing to fold on top here.
                for cloudSubmission in cloudSubmissions {
                    // Locally soft-deleted posts stay hidden from the feeds even if the
                    // CloudKit copy is still approved (e.g. we couldn't write the hidden
                    // state because another account created it). Keep them in the
                    // deleted bucket so the moderator page can still show/restore them.
                    if hiddenSubmissionIDs.contains(cloudSubmission.id) {
                        var hidden = cloudSubmission
                        hidden.isApproved = false
                        if !updatedPending.contains(where: { $0.id == hidden.id }) {
                            updatedPending.append(hidden)
                        }
                        continue
                    }

                    if cloudSubmission.isApproved {
                        // Check if we already have this approved submission
                        if let existingIndex = updatedApproved.firstIndex(where: { $0.id == cloudSubmission.id }) {
                            print("🔄 Updating existing approved submission: \(cloudSubmission.title)")
                            updatedApproved[existingIndex] = cloudSubmission
                        } else {
                            print("📥 Adding new approved submission from CloudKit: \(cloudSubmission.title)")
                            updatedApproved.append(cloudSubmission)
                        }
                    } else {
                        // Check if we already have this pending submission
                        if let existingIndex = updatedPending.firstIndex(where: { $0.id == cloudSubmission.id }) {
                            print("🔄 Updating existing pending submission: \(cloudSubmission.title)")
                            updatedPending[existingIndex] = cloudSubmission
                        } else {
                            print("📥 Adding new pending submission from CloudKit: \(cloudSubmission.title)")
                            updatedPending.append(cloudSubmission)
                        }
                    }
                }
                
                // Reconcile local submissions that aren't in this fetch.
                //
                // A single fetch is NOT authoritative about what's been deleted: the
                // feed query pulls full video/audio assets, and a transient asset
                // download failure (or CloudKit's index lag right after a write, e.g.
                // just after deleting a post) silently drops otherwise-present records
                // from the result. Trusting that to declare a server-side delete is
                // exactly what made whole feeds vanish and then reappear on the next
                // sync. So for ANY locally-cached post missing from the fetch, we keep
                // it for now and verify it per-record with a lightweight `recordExists`
                // lookup (see `reconcileMissingLocalSubmission`), which is immune to the
                // query/asset issues above. Genuine deletes still stick — they just get
                // confirmed one cycle later instead of guessed.
                print("🔍 Reconciling local-only submissions...")
                for localSubmission in submissions {
                    if !cloudSubmissionIDs.contains(localSubmission.id) {
                        // Soft-deleted posts are kept locally (moderator "Deleted"
                        // section) and never re-uploaded, so a deletion can't resurrect.
                        if hiddenSubmissionIDs.contains(localSubmission.id) {
                            if !updatedPending.contains(where: { $0.id == localSubmission.id }) {
                                updatedPending.append(localSubmission)
                            }
                        } else {
                            updatedPending.append(localSubmission)
                            Task { await reconcileMissingLocalSubmission(localSubmission) }
                        }
                    }
                }

                for localApproved in approvedSubmissions {
                    if !cloudSubmissionIDs.contains(localApproved.id) {
                        // A soft-deleted post should never sit in the approved feed.
                        if hiddenSubmissionIDs.contains(localApproved.id) {
                            continue
                        } else {
                            updatedApproved.append(localApproved)
                            Task { await reconcileMissingLocalSubmission(localApproved) }
                        }
                    }
                }

                // Collapse any duplicate IDs so the same post can't render (or persist)
                // multiple times — the reconcile loops above re-append local-only posts
                // without cross-checking each other, so a pre-existing dup would survive.
                submissions = dedupedByID(updatedPending)
                approvedSubmissions = dedupedByID(updatedApproved)
                saveSubmissions()
                saveSyncedRecordIDs()
                
                print("✅ CloudKit sync complete!")
                print("   - Pending: \(submissions.count)")
                print("   - Approved: \(approvedSubmissions.count)")
                print("   - Total: \(submissions.count + approvedSubmissions.count)")

                // 🩺 FEED DIAGNOSTIC: one greppable line that pinpoints why the feed may be
                // empty. Compare `fetched` (what CloudKit returned) against `visible` (what
                // the feed actually shows). If fetched > 0 but visible == 0, posts are being
                // hidden client-side — `moderationHidden` tells you how many the cross-device
                // moderation actions are suppressing. If fetched == 0, it's a fetch/parse
                // issue, not hiding. Search TestFlight console for "FEED DIAGNOSTIC".
                let fetchedHiddenByModeration = cloudSubmissions.filter { hiddenSubmissionIDs.contains($0.id) }.count
                print("🩺 FEED DIAGNOSTIC: fetched=\(cloudSubmissions.count) moderationActions=\(moderationActions.count) hiddenIDs=\(hiddenSubmissionIDs.count) fetchedHiddenByModeration=\(fetchedHiddenByModeration) approved=\(approvedSubmissions.count) visible=\(visibleApprovedSubmissions.count)")
            }
        } catch {
            print("❌ CloudKit sync failed: \(error.localizedDescription)")
            print("❌ Full error: \(error)")
            print("⚠️  Local data preserved, will retry on next sync")
        }
    }

    /// Decides what to do with a locally-cached post that the CloudKit fetch didn't
    /// return and that `syncedRecordIDs` has no record of syncing.
    ///
    /// Instead of blindly re-uploading (which resurrects records deleted straight from
    /// the CloudKit Dashboard) we ask the server directly, then decide:
    ///   - present → it exists after all; record it as synced, no re-upload.
    ///   - absent + created/retried THIS session → a post we're actively trying to
    ///     upload that never finished (e.g. made offline); upload it.
    ///   - absent + not from this session → CloudKit is the master copy and doesn't
    ///     have it, so drop it locally. This covers a post deleted from CloudKit *and* a
    ///     stale local copy left over from a past session/build: neither is resurrected.
    ///   - unknown → couldn't reach CloudKit; leave it alone and let the next sync decide.
    @MainActor
    private func reconcileMissingLocalSubmission(_ submission: Submission) async {
        // Still uploading — absent only because the save hasn't finished yet.
        guard !inFlightUploadIDs.contains(submission.id) else {
            print("⏳ '\(submission.title)' is still uploading — skipping reconcile")
            return
        }
        switch await cloudKitAdapter.recordExists(id: submission.id) {
        case .some(true):
            print("🔎 '\(submission.title)' already exists in CloudKit — marking synced, skipping re-upload")
            syncedRecordIDs.insert(submission.id)
            saveSyncedRecordIDs()
            if pendingUploadIDs.remove(submission.id) != nil {
                savePendingUploadIDs()
            }
        case .some(false):
            // `pendingUploadIDs` is persisted, so it also covers a post whose upload
            // never confirmed in an *earlier* session — previously only the in-memory
            // `sessionUploadIDs` authorized a retry, so after a relaunch such a post
            // was mistaken for a stale local copy and silently deleted. A post that
            // did upload once is removed from `pendingUploadIDs`, so a genuine
            // server-side delete still sticks and nothing is resurrected.
            if sessionUploadIDs.contains(submission.id) || pendingUploadIDs.contains(submission.id) {
                print("⚠️  Pending-upload submission confirmed absent, uploading: \(submission.title)")
                await saveSubmissionToCloudKit(submission)
            } else {
                // Safe in development builds too: local caches are namespaced per
                // CloudKit environment (`CloudKitEnvironmentDetector.localCachePrefix`),
                // so a dev build only ever holds dev posts and can't wipe production ones.
                print("🗑️  '\(submission.title)' is absent from CloudKit (deleted server-side or a stale local copy) — removing locally; CloudKit is the master copy")
                removeSubmissionLocally(submission.id)
            }
        case .none:
            print("⏳ Couldn't confirm '\(submission.title)' in CloudKit — leaving for next sync")
        }
    }


    /// Removes a submission from every local store and clears its tracking state.
    /// Used when reconciliation determines a post was deleted server-side.
    @MainActor
    private func removeSubmissionLocally(_ id: UUID) {
        submissions.removeAll { $0.id == id }
        approvedSubmissions.removeAll { $0.id == id }
        syncedRecordIDs.remove(id)
        sessionUploadIDs.remove(id)
        if pendingUploadIDs.remove(id) != nil {
            savePendingUploadIDs()
        }
        saveSubmissions()
        saveSyncedRecordIDs()
    }


    /// Save a submission to CloudKit.
    ///
    /// Pass `trackProgress: true` for interactive posts so the submission form can
    /// show a live upload wheel → checkmark (or an error + Retry). Background saves
    /// (approve/restore/hide/sync) leave it `false` and stay invisible.
    ///
    /// Pass `preservingOwner: true` when writing a post this account didn't create (a
    /// moderator editing someone else's submission). It leaves the record's `userID`
    /// key unwritten so the save doesn't reassign the post to the moderator, and keeps
    /// the owner's cached media on disk instead of clearing it as a finished upload.
    @MainActor
    func saveSubmissionToCloudKit(
        _ submission: Submission,
        trackProgress: Bool = false,
        preservingOwner: Bool = false
    ) async {
        if trackProgress {
            UploadProgressCenter.shared.begin(submission.id, title: submission.title, type: submission.type)
        }
        print("🌐 ========================================")
        print("🌐 CLOUDKIT SAVE DIAGNOSTICS")
        print("🌐 ========================================")
        print("🌐 Submission Title: \(submission.title)")
        print("🌐 Submission ID: \(submission.id)")
        print("🌐 Submission Type: \(submission.type.rawValue)")
        print("🌐 Is Approved: \(submission.isApproved)")
        print("🌐 Submitted By: \(submission.submittedBy)")
        print("🌐 Video File Name: \(submission.videoFileName ?? "none")")
        print("🌐 Audio File Name: \(submission.audioFileName ?? "none")")
        print("🌐 CloudKit Available: \(cloudKitAdapter.isAvailable)")
        
        guard cloudKitAdapter.isAvailable else {
            print("❌ ========================================")
            print("❌ CLOUDKIT NOT AVAILABLE")
            print("❌ ========================================")
            print("❌ Submission saved LOCALLY ONLY")
            print("❌ Other users will NOT see this post")
            print("❌ ")
            print("❌ Possible reasons:")
            print("❌ 1. Not signed into iCloud")
            print("❌    → Go to Settings > [Your Name] > iCloud")
            print("❌ 2. No internet connection")
            print("❌    → Check your network connection")
            print("❌ 3. CloudKit container not configured")
            print("❌    → Check Xcode project settings")
            print("❌ 4. CloudKit permissions not granted")
            print("❌    → Check app permissions in Settings")
            print("❌ ========================================")
            // Reported whether or not a form is on screen: a background save that
            // fails silently leaves a post that a later sync will drop as "absent
            // from CloudKit", with nothing ever telling the user why.
            UploadProgressCenter.shared.fail(
                submission.id,
                title: submission.title,
                type: submission.type,
                message: "iCloud isn't available. Make sure you're signed into iCloud and connected to the internet, then try again."
            )
            return
        }

        inFlightUploadIDs.insert(submission.id)
        defer { inFlightUploadIDs.remove(submission.id) }

        print("✅ CloudKit is available, proceeding with save...")
        print("🚀 Calling cloudKitAdapter.saveSubmission()...")
        print("🎬 This will convert to typed model (\(submission.type.rawValue)) and upload media assets")
        
        do {
            try await cloudKitAdapter.saveSubmission(submission, preservingOwner: preservingOwner)
            // Confirmed in CloudKit — so if it later disappears from a fetch, we know
            // it was deleted server-side (not just still-uploading) and can remove it.
            syncedRecordIDs.insert(submission.id)
            saveSyncedRecordIDs()
            // The upload succeeded, so the local upload copy is now redundant — CloudKit
            // is the source of truth and it re-downloads on demand like any other post.
            // Delete it so a poster's own uploads don't accumulate on disk. Skipped when
            // editing someone else's post: any file under those names is this device's
            // download cache, not an upload copy of ours to clean up.
            if !preservingOwner {
                if let name = submission.videoFileName { FileManager.default.removeMediaFile(named: name) }
                if let name = submission.audioFileName { FileManager.default.removeMediaFile(named: name) }
                for name in submission.musicTrackFileNames ?? [] {
                    FileManager.default.removeMediaFile(named: name)
                }
            }
            // Upload confirmed, so it's no longer awaiting one. (On failure we leave it
            // in the set so the current session retries instead of dropping it.)
            sessionUploadIDs.remove(submission.id)
            if pendingUploadIDs.remove(submission.id) != nil {
                savePendingUploadIDs()
            }
            if trackProgress {
                UploadProgressCenter.shared.finish(submission.id)
            }
            print("✅ ========================================")
            print("✅ CLOUDKIT SAVE SUCCESSFUL")
            print("✅ ========================================")
            print("✅ Submission: \(submission.title)")
            print("✅ Saved to CloudKit successfully")
            print("✅ Video/Audio assets uploaded")
            print("✅ Other users should now see this post")
            print("✅ ========================================")
        } catch {
            print("❌ ========================================")
            print("❌ CLOUDKIT SAVE FAILED")
            print("❌ ========================================")
            print("❌ Submission: \(submission.title)")
            print("❌ Error Type: \(type(of: error))")
            print("❌ Error Description: \(error.localizedDescription)")
            print("❌ Full Error: \(error)")
            print("❌ ")
            print("❌ Common causes:")
            print("❌ 1. Schema not created in CloudKit Dashboard")
            print("❌ 2. Missing required fields")
            print("❌ 3. Network connectivity issues")
            print("❌ 4. CloudKit quota exceeded")
            print("❌ 5. Video file too large (>250MB)")
            print("❌ ")
            print("❌ Action: Submission saved locally")
            print("❌ Will retry on next sync")
            print("❌ ========================================")
            // Reported whether or not a form is on screen (see the availability guard
            // above), so a failed background save surfaces in the Home banner with a
            // Retry instead of the post quietly disappearing on a later sync.
            //
            // A moderator's edit of someone else's post is rejected outright when the
            // record type doesn't grant authenticated users Write permission, and
            // retrying can't fix that — so say so rather than offering the usual
            // "saved on this device, tap Retry" (which is about the user's OWN upload).
            let isPermissionRejection = (error as? CKError)?.code == .permissionFailure
            let message = isPermissionRejection && preservingOwner
                ? "iCloud won't let this account change another person's post. The edit is saved on this device only."
                : "\(error.localizedDescription) Your post was saved on this device — tap Retry to upload it."
            UploadProgressCenter.shared.fail(
                submission.id,
                title: submission.title,
                type: submission.type,
                message: message
            )
            // Submission is still saved locally, will retry on next sync
        }
    }

    /// Re-runs the CloudKit upload for a submission that failed mid-post, keeping the
    /// progress indicator live. The submission is already saved locally by `add`.
    @MainActor
    func retryUpload(_ submission: Submission) {
        // Flip the tracked state back to "uploading" immediately so the UI reacts
        // before the async save starts reporting progress.
        UploadProgressCenter.shared.begin(submission.id, title: submission.title, type: submission.type)
        // An explicit retry re-authorizes this post for upload in the current session.
        pendingUploadIDs.insert(submission.id)
        savePendingUploadIDs()
        sessionUploadIDs.insert(submission.id)
        Task {
            await saveSubmissionToCloudKit(submission, trackProgress: true)
        }
    }

    /// Retries a failed upload by submission ID (used by the Home-feed banner, which
    /// only knows the ID). No-op if the submission isn't found locally.
    @MainActor
    func retryUpload(id: UUID) {
        guard let submission = approvedSubmissions.first(where: { $0.id == id }) else { return }
        retryUpload(submission)
    }

    /// Delete a submission from CloudKit. Returns `true` if the record was removed
    /// server-side, `false` if CloudKit was unavailable or the delete failed (e.g. the
    /// record belongs to another account and can't be deleted from here).
    @MainActor
    @discardableResult
    func deleteSubmissionFromCloudKit(_ submission: Submission) async -> Bool {
        guard cloudKitAdapter.isAvailable else {
            print("⚠️ CloudKit not available")
            return false
        }

        do {
            try await cloudKitAdapter.deleteSubmission(submission)
            print("✅ Deleted submission from CloudKit: \(submission.title)")
            return true
        } catch {
            print("❌ Failed to delete from CloudKit: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Force a manual sync - useful for debugging or refresh actions
    @MainActor
    func forceSyncWithCloudKit() async {
        print("🔄 Force sync triggered by user")
        await syncWithCloudKit()
    }

    /// Purges the legacy placeholder posts from local storage and CloudKit.
    ///
    /// The app already filters these out on load/sync, but this actively deletes the
    /// records from the public database (best-effort — a record can only be deleted
    /// by the iCloud account that created it) so they're gone for everyone.
    /// Returns the number of records successfully deleted from CloudKit.
    @MainActor
    @discardableResult
    func removePlaceholderPosts() async -> Int {
        // Remove locally and persist so they disappear immediately.
        submissions.removeAll { $0.isPlaceholder }
        approvedSubmissions.removeAll { $0.isPlaceholder }
        saveSubmissions()

        // Delete each known placeholder record from CloudKit by its fixed ID.
        var deleted = 0
        for id in Submission.placeholderIDs {
            let recordID = CKRecord.ID(recordName: id.uuidString)
            do {
                try await CloudKitManager.shared.delete(recordID: recordID)
                deleted += 1
                print("✅ Purged placeholder \(id.uuidString) from CloudKit")
            } catch {
                print("⚠️ Could not purge placeholder \(id.uuidString): \(error.localizedDescription)")
            }
        }
        return deleted
    }
    
    /// Setup automatic background sync
    @MainActor
    private func setupAutomaticSync() async {
        await CloudKitManager.shared.setupAutomaticSync()
    }
    
    /// Called when receiving CloudKit notifications
    @MainActor
    func handleCloudKitNotification() async {
        print("🔔 CloudKit notification received - syncing...")
        await syncWithCloudKit()
        // A feed push is the moment a connection's new post lands; tell the user.
        ConnectionsManager.shared.noticeNewPosts(
            approvedSubmissions,
            directory: UserProfileManager.shared.allUsers
        )
        // A project push may be a new casting or crew call: tell the people whose
        // tags match its open roles (visible list, so school scope already applies).
        await RoleCallNotifier.noticeOpenRoles(in: visibleApprovedSubmissions)
    }
}

