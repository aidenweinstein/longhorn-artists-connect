# Nexus Web — file and function manifest

Companion to `../NEXUS_WEB_PLAN.md`. That document argues *why* and sequences the
phases; this one is the build manifest: every file to create, and the functions
inside it.

**Status: nothing in this document is written yet.** The only files in `web/`
today are `scripts/spike-cloudkit.mjs` and the gitignored `.secrets/`. Treat
every signature below as a proposal — they're grounded in the real Swift field
lists and record names (cited per row), but no line of it has compiled.

Scope is **Phase 1**, the read-only public site, plus the shared plumbing Phase 2
and 3 build on. Phases 2–4 get a short section at the end rather than a full
manifest, because their shape depends on decisions Phase 1 makes.

## Blocked before any of this runs

`.secrets/cloudkit.env` has `CLOUDKIT_KEY_ID=` with an **empty value**. The
keypair in `.secrets/cloudkit-s2s-key.pem` was generated but its public half was
never registered, so every signed request would 401.

```sh
openssl ec -in web/.secrets/cloudkit-s2s-key.pem -pubout   # paste into Dashboard
# CloudKit Dashboard → container → Tokens & Keys → Server-to-Server Keys
# then paste the Key ID it returns into web/.secrets/cloudkit.env
```

Then `node web/scripts/spike-cloudkit.mjs` is Phase 0 spike 1, and it must pass
before the manifest below is worth building.

One gotcha the existing PEM walks straight into: it's `BEGIN EC PRIVATE KEY`
(SEC1). Node's `crypto.createSign` accepts that directly, so `lib/cloudkit/sign.ts`
below is fine — but if any of this is ever moved to a Cloudflare Worker or Edge
runtime, WebCrypto can only import PKCS#8 and you'll need
`openssl pkcs8 -topk8`. This is the exact trap documented at
`verification-service/src/cloudkit.ts:18-23`.

## Stack

Next.js App Router, TypeScript, Tailwind, deployed on Vercel. Node runtime (not
Edge) for anything that signs a CloudKit request, per the SEC1 note above.

## File tree

```
web/
├── BUILD_PLAN.md                 ← this file
├── SCHEMA.md                     ← hand-maintained Swift↔TS field map
├── package.json
├── tsconfig.json
├── next.config.ts
├── tailwind.config.ts
├── .env.example
├── scripts/
│   └── spike-cloudkit.mjs        ← exists already (Phase 0)
├── middleware.ts                 ← gates every route; the whole site is private
├── lib/
│   ├── env.ts
│   ├── auth.ts
│   ├── session.ts
│   ├── types.ts
│   ├── theme.ts
│   ├── cloudkit/
│   │   ├── sign.ts
│   │   ├── client.ts
│   │   ├── recordTypes.ts
│   │   ├── feedKeys.ts
│   │   ├── decode.ts
│   │   ├── credits.ts
│   │   └── records.ts
│   ├── moderation.ts
│   ├── ranking.ts
│   ├── likes.ts
│   ├── seen.ts
│   └── feed.ts
├── app/
│   ├── layout.tsx
│   ├── globals.css
│   ├── page.tsx                          /
│   ├── discover/page.tsx                 /discover
│   ├── film/[id]/page.tsx
│   ├── music/[id]/page.tsx
│   ├── reel/[id]/page.tsx
│   ├── photo/[id]/page.tsx
│   ├── design/[id]/page.tsx
│   ├── project/[id]/page.tsx
│   ├── event/[id]/page.tsx
│   ├── u/[userRecordName]/page.tsx
│   ├── studios/page.tsx
│   ├── studios/[id]/page.tsx
│   ├── signin/page.tsx                   ← the only ungated route
│   ├── robots.ts                         ← Disallow: /
│   └── api/
│       ├── auth/request/route.ts
│       ├── auth/callback/route.ts
│       ├── auth/signout/route.ts
│       └── asset/[recordName]/[field]/route.ts
├── components/
│   ├── FilmCard.tsx
│   ├── MusicCard.tsx
│   ├── ReelCard.tsx
│   ├── PhotographyCard.tsx
│   ├── DesignCard.tsx
│   ├── ProjectCard.tsx
│   ├── EventCard.tsx
│   ├── PostGrid.tsx
│   ├── CreditList.tsx
│   ├── AssetImage.tsx
│   └── VideoPlayer.tsx
└── test/
    ├── sign.test.ts
    ├── decode.test.ts
    ├── credits.test.ts
    ├── moderation.test.ts
    └── ranking.test.ts
```

