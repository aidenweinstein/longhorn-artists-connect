import { cacheLife, cacheTag } from "next/cache";
import { parseTileSizes, type TileSizes } from "../portfolioLayout";
import type { NexusEvent, Project } from "../discoverContent";
import type { Post } from "../mockContent";
import type { ProfileFields } from "../profileFields";
import { cleanWorkStatus } from "../workStatus";
import type { Credit, CreditGroup } from "../postDetails";
import { imageAspect } from "./imageSize";
import { schoolSlugForName } from "../schools";
import { posterSource, profileImage } from "../smallImage";
import { asset, assetChecksum, assetChecksums, assets, fileURL, fileURLs, isCloudKitConfigured, list, lookup, num, queryAll, str, type CKRecord } from "./client";

/**
 * Real content from the app's public CloudKit database, mapped into the website's
 * shapes. Mirrors the app's own rules: only approved posts, never moderator-removed
 * ones, and festival-bound films stay out of the feed.
 *
 * Cached for a few minutes; asset download URLs are refreshed with each fetch.
 * The site-wide lists use `use cache: remote`: on Vercel every server instance shares
 * one copy, so a visitor almost never waits on CloudKit. Plain `use cache` lives in
 * one instance's memory, and serverless instances come and go, so most visits would
 * have redone the whole fetch.
 */

const DEFAULT_ASPECT: Record<Post["category"], number> = {
  film: 16 / 9,
  music: 1,
  performance: 16 / 9,
  photography: 4 / 5,
  design: 4 / 5,
};

const dateFmt = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: "America/Chicago" });
const eventFmt = new Intl.DateTimeFormat("en-US", {
  weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit", timeZone: "America/Chicago",
});

function created(r: CKRecord): number {
  return num(r, "createdDate") ?? r.created?.timestamp ?? 0;
}

/** "Role: Name" entries plus the parallel profile-ID list, as the app stores credits. */
function credits(r: CKRecord, key: string, idsKey: string): Credit[] {
  const ids = list(r, idsKey);
  return list(r, key).flatMap((entry, n) => {
    const i = entry.indexOf(":");
    const role = i < 0 ? "" : entry.slice(0, i).trim();
    const name = (i < 0 ? entry : entry.slice(i + 1)).trim();
    return name ? [{ role, name, profileID: ids[n] || undefined }] : [];
  });
}

function groups(...pairs: [string, Credit[]][]): CreditGroup[] {
  return pairs.filter(([, c]) => c.length > 0).map(([title, c]) => ({ title, credits: c }));
}

function base(r: CKRecord, category: Post["category"], title: string, creator: string): Post {
  const when = created(r);
  return {
    id: r.recordName,
    title: title || "Untitled",
    creator: creator || str(r, "submittedBy") || "Unknown",
    school: "",
    category,
    meta: when ? dateFmt.format(new Date(when)) : "",
    aspect: DEFAULT_ASPECT[category],
    creatorProfileID: maker(r),
    makerProfileID: maker(r),
    editorIDs: editors(r),
  };
}

/** The account that posted it, as a profile ID. Unlike creatorProfileID, never moved to the main credit. */
function maker(r: CKRecord): string | undefined {
  return str(r, "userID") ? `UserProfile_${str(r, "userID")}` : undefined;
}

/** Who else the maker shared edit access with (profile IDs), when anyone. */
function editors(r: CKRecord): string[] | undefined {
  const ids = list(r, "editorIDs");
  return ids.length ? ids : undefined;
}

function film(r: CKRecord): Post {
  const p = base(r, "film", str(r, "filmTitle"), str(r, "submittedBy"));
  const studio = str(r, "filmStudio");
  return {
    ...p,
    thumbnailUrl: asset(r, "filmThumbnail", "media.jpg"),
    duration: num(r, "filmVideoDuration"),
    videoUrl: fileURL(r, "filmVideo", "media.mp4"),
    videoCrop: str(r, "filmVideoCrop") || undefined,
    images: [...assets(r, "filmStills", "media.jpg"), ...assets(r, "filmBTS", "media.jpg")],
    imageKeys: [...assetChecksums(r, "filmStills"), ...assetChecksums(r, "filmBTS")],
    details: {
      ageRating: str(r, "filmAgeRating") || undefined,
      genres: list(r, "filmGenres"),
      explicit: num(r, "filmExplicit") === 1,
      studio: studio && studio !== "Independent" ? studio : undefined,
      releaseYear: str(r, "filmReleaseYear") || undefined,
      logline: str(r, "filmLogline") || undefined,
      description: str(r, "filmDescription"),
      creditGroups: groups(["Cast", credits(r, "filmCast", "filmCastIDs")], ["Crew", credits(r, "filmCrew", "filmCrewIDs")]),
      trailerUrl: fileURL(r, "filmTrailer", "media.mp4"),
      submittedBy: str(r, "submittedBy"),
    },
  };
}

