# Nexus website: working notes

Running state of the web build, for anyone (or any new Claude chat) picking it up.
`BUILD_PLAN.md` is the original plan; this file records what actually exists.

## Run it
```
cd web
npm install
npm run dev        # http://localhost:3000
```
`node scripts/spike-cloudkit.mjs` re-checks the CloudKit connection.

## CloudKit (connected)
- Server-to-server key "Nexus Website – Production". Key ID + private key live in
  `web/.secrets/` (gitignored, never commit). On Vercel use `CLOUDKIT_KEY_ID` and
  `CLOUDKIT_PRIVATE_KEY` instead.
- `lib/cloudkit/client.ts` signs requests; `lib/cloudkit/content.ts` maps records to
  the site's shapes. Same rules as the app: approved only, ModerationAction removals
  hidden, festival-bound films kept off the feed. Cached ~5 min.
- Field names were read from the app code in this clone. Fields added to the app since
  this clone won't appear until they're added to `content.ts`.
- Thumbnails' real aspect ratios are read from the image bytes (`imageSize.ts`); content
  is never cropped. Videos are served as `media.mp4` (they're MP4 inside).

## Sign-in
- School-email 6-digit code via `verification-service` `/v1/web/session/*`
  (`src/webSession.ts`, tests in `test/webSession.test.ts`). A web session is NOT an
  app identity: it carries no userRecordName.
- Not deployed yet: run `npm run db:init`, `wrangler secret put WEB_CLIENT_TOKEN`,
  `npm run deploy` in `verification-service`, then fill `web/.env.local` from
  `.env.example`. Until then, dev prints codes in the `npm run dev` terminal.
- Guest browsing works only in development; production requires sign-in.

## UI decisions so far
- YouTube-style shell: left sidebar (Home, Discover, Share, Network, Portfolio, then a
  Library section: Staff Picks, Liked, Playlists; Sign in at the bottom; a dev-only
  Launch page link). Orange (school color) top bar with each page's wordmark at full
  size, search, and page filters/actions. Toggle bar never moves into the feed.
- Home: 3-column masonry, shuffled per visit (weighted toward newer posts), real
  profile pictures, timecodes bottom-right, main credit with a prefix ("Directed by",
  "by", "Performed by", "Shot by") taken from the credited role, not the submitter.
- Discover: projects and events only.
- Names and profile pictures link to that person's portfolio at `/portfolio/<person>`
  (feed cards, post byline and main credit, credits list, "More on Nexus"). `<person>`
  is their app profile ID; a credit typed by name links to their profile when the name
  is unique on Nexus, otherwise to a name-only portfolio of the work they're credited on.
  Your own page stays at `/portfolio`.
- EP/Album posts play every track (`musicTracks` + `musicTrackExts`) with a tracklist,
  auto-advance, and previous/next buttons. The app saves no per-track titles, so they
  show as "Track 1, 2...". Lengths after track 1 are read from the files.
- "Also On" pills show a logo when `public/logos/spotify.svg|png` or
  `apple-music.svg|png` exists (use the brands' official kits); otherwise text only.
- Player: CloudKit gives a new signed link for the same file on each refresh. The
  player only restarts on a real track change, and swaps fresh links in at the next
  pause or if the old link fails, so songs no longer jump back to the start.
- Post page: custom player (`components/Player.tsx`), controls on hover only: play,
  volume, time on the left; AirPlay/Cast and fullscreen on the right; school-color
  progress. Autoplays on open; pauses when you leave the page. Credits: role left,
  person right with photo; one row per person with all their roles.
- Share and Network mirror the app's layouts but aren't functional yet.

## Profile styles (added 2026-11-04)
- Every student picks a base style at sign-up (required step after the email code):
  Filmmaker, Actor or Musician. Change it at `/portfolio/style`. Logic in `lib/profileStyle.ts`
  (same rules and JSON as the app's `ProfileStyle.swift`).
- Stored in CloudKit `CreativeProfile_<userRecordName>` (style, details JSON, headshot, updatedAt),
  shared with the app. Until the email is linked to an app account the choice lives in the
  `nexus_profile_style` cookie. Read/write in `lib/cloudkit/creative.ts`.
- Profiles render by style (`components/StyledProfile.tsx`): actor = headshot, stats, reel, resume;
  filmmaker = IMDb filmography by job + stills; musician = upcoming shows, songs, albums & EPs.
- Now (`app/(app)/now/page.tsx`) runs on real projects/events, not `lib/sampleNow.ts`:
  actors get auditions (saved in the profile's details JSON) and roles that fit their age,
  gender, look and skills; filmmakers get their productions and crews matching their role tags;
  musicians get their shows, composer openings, and gigs/open mics/jams.
- Home's unfiltered feed leads with the viewer's style (3 matching posts per 1 other).
- Picking or changing a style files an application for that People page. Approving someone in
  Manage also writes a CloudKit `DirectoryListing`, so the app's public pages match; anyone
  approved from the app shows on the website's People page too.
- NEEDS SCHEMA: `CreativeProfile` and `DirectoryListing` must exist in the Production schema
  (recordName queryable). Until then style saves fail with a message and pages fall back quietly.

## Messages (added 2026-11-04)
- `/network` is two panes: conversations left, open thread right (`?c=<conversation ID>`).
  Phones show the list, then the thread with Back.
- Real data from the app's `Conversation` / `Message` records (`lib/cloudkit/messages.ts`),
  only for a session linked to an app account and only threads that account is in. Never cached.
- Sending writes a `Message` (with senderName/messagePreview so the recipient's phone gets the
  usual push) and bumps the thread's preview, time and unreadCount, like the app.
  Opening a thread marks its incoming messages read. The open page re-checks every 15 seconds.
- Not yet: starting a new conversation, sending attachments, and blocked users (the app keeps
  those on the device only). Without CloudKit keys it falls back to `lib/mockConversations.ts`.

## Sidebar, Discover, Featured (added 2026-11-04)
- Sidebar: Now on top, then each main page with its sub-pages under it — Home (Featured, Liked,
  Playlists), Discover (Projects, Events), Share, Network (Filmmakers, Actors, Musicians),
  Portfolio (Profile style, Edit profile). Defined in `CHILDREN` in `components/Sidebar.tsx`.
- Discover is the calendar only; `/discover/projects` and `/discover/events` are the card grids.
  The calendar shows every shoot day from the app's schedule text (`parseShootSchedule` in
  `lib/calendarEntries.ts`), at its call and wrap times.
- Staff Picks is now Featured at `/featured` (`/staff-picks` redirects). Admins add named
  collections under the picks in Manage. Stored in verification-service (`featured_collections`,
  `featured_collection_items`; routes `/v1/web/people/collections/*`).
- NEEDS DEPLOY: in `verification-service`, run `npm run db:init` (adds the two tables; existing
  data is untouched) and `npm run deploy`. Until then collections fail with a message and
  Featured shows only the picks.

## Status and People cards (added 2026-11-04)
- People cards are just: picture, name, major, class, then status. Everything else is on the portfolio.
- Status ("Looking for Work", "Booked until <date>", "Busy") is set in Edit profile and also shows under the name on
  portfolios. Stored as text, with Booked's date inside it ("Booked until 2026-12-12"); a Booked
  status stops showing once its date passes. List lives in `lib/workStatus.ts`.
- NEEDS SCHEMA: `workStatus` (STRING) on `UserProfile` in both CloudKit environments. Until it's
  in Production, saving a profile keeps everything else and says the status couldn't be saved.

## Open questions
- Keep "Continue as guest" at all?
- Staff Picks: how should the team choose them?
- Older posts lack saved durations; could read them from the files.
- App's "Is this you?" onboarding claims credits by name only, worth hardening.