## lib/env.ts

Server-only credential loading. Throws on first access if misconfigured, so a
missing key fails at boot rather than as a 401 per request.

| Export | Signature | Does |
|---|---|---|
| `CloudKitCreds` | `interface { keyID: string; privateKeyPem: string; container: string; environment: "development" \| "production" }` | Credential bundle. |
| `cloudKitCreds` | `(): CloudKitCreds` | Reads `CLOUDKIT_KEY_ID`, `CLOUDKIT_PRIVATE_KEY`, `CLOUDKIT_CONTAINER`, `CLOUDKIT_ENVIRONMENT`. Defaults environment to `production` — all real content lives there (`NEXUS_WEB_PLAN.md` "Data layer"). Throws naming the missing variable. |

Never import this from a client component.

## middleware.ts

The whole site is private, so gating lives in one place rather than being
re-asserted per route. A route that forgets to check is the failure mode; a
default-deny middleware makes forgetting impossible.

| Export | Signature | Does |
|---|---|---|
| `middleware` | `(req: NextRequest) => NextResponse` | Redirects to `/signin?next=<path>` unless a valid session cookie is present. |
| `config` | `{ matcher: [...] }` | Matches **everything** except `/signin`, `/api/auth/*`, and static assets. Allowlist, not denylist. |

`/api/asset/*` is matched too. Gating pages but not assets would leave every
image and video fetchable by URL — the pages would be private and the content
wouldn't be.

## lib/auth.ts + lib/session.ts

| Export | Signature | Does |
|---|---|---|
| `VerifiedIdentity` | `interface { email: string; schoolID: string; domainKind: string }` | What the Worker returns on a confirmed code. **No `userRecordName`** — a web session is not an app identity. |
| `Session` | `interface { email: string; schoolID: string; domainKind: string; issuedAt: number }` | |
| `createSession` | `(identity: VerifiedIdentity) => Promise<string>` | Signs a session cookie (httpOnly, secure, sameSite=lax). |
| `requestCode` | `(email: string) => Promise<{ pendingID: string }>` | Server-side call to `/v1/web/session/request`. |
| `confirmCode` | `(pendingID: string, code: string) => Promise<VerifiedIdentity>` | Server-side call to `/v1/web/session/confirm`. |
| `readSession` | `(req: NextRequest \| cookies()) => Session \| null` | Verifies and decodes; returns `null` on expiry or bad signature. |
| `requireSession` | `() => Promise<Session>` | Server-component helper; throws to the `/signin` redirect. |
| `destroySession` | `() => void` | |

Auth is a `.edu` code from the `verification-service` Worker — see "The web
sign-in flow" below for the endpoints it needs and why the existing ones don't
fit.

## lib/cloudkit/sign.ts

Port of `verification-service/src/cloudkit.ts:24-98`, which is already proven by
that service's tests.

| Export | Signature | Does |
|---|---|---|
| `signedHeaders` | `(path: string, bodyText: string, creds: CloudKitCreds) => Record<string, string>` | Builds `[date]:[base64(sha256(body))]:[path]`, signs ECDSA P-256, returns the three `X-Apple-CloudKit-Request-*` headers. `path` must exclude the query string. |
| `p1363ToDer` | `(raw: Uint8Array) => Uint8Array` | Only needed if this moves to WebCrypto; Node's signer already emits DER. Kept so the Worker and the site share one implementation. Copy the tests from `verification-service/test/units.test.ts`. |

## lib/cloudkit/client.ts

