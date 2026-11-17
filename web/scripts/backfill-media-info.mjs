// Fills in what older posts are missing, so the website doesn't have to work it out on
// every refresh:
//   - thumbWidth / thumbHeight: the feed picture's size in pixels
//   - the saved length of a post's video or song (filmVideoDuration and friends)
//
// It never changes a value that is already there.
//
//   cd web
//   node scripts/backfill-media-info.mjs            # dry run: only lists what it would save
//   node scripts/backfill-media-info.mjs --write    # saves to the Production database
//
// Uses the same key as the website (web/.secrets/, or CLOUDKIT_KEY_ID + CLOUDKIT_PRIVATE_KEY).
// thumbWidth and thumbHeight (Int64) must be deployed to Production on all five post
// types first; without them the size part is skipped and the lengths are still saved.

import { createHash, createSign } from "node:crypto";
import { readFileSync } from "node:fs";

const WRITE = process.argv.includes("--write");
const CONTAINER = "iCloud.LAA.Longhorn-Artists-Connect";
const HOST = process.env.CLOUDKIT_HOST ?? "https://api.apple-cloudkit.com";

let keyID = process.env.CLOUDKIT_KEY_ID ?? "";
let privateKey = (process.env.CLOUDKIT_PRIVATE_KEY ?? "").replace(/\\n/g, "\n");
if (!keyID || !privateKey) {
  keyID = readFileSync(".secrets/cloudkit.env", "utf8").match(/^\s*CLOUDKIT_KEY_ID\s*=\s*(\S+)/m)?.[1] ?? "";
  privateKey = readFileSync(".secrets/cloudkit-s2s-key.pem", "utf8");
}

async function cloudkit(suffix, body) {
  const subpath = `/database/1/${CONTAINER}/production/public/${suffix}`;
  const payload = JSON.stringify(body);
  const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const hash = createHash("sha256").update(payload).digest("base64");
  const signature = createSign("SHA256").update(`${date}:${hash}:${subpath}`).sign(privateKey, "base64");
  const res = await fetch(HOST + subpath, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "X-Apple-CloudKit-Request-KeyID": keyID,
      "X-Apple-CloudKit-Request-ISO8601Date": date,
      "X-Apple-CloudKit-Request-SignatureV1": signature,
    },
    body: payload,
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`CloudKit ${res.status} on ${suffix}: ${text.slice(0, 300)}`);
  return JSON.parse(text);
}

async function queryAll(recordType) {
  const out = [];
  let continuationMarker;
  do {
    const page = await cloudkit("records/query", { query: { recordType }, resultsLimit: 200, ...(continuationMarker ? { continuationMarker } : {}) });
    for (const r of page.records ?? []) if (!r.serverErrorCode) out.push(r);
    continuationMarker = page.continuationMarker;
  } while (continuationMarker);
  return out;
}

async function range(url, start, length) {
  const res = await fetch(url, { headers: { Range: `bytes=${start}-${start + length - 1}` } });
  if (!res.ok && res.status !== 206) throw new Error(`download ${res.status}`);
  const bytes = new Uint8Array(await res.arrayBuffer());
  // A server that ignores Range sends the whole file from the start.
  return res.status === 206 ? bytes : bytes.subarray(start, start + length);
}

// MARK: - Picture size (JPEG or PNG), as displayed

function exifOrientation(b, start, length) {
  if (String.fromCharCode(...b.subarray(start, start + 4)) !== "Exif") return undefined;
  const tiff = start + 6;
  if (tiff + 8 > b.length) return undefined;
  const little = b[tiff] === 0x49;
  const v = new DataView(b.buffer, b.byteOffset);
  const ifd = tiff + v.getUint32(tiff + 4, little);
  const end = Math.min(b.length, start + length);
  if (ifd + 2 > end) return undefined;
  const count = v.getUint16(ifd, little);
  for (let n = 0; n < count; n++) {
    const entry = ifd + 2 + n * 12;
    if (entry + 12 > end) break;
    if (v.getUint16(entry, little) === 0x0112) return v.getUint16(entry + 8, little);
  }
  return undefined;
}

function pictureSize(b) {
  if (b.length >= 24 && b[0] === 0x89 && b[1] === 0x50) {
    const v = new DataView(b.buffer, b.byteOffset);
    return { w: v.getUint32(16), h: v.getUint32(20) };
  }
  if (b.length < 4 || b[0] !== 0xff || b[1] !== 0xd8) return undefined;
  let i = 2;
  let orientation = 1;
  while (i + 9 < b.length) {
    if (b[i] !== 0xff) { i++; continue; }
    const marker = b[i + 1];
    const len = (b[i + 2] << 8) | b[i + 3];
    if (marker === 0xe1) orientation = exifOrientation(b, i + 4, len - 2) ?? orientation;
    if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
      const h = (b[i + 5] << 8) | b[i + 6];
      const w = (b[i + 7] << 8) | b[i + 8];
      return orientation >= 5 ? { w: h, h: w } : { w, h };
    }
    i += 2 + len;
  }
  return undefined;
}

