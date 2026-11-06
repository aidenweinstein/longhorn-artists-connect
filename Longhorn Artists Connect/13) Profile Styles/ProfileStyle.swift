//
//  ProfileStyle.swift
//  Longhorn Artists Connect
//
//  The base profile style every artist picks: Filmmaker, Actor or Musician.
//
//  The style decides three things:
//  1. What Nexus recommends (`recommend(_:)` leads the Home feed with that kind of work).
//  2. What the Now page in Discover shows (sets and crew calls, auditions and roles,
//     or scoring work, gigs, open mics and jams). See NowView.swift.
//  3. How the profile looks to everyone: an Actors Access style headshot, reel and
//     resume; an IMDb style filmography with stills; or a Spotify style discography.
//     See StyledProfileSection.swift.
//
//  A profile only appears on the public Actors / Filmmakers / Musicians pages after a
//  moderator approves it (see CreativeProfileStore and CreativeDirectoryView).
//
//  Separate from the `UserType` role tags: someone tagged Director and Composer still
//  picks one base style here. Their tags keep driving crew-call matching.
//

import SwiftUI
import Foundation

// MARK: - Profile Style

enum ProfileStyle: String, CaseIterable, Identifiable, Codable, Hashable {
    case filmmaker = "Filmmaker"
    case actor = "Actor"
    case musician = "Musician"

    var id: String { rawValue }

    /// The public page's name ("Actors").
    var plural: String {
        switch self {
        case .filmmaker: return "Filmmakers"
        case .actor: return "Actors"
        case .musician: return "Musicians"
        }
    }

    /// SF Symbol for the style.
    var symbol: String {
        switch self {
        case .filmmaker: return "film"
        case .actor: return "theatermasks"
        case .musician: return "music.note"
        }
    }

    /// One line on what picking this style gets you.
    var pitch: String {
        switch self {
        case .filmmaker:
            return "IMDb-style credits and stills. See the sets you're on and the crews you could join."
        case .actor:
            return "Headshot, reel and resume. Track your auditions and find roles that fit you."
        case .musician:
            return "A discography of your releases. Find scoring work, gigs, open mics and jams."
        }
    }

    /// UserDefaults / `@AppStorage` key for the signed-in account's style.
    static let storageKey = "profileStyle"

    /// The signed-in account's style, or nil before they pick one.
    static var current: ProfileStyle? {
        ProfileStyle(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "")
    }

    /// A starting suggestion from someone's role tags, used to preselect a style.
    static func suggested(for tags: Set<UserType>) -> ProfileStyle? {
        if tags.contains(.actor) || tags.contains(.dancer) { return .actor }
        if tags.contains(.musician) || tags.contains(.singer) || tags.contains(.composer) { return .musician }
        let film: Set<UserType> = [.director, .producer, .writer, .editor, .cinematographer,
                                   .soundMixer, .animator, .vfxArtist]
        if !tags.isDisjoint(with: film) { return .filmmaker }
        return nil
    }

    // MARK: Recommendations

    /// Whether a feed post is the kind of work this style is about.
    func prefers(_ post: Submission) -> Bool {
        let reel = post.reelType.lowercased()
        switch self {
        case .filmmaker:
            return post.type == .film
                || (post.type == .reel && Self.containsAny(reel, ["cinemat", "edit", "direct", "film", "writ", "produc", "anim", "vfx"]))
        case .actor:
            return post.type == .film
                || (post.type == .reel && Self.containsAny(reel, ["act", "perform", "theat", "danc", "choreo", "monolog", "comed"]))
        case .musician:
            return post.type == .music
                || (post.type == .reel && Self.containsAny(reel, ["music", "compos", "sound", "sing", "vocal", "instrument"]))
        }
    }

