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
  (`src/webSession.ts`, tests in `test/webSession.test.ts`). When an account owns the
  email, the session carries its `userRecordName` (an app account, or `web_<id>`).
- Website accounts (2026-11-12): sign-up's last step (`createAccountAction` in
  `app/auth/actions.ts`) creates a real Nexus account through verification-service
  `/v1/web/account/create`: a CloudKit `UserProfile_web_<id>` the app shows like any
  other, plus the style's `CreativeProfile`. Signing in with an email that has no
  account goes to `/signup/finish`. Moving a website account into the app isn't built
  yet; see the verification-service README, "Website accounts".
- Not deployed yet: run `npm run db:init`, `wrangler secret put WEB_CLIENT_TOKEN`,
  `npm run deploy` in `verification-service`, then fill `web/.env.local` from
  `.env.example`. Until then, dev prints codes in the `npm run dev` terminal.
- Guests verify an email too (2026-11-16): "Continue as guest" goes to `/guest`, which emails
  a 6-digit code to ANY address (`purpose: "guest"` on `/v1/web/session/request`) and then
  sets a signed guest pass (`nexus_guest`, `lib/session.ts`). A pass lets someone browse, in
  production too; it is not a session and can't create or act as an account. Needs
  `verification-service` redeployed. The old unsigned `nexus_guest=1` cookie no longer works.

- Email only (2026-11-16): the Sign in with Apple button is gone. Student sign-up now has a
  "Select your school" step (`lib/signupSchools.ts`, same five schools as the app), and the
  email must be at that school's student domain (UT Austin: `@my.utexas.edu`). Checked in the
  form, in `requestCodeAction`, and again in `createAccountAction` for people who arrive
  through Sign in.

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
- Hover previews (2026-11-16): a card's video starts loading, unseen, about 0.1s after the
  pointer rests on it (`warm` in `components/HoverPreview.tsx`), so it can take over from the
  thumbnail as soon as the one-second hover is up. Leaving the card cancels the download.
- Share credits (2026-11-16): every cast, crew and credit name box suggests Nexus members
  as you type (`CreditLine` in `components/share/FormKit.tsx`, `GET /api/people`). Picking
  one saves their profile ID in the app's parallel `...IDs` list, so the credit links to
  their profile; a typed name saves "" as before. Film Cast and Project Cast Assembled
  now have a role box beside the name (blank saves as "Actor").
- Portfolio's top bar (2026-11-16): Edit Profile and Sign Out are buttons on the bar
  (`components/PortfolioBarActions.tsx`), shown on your own Portfolio, Liked, Saved and
  Edit profile pages when signed in. Phones keep them on the portfolio page itself.
- Network's top bar (2026-11-16): Messages, Directory, Actors, Filmmakers and Musicians are
  each a button of their own, not one joined toggle (`components/SubNav.tsx`).

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
- Picking or changing a style files an application for that People page.
- Who's on a People page (2026-11-17): the same two sources on the website and in the app —
  Manage's picks (verification-service `people_features`) plus the people the app's moderators
  put there (`directoryGroups` on `UserProfile`, read by `allDirectoryGroups()` in
  `lib/cloudkit/creative.ts`). The app reads Manage's picks from the service's public
  `GET /v1/people/listed` (`WebsitePeopleList.swift`). The earlier `DirectoryListing` mirror is
  gone: the app never read it. Now's "Listed / Waiting" line checks the same two sources.
- NEEDS SCHEMA: the style fields on `UserProfile` must exist in the Production schema. Until
  then style saves fail with a message and pages fall back quietly.

## Messages (added 2026-11-04)
- `/network` is two panes: conversations left, open thread right (`?c=<conversation ID>`).
  Phones show the list, then the thread with Back.
- Real data from the app's `Conversation` / `Message` records (`lib/cloudkit/messages.ts`),
  only for a session linked to an app account and only threads that account is in. Never cached.
