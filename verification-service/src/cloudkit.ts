/// CloudKit Web Services with server-to-server authentication.
///
/// Every request is signed with an ECDSA P-256 key registered in the CloudKit
/// dashboard. The signature payload is:
///
///     [ISO8601 date]:[base64(SHA256(body))]:[path without query string]
///
/// Signing server-side is what makes the Verification record trustworthy: the
/// record type grants write access to this key alone, so a client cannot forge
/// its own verified status.

import { Env, base64Encode, base64Decode, sha256Base64 } from "./util";

const CK_HOST = "https://api.apple-cloudkit.com";

let cachedKey: CryptoKey | null = null;

/// Imports the PKCS#8 PEM held in the CK_PRIVATE_KEY secret.
///
/// Note: `openssl ecparam` emits a SEC1 key ("BEGIN EC PRIVATE KEY") which
/// WebCrypto cannot import. The README's key-generation step converts it to
/// PKCS#8 ("BEGIN PRIVATE KEY"); if you see an import failure here, that
/// conversion is the thing that was skipped.
async function signingKey(env: Env): Promise<CryptoKey> {
    if (cachedKey) return cachedKey;

    const body = env.CK_PRIVATE_KEY
        .replace(/-----BEGIN [A-Z ]+-----/, "")
        .replace(/-----END [A-Z ]+-----/, "")
        .replace(/\s+/g, "");

    cachedKey = await crypto.subtle.importKey(
        "pkcs8",
        base64Decode(body),
        { name: "ECDSA", namedCurve: "P-256" },
        false,
        ["sign"],
    );
    return cachedKey;
}

/// WebCrypto returns ECDSA signatures as raw r||s (IEEE P1363). CloudKit
/// expects ASN.1 DER. Converting is mandatory — skipping it yields a constant
/// 401 that looks exactly like a wrong key.
export function p1363ToDer(raw: Uint8Array): Uint8Array {
    const half = raw.length / 2;
    const encodeInt = (bytes: Uint8Array): number[] => {
        let start = 0;
        while (start < bytes.length - 1 && bytes[start] === 0) start++;
        const trimmed = [...bytes.slice(start)];
        // DER integers are signed; a leading high bit needs a zero pad.
        if (trimmed[0] & 0x80) trimmed.unshift(0x00);
        return [0x02, trimmed.length, ...trimmed];
    };

    const r = encodeInt(raw.slice(0, half));
    const s = encodeInt(raw.slice(half));
    const body = [...r, ...s];
    return new Uint8Array([0x30, body.length, ...body]);
}

interface CKRequestOptions {
    /// Path after the host, e.g. "/database/1/<container>/production/public/records/modify"
    path: string;
    /// Omit for a GET (signed over an empty body).
    body?: unknown;
}

async function ckFetch(env: Env, options: CKRequestOptions): Promise<any> {
    const isGet = options.body === undefined;
    const bodyText = isGet ? "" : JSON.stringify(options.body);
    const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const bodyHash = await sha256Base64(new TextEncoder().encode(bodyText));
    const payload = `${date}:${bodyHash}:${options.path}`;

    const key = await signingKey(env);
    const rawSignature = await crypto.subtle.sign(
        { name: "ECDSA", hash: "SHA-256" },
        key,
        new TextEncoder().encode(payload),
    );
    const signature = base64Encode(p1363ToDer(new Uint8Array(rawSignature)));

    const response = await fetch(`${CK_HOST}${options.path}`, {
        method: isGet ? "GET" : "POST",
        headers: {
            ...(isGet ? {} : { "content-type": "application/json" }),
            "X-Apple-CloudKit-Request-KeyID": env.CK_KEY_ID,
            "X-Apple-CloudKit-Request-ISO8601Date": date,
            "X-Apple-CloudKit-Request-SignatureV1": signature,
        },
        ...(isGet ? {} : { body: bodyText }),
    });

    const text = await response.text();
    if (!response.ok) {
        throw new Error(`CloudKit ${response.status}: ${text.slice(0, 400)}`);
    }
    return JSON.parse(text);
}

