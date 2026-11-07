import { cacheLife, cacheTag } from "next/cache";
import { parseTileSizes, type TileSizes } from "../portfolioLayout";
import type { NexusEvent, Project } from "../discoverContent";
import type { Post } from "../mockContent";
import type { ProfileFields } from "../profileFields";
import { cleanWorkStatus } from "../workStatus";
import type { Credit, CreditGroup } from "../postDetails";
import { imageAspect } from "./imageSize";
import { asset, assets, isCloudKitConfigured, list, lookup, num, queryAll, str, type CKRecord } from "./client";

/**
 * Real content from the app's public CloudKit database, mapped into the website's
 * shapes. Mirrors the app's own rules: only approved posts, never moderator-removed
 * ones, and festival-bound films stay out of the feed.
 *
 * Cached for a few minutes; asset download URLs are refreshed with each fetch.
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
    creatorProfileID: str(r, "userID") ? `UserProfile_${str(r, "userID")}` : undefined,
  };
}

function film(r: CKRecord): Post {
  const p = base(r, "film", str(r, "filmTitle"), str(r, "submittedBy"));
  const studio = str(r, "filmStudio");
  return {
    ...p,
    thumbnailUrl: asset(r, "filmThumbnail", "media.jpg"),
    duration: num(r, "filmVideoDuration"),
    videoUrl: asset(r, "filmVideo", "media.mp4"),
    images: [...assets(r, "filmStills", "media.jpg"), ...assets(r, "filmBTS", "media.jpg")],
    details: {
      ageRating: str(r, "filmAgeRating") || undefined,
      genres: list(r, "filmGenres"),
      explicit: num(r, "filmExplicit") === 1,
      studio: studio && studio !== "Independent" ? studio : undefined,
      releaseYear: str(r, "filmReleaseYear") || undefined,
      logline: str(r, "filmLogline") || undefined,
      description: str(r, "filmDescription"),
      creditGroups: groups(["Cast", credits(r, "filmCast", "filmCastIDs")], ["Crew", credits(r, "filmCrew", "filmCrewIDs")]),
      trailerUrl: asset(r, "filmTrailer", "media.mp4"),
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
  const audioUrl = asset(r, "musicAudio", `media.${ext}`);
  // EP/Album tracks after the first, saved by the app as a parallel asset + extension list.
  const exts = list(r, "musicTrackExts");
  const extra = ((r.fields["musicTracks"]?.value as { downloadURL?: string }[] | undefined) ?? []).flatMap((a, i) =>
    a?.downloadURL ? [a.downloadURL.replace("${f}", `media.${(exts[i] || "m4a").replace(/^\./, "")}`)] : [],
  );
  const tracks = audioUrl && extra.length ? [audioUrl, ...extra] : undefined;
  return {
    ...p,
    thumbnailUrl: asset(r, "musicCover", "media.jpg"),
    duration: num(r, "musicAudioDuration"),
    audioUrl,
    tracks,
    videoUrl: asset(r, "musicVideo", "media.mp4"),
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
  return {
    ...p,
    thumbnailUrl: asset(r, "reelThumbnail", "media.jpg"),
    duration: num(r, "reelVideoDuration"),
    videoUrl: asset(r, "reelVideo", "media.mp4"),
    details: {
      byline: artist || undefined,
      genres: [],
      kindLabel: str(r, "reelType") || undefined,
      description: str(r, "reelDescription"),
      creditGroups: groups(["Crew", credits(r, "orderedCrew", "orderedCrewIDs")]),
      featuredWork: featured.length ? featured : undefined,
      submittedBy: str(r, "submittedBy"),
    },
  };
}

function equipment(r: CKRecord) {
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
    videoUrl: asset(r, "designVideo", "media.mp4"),
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
    castNeeded,
    crewNeeded,
    posterUrl: asset(r, "projectPoster", "media.jpg"),
    slides: assets(r, "projectSlides", "media.jpg"),
    genres: list(r, "projectGenres"),
    shootStart: num(r, "projectShootStart"),
    releaseDate: str(r, "projectReleaseDateText") || str(r, "expectedReleaseDate") || undefined,
    releaseDateAt: num(r, "projectExpectedReleaseDate"),
    castAssembled: credits(r, "projectCastAssembled", "projectCastAssembledIDs"),
    crewAssembled: credits(r, "projectCrewAssembled", "projectCrewAssembledIDs"),
    writers: str(r, "writers") || undefined,
    scriptPages: num(r, "scriptPageCount") || undefined,
    postedByProfileID: str(r, "userID") ? `UserProfile_${str(r, "userID")}` : undefined,
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
    postedByProfileID: str(r, "userID") ? `UserProfile_${str(r, "userID")}` : undefined,
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

async function safeQuery(type: string): Promise<CKRecord[]> {
  try {
    return await queryAll(type);
  } catch (error) {
    // One missing or misconfigured record type shouldn't take the whole site down.
    console.error(`[cloudkit] ${type}:`, describeError(error));
    return [];
  }
}

/** Post IDs (UUID strings) a moderator has removed. */
async function removedIDs(): Promise<Set<string>> {
  const actions = await safeQuery("ModerationAction");
  return new Set(actions.filter((a) => num(a, "isRemoved") === 1).map((a) => str(a, "postID").toUpperCase()));
}