- Sending writes a `Message` (with senderName/messagePreview so the recipient's phone gets the
  usual push) and bumps the thread's preview, time and unreadCount, like the app.
  Opening a thread marks its incoming messages read. The open page re-checks every 15 seconds.
- Group chats (2026-11-17): threads with `isGroup = 1` are listed by `participantUserIDs`
  (a `LIST_CONTAINS` query), titled by `groupName` or the other members' first names, and
  show who sent each received message. Sending into a group writes one `Message` with
  `recipientUserIDs` (everyone else), `readByUserIDs` (just the sender) and `groupName` (the
  push title); opening one adds the visitor to each unread message's `readByUserIDs`.
  The group queries fail quietly until the Production schema has those fields.
- Not yet: starting a new conversation or group, group settings (name, members, leaving),
  sending attachments, and blocked users (the app keeps those on the device only). Without
  CloudKit keys it falls back to `lib/mockConversations.ts`.

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

## Discover bar and Organizations (added 2026-11-16)
- Discover's bar: one Projects / Events toggle, then Calendar and Organizations as
  buttons of their own (`DISCOVER_GROUPS` in `components/SubNav.tsx`). On a narrow window
  the buttons show icons only. This replaces the "Discover is the calendar only" note above.
- Groups (2026-11-16): the bar's Organizations button is now **Groups**. Both
  `/discover/organizations` and `/discover/classes` light it, and both pages open with an
  Organizations / Classes toggle (`components/GroupsToggle.tsx`). Classes lists the Share
  forms' `FILM_CLASSES`, each with the projects whose studio names it (by name or RTF course
  number), plus any other RTF class a project names.
- `/discover` opens on Projects (same grid as `/discover/projects`). The calendar moved to
  `/discover/calendar`.
- `/discover/organizations` lists the app's 14 orgs in its order and colors;
  `/discover/organizations/<slug>` is each org's page. Names, descriptions, colors, sections,
  Collective's Weekly Shorts and the project catalogs are copied from the app
  (`OrganizationCard.swift`, `CollectiveStudios.swift`) into `lib/organizations.ts`; pictures
  are in `public/orgs/`. Catalog entries link to the real post when one has the same title.
  Events come from event posts whose host is the org's name.
- NEEDS SCHEMA: `Organization` (recordName queryable) and `OrgContentLink` aren't readable in
  Production yet. Until they are, descriptions/pictures edited in CloudKit and posts moderators
  add to org sections in the app don't show; those sections say "Nothing here yet."

## Status and People cards (added 2026-11-04)
- People cards are just: picture, name, major, class, then status. Everything else is on the portfolio.
- Status ("Looking for Work", "Booked until <date>", "Busy") is set in Edit profile and also shows under the name on
  portfolios. Stored as text, with Booked's date inside it ("Booked until 2026-12-12"); a Booked
  status stops showing once its date passes. List lives in `lib/workStatus.ts`.
- NEEDS SCHEMA: `workStatus` (STRING) on `UserProfile` in both CloudKit environments. Until it's
  in Production, saving a profile keeps everything else and says the status couldn't be saved.

## Open questions
- Staff Picks: how should the team choose them?
- Older posts lack saved durations; could read them from the files.
- App's "Is this you?" onboarding claims credits by name only, worth hardening.

## Search (updated 2026-11-16)
- The search box is the size it is on Home on every page. `components/TopBar.tsx` reserves
  the width of Home's category filter (an invisible copy) beside it, adjusted for the
  page's wordmark, and the page's own buttons sit in that space. Discover's and Share's
  buttons now drop to icons under 1280px (was 768px), the same point Home's filter does,
  so they fit. Network's and Portfolio's text tabs have no icons, so under 1280px the
  search box is narrower there.