function music(r: CKRecord): Post {
  const artist = str(r, "musicArtist");
  const p = base(r, "music", str(r, "musicTitle"), artist);
  const ext = (str(r, "musicAudioExt") || "m4a").replace(/^\./, "");
  const links = [
    ["Spotify", str(r, "musicSpotifyLink")],
    ["Apple Music", str(r, "musicAppleMusicLink")],
    ["Amazon Music", str(r, "amazonMusicLink")],
    ["YouTube Music", str(r, "youtubeMusicLink")],
    ["SoundCloud", str(r, "soundcloudLink")],
  ].filter(([, url]) => url) as [string, string][];
  const audioUrl = fileURL(r, "musicAudio", `media.${ext}`);
  // EP/Album tracks after the first, saved by the app as a parallel asset + extension list.
  const exts = list(r, "musicTrackExts");
  // Big website uploads keep R2 links instead (musicTracksURLs), already named with their extension.
  const trackLinks = list(r, "musicTracksURLs");
  const extra = trackLinks.length
    ? fileURLs(r, "musicTracks", "media.m4a")
    : ((r.fields["musicTracks"]?.value as { downloadURL?: string }[] | undefined) ?? []).flatMap((a, i) =>
        a?.downloadURL ? [a.downloadURL.replace("${f}", `media.${(exts[i] || "m4a").replace(/^\./, "")}`)] : [],
      );
  const tracks = audioUrl && extra.length ? [audioUrl, ...extra] : undefined;
  return {
    ...p,
    thumbnailUrl: asset(r, "musicCover", "media.jpg"),
    duration: num(r, "musicAudioDuration"),
    audioUrl,
    tracks,
    videoUrl: fileURL(r, "musicVideo", "media.mp4"),
    details: {
      byline: artist || undefined,
      genres: list(r, "musicGenres"),
      explicit: num(r, "musicExplicit") === 1,
      kindLabel: str(r, "musicCategory") || undefined,
      releaseYear: str(r, "musicReleaseYear") || undefined,
      description: str(r, "musicDescription"),
      creditGroups: groups(["Recording", credits(r, "musicRecording", "musicRecordingIDs")], ["Production", credits(r, "musicProduction", "musicProductionIDs")]),
      links,
      lyrics: str(r, "lyrics") || undefined,
      submittedBy: str(r, "submittedBy"),
    },
  };
}

function reel(r: CKRecord): Post {
  const artist = str(r, "reelArtist");
  const p = base(r, "performance", str(r, "reelTitle"), artist);
  const featured = [...list(r, "featuredWorkManual")];
  const videoUrl = fileURL(r, "reelVideo", "media.mp4");
  // A showcase's videos after the first (website posts), with one title per video in reelVideoTitles.
  const extra = fileURLs(r, "reelVideos", "media.mp4");
  const titles = list(r, "reelVideoTitles");
  const playlistIDs = list(r, "reelPlaylistPostIDs");
  // Per uploaded video: its own thumbnail and who's in it, when saved for every video.
  const own = videoUrl ? [videoUrl, ...extra] : [];
  const thumbs = assets(r, "reelVideoThumbnails", "media.jpg");
  const castNames = list(r, "reelVideoCast");
  const castIDs = list(r, "reelVideoCastIDs");
  const aligned = (l: string[]) => l.length === own.length;
  // A playlist of existing posts lists its own upload too (resolvePlaylists adds the rest).
  const videos =
    videoUrl && (extra.length || playlistIDs.length)
      ? own.map((url, i) => ({
          url,
          title: titles[i] ?? "",
          thumb: aligned(thumbs) ? thumbs[i] : undefined,
          actor: aligned(castNames) && castNames[i] ? { name: castNames[i], profileID: castIDs[i] || undefined } : undefined,
        }))
      : undefined;
  return {
    ...p,
    thumbnailUrl: asset(r, "reelThumbnail", "media.jpg"),
    duration: num(r, "reelVideoDuration"),
    videoUrl,
    videoCrop: str(r, "reelVideoCrop") || undefined,
    videos,
    playlistPostIDs: playlistIDs.length ? playlistIDs : undefined,
    details: {
      byline: artist || undefined,
      genres: [],
      kindLabel: str(r, "reelType") || undefined,
      description: str(r, "reelDescription"),
      creditGroups: groups(["Cast", credits(r, "orderedCast", "orderedCastIDs")], ["Crew", credits(r, "orderedCrew", "orderedCrewIDs")]),
      featuredWork: featured.length ? featured : undefined,
      submittedBy: str(r, "submittedBy"),
    },
  };
}

function equipment(r: CKRecord) {
  // Current posts store "Label: value" entries in photographyGear (app and website).
  const gear = list(r, "photographyGear").flatMap((entry) => {
    const i = entry.indexOf(": ");
    return i > 0 ? [{ label: entry.slice(0, i), value: entry.slice(i + 2) }] : [];
  });
  if (gear.length) return gear;
  try {
    const e = JSON.parse(str(r, "photographyEquipment") || "{}") as Record<string, string>;
    const rows = [["Camera", e.camera], ["Lens", e.lens], ["Lighting", e.lighting], ["Filters", e.filters]]
      .filter(([, v]) => v && v.trim()) as [string, string][];
    return rows.length ? rows.map(([label, value]) => ({ label, value })) : undefined;
  } catch {
    return undefined;
  }
}

