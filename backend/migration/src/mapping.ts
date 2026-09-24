/**
 * CloudKit record -> Postgres row transforms.
 *
 * Field names were taken from the writers/parsers in MediaModels.swift,
 * MessageRecordHandling.swift and UserProfileManager.swift. Where the app reads a
 * field it never writes (e.g. the legacy `eventLocation`), the transform reads
 * both and prefers the current one.
 */

import {
    type CKAssetValue,
    type CKRecord,
    asset,
    assetList,
    bool,
    createdAt,
    creatorUserRecordName,
    date,
    num,
    str,
    strList,
    strOrNull,
} from './cloudkit.js';

export type PostType = 'film' | 'music' | 'reel' | 'project' | 'event' | 'photography';
export type MediaKind =
    | 'video' | 'audio' | 'thumbnail' | 'trailer' | 'bts' | 'still' | 'gallery' | 'script';
export type CreditKind =
    | 'cast' | 'crew' | 'recording' | 'production' | 'cast_assembled' | 'crew_assembled';

export interface PendingAsset {
    postId: string;
    kind: MediaKind;
    sortOrder: number;
    ck: CKAssetValue;
    /** Extension hint recorded alongside the asset, when the schema has one. */
    extensionHint: string | null;
}

export interface CreditRow {
    post_id: string;
    kind: CreditKind;
    role: string;
    name: string;
    legacy_profile_cloudkit_id: string | null;
    sort_order: number;
}

export interface PostRow {
    id: string;
    type: PostType;
    legacy_author_cloudkit_id: string | null;
    submitted_by_name: string;
    title: string;
    details: string;
    is_approved: boolean;
    is_removed: boolean;
    created_at: string;
    last_edited_at: string | null;
    [column: string]: unknown;
}

export interface TransformedPost {
    post: PostRow;
    credits: CreditRow[];
    assets: PendingAsset[];
}

// ---------------------------------------------------------------------------
// Credits
// ---------------------------------------------------------------------------

/**
 * Parses the parallel `["<role>: <name>"]` / `["<profileID>"]` arrays into rows.
 *
 * The app splits on the first ":" and DROPS any entry without one
 * (MediaModels.swift:299-305). That silently loses hand-typed credits that were
 * saved without a role. Since the goal is not to lose data, an entry with no
 * colon is kept here as a nameless-role credit rather than discarded — this
 * migration is deliberately more permissive than the parser it replaces.
 */
function parseCredits(
    record: CKRecord,
    postId: string,
    namesField: string,
    idsField: string,
    kind: CreditKind,
): CreditRow[] {
    const entries = strList(record, namesField);
    const ids = strList(record, idsField);

    return entries.map((entry, index) => {
        const separator = entry.indexOf(':');
        const hasRole = separator !== -1;
        const role = hasRole ? entry.slice(0, separator).trim() : '';
        const name = hasRole ? entry.slice(separator + 1).trim() : entry.trim();
        const rawId = ids[index] ?? '';

        return {
            post_id: postId,
            kind,
            role,
            name,
            // The app writes "" for free-typed names, not a missing element.
            legacy_profile_cloudkit_id: rawId === '' ? null : normalizeUserID(rawId),
            sort_order: index,
        };
    });
}

/**
 * Profile records are named `UserProfile_<userRecordName>`, but messaging and
 * likes use the raw id. Normalize to the raw form everywhere, matching
 * DirectoryUser.messagingUserID (UserProfileManager.swift:62).
 */
export function normalizeUserID(id: string): string {
    const prefix = 'UserProfile_';
    return id.startsWith(prefix) ? id.slice(prefix.length) : id;
}

// ---------------------------------------------------------------------------
// Shared post scaffolding
// ---------------------------------------------------------------------------

function basePost(record: CKRecord, type: PostType, titleField: string, detailsField: string): PostRow {
    return {
        id: record.recordName, // already a UUID string; preserved verbatim
        type,
        legacy_author_cloudkit_id: creatorUserRecordName(record),
        submitted_by_name: str(record, 'submittedBy'),
        title: str(record, titleField),
        details: str(record, detailsField),
        is_approved: bool(record, 'isApproved'),
        // ModerationAction records are applied on top of this afterwards; see
        // applyModerationActions() below.
        is_removed: false,
        created_at: createdAt(record),
        last_edited_at: date(record, 'lastEditedDate'),
    };
}

function image(postId: string, ck: CKAssetValue | null, kind: MediaKind, sortOrder = 0): PendingAsset[] {
    return ck ? [{ postId, kind, sortOrder, ck, extensionHint: null }] : [];
}

