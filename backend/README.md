# Nexus backend (Supabase)

Postgres schema replacing the CloudKit public database, shared by the iOS app and
the forthcoming Android app.

> **Status: unverified.** These migrations have not been run. There is no Supabase
> project yet. Nothing here is proven until `backend/tests/rls_test.sql` passes
> against a real local stack — see *Running it* below. Expect to fix syntax and
> policy errors on the first pass.

## Why the migration exists

CloudKit is not just Apple's database, it is Apple's *identity system*, and the
app treats the two as one thing: a user's identity **is**
`CKContainer.userRecordID()`. An Android device cannot obtain one. So Android is
not reachable without real accounts, and real accounts are not reachable without
leaving CloudKit.

Two subsystems in the iOS app exist *only* to work around CloudKit and are
deleted by this schema rather than ported:

| iOS workaround | Why it existed | Replacement |
|---|---|---|
| `ModerationAction` / `ModerationEdit` (`CloudKitManager.swift:886-962`) | In the public DB only a record's creator may modify it, so moderating another user's post silently failed and the post repopulated. Moderators wrote parallel records that every client re-applied at sync. | `posts_update_own_or_moderator` in `0002_rls.sql`. Moderators just have UPDATE. |
| MIME byte-sniffing (`CloudKitWebServices.swift:141-219`) | CloudKit derived `Content-Type` from a `${f}` filename template, so the app range-requested the first 16 bytes of every track to guess the container. | `post_media.mime_type`, recorded at upload. We control the upload path on both clients. |

Much of `SubmissionStore`'s 2218 lines — `syncedRecordIDs`, `pendingUploadIDs`,
`hiddenSubmissionIDs`, `reconcileMissingLocalSubmission`, `applyModerationActions`,
`applyModerationEdit` — is likewise compensation for CloudKit's eventual
consistency and ownership rules. Budget to **delete** it, not port it.

## Files

| File | Contents |
|---|---|
| `migrations/0001_schema.sql` | Tables, enums, indexes |
| `migrations/0002_rls.sql` | Helper functions and every RLS policy |
| `migrations/0003_functions.sql` | Account claiming, feed view, conversation upsert, audit + account deletion |
| `migrations/0004_storage.sql` | Buckets and storage policies |
| `tests/rls_test.sql` | Assertions proving the permission model |

## Schema mapping

| CloudKit record type | Table |
|---|---|
| `FilmSubmission`, `MusicSubmission`, `ReelSubmission`, `ProjectSubmission`, `EventSubmission`, `PhotographySubmission` | `posts` (single table, `type` discriminator) |
| asset fields (`filmVideo`, `musicAudio`, `filmBTS`, …) | `post_media` |
| `filmCast` / `filmCastIDs` / `orderedCrew` / … | `post_credits` |
| `UserProfile` | `profiles` |
| `PostLike` | `post_likes` |
| `Conversation`, `Message` | `conversations`, `messages` |
| `Flag` | `reports` |
| `ModerationAction`, `ModerationEdit` | *(none — see above)* |

Three things worth knowing:

- **One `posts` table, not six.** The app already collapses all six types into a
  single `Submission` struct (`SubmissionStore.swift:84`) and only converts to
  per-type records at the boundary (`CloudKitTransitionAdapter.swift:54`).
- **Post IDs are preserved.** CloudKit record names for submissions are already
  UUID strings, so every ID in the shipped app stays valid — including
  `featured_work_ids` cross-references and cached media file names.
- **Credits become rows.** They were stored as `"<role>: <name>"` strings with a
  parallel ID array and re-split on `": "` when read
  (`MediaModels.swift:183-186`, `:297-313`), which corrupts any role or name
  containing a colon. `post_credits` fixes that; the migration script must handle
  already-corrupted historical rows.

## The claim flow has one chance to work

`claim_legacy_profile()` binds a user's CloudKit identity to their new account.
The only link between the two is the record name cached on their iPhone at
`ModeratorAccess.currentUserRecordNameKey` (written in `CloudKitManager.swift:44`).
It exists nowhere else — not on the server, not on another device.

A user who skips the cutover build and later reinstalls **loses it permanently**
and needs manual reattachment. This is why the forced-update gate ships before
the cutover, and why iOS must migrate before Android starts.

## Standing up the project