function photography(r: CKRecord): Post {
  const artist = str(r, "photographyArtist");
  const p = base(r, "photography", str(r, "photographyTitle"), artist);
  const images = assets(r, "photographyImages", "media.jpg");
  return {
    ...p,
    thumbnailUrl: asset(r, "photographyThumbnail", "media.jpg") ?? images[0],
    images,
    imageKeys: assetChecksums(r, "photographyImages"),
    details: {
      byline: artist || undefined,
      genres: [],
      releaseYear: str(r, "photographyReleaseYear") || undefined,
      description: str(r, "photographyDescription"),
      equipment: equipment(r),
      creditGroups: groups(["Credits", credits(r, "orderedCrew", "orderedCrewIDs")]),
      submittedBy: str(r, "submittedBy"),
    },
  };
}

function design(r: CKRecord): Post {
  const p = base(r, "design", str(r, "designTitle"), str(r, "submittedBy"));
  const images = assets(r, "designImages", "media.jpg");
  return {
    ...p,
    thumbnailUrl: asset(r, "designThumbnail", "media.jpg") ?? images[0],
    duration: num(r, "designVideoDuration"),
    images,
    imageKeys: assetChecksums(r, "designImages"),
    videoUrl: fileURL(r, "designVideo", "media.mp4"),
    videoCrop: str(r, "designVideoCrop") || undefined,
    details: {
      genres: [],
      kindLabel: str(r, "designCategory") || undefined,
      releaseYear: str(r, "designReleaseYear") || undefined,
      description: str(r, "designDescription"),
      creditGroups: groups(["Credits", credits(r, "orderedCrew", "orderedCrewIDs")]),
      submittedBy: str(r, "submittedBy"),
    },
  };
}

function project(r: CKRecord): Project {
  const castNeeded = list(r, "projectCastNeeded");
  const crewNeeded = list(r, "projectCrewNeeded");
  const type = str(r, "projectType");
  return {
    kind: "project",
    id: r.recordName,
    title: str(r, "projectTitle") || "Untitled",
    projectType: (type as Project["projectType"]) || "Cast & Crew Call",
    logline: str(r, "projectDescription"),
    postedBy: str(r, "submittedBy"),
    shootDates: str(r, "projectShootDatesText") || undefined,
    studio: str(r, "projectStudio").trim() || undefined,
    castNeeded,
    crewNeeded,
    posterUrl: asset(r, "projectPoster", "media.jpg"),
    posterKey: assetChecksum(r, "projectPoster"),
    posterSmallUrl: posterSource(r.recordName, assetChecksum(r, "projectPoster"), asset(r, "projectPoster", "media.jpg")),
    slides: assets(r, "projectSlides", "media.jpg"),
    genres: list(r, "projectGenres"),
    shootStart: num(r, "projectShootStart"),
    releaseDate: str(r, "projectReleaseDateText") || str(r, "expectedReleaseDate") || undefined,
    releaseDateAt: num(r, "projectExpectedReleaseDate"),
    castAssembled: credits(r, "projectCastAssembled", "projectCastAssembledIDs"),
    crewAssembled: credits(r, "projectCrewAssembled", "projectCrewAssembledIDs"),
    writers: str(r, "writers") || undefined,
    scriptPages: num(r, "scriptPageCount") || undefined,
    postedByProfileID: maker(r),
    editorIDs: editors(r),
    createdAt: created(r) || undefined,
    editedAt: num(r, "lastEditedDate"),
  };
}

function event(r: CKRecord): NexusEvent {
  // Current records use eventStartTime/eventEndTime; older ones used ...Date.
  const start = num(r, "eventStartTime") ?? num(r, "eventStartDate");
  return {
    kind: "event",
    id: r.recordName,
    title: str(r, "eventTitle") || "Untitled",
    host: str(r, "eventHost"),
    location: str(r, "eventLocationText") || str(r, "eventLocation"),
    when: start ? eventFmt.format(new Date(start)) : "",
    logline: str(r, "eventDescription"),
    ticketed: !!str(r, "eventTicketsURL"),
    flyerUrl: asset(r, "eventFlyer", "media.jpg"),
    flyerKey: assetChecksum(r, "eventFlyer"),
    flyerSmallUrl: posterSource(r.recordName, assetChecksum(r, "eventFlyer"), asset(r, "eventFlyer", "media.jpg")),
    startsAt: start,
    endsAt: num(r, "eventEndTime") ?? num(r, "eventEndDate"),
    category: str(r, "eventCategory") || undefined,
    // Older events stored the lineup as one comma-separated string.
    lineup: (list(r, "eventLineup").length ? list(r, "eventLineup") : str(r, "eventLineup").split(","))
      .map((s) => s.trim())
      .filter(Boolean),
    expectations: str(r, "eventExpectations").trim() || undefined,
    ticketsUrl: str(r, "eventTicketsURL").trim() || undefined,
    applyUrl: str(r, "eventApplicationURL").trim() || undefined,
    showings: list(r, "eventShowtimes")
      .map((entry) => entry.split("|").map((t) => Date.parse(t)))
      .filter((pair): pair is [number, number] => pair.length === 2 && pair.every(Number.isFinite))
      .sort((a, b) => a[0] - b[0]),
    postedBy: str(r, "submittedBy") || undefined,
    postedByProfileID: maker(r),
    editorIDs: editors(r),
    createdAt: created(r) || undefined,
    editedAt: num(r, "lastEditedDate"),
  };
}

