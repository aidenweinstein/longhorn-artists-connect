"use server";

import { randomUUID, timingSafeEqual } from "node:crypto";
import { updateTag } from "next/cache";
import { currentAccount } from "@/lib/account";
import { assetUploadURLs, createRecord, isCloudKitConfigured, type CKField } from "@/lib/cloudkit/client";
import { POSTS_TAG, accountTag } from "@/lib/cloudkit/content";
import { signValue } from "@/lib/session";
import {
  ASSET_FIELDS,
  MAX_FILES_PER_FIELD,
  RECORD_TYPES,
  type AssetReceipt,
  type CreditInput,
  type PostInput,
  type PublishResult,
  type ShareTypeID,
  type StartResult,
} from "@/lib/sharePost";

/**
 * Posting from the website. Two steps, so files never pass through this server
 * (Vercel caps a request at 4.5 MB, and films upload at full original quality):
 *
 * 1. startPost hands the browser CloudKit upload URLs for a new record name.
 * 2. The browser sends each file straight to Apple, then publishPost saves the
 *    record with the receipts, written the way the app's MediaModels write it:
 *    auto-approved, owned by the signed-in app account, stamped with its school.
 */

const NOT_LINKED = "To post, sign in with the school email linked to your Nexus app account.";

async function poster() {
  const current = await currentAccount();
  const userRecordName = current?.session.userRecordName;
  if (!current || !userRecordName || !current.account) return null;
  return { session: current.session, account: current.account, userRecordName };
}

const tokenFor = (recordName: string, userRecordName: string) => signValue(`post:${recordName}:${userRecordName}`);

function isShareType(type: unknown): type is ShareTypeID {
  return typeof type === "string" && type in RECORD_TYPES;
}

export async function startPost(type: ShareTypeID, counts: Record<string, number>): Promise<StartResult> {
  if (!isShareType(type)) return { ok: false, message: "Unknown post type." };
  if (!isCloudKitConfigured()) return { ok: false, message: "Posting isn't set up on this server yet." };
  const who = await poster();
  if (!who) return { ok: false, message: NOT_LINKED };

  const allowed = ASSET_FIELDS[type];
  const recordName = randomUUID().toUpperCase();
  const tokens: { recordType: string; recordName: string; fieldName: string }[] = [];
  const slots: [string, number][] = [];
  for (const [field, raw] of Object.entries(counts ?? {})) {
    const n = Math.floor(Number(raw));
    if (!(field in allowed) || !(n > 0)) continue;
    const count = allowed[field] === "one" ? 1 : Math.min(n, MAX_FILES_PER_FIELD);
    slots.push([field, count]);
    const target =
      field === "scriptFile"
        ? { recordType: "Script", recordName: `Script_${recordName}` }
        : { recordType: RECORD_TYPES[type], recordName };
    for (let i = 0; i < count; i++) tokens.push({ ...target, fieldName: field });
  }

  try {
    const flat = await assetUploadURLs(tokens);
    const urls: Record<string, string[]> = {};
    let i = 0;
    for (const [field, count] of slots) urls[field] = flat.slice(i, (i += count));
    return { ok: true, recordName, token: tokenFor(recordName, who.userRecordName), urls };
  } catch (error) {
    console.error("[share] startPost:", error);
    return { ok: false, message: "Couldn't start the upload. Try again in a moment." };
  }
}

// MARK: - Field builders

const s = (value: string): CKField => ({ value, type: "STRING" });
const list = (value: string[]): CKField => ({ value, type: "STRING_LIST" });
const int = (value: number): CKField => ({ value: Math.round(value), type: "INT64" });
const double = (value: number): CKField => ({ value, type: "DOUBLE" });
const time = (value: number): CKField => ({ value: Math.round(value), type: "TIMESTAMP" });

const clean = (v: unknown, max = 5000) => (typeof v === "string" ? v.trim().slice(0, max) : "");
const cleanList = (v: unknown, max = 200) =>
  (Array.isArray(v) ? v : []).map((x) => clean(x, max)).filter(Boolean).slice(0, 200);
const cleanCredits = (v: unknown): CreditInput[] =>
  (Array.isArray(v) ? v : [])
    .map((c: Partial<CreditInput>) => ({ role: clean(c?.role, 120), name: clean(c?.name, 120) }))
    .filter((c) => c.name)
    .slice(0, 200);
const finite = (v: unknown) => (typeof v === "number" && Number.isFinite(v) && v > 0 ? v : undefined);

