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
///   - the app profile is filled in from the website profile where it's empty
///     (never overwriting what the app already has);
///   - once nothing failed, the website profile and its Verification are deleted,
///     so the person shows up once, in the app and on the website.
///
/// The email itself is relinked by the caller (verified_emails), so signing in on
/// the website with it opens the app account from then on.
///
/// Best-effort: a record this server key can't write (one the app created and
/// keeps creator-only) is reported and skipped, and the website profile is then
/// kept so nothing is lost; merging again later picks up where this left off.

import type { Env } from "./util";
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

/// Profile fields never copied: one-time or private values.
const NEVER_COPY = new Set(["verificationNonce", "userEmail", "mergedInto"]);
const COPYABLE_TYPES = new Set(["STRING", "STRING_LIST", "INT64", "DOUBLE", "TIMESTAMP"]);

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

const isEmpty = (field: Field | undefined) =>
    !field || field.value === undefined || field.value === null || field.value === "" ||
    (Array.isArray(field.value) && field.value.length === 0);

/// Profile fields the website profile has and the app profile is missing.
export function profileFill(web: Record<string, Field>, app: Record<string, Field>): Record<string, Field> {
    const out: Record<string, Field> = {};
    for (const [key, field] of Object.entries(web ?? {})) {
        if (NEVER_COPY.has(key) || !field.type || !COPYABLE_TYPES.has(field.type)) continue;
        if (!isEmpty(field) && isEmpty(app?.[key])) out[key] = field;
    }
    return out;
}

async function* allRecords(env: Env, recordType: string) {
    let marker: string | undefined;
    do {
        const page = await queryRecords(env, recordType, marker, 200);
        for (const r of page.records) yield r;
        marker = page.continuationMarker;
    } while (marker);
}

export async function mergeWebAccount(env: Env, webUser: string, appUser: string): Promise<MergeReport> {
    const report: MergeReport = { rewritten: 0, errors: [], profileDeleted: false };
    const note = (outcome: { saved: number; errors: { recordName: string; reason: string }[] }) => {
        report.rewritten += outcome.saved;
        report.errors.push(...outcome.errors.map((e) => `${e.recordName}: ${e.reason}`));
    };

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

    // Fill in the app profile from the website one, where the app's is empty.
    try {
        const [web, app] = await Promise.all([fetchUserProfile(env, webUser), fetchUserProfile(env, appUser)]);
        if (web && app) {
            const fill = profileFill(web.fields, app.fields);
            if (Object.keys(fill).length) {
                note(await modifyRecords(env, [{ operationType: "forceUpdate", record: { recordType: "UserProfile", recordName: `UserProfile_${appUser}`, fields: fill } }]));
            }
        }
    } catch (error) {
        report.errors.push(`UserProfile fill: ${error instanceof Error ? error.message : String(error)}`);
    }

    // Only once everything moved: the website account goes away, so nobody sees it twice.
    if (report.errors.length === 0) {
        try {
            await deleteRecord(env, `UserProfile_${webUser}`);
            await deleteRecord(env, `Verification_${webUser}`);
            report.profileDeleted = true;
        } catch (error) {
            report.errors.push(`delete website profile: ${error instanceof Error ? error.message : String(error)}`);
        }
    }
    return report;
}
