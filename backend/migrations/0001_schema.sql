-- 0001_schema.sql
-- Nexus / Longhorn Artists Connect — Supabase (Postgres) schema.
--
-- Replaces the CloudKit public database. Mapping notes are inline; the short
-- version is in backend/README.md.
--
-- Two structural decisions worth stating up front:
--
--  1. ONE `posts` table with a `type` discriminator, not six tables. The iOS app
--     already collapses all six media types into a single `Submission` struct
--     (SubmissionStore.swift:84) and converts to/from the per-type CloudKit
--     records only at the boundary (CloudKitTransitionAdapter.swift:54). Mirroring
--     `Submission` keeps the feed a single SELECT instead of six.
--
--  2. Post IDs are PRESERVED from CloudKit. Every CloudKit record name for a
--     submission is already a UUID string (`CKRecord.ID(recordName: id.uuidString)`),
--     so every ID in the shipped app — including `featured_work_ids` references and
--     locally cached file names — stays valid across the migration.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

-- Mirrors MediaType (SubmissionStore.swift:7).
create type post_type as enum (
    'film', 'music', 'reel', 'project', 'event', 'photography'
);

-- One row per uploaded file. Replaces the ~12 *FileName columns on `Submission`
-- and the CloudKit asset fields (filmVideo, filmTrailer, filmBTS, filmStills,
-- musicAudio, musicCover, reelVideo, projectPoster, eventFlyer,
-- photographyImages, *Thumbnail).
create type media_kind as enum (
    'video',      -- filmVideo / reelVideo / musicVideo
    'audio',      -- musicAudio
    'thumbnail',  -- filmThumbnail / musicCover / reelThumbnail / projectPoster
                  -- / eventFlyer / photographyThumbnail
    'trailer',    -- filmTrailer
    'bts',        -- filmBTS
    'still',      -- filmStills
    'gallery',    -- photographyImages
    'script'      -- project script PDF
);

-- Credits were stored as parallel string arrays: `"<role>: <name>"` plus a
-- separate IDs array (MediaModels.swift:183-186), re-split on ": " when read
-- (:297-313). That silently corrupts any role or name containing a colon. They
-- become real rows here.
create type credit_kind as enum (
    'cast',            -- filmCast
    'crew',            -- filmCrew / orderedCrew (reel, photography)
    'recording',       -- musicRecording
    'production',      -- musicProduction
    'cast_assembled',  -- projectCastAssembled
    'crew_assembled'   -- projectCrewAssembled
);

-- ---------------------------------------------------------------------------
-- profiles — replaces the `UserProfile` record type
-- ---------------------------------------------------------------------------
-- Columns follow DirectoryUser (UserProfileManager.swift:16-44).
--
-- `id` is nullable ONLY during migration: profiles are imported from CloudKit
-- before their owner has ever authenticated, and are bound to an auth user by the
-- claim flow (see 0003, `claim_legacy_profile`). Once claimed it is the FK that
-- everything hangs off. `legacy_cloudkit_user_id` is the bridge; it is the raw
-- CKContainer.userRecordID recordName, i.e. the `UserProfile_` prefix stripped
-- (UserProfileManager.swift:62).
create table profiles (
    id                        uuid primary key default gen_random_uuid(),
    auth_user_id              uuid unique references auth.users (id) on delete set null,
    legacy_cloudkit_user_id   text unique,

    first_name                text not null default '',
    last_name                 text not null default '',
    bio                       text not null default '',
    instagram_handle          text not null default '',
    avatar_path               text,

    -- Student fields
    is_ut_student             boolean not null default true,
    major                     text not null default '',
    graduation_year           text not null default '',
    school                    text not null default '',

    -- Industry-professional fields (industry replaces major, company replaces class)
    is_industry_professional  boolean not null default false,
    industry                  text not null default '',
    company                   text not null default '',
    company_role              text not null default '',

    -- Parsed from the comma-separated `userTypes` string in CloudKit.
    user_types                text[] not null default '{}',
    -- Owner's chosen ordering of their portfolio posts.
    portfolio_order           uuid[] not null default '{}',

    created_at                timestamptz not null default now(),
    updated_at                timestamptz not null default now(),

    constraint profiles_have_a_name check (first_name <> '' or last_name <> '')
);

