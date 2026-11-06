# Nexus on the Web — Implementation Plan

Goal: a website that serves the same Nexus content as the iOS app, instead of an Android port.

> **File-and-function manifest: `web/BUILD_PLAN.md`.** This document covers why and
> in what order; that one lists every file to create and the functions inside it.

## Why this is much cheaper than an Android port

An Android port means reimplementing ~20k lines of SwiftUI *and* solving CloudKit access
from a non-Apple platform. The website solves only the second problem, and you already
have most of the answer:

- Every record type the site needs is in the **public** CloudKit database of
  `iCloud.LAA.Longhorn-Artists-Connect` — `FilmSubmission`, `MusicSubmission`,
  `ReelSubmission`, `PhotographySubmission`, `ProjectSubmission`, `EventSubmission`,
  legacy `Submission`, `UserProfile`, `PostLike`, `ModerationAction`, `ModerationEdit`,
  `Flag`, `Organization`, `OrgContentLink`, and (added 2026-11-04) `CreativeProfile` and
  `DirectoryListing` — a person's base profile style (Filmmaker / Actor / Musician) with
  its details and headshot, and the moderator's decision to list them on the public
  Actors / Filmmakers / Musicians pages. See `13) Profile Styles/CreativeProfileStore.swift`.
- `10) Cloudkit/CloudKitWebServices.swift` is already a working CloudKit Web Services
  REST client (record lookup + `downloadURL` assets + range streaming). The website uses
  the same API, from a server instead of from the app.
- Assets come back as short-lived signed CDN URLs that support HTTP range requests —
  exactly what `<img>` and `<video>` want.

**Phase 1 requires zero changes to the iOS app and zero changes to the CloudKit schema.**

## Recommended architecture

A **Next.js (App Router, TypeScript) app with a thin server layer** that talks to CloudKit
Web Services using a **server-to-server key**, deployed on Vercel or Cloudflare.

```
browser ──► Next.js server (Node)                    ──► CloudKit Web Services REST
             ├── /api/feed          cached 60s            (server-to-server key,
             ├── /api/post/[t]/[id] cached 5m               public DB, production env)
             ├── /api/profile/[id]  cached 5m
             └── /api/asset/[r]/[f] 302 → signed CDN URL (no-store)
                                                     ──► Cloudflare Stream / Mux (HLS)
```

Why a server and not a pure CloudKit JS single-page app:

| Concern | Server + REST (recommended) | Pure CloudKit JS SPA |
|---|---|---|
| Browsing without signing in | Yes — server holds the credential | Needs an API token in client JS; user-specific data needs an iCloud popup |
| Credential exposure | Private key stays server-side | Token ships to every visitor |
| CloudKit read quota | One cached fetch serves all visitors | Every visitor hits CloudKit directly |
| Moderation filtering | Enforced server-side, can't be bypassed | Client-side only — trivially bypassed |
| SEO / link previews | Server-rendered | Empty HTML shell |
| Path to HLS video | Server can run the transcode pipeline | No place to put it |

The pure-CloudKit-JS route is the "weekend MVP" option if you want something on screen in
two days. It is a dead end for anything past read-only browsing, so only take it as a demo.

## Phase 0 — Three spikes, before committing to anything

Each is a few hours and each one can invalidate a later phase.

1. **Server-to-server key works.** Create a server-to-server key in CloudKit Dashboard
   (container → Tokens & Keys), then from a Node script sign an ECDSA P-256 request to
   `POST /database/1/iCloud.LAA.Longhorn-Artists-Connect/production/public/records/query`
   for `FilmSubmission`. Confirm you get records and a `downloadURL` for `filmThumbnail`.
   Reuse the field names and the `${f}` filename substitution logic already documented in
   `CloudKitWebServices.swift` — the CDN derives `Content-Type` from that filename, and
   getting it wrong is what caused the `-11828` playback failures in the app.
2. **Web identity ↔ app identity.** The app identifies users by
   `CKContainer.default().userRecordID().recordName`, and profile records are named
   `UserProfile_<userRecordID>` (see `1) App/UserProfileManager.swift:57-65`). Confirm that
   CloudKit JS's Apple ID sign-in returns that *same* `userRecordName` for your own account
   in this container. **This single fact decides the whole Phase 3 write story.** If it
   holds, web accounts are app accounts for free. If it doesn't, writes need an account
   linking flow (sign in on the app → short code → enter on web), which is a week of work
   on its own. Note that plain Sign in with Apple JS gives a different `sub` identifier and
   is *not* a substitute.
