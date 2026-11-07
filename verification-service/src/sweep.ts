/// Nightly sweep.
///
/// CloudKit's public-database permissions are only World / Authenticated /
/// Creator — there is no way to express "only verified users may create a
/// FilmSubmission". The in-app gate is therefore cosmetic, and this cron is
/// what actually enforces the rule: it walks the public record types and finds
/// posts whose creator has no verification on file.
///
/// Defaults to SWEEP_ACTION="report", which only records findings. Review
/// `sweep_findings` for a few nights before switching to "delete" — a bad
/// registry entry would otherwise quietly delete legitimate work.

import { Env, nowSeconds } from "./util";
import { queryRecords, deleteRecord } from "./cloudkit";

const SWEPT_RECORD_TYPES = [
    "FilmSubmission",
    "MusicSubmission",
    "ReelSubmission",
    "ProjectSubmission",
    "EventSubmission",
    "PhotographySubmission",
    "DesignSubmission",
    "Submission", // legacy type still present in the container
];

/// Safety valve: if a single pass would flag more than this share of records,
/// something is wrong (expired key, empty registry, bad migration) and we bail
/// rather than mass-delete.
const MAX_FLAG_RATIO = 0.5;
const MIN_RECORDS_FOR_RATIO_CHECK = 20;

/// Why a record was flagged.
///
/// `creator-unverified` is the enforcement case: the creator has no
/// verification on file, so the post shouldn't exist. `school-mismatch` is an
/// integrity case: the post claims a school that isn't its creator's. Because
/// `schoolID` is written by the client it can say anything, and the only place
/// the lie is visible is here, against the server-written `Verification`.
export type SweepReason = "creator-unverified" | "school-mismatch";

/// What the service knows about a creator, from D1.
export interface CreatorVerification {
    verified: boolean;
    /// The creator's verified school slug, or null when unverified.
    schoolID: string | null;
}

/// Decides whether one record is a finding, and why.
///
/// Pure, and exported so the rules are testable without a CloudKit key or a
/// live D1 — the sweep can delete real work, so these rules get unit tests
/// rather than a production dry run.
///
/// A record is *not* flagged for a missing `schoolID`. Absent is not the same
/// as wrong: the field is unstamped on every record until the backfill runs,
/// and treating unstamped as a mismatch would flag the entire container on the
/// first night. Only a stamped-and-different value is a finding.
export function classifyRecord(
    record: any,
    verification: CreatorVerification,
    grandfatherBefore: number,
): SweepReason | null {
    const createdAt: number = record.created?.timestamp ?? 0;

    // Grandfather anything created before verification shipped.
    if (grandfatherBefore > 0 && createdAt > 0 && createdAt / 1000 < grandfatherBefore) {
        return null;
    }
    if (!record.created?.userRecordName) return null;

    if (!verification.verified) return "creator-unverified";

    const stamped = record.fields?.schoolID?.value;
    if (
        typeof stamped === "string" &&
        stamped !== "" &&
        verification.schoolID != null &&
        stamped !== verification.schoolID
    ) {
        return "school-mismatch";
    }

    return null;
}

/// A mismatch is reported, never deleted — even when SWEEP_ACTION is "delete".
///
/// The post is real work by a real verified student; the wrong thing about it
/// is one string. Deleting it would punish the author for a field they may not
/// have set deliberately (switching schools, a stale cached verification). The
/// remedy is to correct `schoolID`, which the backfill endpoint can already do.
function isDeletable(reason: SweepReason): boolean {
    return reason === "creator-unverified";
}

