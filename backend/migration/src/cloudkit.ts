/**
 * Minimal read-only CloudKit Web Services client.
 *
 * Mirrors the endpoint shape and auth already proven in the app
 * (CloudKitWebServices.assetFieldLookup, CloudKitWebServices.swift:313-380):
 * a public-database API token passed as `?ckAPIToken=`, POSTing to
 * https://api.apple-cloudkit.com/database/1/<container>/<env>/public/...
 *
 * The one thing this file must get right is PAGINATION. A CloudKit query returns
 * a single server-sized page plus a continuation marker. The iOS app learned this
 * the hard way — see the comment on CloudKitManager.fetchAllRecords
 * (CloudKitManager.swift:147-162): ignoring the cursor silently drops every
 * record past the first page, and because these records carry video assets that
 * page can be small. A partial export would look like a successful migration and
 * quietly lose posts.
 */

import { setTimeout as sleep } from 'node:timers/promises';

export interface CKAssetValue {
    downloadURL?: string;
    size?: number;
    fileChecksum?: string;
}

/** A field as web services wraps it: { value, type }. */
export interface CKField {
    value: unknown;
    type?: string;
}

export interface CKRecord {
    recordName: string;
    recordType: string;
    fields: Record<string, CKField>;
    created?: { timestamp?: number; userRecordName?: string; deviceID?: string };
    modified?: { timestamp?: number; userRecordName?: string; deviceID?: string };
    deleted?: boolean;
}

export interface CloudKitConfig {
    apiToken: string;
    containerID: string;
    environment: string;
}

const BASE = 'https://api.apple-cloudkit.com/database/1';
const PAGE_SIZE = 200; // CloudKit's documented maximum for a query request.

export class CloudKitClient {
    constructor(private readonly config: CloudKitConfig) {
        if (!config.apiToken) {
            throw new Error('CK_API_TOKEN is empty. See backend/migration/.env.example.');
        }
    }

    private url(path: string): string {
        const { containerID, environment, apiToken } = this.config;
        return `${BASE}/${containerID}/${environment}/public/${path}?ckAPIToken=${encodeURIComponent(apiToken)}`;
    }

    private async post(path: string, body: unknown): Promise<any> {
        const url = this.url(path);

        // Retry transient failures. CloudKit rate-limits and occasionally drops
        // connections on long export runs.
        let lastError: unknown;
        for (let attempt = 1; attempt <= 5; attempt++) {
            try {
                const response = await fetch(url, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(body),
                });

                if (response.status === 429 || response.status >= 500) {
                    const wait = 2 ** attempt * 500;
                    console.warn(`  ⏳ HTTP ${response.status}; retrying in ${wait}ms (attempt ${attempt}/5)`);
                    await sleep(wait);
                    continue;
                }

                if (!response.ok) {
                    const text = await response.text();
                    throw new Error(`CloudKit ${path} failed: HTTP ${response.status} ${text.slice(0, 500)}`);
                }

                return await response.json();
            } catch (error) {
                lastError = error;
                if (attempt === 5) break;
                const wait = 2 ** attempt * 500;
                console.warn(`  ⏳ transport error; retrying in ${wait}ms (attempt ${attempt}/5)`);
                await sleep(wait);
            }
        }
        throw lastError instanceof Error ? lastError : new Error(String(lastError));
    }

    /**
     * Every record of a type, following the continuation marker to exhaustion.
     *
     * No `desiredKeys`: unlike the app's feed queries (CloudKitManager.FeedKeys),
     * the migration wants every field, including the heavy assets' metadata. Asset
     * *bytes* are still fetched separately via downloadAsset().
     */
    async fetchAll(recordType: string, onPage?: (count: number) => void): Promise<CKRecord[]> {
        const records: CKRecord[] = [];
        let continuationMarker: string | undefined;

        do {
            const body: Record<string, unknown> = {
                query: { recordType },
                resultsLimit: PAGE_SIZE,
            };
            if (continuationMarker) body['continuationMarker'] = continuationMarker;

            const json = await this.post('records/query', body);

            // A record type that has never been written has no schema in this
            // environment. Treat it as empty rather than fatal — e.g. Photography
            // fields are known to be missing from the schema in both environments.
            if (json.serverErrorCode === 'BAD_REQUEST' || json.serverErrorCode === 'NOT_FOUND') {
                console.warn(`  ⚠️  ${recordType}: ${json.serverErrorCode} (${json.reason ?? 'no schema?'}) — treating as empty`);
                return records;
            }

            const page: CKRecord[] = (json.records ?? []).filter((r: CKRecord) => !r.deleted);
            records.push(...page);
            onPage?.(records.length);

            continuationMarker = json.continuationMarker ?? undefined;
        } while (continuationMarker);

        return records;
    }

    /**
     * Downloads one asset's bytes.
     *
     * `downloadURL` is a template containing a `${f}` placeholder for the served
     * filename, and the CDN derives Content-Type from that name's extension —
     * the quirk that forced the byte-sniffing in CloudKitWebServices.streamURL
     * (:141-219). Here it does not matter what we ask for, because we record the
     * real MIME type ourselves at upload time; we substitute a plain name only to
     * produce a valid URL.
     */
    async downloadAsset(asset: CKAssetValue): Promise<Buffer | null> {
        if (!asset.downloadURL) return null;
        const url = asset.downloadURL.replace('${f}', 'file');

        for (let attempt = 1; attempt <= 5; attempt++) {
            try {
                const response = await fetch(url);
                if (response.status === 429 || response.status >= 500) {
                    await sleep(2 ** attempt * 500);
                    continue;
                }
                if (!response.ok) {
                    console.warn(`  ⚠️  asset download HTTP ${response.status}`);
                    return null;
                }
                return Buffer.from(await response.arrayBuffer());
            } catch {
                if (attempt === 5) return null;
                await sleep(2 ** attempt * 500);
            }
        }
        return null;
    }
}