create index profiles_auth_user_id_idx on profiles (auth_user_id);
create index profiles_legacy_id_idx     on profiles (legacy_cloudkit_user_id);
create index profiles_last_name_idx     on profiles (last_name);

-- ---------------------------------------------------------------------------
-- moderators — replaces the hardcoded name match
-- ---------------------------------------------------------------------------
-- ModeratorAccess.isModerator (SecurityConfiguration.swift:190) compares a
-- UserDefaults display name against the literal "Aiden Weinstein", and
-- ModeratorSession gates it behind a hardcoded password. Both are client-side and
-- trivially bypassed. Moderator status is now a server fact; the password prompt
-- stays only as a local "are you sure" affordance.
create table moderators (
    profile_id  uuid primary key references profiles (id) on delete cascade,
    granted_at  timestamptz not null default now(),
    granted_by  uuid references profiles (id) on delete set null,
    note        text not null default ''
);

-- ---------------------------------------------------------------------------
-- posts — replaces {Film,Music,Reel,Project,Event,Photography}Submission
-- ---------------------------------------------------------------------------
create table posts (
    id                    uuid primary key,   -- preserved from CloudKit
    type                  post_type not null,

    -- Nullable until the author claims their account (see profiles.id note).
    -- `legacy_author_cloudkit_id` is the migration-time attribution and is
    -- backfilled into author_id by claim_legacy_profile().
    author_id                 uuid references profiles (id) on delete set null,
    legacy_author_cloudkit_id text,
    -- CloudKit `submittedBy`: a display name, not an ID. Kept for posts whose
    -- author can never be resolved.
    submitted_by_name         text not null default '',

    title                 text not null default '',
    details               text not null default '',

    is_approved           boolean not null default false,
    -- Replaces the ModerationAction overlay entirely. Moderators now write this
    -- column directly; RLS permits it (see 0002).
    is_removed            boolean not null default false,

    created_at            timestamptz not null default now(),
    last_edited_at        timestamptz,

    -- Shared display fields
    logline               text not null default '',
    age_rating            text not null default '',
    genres                text[] not null default '{}',
    explicit              boolean not null default false,
    release_year          text not null default '',
    -- Films only: "festival-bound" posts are hidden from the public feed and
    -- visible only to credited people (enforced in RLS, not on the client).
    festival_bound        boolean not null default false,
    -- Seconds; captured at upload so the duration badge renders without
    -- downloading the media (the reason filmVideoDuration is in FeedKeys).
    media_duration_seconds double precision,

    -- Event
    event_start_at        timestamptz,
    event_end_at          timestamptz,
    event_location_text   text,
    event_host            text not null default '',
    event_category        text not null default '',
    event_tickets_url     text,
    event_expectations    text,
    event_application_url text,
    event_lineup          text,

    -- Project
    project_type              text not null default '',  -- Cast & Crew Call | Script | In-Development
    project_shoot_dates_text  text not null default '',
    project_shoot_start       timestamptz,
    project_release_date_text text not null default '',
    project_expected_release  timestamptz,
    cast_needed               text[] not null default '{}',
    crew_needed               text[] not null default '{}',
    script_page_count         integer not null default 0,

    -- Film
    studio                text not null default '',

    -- Music
    artist                text not null default '',
    lyrics                text not null default '',
    spotify_link          text not null default '',
    apple_music_link      text not null default '',
    amazon_music_link     text not null default '',
    youtube_music_link    text not null default '',
    soundcloud_link       text not null default '',

    -- Reel
    reel_type             text not null default '',
    reel_experience       text not null default '',
    reel_specific_skills  text not null default '',
    -- UUIDs of other posts shown as "Featured Work". Not an FK array: referenced
    -- posts may be removed, and the client already tolerates unresolvable IDs.
    featured_work_ids     uuid[] not null default '{}',
    -- Hand-typed entries for work that isn't on the app; each element is a
    -- JSON-encoded ManualFeaturedWork.
    featured_work_manual  jsonb not null default '[]',

    -- Photography: EquipmentInfo (SharedSubmissionTypes.swift:528) — camera, lens,
    -- lighting, filters, support, accessories. Flat and display-only, so jsonb.
    equipment             jsonb not null default '{}',

    -- Escape hatch for future type-specific fields, so adding one does not
    -- require a migration on a table this wide.
    type_specific         jsonb not null default '{}'
);