function databasePath(env: Env, operation: string): string {
    return `/database/1/${env.CK_CONTAINER}/${env.CK_ENVIRONMENT}/public/${operation}`;
}

// MARK: - Operations

/// Reads a user's own UserProfile record. Used to confirm the nonce the client
/// wrote there, which proves it controls the CloudKit account it claims.
export async function fetchUserProfile(env: Env, userRecordName: string): Promise<any | null> {
    const result = await ckFetch(env, {
        path: databasePath(env, "records/lookup"),
        body: { records: [{ recordName: `UserProfile_${userRecordName}` }] },
    });

    const record = result.records?.[0];
    if (!record || record.serverErrorCode) return null;
    return record;
}

export async function writeVerificationRecord(
    env: Env,
    params: {
        userRecordName: string;
        emailHash: string;
        schoolID: string;
        schoolName: string;
        domainKind: string;
        verifiedAt: number;
        /// "email" for the app's flow, "web" for an account made on the website.
        method?: string;
    },
): Promise<void> {
    await ckFetch(env, {
        path: databasePath(env, "records/modify"),
        body: {
            operations: [
                {
                    operationType: "forceReplace",
                    record: {
                        recordType: "Verification",
                        recordName: `Verification_${params.userRecordName}`,
                        fields: {
                            userRecordName: { value: params.userRecordName },
                            emailHash: { value: params.emailHash },
                            schoolID: { value: params.schoolID },
                            schoolName: { value: params.schoolName },
                            domainKind: { value: params.domainKind },
                            method: { value: params.method ?? "email" },
                            verifiedAt: { value: params.verifiedAt * 1000 },
                            // 0 until an enrollment vendor is wired in.
                            enrollmentVerified: { value: 0 },
                        },
                    },
                },
            ],
        },
    });
}

/// Creates a brand-new `UserProfile` for an account made on the website.
///
/// `create` (not replace), so it can never overwrite an existing profile. Like
/// the app's save, a field Production's schema doesn't have yet is dropped and
/// the save retried — but only fields in `optional`; any other rejection throws.
/// Returns the fields that were left off.
export async function createUserProfile(
    env: Env,
    recordName: string,
    fields: Record<string, { value: string | number }>,
    optional: readonly string[],
): Promise<string[]> {
    const current = { ...fields };
    const dropped: string[] = [];
    for (let attempt = 0; attempt <= optional.length; attempt++) {
        const result = await ckFetch(env, {
            path: databasePath(env, "records/modify"),
            body: { operations: [{ operationType: "create", record: { recordType: "UserProfile", recordName, fields: current } }] },
        });
        const record = result.records?.[0];
        if (!record?.serverErrorCode) return dropped;
        const reason = String(record.reason ?? "");
        const culprit = optional.find(
            (key) => key in current && new RegExp(`(^|[^A-Za-z0-9_])${key}([^A-Za-z0-9_]|$)`).test(reason),
        );
        if (!culprit) throw new Error(`CloudKit ${record.serverErrorCode}: ${reason}`);
        console.warn(`UserProfile ${recordName}: left off ${culprit} (${reason})`);
        delete current[culprit];
        dropped.push(culprit);
    }
    throw new Error("CloudKit kept rejecting the new profile.");
}

/// The CloudKit user this server-to-server key acts as: the `created` user on
/// every record the key writes. Null if CloudKit won't say.
export async function fetchCallerRecordName(env: Env): Promise<string | null> {
    try {
        const result = await ckFetch(env, { path: databasePath(env, "users/caller") });
        return typeof result?.userRecordName === "string" ? result.userRecordName : null;
    } catch (error) {
        console.error("users/caller failed", error);
        return null;
    }
}