/** "fetch failed" alone hides why; the cause says ENOTFOUND, ETIMEDOUT, a certificate problem... */
function describeError(error: unknown): string {
  if (!(error instanceof Error)) return String(error);
  const cause = error.cause as { code?: string; message?: string } | undefined;
  return cause ? `${error.message} (${[cause.code, cause.message].filter(Boolean).join(": ")})` : error.message;
}

async function safeQuery(type: string, desiredKeys?: string[]): Promise<CKRecord[]> {
  // One missing or misconfigured record type shouldn't take the whole site down.
  return (await tryQuery(type, desiredKeys)) ?? [];
}

/** Waits between tries of a failed query: CloudKit often fails one request and answers the next. */
const RETRY_DELAYS_MS = [400, 1200];

/**
 * Every record of a type, trying again twice if CloudKit fails. Null when it still
 * fails, so callers can tell "none" from "couldn't load" (see getAllPosts).
 */
async function tryQuery(type: string, desiredKeys?: string[]): Promise<CKRecord[] | null> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await queryAll(type, 2000, desiredKeys);
    } catch (error) {
      if (attempt >= RETRY_DELAYS_MS.length) {
        console.error(`[cloudkit] ${type}:`, describeError(error));
        return null;
      }
      await new Promise((resolve) => setTimeout(resolve, RETRY_DELAYS_MS[attempt]));
    }
  }
}

/** Post IDs (UUID strings) a moderator has removed. */
async function removedIDs(): Promise<Set<string>> {
  const actions = await safeQuery("ModerationAction");
  return new Set(actions.filter((a) => num(a, "isRemoved") === 1).map((a) => str(a, "postID").toUpperCase()));
}

const visible = (removed: Set<string>) => (r: CKRecord) =>
  num(r, "isApproved") === 1 && !removed.has(r.recordName.toUpperCase());

/**
 * Placeholder posts from an early app build that are still in the public database.
 * Hardcoded so they never show (same list as the app's `PlaceholderData.swift`):
 * the five fixed record IDs, plus three that come back under other IDs, by title.
 */
const PLACEHOLDER_TITLES = new Set(["morgan taylor - acting reel 2026", "the midnight garden", "neon dreams"]);
const PLACEHOLDER_ID = /^00000000-0000-0000-0000-00000000000[1-5]$/;
const notPlaceholder = (p: { id: string; title: string }) =>
  !PLACEHOLDER_ID.test(p.id) &&
  !PLACEHOLDER_TITLES.has(p.title.replace(/[\u2013\u2014]/g, "-").trim().toLowerCase());

/** Tag on the feed caches, so a post made on the website shows up right away. */
export const POSTS_TAG = "posts";

/**
 * Fills in playlists made of existing posts: each one plays its own uploaded videos, then
 * the posts it lists, under those posts' titles, and takes on those posts' school feeds.
 * Runs after attachAvatars, which sets each post's schoolSlugs. Returns the IDs of every post that sits
 * in a playlist; those stay off the feeds (still on portfolios and at their own address).
 */
function resolvePlaylists(posts: Post[]): Set<string> {
  const byID = new Map(posts.map((p) => [p.id.toUpperCase(), p]));
  const inPlaylist = new Set<string>();
  for (const p of posts) {
    if (!p.playlistPostIDs?.length) continue;
    const items = p.playlistPostIDs.flatMap((id) => {
      const q = byID.get(id.toUpperCase());
      // Never another playlist, so two can't hide each other.
      return q && q.id !== p.id && q.videoUrl && !q.playlistPostIDs?.length ? [q] : [];
    });
    if (items.length === 0) {
      // None of its posts are left: a lone upload plays as an ordinary video.
      if (p.videos?.length === 1) p.videos = undefined;
      continue;
    }
    for (const q of items) inPlaylist.add(q.id);
    // The playlist stands in for the posts it holds (they're off the feeds), so it's on the
    // feed of every school they're on: an actor showcase with UT and USC actors shows at both.
    p.schoolSlugs = [...new Set([...(p.schoolSlugs ?? []), ...items.flatMap((q) => q.schoolSlugs ?? [])])];
    const own = p.videos ?? (p.videoUrl ? [{ url: p.videoUrl, title: "" }] : []);
    // An added post brings its own thumbnail, and its main credit is who's in it.
    p.videos = [
      ...own,
      ...items.map((q) => ({
        url: q.videoUrl!,
        title: q.title,
        postID: q.id,
        thumb: q.thumbnailUrl,
        actor: { name: q.creator, profileID: q.creatorProfileID, avatarUrl: q.creatorAvatarUrl, avatarKey: q.creatorAvatarKey },
      })),
    ];
    // A playlist with no upload of its own previews and opens on its first video.
    if (!p.videoUrl) {
      p.videoUrl = p.videos[0].url;
      p.duration = items[0].duration;
    }
  }
  return inPlaylist;
}

/**
 * One post straight from CloudKit by its record name. For a post too new to be in
 * getAllPosts yet: CloudKit's queries take a few seconds to list a new record, but
 * looking one up by name finds it at once. Same rules as the feed (approved, not removed).
 */