    /// Reorders an already-ranked feed so this style's kind of work leads: up to three
    /// preferred posts, then one other, repeating. Each group keeps its ranked order, so
    /// the recommender's like/seen ordering still applies within it and nothing is dropped.
    func recommend(_ ranked: [Submission]) -> [Submission] {
        var preferred: [Submission] = []
        var other: [Submission] = []
        for post in ranked {
            if prefers(post) { preferred.append(post) } else { other.append(post) }
        }
        var result: [Submission] = []
        result.reserveCapacity(ranked.count)
        var p = 0
        var o = 0
        while p < preferred.count || o < other.count {
            var taken = 0
            while taken < 3 && p < preferred.count {
                result.append(preferred[p])
                p += 1
                taken += 1
            }
            if o < other.count {
                result.append(other[o])
                o += 1
            }
        }
        return result
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

// MARK: - Style Details

/// One line on an actor's resume that isn't a post on Nexus (a play, a commercial,
/// a student film from before they joined).
struct ResumeCredit: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var category: String = "Film"
    var project: String = ""
    var role: String = ""
    /// Director, theatre or production company.
    var company: String = ""
    var year: String = ""

    static let categories = ["Film", "Television", "Theatre", "Commercial", "New Media", "Other"]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "Film"
        project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        company = try c.decodeIfPresent(String.self, forKey: .company) ?? ""
        year = try c.decodeIfPresent(String.self, forKey: .year) ?? ""
    }
}

/// What an actor's page shows besides their credits on Nexus — the Actors Access sheet.
/// Every field is optional; decoding tolerates missing keys so later fields never
/// break profiles saved by older builds.
struct ActorDetails: Codable, Equatable {
    /// Playable age range.
    var ageMin: Int?
    var ageMax: Int?
    var gender: String = ""
    var height: String = ""
    var ethnicAppearance: String = ""
    var hair: String = ""
    var eyes: String = ""
    var union: String = ""
    var basedIn: String = ""
    var languages: String = ""
    var specialSkills: String = ""
    var training: String = ""
    /// UUID string of the Performance (reel) or Film post used as their reel.
    var reelPostID: String?
    /// Credits that aren't posts on Nexus.
    var resume: [ResumeCredit] = []

    static let genders = ["Female", "Male", "Non-binary"]
    static let unions = ["Non-union", "SAG-AFTRA Eligible", "SAG-AFTRA", "AEA"]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ageMin = try c.decodeIfPresent(Int.self, forKey: .ageMin)
        ageMax = try c.decodeIfPresent(Int.self, forKey: .ageMax)
        gender = try c.decodeIfPresent(String.self, forKey: .gender) ?? ""
        height = try c.decodeIfPresent(String.self, forKey: .height) ?? ""
        ethnicAppearance = try c.decodeIfPresent(String.self, forKey: .ethnicAppearance) ?? ""
        hair = try c.decodeIfPresent(String.self, forKey: .hair) ?? ""
        eyes = try c.decodeIfPresent(String.self, forKey: .eyes) ?? ""
        union = try c.decodeIfPresent(String.self, forKey: .union) ?? ""
        basedIn = try c.decodeIfPresent(String.self, forKey: .basedIn) ?? ""
        languages = try c.decodeIfPresent(String.self, forKey: .languages) ?? ""
        specialSkills = try c.decodeIfPresent(String.self, forKey: .specialSkills) ?? ""
        training = try c.decodeIfPresent(String.self, forKey: .training) ?? ""
        reelPostID = try c.decodeIfPresent(String.self, forKey: .reelPostID)
        resume = try c.decodeIfPresent([ResumeCredit].self, forKey: .resume) ?? []
    }

    /// "18–25", "20+", or "" when unset.
    var ageRangeText: String {
        switch (ageMin, ageMax) {
        case let (min?, max?): return min == max ? "\(min)" : "\(min)–\(max)"
        case let (min?, nil): return "\(min)+"
        case let (nil, max?): return "Up to \(max)"
        default: return ""
        }
    }

    /// The label/value rows shown beside the headshot, skipping blanks.
    var statRows: [(label: String, value: String)] {
        [("Age range", ageRangeText), ("Gender", gender), ("Height", height),
         ("Ethnic appearance", ethnicAppearance), ("Hair", hair), ("Eyes", eyes),
         ("Union", union), ("Based in", basedIn)]
            .filter { !$0.1.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { (label: $0.0, value: $0.1) }
    }

    /// True once the details that role matching reads are filled in.
    var hasMatchingBasics: Bool {
        (ageMin != nil || ageMax != nil) && !gender.isEmpty
    }
}