export async function runSweep(env: Env): Promise<void> {
    const startedAt = nowSeconds();
    const grandfatherBefore = Number(env.SWEEP_GRANDFATHER_BEFORE ?? "0");
    const action = env.SWEEP_ACTION === "delete" ? "delete" : "report";

    let scanned = 0;
    const flagged: {
        recordType: string;
        recordName: string;
        creator: string;
        reason: SweepReason;
    }[] = [];

    for (const recordType of SWEPT_RECORD_TYPES) {
        let marker: string | undefined;
        do {
            let page;
            try {
                // Deliberately no `desiredKeys`: narrowing to ["schoolID"] would
                // be cheaper, but CloudKit errors on a field that doesn't exist
                // in the deployed schema, and `schoolID` isn't created yet. That
                // error would skip the whole record type and silently stop
                // enforcing. Revisit once the field exists in both environments.
                page = await queryRecords(env, recordType, marker);
            } catch (error) {
                // A missing record type is expected for legacy names; log and move on.
                console.error(`sweep: query ${recordType} failed`, error);
                break;
            }

            for (const record of page.records) {
                scanned++;
                const creator: string | undefined = record.created?.userRecordName;
                const verification = creator
                    ? await creatorVerification(env, creator)
                    : { verified: false, schoolID: null };

                const reason = classifyRecord(record, verification, grandfatherBefore);
                if (reason && creator) {
                    flagged.push({ recordType, recordName: record.recordName, creator, reason });
                }
            }

            marker = page.continuationMarker;
        } while (marker);
    }

    // The ratio guard exists to stop a mass delete, so it counts only the
    // findings that can delete. Mismatches can't, and letting them trip the
    // abort would mean a schoolID bug suppressed the enforcement sweep too.
    const deletable = flagged.filter((item) => isDeletable(item.reason));
    if (
        scanned >= MIN_RECORDS_FOR_RATIO_CHECK &&
        deletable.length / scanned > MAX_FLAG_RATIO
    ) {
        console.error(
            `sweep: ABORTED — would flag ${deletable.length}/${scanned} records as unverified, above the ${MAX_FLAG_RATIO} safety ratio`,
        );
        return;
    }

    for (const item of flagged) {
        let resolved = "report";
        if (action === "delete" && isDeletable(item.reason)) {
            try {
                await deleteRecord(env, item.recordName);
                resolved = "deleted";
            } catch (error) {
                console.error(`sweep: delete ${item.recordName} failed`, error);
                resolved = "skipped";
            }
        }

        await env.DB.prepare(
            `INSERT INTO sweep_findings (found_at, record_type, record_name, creator, action, reason)
             VALUES (?, ?, ?, ?, ?, ?)`,
        )
            .bind(startedAt, item.recordType, item.recordName, item.creator, resolved, item.reason)
            .run();
    }

    // Housekeeping: expired codes and stale rate-limit buckets.
    await env.DB.batch([
        env.DB.prepare(`DELETE FROM pending_verifications WHERE expires_at < ?`).bind(
            startedAt - 86_400,
        ),
        env.DB.prepare(`DELETE FROM pending_web_sessions WHERE expires_at < ?`).bind(
            startedAt - 86_400,
        ),
        env.DB.prepare(`DELETE FROM rate_limits WHERE window_start < ?`).bind(startedAt - 86_400),
    ]);

    const mismatches = flagged.length - deletable.length;
    console.log(
        `sweep: scanned=${scanned} unverified=${deletable.length} schoolMismatch=${mismatches} action=${action} took=${nowSeconds() - startedAt}s`,
    );
}

const verifiedCache = new Map<string, CreatorVerification>();

/// One D1 row per creator per sweep, cached because a prolific poster would
/// otherwise be looked up once per post.
async function creatorVerification(env: Env, userRecordName: string): Promise<CreatorVerification> {
    const cached = verifiedCache.get(userRecordName);
    if (cached !== undefined) return cached;

    const row = await env.DB.prepare(
        `SELECT school_id FROM verified_emails WHERE user_record_name = ? AND revoked_at IS NULL`,
    )
        .bind(userRecordName)
        .first<{ school_id: string }>();

    const verification: CreatorVerification = row
        ? { verified: true, schoolID: row.school_id }
        : { verified: false, schoolID: null };
    verifiedCache.set(userRecordName, verification);
    return verification;
}