export async function postByID(id: string): Promise<Post | undefined> {
  "use cache: remote";
  cacheLife({ stale: 30, revalidate: 60, expire: 300 });
  cacheTag(POSTS_TAG);
  if (!/^[0-9A-Fa-f-]{36}$/.test(id)) return undefined;
  const [r, removed] = await Promise.all([lookup(id).catch(() => null), removedIDs()]);
  if (!r || !visible(removed)(r)) return undefined;
  const map: Record<string, (r: CKRecord) => Post> = {
    FilmSubmission: film,
    MusicSubmission: music,
    ReelSubmission: reel,
    PhotographySubmission: photography,
    DesignSubmission: design,
  };
  const post = map[r.recordType]?.(r);
  return post && notPlaceholder(post) ? post : undefined;
}

export async function getAllPosts(): Promise<{ posts: Post[]; festivalBound: Set<string>; inPlaylist: Set<string> }> {
  "use cache: remote";
  cacheTag(POSTS_TAG);

  const [removed, people, ...loaded] = await Promise.all([
    removedIDs(),
    profiles(),
    tryQuery("FilmSubmission"),
    tryQuery("MusicSubmission"),
    tryQuery("ReelSubmission"),
    tryQuery("PhotographySubmission"),
    tryQuery("DesignSubmission"),
  ]);
  const [films, musics, reels, photos, designs] = loaded.map((records) => records ?? []);
  // When CloudKit fails even after retrying, what loaded is still shown, but kept only
  // briefly. Without the profiles every post would count as UT's (school feeds empty out),
  // and a missing type would drop those posts from feeds and portfolios, for up to an hour.
  if (!people.complete || loaded.some((records) => records === null)) {
    cacheLife({ stale: 30, revalidate: 30, expire: 300 });
  } else {
    cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  }
  const ok = visible(removed);
  const festivalBound = new Set(films.filter((f) => num(f, "filmFestivalBound") === 1).map((f) => f.recordName));
  const posts = [
    ...films.filter(ok).map(film),
    ...musics.filter(ok).map(music),
    ...reels.filter(ok).map(reel),
    ...photos.filter(ok).map(photography),
    ...designs.filter(ok).map(design),
  ].filter(notPlaceholder);
  const order = new Map([...films, ...musics, ...reels, ...photos, ...designs].map((r) => [r.recordName, created(r)]));
  posts.sort((a, b) => (order.get(b.id) ?? 0) - (order.get(a.id) ?? 0));
  applyMainCredit(posts);
  attachAvatars(posts, people);
  const thumbKeys = new Map(
    [
      ...films.map((r) => [r.recordName, assetChecksum(r, "filmThumbnail")] as const),
      ...musics.map((r) => [r.recordName, assetChecksum(r, "musicCover")] as const),
      ...reels.map((r) => [r.recordName, assetChecksum(r, "reelThumbnail")] as const),
      ...photos.map((r) => [r.recordName, assetChecksum(r, "photographyThumbnail") ?? assetChecksum(r, "photographyImages")] as const),
      ...designs.map((r) => [r.recordName, assetChecksum(r, "designThumbnail") ?? assetChecksum(r, "designImages")] as const),
    ].filter((e): e is readonly [string, string] => !!e[1]),
  );
  // The checksum also names the picture in the site's small-image addresses (lib/smallImage.ts).
  // Posts saved with their thumbnail's size (thumbWidth / thumbHeight) need no measuring.
  const savedAspect = new Map(
    [...films, ...musics, ...reels, ...photos, ...designs].flatMap((r) => {
      const w = num(r, "thumbWidth");
      const h = num(r, "thumbHeight");
      return w && h && w > 0 && h > 0 ? [[r.recordName, w / h] as const] : [];
    }),
  );
  for (const p of posts) {
    p.thumbnailKey = thumbKeys.get(p.id);
    p.aspect = savedAspect.get(p.id) ?? p.aspect;
  }
  await withTrueAspects(posts.filter((p) => !savedAspect.has(p.id)), thumbKeys);
  return { posts, festivalBound, inPlaylist: resolvePlaylists(posts) };
}

export async function getDiscoverItems(): Promise<(Project | NexusEvent)[]> {
  "use cache: remote";
  cacheTag(POSTS_TAG);

  const [removed, projects, events, people] = await Promise.all([
    removedIDs(),
    safeQuery("ProjectSubmission"),
    safeQuery("EventSubmission"),
    profiles(),
  ]);
  // Without the profiles every project would count as UT's, so check again soon.
  if (!people.complete) {
    cacheLife({ stale: 30, revalidate: 30, expire: 300 });
  } else {
    cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  }
  const ok = visible(removed);
  const items = [...projects.filter(ok).map(project), ...events.filter(ok).map(event)].filter(notPlaceholder);
  attachProjectSchools(items, people);
  const order = new Map([...projects, ...events].map((r) => [r.recordName, created(r)]));
  return items.sort((a, b) => (order.get(b.id) ?? 0) - (order.get(a.id) ?? 0));
}

type Profile = {
  id: string;
  name: string;
  imageUrl?: string;
  imageKey?: string;
  /** In profileDirectory, `imageUrl` is a small copy and this is the full-size upload. */
  fullImageUrl?: string;
  roles: string[];
  /** The profile's school as stored ("University of Southern California"); empty for early UT accounts. */
  school?: string;
};

/** A name as a lookup key: case, accents, punctuation and extra spaces don't matter. */
const nameKey = (name: string) =>
  name.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

