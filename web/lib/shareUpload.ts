import { abortEarlyUpload, publishPost, startEarlyUpload, startPost } from "@/app/(app)/share/actions";
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

export type Progress = { stage: "preparing" | "uploading" | "saving"; fraction: number; /** Estimated from recent upload speed. */ secondsLeft?: number };

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
async function uploadPart(url: string, body: Blob, onProgress: (sent: number) => void, signal?: AbortSignal): Promise<string> {
  let lastError: Error = new Error("Upload failed.");
  for (let attempt = 0; attempt < 4; attempt++) {
    if (attempt) await new Promise((r) => setTimeout(r, 1000 * 2 ** attempt));
    if (signal?.aborted) throw new Error("Upload cancelled.");
    try {
      return await new Promise<string>((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        const stop = () => xhr.abort();
        signal?.addEventListener("abort", stop, { once: true });
        xhr.onloadend = () => signal?.removeEventListener("abort", stop);
        xhr.onabort = () => reject(new Error("Upload cancelled."));
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
      if (signal?.aborted) throw lastError;
    }
  }
  throw lastError;
}

/** Uploads one big file to R2, four parts at a time. */
async function uploadLarge(slot: LargeUploadSlot, file: Blob, onProgress: (sent: number) => void, signal?: AbortSignal): Promise<LargeUploadDone> {
  const etags: string[] = new Array(slot.partURLs.length);
  const sentByPart = new Array<number>(slot.partURLs.length).fill(0);
  let last = 0;
  const report = () => {
    const sum = sentByPart.reduce((a, b) => a + b, 0);
    noteSent(sum - last);
    last = sum;
    onProgress(sum);
  };
  let next = 0;
  const worker = async () => {
    while (next < slot.partURLs.length) {
      if (signal?.aborted) throw new Error("Upload cancelled.");
      const i = next++;
      const part = file.slice(i * slot.partSize, Math.min(file.size, (i + 1) * slot.partSize));
      etags[i] = await uploadPart(slot.partURLs[i], part, (n) => {
        sentByPart[i] = n;
        report();
      }, signal);
    }
  };
  await Promise.all(Array.from({ length: Math.min(4, slot.partURLs.length) }, worker));
  return { key: slot.key, uploadID: slot.uploadID, etags };
}

// MARK: - Upload speed, for "about 3 min left"

/** Bytes sent so far (all uploads), sampled over the last 20 seconds. */
const samples: { t: number; total: number }[] = [];
let sentEver = 0;
function noteSent(delta: number) {
  if (!(delta > 0)) return;
  sentEver += delta;
  const t = performance.now();
  samples.push({ t, total: sentEver });
  while (samples.length > 2 && t - samples[0].t > 20000) samples.shift();
}

/** Seconds to send `remaining` bytes at the recent speed, or undefined until there's enough to tell. */
export function secondsLeft(remaining: number): number | undefined {
  if (samples.length < 2 || remaining <= 0) return remaining <= 0 ? 0 : undefined;
  const first = samples[0];
  const span = (performance.now() - first.t) / 1000;
  if (span < 3) return undefined;
  const rate = (sentEver - first.total) / span;
  return rate > 0 ? remaining / rate : undefined;
}

/** "about 3 min left", for the progress bars. */
export function timeLeftLabel(seconds: number | undefined): string {
  if (seconds === undefined) return "";
  if (seconds < 60) return "less than a minute left";
  const min = Math.round(seconds / 60);
  if (min < 90) return `about ${min} min left`;
  return `about ${Math.round((seconds / 3600) * 10) / 10} hours left`;
}

// MARK: - Early uploads

/**
 * Videos and audio start uploading the moment they're picked, while the rest of the form
 * is filled in, so Post has little left to send. All of a form's early uploads share one
 * record name (startEarlyUpload issues it; startPost and publishPost continue with it).
 * Under 45 MB they go to staging (moved on to CloudKit at publish), else they stay in R2,
 * the same split publish makes.
 */
type Early = {
  file: File;
  staging: boolean;
  sent: number;
  failed: boolean;
  slot?: LargeUploadSlot;
  controller: AbortController;
  done: Promise<LargeUploadDone>;
};
type EarlySession = { editPostID: string | null; recordName?: string; token?: string };

let session: EarlySession = { editPostID: null };
const early = new Map<File, Early>();
/** Starts run one at a time, so the first one's record name reaches the rest. */
let startChain: Promise<unknown> = Promise.resolve();
let version = 0;
const listeners = new Set<() => void>();
const emit = () => {
  version++;
  listeners.forEach((l) => l());
};

export const isEarlyKind = (file: File) => /^(video|audio)\//.test(file.type) && file.size > 0;

function cancelEarly(entry: Early) {
  entry.controller.abort();
  early.delete(entry.file);
  if (entry.slot) void abortEarlyUpload(entry.slot.key, entry.slot.uploadID).catch(() => undefined);
}

function resetEarly(editPostID: string | null) {
  for (const entry of [...early.values()]) cancelEarly(entry);
  session = { editPostID };
  emit();
}

function startEarly(file: File) {
  const s = session;
  const controller = new AbortController();
  const entry: Early = { file, staging: file.size < CLOUDKIT_MAX_BYTES, sent: 0, failed: false, controller, done: undefined as unknown as Promise<LargeUploadDone> };
  entry.done = (async () => {
    const begin = startChain.then(async () => {
      if (controller.signal.aborted) throw new Error("Upload cancelled.");
      const continueAs = s.recordName && s.token ? { recordName: s.recordName, token: s.token } : undefined;
      const r = await startEarlyUpload({ size: file.size, contentType: file.type || "application/octet-stream", ext: fileExt(file) }, continueAs, s.editPostID ?? undefined);
      if (r.ok && !s.recordName) {
        s.recordName = r.recordName;
        s.token = r.token;
      }
      return r;
    });
    startChain = begin.catch(() => undefined);
    const r = await begin;
    if (!r.ok) throw new Error(r.message);
    entry.slot = r.slot;
    entry.staging = r.staging;
    if (controller.signal.aborted || r.recordName !== s.recordName) {
      void abortEarlyUpload(r.slot.key, r.slot.uploadID).catch(() => undefined);
      throw new Error("Upload cancelled.");
    }
    return uploadLarge(r.slot, file, (n) => {
      entry.sent = n;
      emit();
    }, controller.signal);
  })();
  entry.done.then(emit, () => {
    entry.failed = true;
    emit();
  });
  early.set(file, entry);
  emit();
}

/**
 * Called with every video and audio file a Share form currently holds: starts the new ones
 * and stops uploading any that were removed or replaced. Calling it with [] stops them all.
 */
export function syncEarlyUploads(files: File[], editPostID: string | null) {
  if (editPostID !== session.editPostID) resetEarly(editPostID);
  const wanted = new Set(files.filter(isEarlyKind));
  for (const entry of [...early.values()]) if (!wanted.has(entry.file)) cancelEarly(entry);
  let changed = false;
  for (const file of wanted) {
    const entry = early.get(file);
    // A failed one is left for Post to upload again.
    if (!entry) {
      startEarly(file);
      changed = true;
    }
  }
  if (changed) emit();
}

export function subscribeEarly(listener: () => void): () => void {
  listeners.add(listener);
  return () => void listeners.delete(listener);
}
export const earlyVersion = () => version;

/** How the early uploads are going, for the note under the form; null when there are none. */
export function earlyStatus(): { sent: number; total: number; done: boolean; failed: boolean; secondsLeft?: number } | null {
  const list = [...early.values()];
  if (!list.length) return null;
  const total = list.reduce((sum, e) => sum + e.file.size, 0);
  const sent = list.reduce((sum, e) => sum + (e.failed ? 0 : e.sent), 0);
  const failed = list.some((e) => e.failed);
  const done = !failed && sent >= total;
  return { sent, total, done, failed, secondsLeft: done ? 0 : secondsLeft(total - sent) };
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

  // Fields whose files all started uploading when they were picked use those uploads.
  const sameSession = session.editPostID === (editPostID ?? null) && !!session.recordName;
  const usable = (blobs: Blob[], staging: boolean) =>
    sameSession &&
    blobs.every((b) => {
      const e = b instanceof File ? early.get(b) : undefined;
      return !!e && !e.failed && e.staging === staging;
    });
  const earlyFields: { which: "small" | "large"; field: string; entries: Early[] }[] = [];
  const fresh = (list: [string, Blob[]][], which: "small" | "large") =>
    list.filter(([field, blobs]) => {
      if (!usable(blobs, which === "small")) return true;
      earlyFields.push({ which, field, entries: blobs.map((b) => early.get(b as File)!) });
      return false;
    });
  const freshSmall = fresh(small, "small");
  const freshBig = fresh(big, "large");
  const usedEarly = earlyFields.flatMap((f) => f.entries);

  const specs = (list: [string, Blob[]][]): Record<string, LargeFileSpec[]> =>
    Object.fromEntries(list.map(([field, blobs]) => [field, blobs.map((b) => ({ size: b.size, contentType: b.type || "application/octet-stream", ext: fileExt(b) }))]));
  const continueAs = session.recordName && session.token && sameSession ? { recordName: session.recordName, token: session.token } : undefined;
  const start = await startPost(type, specs(freshSmall), specs(freshBig), editPostID, continueAs);
  if (!start.ok) return start;
  if (usedEarly.length && start.recordName !== session.recordName) {
    resetEarly(editPostID ?? null);
    return { ok: false, message: "This upload expired. Press Post again." };
  }

  const total = prepared.reduce((sum, [, blobs]) => sum + blobs.reduce((s, b) => s + b.size, 0), 0) || 1;
  const sent = new Map<string, number>();
  const report = () => {
    const sum = [...sent.values()].reduce((a, b) => a + b, 0) + usedEarly.reduce((a, e) => a + e.sent, 0);
    onProgress({ stage: "uploading", fraction: Math.min(1, sum / total), secondsLeft: secondsLeft(total - sum) });
  };
  const stopListening = subscribeEarly(report);
  report();

  // Every file goes to R2 (browsers can't upload to CloudKit; the server moves the small
  // ones on to CloudKit when the post is published). Small files a few at a time, then big
  // ones one by one, each in parts.
  const done: { small: Record<string, LargeUploadDone[]>; large: Record<string, LargeUploadDone[]> } = { small: {}, large: {} };
  const earlyDone = Promise.all(earlyFields.map(async (f) => [f, await Promise.all(f.entries.map((e) => e.done))] as const));
  earlyDone.catch(() => undefined);
  try {
    for (const [which, list, parallel] of [["small", freshSmall, 3], ["large", freshBig, 1]] as const) {
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
    for (const [f, results] of await earlyDone) done[f.which][f.field] = results;
  } catch (error) {
    return { ok: false, message: error instanceof Error ? error.message : "Upload failed." };
  } finally {
    stopListening();
  }

  onProgress({ stage: "saving", fraction: 1 });
  const { files: _files, ...rest } = draft;
  void _files;
  const numbers = thumbSize ? { ...rest.numbers, thumbWidth: thumbSize.width, thumbHeight: thumbSize.height } : rest.numbers;
  try {
    return await publishPost({ ...rest, numbers, type, recordName: start.recordName, token: start.token, assets: {}, small: done.small, large: done.large }, editPostID);
  } finally {
    // publishPost has finished these uploads (or given up on them): a retry starts fresh.
    for (const e of usedEarly) early.delete(e.file);
    resetEarly(editPostID ?? null);
  }
}