3. **What do the videos actually contain?** Pull three real production `filmVideo` /
   `reelVideo` assets and run `ffprobe`. The app uploads QuickTime `.mov` exports
   (`CloudKitWebServices.defaultExtension(for:)`), and `.mov` is not a web-baseline
   container — HEVC-in-MOV will not play in Chrome or Firefox at all. The result tells you
   whether Phase 2 is "nice to have" or "the site has no video without it".

## Phase 1 — Read-only public site

The bulk of the value. No app changes, no schema changes.

### Data layer

- `lib/cloudkit/client.ts` — signed REST client: `query`, `lookup`, `assetURL`. Port the
  environment handling from `CloudKitWebServices.swift` — default to **production**, since
  all real content lives there.
- `lib/cloudkit/records.ts` — typed decoders, one per record type, mirroring the
  `from(record:)` initializers in `8) Records/MediaModels.swift` (`Film` :74, `Music` :367,
  `Reel` :629, `Photography` :821, `Project` :1000, `Event` :1268). Decode defensively:
  the app already has scars from fields missing in one environment
  (`orderedCrew`, `photographyEquipment`, `lyrics`), so every field is optional with a
  fallback, and an unknown field is never fatal.
- `SCHEMA.md` — the one hand-maintained artifact tying Swift and TypeScript together.
  Add a note in `MediaModels.swift` pointing at it so future field additions update both.

### Correctness requirements (not optional)

- **Moderation parity.** Fetch `ModerationAction` on every revalidation and drop every
  post with `isRemoved == 1` *server-side* before it reaches the browser, matching
  `8) Records/SubmissionStore.swift:1381-1400`. Apply `ModerationEdit` overrides too. A
  post a moderator removed must not be reachable on the web, including by direct URL.
- **Feed ranking parity.** Port the v1 ranking from `8) Records/Algorithms.swift`: order by
  `PostLike` count, seeded-random tie-break, seen posts sink below unseen. Seen state is
  per-device in the app (`UserDefaults` key `seenContentIDs`), so per-browser
  `localStorage` is the faithful equivalent.
- **Asset URLs are short-lived.** Never bake a `downloadURL` into cached HTML. Serve
  `/api/asset/[recordName]/[field]` that resolves a fresh URL and returns a `302`, with
  `Cache-Control: no-store` on the redirect itself.

### Pages

| Route | Content | Source |
|---|---|---|
| `/` | Home feed (films, music, reels, photography) | `A) HomeView.swift` |
| `/discover` | Projects + events | `B) DiscoverView.swift` |
| `/film/[id]`, `/music/[id]`, `/reel/[id]`, `/photo/[id]` | Post detail | `4) HomePage/*Card.swift` |
| `/project/[id]`, `/event/[id]` | Post detail | `5) DiscoverPage/*Card.swift` |
| `/u/[userRecordName]` | Profile + portfolio, honoring `portfolioOrder`, with the base-profile section (actor sheet / filmography / discography) | `E) PortfolioView.swift`, `13) Profile Styles/StyledProfileSection.swift` |
| `/studios`, `/studios/[id]` | Organizations | `Collective Studios.swift`, `E3) StudioPageView.swift` |
| `/now` | The viewer's current projects and openings for their base profile | `13) Profile Styles/NowView.swift` |
| `/actors`, `/filmmakers`, `/musicians` | Moderator-approved profiles by base profile | `13) Profile Styles/CreativeDirectoryView.swift` |

Explicitly **out of scope for Phase 1**: Share (uploads), Network (DMs), Moderate.

### Design

Port the brand primitives, not the layout. `1) App/NexusColors.swift` and
`2) Onboarding/FontExtensions.swift` become CSS custom properties and a Tailwind theme.
Do not try to reproduce `ScreenSizeFormat`-driven toolbar tuning — the web equivalent is
ordinary responsive breakpoints.

**Estimate: 3–4 weeks** for one developer, most of it in decoders and the six card layouts.

## Phase 2 — Video and audio that actually play

Depends on spike 3. If any production video is HEVC or plain `.mov`, this phase is a
prerequisite for launch, not an enhancement.

- **Pipeline.** A scheduled worker queries each submission type for records lacking an
  `hlsPlaybackID`, fetches the asset via `downloadURL`, uploads to **Cloudflare Stream**
  (cheaper, simpler) or **Mux** (better analytics/API), then writes `hlsPlaybackID` back to
  the CloudKit record.
- **Schema change — add the field in BOTH environments first.** Add `hlsPlaybackID`
  (String, queryable) to all five media record types in development *and* production before
  any code writes it. Saving an unknown field is what made production photography and music
  posts flash and vanish; the save path now drops unknown fields silently, which would make
  this fail invisibly instead.
- **Web player.** `hls.js` everywhere, native HLS on Safari.
- **Audio needs nothing.** Production music assets are MP3, which is web-baseline — serve
  them straight through `/api/asset`.