- `/api/search` covers every type: all five kinds of post, projects, events, organizations
  and every profile. It matches names first, then details: the type itself ("films",
  "actors", "organizations"), genres, studio, school, credits, cast/crew needed, role tags,
  profile type, and Actor/Filmmaker/Musician Info (skills, languages, specialties,
  instruments, genres, artist name). Type-only matches take turns by kind. People are
  labelled Filmmaker / Actor / Musician (chosen style, else from role tags), else Artist.
- Enter narrows the list on Home, school feeds and Discover's Projects/Events/Calendar
  (same matching, `postMatches` / `discoverMatches` in `lib/search.ts`); on every other
  page it opens the top match. There is no full results page yet.

## Actor/Filmmaker/Musician info lives on UserProfile (2026-11-16)
- The website no longer uses a separate `CreativeProfile` record type. Style, details JSON
  and headshot are three fields on the person's own `UserProfile` record
  (`style` String, `details` String, `headshot` Asset; no `updatedAt`), read and
  written in `lib/cloudkit/creative.ts`. This replaces the `CreativeProfile` notes above.
- NEEDS SCHEMA: those three fields must be deployed to Production. A save that CloudKit
  rejects now shows a message instead of passing silently (`modify` in `lib/cloudkit/client.ts`
  used to ignore every NOT_FOUND, including "record type not found").
- NOT DONE: the app's `CreativeProfileStore.swift` still reads and writes `CreativeProfile`,
  so the app and website don't share this info until the app is switched to the same fields.

## Load speed (added 2026-11-16)
- Home sends 24 cards with the page and fetches the next 24 from `/api/feed` shortly before
  you reach the end (`components/FeedGrid.tsx`, `lib/feedPage.ts`). The shuffle comes from a
  per-visit seed (`lib/mixFeed.ts`), so later pages continue the same order. Feed cards carry
  only what a card shows, not descriptions, lyrics, credits or galleries.
- Home shows a placeholder feed at once and streams the real one in; `app/(app)/loading.tsx`
  does the same for every other page that waits on data.
- The first paint carries the 2- and 3-column layouts (the 2-column one doubles as the phone
  layout); once the window's width is known FeedGrid keeps only the one in use. Other grids
  (portfolios, school pages) still carry both.
- Feed thumbnails and profile pictures come from `/img/t/<post>` and `/img/p/<profile>`
  (`app/img/[kind]/[id]/route.ts`, `lib/smallImage.ts`): small WebP copies at 480/960 px and
  96 px, named by the file's checksum so the address never changes and browsers keep their copy.
  Post pages still show the full-size originals. If resizing fails the route redirects to the original.
- The site-wide CloudKit lists (`getAllPosts`, `getDiscoverItems`, `profileDirectory`,
  `allCreativeProfiles`, `allListings`, the organization lists) use `"use cache: remote"`, one
  copy shared by every Vercel instance. Plain `"use cache"` lives in one instance's memory, so
  most visits were redoing the whole CloudKit fetch. Per-person lookups still use `"use cache"`.
- Thumbnail shapes are read from the first 64 KB (512 KB only if needed) and remembered by the
  file's checksum, so a refresh only measures new pictures. The profile list asks CloudKit for
  four fields instead of whole profiles.
- Second round (same day): portfolios and school pages use `PostGrid` / `PagedGrid` (first 24
  cards, more on scroll, one layout). Small copies now also cover profile pictures everywhere
  (`profileDirectory` and `getAccount` hand out the small address; the upload is `fullImageUrl`),
  project posters and event flyers (`/img/d/`), search results, "More on Nexus", and post-page
  galleries (`/img/g/`, 1600 px, with a "Full size" link to the upload).
- `thumbWidth` / `thumbHeight` (Int64, all five post types): saved by the website at upload
  (`lib/shareUpload.ts`) and by the app (`setThumbnailSize` in `MediaModels.swift`); posts that
  have them are never measured. `node scripts/backfill-media-info.mjs` lists what older posts
  are missing (sizes and video/song lengths); add `--write` to save it to Production.
