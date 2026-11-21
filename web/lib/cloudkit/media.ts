import type { CKRecord } from "./client";
import { list, str } from "./client";

/** Post fields holding video or audio files, served through /media (app/media/...). */
export const MEDIA_FIELDS = new Set([
  "filmVideo",
  "filmTrailer",
  "musicAudio",
  "musicTracks",
  "musicVideo",
  "reelVideo",
  "reelVideos",
  "designVideo",
]);

/** A stored https link (an R2 upload), or nothing. */
const link = (v: string) => (/^https:\/\//.test(v) ? v : undefined);

const has = (r: CKRecord, key: string) => !!(r.fields[key]?.value as { downloadURL?: string } | undefined)?.downloadURL;

/**
 * A playable address for a video or audio field: the permanent R2 link a big website
 * upload keeps in `<key>URL`, or else this site's /media address for the CloudKit file,
 * which always redirects to a fresh link (CloudKit's own links expire; see the route).
 */
export function mediaURL(r: CKRecord, key: string, filename: string): string | undefined {
  const r2 = link(str(r, `${key}URL`));
  if (r2) return r2;
  return has(r, key) ? `/media/${r.recordName}/${key}/0/${filename}` : undefined;
}

/** Like mediaURL for a list field: the R2 links in `<key>URLs`, or /media addresses for the CloudKit files. */
export function mediaURLs(r: CKRecord, key: string, filename: string | ((index: number) => string)): string[] {
  const links = list(r, `${key}URLs`).flatMap((v) => link(v) ?? []);
  if (links.length) return links;
  const values = (r.fields[key]?.value as { downloadURL?: string }[] | undefined) ?? [];
  return values.flatMap((a, i) =>
    a?.downloadURL ? [`/media/${r.recordName}/${key}/${i}/${typeof filename === "function" ? filename(i) : filename}`] : [],
  );
}