/// The extra lines on a musician's page.
struct MusicianDetails: Codable, Equatable {
    /// Stage or band name, when it differs from their own name.
    var artistName: String = ""
    var instruments: String = ""
    var genres: String = ""
    var availableForSessions: Bool = false
    var availableForGigs: Bool = true
    var availableForScoring: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artistName = try c.decodeIfPresent(String.self, forKey: .artistName) ?? ""
        instruments = try c.decodeIfPresent(String.self, forKey: .instruments) ?? ""
        genres = try c.decodeIfPresent(String.self, forKey: .genres) ?? ""
        availableForSessions = try c.decodeIfPresent(Bool.self, forKey: .availableForSessions) ?? false
        availableForGigs = try c.decodeIfPresent(Bool.self, forKey: .availableForGigs) ?? true
        availableForScoring = try c.decodeIfPresent(Bool.self, forKey: .availableForScoring) ?? false
    }

    var availability: [String] {
        var items: [String] = []
        if availableForGigs { items.append("Live gigs") }
        if availableForSessions { items.append("Session work") }
        if availableForScoring { items.append("Scoring") }
        return items
    }
}

/// The extra lines on a filmmaker's page.
struct FilmmakerDetails: Codable, Equatable {
    var specialties: String = ""
    var gear: String = ""
    var openToCrew: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        specialties = try c.decodeIfPresent(String.self, forKey: .specialties) ?? ""
        gear = try c.decodeIfPresent(String.self, forKey: .gear) ?? ""
        openToCrew = try c.decodeIfPresent(Bool.self, forKey: .openToCrew) ?? true
    }
}

/// Every style's details, saved together as one JSON string so switching style never
/// throws away what was typed for another one.
struct CreativeDetails: Codable, Equatable {
    var actor = ActorDetails()
    var musician = MusicianDetails()
    var filmmaker = FilmmakerDetails()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        actor = try c.decodeIfPresent(ActorDetails.self, forKey: .actor) ?? ActorDetails()
        musician = try c.decodeIfPresent(MusicianDetails.self, forKey: .musician) ?? MusicianDetails()
        filmmaker = try c.decodeIfPresent(FilmmakerDetails.self, forKey: .filmmaker) ?? FilmmakerDetails()
    }

    var jsonString: String {
        guard let data = try? JSONEncoder().encode(self) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decode(_ string: String?) -> CreativeDetails {
        guard let data = string?.data(using: .utf8),
              let details = try? JSONDecoder().decode(CreativeDetails.self, from: data) else {
            return CreativeDetails()
        }
        return details
    }
}

// MARK: - Synced Records

/// Someone's style and details as stored in their `CreativeProfile` record.
struct CreativeProfile: Identifiable, Equatable {
    /// Raw iCloud user record name — the same ID as `DirectoryUser.messagingUserID`.
    let userID: String
    var style: ProfileStyle
    var details: CreativeDetails
    /// Local copy of the headshot asset, when there is one.
    var headshotFileURL: URL?
    var updatedAt: Date

    var id: String { userID }
}

/// A moderator's decision on whether a profile appears on its style's public page.
/// Moderator-owned, like `ModerationAction`, because only a record's creator can
/// modify it in the public database.
struct DirectoryListing: Equatable {
    enum Status: String {
        case approved
        case declined
    }

    let userID: String
    /// The style the decision was made for. Switching style sends the profile back
    /// to the review queue.
    let style: ProfileStyle
    let status: Status
    let modifiedAt: Date
}

// MARK: - Cast Role Matching

/// What a casting call line asks for, read from the poster's free-form wording —
/// e.g. "Rosa (F, 18–25, Latina, Spanish-speaking)" or "Danny — male, early 20s, plays guitar".
/// Anything the line doesn't mention isn't required.
struct CastRoleRequirements {
    var gender: String?
    var ageMin: Int?
    var ageMax: Int?
    /// Ethnicity groups the line mentions (each group is its synonyms).
    var ethnicityGroups: [[String]] = []
    /// Skills the line mentions, by display label.
    var skills: [String] = []