- The Network page asks `/api/network/pulse` every 15 s and only rebuilds when it changes.
- Not done: video is still the original file from CloudKit (no adaptive streaming).

## Mock launch (added 2026-11-16)
- Sidebar button "Mock launch" (`components/MockLaunchLink.tsx`), above the account button.
  Shown in development, and on the live site only to admins (`ADMIN_EMAILS`).
- Opens `/welcome/mock` (the launch page), then `/signup/mock`: every sign-up screen via
  `<SignUpForm mock />`. No email is sent, any 6-digit code passes, and no account, session,
  style or guest pass is saved. The email box still checks the school's student domain.

## Educators and sign-up emails (added 2026-11-16)
- Sign-up's second choice is "I'm an Educator" (was Industry Professional). Educators pick a
  school, verify with that school's email, pick a profile style, then give a Department (no
  class year). Their account is made with `schoolRole: "Professor"`.
- Domains per school and role are in `lib/signupSchools.ts` (`educatorDomains`). UT Austin
  educators: `@austin.utexas.edu` or `@utexas.edu`; the other schools use one domain for everyone,
  so there the site can't tell an educator from a student.
- The email box takes only the part before "@"; the domain is filled in (a menu when there are two).
- The name box's example is a well-known name from the school picked (`exampleNames`); schools
  without any show no example.
- `/signup/finish` (arrived through Sign in) now asks student or educator first.
- NEEDS DEPLOY: `verification-service` `/v1/web/account/create` accepts `role: "educator"`. Until
  it's redeployed, creating an educator account fails with "Pick your graduation year."

## Sign-up steps (changed 2026-11-16, later the same day)
- Steps are now: student or educator, school, email, code, then one profile step with name,
  major (Department for educators), class year (students) and tags. The name is no longer asked
  beside the email.
- Sign-up no longer asks for a profile type (Filmmaker / Actor / Musician), so new accounts get
  no `CreativeProfile` and file no People-page application. `/portfolio/style` still exists.
  This replaces "Every student picks a base style at sign-up" under Profile styles above.
- Tags are the app's role tags (`ROLE_TAGS`), optional, saved to `userTypes` the way Edit
  profile saves them. NEEDS DEPLOY: `verification-service` account create now takes `userTypes`;
  until it's redeployed, tags picked at sign-up aren't saved.

## Launch and sign-in look (changed 2026-11-16)
- The welcome, sign-in and sign-up screens are black, white and gray only: white buttons,
  white selection outlines, gray text. No burnt orange in buttons, links or highlights.
- The only color is three glows (`components/SchoolGlows.tsx`): UT Austin orange top center,
  UC Berkeley blue bottom left, USC cardinal bottom right. The signed-in site is unchanged
  and still uses the school color.

## School first, then school colors (changed 2026-11-16)
- Sign-in and sign-up both start with "Select your school" (`components/SchoolPicker.tsx`): a
  black and white screen where each school's button is in its own colors. Picking one moves on.
- From then on the screen is in that school's colors: buttons, outlines, links, the progress bar
  and the glows. `components/AuthTheme.tsx` sets `--auth`, `--auth-fg` and `--auth-line`; colors
  per school are in `lib/signupSchools.ts` (`color`, `onColor`, `highlight`, `glow`). Back to the
  school list returns to black and white.
- Sign-up order: school, student or educator, email, code, profile.
- Sign-in asks for the email the same way as sign-up (type the part before "@"), offering every
  domain of the school (`components/SchoolEmailBox.tsx`). UT Austin: my.utexas.edu,
  austin.utexas.edu, utexas.edu.
- The welcome page's footer links to collegeartistsconnect.org beside "Nexus by Longhorn Artists Connect".
- Mock launch also has a practice sign-in at `/signin/mock` (`<SignInForm mock />`); the mock welcome
  and mock sign-up pages link to it.