create index posts_feed_idx        on posts (created_at desc)
    where is_approved and not is_removed and not festival_bound;
create index posts_type_idx        on posts (type, created_at desc);
create index posts_author_idx      on posts (author_id, created_at desc);
create index posts_legacy_author_idx on posts (legacy_author_cloudkit_id);
create index posts_event_start_idx on posts (event_start_at) where type = 'event';

-- ---------------------------------------------------------------------------
-- post_credits — replaces the "role: name" string arrays
-- ---------------------------------------------------------------------------
-- `profile_id` is the directory link (OrderedEntry.profileID); null for
-- free-typed names. `sort_order` preserves the ordering the ordered* arrays
-- existed to maintain.
create table post_credits (
    id          uuid primary key default gen_random_uuid(),
    post_id     uuid not null references posts (id) on delete cascade,
    kind        credit_kind not null,
    role        text not null default '',
    name        text not null default '',
    profile_id  uuid references profiles (id) on delete set null,
    -- Preserved so a credit can still resolve to a person whose profile has not
    -- been claimed yet.
    legacy_profile_cloudkit_id text,
    sort_order  integer not null default 0
);

create index post_credits_post_idx    on post_credits (post_id, kind, sort_order);
create index post_credits_profile_idx on post_credits (profile_id);

-- ---------------------------------------------------------------------------
-- post_media — replaces CKAsset fields and the local file-name columns
-- ---------------------------------------------------------------------------
-- `storage_path` is a Supabase Storage object path, or a Cloudflare Stream / Mux
-- playback ID once video moves to HLS (see backend/README.md).
--
-- `mime_type` is recorded at UPLOAD time. This is the fix for the sniffing hack
-- in CloudKitWebServices.streamURL (:141-219): CloudKit derived Content-Type from
-- a `${f}` filename template, so the app had to range-request the first 16 bytes
-- of every track and guess the container. Controlling upload removes the problem.
create table post_media (
    id              uuid primary key default gen_random_uuid(),
    post_id         uuid not null references posts (id) on delete cascade,
    kind            media_kind not null,
    storage_path    text not null,
    mime_type       text not null,
    byte_size       bigint,
    duration_seconds double precision,
    width           integer,
    height          integer,
    sort_order      integer not null default 0,
    created_at      timestamptz not null default now()
);

create index post_media_post_idx on post_media (post_id, kind, sort_order);

-- At most one of each single-valued kind per post; bts/still/gallery repeat.
create unique index post_media_single_kind_idx
    on post_media (post_id, kind)
    where kind in ('video', 'audio', 'thumbnail', 'trailer', 'script');

-- ---------------------------------------------------------------------------
-- post_likes — replaces the PostLike record type
-- ---------------------------------------------------------------------------
-- CloudKit needed deterministic record names ("like_<postID>_<userID>",
-- CloudKitManager.swift:494) to make liking idempotent and prevent double-likes.
-- A composite primary key does that natively.
create table post_likes (
    post_id     uuid not null references posts (id) on delete cascade,
    profile_id  uuid not null references profiles (id) on delete cascade,
    created_at  timestamptz not null default now(),
    primary key (post_id, profile_id)
);

create index post_likes_profile_idx on post_likes (profile_id);

