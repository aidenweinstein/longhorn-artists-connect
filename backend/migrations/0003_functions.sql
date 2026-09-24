-- 0003_functions.sql
-- Account claiming, feed views, conversation upsert, and moderation auditing.

-- ---------------------------------------------------------------------------
-- New-signup profile creation
-- ---------------------------------------------------------------------------
-- Every auth user gets a profile row immediately so `current_profile_id()` is
-- never null for a signed-in user. Claiming (below) MERGES a legacy profile into
-- this one rather than creating a second.

create or replace function handle_new_auth_user() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
    insert into profiles (auth_user_id, first_name, last_name)
    values (
        new.id,
        coalesce(new.raw_user_meta_data ->> 'first_name', 'New'),
        coalesce(new.raw_user_meta_data ->> 'last_name',  'Member')
    )
    on conflict (auth_user_id) do nothing;
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function handle_new_auth_user();

-- ---------------------------------------------------------------------------
-- claim_legacy_profile — the iOS migration bridge
-- ---------------------------------------------------------------------------
-- This is the hinge of the whole cutover, and it has exactly one chance to work.
--
-- The ONLY link between a user's CloudKit identity and their new account is the
-- CloudKit record name cached on their iPhone at
-- ModeratorAccess.currentUserRecordNameKey (written in CloudKitManager.swift:44).
-- It exists nowhere else — not on the server, not on any other device. A user who
-- skips the cutover build and later reinstalls loses it permanently and will need
-- manual reattachment.
--
-- Single-use by construction: the UPDATE only matches a legacy profile that is
-- not yet bound to an auth user, so a second caller claiming the same ID gets
-- 'already_claimed'.
create or replace function claim_legacy_profile(legacy_id text)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
    caller_auth   uuid := auth.uid();
    caller_profile uuid;
    legacy_profile uuid;
    posts_moved    integer := 0;
    credits_moved  integer := 0;
begin
    if caller_auth is null then
        return jsonb_build_object('status', 'not_authenticated');
    end if;

    if legacy_id is null or btrim(legacy_id) = '' then
        return jsonb_build_object('status', 'invalid_legacy_id');
    end if;

    select id into caller_profile from profiles where auth_user_id = caller_auth;
    if caller_profile is null then
        return jsonb_build_object('status', 'no_profile');
    end if;

    -- Already claimed by this same account: idempotent success, so a retry after
    -- a dropped connection does not look like a failure.
    if exists (
        select 1 from profiles
        where legacy_cloudkit_user_id = legacy_id and auth_user_id = caller_auth
    ) then
        return jsonb_build_object('status', 'already_mine', 'profile_id', caller_profile);
    end if;

    select id into legacy_profile
    from profiles
    where legacy_cloudkit_user_id = legacy_id
      and auth_user_id is null
    for update;

    if legacy_profile is null then
        if exists (select 1 from profiles where legacy_cloudkit_user_id = legacy_id) then
            return jsonb_build_object('status', 'already_claimed');
        end if;
        return jsonb_build_object('status', 'not_found');
    end if;

    -- Merge the imported profile's content into the freshly created auth profile,
    -- keeping any non-empty value the migration imported.
    update profiles p
    set first_name               = nullif(l.first_name, ''),
        last_name                = nullif(l.last_name, ''),
        bio                      = l.bio,
        instagram_handle         = l.instagram_handle,
        avatar_path              = coalesce(l.avatar_path, p.avatar_path),
        is_ut_student            = l.is_ut_student,
        major                    = l.major,
        graduation_year          = l.graduation_year,
        school                   = l.school,
        is_industry_professional = l.is_industry_professional,
        industry                 = l.industry,
        company                  = l.company,
        company_role             = l.company_role,
        user_types               = l.user_types,
        portfolio_order          = l.portfolio_order,
        legacy_cloudkit_user_id  = l.legacy_cloudkit_user_id
    from profiles l
    where p.id = caller_profile
      and l.id = legacy_profile;

    -- Repoint everything that referenced the placeholder.
    update posts set author_id = caller_profile
    where author_id = legacy_profile
       or (author_id is null and legacy_author_cloudkit_id = legacy_id);
    get diagnostics posts_moved = row_count;

    update post_credits set profile_id = caller_profile
    where profile_id = legacy_profile
       or (profile_id is null and legacy_profile_cloudkit_id = legacy_id);
    get diagnostics credits_moved = row_count;

    update conversations set participant_a = caller_profile where participant_a = legacy_profile;
    update conversations set participant_b = caller_profile where participant_b = legacy_profile;
    update messages      set sender_id     = caller_profile where sender_id     = legacy_profile;
    update post_likes    set profile_id    = caller_profile where profile_id    = legacy_profile
        and not exists (
            select 1 from post_likes existing
            where existing.post_id = post_likes.post_id
              and existing.profile_id = caller_profile
        );

    -- Drop the now-empty placeholder. Its FKs are all repointed above; the
    -- remaining ON DELETE SET NULL edges are intentional.
    delete from profiles where id = legacy_profile;

    insert into audit_log (actor_id, action, target_table, target_id, detail)
    values (caller_profile, 'claim_legacy_profile', 'profiles', legacy_id,
            jsonb_build_object('posts_moved', posts_moved, 'credits_moved', credits_moved));

    return jsonb_build_object(
        'status',        'claimed',
        'profile_id',    caller_profile,
        'posts_moved',   posts_moved,
        'credits_moved', credits_moved
    );
end;
$$;