## Share's Drafts page (added 2026-11-16)
- The Drafts button on Share's bar (`components/share/DraftsButton.tsx`) opens `/share/drafts`
  and stays lit while it's open. The page mirrors the app's `DraftsView` ("No drafts yet").
- Not yet: the Share forms can't save a draft, so the list is always empty. The app keeps
  drafts on the device only, so website drafts would live in the browser, not CloudKit.

## Portfolio grid editing, school secondary colors, launch buttons (2026-11-16, late)
- Edit grid: on your own portfolio the Work grid has an "Edit grid" button (`components/PortfolioGrid.tsx`).
  Drag posts (or use the arrows, for phones and keyboards) to reorder; − / + steps a post through
  Small, Medium, Large. Save calls `savePortfolioLayout` (`app/(app)/portfolio/actions.ts`): the order
  goes to `UserProfile.portfolioOrder` (shared with the app), sizes to `UserProfile.portfolioLayout`.
- Every portfolio now shows its owner's saved order (`sortByOrder` in `ProfileView`). With all posts
  Small the grid is the usual masonry; once any post is bigger it becomes a six-column row grid
  (wide window: small 1/3, medium 1/2, large 2/3; phones: one per row).
- NEEDS SCHEMA: `portfolioLayout` (String) on `UserProfile` in Production. Until then the order saves
  and the page says sizes couldn't be saved.
- School secondary colors: on `/school/usc` and `/school/berkeley` the top bar's wordmark, text and
  buttons use the school's gold (`accent` in `lib/schools.ts`: USC `#FFCC00`, Berkeley `#FDB515`), the
  selected school in the sidebar is its main color with gold text, and the feed's preview bars are gold.
- The sidebar's "Mock launch" and "Launch page" buttons are gone. The pages remain at `/welcome`,
  `/welcome/mock`, `/signup/mock` and `/signin/mock`; `components/MockLaunchLink.tsx` is no longer used.
  This replaces the "Sidebar button" line under Mock launch above.

## Discover: Classes pages (added 2026-11-16, late)
- `/discover/classes` lists the app's four production classes (`lib/productionClasses.ts`, copied from
  `ProductionClassCatalog` in `SharedSubmissionTypes.swift`), under the Groups toggle (`GroupsToggle`).
  `/discover/classes/<slug>` shows the films posted under that class and its Discover projects.
  A post belongs to a class when its studio ("Class or Org") value matches the class's code, name,
  full name or an earlier wording.
- Classes have no description or picture: the app has none to copy.
- Not done: Discover's bar isn't shown on `/discover/classes/<slug>` (the Groups tab in `SubNav.tsx`
  lights for `/discover/classes` only, not the pages beneath it).

## School logos, your-school badge, mascot line (2026-11-17)
- `lib/schools.ts` now lists all five schools (`SCHOOLS`: UT Austin, UC Berkeley, USC, UMich, Texas A&M)
  with mascot, colors and a logo in `public/schools/`. UMich and Texas A&M are new under Other Schools
  and have feeds at `/school/umich` and `/school/tamu`.
- The logos are the schools' real marks, used without a license (Aiden's decision). If a school objects,
  replace its file in `public/schools/`.
- Top of the sidebar: `components/SchoolBadge.tsx` shows your school's logo and name (the session's
  `schoolID`; UT Austin when signed out or a guest). It opens that school's feed.
- Other Schools and College Artists Connect show their logos in circles. "Launch page" is back, under
  More, in development only as before.
- An empty school feed says "Come on <mascot>, show us what you've got!". Home has no such line: its
  empty state is the shared "Nothing here yet."

## Skip sign-in for testing (2026-11-17)
- Under `npm run dev` only, `/signin` shows a yellow "Skip sign-in" box (`components/DevSkipSignIn.tsx`,
  `app/auth/devActions.ts`). Type a profile's name to be that Nexus account (remembered in the browser),
  or leave it blank to be signed in with no account. The session uses the first `ADMIN_EMAILS` address
  and UT Austin. The action refuses unless NODE_ENV is "development", so it does nothing on Vercel.
