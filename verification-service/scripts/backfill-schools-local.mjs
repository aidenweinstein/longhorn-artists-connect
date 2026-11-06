#!/usr/bin/env node
//
// Local, Worker-free schoolID backfill.
//
// Same job as backfill-schools.mjs, but it talks to CloudKit Web Services
// directly with the server-to-server key in keys/ instead of going through the
// deployed Worker. Use it while the Worker (and its D1) isn't deployed yet.
//
// With no D1 to look up each creator's verified school, every unstamped record
// gets DEFAULT_SCHOOL — correct for the container today, where every post is
// UT Austin work. Records that already carry a schoolID are left alone, so it's
// safe to re-run (and it should be re-run once old builds stop posting).
//
// Writes use `forceUpdate` with only the schoolID field, exactly like
// src/cloudkit.ts `updateRecordFields`: every other field on the post is left
// untouched on the server.
//
// Usage:
//   CK_KEY_ID=<server-to-server key ID> \
//   CK_ENVIRONMENT=production \
//   node scripts/backfill-schools-local.mjs           # dry run (default)
//
//   ... node scripts/backfill-schools-local.mjs --write
//
// CK_ENVIRONMENT defaults to "development" so a bare run can't touch production.

import { readFileSync } from "node:fs";
import { createHash, createPrivateKey, sign } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const CONTAINER = "iCloud.LAA.Longhorn-Artists-Connect";
const DEFAULT_SCHOOL = "ut-austin"; // Must match SchoolScope.legacyDefault.
const RECORD_TYPES = [
    "FilmSubmission",
    "MusicSubmission",
    "ReelSubmission",
    "ProjectSubmission",
    "EventSubmission",
    "PhotographySubmission",
    "DesignSubmission",
];
/// Title field per type, only so the dry run can list posts by name.
const TITLE_FIELD = {
    FilmSubmission: "filmTitle",
    MusicSubmission: "musicTitle",
    ReelSubmission: "reelTitle",
    ProjectSubmission: "projectTitle",
    EventSubmission: "eventTitle",
    PhotographySubmission: "photographyTitle",
    DesignSubmission: "designTitle",
};
const WRITE_BATCH = 100;

const keyID = process.env.CK_KEY_ID;
const environment = process.env.CK_ENVIRONMENT ?? "development";
const write = process.argv.includes("--write");

if (!keyID) {
    console.error("Set CK_KEY_ID (CloudKit Dashboard → API Access → Server-to-Server Keys).");
    process.exit(1);
}
if (environment !== "development" && environment !== "production") {
    console.error(`CK_ENVIRONMENT must be development or production, got "${environment}".`);
    process.exit(1);
}

const here = dirname(fileURLToPath(import.meta.url));
const privateKey = createPrivateKey(readFileSync(join(here, "../keys/ck-key-pkcs8.pem")));

/// Signs and sends one request. Node's ECDSA signatures are already DER, which
/// is what CloudKit expects (the Worker has to convert from P1363 by hand).
async function ckFetch(operation, body) {
    const path = `/database/1/${CONTAINER}/${environment}/public/${operation}`;
    const bodyText = JSON.stringify(body);
    const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const bodyHash = createHash("sha256").update(bodyText).digest("base64");
    const signature = sign("sha256", Buffer.from(`${date}:${bodyHash}:${path}`), privateKey).toString("base64");

    const response = await fetch(`https://api.apple-cloudkit.com${path}`, {
        method: "POST",
        headers: {
            "content-type": "application/json",
            "X-Apple-CloudKit-Request-KeyID": keyID,
            "X-Apple-CloudKit-Request-ISO8601Date": date,
            "X-Apple-CloudKit-Request-SignatureV1": signature,
        },
        body: bodyText,
    });
    const text = await response.text();
    if (!response.ok) throw new Error(`CloudKit ${response.status}: ${text.slice(0, 400)}`);
    return JSON.parse(text);
}

const total = { scanned: 0, toStamp: 0, alreadyStamped: 0, stamped: 0, failed: 0 };
const skippedTypes = [];

console.log(`${write ? "WRITE" : "DRY RUN"} — ${environment}\n`);

for (const recordType of RECORD_TYPES) {
    const pending = [];
    let marker;
    let scanned = 0;
    let already = 0;

    try {
        do {
            const page = await ckFetch("records/query", {
                query: { recordType },
                resultsLimit: 200,
                desiredKeys: ["schoolID", TITLE_FIELD[recordType]],
                ...(marker ? { continuationMarker: marker } : {}),
            });
            marker = page.continuationMarker;
            for (const record of page.records ?? []) {
                scanned++;
                const existing = record.fields?.schoolID?.value;
                if (typeof existing === "string" && existing.length > 0) {
                    already++;
                    continue;
                }
                pending.push(record);
            }
        } while (marker);
    } catch (error) {
        skippedTypes.push({ recordType, reason: error.message });
        console.error(`⚠️  ${recordType}: query failed — ${error.message}`);
        continue;
    }

    total.scanned += scanned;
    total.alreadyStamped += already;
    total.toStamp += pending.length;
    console.log(`${recordType}: ${scanned} records, ${already} already stamped, ${pending.length} to stamp`);
    if (!write) {
        for (const record of pending) {
            const title = record.fields?.[TITLE_FIELD[recordType]]?.value ?? "(untitled)";
            console.log(`   • ${title}  [${record.recordName}]`);
        }
        continue;
    }

    for (let i = 0; i < pending.length; i += WRITE_BATCH) {
        const batch = pending.slice(i, i + WRITE_BATCH);
        const result = await ckFetch("records/modify", {
            operations: batch.map((record) => ({
                operationType: "forceUpdate",
                record: {
                    recordType,
                    recordName: record.recordName,
                    fields: { schoolID: { value: DEFAULT_SCHOOL } },
                },
            })),
        });
        for (const record of result.records ?? []) {
            if (record.serverErrorCode) {
                total.failed++;
                console.error(`   ✗ ${record.recordName}: ${record.serverErrorCode} ${record.reason ?? ""}`);
            } else {
                total.stamped++;
            }
        }
    }
}

console.log(`\n${write ? "WROTE" : "DRY RUN — nothing written"} (${environment})`);
console.log(`scanned          ${total.scanned}`);
console.log(`already stamped  ${total.alreadyStamped}`);
console.log(write ? `stamped          ${total.stamped}` : `would stamp      ${total.toStamp}  → "${DEFAULT_SCHOOL}"`);
if (write) console.log(`failed           ${total.failed}`);

if (skippedTypes.length > 0) {
    console.error("\n⚠️  These record types were SKIPPED — their records are still unstamped:");
    for (const skipped of skippedTypes) console.error(`   ${skipped.recordType}: ${skipped.reason}`);
    process.exit(1);
}
if (total.failed > 0) process.exit(1);
