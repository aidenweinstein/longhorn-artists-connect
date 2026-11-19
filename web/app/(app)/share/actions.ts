"use server";

import { createHash, randomUUID, timingSafeEqual } from "node:crypto";
import { updateTag } from "next/cache";
import { currentAccount } from "@/lib/account";
import { createRecord, isCloudKitConfigured, queryAll, list as readList, str as readStr, updateRecord, uploadAsset, type CKField, type CKRecord } from "@/lib/cloudkit/client";
import { ownedPost, recordHasFile } from "@/lib/editPost";
import { POSTS_TAG, accountTag, getAllPosts, profileDirectory } from "@/lib/cloudkit/content";
import { isAdmin } from "@/lib/featured";
import {
  abortMultipartUpload,
  completeMultipartUpload,
  createMultipartUpload,
  deleteObject,
  getObject,
  isR2Configured,
  keyFromPublicURL,
  listObjects,
  listUnfinishedUploads,
  objectSize,
  partUploadURLs,
  publicURLFor,
} from "@/lib/r2";
import { signValue } from "@/lib/session";
import { encodeCrop, parseCrop } from "@/lib/videoCrop";
import {
  ASSET_FIELDS,
  CLOUDKIT_MAX_BYTES,
  DAILY_LARGE_BYTES_PER_ACCOUNT,
  LARGE_FILE_FIELDS,
  LARGE_PART_BYTES,
  MAX_FILES_PER_FIELD,
  MAX_LARGE_BYTES_PER_POST,
  MAX_LARGE_FILES_PER_POST,
  MAX_LARGE_FILE_BYTES,
  RECORD_TYPES,
  type AssetReceipt,
  type CreditInput,
  type LargeFileSpec,
  type LargeUploadDone,
  type LargeUploadSlot,
  type PostInput,
  type PublishResult,
  type ShareTypeID,
  type StartResult,
  THUMBNAIL_FIELD,
  urlFieldFor,
} from "@/lib/sharePost";

/**
 * Posting from the website. Two steps, so files never pass through this server
 * (Vercel caps a request at 4.5 MB, and films upload at full original quality):
 *
 * 1. startPost hands the browser CloudKit upload URLs for a new record name, plus
 *    Cloudflare R2 part URLs for files too big for CloudKit (over 45 MB: films and
 *    other videos, up to 10 GB; see lib/r2.ts).
 * 2. The browser sends each file straight to Apple or R2, then publishPost finishes
 *    the R2 uploads and saves the record with the receipts and R2 links, written the
 *    way the app's MediaModels write it: auto-approved, owned by the signed-in app
 *    account, stamped with its school.
 */

const NOT_LINKED = "To post, finish creating your Nexus account (Sign up), or sign in with an email that has one.";

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

/** R2 part URLs stay usable for a day, long enough for a 10 GB film on a slow connection. */
const PART_URL_SECONDS = 24 * 60 * 60;

/**
 * Big files are stored as posts/<account>/<record>/<field>-<n>-<bytes>.<ext>: by account,
 * so one listing finds everything an account uploaded (for the daily limit), and with the
 * declared size, so an unfinished upload still counts and a finished one can be checked.
 */
const accountPrefix = (userRecordName: string) =>
  `posts/${/^[\w-]{1,100}$/.test(userRecordName) ? userRecordName : createHash("sha256").update(userRecordName).digest("hex").slice(0, 40)}/`;
const keyPrefix = (userRecordName: string, recordName: string, field: string, staging = false) =>
  `${accountPrefix(userRecordName)}${recordName}/${staging ? "staging/" : ""}${field}-`;
/** Files uploaded early, while the form was still being filled in, before anyone knew their field. */
const earlyPrefix = (userRecordName: string, recordName: string, staging: boolean) =>
  `${accountPrefix(userRecordName)}${recordName}/${staging ? "staging/" : ""}early-`;
const declaredBytes = (key: string) => Number(/-(\d{1,12})\.[a-z0-9]{1,8}$/.exec(key)?.[1] ?? NaN);
const gb = (bytes: number) => `${Math.floor((bytes / 1024 ** 3) * 10) / 10} GB`;

/** Bytes of big files this account started uploading in the last 24 hours, finished or not. */
async function largeBytesToday(userRecordName: string): Promise<number> {
  const prefix = accountPrefix(userRecordName);
  const since = Date.now() - 24 * 60 * 60 * 1000;
  const [stored, unfinished] = await Promise.all([listObjects(prefix), listUnfinishedUploads(prefix)]);
  const done = stored.filter((o) => o.modified >= since).reduce((sum, o) => sum + o.size, 0);
  // An unfinished upload's size isn't known to R2 yet: count what it was declared as.
  const pending = unfinished.filter((u) => u.started >= since).reduce((sum, u) => sum + (declaredBytes(u.key) || MAX_LARGE_FILE_BYTES), 0);
  return done + pending;
}
const safeExt = (ext: unknown) => (typeof ext === "string" && /^[a-z0-9]{1,8}$/i.test(ext) ? ext.toLowerCase() : "bin");
const safeContentType = (t: unknown) =>
  typeof t === "string" && /^[\w.+-]{1,60}\/[\w.+-]{1,60}$/.test(t) ? t : "application/octet-stream";