const visible = (removed: Set<string>) => (r: CKRecord) =>
  num(r, "isApproved") === 1 && !removed.has(r.recordName.toUpperCase());

export async function getAllPosts(): Promise<{ posts: Post[]; festivalBound: Set<string> }> {
  "use cache";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });

  const [removed, people, films, musics, reels, photos, designs] = await Promise.all([
    removedIDs(),
    profiles(),
    safeQuery("FilmSubmission"),
    safeQuery("MusicSubmission"),
    safeQuery("ReelSubmission"),
    safeQuery("PhotographySubmission"),
    safeQuery("DesignSubmission"),
  ]);
  const ok = visible(removed);
  const festivalBound = new Set(films.filter((f) => num(f, "filmFestivalBound") === 1).map((f) => f.recordName));
  const posts = [
    ...films.filter(ok).map(film),
    ...musics.filter(ok).map(music),
    ...reels.filter(ok).map(reel),
    ...photos.filter(ok).map(photography),
    ...designs.filter(ok).map(design),
  ];
  const order = new Map([...films, ...musics, ...reels, ...photos, ...designs].map((r) => [r.recordName, created(r)]));
  posts.sort((a, b) => (order.get(b.id) ?? 0) - (order.get(a.id) ?? 0));
  applyMainCredit(posts);
  attachAvatars(posts, people);
  await withTrueAspects(posts);
  return { posts, festivalBound };
}

export async function getDiscoverItems(): Promise<(Project | NexusEvent)[]> {
  "use cache";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });

  const [removed, projects, events] = await Promise.all([
    removedIDs(),
    safeQuery("ProjectSubmission"),
    safeQuery("EventSubmission"),
  ]);
  const ok = visible(removed);
  const items = [...projects.filter(ok).map(project), ...events.filter(ok).map(event)];
  const order = new Map([...projects, ...events].map((r) => [r.recordName, created(r)]));
  return items.sort((a, b) => (order.get(b.id) ?? 0) - (order.get(a.id) ?? 0));
}

type Profile = { id: string; name: string; imageUrl?: string; roles: string[] };

async function profiles(): Promise<{ byID: Map<string, Profile>; byName: Map<string, Profile> }> {
  const records = await safeQuery("UserProfile");
  const byID = new Map<string, Profile>();
  const nameCounts = new Map<string, number>();
  const byName = new Map<string, Profile>();
  for (const r of records) {
    const name = `${str(r, "firstName")} ${str(r, "lastName")}`.trim();
    const profile = {
      id: r.recordName,
      name,
      imageUrl: asset(r, "profileImage", "media.jpg"),
      // The app's role tags ("Director", "Actor"...), stored as one comma-separated string.
      roles: str(r, "userTypes").split(",").map((t) => t.trim()).filter(Boolean),
    };
    byID.set(r.recordName, profile);
    const key = name.toLowerCase();
    if (key) {
      nameCounts.set(key, (nameCounts.get(key) ?? 0) + 1);
      byName.set(key, profile);
    }
  }
  // A name shared by two people can't pick a photo, so only unique names match.
  for (const [key, count] of nameCounts) if (count > 1) byName.delete(key);
  return { byID, byName };
}

/** Every app profile with a name, A to Z, for picking someone to feature. */
export async function profileDirectory(): Promise<Profile[]> {
  "use cache";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  const { byID } = await profiles();
  return [...byID.values()].filter((p) => p.name).sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * Fills in profile pictures and profile links: by linked profile ID first, then by an
 * unambiguous name, so a credit typed by name still reaches that person's portfolio.
 */
function attachAvatars(posts: Post[], people: Awaited<ReturnType<typeof profiles>>) {
  const find = (id: string | undefined, name: string) =>
    (id ? people.byID.get(id) : undefined) ?? people.byName.get(name.trim().toLowerCase());
  for (const post of posts) {
    const creator = find(post.creatorProfileID, post.creator);
    post.creatorAvatarUrl = creator?.imageUrl;
    post.creatorProfileID = creator?.id ?? post.creatorProfileID;
    for (const group of post.details?.creditGroups ?? []) {
      for (const c of group.credits) {
        const person = find(c.profileID, c.name);
        c.avatarUrl = person?.imageUrl;
        c.profileID = person?.id ?? c.profileID;
      }
    }
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

/** Replaces each post's default aspect with its thumbnail's real one, a few at a time. */
async function withTrueAspects(posts: Post[]) {
  const queue = posts.filter((p) => p.thumbnailUrl);
  const worker = async () => {
    for (let p = queue.shift(); p; p = queue.shift()) {
      const aspect = await imageAspect(p.thumbnailUrl!);
      if (aspect) p.aspect = aspect;
    }
  };
  await Promise.all(Array.from({ length: 8 }, worker));
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
export async function getAccount(userRecordName: string): Promise<Account | null> {
  "use cache";
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
    imageUrl: asset(r, "profileImage", "media.jpg"),
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
    portfolioLayout: parseTileSizes(str(r, "portfolioLayout")),
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