function imageList(postId: string, list: CKAssetValue[], kind: MediaKind): PendingAsset[] {
    return list.map((ck, index) => ({ postId, kind, sortOrder: index, ck, extensionHint: null }));
}

// ---------------------------------------------------------------------------
// Per-type transforms
// ---------------------------------------------------------------------------

export function transformFilm(record: CKRecord): TransformedPost {
    const post = basePost(record, 'film', 'filmTitle', 'filmDescription');
    const id = post.id;

    post['logline'] = str(record, 'filmLogline');
    post['age_rating'] = str(record, 'filmAgeRating');
    post['explicit'] = bool(record, 'filmExplicit');
    post['festival_bound'] = bool(record, 'filmFestivalBound');
    post['studio'] = str(record, 'filmStudio');
    post['genres'] = strList(record, 'filmGenres');
    post['media_duration_seconds'] = num(record, 'filmVideoDuration');

    return {
        post,
        credits: [
            ...parseCredits(record, id, 'filmCast', 'filmCastIDs', 'cast'),
            ...parseCredits(record, id, 'filmCrew', 'filmCrewIDs', 'crew'),
        ],
        assets: [
            ...image(id, asset(record, 'filmVideo'), 'video'),
            ...image(id, asset(record, 'filmThumbnail'), 'thumbnail'),
            ...image(id, asset(record, 'filmTrailer'), 'trailer'),
            ...imageList(id, assetList(record, 'filmBTS'), 'bts'),
            ...imageList(id, assetList(record, 'filmStills'), 'still'),
        ],
    };
}

export function transformMusic(record: CKRecord): TransformedPost {
    const post = basePost(record, 'music', 'musicTitle', 'musicDescription');
    const id = post.id;

    post['artist'] = str(record, 'musicArtist');
    post['explicit'] = bool(record, 'musicExplicit');
    post['genres'] = strList(record, 'musicGenres');
    post['lyrics'] = str(record, 'lyrics');
    post['spotify_link'] = str(record, 'musicSpotifyLink');
    post['apple_music_link'] = str(record, 'musicAppleMusicLink');
    post['amazon_music_link'] = str(record, 'amazonMusicLink');
    post['youtube_music_link'] = str(record, 'youtubeMusicLink');
    post['soundcloud_link'] = str(record, 'soundcloudLink');
    post['media_duration_seconds'] = num(record, 'musicAudioDuration');

    const audio = asset(record, 'musicAudio');

    return {
        post,
        credits: [
            ...parseCredits(record, id, 'musicRecording', 'musicRecordingIDs', 'recording'),
            ...parseCredits(record, id, 'musicProduction', 'musicProductionIDs', 'production'),
        ],
        assets: [
            // musicAudioExt is unreliable — most production records carry none and
            // some disagree with the file, which is why the app sniffs bytes at
            // playback. We pass it as a hint only; the real MIME is detected from
            // the downloaded bytes in export.ts.
            ...(audio
                ? [{ postId: id, kind: 'audio' as MediaKind, sortOrder: 0, ck: audio, extensionHint: strOrNull(record, 'musicAudioExt') }]
                : []),
            ...image(id, asset(record, 'musicCover'), 'thumbnail'),
            ...image(id, asset(record, 'musicVideo'), 'video'),
        ],
    };
}

export function transformReel(record: CKRecord): TransformedPost {
    const post = basePost(record, 'reel', 'reelTitle', 'reelDescription');
    const id = post.id;

    post['reel_type'] = str(record, 'reelType');
    post['artist'] = str(record, 'reelArtist');
    post['media_duration_seconds'] = num(record, 'reelVideoDuration');
    post['featured_work_ids'] = strList(record, 'featuredWork').filter(isUUID);
    // Each element is already a JSON-encoded ManualFeaturedWork string.
    post['featured_work_manual'] = strList(record, 'featuredWorkManual').map(safeParseJSON).filter(Boolean);

    return {
        post,
        credits: parseCredits(record, id, 'orderedCrew', 'orderedCrewIDs', 'crew'),
        assets: [
            ...image(id, asset(record, 'reelVideo'), 'video'),
            ...image(id, asset(record, 'reelThumbnail'), 'thumbnail'),
        ],
    };
}