/// Clears the one-time nonce so it cannot be replayed.
export async function clearProfileNonce(env: Env, userRecordName: string, record: any): Promise<void> {
    await ckFetch(env, {
        path: databasePath(env, "records/modify"),
        body: {
            operations: [
                {
                    operationType: "update",
                    record: {
                        recordType: "UserProfile",
                        recordName: record.recordName,
                        recordChangeTag: record.recordChangeTag,
                        fields: { verificationNonce: { value: "" } },
                    },
                },
            ],
        },
    });
}

export interface QueryPage {
    records: any[];
    continuationMarker?: string;
}

export async function queryRecords(
    env: Env,
    recordType: string,
    continuationMarker?: string,
    resultsLimit = 200,
    desiredKeys?: string[],
): Promise<QueryPage> {
    const result = await ckFetch(env, {
        path: databasePath(env, "records/query"),
        body: {
            query: { recordType },
            resultsLimit,
            ...(continuationMarker ? { continuationMarker } : {}),
            // System metadata (`created`, `recordChangeTag`) comes back whatever
            // this is set to, so a caller that only needs one field can avoid
            // dragging every asset URL on the record across the wire.
            ...(desiredKeys ? { desiredKeys } : {}),
        },
    });
    return { records: result.records ?? [], continuationMarker: result.continuationMarker };
}

export interface RecordFieldUpdate {
    recordName: string;
    recordType: string;
    fields: Record<string, { value: string | number }>;
}

export interface ModifyOutcome {
    saved: number;
    errors: { recordName: string; reason: string }[];
}

/// Writes specific fields onto existing records, leaving every other field as
/// it is on the server.
///
/// Uses `forceUpdate`, so a record the app edited between the query and this
/// write doesn't fail on a stale change tag. That's safe only because callers
/// here write fields the app doesn't otherwise touch — don't reuse this to
/// overwrite user-editable content.
///
/// The public database is non-atomic, so a bad record fails on its own rather
/// than taking the batch down with it; per-record failures come back inside a
/// 200 response and are reported, not thrown.
export async function updateRecordFields(
    env: Env,
    updates: RecordFieldUpdate[],
): Promise<ModifyOutcome> {
    if (updates.length === 0) return { saved: 0, errors: [] };

    const result = await ckFetch(env, {
        path: databasePath(env, "records/modify"),
        body: {
            operations: updates.map((update) => ({
                operationType: "forceUpdate",
                record: {
                    recordType: update.recordType,
                    recordName: update.recordName,
                    fields: update.fields,
                },
            })),
        },
    });

    const outcome: ModifyOutcome = { saved: 0, errors: [] };
    for (const record of result.records ?? []) {
        if (record.serverErrorCode) {
            outcome.errors.push({
                recordName: record.recordName ?? "unknown",
                reason: `${record.serverErrorCode}: ${record.reason ?? ""}`.trim(),
            });
        } else {
            outcome.saved++;
        }
    }
    return outcome;
}

export async function deleteRecord(env: Env, recordName: string): Promise<void> {
    await ckFetch(env, {
        path: databasePath(env, "records/modify"),
        body: { operations: [{ operationType: "forceDelete", record: { recordName } }] },
    });
}

/// Runs raw `records/modify` operations and reports per-record failures (the
/// public database is non-atomic, so one bad record doesn't fail the rest).
export async function modifyRecords(env: Env, operations: unknown[]): Promise<ModifyOutcome> {
    if (operations.length === 0) return { saved: 0, errors: [] };
    const result = await ckFetch(env, { path: databasePath(env, "records/modify"), body: { operations } });
    const outcome: ModifyOutcome = { saved: 0, errors: [] };
    for (const record of result.records ?? []) {
        if (record.serverErrorCode) {
            outcome.errors.push({ recordName: record.recordName ?? "unknown", reason: `${record.serverErrorCode}: ${record.reason ?? ""}`.trim() });
        } else {
            outcome.saved++;
        }
    }
    return outcome;
}
