/// Moving a website account into an app account (added 2026-11-19).
///
/// Someone who made an account on the website and later verifies the same email
/// in the app has proved both things at once: the email code proves the address,
/// and the nonce on their UserProfile proves the iCloud account. That's when
/// handleVerifyConfirm calls this, and their website account `web_<id>` becomes
/// part of the app account:
///
///   - every post, credit, connection, conversation and message that names the
///     website account is rewritten to name the app account;
///   - the app copies the website profile into its own UserProfile record
///     (StudentVerificationManager.confirmCode, then
///     UserProfileModel.adoptWebsiteProfile). This server can't: the app's record
///     is Creator-only, and CloudKit answers ACCESS_DENIED to this key;
///   - the app then calls /v1/verify/merge/finish (finishMerge below), and once
///     the app profile is a real account and nothing failed, the website profile
///     and its Verification are deleted, so the person shows up once.
///
/// The merge is tracked in D1 (web_merges) from the first step to the last, so
/// an app that crashed between copying and finishing, or an account merged by
/// the website's Sign in with Apple, is finished by the nightly cron instead
/// (finishPendingMerges), and a later /verify/confirm can still name the
/// website account to the app.
///
/// The email itself is relinked by the caller (verified_emails), so signing in on
/// the website with it opens the app account from then on.
///
/// Best-effort: a record this server key can't write (one the app created and
/// keeps creator-only) is reported and skipped, and the website profile is then
/// kept so nothing is lost; finishing again later picks up where this left off.

import type { Env } from "./util";
import { nowSeconds } from "./util";
import { deleteRecord, fetchUserProfile, modifyRecords, queryRecords } from "./cloudkit";

/// Every record type that can name a user.
const TYPES = [
    "FilmSubmission",
    "MusicSubmission",
    "ReelSubmission",
    "ProjectSubmission",
    "EventSubmission",
    "PhotographySubmission",
    "DesignSubmission",
    "Submission",
    "Conversation",
    "Message",
];

export interface MergeReport {
    rewritten: number;
    errors: string[];
    profileDeleted: boolean;
}

type Field = { value: unknown; type?: string };

/// The field with every mention of `from` replaced by `to`, or null when it doesn't mention it.
export function rewriteField(field: Field, from: string, to: string): Field | null {
    const swap = (v: unknown) =>
        v === from ? to : v === `UserProfile_${from}` ? `UserProfile_${to}` : v;
    if (typeof field.value === "string") {
        const next = swap(field.value);
        return next === field.value ? null : { ...field, value: next };
    }
    if (Array.isArray(field.value)) {
        const next = field.value.map(swap);
        return next.some((v, i) => v !== (field.value as unknown[])[i]) ? { ...field, value: next } : null;
    }
    return null;
}

/// Only the fields of `fields` that change.
export function rewriteFields(fields: Record<string, Field>, from: string, to: string): Record<string, Field> {
    const out: Record<string, Field> = {};
    for (const [key, field] of Object.entries(fields ?? {})) {
        const next = rewriteField(field, from, to);
        if (next) out[key] = next;
    }
    return out;
}

/// Whether a UserProfile record is a finished account rather than the stub the
/// app writes to hold the verification nonce. Every completed app save writes
/// `isUTStudent`, as does the website's account creation; the app's own
/// loadFromCloudKit applies the same test.
export function isCompleteProfile(profile: { fields?: Record<string, Field> } | null | undefined): boolean {
    const value = profile?.fields?.isUTStudent?.value;
    return value !== undefined && value !== null;
}

async function* allRecords(env: Env, recordType: string) {
    let marker: string | undefined;
    do {
        const page = await queryRecords(env, recordType, marker, 200);
        for (const r of page.records) yield r;
        marker = page.continuationMarker;
    } while (marker);
}

// MARK: - Tracking

export interface PendingMerge {
    webUser: string;
    appUser: string;
}

/// Remembers that `webUser` is being merged into `appUser`. Re-running is harmless.
async function trackMerge(env: Env, webUser: string, appUser: string): Promise<void> {
    await env.DB.prepare(
        `INSERT INTO web_merges (web_user, app_user, requested_at)
         VALUES (?, ?, ?)
         ON CONFLICT(web_user) DO UPDATE SET
           app_user = excluded.app_user,
           finished_at = NULL`,
    )
        .bind(webUser, appUser, nowSeconds())
        .run();
}

/// The website account still being merged into `appUser`, if any.
export async function pendingMergeFor(env: Env, appUser: string): Promise<PendingMerge | null> {
    const row = await env.DB.prepare(
        `SELECT web_user FROM web_merges WHERE app_user = ? AND finished_at IS NULL ORDER BY requested_at DESC LIMIT 1`,
    )
        .bind(appUser)
        .first<{ web_user: string }>();
    return row ? { webUser: row.web_user, appUser } : null;
}

/// Whether `webUser` is on record as merging into `appUser` and not finished.
export async function isPendingMerge(env: Env, webUser: string, appUser: string): Promise<boolean> {
    const row = await env.DB.prepare(
        `SELECT 1 AS present FROM web_merges WHERE web_user = ? AND app_user = ? AND finished_at IS NULL`,
    )
        .bind(webUser, appUser)
        .first<{ present: number }>();
    return !!row;
}

// MARK: - Merging

