-- 0002_rls.sql
-- Row Level Security. This is the file the whole migration rests on.
--
-- The single most important policy here is `posts_update_own_or_moderator`. In the
-- CloudKit public database only a record's creator may modify or delete it, so a
-- moderator acting on someone else's post silently failed and the post repopulated
-- on every other device. The workaround was two parallel record types
-- (ModerationAction / ModerationEdit, CloudKitManager.swift:886-962) owned by the
-- moderator, which every client re-applied client-side at sync time.
--
-- That workaround does not exist here. A moderator simply has UPDATE permission.
-- Do not port ModerationAction or ModerationEdit.
--
-- Verify this file with backend/tests/rls_test.sql before writing client code.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
-- All SECURITY DEFINER so they bypass RLS on the tables they read. Without that,
-- `posts` policies reading `post_credits` and `post_credits` policies reading
-- `posts` would recurse infinitely.

create or replace function current_profile_id() returns uuid
language sql stable security definer set search_path = public, pg_temp as $$
    select id from profiles where auth_user_id = auth.uid();
$$;

create or replace function is_moderator() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
    select exists (
        select 1
        from moderators m
        join profiles p on p.id = m.profile_id
        where p.auth_user_id = auth.uid()
    );
$$;

-- Films marked festival-bound stay private: visible only to people credited on
-- them (plus the author and moderators). Previously a client-side display rule
-- only — the record itself was readable by anyone.
create or replace function is_credited_on(target_post uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
    select exists (
        select 1
        from post_credits c
        join profiles p on p.id = c.profile_id
        where c.post_id = target_post
          and p.auth_user_id = auth.uid()
    );
$$;

-- Canonical post visibility, reused by every child table so the rule lives in
-- exactly one place.
create or replace function can_view_post(target_post uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
    select exists (
        select 1
        from posts po
        where po.id = target_post
          and (
                is_moderator()
             or po.author_id = current_profile_id()
             or (
                    po.is_approved
                and not po.is_removed
                and (not po.festival_bound or is_credited_on(po.id))
                )
          )
    );
$$;

create or replace function owns_post(target_post uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
    select exists (
        select 1 from posts
        where id = target_post and author_id = current_profile_id()
    );
$$;

create or replace function is_conversation_participant(target_conversation uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
    select exists (
        select 1 from conversations
        where id = target_conversation
          and current_profile_id() in (participant_a, participant_b)
    );
$$;

-- Blocking is enforced, not just hidden. Either direction blocks.
create or replace function has_block_between(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
    select exists (
        select 1 from message_prefs
        where blocked
          and ((profile_id = a and other_id = b) or (profile_id = b and other_id = a))
    );
$$;

-- ---------------------------------------------------------------------------
-- Enable RLS everywhere
-- ---------------------------------------------------------------------------

alter table profiles      enable row level security;
alter table moderators    enable row level security;
alter table posts         enable row level security;
alter table post_credits  enable row level security;
alter table post_media    enable row level security;
alter table post_likes    enable row level security;
alter table conversations enable row level security;
alter table messages      enable row level security;
alter table message_prefs enable row level security;
alter table reports       enable row level security;
alter table audit_log     enable row level security;
alter table app_config    enable row level security;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
-- The directory is readable by any signed-in user. Guest (non-UT) profiles are
-- hidden from the directory in the UI, not here — moderators still need to see
-- them to toggle status back.

create policy profiles_select_authenticated on profiles
    for select to authenticated
    using (true);

create policy profiles_insert_self on profiles
    for insert to authenticated
    with check (auth_user_id = auth.uid());

-- Self-edit, or a moderator (needed by UserProfileManager.setGuestStatus, which
-- today fails with permissionFailure against another user's record —
-- UserProfileManager.swift:245).
create policy profiles_update_self_or_moderator on profiles
    for update to authenticated
    using (auth_user_id = auth.uid() or is_moderator())
    with check (auth_user_id = auth.uid() or is_moderator());

create policy profiles_delete_self_or_moderator on profiles
    for delete to authenticated
    using (auth_user_id = auth.uid() or is_moderator());

-- ---------------------------------------------------------------------------
-- moderators
-- ---------------------------------------------------------------------------
-- Readable so a client can render moderator badges; grants are service-role only.
-- There is deliberately no INSERT/UPDATE/DELETE policy: you cannot make yourself
-- a moderator through the API.

create policy moderators_select_authenticated on moderators
    for select to authenticated
    using (true);

-- ---------------------------------------------------------------------------
-- posts
-- ---------------------------------------------------------------------------

-- Approved, not removed, and not festival-bound-unless-credited. Authors always
-- see their own (including pending). Moderators see everything, which is what
-- ModerateView needs.
create policy posts_select_visible on posts
    for select to authenticated
    using (
           is_moderator()
        or author_id = current_profile_id()
        or (
               is_approved
           and not is_removed
           and (not festival_bound or is_credited_on(id))
           )
    );

create policy posts_insert_own on posts
    for insert to authenticated
    with check (author_id = current_profile_id());

-- >>> The policy that replaces the moderation overlay. <<<
create policy posts_update_own_or_moderator on posts
    for update to authenticated
    using (author_id = current_profile_id() or is_moderator())
    with check (author_id = current_profile_id() or is_moderator());

create policy posts_delete_own_or_moderator on posts
    for delete to authenticated
    using (author_id = current_profile_id() or is_moderator());

-- ---------------------------------------------------------------------------
-- post_credits / post_media — visibility follows the parent post
-- ---------------------------------------------------------------------------

create policy post_credits_select on post_credits
    for select to authenticated
    using (can_view_post(post_id));

create policy post_credits_write on post_credits
    for all to authenticated
    using (owns_post(post_id) or is_moderator())
    with check (owns_post(post_id) or is_moderator());

create policy post_media_select on post_media
    for select to authenticated
    using (can_view_post(post_id));

create policy post_media_write on post_media
    for all to authenticated
    using (owns_post(post_id) or is_moderator())
    with check (owns_post(post_id) or is_moderator());

-- ---------------------------------------------------------------------------
-- post_likes
-- ---------------------------------------------------------------------------
-- Readable on any visible post, so `fetchLikeCount` / `fetchLikers`
-- (CloudKitManager.swift:522-536) become a COUNT and a join. Writable only as
-- yourself — the property the "like_<postID>_<userID>" naming scheme was
-- simulating.

create policy post_likes_select on post_likes
    for select to authenticated
    using (can_view_post(post_id));

create policy post_likes_insert_self on post_likes
    for insert to authenticated
    with check (profile_id = current_profile_id() and can_view_post(post_id));

create policy post_likes_delete_self on post_likes
    for delete to authenticated
    using (profile_id = current_profile_id());

-- ---------------------------------------------------------------------------
-- conversations / messages
-- ---------------------------------------------------------------------------
-- Moderators are deliberately NOT given read access to private messages.

create policy conversations_select_participant on conversations
    for select to authenticated
    using (current_profile_id() in (participant_a, participant_b));

create policy conversations_insert_participant on conversations
    for insert to authenticated
    with check (
            current_profile_id() in (participant_a, participant_b)
        and not has_block_between(participant_a, participant_b)
    );

create policy conversations_update_participant on conversations
    for update to authenticated
    using (current_profile_id() in (participant_a, participant_b))
    with check (current_profile_id() in (participant_a, participant_b));

create policy messages_select_participant on messages
    for select to authenticated
    using (is_conversation_participant(conversation_id));

create policy messages_insert_sender on messages
    for insert to authenticated
    with check (
            sender_id = current_profile_id()
        and is_conversation_participant(conversation_id)
    );

-- Recipients need UPDATE to set read_at; senders to edit/retract.
create policy messages_update_participant on messages
    for update to authenticated
    using (is_conversation_participant(conversation_id))
    with check (is_conversation_participant(conversation_id));

create policy messages_delete_sender on messages
    for delete to authenticated
    using (sender_id = current_profile_id());

create policy message_prefs_own on message_prefs
    for all to authenticated
    using (profile_id = current_profile_id())
    with check (profile_id = current_profile_id());

-- ---------------------------------------------------------------------------
-- reports
-- ---------------------------------------------------------------------------
-- Reporters can file and see their own; moderators see and resolve everything.
-- Required by Play's UGC policy.

create policy reports_insert_self on reports
    for insert to authenticated
    with check (reporter_id = current_profile_id());

create policy reports_select_own_or_moderator on reports
    for select to authenticated
    using (reporter_id = current_profile_id() or is_moderator());

create policy reports_update_moderator on reports
    for update to authenticated
    using (is_moderator())
    with check (is_moderator());

-- ---------------------------------------------------------------------------
-- audit_log / app_config
-- ---------------------------------------------------------------------------
-- audit_log is written by triggers (SECURITY DEFINER) and read by moderators.
-- No INSERT policy: clients cannot forge entries.

create policy audit_log_select_moderator on audit_log
    for select to authenticated
    using (is_moderator());

-- The version gate must be readable BEFORE sign-in, or a blocked client can never
-- learn it is blocked.
create policy app_config_select_all on app_config
    for select to anon, authenticated
    using (true);
