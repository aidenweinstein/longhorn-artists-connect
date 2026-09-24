-- rls_test.sql
-- The most important test in the migration.
--
-- The entire plan rests on one claim: a moderator can modify another user's post
-- server-side. If that is false, the ModerationAction/ModerationEdit overlay has
-- to be rebuilt and the migration loses most of its value. Prove it before
-- writing any client code.
--
-- Run against a local stack:
--     supabase db reset
--     psql "$LOCAL_DB_URL" -v ON_ERROR_STOP=1 -f backend/tests/rls_test.sql
--
-- Everything runs in a transaction that rolls back, so it is safe to re-run.
-- Any failed assertion aborts with a message.

begin;

-- ---------------------------------------------------------------------------
-- Fixtures (as superuser, before we start impersonating)
-- ---------------------------------------------------------------------------

-- Minimal auth.users rows. The on_auth_user_created trigger creates profiles.
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
values
    ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000',
     'authenticated', 'authenticated', 'author@test.dev',
     '{"first_name":"Ada","last_name":"Author"}'),
    ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000',
     'authenticated', 'authenticated', 'stranger@test.dev',
     '{"first_name":"Sam","last_name":"Stranger"}'),
    ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000',
     'authenticated', 'authenticated', 'mod@test.dev',
     '{"first_name":"Mo","last_name":"Moderator"}'),
    ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000',
     'authenticated', 'authenticated', 'credited@test.dev',
     '{"first_name":"Cleo","last_name":"Credited"}');

create temporary table t (k text primary key, v uuid);
insert into t
select 'author',   id from profiles where auth_user_id = '11111111-1111-1111-1111-111111111111';
insert into t
select 'stranger', id from profiles where auth_user_id = '22222222-2222-2222-2222-222222222222';
insert into t
select 'mod',      id from profiles where auth_user_id = '33333333-3333-3333-3333-333333333333';
insert into t
select 'credited', id from profiles where auth_user_id = '44444444-4444-4444-4444-444444444444';

insert into moderators (profile_id) select v from t where k = 'mod';

-- Three posts by the author: approved, pending, and festival-bound.
insert into posts (id, type, author_id, title, is_approved, festival_bound)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'film', v, 'Approved Film', true, false from t where k = 'author';
insert into posts (id, type, author_id, title, is_approved, festival_bound)
select 'aaaaaaaa-0000-0000-0000-000000000002', 'film', v, 'Pending Film', false, false from t where k = 'author';
insert into posts (id, type, author_id, title, is_approved, festival_bound)
select 'aaaaaaaa-0000-0000-0000-000000000003', 'film', v, 'Festival Film', true, true from t where k = 'author';

-- Cleo is credited on the festival-bound film.
insert into post_credits (post_id, kind, role, name, profile_id)
select 'aaaaaaaa-0000-0000-0000-000000000003', 'cast', 'Lead', 'Cleo Credited', v
from t where k = 'credited';

-- A legacy (unclaimed) profile plus one of its posts, for the claim test.
insert into profiles (legacy_cloudkit_user_id, first_name, last_name, major)
values ('_abc123legacy', 'Lee', 'Legacy', 'Radio-Television-Film');
insert into posts (id, type, author_id, legacy_author_cloudkit_id, title, is_approved)
values ('aaaaaaaa-0000-0000-0000-000000000009', 'music', null, '_abc123legacy', 'Legacy Track', true);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function assert(condition boolean, label text) returns void
language plpgsql as $$
begin
    if condition is not true then
        raise exception 'FAIL: %', label;
    end if;
    raise notice 'pass: %', label;
end;
$$;

create or replace function become(auth_user uuid) returns void
language plpgsql as $$
begin
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims',
        json_build_object('sub', auth_user, 'role', 'authenticated')::text, true);
end;
$$;

create or replace function become_superuser() returns void
language plpgsql as $$
begin
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', '', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Visibility
-- ---------------------------------------------------------------------------

select become('22222222-2222-2222-2222-222222222222');  -- stranger

select assert(
    (select count(*) from posts where id = 'aaaaaaaa-0000-0000-0000-000000000001') = 1,
    'stranger sees an approved post');

select assert(
    (select count(*) from posts where id = 'aaaaaaaa-0000-0000-0000-000000000002') = 0,
    'stranger does NOT see a pending post');

select assert(
    (select count(*) from posts where id = 'aaaaaaaa-0000-0000-0000-000000000003') = 0,
    'stranger does NOT see a festival-bound post');

select become('44444444-4444-4444-4444-444444444444');  -- credited
select assert(
    (select count(*) from posts where id = 'aaaaaaaa-0000-0000-0000-000000000003') = 1,
    'a credited user DOES see the festival-bound post');

select become('11111111-1111-1111-1111-111111111111');  -- author
select assert(
    (select count(*) from posts where id = 'aaaaaaaa-0000-0000-0000-000000000002') = 1,
    'author sees their own pending post');

select become('33333333-3333-3333-3333-333333333333');  -- moderator
select assert(
    (select count(*) from posts where author_id = (select v from t where k = 'author')) = 3,
    'moderator sees all three posts');

