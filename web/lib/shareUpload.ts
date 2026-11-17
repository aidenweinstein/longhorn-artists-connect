import { publishPost, startPost } from "@/app/(app)/share/actions";
import type { LargeFileSpec, LargeUploadDone, LargeUploadSlot, PostInput, PublishResult, ShareTypeID } from "./sharePost";
import {
  CLOUDKIT_MAX_BYTES,
  LARGE_FILE_FIELDS,
  MAX_LARGE_BYTES_PER_POST,
  MAX_LARGE_FILES_PER_POST,
  MAX_LARGE_FILE_BYTES,
  THUMBNAIL_FIELD,
} from "./sharePost";
import type { VideoCrop } from "./videoCrop";

/**
 * What a Share form hands over when Post is pressed: its values plus the files for
 * each CloudKit asset field. Images are shrunk the way the app's
 * downscaledImageForUpload does; videos and audio go up untouched (full quality).
 */
export type PostDraft = Omit<PostInput, "recordName" | "token" | "assets" | "large"> & {
  files: Record<string, FileSpec[]>;
};

export type FileSpec = { file: File; image?: { maxDimension: number } };

export type Progress = { stage: "preparing" | "uploading" | "saving"; fraction: number };

export const image = (file: File, maxDimension = 2000): FileSpec => ({ file, image: { maxDimension } });
export const raw = (file: File): FileSpec => ({ file });

/** The file's extension, lowercased, for the app's musicAudioExt / scriptFileExt. */
export function extension(file: File, fallback: string): string {
  const m = /\.([a-z0-9]{1,8})$/i.exec(file.name);
  return m ? m[1].toLowerCase() : fallback;
}

/** Re-encodes an image as a JPEG no larger than maxDimension. Unreadable formats go up as they are. */
async function shrinkImage(file: File, maxDimension: number): Promise<Blob> {
  try {
    const bitmap = await createImageBitmap(file);
    const scale = Math.min(1, maxDimension / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(bitmap.width * scale));
    canvas.height = Math.max(1, Math.round(bitmap.height * scale));
    canvas.getContext("2d")!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    bitmap.close();
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.85));
    return blob ?? file;
  } catch {
    return file;
  }
}

function withMedia<T>(file: File, kind: "video" | "audio", read: (el: HTMLVideoElement | HTMLAudioElement) => Promise<T>): Promise<T | undefined> {
  return new Promise((resolve) => {
    const url = URL.createObjectURL(file);
    const el = document.createElement(kind);
    el.preload = "auto";
    el.muted = true;
    const done = (value: T | undefined) => {
      URL.revokeObjectURL(url);
      el.removeAttribute("src");
      resolve(value);
    };
    const timer = setTimeout(() => done(undefined), 15000);
    el.onerror = () => {
      clearTimeout(timer);
      done(undefined);
    };
    el.onloadedmetadata = () => {
      read(el).then(
        (v) => (clearTimeout(timer), done(v)),
        () => (clearTimeout(timer), done(undefined)),
      );
    };
    el.src = url;
  });
}

/** Length in seconds, saved so the duration badge shows before anything plays. */
export function mediaDuration(file: File): Promise<number | undefined> {
  const kind = file.type.startsWith("audio/") ? "audio" : "video";
  return withMedia(file, kind, async (el) => (Number.isFinite(el.duration) && el.duration > 0 ? el.duration : undefined));
}

/**
 * A frame near the start of a video as a File, standing in for a thumbnail the way the
 * app's first-frame poster does. With a playback crop, the frame is cropped to match,
 * so the feed card has the same shape the player will.
 */
export function videoFrame(file: File, crop?: VideoCrop | null): Promise<File | undefined> {
  return withMedia(file, "video", (el) => {
    const video = el as HTMLVideoElement;
    return new Promise<File | undefined>((resolve) => {
      video.onseeked = () => {
        const vw = video.videoWidth;
        const vh = video.videoHeight;
        if (!vw || !vh) return resolve(undefined);
        const c = crop ?? { x: 0, y: 0, w: 1, h: 1 };
        const sx = Math.round(c.x * vw);
        const sy = Math.round(c.y * vh);
        const sw = Math.max(1, Math.round(c.w * vw));
        const sh = Math.max(1, Math.round(c.h * vh));
        const canvas = document.createElement("canvas");
        canvas.width = sw;
        canvas.height = sh;
        canvas.getContext("2d")!.drawImage(video, sx, sy, sw, sh, 0, 0, sw, sh);
        canvas.toBlob((b) => resolve(b ? new File([b], "thumbnail.jpg", { type: "image/jpeg" }) : undefined), "image/jpeg", 0.85);
      };
      video.currentTime = Math.min(1, (video.duration || 2) / 2);
    });
  });
}

