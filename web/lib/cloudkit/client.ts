import { createHash, createSign } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Server-to-server CloudKit Web Services client for the public database.
 * Signing matches scripts/spike-cloudkit.mjs and verification-service/src/cloudkit.ts.
 *
 * Credentials come from CLOUDKIT_KEY_ID + CLOUDKIT_PRIVATE_KEY (Vercel), or from
 * web/.secrets/cloudkit.env + cloudkit-s2s-key.pem when running locally.
 */

const CONTAINER = "iCloud.LAA.Longhorn-Artists-Connect";
const ENVIRONMENT = "production";
const HOST = "https://api.apple-cloudkit.com";

type Creds = { keyID: string; privateKey: string };

let cached: Creds | null | undefined;

function loadCreds(): Creds | null {
  if (cached !== undefined) return cached;
  let keyID = process.env.CLOUDKIT_KEY_ID ?? "";
  let privateKey = (process.env.CLOUDKIT_PRIVATE_KEY ?? "").replace(/\\n/g, "\n");
  if (!keyID || !privateKey) {
    try {
      const dir = join(process.cwd(), ".secrets");
      const env = readFileSync(join(dir, "cloudkit.env"), "utf8");
      keyID = keyID || (env.match(/^\s*CLOUDKIT_KEY_ID\s*=\s*(\S+)/m)?.[1] ?? "");
      privateKey = privateKey || readFileSync(join(dir, "cloudkit-s2s-key.pem"), "utf8");
    } catch {
      /* not configured */
    }
  }
  cached = keyID && privateKey ? { keyID, privateKey } : null;
  return cached;
}

export function isCloudKitConfigured(): boolean {
  return loadCreds() !== null;
}

export type CKField = { value: unknown; type?: string };
export type CKRecord = {
  recordName: string;
  recordType: string;
  fields: Record<string, CKField>;
  created?: { timestamp: number };
};

async function request<T>(subpathSuffix: string, body: unknown): Promise<T> {
  const creds = loadCreds();
  if (!creds) throw new Error("CloudKit is not configured.");

  const subpath = `/database/1/${CONTAINER}/${ENVIRONMENT}/public/${subpathSuffix}`;
  const payload = JSON.stringify(body);
  const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const bodyHash = createHash("sha256").update(payload).digest("base64");
  const signature = createSign("SHA256").update(`${date}:${bodyHash}:${subpath}`).sign(creds.privateKey, "base64");

  const res = await fetch(HOST + subpath, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "X-Apple-CloudKit-Request-KeyID": creds.keyID,
      "X-Apple-CloudKit-Request-ISO8601Date": date,
      "X-Apple-CloudKit-Request-SignatureV1": signature,
    },
    body: payload,
    cache: "no-store",
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`CloudKit ${res.status} on ${subpathSuffix}: ${text.slice(0, 300)}`);
  return JSON.parse(text) as T;
}

/** Every record of a type, following continuation markers. Unfiltered, like the app's NSPredicate(value: true). */
export async function queryAll(recordType: string, maxRecords = 2000): Promise<CKRecord[]> {
  const out: CKRecord[] = [];
  let continuationMarker: string | undefined;
  do {
    const page = await request<{ records?: (CKRecord & { serverErrorCode?: string })[]; continuationMarker?: string }>(
      "records/query",
      { query: { recordType }, resultsLimit: 200, ...(continuationMarker ? { continuationMarker } : {}) },
    );
    for (const r of page.records ?? []) if (!r.serverErrorCode) out.push(r);
    continuationMarker = page.continuationMarker;
  } while (continuationMarker && out.length < maxRecords);
  return out;
}

/** Records of a type whose `field` equals `value` (the field must be Queryable). */
export async function queryWhere(recordType: string, field: string, value: string, desiredKeys: string[] = [], maxRecords = 5000) {
  const out: CKRecord[] = [];
  let continuationMarker: string | undefined;
  do {
    const page = await request<{ records?: (CKRecord & { serverErrorCode?: string })[]; continuationMarker?: string }>(
      "records/query",
      {
        query: { recordType, filterBy: [{ fieldName: field, comparator: "EQUALS", fieldValue: { value } }] },
        desiredKeys,
        resultsLimit: 200,
        ...(continuationMarker ? { continuationMarker } : {}),
      },
    );
    for (const r of page.records ?? []) if (!r.serverErrorCode) out.push(r);
    continuationMarker = page.continuationMarker;
  } while (continuationMarker && out.length < maxRecords);
  return out;
}

