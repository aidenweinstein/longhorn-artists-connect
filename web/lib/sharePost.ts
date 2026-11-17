// What the Share forms send to the server, and which file fields each post type has.
// Shared by the browser (components/share) and the server actions (app/(app)/share).

export type ShareTypeID = "film" | "music" | "performance" | "photography" | "design" | "project" | "event";

/** The app's CloudKit record type for each Share type (the app calls Performance a Reel). */
export const RECORD_TYPES: Record<ShareTypeID, string> = {
  film: "FilmSubmission",
  music: "MusicSubmission",
  performance: "ReelSubmission",
  photography: "PhotographySubmission",
  design: "DesignSubmission",
  project: "ProjectSubmission",
  event: "EventSubmission",
};

/** Asset fields per type: "one" is a single file, "many" an ordered list. */
export const ASSET_FIELDS: Record<ShareTypeID, Record<string, "one" | "many">> = {
  film: { filmVideo: "one", filmThumbnail: "one", filmTrailer: "one", filmBTS: "many", filmStills: "many" },
  music: { musicAudio: "one", musicTracks: "many", musicCover: "one", musicVideo: "one" },
  // reelVideos: a showcase's videos after the first (the first stays in reelVideo, which the app plays).
  performance: { reelVideo: "one", reelVideos: "many", reelThumbnail: "one", reelStills: "many" },
  photography: { photographyImages: "many", photographyThumbnail: "one" },
  design: { designImages: "many", designThumbnail: "one", designVideo: "one" },
  // scriptFile goes on the app's separate Script record (the Scripts collection).
  project: { projectPoster: "one", projectSlides: "many", scriptFile: "one" },
  event: { eventFlyer: "one" },
};

/** The asset field holding each kind of post's feed picture; its pixel size is saved as thumbWidth / thumbHeight. */
export const THUMBNAIL_FIELD: Partial<Record<ShareTypeID, string>> = {
  film: "filmThumbnail",
  music: "musicCover",
  performance: "reelThumbnail",
  photography: "photographyThumbnail",
  design: "designThumbnail",
};

export const MAX_FILES_PER_FIELD = 40;

/**
 * CloudKit Web Services takes files up to 50 MB. Anything bigger in these fields goes to
 * Cloudflare R2 instead (lib/r2.ts), and the record gets a link in `<field>URL` (one file)
 * or `<field>URLs` (a list), which the website and the app play from.
 */
export const LARGE_FILE_FIELDS: ReadonlySet<string> = new Set([
  "filmVideo", "filmTrailer", "musicAudio", "musicTracks", "musicVideo", "reelVideo", "reelVideos", "designVideo",
]);
/** Files from this size up go to R2. A margin under CloudKit's 50 MB. */
export const CLOUDKIT_MAX_BYTES = 45 * 1024 * 1024;
/** The largest file the website takes. */
export const MAX_LARGE_FILE_BYTES = 10 * 1024 * 1024 * 1024;
/** Per post: at most this many big files, adding up to at most this much. */
export const MAX_LARGE_FILES_PER_POST = 5;
export const MAX_LARGE_BYTES_PER_POST = 20 * 1024 * 1024 * 1024;
/** Per account: big files started in any 24 hours, finished or not, add up to at most this. */
export const DAILY_LARGE_BYTES_PER_ACCOUNT = 30 * 1024 * 1024 * 1024;
/**
 * R2 parts: 16 MB each, sent several at a time, so even a 60 MB file goes up over a few
 * connections at once, and a dropped part costs little to resend. (A 10 GB film is 640 parts.)
 */
export const LARGE_PART_BYTES = 16 * 1024 * 1024;

/** The record field holding the R2 link(s) for an asset field. */
export const urlFieldFor = (field: string, kind: "one" | "many") => (kind === "one" ? `${field}URL` : `${field}URLs`);

/** What the browser says about each big file before uploading it. */
export type LargeFileSpec = { size: number; contentType: string; ext: string };
/** Where one big file goes: its storage key, the multipart upload, and one URL per part. */
export type LargeUploadSlot = { key: string; uploadID: string; partSize: number; partURLs: string[] };
/** A finished upload: the ETag R2 answered for each part, in order. */
export type LargeUploadDone = { key: string; uploadID: string; etags: string[] };

/** CloudKit's upload receipt for one file (the `singleFile` it answers an upload with). */
export type AssetReceipt = Record<string, unknown>;

/** `profileID` is set when the name was picked from the Nexus members suggested while typing. */
export type CreditInput = { role: string; name: string; profileID?: string };

/** A Nexus member suggested while typing a name (GET /api/people). */
export type PersonMatch = { id: string; name: string; imageUrl?: string; subtitle?: string };

export type PostInput = {
  type: ShareTypeID;
  recordName: string;
  token: string;
  text: Record<string, string>;
  lists: Record<string, string[]>;
  credits: Record<string, CreditInput[]>;
  numbers: Record<string, number>;
  flags: Record<string, boolean>;
  /** CloudKit receipts, filled in by the server once small files reach CloudKit. */
  assets: Record<string, AssetReceipt[]>;
  /** Small files uploaded to R2, on their way to CloudKit, by asset field. */
  small?: Record<string, LargeUploadDone[]>;
  /** Big files uploaded to R2 to stay there, by asset field. */
  large?: Record<string, LargeUploadDone[]>;
};

export type StartResult =
  | { ok: true; recordName: string; token: string; small: Record<string, LargeUploadSlot[]>; large: Record<string, LargeUploadSlot[]> }
  | { ok: false; message: string };

export type PublishResult = { ok: true; href: string; note?: string } | { ok: false; message: string };