- Create account has its own testing shortcut: on the email step, "Skip email and code (testing only)"
  (`skipped` in `app/signup/SignUpForm.tsx`, dev only) jumps to the profile step. The last step then ends
  like the mock walkthrough: no account is created and nobody is signed in.

## Performance posts with several videos (2026-11-17)
- The Performance form takes one video or several, in playing order, each with a title once there is
  more than one (`VideoList` in `components/share/forms/PerformanceForm.tsx`). Meant for showcases
  (the "Actor Showcase" category): one post that plays as a playlist.
- Saved on `ReelSubmission`: the first video stays in `reelVideo` (what the app plays); the rest go to
  `reelVideos` (asset list) and every video's title to `reelVideoTitles` (string list, same order).
- The post page plays them with `components/VideoPlaylist.tsx`: numbered list, auto-advance, previous/next.
- NEEDS SCHEMA: `reelVideos` (Asset List) and `reelVideoTitles` (String List) on `ReelSubmission` in
  Production. Until they exist, posting more than one video fails; a single video posts as before.
- The app shows only the first video until it reads `reelVideos`.

## Playlists of existing posts (2026-11-17)
- Admins (`ADMIN_EMAILS`) see "Existing posts (admins)" in the Performance form: search any post with a
  video, add and order them (`ExistingPosts` in `PerformanceForm.tsx`, `app/(app)/share/playlistActions.ts`).
  The post saves their IDs in `reelPlaylistPostIDs` on its `ReelSubmission`. `publishPost` refuses the
  list from anyone who isn't an admin and keeps only real posts that have a video.
- A playlist plays its own uploaded videos first, then the listed posts under their own titles, each with
  an "Open post" link (`resolvePlaylists` in `lib/cloudkit/content.ts`, `VideoPlaylist.tsx`).
- Posts inside a playlist are left out of `feedPosts()` (Home, school feeds, search, "More on Nexus",
  organization and class pages). They still show on portfolios and open at their own address.
- A playlist with no upload of its own has no `reelVideo`; it needs a thumbnail, and the app will show it
  as a Performance post with nothing to play until the app reads `reelPlaylistPostIDs`.
- NEEDS SCHEMA: `reelPlaylistPostIDs` (String List) on `ReelSubmission`, besides `reelVideos` and
  `reelVideoTitles`. These three are never dropped to rescue a save: without them the post is refused
  with a message naming the fields. (Correction to the note above: before this, a multi-video post would
  have gone up with only its first video.)
- Not built: editing or deleting a playlist from the website.


## Big uploads go to Cloudflare R2 (2026-11-17)

- CloudKit Web Services refuses files over 50 MB, so Share sends any file of 45 MB or more in
  filmVideo, filmTrailer, musicAudio, musicTracks, musicVideo, reelVideo, reelVideos or
  designVideo to Cloudflare R2 instead, up to 10 GB (`lib/r2.ts`, signed requests, no packages).
  Other fields (pictures, scripts) still have to be under 45 MB.
- The browser uploads 16 MB parts straight to R2 (four at a time, each retried) using URLs
  `startPost` signs; `publishPost` finishes the upload and saves the public link on the record
  as `<field>URL` (String) or `<field>URLs` (String List). Keys: see Limits below.
- Browsers can't upload to CloudKit (its upload host sends no CORS headers), so every file goes to
  R2 first; `publishPost` moves files under 45 MB on to CloudKit from the server (`staging/` keys) and
  deletes the staged copies.
