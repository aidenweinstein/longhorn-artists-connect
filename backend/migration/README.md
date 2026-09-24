# CloudKit → Supabase migration

One-off script. Runs in three stages so the slow half can be repeated
independently of the risky half.

> **Status: unverified.** Never executed — there is no Supabase project and no
> export has been attempted. Treat the first run as a debugging session, not a
> migration. Run it against staging with `SKIP_ASSETS=1` first.

```
npm install
cp .env.example .env     # fill in CK_API_TOKEN and SUPABASE_*
npm run typecheck

SKIP_ASSETS=1 npm run export   # structural dry run, minutes
npm run export                 # full run with media, hours
npm run load
npm run verify
```

| Stage | Reads | Writes |
|---|---|---|
| `export` | CloudKit Web Services | `out/` on local disk |
| `load` | `out/` | Supabase (service role) |
| `verify` | both | nothing — exits non-zero on failure |

Export and load are separate because export downloads every video in the app.
You will want to re-run the load several times while fixing schema problems, and
paying for the download each time is unreasonable.

## Read `out/report.json` before loading

The export makes no decisions about damaged data — it records anomalies and
continues. The report lists posts with no resolvable creator, assets that failed
to download, assets whose container disagreed with what the record claimed,
skipped profiles, and orphaned likes/messages.

## Attribution, and why it can fail

`posts.legacy_author_cloudkit_id` comes from the record's `created.userRecordName`
in the CloudKit REST response. That is the value `claim_legacy_profile()` matches
on when a user signs in, so it is what reunites people with their posts.

**Verify this on the dry run.** CloudKit may return `_defaultOwner`, or omit the
creator entirely, for public-database records depending on container settings. If
`posts_without_creator` in the report is large, attribution has to fall back to
matching the `submittedBy` display name against `UserProfile` records — which is
lossy for duplicate names, and needs a decision before the production run.

Unattributed posts still load; they just have a null `author_id` until claimed.

## What is deliberately not migrated

- **`ModerationAction`** is folded into `posts.is_removed` at export time, then
  retired. It only ever existed because CloudKit refused to let a moderator write
  to someone else's post (`CloudKitManager.swift:896-901`). Nothing in the new
  schema reads it.
- **`ModerationEdit`** is exported to `rows/moderation_edits.json` but **not**
  applied. Each payload is a JSON-encoded `Submission` that overrode fields on
  another user's post, and mapping those fields back is lossy. Review them by
  hand after loading, apply what still matters directly to the post row, then
  delete the file.
- **Script PDFs cannot be migrated at all.** They were never uploaded to
  CloudKit — `Submission.scriptURL` reads only the author's local Documents
  directory (`SubmissionStore.swift:360-372`). They exist solely on the device
  that created them. Anyone who reinstalled has already lost theirs. If scripts
  matter, the cutover build needs to upload any it still finds locally *before*
  CloudKit is retired.
- **Film and music `releaseYear`.** The field exists on `Submission` but is only
  ever persisted for photography (`photographyReleaseYear`). This was already
  being dropped before the migration; there is nothing to recover.

## Known-absent fields

`orderedCrew`, `orderedCrewIDs` and `photographyEquipment` are missing from the
`PhotographySubmission` schema in **both** CloudKit environments. Every
photography record will therefore export with no crew and no equipment. That is
existing data loss being faithfully reproduced, not a bug in the script.

## MIME types are fixed here, once

`src/mime.ts` ports the byte-sniffing from
`CloudKitWebServices.containerExtension(forHeaderBytes:isAudio:)`
(`CloudKitWebServices.swift:198-219`), which the app currently runs at *playback
time, on every track*, because CloudKit typed files by filename and
`musicAudioExt` is unreliable. A wrong type produced AVFoundation `-11828`
"Cannot Open".

Running it once during migration, writing the result to `post_media.mime_type`
and setting it as the Storage object's Content-Type, means neither client ever
guesses again. `verify` asserts audio rows ended up with an `audio/*` type.

## Service role key

`load` and `verify` use `SUPABASE_SERVICE_ROLE_KEY`, which **bypasses RLS
entirely**. It has to: the loader writes rows for users who have not
authenticated yet, which RLS correctly forbids for any normal client.

This means the loader has no safety net. Point it at staging first. Never put
this key in an app. Revoke it when the migration is done.

## Cutover

Run twice: once into staging to shake out problems, then a final run during the
cutover window after CloudKit writes are frozen. Everything upserts on stable
ids, so a failed run can be repeated without duplicating rows.