/** "https://" added when a link has no scheme, as the app's normalizedLink does. */
function link(raw: string): string {
  if (!raw) return "";
  return /^https?:\/\//i.test(raw) ? raw : `https://${raw}`;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
/** "2026-06-15" → "Jun 15, 2026", the date format the app's shoot-date parser reads. */
function dayText(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  return m ? `${MONTHS[Number(m[2]) - 1]} ${Number(m[3])}, ${m[1]}` : "";
}

/** Upload receipts for a field, only in the shape CloudKit returned them. */
function receipts(input: PostInput, field: string): AssetReceipt[] {
  const all = input.assets?.[field];
  return (Array.isArray(all) ? all : [])
    .filter((r): r is AssetReceipt => !!r && typeof r === "object" && typeof (r as { receipt?: unknown }).receipt === "string")
    .slice(0, MAX_FILES_PER_FIELD);
}
const one = (input: PostInput, field: string): CKField | undefined => {
  const [r] = receipts(input, field);
  return r ? { value: r, type: "ASSETID" } : undefined;
};
const many = (input: PostInput, field: string): CKField | undefined => {
  const rs = receipts(input, field);
  return rs.length ? { value: rs, type: "ASSETID_LIST" } : undefined;
};

/** "role: name" entries plus the parallel profile-ID list, as the app stores credits. */
function creditFields(into: Record<string, CKField>, key: string, idsKey: string, credits: CreditInput[]) {
  if (!credits.length) return;
  into[key] = list(credits.map((c) => `${c.role}: ${c.name}`));
  into[idsKey] = list(credits.map(() => ""));
}

type Built = { fields: Record<string, CKField>; required: string[]; missing?: string };

function build(input: PostInput, submittedBy: string): Built {
  const t = (k: string, max?: number) => clean(input.text?.[k], max);
  const l = (k: string) => cleanList(input.lists?.[k]);
  const c = (k: string) => cleanCredits(input.credits?.[k]);
  const n = (k: string) => finite(input.numbers?.[k]);
  const f = (k: string) => input.flags?.[k] === true;
  const title = t("title", 200);
  const fields: Record<string, CKField> = {};
  const put = (key: string, value: CKField | undefined) => {
    if (value !== undefined) fields[key] = value;
  };
  const text = (key: string, value: string) => value && put(key, s(value));
  const strings = (key: string, value: string[]) => value.length && put(key, list(value));

  fields.isApproved = int(1);
  fields.submittedBy = s(submittedBy);

  switch (input.type) {
    case "film": {
      if (!one(input, "filmVideo")) return { fields, required: [], missing: "a video" };
      fields.filmTitle = s(title);
      fields.createdDate = time(Date.now());
      text("filmLogline", t("logline", 500));
      text("filmAgeRating", t("ageRating", 10));
      text("filmStudio", t("studio", 200));
      text("filmReleaseYear", t("releaseYear", 4));
      fields.filmExplicit = int(0);
      fields.filmFestivalBound = int(f("festivalBound") ? 1 : 0);
      strings("filmGenres", l("genres"));
      creditFields(fields, "filmCast", "filmCastIDs", l("cast").map((name) => ({ role: "Actor", name })));
      creditFields(fields, "filmCrew", "filmCrewIDs", c("crew"));
      put("filmVideo", one(input, "filmVideo"));
      const duration = n("videoDuration");
      if (duration) fields.filmVideoDuration = double(duration);
      put("filmThumbnail", one(input, "filmThumbnail"));
      put("filmTrailer", one(input, "filmTrailer"));
      put("filmBTS", many(input, "filmBTS"));
      put("filmStills", many(input, "filmStills"));
      return { fields, required: ["filmTitle", "filmVideo", "isApproved", "submittedBy", "userID"] };
    }
    case "music": {
      if (!one(input, "musicAudio")) return { fields, required: [], missing: "an audio file" };
      fields.musicTitle = s(title);
      fields.createdDate = time(Date.now());
      text("musicArtist", t("artist", 200));
      text("musicReleaseYear", t("releaseYear", 4));
      text("musicCategory", t("category", 40));
      fields.musicExplicit = int(f("explicit") ? 1 : 0);
      strings("musicGenres", l("genres"));
      text("musicSpotifyLink", link(t("spotify", 500)));
      text("musicAppleMusicLink", link(t("appleMusic", 500)));
      text("youtubeMusicLink", link(t("youtubeMusic", 500)));
      text("soundcloudLink", link(t("soundcloud", 500)));
      text("lyrics", t("lyrics", 10000));
      creditFields(fields, "musicRecording", "musicRecordingIDs", c("recording"));
      creditFields(fields, "musicProduction", "musicProductionIDs", c("production"));
      put("musicAudio", one(input, "musicAudio"));
      fields.musicAudioExt = s(t("audioExt", 10) || "m4a");
      const duration = n("audioDuration");
      if (duration) fields.musicAudioDuration = double(duration);
      const tracks = many(input, "musicTracks");
      if (tracks) {
        put("musicTracks", tracks);
        const exts = l("trackExts");
        fields.musicTrackExts = list((tracks.value as unknown[]).map((_, i) => exts[i] || "m4a"));
      }
      put("musicCover", one(input, "musicCover"));
      put("musicVideo", one(input, "musicVideo"));
      return { fields, required: ["musicTitle", "musicAudio", "isApproved", "submittedBy", "userID"] };
    }
    case "performance": {
      if (!one(input, "reelVideo")) return { fields, required: [], missing: "a video" };
      fields.reelTitle = s(title);
      fields.createdDate = time(Date.now());
      text("reelDescription", t("description"));
      text("reelType", t("category", 40));
      text("reelReleaseYear", t("releaseYear", 4));
      creditFields(fields, "orderedCast", "orderedCastIDs", c("cast"));
      strings("featuredWorkManual", l("featured"));
      put("reelVideo", one(input, "reelVideo"));
      const duration = n("videoDuration");
      if (duration) fields.reelVideoDuration = double(duration);
      put("reelThumbnail", one(input, "reelThumbnail"));
      put("reelStills", many(input, "reelStills"));
      return { fields, required: ["reelTitle", "reelVideo", "isApproved", "submittedBy", "userID"] };
    }
    case "photography": {
      if (!many(input, "photographyImages")) return { fields, required: [], missing: "photos" };
      fields.photographyTitle = s(title);
      fields.createdDate = time(Date.now());
      text("photographyDescription", t("description"));
      text("photographyReleaseYear", t("releaseYear", 4));
      strings("photographyGear", l("gear"));
      const credits = c("credits");
      creditFields(fields, "orderedCrew", "orderedCrewIDs", credits);
      const photographer = credits.find((x) => /photograph/i.test(x.role));
      if (photographer) fields.photographyArtist = s(photographer.name);
      put("photographyImages", many(input, "photographyImages"));
      put("photographyThumbnail", one(input, "photographyThumbnail"));
      return { fields, required: ["photographyTitle", "photographyImages", "isApproved", "submittedBy", "userID"] };
    }
    case "design": {
      if (!many(input, "designImages") && !one(input, "designVideo")) return { fields, required: [], missing: "images or a video" };
      fields.designTitle = s(title);
      // Design records name their dates designCreatedDate (DesignSubmission schema).
      fields.designCreatedDate = time(Date.now());
      text("designDescription", t("description"));
      text("designCategory", t("category", 40));
      text("designReleaseYear", t("releaseYear", 4));
      creditFields(fields, "orderedCrew", "orderedCrewIDs", c("credits"));
      put("designImages", many(input, "designImages"));
      put("designVideo", one(input, "designVideo"));
      const duration = n("videoDuration");
      if (duration) fields.designVideoDuration = double(duration);
      put("designThumbnail", one(input, "designThumbnail"));
      return { fields, required: ["designTitle", "isApproved", "submittedBy", "userID"] };
    }
    case "project": {
      fields.projectTitle = s(title);
      fields.createdDate = time(Date.now());
      text("projectDescription", t("logline", 500));
      const category = t("category", 40);
      text("projectType", category);
      text("writers", t("writers", 300));
      const pages = n("scriptPageCount");
      if (pages) fields.scriptPageCount = int(pages);
      const start = t("shootStart", 10);
      const end = t("shootEnd", 10);
      const shootText = [dayText(start), dayText(end)].filter(Boolean).join(" - ");
      text("projectShootDatesText", shootText);
      const startAt = n("shootStartAt");
      if (startAt) fields.projectShootStart = time(startAt);
      text("projectReleaseDateText", dayText(t("release", 10)));
      const releaseAt = n("releaseAt");
      if (releaseAt) fields.projectExpectedReleaseDate = time(releaseAt);
      strings("projectCastNeeded", l("castNeeded"));
      strings("projectCrewNeeded", l("crewNeeded"));
      creditFields(fields, "projectCastAssembled", "projectCastAssembledIDs", l("castAssembled").map((name) => ({ role: "Actor", name })));
      creditFields(fields, "projectCrewAssembled", "projectCrewAssembledIDs", c("crewAssembled"));
      strings("projectGenres", l("genres"));
      put("projectPoster", one(input, "projectPoster"));
      put("projectSlides", many(input, "projectSlides"));
      return { fields, required: ["projectTitle", "isApproved", "submittedBy", "userID"] };
    }
    case "event": {
      fields.eventTitle = s(title);
      fields.createdDate = time(Date.now());
      text("eventDescription", t("description"));
      text("eventHost", t("host", 200));
      text("eventCategory", t("category", 40));
      const start = n("startAt");
      const end = n("endAt");
      if (start) fields.eventStartTime = time(start);
      if (end) fields.eventEndTime = time(end);
      text("eventLocationText", t("location", 300));
      text("eventTicketsURL", link(t("ticketsURL", 500)));
      text("eventExpectations", t("expectations"));
      text("eventApplicationURL", link(t("applicationURL", 500)));
      // The app's lineupEntries: split on commas and new lines.
      strings("eventLineup", t("lineup").split(/[,\n]/).map((x) => x.trim()).filter(Boolean));
      // "<start>|<end>" in ISO 8601 without fractional seconds, like EventShowing.wireEntries.
      const iso = (ms: number) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
      const showings = l("showings")
        .map((entry) => entry.split("|").map(Number))
        .filter((p) => p.length === 2 && p.every((x) => Number.isFinite(x) && x > 0))
        .sort((a, b) => a[0] - b[0]);
      strings("eventShowtimes", showings.map(([a, b]) => `${iso(a)}|${iso(b)}`));
      put("eventFlyer", one(input, "eventFlyer"));
      return { fields, required: ["eventTitle", "isApproved", "submittedBy", "userID"] };
    }
  }
}

export async function publishPost(input: PostInput): Promise<PublishResult> {
  if (!input || !isShareType(input.type)) return { ok: false, message: "Unknown post type." };
  const who = await poster();
  if (!who) return { ok: false, message: NOT_LINKED };

  // The record name must be one startPost issued to this same account.
  const recordName = typeof input.recordName === "string" ? input.recordName : "";
  const expected = Buffer.from(tokenFor(recordName, who.userRecordName));
  const presented = Buffer.from(typeof input.token === "string" ? input.token : "");
  if (!/^[0-9A-F-]{36}$/.test(recordName) || expected.length !== presented.length || !timingSafeEqual(expected, presented)) {
    return { ok: false, message: "This upload expired. Press Post again." };
  }

  if (!clean(input.text?.title)) return { ok: false, message: "Add a title." };
  const submittedBy = who.account.name || "Anonymous";
  const { fields, required, missing } = build(input, submittedBy);
  if (missing) return { ok: false, message: `Add ${missing}.` };

  fields.userID = s(who.userRecordName);
  // The school the post belongs to (SchoolScope.stamp in the app). The sweep removes
  // posts without one, and every school's feed filters on it.
  const school = who.session.schoolID;
  if (school && school !== "dev") fields.schoolID = s(school);

  try {
    const dropped = await createRecord(RECORD_TYPES[input.type], recordName, fields, required);

    let note: string | undefined;
    const script = one(input, "scriptFile");
    if (input.type === "project" && script) {
      // Scripts also go in the app's Scripts collection (ScriptsCollectionView.submit),
      // where the file itself lives.
      try {
        const genres = cleanList(input.lists?.genres);
        const authors = clean(input.text.writers, 300).split(",").map((a) => a.trim()).filter(Boolean);
        await createRecord(
          "Script",
          `Script_${recordName}`,
          {
            title: s(clean(input.text.title, 200)),
            logline: s(clean(input.text.logline, 500)),
            ...(genres.length ? { genres: list(genres) } : {}),
            authors: list(authors.length ? authors : [submittedBy]),
            pageCount: int(finite(input.numbers?.scriptPageCount) ?? 0),
            projectStatus: s(""),
            shootDates: s(""),
            submittedBy: s(submittedBy),
            submittedByUserID: s(who.userRecordName),
            uploadDate: time(Date.now()),
            scriptFileExt: s(clean(input.text.scriptExt, 10) || "pdf"),
            scriptFile: script,
          },
          ["title", "scriptFile"],
        );
      } catch (error) {
        console.error("[share] script record:", error);
        note = "Posted, but the script file couldn't be added to the Scripts collection.";
      }
    }
    // Fields Production doesn't have yet were logged by createRecord; add them in
    // CloudKit Dashboard (as for the app's schema-gap banner) to keep them next time.
    if (dropped.length) console.warn(`[share] ${RECORD_TYPES[input.type]} posted without: ${dropped.join(", ")}`);

    updateTag(POSTS_TAG);
    updateTag(accountTag(who.userRecordName));
    const href = input.type === "project" || input.type === "event" ? `/discover/${recordName}` : `/post/${recordName}`;
    return { ok: true, href, note };
  } catch (error) {
    console.error("[share] publishPost:", error);
    const message = error instanceof Error ? error.message : String(error);
    if (/already exists|CONFLICT/i.test(message)) return { ok: false, message: "This post was already published." };
    return { ok: false, message: "CloudKit didn't accept the post. Try again in a moment." };
  }
}