async function profiles(): Promise<{ byID: Map<string, Profile>; byName: Map<string, Profile>; schoolByName: Map<string, string>; duplicates: Set<string>; complete: boolean }> {
  // Only the fields used here: profiles also hold bios, links and more that no list needs.
  const loaded = await tryQuery("UserProfile", ["firstName", "lastName", "profileImage", "userTypes", "school"]);
  const records = loaded ?? [];
  const byID = new Map<string, Profile>();
  const nameCounts = new Map<string, number>();
  const byName = new Map<string, Profile>();
  for (const r of records) {
    const name = `${str(r, "firstName")} ${str(r, "lastName")}`.trim();
    const profile = {
      id: r.recordName,
      name,
      imageUrl: asset(r, "profileImage", "media.jpg"),
      imageKey: assetChecksum(r, "profileImage"),
      // The app's role tags ("Director", "Actor"...), stored as one comma-separated string.
      roles: str(r, "userTypes").split(",").map((t) => t.trim()).filter(Boolean),
      school: str(r, "school"),
    };
    byID.set(r.recordName, profile);
  }
  // Someone with an app account who also made one on the website shows once, as the
  // app account, until verifying that email in the app merges the two.
  const appNames = new Set([...byID.values()].filter((p) => !isWebProfile(p.id)).map((p) => p.name.toLowerCase()).filter(Boolean));
  const duplicates = new Set([...byID.values()].filter((p) => isWebProfile(p.id) && appNames.has(p.name.toLowerCase())).map((p) => p.id));
  // Every school each name belongs to, website duplicates included.
  const schoolsByName = new Map<string, Set<string>>();
  for (const profile of byID.values()) {
    const key = nameKey(profile.name);
    if (!key) continue;
    schoolsByName.set(key, (schoolsByName.get(key) ?? new Set()).add(profile.school ?? ""));
    if (duplicates.has(profile.id)) continue;
    nameCounts.set(key, (nameCounts.get(key) ?? 0) + 1);
    byName.set(key, profile);
  }
  // A name shared by two people can't pick a photo, so only unique names match.
  for (const [key, count] of nameCounts) if (count > 1) byName.delete(key);
  // A credit typed by name still puts a post on that person's school feed when every
  // profile with that name is at the same school (e.g. someone with two accounts).
  const schoolByName = new Map<string, string>();
  for (const [key, schools] of schoolsByName) if (schools.size === 1) schoolByName.set(key, [...schools][0]);
  // false when CloudKit couldn't list the profiles: everyone is missing, not just new.
  return { byID, byName, schoolByName, duplicates, complete: loaded !== null };
}

/** A profile made on the website (UserProfile_web_<id>), not in the app. */
const isWebProfile = (profileID: string) => profileID.startsWith("UserProfile_web_");

/** Cache tag for the list of every profile, so a new account shows up right away. */
export const PROFILES_TAG = "profiles";

/** Every app profile with a name, A to Z, for picking someone to feature. */
export async function profileDirectory(): Promise<Profile[]> {
  "use cache: remote";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  cacheTag(PROFILES_TAG);
  const { byID, duplicates } = await profiles();
  return [...byID.values()]
    .filter((p) => p.name && !duplicates.has(p.id))
    .sort((a, b) => a.name.localeCompare(b.name))
    // Lists and cards show a small copy; the upload itself stays available as fullImageUrl.
    .map((p) => ({ ...p, fullImageUrl: p.imageUrl, imageUrl: profileImage(p.id, p.imageKey, p.imageUrl) }));
}

/** A profile picture's full-size link and checksum as they are now, for the small-image route. */
export async function profileImageSource(profileID: string): Promise<{ url?: string; key?: string } | undefined> {
  const listed = (await profileDirectory()).find((p) => p.id === profileID);
  if (listed) return { url: listed.fullImageUrl, key: listed.imageKey };
  // Not in the list (no name yet, or newer than the list): read the one record.
  const r = await lookup(profileID).catch(() => null);
  return r?.recordType === "UserProfile" ? { url: asset(r, "profileImage", "media.jpg"), key: assetChecksum(r, "profileImage") } : undefined;
}

/**
 * Fills in profile pictures and profile links: by linked profile ID first, then by an
 * unambiguous name, so a credit typed by name still reaches that person's portfolio.
 */
function personLookup(people: Awaited<ReturnType<typeof profiles>>) {
  // A linked profile with no name is a blank one (e.g. an app account that never filled in
  // its profile while the person set up a full one on the website): the name decides then.
  const find = (id: string | undefined, name: string) => {
    const linked = id ? people.byID.get(id) : undefined;
    return (linked?.name ? linked : undefined) ?? people.byName.get(nameKey(name)) ?? linked;
  };
  // The school of a credited person: their profile's, or else the one school everyone with
  // that name is at. A blank profile counts as UT (like the app's early accounts) only when
  // nothing else says where the person is.
  const schoolOf = (person: Profile | undefined, name: string) => {
    if (person?.name && person.school) return schoolSlugForName(person.school);
    const key = nameKey(name);
    if (people.schoolByName.has(key)) return schoolSlugForName(people.schoolByName.get(key));
    return person ? schoolSlugForName(person.school) : undefined;
  };
  return { find, schoolOf };
}