| Export | Signature | Does |
|---|---|---|
| `CKRecord` | `interface { recordName: string; recordType: string; recordChangeTag?: string; created?: { userRecordName?: string; timestamp?: number }; fields: Record<string, { value: unknown; type?: string }> }` | Raw REST record shape. |
| `queryRecords` | `(recordType: string, opts?: { desiredKeys?: string[]; sortBy?: string; filterBy?: CKFilter[]; limit?: number; marker?: string }) => Promise<{ records: CKRecord[]; marker?: string }>` | One page of `records/query`. |
| `queryAll` | `(recordType: string, opts?) => Promise<CKRecord[]>` | **Follows the continuation marker to exhaustion.** Not optional: `CloudKitManager.fetchAllRecords` (`:462`) learned this the hard way, and `backend/README.md:186` calls it out — a single page silently truncates the dataset. |
| `lookupRecords` | `(recordNames: string[], desiredKeys?: string[]) => Promise<CKRecord[]>` | `records/lookup`. Per-record errors come back inside a 200; drop them rather than throwing. |
| `assetURL` | `(field: { value: { downloadURL?: string } } \| undefined, filename: string) => string \| null` | Substitutes `${f}` in the CDN template with `filename`. **The filename decides `Content-Type`** — see `SCHEMA.md` and the `-11828` history in `CloudKitWebServices.swift`. |

## lib/cloudkit/recordTypes.ts

Direct mirror of `10) Cloudkit/CloudKitRecordTypes.swift`. Same names, same
groupings, so a schema change is a two-file edit with an obvious diff.

| Export | Signature |
|---|---|
| `RecordTypes` | `const` object: `film`, `music`, `reel`, `project`, `event`, `photography`, `design`, `legacySubmission`, `postLike`, `moderationAction`, `moderationEdit`, `flag`, `userProfile`, `verification`, `organization`, `orgContentLink`, `conversation`, `message` |
| `LIVE_SUBMISSIONS` | `readonly string[]` — the seven postable types |
| `ALL_SUBMISSIONS` | `LIVE_SUBMISSIONS` + `legacySubmission` |
| `PostType` | `"film" \| "music" \| "reel" \| "photography" \| "design" \| "project" \| "event"` — the URL segment union |
| `recordTypeFor` | `(type: PostType) => string` |
| `postTypeFor` | `(recordType: string) => PostType \| null` |

Note `DesignSubmission` and `Flag` exist in **neither** CloudKit environment as of
2026-09-23, so `design` queries will error until the type is created. `queryAll`
callers must tolerate a missing record type without failing the whole feed.

## lib/cloudkit/feedKeys.ts

Copies of the `desiredKeys` allowlists at `CloudKitManager.swift:484-561`.

| Export | Signature | Does |
|---|---|---|
| `FEED_KEYS` | `Record<PostType, string[]>` | Per-type allowlist. |
| `DETAIL_KEYS` | `Record<PostType, string[]>` | Feed keys plus the heavy fields a detail page needs (`filmStills`, `filmBTS`, `lyrics`, …). |

**`desiredKeys` is an allowlist, and omitting a field parses it as nil.** That
single fact caused the vanishing lineup, artist and Featured Work bugs the Swift
comments at `:511`, `:536` and `:540` document. Copy the lists verbatim; don't
trim them.

Fields per type, as they stand today:

| Type | Feed keys |
|---|---|
| film | `filmTitle`, `filmDescription`, `isApproved`, `submittedBy`, `createdDate`, `lastEditedDate`, `filmLogline`, `filmAgeRating`, `filmExplicit`, `filmStudio`, `filmGenres`, `filmCast`, `filmCastIDs`, `filmCrew`, `filmCrewIDs`, `filmVideoDuration` |
| music | `musicTitle`, `musicDescription`, `isApproved`, `submittedBy`, `createdDate`, `lastEditedDate`, `musicArtist`, `musicCategory`, `musicExplicit`, `musicGenres`, `musicSpotifyLink`, `musicAppleMusicLink`, `amazonMusicLink`, `youtubeMusicLink`, `soundcloudLink`, `lyrics`, `musicRecording`, `musicRecordingIDs`, `musicProduction`, `musicProductionIDs`, `musicAudioExt`, `musicAudioDuration` |
| reel | `reelTitle`, `reelDescription`, `isApproved`, `submittedBy`, `createdDate`, `lastEditedDate`, `reelType`, `orderedCrew`, `orderedCrewIDs`, `reelArtist`, `featuredWork`, `featuredWorkManual`, `reelVideoDuration` |
| project | `projectTitle`, `projectDescription`, `isApproved`, `submittedBy`, `createdDate`, `lastEditedDate`, `projectShootDatesText`, `projectShootStart`, `projectReleaseDateText`, `projectExpectedReleaseDate`, `projectGenres`, `projectCastNeeded`, `projectCrewNeeded`, `projectCastAssembled`, `projectCastAssembledIDs`, `projectCrewAssembled`, `projectCrewAssembledIDs`, `projectSlides` |
| event | `eventTitle`, `eventDescription`, `isApproved`, `submittedBy`, `createdDate`, `lastEditedDate`, `eventStartTime`, `eventEndTime`, `eventLocationText`, `eventLocation`, `eventHost`, `eventCategory`, `eventTicketsURL`, `eventLineup`, `eventExpectations`, `eventApplicationURL`, `eventShowtimes` |
| photography | `photographyTitle`, `photographyDescription`, `isApproved`, `submittedBy`, `createdDate`, `lastEditedDate`, `photographyArtist`, `photographyReleaseYear`, `photographyImages`, `photographyEquipment`, `orderedCrew`, `orderedCrewIDs` |
| design | `designTitle`, `designDescription`, `isApproved`, `submittedBy`, `createdDate`, `lastEditedDate`, `designCategory`, `designReleaseYear`, `designImages`, `designVideoDuration`, `orderedCrew`, `orderedCrewIDs` |