// ---------------------------------------------------------------------------
// Field accessors
// ---------------------------------------------------------------------------
// Web services wraps every field as { value, type }, and omits absent fields
// entirely. Everything below tolerates a missing field, which is not defensive
// padding — `orderedCrew`, `orderedCrewIDs` and `photographyEquipment` are known
// to be absent from the PhotographySubmission schema in BOTH environments, so
// those reads WILL return undefined for every photography record.

export function str(record: CKRecord, key: string): string {
    const v = record.fields[key]?.value;
    return typeof v === 'string' ? v : '';
}

export function strOrNull(record: CKRecord, key: string): string | null {
    const v = record.fields[key]?.value;
    return typeof v === 'string' && v !== '' ? v : null;
}

export function num(record: CKRecord, key: string): number | null {
    const v = record.fields[key]?.value;
    return typeof v === 'number' ? v : null;
}

/** CloudKit has no boolean type; the app stores 1/0 (and older rows, true/false). */
export function bool(record: CKRecord, key: string, fallback = false): boolean {
    const v = record.fields[key]?.value;
    if (typeof v === 'number') return v === 1;
    if (typeof v === 'boolean') return v;
    return fallback;
}

/** Timestamps arrive as epoch milliseconds. */
export function date(record: CKRecord, key: string): string | null {
    const v = record.fields[key]?.value;
    if (typeof v !== 'number') return null;
    return new Date(v).toISOString();
}

export function strList(record: CKRecord, key: string): string[] {
    const v = record.fields[key]?.value;
    if (!Array.isArray(v)) return [];
    return v.filter((x): x is string => typeof x === 'string');
}

export function asset(record: CKRecord, key: string): CKAssetValue | null {
    const v = record.fields[key]?.value;
    if (!v || typeof v !== 'object') return null;
    const a = v as CKAssetValue;
    return a.downloadURL ? a : null;
}

export function assetList(record: CKRecord, key: string): CKAssetValue[] {
    const v = record.fields[key]?.value;
    if (!Array.isArray(v)) return [];
    return v
        .filter((x): x is CKAssetValue => !!x && typeof x === 'object' && 'downloadURL' in x)
        .filter((x) => !!x.downloadURL);
}

/** Record creation time, falling back to the explicit createdDate field. */
export function createdAt(record: CKRecord): string {
    if (typeof record.created?.timestamp === 'number') {
        return new Date(record.created.timestamp).toISOString();
    }
    return date(record, 'createdDate') ?? new Date(0).toISOString();
}

/**
 * The CloudKit user record name of whoever created the record — the attribution
 * that `claim_legacy_profile()` matches on.
 *
 * NOTE: verify this during the dry run. CloudKit may return `_defaultOwner` (or
 * omit the field) for public-database records depending on container settings,
 * in which case attribution has to fall back to matching the `submittedBy`
 * display name against UserProfile records, which is lossy for duplicate names.
 * The dry run reports how many records lack a usable creator.
 */
export function creatorUserRecordName(record: CKRecord): string | null {
    const name = record.created?.userRecordName;
    if (!name || name === '_defaultOwner') return null;
    return name;
}