/** Checks a field's file list from the browser: allowed field, count, sizes. Returns a message when it's refused. */
function checkSpecs(field: string, specs: unknown, kind: "one" | "many", maxBytes: number): LargeFileSpec[] | string {
  if (!Array.isArray(specs)) return [];
  const list = (specs as LargeFileSpec[]).slice(0, kind === "one" ? 1 : MAX_FILES_PER_FIELD);
  for (const spec of list) {
    const size = Number(spec?.size);
    if (!Number.isSafeInteger(size) || size <= 0) return "One of the files is empty.";
    if (size > maxBytes) {
      return maxBytes >= MAX_LARGE_FILE_BYTES
        ? "Files can be up to 10 GB. Try a smaller export."
        : `One of your files is too big. Pictures and documents need to be under ${Math.round(CLOUDKIT_MAX_BYTES / 1024 ** 2)} MB.`;
    }
  }
  return list;
}

/** A multipart upload for one file, with a size-locked URL per part. */
async function slotFor(key: string, spec: LargeFileSpec): Promise<LargeUploadSlot> {
  const size = Number(spec.size);
  const uploadID = await createMultipartUpload(key, safeContentType(spec.contentType));
  // Every part locked to its exact size; the last one takes what's left.
  const count = Math.max(1, Math.ceil(size / LARGE_PART_BYTES));
  const partSizes = Array.from({ length: count }, (_, i) => Math.min(LARGE_PART_BYTES, size - i * LARGE_PART_BYTES));
  return { key, uploadID, partSize: LARGE_PART_BYTES, partURLs: partUploadURLs(key, uploadID, partSizes, PART_URL_SECONDS) };
}

/** A message when this account can't start `bytes` more of uploads today, else null. */
async function dailyRefusal(userRecordName: string, bytes: number): Promise<string | null> {
  try {
    const used = await largeBytesToday(userRecordName);
    if (used + bytes <= DAILY_LARGE_BYTES_PER_ACCOUNT) return null;
    const left = Math.max(0, DAILY_LARGE_BYTES_PER_ACCOUNT - used);
    return `You can upload ${gb(DAILY_LARGE_BYTES_PER_ACCOUNT)} of files a day, and have ${gb(left)} left. Try again in a few hours.`;
  } catch (error) {
    console.error("[share] daily upload check:", error);
    return "Couldn't start the upload. Try again in a moment.";
  }
}

/** Whether `token` is the one issued for this record name and account. */
function validToken(recordName: unknown, token: unknown, userRecordName: string): recordName is string {
  if (typeof recordName !== "string" || !/^[0-9A-F-]{36}$/.test(recordName) || typeof token !== "string") return false;
  const expected = Buffer.from(tokenFor(recordName, userRecordName));
  const presented = Buffer.from(token);
  return expected.length === presented.length && timingSafeEqual(expected, presented);
}

export type EarlyUploadResult =
  | { ok: true; recordName: string; token: string; staging: boolean; slot: LargeUploadSlot }
  | { ok: false; message: string };

/**
 * Starts uploading a video or audio file the moment it's picked, while the rest of the
 * form is filled in, so pressing Post has little or nothing left to send. Under 45 MB it
 * goes to staging (on to CloudKit at publish), else it stays in R2. All of a form's early
 * uploads share one record name, which startPost and publishPost then continue with.
 */
export async function startEarlyUpload(
  spec: LargeFileSpec,
  continueAs?: { recordName: string; token: string },
  editPostID?: string,
): Promise<EarlyUploadResult> {
  if (!isCloudKitConfigured() || !isR2Configured()) return { ok: false, message: "File uploads aren't set up on this server yet." };
  const who = await poster();
  if (!who) return { ok: false, message: NOT_LINKED };
  const size = Number(spec?.size);
  if (!Number.isSafeInteger(size) || size <= 0) return { ok: false, message: "This file is empty." };
  if (size > MAX_LARGE_FILE_BYTES) return { ok: false, message: "Files can be up to 10 GB. Try a smaller export." };

  let recordName = randomUUID().toUpperCase();
  if (editPostID !== undefined) {
    const owned = await ownedPost(String(editPostID), who.userRecordName).catch(() => null);
    if (!owned) return { ok: false, message: "You can only edit posts you made." };
    recordName = owned.record.recordName;
  } else if (continueAs && validToken(continueAs.recordName, continueAs.token, who.userRecordName)) {
    recordName = continueAs.recordName;
  }
  const refused = await dailyRefusal(who.userRecordName, size);
  if (refused) return { ok: false, message: refused };

  const staging = size < CLOUDKIT_MAX_BYTES;
  try {
    const key = `${earlyPrefix(who.userRecordName, recordName, staging)}${randomUUID().slice(0, 8)}-${size}.${safeExt(spec.ext)}`;
    const slot = await slotFor(key, { ...spec, size });
    return { ok: true, recordName, token: tokenFor(recordName, who.userRecordName), staging, slot };
  } catch (error) {
    console.error("[share] startEarlyUpload:", error);
    return { ok: false, message: "Couldn't start the upload. Try again in a moment." };
  }
}