/** Rough page count of a PDF script (the app shows it on the card). 0 when unknown. */
export async function pdfPageCount(file: File): Promise<number> {
  if (!/pdf$/i.test(file.type) && !/\.pdf$/i.test(file.name)) return 0;
  try {
    const text = new TextDecoder("latin1").decode(await file.arrayBuffer());
    return (text.match(/\/Type\s*\/Page(?![s\w])/g) ?? []).length;
  } catch {
    return 0;
  }
}

/**
 * Sends one part of a big file to the R2 URL startPost signed for it, and answers the
 * part's ETag (R2 needs them all to put the file together). A dropped part is resent
 * a few times before giving up, so one hiccup doesn't cost a 10 GB upload.
 */
async function uploadPart(url: string, body: Blob, onProgress: (sent: number) => void): Promise<string> {
  let lastError: Error = new Error("Upload failed.");
  for (let attempt = 0; attempt < 4; attempt++) {
    if (attempt) await new Promise((r) => setTimeout(r, 1000 * 2 ** attempt));
    try {
      return await new Promise<string>((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        xhr.open("PUT", url);
        xhr.upload.onprogress = (e) => onProgress(e.loaded);
        xhr.onload = () => {
          const etag = xhr.getResponseHeader("ETag");
          if (xhr.status >= 200 && xhr.status < 300 && etag) {
            onProgress(body.size);
            return resolve(etag);
          }
          // A success without an ETag means the bucket's CORS rule doesn't expose it.
          reject(new Error(xhr.status >= 200 && xhr.status < 300 ? "Upload failed (no ETag)." : `Upload failed (${xhr.status}).`));
        };
        xhr.onerror = () => reject(new Error("Upload failed. Check your connection and try again."));
        xhr.send(body);
      });
    } catch (error) {
      onProgress(0);
      lastError = error instanceof Error ? error : lastError;
    }
  }
  throw lastError;
}

/** Uploads one big file to R2, four parts at a time. */
async function uploadLarge(slot: LargeUploadSlot, file: Blob, onProgress: (sent: number) => void): Promise<LargeUploadDone> {
  const etags: string[] = new Array(slot.partURLs.length);
  const sentByPart = new Array<number>(slot.partURLs.length).fill(0);
  const report = () => onProgress(sentByPart.reduce((a, b) => a + b, 0));
  let next = 0;
  const worker = async () => {
    while (next < slot.partURLs.length) {
      const i = next++;
      const part = file.slice(i * slot.partSize, Math.min(file.size, (i + 1) * slot.partSize));
      etags[i] = await uploadPart(slot.partURLs[i], part, (n) => {
        sentByPart[i] = n;
        report();
      });
    }
  };
  await Promise.all(Array.from({ length: Math.min(4, slot.partURLs.length) }, worker));
  return { key: slot.key, uploadID: slot.uploadID, etags };
}

/** "mov" for clip.MOV, from the name, else the file type. */
function fileExt(blob: Blob): string {
  const name = blob instanceof File ? blob.name : "";
  const m = /\.([a-z0-9]{1,8})$/i.exec(name);
  if (m) return m[1].toLowerCase();
  const sub = blob.type.split("/")[1] ?? "";
  return /^[a-z0-9]{1,8}$/i.test(sub) ? (sub === "quicktime" ? "mov" : sub.toLowerCase()) : "bin";
}

const mb = (bytes: number) => `${Math.round(bytes / (1024 * 1024))} MB`;

/** The asset field that holds each kind of post's feed picture. */
const THUMBNAIL_FIELDS = new Set(Object.values(THUMBNAIL_FIELD));

/** Width and height in pixels as the picture is displayed, or undefined for an unreadable file. */
async function imageSize(blob: Blob | undefined): Promise<{ width: number; height: number } | undefined> {
  if (!blob) return undefined;
  try {
    const bitmap = await createImageBitmap(blob);
    const size = { width: bitmap.width, height: bitmap.height };
    bitmap.close();
    return size.width > 0 && size.height > 0 ? size : undefined;
  } catch {
    return undefined;
  }
}

