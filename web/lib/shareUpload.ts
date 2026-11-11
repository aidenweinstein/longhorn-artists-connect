import { publishPost, startPost } from "@/app/(app)/share/actions";
import type { AssetReceipt, PostInput, PublishResult, ShareTypeID } from "./sharePost";

/**
 * What a Share form hands over when Post is pressed: its values plus the files for
 * each CloudKit asset field. Images are shrunk the way the app's
 * downscaledImageForUpload does; videos and audio go up untouched (full quality).
 */
export type PostDraft = Omit<PostInput, "recordName" | "token" | "assets"> & {
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

/** A frame near the start of a video as a File, standing in for a thumbnail the way the app's first-frame poster does. */
export function videoFrame(file: File): Promise<File | undefined> {
  return withMedia(file, "video", (el) => {
    const video = el as HTMLVideoElement;
    return new Promise<File | undefined>((resolve) => {
      video.onseeked = () => {
        const canvas = document.createElement("canvas");
        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;
        if (!canvas.width || !canvas.height) return resolve(undefined);
        canvas.getContext("2d")!.drawImage(video, 0, 0);
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
 * Sends one file to the upload URL CloudKit issued. The body goes without a
 * Content-Type, as a simple cross-origin request (the same direct-to-Apple upload
 * CloudKit JS does); the answer is the receipt to save on the record.
 */
function upload(url: string, body: Blob, onProgress: (sent: number) => void): Promise<AssetReceipt> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("POST", url);
    xhr.upload.onprogress = (e) => onProgress(e.loaded);
    xhr.onload = () => {
      try {
        const json = JSON.parse(xhr.responseText) as { singleFile?: AssetReceipt };
        if (xhr.status >= 200 && xhr.status < 300 && json.singleFile) {
          onProgress(body.size);
          return resolve(json.singleFile);
        }
      } catch {
        /* fall through */
      }
      reject(new Error(`Upload failed (${xhr.status}).`));
    };
    xhr.onerror = () => reject(new Error("Upload failed. Check your connection and try again."));
    xhr.send(new Blob([body]));
  });
}

/** Runs the whole post: prepare files, get upload slots, upload, then save the record. */
export async function publish(type: ShareTypeID, draft: PostDraft, onProgress: (p: Progress) => void): Promise<PublishResult> {
  onProgress({ stage: "preparing", fraction: 0 });
  const prepared: [string, Blob[]][] = [];
  for (const [field, specs] of Object.entries(draft.files)) {
    if (!specs.length) continue;
    const blobs = await Promise.all(specs.map((s) => (s.image ? shrinkImage(s.file, s.image.maxDimension) : Promise.resolve(s.file as Blob))));
    prepared.push([field, blobs]);
  }

  const counts = Object.fromEntries(prepared.map(([field, blobs]) => [field, blobs.length]));
  const start = await startPost(type, counts);
  if (!start.ok) return start;

  const total = prepared.reduce((sum, [, blobs]) => sum + blobs.reduce((s, b) => s + b.size, 0), 0) || 1;
  const sent = new Map<string, number>();
  const report = () => onProgress({ stage: "uploading", fraction: [...sent.values()].reduce((a, b) => a + b, 0) / total });
  report();

  const assets: Record<string, AssetReceipt[]> = {};
  try {
    for (const [field, blobs] of prepared) {
      const urls = start.urls[field] ?? [];
      // A few at a time: fast for photo sets without opening dozens of connections.
      const results: AssetReceipt[] = new Array(blobs.length);
      let next = 0;
      const worker = async () => {
        while (next < blobs.length) {
          const i = next++;
          if (!urls[i]) throw new Error("Missing upload slot.");
          results[i] = await upload(urls[i], blobs[i], (n) => {
            sent.set(`${field}:${i}`, n);
            report();
          });
        }
      };
      await Promise.all(Array.from({ length: Math.min(3, blobs.length) }, worker));
      assets[field] = results;
    }
  } catch (error) {
    return { ok: false, message: error instanceof Error ? error.message : "Upload failed." };
  }

  onProgress({ stage: "saving", fraction: 1 });
  const { files: _files, ...rest } = draft;
  void _files;
  return publishPost({ ...rest, type, recordName: start.recordName, token: start.token, assets });
}