- Reading: `fileURL` / `fileURLs` in `lib/cloudkit/client.ts` prefer the R2 link. The app reads the
  link fields with the feed (`FeedKeys`, parsed into `Submission.mediaLinkURL` / `trailerLinkURL` /
  `musicTrackLinkURLs`) and plays straight from them via `CloudKitManager.streamResolutionDetailed(for:)`,
  with no CloudKit lookup and no need for the web-services token; its web-services lookups
  (`CloudKitWebServices.assetFieldLookup` / `streamURLs`) prefer the links too, as a fallback.
- CloudKit fields (Development, then deploy to Production): FilmSubmission filmVideoURL,
  filmTrailerURL; MusicSubmission musicAudioURL, musicVideoURL, musicTracksURLs (list);
  ReelSubmission reelVideoURL, reelVideosURLs (list); DesignSubmission designVideoURL.
- Limits (abuse protection): at most 5 big files and 20 GB per post (`MAX_LARGE_*` in
  `lib/sharePost.ts`); each account can start at most 30 GB of big uploads in any 24 hours,
  finished or not, counted by listing its keys in R2 (keys are `posts/<account>/<record>/<field>-<n>-<bytes>.<ext>`).
  Every part URL is signed with its exact Content-Length, and the finished file must match the
  size declared in its key, or it's deleted.
- Early uploads (2026-11-17): videos and audio start uploading the moment they're picked
  (`syncEarlyUploads` in `lib/shareUpload.ts`, driven by `EarlyUploads` in `DraftContext.tsx`), via
  `startEarlyUpload` (keys `.../<record>/early-…` or `.../<record>/staging/early-…`). Post reuses them
  when the same files are still there (`startPost(..., continueAs)` keeps the record name); removed or
  replaced files are aborted (`abortEarlyUpload`). Progress bars show "about N min left".
- Bucket CORS rules for wrangler: `scripts/r2-cors.json`. Bucket CORS must allow PUT from the site's origins and expose `ETag`, or every upload fails
  with "Upload failed (no ETag)."
- Not yet: deleting a post doesn't delete its R2 file. The app has no music-video player, so a
  music video (R2 or not) only shows on the website.

## Editing posts (2026-11-17)

- Edit shows on a post's page for the account that made it (`components/EditPostLink.tsx`, checked by
  `canEditPost`). It opens `/share/<type>?edit=<postID>`: the Share form, filled in from the record
  (`lib/editPost.ts`), with Save instead of Post.
- Files not replaced stay; emptied text and lists are saved empty. The post keeps isApproved,
  submittedBy and its created date; lastEditedDate (designLastEditedDate) is set. A replaced R2 file is
  deleted after the save. Playlists' linked posts aren't changed from the website.
- A new post can take a few seconds to show in CloudKit's queries: `publishPost` waits for it before
  refreshing the feeds, and `findPost` falls back to looking a post up by ID (`postByID`).

## Portfolio tile sizes field renamed (2026-11-19)
- Tile sizes are now saved in `UserProfile.portfolioLayoutWebsite` (String), added to the schema by Aiden,
  replacing `portfolioLayout` in the notes above. `portfolioLayoutMobile` (String) also exists for the
  app's own grid sizes; nothing reads or writes it yet. The website's phone layout (one post per row)
  doesn't use it.

## Cal Poly SLO, Ohio State, UVA, UC Santa Barbara (2026-11-19)
- Added to `SCHOOLS` (lib/schools.ts) and `SIGNUP_SCHOOLS` (lib/signupSchools.ts), with feeds at
  `/school/calpoly-slo`, `/school/ohio-state`, `/school/uva`, `/school/ucsb`. Email domains: calpoly.edu,
  osu.edu, virginia.edu, ucsb.edu.
- Their logos in `public/schools/` are placeholder lettermarks in school colors (CP, OSU, UVA, UCSB) until
  the real marks are dropped in under the same names.
- The app (OnboardingSchool.all, SchoolScope, SchoolColors) and `verification-service/seed/schools.sql`
  have them too; the seed must be applied to D1 before their addresses verify.