/** Runs the whole post: prepare files, get upload slots, upload, then save the record. */
export async function publish(
  type: ShareTypeID,
  draft: PostDraft,
  onProgress: (p: Progress) => void,
  /** Editing: the post being changed. Files left out stay as they are. */
  editPostID?: string,
): Promise<PublishResult> {
  onProgress({ stage: "preparing", fraction: 0 });
  const prepared: [string, Blob[]][] = [];
  for (const [field, specs] of Object.entries(draft.files)) {
    if (!specs.length) continue;
    const blobs = await Promise.all(specs.map((s) => (s.image ? shrinkImage(s.file, s.image.maxDimension) : Promise.resolve(s.file as Blob))));
    prepared.push([field, blobs]);
  }

  // The thumbnail's pixel size goes up with the post, so the feed can lay it out
  // without measuring the picture first.
  const thumbSize = await imageSize(prepared.find(([field]) => THUMBNAIL_FIELDS.has(field))?.[1][0]);

  // Files over CloudKit's limit go to R2 (a whole field at a time, so a list keeps its order).
  // Other fields can't take a file that big.
  const small: [string, Blob[]][] = [];
  const big: [string, Blob[]][] = [];
  for (const [field, blobs] of prepared) {
    const largest = Math.max(...blobs.map((b) => b.size));
    if (largest > MAX_LARGE_FILE_BYTES) return { ok: false, message: "Files can be up to 10 GB. Try a smaller export." };
    if (largest < CLOUDKIT_MAX_BYTES) small.push([field, blobs]);
    else if (LARGE_FILE_FIELDS.has(field)) big.push([field, blobs]);
    else return { ok: false, message: `One of your files is ${mb(largest)}. Pictures and documents need to be under ${mb(CLOUDKIT_MAX_BYTES)}.` };
  }

  // The same per-post limits the server enforces, said before anything uploads.
  const bigBlobs = big.flatMap(([, blobs]) => blobs);
  if (bigBlobs.length > MAX_LARGE_FILES_PER_POST) {
    return { ok: false, message: `A post can have up to ${MAX_LARGE_FILES_PER_POST} files over ${mb(CLOUDKIT_MAX_BYTES)}.` };
  }
  const bigTotal = bigBlobs.reduce((sum, b) => sum + b.size, 0);
  if (bigTotal > MAX_LARGE_BYTES_PER_POST) {
    return { ok: false, message: `Files over ${mb(CLOUDKIT_MAX_BYTES)} can add up to ${Math.round(MAX_LARGE_BYTES_PER_POST / 1024 ** 3)} GB per post.` };
  }

  const specs = (list: [string, Blob[]][]): Record<string, LargeFileSpec[]> =>
    Object.fromEntries(list.map(([field, blobs]) => [field, blobs.map((b) => ({ size: b.size, contentType: b.type || "application/octet-stream", ext: fileExt(b) }))]));
  const start = await startPost(type, specs(small), specs(big), editPostID);
  if (!start.ok) return start;

  const total = prepared.reduce((sum, [, blobs]) => sum + blobs.reduce((s, b) => s + b.size, 0), 0) || 1;
  const sent = new Map<string, number>();
  const report = () => onProgress({ stage: "uploading", fraction: [...sent.values()].reduce((a, b) => a + b, 0) / total });
  report();

  // Every file goes to R2 (browsers can't upload to CloudKit; the server moves the small
  // ones on to CloudKit when the post is published). Small files a few at a time, then big
  // ones one by one, each in parts.
  const done: { small: Record<string, LargeUploadDone[]>; large: Record<string, LargeUploadDone[]> } = { small: {}, large: {} };
  try {
    for (const [which, list, parallel] of [["small", small, 3], ["large", big, 1]] as const) {
      for (const [field, blobs] of list) {
        const slots = start[which][field] ?? [];
        const results: LargeUploadDone[] = new Array(blobs.length);
        let next = 0;
        const worker = async () => {
          while (next < blobs.length) {
            const i = next++;
            if (!slots[i]) throw new Error("Missing upload slot.");
            results[i] = await uploadLarge(slots[i], blobs[i], (n) => {
              sent.set(`${field}:${i}`, n);
              report();
            });
          }
        };
        await Promise.all(Array.from({ length: Math.min(parallel, blobs.length) }, worker));
        done[which][field] = results;
      }
    }
  } catch (error) {
    return { ok: false, message: error instanceof Error ? error.message : "Upload failed." };
  }

  onProgress({ stage: "saving", fraction: 1 });
  const { files: _files, ...rest } = draft;
  void _files;
  const numbers = thumbSize ? { ...rest.numbers, thumbWidth: thumbSize.width, thumbHeight: thumbSize.height } : rest.numbers;
  return publishPost({ ...rest, numbers, type, recordName: start.recordName, token: start.token, assets: {}, small: done.small, large: done.large }, editPostID);
}