revoke all on function claim_legacy_profile(text) from public;
grant execute on function claim_legacy_profile(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Feed view
-- ---------------------------------------------------------------------------
-- Replaces the six parallel fetchApproved* queries (CloudKitManager.swift:569-759)
-- and their client-side merge. Like counts come back with the row, so
-- refreshLikeCount's per-post round trip disappears.
--
-- `security_invoker` makes the view respect the caller's RLS rather than the
-- view owner's — without it this would leak unapproved and festival-bound posts.
create or replace view feed_posts
with (security_invoker = true) as
select
    p.*,
    coalesce(l.like_count, 0)                        as like_count,
    exists (
        select 1 from post_likes pl
        where pl.post_id = p.id and pl.profile_id = current_profile_id()
    )                                                as liked_by_me,
    (select pm.storage_path from post_media pm
      where pm.post_id = p.id and pm.kind = 'thumbnail' limit 1) as thumbnail_path,
    author.first_name || ' ' || author.last_name     as author_name,
    author.avatar_path                               as author_avatar_path
from posts p
left join profiles author on author.id = p.author_id
left join (
    select post_id, count(*) as like_count
    from post_likes
    group by post_id
) l on l.post_id = p.id;

-- ---------------------------------------------------------------------------
-- find_or_create_conversation
-- ---------------------------------------------------------------------------
-- Replaces MessageRecordHandling.findOrCreateConversation (:726) and its
-- deterministicID pairing trick. Atomic, so two devices starting a conversation
-- simultaneously cannot create duplicates.
create or replace function find_or_create_conversation(other_profile uuid)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
    me     uuid := current_profile_id();
    result uuid;
begin
    if me is null then
        raise exception 'not authenticated';
    end if;
    if other_profile = me then
        raise exception 'cannot start a conversation with yourself';
    end if;
    if has_block_between(me, other_profile) then
        raise exception 'blocked';
    end if;

    select id into result
    from conversations
    where least(participant_a, participant_b)    = least(me, other_profile)
      and greatest(participant_a, participant_b) = greatest(me, other_profile);

    if result is not null then
        return result;
    end if;

    insert into conversations (participant_a, participant_b)
    values (least(me, other_profile), greatest(me, other_profile))
    on conflict do nothing
    returning id into result;

    -- Lost the race: the other device inserted first.
    if result is null then
        select id into result
        from conversations
        where least(participant_a, participant_b)    = least(me, other_profile)
          and greatest(participant_a, participant_b) = greatest(me, other_profile);
    end if;

    return result;
end;
$$;

grant execute on function find_or_create_conversation(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Conversation preview maintenance
-- ---------------------------------------------------------------------------
-- Was three separate CloudKit writes per message (saveMessageToCloudKit +
-- updateConversation + resetUnreadCount). Now one trigger.

create or replace function touch_conversation_on_message() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
    update conversations
    set last_message_at      = new.created_at,
        last_message_preview = left(
            case
                when new.shared_post_id is not null then 'Shared a post'
                when new.attachment_path is not null and btrim(new.body) = '' then 'Sent an attachment'
                else new.body
            end, 140)
    where id = new.conversation_id;
    return new;
end;
$$;

create trigger messages_touch_conversation
    after insert on messages
    for each row execute function touch_conversation_on_message();

-- ---------------------------------------------------------------------------
-- Moderation auditing
-- ---------------------------------------------------------------------------
-- Logs only when someone OTHER than the author changes moderation state, so
-- ordinary edits do not fill the log.

create or replace function audit_post_moderation() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
    actor uuid := current_profile_id();
begin
    if actor is distinct from new.author_id
       and (old.is_removed is distinct from new.is_removed
            or old.is_approved is distinct from new.is_approved) then
        insert into audit_log (actor_id, action, target_table, target_id, detail)
        values (
            actor,
            case when old.is_removed is distinct from new.is_removed
                 then (case when new.is_removed then 'post_removed' else 'post_restored' end)
                 else (case when new.is_approved then 'post_approved' else 'post_unapproved' end)
            end,
            'posts', new.id::text,
            jsonb_build_object(
                'was_removed',  old.is_removed,  'now_removed',  new.is_removed,
                'was_approved', old.is_approved, 'now_approved', new.is_approved
            )
        );
    end if;
    return new;
end;
$$;

create trigger posts_audit_moderation
    after update on posts
    for each row execute function audit_post_moderation();

-- ---------------------------------------------------------------------------
-- Account deletion — required by BOTH Google Play and App Store review
-- ---------------------------------------------------------------------------
-- The app has no self-service deletion today (only the moderator-facing
-- UserProfileManager.deleteUserProfile). Both stores require an in-app path plus
-- a public web request URL. Content is anonymized rather than cascade-deleted so
-- other users' conversations and credited posts do not develop holes; media is
-- purged separately by the Edge Function that calls this.
create or replace function delete_my_account() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
    me uuid := current_profile_id();
begin
    if me is null then
        return jsonb_build_object('status', 'not_authenticated');
    end if;

    delete from posts where author_id = me;
    delete from post_likes where profile_id = me;
    delete from message_prefs where profile_id = me or other_id = me;

    update post_credits
    set profile_id = null, legacy_profile_cloudkit_id = null
    where profile_id = me;

    update messages set body = '', attachment_path = null where sender_id = me;

    update profiles
    set first_name = 'Deleted', last_name = 'User', bio = '', instagram_handle = '',
        avatar_path = null, user_types = '{}', portfolio_order = '{}',
        major = '', graduation_year = '', school = '',
        industry = '', company = '', company_role = '',
        legacy_cloudkit_user_id = null, auth_user_id = null
    where id = me;

    insert into audit_log (actor_id, action, target_table, target_id)
    values (null, 'account_deleted', 'profiles', me::text);

    return jsonb_build_object('status', 'deleted');
end;
$$;

grant execute on function delete_my_account() to authenticated;
