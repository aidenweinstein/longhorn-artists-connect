/// One-off migration: stamps `schoolID` onto submission records created before
/// the app split feeds by school.
///
/// This must run to completion BEFORE shipping a build that filters feeds on
/// `schoolID`. CloudKit has no way to query for "this field is nil", so an
/// unstamped record isn't merely misfiled — it's invisible to every school's
/// feed, including the one it belongs to.
///
/// A record's school comes from its creator's verified school in D1. Creators
/// with no verification on file are the grandfathered accounts that are exempt
/// from verifying by design, so they fall back to BACKFILL_DEFAULT_SCHOOL.
///
/// Run it through the admin endpoint (see README, "Backfilling schoolID"):
/// dry run first, confirm the per-school tally looks right, then run for real
/// and confirm a second pass reports zero left to stamp.

import { Env } from "./util";
import { queryRecords, updateRecordFields, RecordFieldUpdate } from "./cloudkit";

/// The seven live submission types. The legacy `Submission` type is left alone
/// deliberately: the app's legacy read path doesn't filter by school, so
/// stamping it would achieve nothing.
const BACKFILLED_RECORD_TYPES = [
    "FilmSubmission",
    "MusicSubmission",
    "ReelSubmission",
    "ProjectSubmission",
    "EventSubmission",
    "PhotographySubmission",
    "DesignSubmission",
];

/// Records per records/modify call. CloudKit caps a modify at 200 operations;
/// 100 leaves headroom.
const WRITE_BATCH = 100;

/// Records scanned per HTTP call, keeping one invocation inside the Worker's
/// CPU and subrequest budget. The driver script loops on the returned cursor.
const DEFAULT_MAX_RECORDS = 1000;

const QUERY_PAGE = 200;

export interface BackfillCursor {
    recordType: string;
    marker?: string;
}

export interface BackfillResult {
    dryRun: boolean;
    scanned: number;
    /// Records this pass stamped (or would have stamped, on a dry run).
    stamped: number;
    /// Records that already carried a schoolID and were left alone.
    alreadyStamped: number;
    failed: number;
    /// Non-null when there is more to do; pass it back on the next call.
    cursor: BackfillCursor | null;
    /// What this pass assigned, per school — the number to sanity-check before
    /// running for real.
    bySchool: Record<string, number>;
    /// Record types whose query failed. MUST be empty before you treat the
    /// backfill as complete: a type skipped here still has unstamped records,
    /// which the new filter would hide.
    skippedTypes: { recordType: string; reason: string }[];
}

export async function runBackfill(
    env: Env,
    options: { dryRun: boolean; cursor?: BackfillCursor; maxRecords?: number },
): Promise<BackfillResult> {
    const defaultSchool = env.BACKFILL_DEFAULT_SCHOOL || "ut-austin";
    const maxRecords = options.maxRecords ?? DEFAULT_MAX_RECORDS;

    const startIndex = options.cursor
        ? BACKFILLED_RECORD_TYPES.indexOf(options.cursor.recordType)
        : 0;
    if (startIndex < 0) {
        throw new Error(`backfill: unknown record type in cursor: ${options.cursor?.recordType}`);
    }

    const result: BackfillResult = {
        dryRun: options.dryRun,
        scanned: 0,
        stamped: 0,
        alreadyStamped: 0,
        failed: 0,
        cursor: null,
        bySchool: {},
        skippedTypes: [],
    };

    /// Creator -> school, so a prolific poster costs one D1 read per pass.
    const schoolCache = new Map<string, string>();

    for (let index = startIndex; index < BACKFILLED_RECORD_TYPES.length; index++) {
        const recordType = BACKFILLED_RECORD_TYPES[index];
        let marker = index === startIndex ? options.cursor?.marker : undefined;

        do {
            let page;
            try {
                page = await queryRecords(env, recordType, marker, QUERY_PAGE, ["schoolID"]);
            } catch (error) {
                // A record type that doesn't exist in this environment yet is
                // expected and harmless; a transient failure is NOT, and either
                // way it's reported rather than swallowed.
                const reason = error instanceof Error ? error.message : String(error);
                console.error(`backfill: query ${recordType} failed — ${reason}`);
                result.skippedTypes.push({ recordType, reason });
                break;
            }
            marker = page.continuationMarker;

            const updates: RecordFieldUpdate[] = [];
            for (const record of page.records) {
                result.scanned++;

                const existing = record.fields?.schoolID?.value;
                if (typeof existing === "string" && existing.length > 0) {
                    result.alreadyStamped++;
                    continue;
                }

                const creator: string | undefined = record.created?.userRecordName;
                const schoolID = creator
                    ? await schoolFor(env, creator, defaultSchool, schoolCache)
                    : defaultSchool;

                result.bySchool[schoolID] = (result.bySchool[schoolID] ?? 0) + 1;
                updates.push({
                    recordName: record.recordName,
                    recordType,
                    fields: { schoolID: { value: schoolID } },
                });
            }

            if (options.dryRun) {
                result.stamped += updates.length;
            } else {
                for (let i = 0; i < updates.length; i += WRITE_BATCH) {
                    const outcome = await updateRecordFields(env, updates.slice(i, i + WRITE_BATCH));
                    result.stamped += outcome.saved;
                    result.failed += outcome.errors.length;
                    for (const failure of outcome.errors) {
                        console.error(`backfill: ${failure.recordName} — ${failure.reason}`);
                    }
                }
            }

            if (result.scanned >= maxRecords) {
                result.cursor = nextCursor(recordType, marker, index);
                return result;
            }
        } while (marker);
    }

    return result;
}

/// Where the next call should resume: mid-type if the page had a marker,
/// otherwise the start of the following type, otherwise done.
function nextCursor(
    recordType: string,
    marker: string | undefined,
    index: number,
): BackfillCursor | null {
    if (marker) return { recordType, marker };
    if (index + 1 < BACKFILLED_RECORD_TYPES.length) {
        return { recordType: BACKFILLED_RECORD_TYPES[index + 1] };
    }
    return null;
}

async function schoolFor(
    env: Env,
    userRecordName: string,
    fallback: string,
    cache: Map<string, string>,
): Promise<string> {
    const cached = cache.get(userRecordName);
    if (cached) return cached;

    const row = await env.DB.prepare(
        `SELECT school_id FROM verified_emails
         WHERE user_record_name = ? AND revoked_at IS NULL`,
    )
        .bind(userRecordName)
        .first<{ school_id: string }>();

    const school = row?.school_id ?? fallback;
    cache.set(userRecordName, school);
    return school;
}