Asset fields, deliberately **not** in the feed lists (fetched per-post or via
`/api/asset`): `filmVideo`, `filmThumbnail`, `filmStills`, `filmBTS`,
`musicAudio`, `musicCover`, `musicVideo`, `reelVideo`, `reelThumbnail`,
`projectPoster`, `eventFlyer`, `photographyThumbnail`, `designVideo`,
`designThumbnail`.

## lib/cloudkit/decode.ts

Defensive primitives. Every one returns a fallback rather than throwing —
`NEXUS_WEB_PLAN.md` "Data layer" makes this a requirement, and the schema-gap
history is why.

| Export | Signature |
|---|---|
| `str` | `(r: CKRecord, key: string, fallback?: string) => string` |
| `optStr` | `(r: CKRecord, key: string) => string \| null` |
| `num` | `(r: CKRecord, key: string, fallback?: number) => number` |
| `optNum` | `(r: CKRecord, key: string) => number \| null` |
| `bool` | `(r: CKRecord, key: string) => boolean` — CloudKit stores these as 0/1 |
| `strList` | `(r: CKRecord, key: string) => string[]` — tolerates a single string where a STRING_LIST was expected, the `eventLineup` type mismatch |
| `date` | `(r: CKRecord, key: string) => Date \| null` — CloudKit timestamps are epoch **milliseconds** |
| `assetRef` | `(r: CKRecord, key: string) => { downloadURL: string } \| null` |
| `assetRefList` | `(r: CKRecord, key: string) => { downloadURL: string }[]` |

## lib/cloudkit/credits.ts

| Export | Signature | Does |
|---|---|---|
| `Credit` | `interface { role: string; name: string; userRecordName: string \| null }` | |
| `parseCredits` | `(entries: string[], ids: string[]) => Credit[]` | Splits the `"<role>: <name>"` encoding and zips the parallel ID array. |

Split on the **first** `": "` only. `MediaModels.swift:183-186` splits naively, so
a role or name containing a colon corrupts — `backend/README.md:63-67` flags the
same bug. Don't port the bug; do keep the output stable for already-corrupted
historical rows.

## lib/cloudkit/records.ts

One decoder per type, mirroring the `from(record:)` initializers in
`8) Records/MediaModels.swift` (Film `:199`, Music `:495`, Reel `:795`,
Photography `:980`, Design `:1172`, Project `:1376`, Event `:1708`).

| Export | Signature |
|---|---|
| `decodeFilm` | `(r: CKRecord) => Film \| null` |
| `decodeMusic` | `(r: CKRecord) => Music \| null` |
| `decodeReel` | `(r: CKRecord) => Reel \| null` |
| `decodePhotography` | `(r: CKRecord) => Photography \| null` |
| `decodeDesign` | `(r: CKRecord) => Design \| null` |
| `decodeProject` | `(r: CKRecord) => Project \| null` |
| `decodeEvent` | `(r: CKRecord) => Event \| null` |
| `decodeUserProfile` | `(r: CKRecord) => UserProfile \| null` |
| `decodeOrganization` | `(r: CKRecord) => Organization \| null` |
| `decodePost` | `(r: CKRecord) => Post \| null` | dispatches on `recordType` |