export function transformProject(record: CKRecord): TransformedPost {
    const post = basePost(record, 'project', 'projectTitle', 'projectDescription');
    const id = post.id;

    post['genres'] = strList(record, 'projectGenres');
    post['project_shoot_dates_text'] = str(record, 'projectShootDatesText');
    post['project_shoot_start'] = date(record, 'projectShootStart');
    post['project_release_date_text'] = str(record, 'projectReleaseDateText');
    post['project_expected_release'] = date(record, 'projectExpectedReleaseDate');
    post['cast_needed'] = strList(record, 'projectCastNeeded');
    post['crew_needed'] = strList(record, 'projectCrewNeeded');

    return {
        post,
        credits: [
            ...parseCredits(record, id, 'projectCastAssembled', 'projectCastAssembledIDs', 'cast_assembled'),
            ...parseCredits(record, id, 'projectCrewAssembled', 'projectCrewAssembledIDs', 'crew_assembled'),
        ],
        // Script PDFs are NOT exportable — see the note in README.md. They were
        // never uploaded to CloudKit, only ever written to the author's Documents
        // directory (Submission.scriptURL, SubmissionStore.swift:360-372).
        assets: image(id, asset(record, 'projectPoster'), 'thumbnail'),
    };
}

export function transformEvent(record: CKRecord): TransformedPost {
    const post = basePost(record, 'event', 'eventTitle', 'eventDescription');
    const id = post.id;

    post['event_start_at'] = date(record, 'eventStartTime');
    post['event_end_at'] = date(record, 'eventEndTime');
    // The current writer uses eventLocationText; `eventLocation` is a legacy field
    // still listed in CloudKitManager.FeedKeys.event but no longer written.
    post['event_location_text'] = str(record, 'eventLocationText') || str(record, 'eventLocation');
    post['event_host'] = str(record, 'eventHost');
    post['event_category'] = str(record, 'eventCategory');
    post['event_tickets_url'] = strOrNull(record, 'eventTicketsURL');
    post['event_expectations'] = strOrNull(record, 'eventExpectations');
    post['event_application_url'] = strOrNull(record, 'eventApplicationURL');
    post['event_lineup'] = strOrNull(record, 'eventLineup');

    return {
        post,
        credits: [],
        assets: image(id, asset(record, 'eventFlyer'), 'thumbnail'),
    };
}

export function transformPhotography(record: CKRecord): TransformedPost {
    const post = basePost(record, 'photography', 'photographyTitle', 'photographyDescription');
    const id = post.id;

    post['artist'] = str(record, 'photographyArtist');
    post['release_year'] = str(record, 'photographyReleaseYear');
    // These three fields are missing from the PhotographySubmission schema in both
    // environments, so they will be absent on every record until the schema is
    // fixed. The reads are harmless; they just yield empty.
    post['equipment'] = safeParseJSON(str(record, 'photographyEquipment')) ?? {};

    return {
        post,
        credits: parseCredits(record, id, 'orderedCrew', 'orderedCrewIDs', 'crew'),
        assets: [
            ...image(id, asset(record, 'photographyThumbnail'), 'thumbnail'),
            ...imageList(id, assetList(record, 'photographyImages'), 'gallery'),
        ],
    };
}

export const POST_TRANSFORMS: Record<string, { type: PostType; fn: (r: CKRecord) => TransformedPost }> = {
    FilmSubmission: { type: 'film', fn: transformFilm },
    MusicSubmission: { type: 'music', fn: transformMusic },
    ReelSubmission: { type: 'reel', fn: transformReel },
    ProjectSubmission: { type: 'project', fn: transformProject },
    EventSubmission: { type: 'event', fn: transformEvent },
    PhotographySubmission: { type: 'photography', fn: transformPhotography },
};

// ---------------------------------------------------------------------------
// Profiles, likes, moderation, messaging
// ---------------------------------------------------------------------------

export interface ProfileRow {
    legacy_cloudkit_user_id: string;
    first_name: string;
    last_name: string;
    bio: string;
    instagram_handle: string;
    is_ut_student: boolean;
    major: string;
    graduation_year: string;
    school: string;
    is_industry_professional: boolean;
    industry: string;
    company: string;
    company_role: string;
    user_types: string[];
    portfolio_order: string[];
}