export type CKWrite =
  | { kind: "save"; recordType: string; recordName: string; fields: Record<string, CKField> }
  | { kind: "delete"; recordName: string };

/** Creates/replaces or deletes records. Throws with CloudKit's reason if any one fails. */
export async function modify(writes: CKWrite[]): Promise<void> {
  const res = await request<{ records?: { recordName: string; serverErrorCode?: string; reason?: string }[] }>("records/modify", {
    operations: writes.map((w) =>
      w.kind === "save"
        ? { operationType: "forceReplace", record: { recordType: w.recordType, recordName: w.recordName, fields: w.fields } }
        : { operationType: "forceDelete", record: { recordName: w.recordName } },
    ),
  });
  // Deleting something already gone is fine, the same as the app treats it.
  const failed = res.records?.find((r) => r.serverErrorCode && r.serverErrorCode !== "NOT_FOUND");
  if (failed) throw new Error(`CloudKit ${failed.serverErrorCode}: ${failed.reason ?? ""}`);
}

/** One record by name, or null when it doesn't exist. */
export async function lookup(recordName: string): Promise<CKRecord | null> {
  const res = await request<{ records?: (CKRecord & { serverErrorCode?: string })[] }>("records/lookup", {
    records: [{ recordName }],
  });
  const r = res.records?.[0];
  return r && !r.serverErrorCode ? r : null;
}

/**
 * Overwrites only the given fields on one existing record. Returns the server's error
 * for that record (e.g. a field the production schema doesn't have yet), or null.
 */
export async function updateFields(
  recordType: string,
  recordName: string,
  fields: Record<string, CKField>,
): Promise<{ code: string; reason: string } | null> {
  const res = await request<{ records?: { serverErrorCode?: string; reason?: string }[] }>("records/modify", {
    operations: [{ operationType: "forceUpdate", record: { recordType, recordName, fields } }],
  });
  const r = res.records?.[0];
  return r?.serverErrorCode ? { code: r.serverErrorCode, reason: r.reason ?? "" } : null;
}

/**
 * Uploads a file for an asset field and returns the value to save in that field.
 * CloudKit's two steps: ask for an upload URL, send the bytes there, then put the
 * returned receipt in the record. The bytes go only to Apple.
 */
export async function uploadAsset(
  recordType: string,
  recordName: string,
  fieldName: string,
  bytes: Uint8Array,
  contentType: string,
): Promise<CKField> {
  const res = await request<{ tokens?: { url?: string }[] }>("assets/upload", {
    tokens: [{ recordType, recordName, fieldName }],
  });
  const url = res.tokens?.[0]?.url;
  if (!url) throw new Error("CloudKit didn't return an upload URL.");
  const up = await fetch(url, {
    method: "POST",
    headers: { "content-type": contentType },
    body: Buffer.from(bytes),
    cache: "no-store",
  });
  if (!up.ok) throw new Error(`Asset upload failed: ${up.status}`);
  const { singleFile } = (await up.json()) as { singleFile?: Record<string, unknown> };
  if (!singleFile) throw new Error("Asset upload returned no receipt.");
  return { value: singleFile, type: "ASSETID" };
}

// MARK: - Field readers

export function str(r: CKRecord, key: string): string {
  const v = r.fields[key]?.value;
  return typeof v === "string" ? v : "";
}

export function num(r: CKRecord, key: string): number | undefined {
  const v = r.fields[key]?.value;
  return typeof v === "number" ? v : undefined;
}

export function list(r: CKRecord, key: string): string[] {
  const v = r.fields[key]?.value;
  return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];
}

type CKAsset = { downloadURL?: string };

/**
 * A playable URL for an asset. The CDN derives Content-Type from the filename put in
 * place of ${f}, so pass a filename with the right extension (media.jpg, media.mp4...).
 */
export function asset(r: CKRecord, key: string, filename: string): string | undefined {
  const v = r.fields[key]?.value as CKAsset | undefined;
  return v?.downloadURL ? v.downloadURL.replace("${f}", filename) : undefined;
}

export function assets(r: CKRecord, key: string, filename: string): string[] {
  const v = r.fields[key]?.value;
  if (!Array.isArray(v)) return [];
  return (v as CKAsset[]).flatMap((a) => (a?.downloadURL ? [a.downloadURL.replace("${f}", filename)] : []));
}