`null` means "unusable" (no title, no id) and the caller drops it. An unknown or
missing *field* is never fatal.

## lib/moderation.ts

Parity with `8) Records/SubmissionStore.swift:1381-1400`. **Enforced server-side
before anything reaches the browser**, including on direct-URL detail pages — a
removed post must be unreachable, not merely unlisted.

| Export | Signature | Does |
|---|---|---|
| `ModerationState` | `interface { removedIDs: Set<string>; edits: Map<string, Record<string, unknown>> }` | |
| `fetchModerationState` | `() => Promise<ModerationState>` | `queryAll` over `ModerationAction` + `ModerationEdit`. Called on every revalidation. |
| `isRemoved` | `(state: ModerationState, postID: string) => boolean` | `isRemoved == 1`. |
| `applyEdits` | `<T extends Post>(state: ModerationState, post: T) => T` | Overlays `ModerationEdit` fields. |
| `filterAndApply` | `<T extends Post>(state: ModerationState, posts: T[]) => T[]` | Drop then overlay, in that order. |

If `fetchModerationState` throws, **fail closed** — serve stale cache or an
error, never an unmoderated feed.

## lib/ranking.ts

Port of the v1 ranking in `8) Records/Algorithms.swift`.

| Export | Signature | Does |
|---|---|---|
| `rankFeed` | `(posts: Post[], likeCounts: Map<string, number>, seenIDs: Set<string>, seed: number) => Post[]` | Likes descending, seeded-random tie-break, seen posts sink below unseen. |
| `seededShuffle` | `<T>(items: T[], seed: number) => T[]` | Deterministic, so server and client agree. |

Seen state is per-device in the app (`UserDefaults` `seenContentIDs`), so ranking
that depends on it has to run **client-side** after hydration, or the server
would have to cache per-visitor. Server sorts by likes; the client re-sinks seen.

## lib/likes.ts

| Export | Signature | Does |
|---|---|---|
| `fetchLikeCounts` | `(postIDs?: string[]) => Promise<Map<string, number>>` | `queryAll` over `PostLike`, tallied by `postID`. Whole-table scan, which is why it's cached with the feed rather than per-request. |

## lib/seen.ts

Client-only. The browser equivalent of the app's per-device seen set.

| Export | Signature |
|---|---|
| `loadSeen` | `() => Set<string>` — `localStorage["seenContentIDs"]` |
| `markSeen` | `(postID: string) => void` |

## lib/feed.ts

The only module the pages import. Everything above is an implementation detail.

| Export | Signature | Cache |
|---|---|---|
| `getHomeFeed` | `() => Promise<Post[]>` | 60s |
| `getDiscoverFeed` | `() => Promise<Post[]>` | 60s |
| `getPost` | `(type: PostType, id: string) => Promise<Post \| null>` | 5m |
| `getProfile` | `(userRecordName: string) => Promise<{ profile: UserProfile; posts: Post[] } \| null>` | 5m |
| `getStudios` | `() => Promise<Organization[]>` | 5m |
| `getStudio` | `(id: string) => Promise<{ org: Organization; posts: Post[] } \| null>` | 5m |

Each fans out over the relevant record types, decodes, then runs
`filterAndApply` before returning. `getPost` returns `null` for a removed post so
the route can 404 it.

Home = film + music + reel + photography (+ design once the type exists).
Discover = project + event. Matches `A) HomeView.swift` / `B) DiscoverView.swift`.

Profiles honour `portfolioOrder` from `UserProfile`, per `E) PortfolioView.swift`.

## app/api/asset/[recordName]/[field]/route.ts

| Export | Signature | Does |
|---|---|---|
| `GET` | `(req: Request, ctx: { params: { recordName: string; field: string } }) => Promise<Response>` | Looks up the record, resolves a **fresh** `downloadURL`, returns `302`. |

Four rules, the first from the access policy and the rest from
`NEXUS_WEB_PLAN.md` "Correctness requirements":

- **Require a session.** Covered by `middleware.ts`, but assert it here too —
  this route is the one that hands out content, and a middleware matcher typo
  would otherwise expose every asset silently.
- `Cache-Control: no-store` **on the redirect**. Signed CDN URLs are short-lived;
  baking one into cached HTML serves a dead link later.