-- ---------------------------------------------------------------------------
-- 2. Write permission — the claim the migration depends on
-- ---------------------------------------------------------------------------

select become('22222222-2222-2222-2222-222222222222');  -- stranger
update posts set is_removed = true where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select assert(
    (select not is_removed from posts where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
    'stranger CANNOT remove another user''s post');

update posts set title = 'Hijacked' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select assert(
    (select title from posts where id = 'aaaaaaaa-0000-0000-0000-000000000001') = 'Approved Film',
    'stranger CANNOT edit another user''s post');

select become('33333333-3333-3333-3333-333333333333');  -- moderator
update posts set is_removed = true where id = 'aaaaaaaa-0000-0000-0000-000000000001';

select become_superuser();
select assert(
    (select is_removed from posts where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
    '>>> MODERATOR CAN REMOVE ANOTHER USER''S POST — the CloudKit blocker is gone <<<');

select assert(
    (select count(*) from audit_log
      where action = 'post_removed'
        and target_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 1,
    'the removal was written to audit_log');

-- ... and the removal is visible to everyone else, which the CloudKit overlay
-- existed to fake.
select become('22222222-2222-2222-2222-222222222222');
select assert(
    (select count(*) from posts where id = 'aaaaaaaa-0000-0000-0000-000000000001') = 0,
    'the moderator removal is visible to other users (no client-side overlay)');

select become_superuser();
update posts set is_removed = false where id = 'aaaaaaaa-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- 3. Likes
-- ---------------------------------------------------------------------------

select become('22222222-2222-2222-2222-222222222222');

insert into post_likes (post_id, profile_id)
select 'aaaaaaaa-0000-0000-0000-000000000001', v from t where k = 'stranger';
select assert(
    (select count(*) from post_likes where post_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 1,
    'a user can like a visible post');

-- Idempotency: the property the "like_<postID>_<userID>" record naming simulated.
select assert(
    (select count(*) from (
        insert into post_likes (post_id, profile_id)
        select 'aaaaaaaa-0000-0000-0000-000000000001', v from t where k = 'stranger'
        on conflict do nothing
        returning 1
    ) x) = 0,
    'double-liking is a no-op (composite PK)');

do $$
begin
    begin
        insert into post_likes (post_id, profile_id)
        select 'aaaaaaaa-0000-0000-0000-000000000001', v from t where k = 'author';
        raise exception 'FAIL: a user was able to like AS someone else';
    exception when insufficient_privilege or check_violation then
        raise notice 'pass: a user cannot like on another user''s behalf';
    end;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Messaging privacy
-- ---------------------------------------------------------------------------

select become('11111111-1111-1111-1111-111111111111');  -- author
select find_or_create_conversation((select v from t where k = 'stranger')) as convo \gset

insert into messages (conversation_id, sender_id, body)
select :'convo', v, 'private note' from t where k = 'author';

select assert(
    (select count(*) from messages where conversation_id = :'convo') = 1,
    'a participant reads their own conversation');

select assert(
    (select last_message_preview from conversations where id = :'convo') = 'private note',
    'the conversation preview trigger fired');

select become('33333333-3333-3333-3333-333333333333');  -- moderator
select assert(
    (select count(*) from messages where conversation_id = :'convo') = 0,
    'moderators CANNOT read private messages');

select become('11111111-1111-1111-1111-111111111111');
select assert(
    find_or_create_conversation((select v from t where k = 'stranger')) = :'convo',
    'find_or_create_conversation is idempotent');

-- ---------------------------------------------------------------------------
-- 5. Legacy account claiming
-- ---------------------------------------------------------------------------

select become('22222222-2222-2222-2222-222222222222');  -- stranger claims it first
select assert(
    (claim_legacy_profile('_abc123legacy') ->> 'status') = 'claimed',
    'a legacy profile can be claimed');

select assert(
    (select count(*) from posts
      where id = 'aaaaaaaa-0000-0000-0000-000000000009'
        and author_id = (select v from t where k = 'stranger')) = 1,
    'claiming backfills author_id on the legacy post');

select become('11111111-1111-1111-1111-111111111111');  -- someone else tries
select assert(
    (claim_legacy_profile('_abc123legacy') ->> 'status') = 'already_claimed',
    'a legacy profile CANNOT be claimed twice');

select assert(
    (claim_legacy_profile('_does_not_exist') ->> 'status') = 'not_found',
    'claiming an unknown legacy id fails cleanly');

-- ---------------------------------------------------------------------------
-- 6. Privilege escalation
-- ---------------------------------------------------------------------------

select become('22222222-2222-2222-2222-222222222222');
do $$
begin
    begin
        insert into moderators (profile_id)
        select id from profiles where auth_user_id = '22222222-2222-2222-2222-222222222222';
        raise exception 'FAIL: a user made THEMSELVES a moderator';
    exception when insufficient_privilege then
        raise notice 'pass: a user cannot grant themselves moderator';
    end;
end;
$$;

select become_superuser();
\echo ''
\echo 'All RLS assertions passed.'
rollback;