    init(wording: String) {
        let text = " " + wording.lowercased() + " "

        if Self.matches(text, "\\b(non[- ]?binary|enby)\\b") {
            gender = "Non-binary"
        } else if Self.matches(text, "\\b(female|woman|women|girl|actress|she/her)\\b")
                    || Self.matches(text, "[\\s(,/]f[\\s),/]") {
            gender = "Female"
        } else if Self.matches(text, "\\b(male|man|men|boy|he/him)\\b")
                    || Self.matches(text, "[\\s(,/]m[\\s),/]") {
            gender = "Male"
        }

        (ageMin, ageMax) = Self.ages(in: text)

        for group in Self.ethnicityTable where group.contains(where: { Self.matches(text, "\\b\($0)\\b") }) {
            ethnicityGroups.append(group)
        }

        for skill in Self.skillTable where Self.matches(text, skill.pattern) {
            skills.append(skill.label)
        }
    }

    /// Short chips describing the requirements ("Female", "18–25", "Spanish").
    var summary: [String] {
        var chips: [String] = []
        if let gender { chips.append(gender) }
        switch (ageMin, ageMax) {
        case let (min?, max?): chips.append("\(min)–\(max)")
        case let (min?, nil): chips.append("\(min)+")
        default: break
        }
        chips += ethnicityGroups.compactMap { $0.first?.capitalized }
        chips += skills
        return chips
    }

    /// Whether an actor could play this. Details the actor left blank don't rule them
    /// out (so a half-finished profile still sees roles), except skills: a role that
    /// needs guitar only matches someone who listed it.
    func fits(_ actor: ActorDetails) -> Bool {
        if let gender, !actor.gender.isEmpty, actor.gender.lowercased() != gender.lowercased() {
            return false
        }
        if ageMin != nil || ageMax != nil, actor.ageMin != nil || actor.ageMax != nil {
            let low = actor.ageMin ?? actor.ageMax ?? 0
            let high = actor.ageMax ?? actor.ageMin ?? 200
            if high < (ageMin ?? 0) || low > (ageMax ?? 200) { return false }
        }
        let look = actor.ethnicAppearance.lowercased()
        if !ethnicityGroups.isEmpty, !look.isEmpty {
            let any = ethnicityGroups.contains { group in group.contains { look.contains($0) } }
            if !any { return false }
        }
        if !skills.isEmpty {
            let have = (actor.specialSkills + " " + actor.languages).lowercased()
            for label in skills {
                guard let skill = Self.skillTable.first(where: { $0.label == label }) else { continue }
                if !skill.stems.contains(where: { have.contains($0) }) { return false }
            }
        }
        return true
    }