You need two environments: a **local** stack for iterating on the schema, and a
**hosted staging** project for the first real migration run. Production comes
third, at cutover.

### 1. Local stack (do this first)

Requires Docker Desktop running.

```sh
brew install supabase/tap/supabase
cd "<repo root>"          # the folder containing Longhorn Artists Connect.xcodeproj
supabase init             # creates supabase/ — say no to overwriting anything
```

`supabase init` creates its own `supabase/migrations/` directory. Point it at
ours instead of maintaining two copies:

```sh
rmdir supabase/migrations
ln -s ../backend/migrations supabase/migrations
```

Then:

```sh
supabase start            # first run pulls several GB of images
supabase db reset         # applies backend/migrations/ in filename order
```

`supabase start` prints your local API URL, anon key and service role key. Studio
is at http://127.0.0.1:54323.

Iterate here — `supabase db reset` is instant and destroys nothing that matters.

### 2. Run the permission tests

```sh
psql "$(supabase status -o json | jq -r .DB_URL)" -v ON_ERROR_STOP=1 \
     -f backend/tests/rls_test.sql
```

The test runs in a transaction and rolls back, so it is safe to re-run.

**Do not write client code until it passes.** The assertion labelled
`>>> MODERATOR CAN REMOVE ANOTHER USER'S POST <<<` is the one the entire
migration rests on; if it fails, the moderation overlay has to be rebuilt and the
plan needs revisiting.

### 3. Hosted staging project

At [supabase.com/dashboard](https://supabase.com/dashboard): **New project**.

- **Region:** `us-east-1` or `us-west-1` — closest to your users.
- **Plan:** Free is fine for staging. Production needs **Pro ($25/mo)**; the free
  tier's 1 GB storage and 5 GB egress will not hold this app's video, and free
  projects pause after a week of inactivity.
- Save the database password immediately; it is shown once.

Link and push:

```sh
supabase link --project-ref <your-project-ref>
supabase db push          # applies backend/migrations/ to the hosted project
```

Then re-run `rls_test.sql` against the hosted database — connection string is in
Dashboard → Settings → Database. Local Postgres and hosted Supabase differ in
extensions and auth schema details, so a pass locally is not a pass remotely.

### 4. Auth providers

Dashboard → Authentication → Providers:

- **Apple** — needs a Services ID, Key ID, Team ID and a `.p8` key from the Apple
  Developer portal. The app is already entitled
  (`com.apple.developer.applesignin`).
- **Google** — OAuth client IDs from Google Cloud Console. You need *three*: Web
  (Supabase uses it server-side), Android (tied to your signing SHA-1), and iOS.
  The Android one cannot be created until the app is signed, so defer it.
- **Email** — enable magic link, disable signups-without-confirmation.

Add redirect URLs for both apps' custom schemes under Authentication → URL
Configuration.

### 5. Grant yourself moderator

There is deliberately no API path to do this — see the `moderators` table note in
`0002_rls.sql`. Sign in once through the app, then in Studio's SQL editor:

```sql
insert into moderators (profile_id)
select id from profiles where auth_user_id =
    (select id from auth.users where email = 'you@example.com');
```

### 6. Migrate the data

See `backend/migration/README.md`. Run it against staging with `SKIP_ASSETS=1`
first.

## Not yet built

- **Migration script** (`backend/migration/`) — exports CloudKit via the REST API
  and loads Postgres. Reuse the endpoint and token handling from
  `CloudKitWebServices.assetFieldLookup` (`:313-380`), and heed the pagination
  lesson in `CloudKitManager.fetchAllRecords` (`:163-175`): **follow the cursor**,
  or you export a partial dataset.
- **FCM Edge Function** — trigger on `messages` INSERT. Supabase has no push; FCM
  covers Android natively and relays to APNs for iOS. Replaces
  `CKQuerySubscription` (`MessageRecordHandling.swift:918-990`).
  Feed sync does *not* need push — use Realtime `postgres_changes` on `posts`.
- **HLS** — route film/reel video through Cloudflare Stream or Mux and store the
  playback ID in `post_media.storage_path`. Supabase Storage supports HTTP range
  requests, so progressive playback works without this; treat it as a follow-on,
  not a blocker.
- **Account-deletion web endpoint** — `delete_my_account()` exists, but both
  Google Play and App Store review also require a publicly reachable deletion
  request URL.