/** Stops an early upload whose file was removed or replaced (so it stops counting toward the daily limit). */
export async function abortEarlyUpload(key: string, uploadID: string): Promise<void> {
  const who = await poster();
  if (!who || typeof key !== "string" || typeof uploadID !== "string" || !uploadID || uploadID.length > 1000) return;
  if (!key.startsWith(accountPrefix(who.userRecordName)) || !/^[\w./-]{1,240}$/.test(key) || !/\/(staging\/)?early-[^/]+$/.test(key)) return;
  await abortMultipartUpload(key, uploadID);
}

/**
 * Sets up a post's uploads. `smallFiles` (under 45 MB) go to R2 to be moved on to CloudKit
 * when the post is published; `largeFiles` (45 MB to 10 GB, video and audio fields only) go
 * to R2 to stay there.
 */
export async function startPost(
  type: ShareTypeID,
  smallFiles: Record<string, LargeFileSpec[]> = {},
  largeFiles: Record<string, LargeFileSpec[]> = {},
  /** Editing: the post being changed (its maker only). New files then replace its old ones. */
  editPostID?: string,
  /** The record name (and its token) startEarlyUpload already gave this form's early uploads. */
  continueAs?: { recordName: string; token: string },
): Promise<StartResult> {
  if (!isShareType(type)) return { ok: false, message: "Unknown post type." };
  if (!isCloudKitConfigured()) return { ok: false, message: "Posting isn't set up on this server yet." };
  const who = await poster();
  if (!who) return { ok: false, message: NOT_LINKED };

  const allowed = ASSET_FIELDS[type];
  let recordName = randomUUID().toUpperCase();
  if (editPostID !== undefined) {
    const owned = await ownedPost(String(editPostID), who.userRecordName).catch(() => null);
    if (!owned || owned.type !== type) return { ok: false, message: "You can only edit posts you made." };
    recordName = owned.record.recordName;
  } else if (continueAs && validToken(continueAs.recordName, continueAs.token, who.userRecordName)) {
    recordName = continueAs.recordName;
  }

  const bigWanted: [string, LargeFileSpec[]][] = [];
  for (const [field, specs] of Object.entries(largeFiles ?? {})) {
    if (!(field in allowed) || !LARGE_FILE_FIELDS.has(field)) continue;
    const list = checkSpecs(field, specs, allowed[field], MAX_LARGE_FILE_BYTES);
    if (typeof list === "string") return { ok: false, message: list };
    if (list.length) bigWanted.push([field, list]);
  }
  const smallWanted: [string, LargeFileSpec[]][] = [];
  for (const [field, specs] of Object.entries(smallFiles ?? {})) {
    if (!(field in allowed) || bigWanted.some(([f]) => f === field)) continue;
    const list = checkSpecs(field, specs, allowed[field], CLOUDKIT_MAX_BYTES);
    if (typeof list === "string") return { ok: false, message: list };
    if (list.length) smallWanted.push([field, list]);
  }
  if ((bigWanted.length || smallWanted.length) && !isR2Configured()) {
    return { ok: false, message: "File uploads aren't set up on this server yet." };
  }

  const bigSpecs = bigWanted.flatMap(([, specs]) => specs);
  const bigTotal = bigSpecs.reduce((sum, spec) => sum + Number(spec.size), 0);
  const allTotal = bigTotal + smallWanted.flatMap(([, specs]) => specs).reduce((sum, spec) => sum + Number(spec.size), 0);
  if (bigSpecs.length > MAX_LARGE_FILES_PER_POST) {
    return { ok: false, message: `A post can have up to ${MAX_LARGE_FILES_PER_POST} files over 45 MB.` };
  }
  if (bigTotal > MAX_LARGE_BYTES_PER_POST) {
    return { ok: false, message: `Files over 45 MB can add up to ${gb(MAX_LARGE_BYTES_PER_POST)} per post. This one has ${gb(bigTotal)}.` };
  }
  if (allTotal > 0) {
    const refused = await dailyRefusal(who.userRecordName, allTotal);
    if (refused) return { ok: false, message: refused };
  }

  try {
    const prefix = `${accountPrefix(who.userRecordName)}${recordName}/`;
    const slots = async (wanted: [string, LargeFileSpec[]][], folder: string) => {
      const out: Record<string, LargeUploadSlot[]> = {};
      for (const [field, specs] of wanted) {
        out[field] = await Promise.all(
          specs.map((spec, n) => slotFor(`${prefix}${folder}${field}-${n}-${randomUUID().slice(0, 8)}-${Number(spec.size)}.${safeExt(spec.ext)}`, spec)),
        );
      }
      return out;
    };
    const [small, large] = await Promise.all([slots(smallWanted, "staging/"), slots(bigWanted, "")]);
    return { ok: true, recordName, token: tokenFor(recordName, who.userRecordName), small, large };
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
    .map((c: Partial<CreditInput>) => ({ role: clean(c?.role, 120), name: clean(c?.name, 120), profileID: profileIDOf(c?.profileID) }))
    .filter((c) => c.name)
    .slice(0, 200);
/** A profile record name ("UserProfile_..."), or nothing. Checked against real profiles before saving. */
const profileIDOf = (v: unknown) => (typeof v === "string" && /^UserProfile_[A-Za-z0-9_.-]{1,120}$/.test(v) ? v : undefined);
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

/**
 * "role: name" entries plus the parallel profile-ID list, as the app stores credits:
 * the ID of the member picked from the suggestions, or "" for a name that was typed.
 */
function creditFields(into: Record<string, CKField>, key: string, idsKey: string, credits: CreditInput[]) {
  if (!credits.length) return;
  into[key] = list(credits.map((c) => `${c.role}: ${c.name}`));
  into[idsKey] = list(credits.map((c) => c.profileID ?? ""));
}

/** Cast with no role typed is saved as "Actor", the role the app gives cast by default. */
const asCast = (credits: CreditInput[]) => credits.map((c) => ({ ...c, role: c.role || "Actor" }));

/** Name by profile ID for every member a credit links to, or an empty map when none do. */
async function linkedMembers(input: PostInput): Promise<Map<string, string>> {
  const linked = Object.values(input.credits ?? {}).some((group) => cleanCredits(group).some((c) => c.profileID));
  if (!linked) return new Map();
  const everyone = await profileDirectory().catch(() => []);
  return new Map(everyone.map((p) => [p.id, p.name]));
}

type Built = { fields: Record<string, CKField>; required: string[]; missing?: string };

function build(
  input: PostInput,
  submittedBy: string,
  members: Map<string, string>,
  playlistIDs: string[] = [],
  large: Record<string, string[]> = {},
  /** Editing an existing post: `kept` names its asset fields that already have files. */
  edit?: { kept: Set<string> },
): Built {
  // A file is there if it went to CloudKit or, for big files, to R2 (or, editing, the post has one).
  const fresh = (field: string) => !!one(input, field) || !!many(input, field) || !!large[field]?.length;
  const has = (field: string) => fresh(field) || !!edit?.kept.has(field);
  const t = (k: string, max?: number) => clean(input.text?.[k], max);
  const l = (k: string) => cleanList(input.lists?.[k]);
  // A linked credit carries the member's own name; an ID that isn't a real profile is dropped.
  const c = (k: string) =>
    cleanCredits(input.credits?.[k]).map((credit) => {
      const name = credit.profileID ? members.get(credit.profileID) : undefined;
      return name ? { ...credit, name } : { ...credit, profileID: undefined };
    });
  const n = (k: string) => finite(input.numbers?.[k]);
  const f = (k: string) => input.flags?.[k] === true;
  const title = t("title", 200);
  const fields: Record<string, CKField> = {};
  const put = (key: string, value: CKField | undefined) => {
    if (value !== undefined) fields[key] = value;
  };
  // Editing, an emptied field is written empty, so what was removed goes away.
  const text = (key: string, value: string) => (value ? put(key, s(value)) : edit && put(key, s("")));
  const strings = (key: string, value: string[]) => (value.length ? put(key, list(value)) : edit && put(key, list([])));
  const credit = (key: string, idsKey: string, credits: CreditInput[]) => {
    if (credits.length || !edit) return creditFields(fields, key, idsKey, credits);
    fields[key] = list([]);
    fields[idsKey] = list([]);
  };
  // The video's playback crop, re-checked and re-written in the app's "x,y,w,h" form.
  const crop = () => encodeCrop(parseCrop(t("videoCrop", 80)));

  fields.isApproved = int(1);
  fields.submittedBy = s(submittedBy);

  // The feed picture's pixel size, measured in the browser: with it the feed needs no
  // measuring of its own. Left off (by createRecord) if Production doesn't have the fields.
  const thumbField = THUMBNAIL_FIELD[input.type];
  const thumbWidth = n("thumbWidth");
  const thumbHeight = n("thumbHeight");
  if (thumbField && one(input, thumbField) && thumbWidth && thumbHeight && thumbWidth > 0 && thumbHeight > 0 && thumbWidth < 100_000 && thumbHeight < 100_000) {
    fields.thumbWidth = int(thumbWidth);
    fields.thumbHeight = int(thumbHeight);
  }

  switch (input.type) {
    case "film": {
      if (!has("filmVideo")) return { fields, required: [], missing: "a video" };
      fields.filmTitle = s(title);
      fields.createdDate = time(Date.now());
      text("filmLogline", t("logline", 500));
      text("filmAgeRating", t("ageRating", 10));
      text("filmStudio", t("studio", 200));
      text("filmReleaseYear", t("releaseYear", 4));
      fields.filmExplicit = int(0);
      fields.filmFestivalBound = int(f("festivalBound") ? 1 : 0);
      strings("filmGenres", l("genres"));
      credit("filmCast", "filmCastIDs", asCast(c("cast")));
      credit("filmCrew", "filmCrewIDs", c("crew"));
      put("filmVideo", one(input, "filmVideo"));
      const duration = n("videoDuration");
      if (duration) fields.filmVideoDuration = double(duration);
      text("filmVideoCrop", crop());
      put("filmThumbnail", one(input, "filmThumbnail"));
      put("filmTrailer", one(input, "filmTrailer"));
      put("filmBTS", many(input, "filmBTS"));
      put("filmStills", many(input, "filmStills"));
      return { fields, required: ["filmTitle", "filmVideo", "isApproved", "submittedBy", "userID"] };
    }
    case "music": {
      if (!has("musicAudio")) return { fields, required: [], missing: "an audio file" };
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
      credit("musicRecording", "musicRecordingIDs", c("recording"));
      credit("musicProduction", "musicProductionIDs", c("production"));
      put("musicAudio", one(input, "musicAudio"));
      // The extension goes with the file: only a new audio file brings one.
      if (fresh("musicAudio")) fields.musicAudioExt = s(t("audioExt", 10) || "m4a");
      const duration = n("audioDuration");
      if (duration) fields.musicAudioDuration = double(duration);
      const tracks = many(input, "musicTracks");
      put("musicTracks", tracks);
      const trackCount = tracks ? (tracks.value as unknown[]).length : (large.musicTracks?.length ?? 0);
      if (trackCount) {
        const exts = l("trackExts");
        fields.musicTrackExts = list(Array.from({ length: trackCount }, (_, i) => exts[i] || "m4a"));
      }
      put("musicCover", one(input, "musicCover"));
      put("musicVideo", one(input, "musicVideo"));
      return { fields, required: ["musicTitle", "musicAudio", "isApproved", "submittedBy", "userID"] };
    }
    case "performance": {
      // A playlist of existing posts (admins) needs no upload of its own, but then it needs a thumbnail.
      if (!has("reelVideo") && !playlistIDs.length) return { fields, required: [], missing: "a video" };
      if (!has("reelVideo") && !one(input, "reelThumbnail")) return { fields, required: [], missing: "a thumbnail" };
      fields.reelTitle = s(title);
      fields.createdDate = time(Date.now());
      text("reelDescription", t("description"));
      text("reelType", t("category", 40));
      text("reelReleaseYear", t("releaseYear", 4));
      credit("orderedCast", "orderedCastIDs", c("cast"));
      strings("featuredWorkManual", l("featured"));
      put("reelVideo", one(input, "reelVideo"));
      // A showcase's other videos, and a title for every video (the first included), in order.
      const moreVideos = many(input, "reelVideos");
      put("reelVideos", moreVideos);
      const moreCount = moreVideos ? (moreVideos.value as unknown[]).length : (large.reelVideos?.length ?? 0);
      if (moreCount) {
        const count = moreCount + 1;
        const titles: unknown[] = Array.isArray(input.lists?.videoTitles) ? input.lists.videoTitles : [];
        fields.reelVideoTitles = list(Array.from({ length: count }, (_, i) => clean(titles[i], 200) || `Video ${i + 1}`));
      }
      const duration = n("videoDuration");
      if (duration) fields.reelVideoDuration = double(duration);
      if (one(input, "reelVideo")) text("reelVideoCrop", crop());
      put("reelThumbnail", one(input, "reelThumbnail"));
      put("reelStills", many(input, "reelStills"));
      if (playlistIDs.length) fields.reelPlaylistPostIDs = list(playlistIDs);
      // The playlist fields are never dropped to rescue a save: a showcase missing its videos isn't the post.
      const playlistFields = ["reelVideo", "reelVideos", "reelVideoTitles", "reelPlaylistPostIDs"].filter((k) => k in fields);
      return { fields, required: ["reelTitle", ...playlistFields, "isApproved", "submittedBy", "userID"] };
    }
    case "photography": {
      if (!many(input, "photographyImages")) return { fields, required: [], missing: "photos" };
      fields.photographyTitle = s(title);
      fields.createdDate = time(Date.now());
      text("photographyDescription", t("description"));
      text("photographyReleaseYear", t("releaseYear", 4));
      strings("photographyGear", l("gear"));
      const credits = c("credits");
      credit("orderedCrew", "orderedCrewIDs", credits);
      const photographer = credits.find((x) => /photograph/i.test(x.role));
      if (photographer) fields.photographyArtist = s(photographer.name);
      put("photographyImages", many(input, "photographyImages"));
      put("photographyThumbnail", one(input, "photographyThumbnail"));
      return { fields, required: ["photographyTitle", "photographyImages", "isApproved", "submittedBy", "userID"] };
    }
    case "design": {
      if (!has("designImages") && !has("designVideo")) return { fields, required: [], missing: "images or a video" };
      fields.designTitle = s(title);
      // Design records name their dates designCreatedDate (DesignSubmission schema).
      fields.designCreatedDate = time(Date.now());
      text("designDescription", t("description"));
      text("designCategory", t("category", 40));
      text("designReleaseYear", t("releaseYear", 4));
      credit("orderedCrew", "orderedCrewIDs", c("credits"));
      put("designImages", many(input, "designImages"));
      put("designVideo", one(input, "designVideo"));
      const duration = n("videoDuration");
      if (duration) fields.designVideoDuration = double(duration);
      if (one(input, "designVideo")) text("designVideoCrop", crop());
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
      credit("projectCastAssembled", "projectCastAssembledIDs", asCast(c("castAssembled")));
      credit("projectCrewAssembled", "projectCrewAssembledIDs", c("crewAssembled"));
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

/**
 * Publishes a post, or with `editPostID` saves changes to one (its maker only): fields
 * are updated in place, files not replaced stay, and the post keeps its date, approval
 * and owner.
 */
export async function publishPost(input: PostInput, editPostID?: string): Promise<PublishResult> {
  if (!input || !isShareType(input.type)) return { ok: false, message: "Unknown post type." };
  const who = await poster();
  if (!who) return { ok: false, message: NOT_LINKED };

  // The record name must be one startPost issued to this same account.
  const recordName = typeof input.recordName === "string" ? input.recordName : "";
  if (!validToken(recordName, input.token, who.userRecordName)) {
    return { ok: false, message: "This upload expired. Press Post again." };
  }
  let editing: CKRecord | null = null;
  if (editPostID !== undefined) {
    const owned = await ownedPost(String(editPostID), who.userRecordName).catch(() => null);
    if (!owned || owned.type !== input.type || owned.record.recordName !== recordName) {
      return { ok: false, message: "You can only edit posts you made." };
    }
    editing = owned.record;
  }

  if (!clean(input.text?.title)) return { ok: false, message: "Add a title." };
  const submittedBy = who.account.name || "Anonymous";
  // Existing posts added to a Performance post (a playlist): admins only, and only real posts with a video.
  let playlistIDs: string[] = [];
  // (Editing keeps a playlist's posts as they are.)
  const wanted = input.type === "performance" && !editing ? cleanList(input.lists?.playlistPostIDs, 40).slice(0, MAX_FILES_PER_FIELD) : [];
  if (wanted.length) {
    if (!isAdmin(who.session)) return { ok: false, message: "Only admins can add existing posts to a playlist." };
    const byID = new Map((await getAllPosts()).posts.map((p) => [p.id.toUpperCase(), p]));
    playlistIDs = [...new Set(wanted.map((id) => id.toUpperCase()))].flatMap((id) => {
      const p = byID.get(id);
      return p?.videoUrl && !p.playlistPostIDs?.length ? [p.id] : [];
    });
    if (!playlistIDs.length) return { ok: false, message: "None of the posts you added could be found. Search for them again." };
  }
  const allowed = ASSET_FIELDS[input.type];
  /** Finishes one R2 upload this post's startPost set up; answers its key, or a message when it can't be used. */
  async function finish(field: string, up: LargeUploadDone, staging: boolean): Promise<{ key: string } | { message: string }> {
    const key = typeof up?.key === "string" ? up.key : "";
    const uploadID = typeof up?.uploadID === "string" ? up.uploadID : "";
    const etags = Array.isArray(up?.etags) ? up.etags : [];
    const declared = declaredBytes(key);
    // Only files set up for this record, by this account.
    const ours = key.startsWith(keyPrefix(who!.userRecordName, recordName, field, staging)) || key.startsWith(earlyPrefix(who!.userRecordName, recordName, staging));
    if (!ours || !(declared > 0) || !/^[\w./-]{1,240}$/.test(key) || !uploadID || uploadID.length > 1000) {
      return { message: "This upload expired. Press Post again." };
    }
    if (etags.length !== Math.max(1, Math.ceil(declared / LARGE_PART_BYTES)) || !etags.every((e) => typeof e === "string" && /^"?[\w-]{1,100}"?$/.test(e))) {
      await abortMultipartUpload(key, uploadID);
      return { message: "A file didn't finish uploading. Press Post again." };
    }
    await completeMultipartUpload(key, uploadID, etags.map((etag: string, i: number) => ({ partNumber: i + 1, etag })));
    const size = await objectSize(key);
    // The finished file must be exactly the size declared when the upload started.
    if (size === null || size !== declared || size > (staging ? CLOUDKIT_MAX_BYTES : MAX_LARGE_FILE_BYTES)) {
      await deleteObject(key);
      return { message: "A file didn't upload correctly. Press Post again." };
    }
    return { key };
  }

  // Small files: from R2 on to CloudKit (browsers can't upload to CloudKit themselves).
  const assets: Record<string, AssetReceipt[]> = {};
  const staged: string[] = [];
  try {
    for (const [field, uploads] of Object.entries(input.small ?? {})) {
      if (!(field in allowed) || !Array.isArray(uploads) || !uploads.length) continue;
      const target =
        field === "scriptFile" ? { recordType: "Script", recordName: `Script_${recordName}` } : { recordType: RECORD_TYPES[input.type], recordName };
      const list = uploads.slice(0, allowed[field] === "one" ? 1 : MAX_FILES_PER_FIELD);
      const receiptsFor: AssetReceipt[] = new Array(list.length);
      // A few at a time, in order.
      let next = 0;
      let refused: string | null = null;
      const worker = async () => {
        while (next < list.length && !refused) {
          const i = next++;
          const done = await finish(field, list[i], true);
          if ("message" in done) {
            refused = done.message;
            return;
          }
          staged.push(done.key);
          const { bytes, contentType } = await getObject(done.key);
          receiptsFor[i] = (await uploadAsset(target.recordType, target.recordName, field, bytes, contentType)).value as AssetReceipt;
        }
      };
      await Promise.all(Array.from({ length: Math.min(4, list.length) }, worker));
      if (refused) return { ok: false, message: refused };
      assets[field] = receiptsFor;
    }
  } catch (error) {
    console.error("[share] moving files to CloudKit:", error);
    return { ok: false, message: "Couldn't finish uploading your files. Press Post again." };
  } finally {
    // The staged copies are done with either way.
    await Promise.all(staged.map((key) => deleteObject(key)));
  }

  // Big files: finish each R2 upload, and link it from the record.
  const large: Record<string, string[]> = {};
  try {
    for (const [field, uploads] of Object.entries(input.large ?? {})) {
      if (!(field in allowed) || !LARGE_FILE_FIELDS.has(field) || !Array.isArray(uploads) || !uploads.length) continue;
      const urls: string[] = [];
      for (const up of uploads.slice(0, allowed[field] === "one" ? 1 : MAX_FILES_PER_FIELD)) {
        const done = await finish(field, up, false);
        if ("message" in done) return { ok: false, message: done.message };
        urls.push(publicURLFor(done.key));
      }
      if (urls.length) large[field] = urls;
    }
  } catch (error) {
    console.error("[share] finishing large upload:", error);
    return { ok: false, message: "Couldn't finish uploading the video. Press Post again." };
  }

  // The receipts go on the record the way the browser used to send them.
  input = { ...input, assets };
  const kept = editing ? new Set(Object.keys(allowed).filter((f) => recordHasFile(editing!, f))) : undefined;
  const built = build(input, submittedBy, await linkedMembers(input), playlistIDs, large, kept && { kept });
  const { fields, missing } = built;
  if (missing) return { ok: false, message: `Add ${missing}.` };
  // R2 links are never dropped to rescue a save: a post without its video isn't the post.
  const required = [...built.required];
  for (const [field, urls] of Object.entries(large)) {
    const kind = allowed[field];
    const key = urlFieldFor(field, kind);
    fields[key] = kind === "one" ? s(urls[0]) : list(urls);
    required.push(key);
  }

  if (editing) return saveEdit(input, editing, fields, required, { assets, large, allowed, userRecordName: who.userRecordName });

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

    // Refresh the feeds only once CloudKit's queries list the new post, or the refresh
    // would miss it and the feeds would go without it for minutes.
    await waitUntilListed(RECORD_TYPES[input.type], recordName);
    updateTag(POSTS_TAG);
    updateTag(accountTag(who.userRecordName));
    const href = input.type === "project" || input.type === "event" ? `/discover/${recordName}` : `/post/${recordName}`;
    return { ok: true, href, note };
  } catch (error) {
    console.error("[share] publishPost:", error);
    // The post wasn't saved: its big files in R2 would never be used.
    await dropLarge(large);
    const message = error instanceof Error ? error.message : String(error);
    if (/already exists|CONFLICT/i.test(message)) return { ok: false, message: "This post was already published." };
    const linkField = Object.keys(large).map((f) => urlFieldFor(f, allowed[f])).find((k) => message.includes(k));
    if (linkField) {
      const kind = linkField.endsWith("URLs") ? "String List" : "String";
      return { ok: false, message: `Big videos can't be saved yet: add ${linkField} (${kind}) to ${RECORD_TYPES[input.type]} in CloudKit first.` };
    }
    if (/reelVideos|reelVideoTitles|reelPlaylistPostIDs/.test(message)) {
      return { ok: false, message: "Playlists can't be saved yet: add reelVideos (Asset List), reelVideoTitles (String List) and reelPlaylistPostIDs (String List) to ReelSubmission in CloudKit first." };
    }
    return { ok: false, message: "CloudKit didn't accept the post. Try again in a moment." };
  }
}

/** The second half of publishPost when editing: updates the record in place. */
async function saveEdit(
  input: PostInput,
  record: CKRecord,
  fields: Record<string, CKField>,
  required: string[],
  ctx: { assets: Record<string, AssetReceipt[]>; large: Record<string, string[]>; allowed: Record<string, "one" | "many">; userRecordName: string },
): Promise<PublishResult> {
  const recordName = record.recordName;
  const recordType = RECORD_TYPES[input.type];
  // The post keeps its approval, author name and date; it gets an edited date.
  for (const key of ["isApproved", "submittedBy", "createdDate", "designCreatedDate"]) delete fields[key];
  fields[input.type === "design" ? "designLastEditedDate" : "lastEditedDate"] = time(Date.now());

  // A replaced file's old R2 copy is deleted once the save succeeds; a field that now has
  // a CloudKit file drops its old R2 link, which would otherwise still win.
  const stale: string[] = [];
  for (const [field, kind] of Object.entries(ctx.allowed)) {
    if (!ctx.assets[field]?.length && !ctx.large[field]?.length) continue;
    const urlKey = urlFieldFor(field, kind);
    const old = kind === "one" ? [readStr(record, urlKey)].filter(Boolean) : readList(record, urlKey);
    if (!old.length) continue;
    stale.push(...old.flatMap((u) => keyFromPublicURL(u) ?? []));
    if (!ctx.large[field]?.length) fields[urlKey] = kind === "one" ? s("") : list([]);
  }

  try {
    const dropped = await updateRecord(recordType, recordName, fields, required);
    let note: string | undefined;
    const script = one(input, "scriptFile");
    if (input.type === "project" && script) {
      try {
        await updateRecord(
          "Script",
          `Script_${recordName}`,
          { scriptFile: script, scriptFileExt: s(clean(input.text.scriptExt, 10) || "pdf"), title: s(clean(input.text.title, 200)) },
          ["scriptFile"],
        );
      } catch (error) {
        console.error("[share] edit script record:", error);
        note = "Saved, but the script file couldn't be replaced.";
      }
    }
    await Promise.all(stale.map((key) => deleteObject(key)));
    if (dropped.length) console.warn(`[share] ${recordType} edit saved without: ${dropped.join(", ")}`);
    // CloudKit's queries catch up with a change after a moment; refresh the feeds after that.
    await new Promise((r) => setTimeout(r, 2500));
    updateTag(POSTS_TAG);
    updateTag(accountTag(ctx.userRecordName));
    const href = input.type === "project" || input.type === "event" ? `/discover/${recordName}` : `/post/${recordName}`;
    return { ok: true, href, note };
  } catch (error) {
    console.error("[share] saveEdit:", error);
    await dropLarge(ctx.large);
    const message = error instanceof Error ? error.message : String(error);
    const linkField = Object.keys(ctx.large).map((f) => urlFieldFor(f, ctx.allowed[f])).find((k) => message.includes(k));
    if (linkField) {
      const kind = linkField.endsWith("URLs") ? "String List" : "String";
      return { ok: false, message: `Big videos can't be saved yet: add ${linkField} (${kind}) to ${recordType} in CloudKit first.` };
    }
    return { ok: false, message: "CloudKit didn't accept the changes. Try again in a moment." };
  }
}

/** Deletes big files uploaded for a save that failed. */
async function dropLarge(large: Record<string, string[]>): Promise<void> {
  const keys = Object.values(large).flat().flatMap((url) => keyFromPublicURL(url) ?? []);
  await Promise.all(keys.map((key) => deleteObject(key)));
}

/** Waits (up to about 8 seconds) until CloudKit's queries of a record type include a new record. */
async function waitUntilListed(recordType: string, recordName: string): Promise<void> {
  for (let attempt = 0; attempt < 8; attempt++) {
    try {
      const records = await queryAll(recordType, 2000, ["isApproved"]);
      if (records.some((r) => r.recordName === recordName)) return;
    } catch {
      return;
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
}
