/// Alumni accounts (added 2026-11-20).
///
/// Alumni usually no longer have a school email, so they verify ANY address they
/// control (`purpose: "alumni"` on /v1/verify/request or /v1/web/session/request)
/// and name the school they graduated from. That makes them a member of the
/// school, but browse-only until a moderator approves them on the website's
/// admin pages:
///
///   - until then their `domain_kind` (D1 `verified_emails`, and `domainKind` on
///     their CloudKit `Verification` record) is "alumni_pending";
///   - approving changes both to "alumni", which is what the app and the website
///     read to let them post, connect and message;
///   - the nightly sweep treats a pending alum like an enthusiast (unverified).
///
/// `alumni_reviews` is the moderators' queue. It keeps the address the person
/// gave, so moderators can tell who they are, only until a decision is made.

import type { Env } from "./util";
import { json, errorResponse, nowSeconds } from "./util";
import { updateRecordFields } from "./cloudkit";
import { authorizeWebClient, type DomainMatch } from "./webSession";

/// An alum waiting for a moderator.
export const ALUMNI_PENDING_KIND = "alumni_pending";
/// An approved alum: a full member of their school.
export const ALUMNI_KIND = "alumni";

export const isAlumniKind = (kind: string | null | undefined) => kind === ALUMNI_KIND || kind === ALUMNI_PENDING_KIND;

/// The school an alum says they graduated from, if it's in the registry.
export async function alumniSchool(env: Env, schoolID: string): Promise<DomainMatch | null> {
    const id = schoolID.trim();
    if (!id) return null;
    const row = await env.DB.prepare(`SELECT id, name FROM schools WHERE id = ? AND enabled = 1`)
        .bind(id)
        .first<{ id: string; name: string }>();
    return row ? { schoolID: row.id, schoolName: row.name, kind: ALUMNI_PENDING_KIND } : null;
}

/// Whether a moderator has approved this account as an alum.
export async function isAlumniApproved(env: Env, userRecordName: string): Promise<boolean> {
    const row = await env.DB.prepare(
        `SELECT 1 AS approved FROM alumni_reviews WHERE user_record_name = ? AND approved_at IS NOT NULL`,
    )
        .bind(userRecordName)
        .first<{ approved: number }>();
    return !!row;
}

/// The kind to record for an alum who just verified: "alumni" if they were approved
/// before (verifying again, or a merged account), else "alumni_pending".
export async function alumniKindFor(env: Env, userRecordName: string): Promise<string> {
    return (await isAlumniApproved(env, userRecordName)) ? ALUMNI_KIND : ALUMNI_PENDING_KIND;
}

/// Puts an alum in the moderators' queue. Re-running keeps an earlier decision.
export async function queueAlumniReview(env: Env, userRecordName: string, schoolID: string, email: string): Promise<void> {
    await env.DB.prepare(
        `INSERT INTO alumni_reviews (user_record_name, school_id, email, requested_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(user_record_name) DO UPDATE SET
           school_id = excluded.school_id,
           email = CASE WHEN alumni_reviews.approved_at IS NULL THEN excluded.email ELSE '' END,
           requested_at = CASE WHEN alumni_reviews.approved_at IS NULL THEN excluded.requested_at ELSE alumni_reviews.requested_at END,
           denied_at = CASE WHEN alumni_reviews.approved_at IS NULL THEN NULL ELSE alumni_reviews.denied_at END`,
    )
        .bind(userRecordName, schoolID, email.slice(0, 254), nowSeconds())
        .run();
}

/// Moves a merged website account's review onto the app account it became.
export async function moveAlumniReview(env: Env, fromUser: string, toUser: string): Promise<void> {
    await env.DB.prepare(`UPDATE OR IGNORE alumni_reviews SET user_record_name = ? WHERE user_record_name = ?`)
        .bind(toUser, fromUser)
        .run();
}

/// Website admin routes (WEB_CLIENT_TOKEN; the website checks the moderator):
///   POST /v1/web/alumni/pending                              -> { alumni: [...] }
///   POST /v1/web/alumni/decide { userRecordName, approve, by } -> { ok }
export async function handleAlumni(request: Request, env: Env, pathname: string): Promise<Response> {
    const denied = authorizeWebClient(request, env);
    if (denied) return denied;

    if (pathname === "/v1/web/alumni/pending") {
        const rows = await env.DB.prepare(
            `SELECT r.user_record_name, r.school_id, s.name AS school_name, r.email, r.requested_at
             FROM alumni_reviews r LEFT JOIN schools s ON s.id = r.school_id
             WHERE r.approved_at IS NULL AND r.denied_at IS NULL
             ORDER BY r.requested_at`,
        ).all<{ user_record_name: string; school_id: string; school_name: string | null; email: string; requested_at: number }>();
        return json({
            alumni: (rows.results ?? []).map((r) => ({
                userRecordName: r.user_record_name,
                schoolID: r.school_id,
                schoolName: r.school_name ?? "",
                email: r.email,
                requestedAt: r.requested_at,
            })),
        });
    }

    if (pathname === "/v1/web/alumni/decide") {
        let body: Record<string, unknown>;
        try {
            body = (await request.json()) as Record<string, unknown>;
        } catch {
            return errorResponse("bad_request", "Malformed body.", 400);
        }
        const userRecordName = String(body.userRecordName ?? "").trim();
        const by = String(body.by ?? "").trim().slice(0, 254);
        if (!userRecordName) return errorResponse("bad_request", "Missing userRecordName.", 400);
        const now = nowSeconds();

        if (body.approve === true) {
            const updated = await env.DB.prepare(
                `UPDATE alumni_reviews SET approved_at = ?, approved_by = ?, denied_at = NULL, email = ''
                 WHERE user_record_name = ?`,
            )
                .bind(now, by, userRecordName)
                .run();
            if (!updated.meta?.changes) return errorResponse("not_found", "No such alum.", 404);
            await env.DB.prepare(
                `UPDATE verified_emails SET domain_kind = ? WHERE user_record_name = ? AND domain_kind = ?`,
            )
                .bind(ALUMNI_KIND, userRecordName, ALUMNI_PENDING_KIND)
                .run();
            // What the app and the website read. The approval itself is in D1, so a
            // failed write here is reported and can be retried by approving again.
            const outcome = await updateRecordFields(env, [
                { recordType: "Verification", recordName: `Verification_${userRecordName}`, fields: { domainKind: { value: ALUMNI_KIND } } },
            ]);
            if (outcome.errors.length) {
                console.error(`alumni approve ${userRecordName}: Verification not updated`, outcome.errors);
                return errorResponse("partial", "Approved, but the account didn't update yet. Approve again in a moment.", 502);
            }
            return json({ ok: true });
        }

        // Turned down: they stay browse-only and drop off the queue.
        const updated = await env.DB.prepare(
            `UPDATE alumni_reviews SET denied_at = ?, approved_by = ?, email = '' WHERE user_record_name = ? AND approved_at IS NULL`,
        )
            .bind(now, by, userRecordName)
            .run();
        if (!updated.meta?.changes) return errorResponse("not_found", "No such alum waiting.", 404);
        return json({ ok: true });
    }

    return errorResponse("not_found", "Unknown endpoint.", 404);
}
