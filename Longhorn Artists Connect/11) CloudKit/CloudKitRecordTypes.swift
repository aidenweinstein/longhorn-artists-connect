//
//  CloudKitRecordTypes.swift
//  Longhorn Artists Connect
//
//  Single source of truth for every CloudKit record type name.
//

import Foundation

/// Every record type name in the public CloudKit database, in one place.
///
/// A record type name is a string that has to agree across four places the
/// compiler cannot check for you:
///
/// 1. this app,
/// 2. the CloudKit Dashboard schema, in **both** the Development and
///    Production environments,
/// 3. `verification-service/` (`src/sweep.ts`, `src/backfill.ts`),
/// 4. `backend/migration/` (`src/mapping.ts`, `src/export.ts`).
///
/// When they disagree the failure is silent: a query against a type that does
/// not exist in the current environment returns an error the feed paths
/// swallow, and a save naming an unknown type is dropped. Both look like
/// "the post flashed and vanished".
///
/// Editing this file does **not** change the schema. Adding a case here is a
/// note to yourself to go create the type in the Dashboard in both
/// environments; the app cannot create record types at runtime.
enum CloudKitRecordTypes {

    // MARK: - Submissions (one per Share tab content type)

    static let film = "FilmSubmission"
    static let music = "MusicSubmission"
    static let reel = "ReelSubmission"
    static let project = "ProjectSubmission"
    static let event = "EventSubmission"
    static let photography = "PhotographySubmission"
    static let design = "DesignSubmission"

    /// The original single record type, from before submissions were split by
    /// content type. Still read so that pre-split posts stay visible; nothing
    /// writes it any more.
    static let legacySubmission = "Submission"

    // MARK: - Post metadata

    static let postLike = "PostLike"

    /// Moderator removals. A parallel record rather than an edit to the post,
    /// because in the public database only a record's creator may modify it.
    static let moderationAction = "ModerationAction"

    /// Moderator field overrides, applied on top of a post at read time.
    /// Being phased out in favour of editing the post record directly.
    static let moderationEdit = "ModerationEdit"

    /// User reports of a post.
    static let flag = "Flag"

    // MARK: - People

    static let userProfile = "UserProfile"

    /// Written by the verification service, never by the app.
    static let verification = "Verification"

    /// A person's profile style (Filmmaker / Actor / Musician), its details JSON and
    /// an actor's headshot. Written only by its owner. See `CreativeProfileStore`.
    /// Added 2026-11-04.
    static let creativeProfile = "CreativeProfile"

    /// Moderator decision putting a profile on (or off) its style's public page.
    /// Moderator-owned, like `ModerationAction`. Added 2026-11-04.
    static let directoryListing = "DirectoryListing"

    // MARK: - Scripts

    /// A script in the Script Collection (see `ScriptManager`). Not reachable
    /// from the tab bar since Agent mode was removed on 2026-10-16.
    static let script = "Script"

    // MARK: - Organizations

    static let organization = "Organization"
    static let orgContentLink = "OrgContentLink"

    // MARK: - Messaging

    static let conversation = "Conversation"
    static let message = "Message"

    // MARK: - Connections

    /// One directed edge of a private, mutual connection (`fromUserID` →
    /// `toUserID`). Written only by its sender; see `ConnectionsManager` for the
    /// two-edge model and the field list. Added 2026-10-23.
    static let connection = "Connection"

    // MARK: - Groups

    /// The seven types a new post can be written as. This is the list that
    /// feed fetches fan out over, and the list `schoolID` has to exist on.
    static let liveSubmissions = [
        film,
        music,
        reel,
        project,
        event,
        photography,
        design,
    ]

    /// Every type that holds a post, including the legacy one. Read paths want
    /// this; write paths want `liveSubmissions`.
    static let allSubmissions = liveSubmissions + [legacySubmission]

    static let postMetadata = [
        postLike,
        moderationAction,
        moderationEdit,
        flag,
    ]

    static let people = [
        userProfile,
        verification,
        creativeProfile,
        directoryListing,
    ]

    static let organizations = [
        organization,
        orgContentLink,
    ]

    static let messaging = [
        conversation,
        message,
    ]

    /// Every record type the app touches. Use this when auditing the schema
    /// against the Dashboard.
    static let all = allSubmissions + postMetadata + people + [script] + organizations + messaging
}

// MARK: - Schema status
//
// Last checked 2026-09-25. This table is hand-maintained — it records what was
// true at that date, not what the Dashboard says right now. Verify before
// relying on a row. `schoolID` (queryable) exists on all seven *Submission
// types in both environments as of 2026-09-25.
//
// | Record type           | Development | Production | Note                            |
// |-----------------------|-------------|------------|---------------------------------|
// | FilmSubmission        | yes         | yes        | `filmReleaseYear` (added 2026-09-25) missing in both |
// | MusicSubmission       | yes         | yes        | `musicTracks`/`musicTrackExts`, `musicReleaseYear` missing in both |
// | ReelSubmission        | yes         | yes        | `reelArtist`, `featuredWorkManual`, `reelVideoDuration`, `reelReleaseYear` missing in both |
// | ProjectSubmission     | yes         | yes        | `projectSlides`, `projectAuditionURL`, `projectContacts` (added 2026-09-29), `projectStudio` (added 2026-10-17) missing in both |
// | EventSubmission       | yes         | yes        | `eventShowtimes` missing in both |
// | PhotographySubmission | yes         | yes        |                                 |
// | DesignSubmission      | yes         | yes        | queryable since 2026-09-25; field types unverified until a real post |
// | Submission            | yes         | yes        | legacy, read-only               |
// | PostLike              | yes         | yes        |                                 |
// | ModerationAction      | yes         | yes        |                                 |
// | ModerationEdit        | yes         | yes        | being phased out                |
// | Flag                  | NO          | NO         | reports fail silently until created |
// | UserProfile           | yes         | yes        |                                 |
// | Verification          | server-owned| server-owned| Authenticated = Read, writes reserved to the service key |
// | Script                | NO          | NO         | added 2026-09-29; fields listed on `ScriptManager` |
// | Organization          | yes         | yes        |                                 |
// | OrgContentLink        | yes         | yes        |                                 |
// | Conversation          | yes         | yes        |                                 |
// | Message               | yes         | yes        |                                 |
// | Connection            | NO          | NO         | added 2026-10-23; fields on `ConnectionsManager`. Connect buttons fail silently until created |
// | CreativeProfile       | NO          | NO         | added 2026-11-04; style, details (STRING), headshot (ASSET), updatedAt (DATE). Needs recordName QUERYABLE |
// | DirectoryListing      | NO          | NO         | added 2026-11-04; userID, style, status (STRING), modifiedAt (DATE). Needs recordName QUERYABLE |
//
// Cross-service lists that must stay in step with `liveSubmissions` above:
//
// - `verification-service/src/sweep.ts` — the seven types plus `Submission`.
// - `verification-service/src/backfill.ts` — the seven types only. Omitting
//   `Submission` is deliberate: the legacy read path does not filter by school.
// - `backend/migration/src/mapping.ts` — maps all of them onto one `posts`
//   table.
