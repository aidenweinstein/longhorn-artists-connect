#!/usr/bin/env node
//
//  spike-cloudkit.mjs
//  Phase 0 / Spike 1 — prove a server-to-server key can read the public Nexus content.
//
//  Answers four questions in one run:
//    1. Does server-to-server auth work at all? (the whole web plan blocks on this)
//    2. How many records of each type actually exist in production?
//    3. What are the real field names/types? (input for the TypeScript decoders)
//    4. Do asset downloadURLs support HTTP range requests, and what container are
//       the videos really in? (browsers cannot play HEVC-in-MOV)
//
//  Usage:  node web/scripts/spike-cloudkit.mjs
//  Config: web/.secrets/cloudkit.env  (CLOUDKIT_KEY_ID=...)
//  No dependencies — stdlib only.
//

import { createSign, createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const SECRETS = join(HERE, "..", ".secrets");

// Must match the app's iCloud container (CloudKitWebServices.containerID).
const CONTAINER = "iCloud.LAA.Longhorn-Artists-Connect";
// All real content lives in production, regardless of build config — same reasoning as
// CloudKitWebServices.environment.
const ENVIRONMENT = "production";
const HOST = "https://api.apple-cloudkit.com";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

function loadEnv() {
    let keyID = process.env.CLOUDKIT_KEY_ID;
    if (!keyID) {
        try {
            const text = readFileSync(join(SECRETS, "cloudkit.env"), "utf8");
            for (const line of text.split("\n")) {
                const m = line.match(/^\s*CLOUDKIT_KEY_ID\s*=\s*(.+?)\s*$/);
                if (m) keyID = m[1].replace(/^["']|["']$/g, "");
            }
        } catch {
            /* fall through to the error below */
        }
    }
    if (!keyID) {
        fail(
            "No key ID found.\n" +
            "Create web/.secrets/cloudkit.env containing:\n" +
            "  CLOUDKIT_KEY_ID=<the Key ID from CloudKit Dashboard>"
        );
    }
    let privateKey;
    try {
        privateKey = readFileSync(join(SECRETS, "cloudkit-s2s-key.pem"), "utf8");
    } catch {
        fail("Missing web/.secrets/cloudkit-s2s-key.pem — regenerate with:\n" +
            "  openssl ecparam -name prime256v1 -genkey -noout -out web/.secrets/cloudkit-s2s-key.pem");
    }
    return { keyID, privateKey };
}

function fail(msg) {
    console.error(`\n✗ ${msg}\n`);
    process.exit(1);
}

// ---------------------------------------------------------------------------
// Signed request
//
// CloudKit server-to-server auth signs the string
//     <ISO8601 date>:<base64(sha256(body))>:<request subpath>
// with the P-256 private key, and sends the DER signature base64-encoded. The date
// must be byte-identical to the header, which is why it is formatted once and reused.
// ---------------------------------------------------------------------------

async function ckRequest(subpathSuffix, body, { keyID, privateKey }) {
    const subpath = `/database/1/${CONTAINER}/${ENVIRONMENT}/public/${subpathSuffix}`;
    const payload = JSON.stringify(body);
    const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const bodyHash = createHash("sha256").update(payload).digest("base64");

    const signature = createSign("SHA256")
        .update(`${date}:${bodyHash}:${subpath}`)
        .sign(privateKey, "base64");

    const response = await fetch(HOST + subpath, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            "X-Apple-CloudKit-Request-KeyID": keyID,
            "X-Apple-CloudKit-Request-ISO8601Date": date,
            "X-Apple-CloudKit-Request-SignatureV1": signature,
        },
        body: payload,
    });

    const text = await response.text();
    if (!response.ok) {
        return { ok: false, status: response.status, error: text.slice(0, 400) };
    }
    return { ok: true, ...JSON.parse(text) };
}

/// Queries up to `limit` records of a type. An unfiltered query mirrors what the app
/// does (`CKQuery(recordType:predicate: NSPredicate(value: true))`).
async function queryRecords(recordType, limit, creds) {
    return ckRequest("records/query", {
        query: { recordType },
        resultsLimit: limit,
    }, creds);
}

// ---------------------------------------------------------------------------
// Asset probing
// ---------------------------------------------------------------------------

/// Builds a playable URL from a downloadURL template. The `${f}` token is the filename
/// the CDN serves the asset as, and it derives Content-Type from that extension —
/// substituting nothing yields application/octet-stream, which no player can identify.
/// This is the same trap documented in CloudKitWebServices.streamURL.
function assetURL(template, filename) {
    return template.replace("${f}", filename);
}

/// Range-GETs the first bytes of an asset. Confirms the CDN honors Range (status 206),
/// reports the Content-Type the browser will see, and returns the leading bytes so the
/// container can be identified.
async function probeAsset(url) {
    try {
        const response = await fetch(url, { headers: { Range: "bytes=0-31" } });
        const buf = Buffer.from(await response.arrayBuffer());
        return {
            status: response.status,
            contentType: response.headers.get("content-type"),
            contentRange: response.headers.get("content-range"),
            acceptRanges: response.headers.get("accept-ranges"),
            bytes: buf,
        };
    } catch (e) {
        return { error: e.message };
    }
}

/// Identifies an ISO-BMFF container from its `ftyp` brand. `qt  ` means QuickTime/MOV,
/// which is NOT a web-baseline container; `isom`/`mp42`/`avc1` are MP4.
function describeContainer(bytes) {
    if (bytes.length < 12) return "too few bytes";
    const box = bytes.subarray(4, 8).toString("ascii");
    if (box !== "ftyp") {
        const hex = bytes.subarray(0, 8).toString("hex");
        if (bytes.subarray(0, 3).toString("ascii") === "ID3") return "MP3 (ID3) — web-baseline ✓";
        if (bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0) return "MP3 (frame sync) — web-baseline ✓";
        return `not ISO-BMFF (first 8 bytes: ${hex})`;
    }
    const brand = bytes.subarray(8, 12).toString("ascii");
    const isMOV = brand.startsWith("qt");
    return `${isMOV ? "QuickTime/MOV" : "MP4"} (ftyp brand "${brand}") — ` +
        (isMOV ? "NOT web-baseline ✗ needs transcode" : "likely playable, codec still unverified");
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

// Record types the website needs, with the asset field carrying each one's poster image.
const CONTENT_TYPES = [
    ["FilmSubmission", "filmThumbnail", "filmVideo"],
    ["MusicSubmission", "musicCover", "musicAudio"],
    ["ReelSubmission", "reelThumbnail", "reelVideo"],
    ["PhotographySubmission", "photographyThumbnail", null],
    ["ProjectSubmission", "projectPoster", null],
    ["EventSubmission", "eventFlyer", null],
];
const SUPPORTING_TYPES = ["UserProfile", "PostLike", "ModerationAction", "ModerationEdit", "Organization"];

async function main() {
    const creds = loadEnv();
    console.log(`\nContainer:   ${CONTAINER}`);
    console.log(`Environment: ${ENVIRONMENT}`);
    console.log(`Key ID:      ${creds.keyID.slice(0, 12)}…\n`);

    // --- 1. Auth -----------------------------------------------------------
    process.stdout.write("1. Server-to-server auth … ");
    const probe = await queryRecords("FilmSubmission", 1, creds);
    if (!probe.ok) {
        console.log("FAILED");
        console.error(`\n   HTTP ${probe.status}\n   ${probe.error}\n`);
        console.error("   AUTHENTICATION_FAILED → the Key ID doesn't match the public key you pasted.");
        console.error("   BAD_REQUEST on the signature → clock skew, or the date header and signed date differ.");
        console.error("   NOT_FOUND on the container → check the container identifier.\n");
        process.exit(1);
    }
    console.log("OK ✓");

    // --- 2. Inventory ------------------------------------------------------
    console.log("\n2. Production content inventory (capped at 200/type):");
    const samples = {};
    for (const [type, posterField, mediaField] of CONTENT_TYPES) {
        const result = await queryRecords(type, 200, creds);
        if (!result.ok) {
            console.log(`   ${type.padEnd(24)} query failed — HTTP ${result.status}`);
            continue;
        }
        const records = result.records ?? [];
        console.log(`   ${type.padEnd(24)} ${String(records.length).padStart(3)} records`);
        if (records.length) samples[type] = { record: records[0], posterField, mediaField };
    }
    for (const type of SUPPORTING_TYPES) {
        const result = await queryRecords(type, 200, creds);
        const count = result.ok ? (result.records ?? []).length : "—";
        console.log(`   ${type.padEnd(24)} ${String(count).padStart(3)} records${result.ok ? "" : ` (HTTP ${result.status})`}`);
    }

    // --- 3. Schema ---------------------------------------------------------
    const film = samples["FilmSubmission"]?.record;
    if (film) {
        console.log("\n3. FilmSubmission fields as production actually returns them:");
        for (const [name, value] of Object.entries(film.fields ?? {})) {
            const preview = value.type === "ASSETID"
                ? "<asset>"
                : JSON.stringify(value.value ?? null).slice(0, 52);
            console.log(`   ${name.padEnd(26)} ${String(value.type).padEnd(14)} ${preview}`);
        }
    } else {
        console.log("\n3. No FilmSubmission records to inspect — skipping schema dump.");
    }

    // --- 4. Assets ---------------------------------------------------------
    console.log("\n4. Asset streaming (range requests + real containers):");
    for (const [type, { record, posterField, mediaField }] of Object.entries(samples)) {
        for (const [field, filename] of [
            [posterField, "media.jpg"],
            [mediaField, field_default(mediaField)],
        ]) {
            if (!field) continue;
            const asset = record.fields?.[field];
            const template = asset?.value?.downloadURL;
            if (!template) {
                console.log(`   ${type}.${field}: no downloadURL (asset missing on this record)`);
                continue;
            }
            const probe = await probeAsset(assetURL(template, filename));
            if (probe.error) {
                console.log(`   ${type}.${field}: probe failed — ${probe.error}`);
                continue;
            }
            const ranged = probe.status === 206 ? "range OK ✓" : `range NOT honored (HTTP ${probe.status}) ✗`;
            console.log(`   ${type}.${field} as ${filename}`);
            console.log(`      ${ranged}  content-type: ${probe.contentType}`);
            if (mediaField && field === mediaField) {
                console.log(`      container: ${describeContainer(probe.bytes)}`);
            }
        }
    }

    console.log("\n✓ Spike 1 complete.\n");
}

/// The filename to request a media asset as. Mirrors CloudKitWebServices.defaultExtension.
function field_default(field) {
    switch (field) {
        case "filmVideo":
        case "reelVideo": return "media.mov";
        case "musicAudio": return "media.mp3";
        default: return "media.bin";
    }
}

main().catch((e) => fail(e.stack ?? e.message));