/// Rewrites every record naming the website account to name the app account,
/// and records the merge as in progress. With `deleteProfile`, also removes the
/// website profile and its Verification once nothing failed; leave it off while
/// the app still has to copy that profile (see the header).
export async function mergeWebAccount(
    env: Env,
    webUser: string,
    appUser: string,
    options: { deleteProfile?: boolean } = {},
): Promise<MergeReport> {
    const report: MergeReport = { rewritten: 0, errors: [], profileDeleted: false };
    const note = (outcome: { saved: number; errors: { recordName: string; reason: string }[] }) => {
        report.rewritten += outcome.saved;
        report.errors.push(...outcome.errors.map((e) => `${e.recordName}: ${e.reason}`));
    };

    await trackMerge(env, webUser, appUser);

    // Posts, credits, conversations and messages: rewrite the fields that name the website account.
    for (const recordType of TYPES) {
        try {
            const updates: unknown[] = [];
            for await (const r of allRecords(env, recordType)) {
                const changed = rewriteFields(r.fields, webUser, appUser);
                if (Object.keys(changed).length) {
                    updates.push({ operationType: "forceUpdate", record: { recordType, recordName: r.recordName, fields: changed } });
                }
            }
            for (let i = 0; i < updates.length; i += 100) note(await modifyRecords(env, updates.slice(i, i + 100)));
        } catch (error) {
            // A type missing from this environment's schema is fine; anything else is reported.
            const message = error instanceof Error ? error.message : String(error);
            if (!/did not find record type|BAD_REQUEST/i.test(message)) report.errors.push(`${recordType}: ${message}`);
        }
    }

    // Connections are named Connection_<from>_<to>, so each one is re-made under its new name.
    try {
        const operations: unknown[] = [];
        for await (const r of allRecords(env, "Connection")) {
            const changed = rewriteFields(r.fields, webUser, appUser);
            if (!Object.keys(changed).length) continue;
            const fields = { ...r.fields, ...changed };
            const from = String(fields.fromUserID?.value ?? "");
            const to = String(fields.toUserID?.value ?? "");
            if (!from || !to || from === to) {
                operations.push({ operationType: "forceDelete", record: { recordName: r.recordName } });
                continue;
            }
            operations.push({ operationType: "forceReplace", record: { recordType: "Connection", recordName: `Connection_${from}_${to}`, fields } });
            operations.push({ operationType: "forceDelete", record: { recordName: r.recordName } });
        }
        for (let i = 0; i < operations.length; i += 100) note(await modifyRecords(env, operations.slice(i, i + 100)));
    } catch (error) {
        report.errors.push(`Connection: ${error instanceof Error ? error.message : String(error)}`);
    }

    // Only once everything moved: the website account goes away, so nobody sees it twice.
    if (options.deleteProfile && report.errors.length === 0) {
        try {
            await deleteRecord(env, `UserProfile_${webUser}`);
            await deleteRecord(env, `Verification_${webUser}`);
            report.profileDeleted = true;
            await env.DB.prepare(`UPDATE web_merges SET finished_at = ? WHERE web_user = ?`).bind(nowSeconds(), webUser).run();
        } catch (error) {
            report.errors.push(`delete website profile: ${error instanceof Error ? error.message : String(error)}`);
        }
    }
    return report;
}

export type FinishResult =
    | { status: "finished"; report: MergeReport }
    | { status: "incomplete"; report: MergeReport }
    /// The app profile is still the nonce stub: the app hasn't copied the website profile yet.
    | { status: "profile_not_ready" }
    /// Nothing left to do: the website profile is already gone.
    | { status: "already_finished" };

/// The last step of a merge, once the app has copied the website profile into
/// its own record: moves anything that still names the website account, then
/// deletes the website profile. Refuses while the app profile is still a stub,
/// so a premature call (or a stranger's) can't lose the profile.
export async function finishMerge(env: Env, webUser: string, appUser: string): Promise<FinishResult> {
    const [web, app] = await Promise.all([fetchUserProfile(env, webUser), fetchUserProfile(env, appUser)]);
    if (!web) {
        await env.DB.prepare(`UPDATE web_merges SET finished_at = COALESCE(finished_at, ?) WHERE web_user = ?`)
            .bind(nowSeconds(), webUser)
            .run();
        return { status: "already_finished" };
    }
    if (!isCompleteProfile(app)) return { status: "profile_not_ready" };
    const report = await mergeWebAccount(env, webUser, appUser, { deleteProfile: true });
    return { status: report.profileDeleted ? "finished" : "incomplete", report };
}

/// Nightly: finishes merges the app never got to finish itself, wherever the
/// app profile has since become a real account (a crash after the copy, an
/// account the person completed in the app's Create Account flow, or a merge
/// started by the website's Sign in with Apple).
export async function finishPendingMerges(env: Env): Promise<void> {
    const rows = await env.DB.prepare(
        `SELECT web_user, app_user FROM web_merges WHERE finished_at IS NULL ORDER BY requested_at LIMIT 50`,
    ).all<{ web_user: string; app_user: string }>();
    for (const row of rows.results ?? []) {
        try {
            const result = await finishMerge(env, row.web_user, row.app_user);
            if (result.status === "incomplete") {
                console.error(`merge ${row.web_user} -> ${row.app_user} still incomplete:`, result.report.errors.slice(0, 20));
            } else {
                console.log(`merge ${row.web_user} -> ${row.app_user}: ${result.status}`);
            }
        } catch (error) {
            console.error(`merge ${row.web_user} -> ${row.app_user} failed`, error);
        }
    }
}