- Check moderation before redirecting, or the asset route becomes the hole that
  serves removed content.
- The `${f}` filename sets `Content-Type`. Production music assets are all MP3
  regardless of what `musicAudioExt` says — getting this wrong is the documented
  `-11828` failure.

## app/ pages

| Route | File | Source of truth |
|---|---|---|
| `/` | `app/page.tsx` | `3) Main Page Views/A) HomeView.swift` |
| `/discover` | `app/discover/page.tsx` | `B) DiscoverView.swift` |
| `/film/[id]` | `app/film/[id]/page.tsx` | `4) HomePage/B1) FilmCard.swift` |
| `/music/[id]` | `app/music/[id]/page.tsx` | `C1) MusicCard.swift` |
| `/reel/[id]` | `app/reel/[id]/page.tsx` | `D1) ReelCard.swift` |
| `/photo/[id]` | `app/photo/[id]/page.tsx` | `G) PhotographySubmissionView.swift` |
| `/design/[id]` | `app/design/[id]/page.tsx` | `H) DesignSubmissionView.swift` |
| `/project/[id]` | `app/project/[id]/page.tsx` | `5) DiscoverPage/A1) ProjectCard.swift` |
| `/event/[id]` | `app/event/[id]/page.tsx` | `B1) EventCard.swift` |
| `/u/[userRecordName]` | `app/u/[userRecordName]/page.tsx` | `E) PortfolioView.swift` |
| `/studios`, `/studios/[id]` | `app/studios/…` | `Collective Studios.swift`, `E3) StudioPageView.swift` |

Every detail page returns `notFound()` when `getPost` gives `null`.

**No `generateMetadata` with post content, no `opengraph-image`, no
`sitemap.ts`.** On a signed-in-only site those would publish titles, names and
thumbnails to anyone who resolves the URL — including link-preview bots in
Slack, iMessage and Discord, which don't carry a session. A shared link should
preview as the site name and nothing else. `robots.ts` emits a blanket
`Disallow: /`.

## lib/theme.ts + app/globals.css

Port the brand primitives only, not the layout. `1) App/NexusColors.swift` and
`2) Onboarding/FontExtensions.swift` become CSS custom properties and a Tailwind
theme extension. Do **not** reproduce `ScreenSizeFormat`-driven toolbar tuning;
the web equivalent is ordinary breakpoints.

## test/

| File | Covers |
|---|---|
| `sign.test.ts` | DER conversion + a known-payload signature. Port from `verification-service/test/units.test.ts`. |
| `decode.test.ts` | Every primitive against missing / wrong-typed / empty fields; one decoder per type against a fixture with fields absent. |
| `credits.test.ts` | `parseCredits` with colons in the role and in the name, mismatched ID array lengths, empty entries. |
| `moderation.test.ts` | Removed post dropped from feed **and** from `getPost`; edits overlay; fail-closed on fetch error. |
| `ranking.test.ts` | Like ordering, tie-break determinism for a fixed seed, seen posts sinking. |
| `auth.test.ts` | Session signing round-trip; a tampered or expired cookie yields `null`; middleware redirects an unauthenticated request to every gated path **including `/api/asset/*`**. |

The Worker's new endpoints get their own tests in
`verification-service/test/`, next to the existing `classifyRecord` suite:
domain not in the registry is refused, a code is single-use, the attempt cap
holds, and an app `pendingID` cannot be confirmed through the web path.

## SCHEMA.md

The one hand-maintained artifact tying Swift to TypeScript: record type → field →
CloudKit type → which environments have it. Seed it from the table in
`CloudKitRecordTypes.swift` and the `FEED_KEYS` lists above. Add a pointer
comment in `MediaModels.swift` so a new field updates both sides.

## Build order

Each step is verifiable before the next, so a wrong assumption surfaces early.

