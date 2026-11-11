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
  performance: { reelVideo: "one", reelThumbnail: "one", reelStills: "many" },
  photography: { photographyImages: "many", photographyThumbnail: "one" },
  design: { designImages: "many", designThumbnail: "one", designVideo: "one" },
  // scriptFile goes on the app's separate Script record (the Scripts collection).
  project: { projectPoster: "one", projectSlides: "many", scriptFile: "one" },
  event: { eventFlyer: "one" },
};

export const MAX_FILES_PER_FIELD = 40;

/** CloudKit's upload receipt for one file (the `singleFile` it answers an upload with). */
export type AssetReceipt = Record<string, unknown>;

export type CreditInput = { role: string; name: string };

export type PostInput = {
  type: ShareTypeID;
  recordName: string;
  token: string;
  text: Record<string, string>;
  lists: Record<string, string[]>;
  credits: Record<string, CreditInput[]>;
  numbers: Record<string, number>;
  flags: Record<string, boolean>;
  assets: Record<string, AssetReceipt[]>;
};

export type StartResult =
  | { ok: true; recordName: string; token: string; urls: Record<string, string[]> }
  | { ok: false; message: string };

export type PublishResult = { ok: true; href: string; note?: string } | { ok: false; message: string };