    // MARK: Parsing helpers

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Capture groups of the first match of `pattern`, or nil.
    private static func captures(_ text: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let r = match.range(at: index)
            guard r.location != NSNotFound, let swiftRange = Range(r, in: text) else { return "" }
            return String(text[swiftRange])
        }
    }

    private static func ages(in text: String) -> (Int?, Int?) {
        // "18-25", "18–25", "18 to 25"
        if let c = captures(text, "\\b(\\d{1,2})\\s*(?:-|–|—|to)\\s*(\\d{1,2})\\b"),
           let low = Int(c[1]), let high = Int(c[2]), low >= 5, high <= 99, low <= high {
            return (low, high)
        }
        // "early 20s", "mid-30s", "20s"
        if let c = captures(text, "\\b(early|mid|late)?[\\s-]*(\\d)0'?s\\b"), let decade = Int(c[2]) {
            let base = decade * 10
            switch c[1] {
            case "early": return (base, base + 4)
            case "mid": return (base + 3, base + 7)
            case "late": return (base + 6, base + 9)
            default: return (base, base + 9)
            }
        }
        // "25+"
        if let c = captures(text, "\\b(\\d{2})\\s*\\+"), let low = Int(c[1]) {
            return (low, nil)
        }
        // "22 years old", "22yo", "age 22"
        if let c = captures(text, "\\b(\\d{2})\\s*(?:yo|y/o|years? old)\\b"), let age = Int(c[1]) {
            return (age - 2, age + 2)
        }
        if let c = captures(text, "\\bage\\s*(\\d{2})\\b"), let age = Int(c[1]) {
            return (age - 2, age + 2)
        }
        if matches(text, "\\bteens?\\b|\\bteenager") {
            return (13, 19)
        }
        return (nil, nil)
    }

    /// Synonym groups; the first entry is the chip label.
    private static let ethnicityTable: [[String]] = [
        ["latina", "latino", "latinx", "latine", "hispanic"],
        ["black", "african american"],
        ["asian", "east asian", "south asian", "southeast asian"],
        ["white", "caucasian"],
        ["middle eastern", "arab"],
        ["indigenous", "native american"],
        ["pacific islander"],
        ["biracial", "multiracial"],
    ]

    /// Skills a role line can ask for: how to spot it in the role, and the stems that
    /// count as having it in the actor's skills / languages.
    private static let skillTable: [(label: String, pattern: String, stems: [String])] = [
        ("Singing", "\\b(sing|sings|singing|singer|vocals?)\\b", ["sing", "vocal"]),
        ("Dance", "\\b(dance|dances|dancer|dancing)\\b", ["danc", "ballet", "tap", "hip hop", "hip-hop"]),
        ("Guitar", "\\bguitar", ["guitar"]),
        ("Piano", "\\b(piano|keys|keyboard)\\b", ["piano", "keys", "keyboard"]),
        ("Drums", "\\bdrum", ["drum"]),
        ("Violin", "\\bviolin", ["violin"]),
        ("Spanish", "\\bspanish", ["spanish"]),
        ("French", "\\bfrench\\b", ["french"]),
        ("Mandarin", "\\bmandarin", ["mandarin", "chinese"]),
        ("Cantonese", "\\bcantonese", ["cantonese"]),
        ("Japanese", "\\bjapanese", ["japanese"]),
        ("Korean", "\\bkorean", ["korean"]),
        ("German", "\\bgerman\\b", ["german"]),
        ("Italian", "\\bitalian", ["italian"]),
        ("Portuguese", "\\bportuguese", ["portuguese"]),
        ("Arabic", "\\barabic", ["arabic"]),
        ("Hindi", "\\bhindi", ["hindi"]),
        ("ASL", "\\b(asl|sign language)\\b", ["asl", "sign language"]),
        ("Stunts", "\\bstunts?\\b", ["stunt"]),
        ("Stage combat", "\\b(stage combat|fight choreography|combat)\\b", ["combat", "fight"]),
        ("Martial arts", "\\b(martial arts?|karate|kung fu|taekwondo|jiu[- ]?jitsu)\\b", ["martial", "karate", "kung fu", "taekwondo", "jitsu"]),
        ("Skateboarding", "\\bskat(e|ing|eboard)", ["skate"]),
        ("Horseback riding", "\\b(horse|horseback|equestrian)", ["horse", "equestrian"]),
        ("Improv", "\\bimprov", ["improv"]),
        ("Juggling", "\\bjuggl", ["juggl"]),
        ("Swimming", "\\bswim", ["swim"]),
    ]
}

// MARK: - Credit Helpers

extension Submission {
    /// A post's year for credit lists: its release year when set, else the year it was posted.
    var creditYear: String {
        let year = releaseYear.trimmingCharacters(in: .whitespaces)
        if year.count == 4, Int(year) != nil { return year }
        return String(Calendar.current.component(.year, from: createdDate))
    }

    /// An event's category ("Concert", "Showcase"…). The feed model keeps it as the
    /// first genre (see `CloudKitTransitionAdapter`).
    var eventCategoryName: String {
        type == .event ? (genres.first ?? "") : ""
    }

    /// Whether an event is still to come (or running now).
    var isUpcomingEvent: Bool {
        guard type == .event, let start = eventStartDate else { return false }
        return (eventEndDate ?? start) >= Calendar.current.startOfDay(for: Date())
    }

    /// Whether `isPerson` appears in any credit list on this post.
    func credits(where isPerson: (OrderedEntry) -> Bool) -> [OrderedEntry] {
        creditEntries.filter(isPerson)
    }
}

/// Builds the "is this credit that person" check used across the profile-style
/// screens: the linked profile when the credit has one, otherwise the name.
enum PersonMatcher {
    static func make(name: String, profileID: String?) -> (OrderedEntry) -> Bool {
        let key = Collaborator.nameKey(for: name)
        let id = Collaborator.normalizedProfileID(profileID)
        return { entry in
            if let id, let entryID = Collaborator.normalizedProfileID(entry.profileID) {
                return entryID == id
            }
            return !key.isEmpty && Collaborator.nameKey(for: entry.name) == key
        }
    }
}