| # | Step | Done when |
|---|---|---|
| 1 | Register the S2S public key, fill `CLOUDKIT_KEY_ID` | `spike-cloudkit.mjs` returns records + a `downloadURL` |
| 2 | Scaffold Next.js + Tailwind + `lib/env.ts` | `npm run build` passes on an empty page |
| 3 | `sign.ts`, `client.ts` + `sign.test.ts` | a signed `queryAll` returns >1 page of `FilmSubmission` |
| 4 | `recordTypes.ts`, `feedKeys.ts`, `decode.ts`, `credits.ts` + tests | tests green |
| 5 | `records.ts` + `decode.test.ts` | every production record decodes without throwing |
| 6 | `moderation.ts`, `likes.ts`, `ranking.ts` + tests | a removed post is absent from both feed and detail |
| 7 | Worker: `pending_web_sessions` table + `/v1/web/session/{request,confirm}` + tests | a real `.edu` receives a code and confirming returns `{ email, schoolID }` |
| 8 | `session.ts`, `auth.ts`, `middleware.ts`, `/signin`, `/api/auth/*` | signed-out request to `/` redirects; signed-in reaches it |
| 9 | `feed.ts` + `/api/asset` | an image renders in a browser, and 302s for a signed-out request |
| 10 | `/` and one card component | home feed renders |
| 11 | Remaining six cards + detail pages | all routes render |
| 12 | `/u/[…]`, `/studios` | profiles honour `portfolioOrder` |
| 13 | `SCHEMA.md`, `robots.ts` | `Disallow: /` served |

Two risks worth naming:

- **Step 5** is the schedule risk: it's where environment schema gaps surface as
  real decode failures rather than as theory.
- **Steps 7–8 moved forward** from Phase 3. On a signed-in-only site, auth is
  not a feature added later — it's load-bearing before the first page is
  reachable, exactly as `../NEXUS_WEB_PLAN.md` warned option 3 would do. Build
  it before any route exists, so no route is ever written ungated.

## Phases 2–4

Not manifested here; shape depends on Phase 1.

- **Phase 2 (HLS).** Blocked on spike 3 — `ffprobe` three production `filmVideo` /
  `reelVideo` assets. If any is HEVC-in-MOV it won't play in Chrome or Firefox at
  all and this becomes a launch prerequisite. Needs `hlsPlaybackID` (String,
  queryable) added to all five media types **in both environments first**.
  `ffprobe` is not installed on this machine.
- **Phase 3 (auth/writes).** Entirely gated on spike 2: does CloudKit JS sign-in
  return the same `userRecordName` the app uses (`1) App/UserProfileManager.swift:57-65`)?
  Yes → web accounts are app accounts free. No → a week of account-linking.
- **Phase 4 (launch).** Domain, analytics, alert on CloudKit `THROTTLED`,
  load-test the feed with caching off.

## Deliberately not in Phase 1

Share/uploads, Network/DMs, and Moderate. Moderation stays app-only:
`isModeratorMode` is a local password-gated `AppStorage` flag
(`1) App/SecurityConfiguration.swift:185-190`), a model that provides no security
on the web.

## Access policy

**Decided 2026-09-23: the entire site is behind sign-in — reading and posting
both.** Nothing is public on the web.

Posting specifics, for when Phase 3 arrives:

- **Sign-in is not verification.** CloudKit public-database roles are only
  World / Authenticated / Creator, so "signed in" means *any Apple ID*, not a
  verified student. This is the same gap that makes the in-app gate cosmetic and
  forced the nightly sweep into existence (`verification-service/src/sweep.ts`).
  A web sign-in gate keeps out drive-by anonymous posting and nothing more.
- **Web posts must carry `schoolID` and a `Verification` record, or the sweep
  deletes them.** The sweep walks every submission type and flags posts whose
  creator has no verification on file; under `SWEEP_ACTION="delete"` it removes
  them. A web upload path that skips `SchoolScope.stamp`'s equivalent would ship
  content that quietly disappears overnight. Stamp the same registry slug the
  app writes.
- **The verification flow itself is app-only today.** It proves account
  ownership by having the client write a nonce to its own `UserProfile` record
  (`verification-service` README). Web posting therefore requires either porting
  that flow or requiring the user to verify once in the app first — decide
  before building web uploads.

### Reading: nothing is public on the web

**Decided 2026-09-23.** No page, post, profile or asset is reachable without a
session. This is option 3 in `../NEXUS_WEB_PLAN.md` — it preserves today's
privacy posture exactly: content stays as unreachable from a browser as it is
now, and nothing becomes crawlable or indexable.

What it costs, so nobody is surprised later:

- **No SEO, no shareable links, no link previews.** A link pasted into Slack or
  iMessage shows a login wall. Portfolio links students might want to send to
  employers don't work for the recipient.