- **This is the same pipeline iOS wants.** Once `hlsPlaybackID` exists, the app can play
  HLS instead of range-streaming a `.mov`, which is the fast-video work already at the top
  of your list. One pipeline, both clients — the website is the forcing function that pays
  for it.

**Estimate: 1.5–2 weeks** plus transcode/egress cost (Cloudflare Stream is roughly $5 per
1000 minutes stored, $1 per 1000 minutes delivered).

## Phase 3 — Accounts and writes (optional)

Gated entirely on spike 2.

- Sign in via CloudKit JS Apple ID button → `userRecordName` → the user *is* their app
  account. Enables likes (`PostLike`), saved posts, and profile edits with no data model
  work.
- **Web uploads are the expensive part.** CloudKit REST asset upload is a two-step
  (`assets/upload` → include the receipt in the record save), and the app does client-side
  video compression (`8) Records/VideoCompressionHelper.swift`) that a browser can't match.
  If you do web uploads, route the raw file through the Phase 2 transcode pipeline rather
  than trying to reproduce the app's export settings.
- **DMs: defer.** `Conversation` and `Message` are in the public database and the app relies
  on CloudKit push subscriptions, which browsers don't get. Web DMs mean polling, and the
  privacy exposure of DM records in a public database deserves its own review before
  adding a second client. Recommend not shipping messaging on web in v1.
- **Do not replicate moderator mode.** `isModeratorMode` is a local password-gated
  `AppStorage` flag (`1) App/SecurityConfiguration.swift:185-190`). On the web that model
  provides no security at all. Keep moderation app-only.

**Estimate: 2–3 weeks** for auth + likes + saves; +2 weeks if web uploads are included.

## Phase 4 — Launch

- Domain, `robots.txt`, `sitemap.xml`, Open Graph tags per post.
- Analytics and error tracking; alert on CloudKit quota and HTTP 503 `THROTTLED`.
- Load-test the feed endpoint with caching disabled to find the real CloudKit read cost.

## The one decision that needs your call

> **Decided 2026-09-23: option 3 — everything behind sign-in**, reading and
> posting both. Nothing is public on the web. As this section warned, that
> inverts the phase order: auth is now steps 7–8 of the build, not Phase 3, and
> SEO / shareable links / link previews are forfeited. Tracked in
> `web/BUILD_PLAN.md` § "Access policy", which also carries the follow-on
> decision — whether "signed in" means an Apple ID or a verified `.edu`.

**Is Nexus content public on the open web, or behind a login?**

Phase 1 as written makes student posts, names, majors, class years, bios, Instagram
handles, and profile photos publicly crawlable and Google-indexable. Today that data is
only visible inside an app that requires an iCloud account, and the app even carries
`9) User Interaction/ScreenshotProtection.swift` — a posture that is impossible to maintain
in a browser.

Three options, in increasing order of effort:

1. **Fully public.** Best for reach and for artists sharing portfolio links. Needs a
   heads-up to existing users and probably a `listedOnWeb` opt-out field on `UserProfile`.
2. **Posts public, profiles gated.** Content and credits are public; the member directory
   and personal details require sign-in. Reasonable default.
3. **Everything behind Apple ID sign-in.** Preserves today's privacy properties, but
   forfeits SEO, shareable links, and most of the reason to build a website. Also inverts
   the phase order — Phase 3 auth becomes a Phase 1 prerequisite.

I'd recommend **option 2**, but it's a community/privacy call rather than a technical one.

## Deliberately not doing: mirroring CloudKit into Postgres

Tempting — a real database would make feeds, search, and ranking trivial. But it means a
dual-write consistency problem between the app and the mirror, and it would silently
diverge exactly where the schema already has environment gaps.

Read CloudKit directly and cache aggressively. Revisit only if read quota or query
limitations actually bite; at that point mirror **read-only** via a scheduled sync with
CloudKit remaining the single source of truth.

## Sequenced summary

| Phase | Work | Blocks on | Estimate |
|---|---|---|---|
| 0 | Three spikes: S2S key, web identity, video codecs | — | 2–3 days |
| 1 | Read-only site: data layer, 6 card types, feed, profiles | Spike 1 | 3–4 weeks |
| 2 | HLS pipeline + `hlsPlaybackID` schema, web player | Spike 3 | 1.5–2 weeks |
| 3 | Apple ID auth, likes, saves, profile edits | Spike 2 | 2–3 weeks |
| 4 | Domain, SEO, monitoring, load test | 1, 2 | 1 week |

A launchable read-only Nexus web presence is roughly **5–7 weeks**; feature parity minus
messaging and moderation is **9–12 weeks**. Compare that to an Android port, which starts
at "reimplement every screen" and still has to solve CloudKit access from scratch.