-- ---------------------------------------------------------------------------
-- conversations / messages — replaces the Conversation and Message record types
-- ---------------------------------------------------------------------------
-- MessageRecordHandling.deterministicID (:1248) derives a stable UUID from the
-- ordered participant pair so both devices agree on one conversation. A unique
-- constraint on the normalized pair enforces that server-side instead.
create table conversations (
    id                    uuid primary key default gen_random_uuid(),
    participant_a         uuid not null references profiles (id) on delete cascade,
    participant_b         uuid not null references profiles (id) on delete cascade,
    last_message_preview  text not null default '',
    last_message_at       timestamptz,
    created_at            timestamptz not null default now(),

    constraint conversations_distinct_participants check (participant_a <> participant_b)
);

create unique index conversations_pair_idx on conversations (
    least(participant_a, participant_b),
    greatest(participant_a, participant_b)
);
create index conversations_a_idx on conversations (participant_a, last_message_at desc);
create index conversations_b_idx on conversations (participant_b, last_message_at desc);

create table messages (
    id               uuid primary key default gen_random_uuid(),
    conversation_id  uuid not null references conversations (id) on delete cascade,
    sender_id        uuid not null references profiles (id) on delete cascade,
    body             text not null default '',
    attachment_path  text,
    attachment_type  text,
    -- Set when a post is shared into a conversation (SendPostMessageView).
    shared_post_id   uuid references posts (id) on delete set null,
    created_at       timestamptz not null default now(),
    read_at          timestamptz
);

create index messages_conversation_idx on messages (conversation_id, created_at desc);
create index messages_unread_idx on messages (conversation_id) where read_at is null;

-- Block / mute / pin. Currently local-only (MessageRecordHandling.swift:51-102),
-- so it does not follow a user across devices. Server-side means blocking can
-- also be ENFORCED in RLS rather than merely hidden in the UI.
create table message_prefs (
    profile_id  uuid not null references profiles (id) on delete cascade,
    other_id    uuid not null references profiles (id) on delete cascade,
    blocked     boolean not null default false,
    muted       boolean not null default false,
    pinned      boolean not null default false,
    primary key (profile_id, other_id)
);

-- ---------------------------------------------------------------------------
-- reports / audit_log
-- ---------------------------------------------------------------------------
-- reports replaces the `Flag` record type (ReportContentView).
create table reports (
    id                uuid primary key default gen_random_uuid(),
    post_id           uuid references posts (id) on delete cascade,
    reported_profile  uuid references profiles (id) on delete cascade,
    reporter_id       uuid not null references profiles (id) on delete cascade,
    reason            text not null default '',
    details           text not null default '',
    resolved_at       timestamptz,
    resolved_by       uuid references profiles (id) on delete set null,
    created_at        timestamptz not null default now(),

    constraint reports_target_required
        check (post_id is not null or reported_profile is not null)
);

create index reports_open_idx on reports (created_at desc) where resolved_at is null;

-- Moderation history. ModerationAction carried this incidentally; make it explicit
-- so Play/App Store UGC-moderation questions have an answer.
create table audit_log (
    id           bigserial primary key,
    actor_id     uuid references profiles (id) on delete set null,
    action       text not null,
    target_table text not null,
    target_id    text not null,
    detail       jsonb not null default '{}',
    created_at   timestamptz not null default now()
);

create index audit_log_target_idx on audit_log (target_table, target_id, created_at desc);

-- ---------------------------------------------------------------------------
-- app_config — drives the forced-update gate
-- ---------------------------------------------------------------------------
-- AppVersionChecker (AppVersionChecker.swift:40) currently polls the iTunes
-- lookup API and only nudges. The cutover needs a hard floor the server controls,
-- per platform. Publicly readable, service-role writable.
create table app_config (
    platform                  text primary key check (platform in ('ios', 'android')),
    minimum_supported_version text not null,
    latest_version            text not null,
    update_message            text not null default '',
    store_url                 text not null default ''
);

insert into app_config (platform, minimum_supported_version, latest_version, store_url) values
    ('ios',     '0.0.0', '0.0.0', ''),
    ('android', '0.0.0', '0.0.0', '');

-- ---------------------------------------------------------------------------
-- updated_at maintenance
-- ---------------------------------------------------------------------------

create or replace function set_updated_at() returns trigger
language plpgsql as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

create trigger profiles_set_updated_at
    before update on profiles
    for each row execute function set_updated_at();