- **Auth moves to the front of the build.** Steps 7–8, not Phase 3.
- **It narrows who the site reaches**, which is in tension with the original
  premise — `../NEXUS_WEB_PLAN.md` proposed the website *instead of* an Android
  port. See the auth decision below: pick wrong and Android students can't use
  it either, which would leave the site serving nobody the app doesn't already.

Partial mitigations available later if the tradeoff bites: per-post public
opt-in (an author marks one piece shareable), or expiring unguessable share
links for a single post. Both are additive and neither is in Phase 1.

### "Signed in" = verified school email

**Decided 2026-09-23.** Sign-in is a `.edu` code issued by the existing
`verification-service`, not an Apple ID. Non-Apple students can use the site,
and "signed in" means "verified student" rather than "has an Apple ID" —
closing on the web the gap CloudKit's World/Authenticated/Creator roles leave
open in the app.

Consequence: web identity is **not** app identity. Phase 3 writes will need
account linking, and spike 2 (does CloudKit JS return the same
`userRecordName`?) becomes a Phase 3 question rather than a Phase 1 blocker.

## The web sign-in flow

**The existing endpoints cannot be reused as they stand.** All three are built
around proving control of a CloudKit account, which a browser doesn't have:

| Endpoint | Why a browser can't use it |
|---|---|
| `POST /v1/verify/request` | Requires `userRecordName`; returns 400 without one (`src/index.ts:106-109`) |
| `POST /v1/verify/confirm` | Proves ownership by reading a nonce back off the user's own `UserProfile` record (`:233-238`). Only that record's creator can write it — which means the app, via CloudKit's Creator role |
| `GET /v1/verify/status` | Keyed on `userRecordName` (`:288-295`) |

So add two sibling endpoints to the same Worker, reusing the proven parts —
code generation, HMAC hashing, 10-minute TTL, 5-attempt cap, rate limiting,
domain matching, Resend sending — and dropping only the CloudKit step.

| New endpoint | Body | Returns |
|---|---|---|
| `POST /v1/web/session/request` | `{ email }` | `{ pendingID }` |
| `POST /v1/web/session/confirm` | `{ pendingID, code }` | `{ email, schoolID, domainKind }` |

**Dropping the nonce is correct here, not a weakening.** The nonce exists to
stop a client claiming *someone else's* CloudKit account. A web session claims
no account: it asserts only "this person controls this `.edu` address" and
grants read access to a site every verified student can already read. The rule
that keeps it honest — **a web session must never be treated as an app
identity.** It carries no `userRecordName` and must not be accepted as
authority to read or write any particular user's records.

Schema: `pending_verifications.user_record_name` is `TEXT NOT NULL`, so the web
flow gets its own `pending_web_sessions` table rather than a nullable column. A
separate table also guarantees a web pending row can never be confirmed through
the app path, or the reverse. Web sessions write **no** `verified_emails` row —
that table's `user_record_name` is `NOT NULL UNIQUE` and a web-only visitor has
no CloudKit account. The session cookie is the only artifact; when it expires
the visitor verifies again, like a magic link.

Flow, with the code never touching client-side JS:

```
browser ──POST {email}──► Next /api/auth/request
                            └─► Worker /v1/web/session/request ──► Resend
browser ──POST {code}───► Next /api/auth/callback
                            └─► Worker /v1/web/session/confirm
                            └─► createSession() sets an httpOnly cookie
```

Next calls the Worker **server-side**, so there's no CORS surface and the
Worker URL and shared secret stay off the client. Next issues the cookie, not
the Worker, keeping it first-party and `sameSite=lax`.

`VerifiedIdentity` is therefore
`{ email: string; schoolID: string; domainKind: string }` — no `userRecordName`
field, deliberately, so it can't be mistaken for one.

Three things to settle when building it:

- **Session length.** A semester is convenient but a long window on a shared
  laptop. 30 days with sliding renewal is the sane default.
- **`alumni.*` domains.** `school_domains.kind` already distinguishes
  `student` / `alumni` / `staff`. Decide whether alumni may read the site, and
  keep it consistent with the app's policy.
- **Does the web session scope the feed by school?** `SchoolScope` gives app
  users their own school's work. The web identity carries `schoolID`, so the
  same scoping is available — decide whether the website matches that or shows
  everything.