/**
 * Which schools each project belongs to, for Discover: the school of the account that
 * posted it, of everyone it shared edit access with, and of everyone already on its cast
 * and crew, so a UT and USC collaboration shows at both. With nobody known it counts as
 * UT's, like the app's early posts.
 */
function attachProjectSchools(items: (Project | NexusEvent)[], people: Awaited<ReturnType<typeof profiles>>) {
  const { find, schoolOf } = personLookup(people);
  for (const item of items) {
    if (item.kind !== "project") continue;
    const schools = new Set<string>();
    const add = (id: string | undefined, name: string) => {
      if (!id && !name) return;
      const school = schoolOf(find(id, name), name);
      if (school) schools.add(school);
    };
    add(item.postedByProfileID, item.postedBy);
    for (const id of item.editorIDs ?? []) add(id, "");
    for (const c of [...(item.castAssembled ?? []), ...(item.crewAssembled ?? [])]) add(c.profileID, c.name);
    if (!schools.size) schools.add(schoolSlugForName(undefined)!);
    item.schoolSlugs = [...schools];
  }
}

function attachAvatars(posts: Post[], people: Awaited<ReturnType<typeof profiles>>) {
  const { find, schoolOf } = personLookup(people);
  for (const post of posts) {
    const creator = find(post.creatorProfileID, post.creator);
    post.creatorAvatarUrl = creator?.imageUrl;
    post.creatorAvatarKey = creator?.imageKey;
    post.creatorProfileID = creator?.id ?? post.creatorProfileID;
    // A post is on the feed of the school of the account that posted it, of its main
    // credit's school and of every credited person's school, so a UT and USC collaboration
    // shows on both. The poster always counts: a song posted under an artist name, or a film
    // whose director has no profile, still shows at the poster's school. Only when neither
    // the poster nor the main credit has a profile does it count as UT, like the app's early posts.
    const schools = new Set<string>();
    const posterName = post.details?.submittedBy ?? "";
    const poster = post.makerProfileID || posterName ? find(post.makerProfileID, posterName) : undefined;
    const posterSchool = poster || posterName ? schoolOf(poster, posterName) : undefined;
    if (posterSchool) schools.add(posterSchool);
    const creatorSchool = schoolOf(creator, post.creator) ?? posterSchool ?? schoolSlugForName(undefined);
    post.creatorSchoolSlug = creatorSchool;
    if (creatorSchool) schools.add(creatorSchool);
    for (const group of post.details?.creditGroups ?? []) {
      for (const c of group.credits) {
        const person = find(c.profileID, c.name);
        c.avatarUrl = person?.imageUrl;
        c.avatarKey = person?.imageKey;
        c.profileID = person?.id ?? c.profileID;
        const school = schoolOf(person, c.name);
        c.schoolSlug = school;
        if (school) schools.add(school);
      }
    }
    post.schoolSlugs = [...schools];
  }
}

const CREDIT_RULES: Record<Post["category"], { prefix: string; roles: RegExp }> = {
  // Exact role names, so "Director of Photography" or "Assistant Director" never count.
  film: { prefix: "Directed by", roles: /^(co[- ]?)?director$/i },
  music: { prefix: "by", roles: /artist|vocal|singer/i },
  performance: { prefix: "Performed by", roles: /perform|actor|actress|dancer|singer|musician/i },
  design: { prefix: "Directed by", roles: /^(co[- ]?|art |creative )?director$/i },
  photography: { prefix: "Shot by", roles: /photograph/i },
};

/**
 * The feed's main credit is whoever holds the post's lead role (the director of a
 * film, the photographer of a shoot...), not whoever submitted it. Falls back to the
 * artist field the app stores, then the submitter.
 */
function applyMainCredit(posts: Post[]) {
  for (const post of posts) {
    const rule = CREDIT_RULES[post.category];
    const all = (post.details?.creditGroups ?? []).flatMap((g) => g.credits);
    const holders = all.filter((c) => rule.roles.test(c.role));
    const byline = post.details?.byline;
    post.creditPrefix = rule.prefix;
    const submitter = post.details?.submittedBy ?? "";
    let name = byline || "";
    let profileID: string | undefined;
    // Music, performance and photography store the lead artist directly; film and
    // design name their director in the crew list.
    if (holders.length && (!byline || post.category === "film" || post.category === "design")) {
      const names = [...new Set(holders.map((c) => c.name))];
      // The same Credit objects as in the crew list, so they pick up profile photos too.
      if (names.length > 1) post.mainCredits = names.map((n) => holders.find((c) => c.name === n)!);
      name = names.length > 2 ? `${names[0]} & others` : names.join(" & ");
      profileID = holders[0].profileID;
    }
    if (name) {
      post.creator = name;
      // The submitter's own profile only applies when they're the one credited.
      if (name !== submitter) post.creatorProfileID = profileID;
    }
  }
}

/**
 * Thumbnail shapes already measured, by the file's checksum. The download URL changes
 * on every fetch but the checksum only changes with the picture, so each refresh
 * re-reads just new or replaced thumbnails instead of every one on the site.
 */
const aspectByChecksum = new Map<string, number>();

