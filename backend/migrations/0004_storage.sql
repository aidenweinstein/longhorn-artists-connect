-- 0004_storage.sql
-- Storage buckets and their access policies.
--
-- Path conventions (keep both clients in sync with these):
--   media/<post_id>/<kind>/<uuid>.<ext>     e.g. media/3F2A.../video/  a1b2.mov
--   avatars/<profile_id>.jpg
--
-- The first path segment of a `media` object is the post ID, which is what the
-- policies below key off. Do not flatten it.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
    -- Private: access is via signed URLs only, so an unapproved, removed, or
    -- festival-bound post's media is not reachable by guessing a path. CloudKit's
    -- downloadURL had no such gate.
    ('media', 'media', false, 2147483648, null),
    -- Public: avatars appear throughout the directory and every feed row;
    -- signing each one would add a round trip per cell.
    ('avatars', 'avatars', true, 10485760,
     array['image/jpeg', 'image/png', 'image/heic', 'image/webp'])
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- media
-- ---------------------------------------------------------------------------
-- Reuses can_view_post()/owns_post() from 0002 so storage visibility can never
-- drift from row visibility.

create policy media_read_if_post_visible on storage.objects
    for select to authenticated
    using (
        bucket_id = 'media'
        and can_view_post(((storage.foldername(name))[1])::uuid)
    );

create policy media_write_if_post_owner on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'media'
        and (
               owns_post(((storage.foldername(name))[1])::uuid)
            or is_moderator()
        )
    );

create policy media_update_if_post_owner on storage.objects
    for update to authenticated
    using (
        bucket_id = 'media'
        and (owns_post(((storage.foldername(name))[1])::uuid) or is_moderator())
    );

create policy media_delete_if_post_owner on storage.objects
    for delete to authenticated
    using (
        bucket_id = 'media'
        and (owns_post(((storage.foldername(name))[1])::uuid) or is_moderator())
    );

-- ---------------------------------------------------------------------------
-- avatars
-- ---------------------------------------------------------------------------
-- Object name is "<profile_id>.<ext>"; a user may only write their own.

create policy avatars_read_all on storage.objects
    for select to anon, authenticated
    using (bucket_id = 'avatars');

create policy avatars_write_own on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'avatars'
        and split_part(name, '.', 1) = current_profile_id()::text
    );

create policy avatars_update_own on storage.objects
    for update to authenticated
    using (
        bucket_id = 'avatars'
        and split_part(name, '.', 1) = current_profile_id()::text
    );

create policy avatars_delete_own on storage.objects
    for delete to authenticated
    using (
        bucket_id = 'avatars'
        and (split_part(name, '.', 1) = current_profile_id()::text or is_moderator())
    );