export function transformProfile(record: CKRecord): { profile: ProfileRow; avatar: CKAssetValue | null } | null {
    const firstName = str(record, 'firstName');
    const lastName = str(record, 'lastName');

    // Mirrors parseUserMetadata's guard (UserProfileManager.swift:370): a profile
    // with no name at all is invalid and is skipped by the app too.
    if (firstName === '' && lastName === '') return null;

    return {
        profile: {
            legacy_cloudkit_user_id: normalizeUserID(record.recordName),
            first_name: firstName,
            last_name: lastName,
            bio: str(record, 'bio'),
            instagram_handle: str(record, 'instagramHandle'),
            is_ut_student: bool(record, 'isUTStudent', true),
            major: str(record, 'major'),
            graduation_year: str(record, 'graduationYear'),
            school: str(record, 'school'),
            is_industry_professional: bool(record, 'isIndustryProfessional'),
            industry: str(record, 'industry'),
            company: str(record, 'company'),
            company_role: str(record, 'companyRole'),
            // Stored as a single comma-separated string, split on read.
            user_types: str(record, 'userTypes')
                .split(',')
                .map((s) => s.trim())
                .filter((s) => s !== ''),
            portfolio_order: strList(record, 'portfolioOrder').filter(isUUID),
        },
        avatar: asset(record, 'profileImage'),
    };
}

export interface LikeRow {
    post_id: string;
    legacy_user_id: string;
    created_at: string;
}

export function transformLike(record: CKRecord): LikeRow | null {
    const postId = str(record, 'postID');
    const userId = str(record, 'userID');
    if (!isUUID(postId) || userId === '') return null;
    return {
        post_id: postId,
        legacy_user_id: normalizeUserID(userId),
        created_at: createdAt(record),
    };
}

export interface ModerationRow {
    post_id: string;
    is_removed: boolean;
}

/**
 * ModerationAction records are the only place a post's removed state lives —
 * the post record itself was never modified, because CloudKit would not allow it
 * (CloudKitManager.swift:896-901). They are therefore folded into `posts.is_removed`
 * at load time, and the record type is then retired: nothing in the new schema
 * reads or writes it.
 *
 * ModerationEdit is deliberately NOT migrated. Its payload is a JSON-encoded
 * Submission that overrode fields on someone else's post. Rather than carry that
 * overlay forward, the loader APPLIES each edit to the post row directly — which
 * is what the overlay was simulating all along.
 */
export function transformModerationAction(record: CKRecord): ModerationRow | null {
    const postId = str(record, 'postID');
    if (!isUUID(postId)) return null;
    return { post_id: postId, is_removed: bool(record, 'isRemoved') };
}

export interface ModerationEditRow {
    post_id: string;
    payload: Record<string, unknown> | null;
    modified_at: string | null;
}

export function transformModerationEdit(record: CKRecord): ModerationEditRow | null {
    const postId = str(record, 'postID');
    if (!isUUID(postId)) return null;
    return {
        post_id: postId,
        payload: safeParseJSON(str(record, 'payload')),
        modified_at: date(record, 'modifiedAt'),
    };
}

export interface ConversationRow {
    id: string;
    legacy_participant_a: string;
    legacy_participant_b: string;
    last_message_preview: string;
    last_message_at: string | null;
    created_at: string;
}

export function transformConversation(record: CKRecord): ConversationRow | null {
    const a = str(record, 'participant1UserID');
    const b = str(record, 'participant2UserID');
    if (a === '' || b === '' || a === b) return null;
    return {
        id: record.recordName,
        legacy_participant_a: normalizeUserID(a),
        legacy_participant_b: normalizeUserID(b),
        last_message_preview: str(record, 'lastMessagePreview'),
        last_message_at: date(record, 'lastMessageTimestamp'),
        created_at: createdAt(record),
    };
}

export interface MessageRow {
    id: string;
    conversation_id: string;
    legacy_sender_id: string;
    body: string;
    created_at: string;
    read_at: string | null;
    attachmentType: string | null;
}

export function transformMessage(record: CKRecord): { message: MessageRow; attachment: CKAssetValue | null } | null {
    const conversationId = str(record, 'conversationID');
    const sender = str(record, 'senderUserID');
    if (!isUUID(conversationId) || sender === '') return null;

    const timestamp = date(record, 'timestamp') ?? createdAt(record);
    return {
        message: {
            id: record.recordName,
            conversation_id: conversationId,
            legacy_sender_id: normalizeUserID(sender),
            body: str(record, 'content'),
            created_at: timestamp,
            // CloudKit stored only a boolean; there is no per-message read time to
            // recover, so an already-read message gets its send time as read time.
            read_at: bool(record, 'isRead') ? timestamp : null,
            attachmentType: strOrNull(record, 'attachmentType'),
        },
        attachment: asset(record, 'attachment'),
    };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export function isUUID(value: string): boolean {
    return UUID_RE.test(value);
}

export function safeParseJSON(value: string): Record<string, unknown> | null {
    if (!value) return null;
    try {
        const parsed = JSON.parse(value);
        return typeof parsed === 'object' && parsed !== null ? parsed : null;
    } catch {
        return null;
    }
}