async function measurePicture(url) {
  for (const length of [65_536, 524_288]) {
    const size = pictureSize(await range(url, 0, length));
    if (size && size.w > 0 && size.h > 0) return size;
  }
  return undefined;
}

// MARK: - Length of an MP4 / MOV / M4A file, from its header

async function mediaSeconds(url, fileSize) {
  let offset = 0;
  for (let box = 0; box < 64 && (!fileSize || offset < fileSize); box++) {
    const head = await range(url, offset, 16);
    if (head.length < 8) return undefined;
    const v = new DataView(head.buffer, head.byteOffset);
    let size = v.getUint32(0);
    const type = String.fromCharCode(...head.subarray(4, 8));
    if (!/^[\x20-\x7e]{4}$/.test(type)) return undefined; // not an MP4-style file (MP3, WAV...)
    if (size === 1 && head.length >= 16) size = Number(v.getBigUint64(8));
    if (type === "moov") {
      const moov = await range(url, offset, Math.min(size || 4_194_304, 4_194_304));
      const m = new DataView(moov.buffer, moov.byteOffset);
      for (let i = 8; i + 32 < moov.length; i++) {
        if (moov[i] === 0x6d && moov[i + 1] === 0x76 && moov[i + 2] === 0x68 && moov[i + 3] === 0x64) {
          const version = moov[i + 4];
          const timescale = version === 1 ? m.getUint32(i + 24) : m.getUint32(i + 16);
          const duration = version === 1 ? Number(m.getBigUint64(i + 28)) : m.getUint32(i + 20);
          return timescale > 0 && duration > 0 ? duration / timescale : undefined;
        }
      }
      return undefined;
    }
    if (size < 8) return undefined;
    offset += size;
  }
  return undefined;
}

// MARK: - The posts

const TYPES = [
  { recordType: "FilmSubmission", thumb: ["filmThumbnail"], media: "filmVideo", length: "filmVideoDuration" },
  { recordType: "MusicSubmission", thumb: ["musicCover"], media: "musicAudio", length: "musicAudioDuration" },
  { recordType: "ReelSubmission", thumb: ["reelThumbnail"], media: "reelVideo", length: "reelVideoDuration" },
  { recordType: "PhotographySubmission", thumb: ["photographyThumbnail"], media: null, length: null },
  { recordType: "DesignSubmission", thumb: ["designThumbnail"], media: "designVideo", length: "designVideoDuration" },
];

const link = (asset, name) => asset?.downloadURL?.replace("${f}", name);
const has = (r, key) => typeof r.fields[key]?.value === "number" && r.fields[key].value > 0;

let saved = 0;
let sizeFieldsMissing = false;
for (const t of TYPES) {
  const records = await queryAll(t.recordType);
  console.log(`\n${t.recordType}: ${records.length} posts`);
  for (const r of records) {
    const fields = {};
    const thumb = r.fields[t.thumb[0]]?.value;
    if (thumb?.downloadURL && !(has(r, "thumbWidth") && has(r, "thumbHeight"))) {
      const size = await measurePicture(link(thumb, "media.jpg")).catch(() => undefined);
      if (size) {
        fields.thumbWidth = { value: size.w, type: "INT64" };
        fields.thumbHeight = { value: size.h, type: "INT64" };
      }
    }
    const media = t.media ? r.fields[t.media]?.value : undefined;
    if (media?.downloadURL && !has(r, t.length)) {
      const seconds = await mediaSeconds(link(media, "media.mp4"), media.size).catch(() => undefined);
      if (seconds) fields[t.length] = { value: Math.round(seconds * 100) / 100, type: "DOUBLE" };
    }
    if (!Object.keys(fields).length) continue;
    const summary = Object.entries(fields).map(([k, f]) => `${k}=${f.value}`).join("  ");
    console.log(`  ${r.recordName}  ${summary}`);
    if (!WRITE) { saved++; continue; }

    const attempt = async (toSave) => {
      const res = await cloudkit("records/modify", { operations: [{ operationType: "forceUpdate", record: { recordType: t.recordType, recordName: r.recordName, fields: toSave } }] });
      return res.records?.[0]?.serverErrorCode ? res.records[0] : null;
    };
    let failure = await attempt(fields);
    if (failure && /thumbWidth|thumbHeight/.test(failure.reason ?? "")) {
      // Production doesn't have the size fields yet: keep the length, skip the size.
      sizeFieldsMissing = true;
      const rest = Object.fromEntries(Object.entries(fields).filter(([k]) => k !== "thumbWidth" && k !== "thumbHeight"));
      if (!Object.keys(rest).length) continue;
      failure = await attempt(rest);
    }
    if (failure) console.log(`    not saved: ${failure.serverErrorCode} ${failure.reason ?? ""}`);
    else saved++;
  }
}

console.log(`\n${WRITE ? "Saved" : "Would save"} ${saved} post${saved === 1 ? "" : "s"}.${WRITE ? "" : " Nothing was changed. Run again with --write to save."}`);
if (sizeFieldsMissing) console.log("thumbWidth / thumbHeight aren't in the Production schema yet, so picture sizes were skipped. Deploy the schema, then run this again.");