/** Replaces each post's default aspect with its thumbnail's real one, many at a time. */
async function withTrueAspects(posts: Post[], thumbKeys: Map<string, string>) {
  const queue: Post[] = [];
  for (const p of posts) {
    if (!p.thumbnailUrl) continue;
    const known = aspectByChecksum.get(thumbKeys.get(p.id) ?? "");
    if (known) p.aspect = known;
    else queue.push(p);
  }
  const worker = async () => {
    for (let p = queue.shift(); p; p = queue.shift()) {
      const aspect = await imageAspect(p.thumbnailUrl!);
      if (!aspect) continue;
      p.aspect = aspect;
      const key = thumbKeys.get(p.id);
      if (key) aspectByChecksum.set(key, aspect);
    }
  };
  await Promise.all(Array.from({ length: 16 }, worker));
}

export { isCloudKitConfigured };

// MARK: - Accounts

export type Account = {
  /** `UserProfile_<userRecordName>`, the ID credits link to. */
  profileID: string;
  name: string;
  imageUrl?: string;
  bio: string;
  /** "Class of '26 • Radio-Television-Film", or role • company • industry for pros. */
  academicLine: string;
  /** Students only: their major and graduation year ("2027"), shown on separate rows. */
  major?: string;
  classOf?: string;
  school: string;
  roles: string[];
  instagram?: string;
  website?: string;
  /** "Looking for Work" / "Booked until YYYY-MM-DD" / "Busy" (UserProfile.workStatus); see lib/workStatus.ts. */
  workStatus?: string;
  /** The custom post order, shared with the app (submission record names). */
  portfolioOrder: string[];
  /** Custom tile sizes for the portfolio grid; empty means the default layout. */
  portfolioLayout: TileSizes;
};

/** Cache tag for one account, so a saved layout shows immediately. */
export const accountTag = (userRecordName: string) => `account:${userRecordName}`;

/**
 * The app profile for a signed-in account. The website writes nothing here except
 * the owner's own portfolio layout (see app/(app)/portfolio/actions.ts).
 */
/**
 * Whether a website account (`web_<id>`) still exists. It's deleted once its owner
 * verifies the same email in the app, which merges it into their app account
 * (verification-service/src/accountMerge.ts). Throws when CloudKit can't say, so a
 * hiccup is never cached as "gone".
 */
export async function webAccountExists(userRecordName: string): Promise<boolean> {
  "use cache: remote";
  cacheLife({ stale: 60, revalidate: 120, expire: 600 });
  cacheTag(accountTag(userRecordName));
  return (await lookup(`UserProfile_${userRecordName}`)) !== null;
}

export async function getAccount(userRecordName: string): Promise<Account | null> {
  // Shared by every server instance (like the post lists): it's on every signed-in page.
  "use cache: remote";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  cacheTag(accountTag(userRecordName));

  const profileID = `UserProfile_${userRecordName}`;
  let r: CKRecord | null = null;
  try {
    r = await lookup(profileID);
  } catch (error) {
    console.error("[cloudkit] UserProfile lookup:", describeError(error));
  }
  if (!r) return null;

  const pro = num(r, "isIndustryProfessional") === 1;
  const year = str(r, "graduationYear");
  const academicLine = pro
    ? [str(r, "companyRole"), str(r, "company"), str(r, "industry")].filter(Boolean).join(" • ")
    : [year ? `Class of '${year.slice(-2)}` : "", str(r, "major")].filter(Boolean).join(" • ");
  return {
    profileID,
    name: `${str(r, "firstName")} ${str(r, "lastName")}`.trim(),
    imageUrl: profileImage(profileID, assetChecksum(r, "profileImage"), asset(r, "profileImage", "media.jpg")),
    bio: str(r, "bio"),
    academicLine,
    major: pro ? undefined : str(r, "major") || undefined,
    classOf: pro ? undefined : year || undefined,
    school: str(r, "school"),
    roles: str(r, "userTypes").split(",").map((t) => t.trim()).filter(Boolean),
    instagram: str(r, "instagramHandle").replace(/^@/, "") || undefined,
    website: str(r, "websiteURL") || undefined,
    workStatus: str(r, "workStatus") || undefined,
    portfolioOrder: list(r, "portfolioOrder"),
    portfolioLayout: parseTileSizes(str(r, "portfolioLayoutWebsite")),
  };
}

/** The signed-in account's editable profile fields, fresh from CloudKit (never cached). */
export async function getProfileFields(userRecordName: string): Promise<ProfileFields | null> {
  const r = await lookup(`UserProfile_${userRecordName}`);
  if (!r) return null;
  return {
    firstName: str(r, "firstName"),
    lastName: str(r, "lastName"),
    bio: str(r, "bio"),
    roles: str(r, "userTypes").split(",").map((t) => t.trim()).filter(Boolean),
    isIndustryProfessional: num(r, "isIndustryProfessional") === 1,
    major: str(r, "major"),
    minor: str(r, "minor"),
    certificate: str(r, "certificate"),
    graduationYear: str(r, "graduationYear"),
    company: str(r, "company"),
    companyRole: str(r, "companyRole"),
    industry: str(r, "industry"),
    instagramHandle: str(r, "instagramHandle"),
    websiteURL: str(r, "websiteURL"),
    workStatus: cleanWorkStatus(str(r, "workStatus")),
  };
}
