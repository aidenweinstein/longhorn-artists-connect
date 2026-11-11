/// Student verification service.
///
/// Routes:
///   GET  /v1/health
///   GET  /v1/schools?q=          search the school registry
///   POST /v1/verify/request      { email, userRecordName } -> { pendingID, nonce }
///   POST /v1/verify/confirm      { pendingID, code }       -> { verified, school }
///   GET  /v1/verify/status?user= has this account been verified
///   POST /v1/web/session/request website sign-in, see src/webSession.ts
///   POST /v1/web/session/confirm
///   POST /v1/web/people/*         People pages, see src/people.ts
///   POST /v1/admin/backfill-schools   one-off schoolID migration (ADMIN_TOKEN)
///
/// Codes are generated and compared here and nowhere else. The client never
/// sees anything it could use to mark itself verified.

import {
    Env,
    json,
    errorResponse,
    nowSeconds,
    hmacHex,
    constantTimeEqual,
    randomCode,
    randomToken,
    normalizeEmail,
    domainOf,
    domainCandidates,
    checkAllRateLimits,
    clientIP,
} from "./util";
import { sendVerificationCode } from "./email";
import { fetchUserProfile, writeVerificationRecord, clearProfileNonce } from "./cloudkit";
import { runSweep } from "./sweep";
import { runBackfill, BackfillCursor } from "./backfill";
import { handleWebSessionRequest, handleWebSessionConfirm } from "./webSession";
import { handlePeople } from "./people";

const CODE_TTL_SECONDS = 600; // 10 minutes
const MAX_CODE_ATTEMPTS = 5;

export default {
    async fetch(request: Request, env: Env): Promise<Response> {
        const url = new URL(request.url);

        try {
            if (url.pathname === "/v1/health") {
                return json({ ok: true });
            }
            if (url.pathname === "/v1/schools" && request.method === "GET") {
                return await handleSchoolSearch(url, env);
            }
            if (url.pathname === "/v1/verify/request" && request.method === "POST") {
                return await handleVerifyRequest(request, env);
            }
            if (url.pathname === "/v1/verify/confirm" && request.method === "POST") {
                return await handleVerifyConfirm(request, env);
            }
            if (url.pathname === "/v1/verify/status" && request.method === "GET") {
                return await handleStatus(url, env);
            }
            if (url.pathname === "/v1/web/session/request" && request.method === "POST") {
                return await handleWebSessionRequest(request, env, lookupDomain);
            }
            if (url.pathname === "/v1/web/session/confirm" && request.method === "POST") {
                return await handleWebSessionConfirm(request, env);
            }
            if (url.pathname.startsWith("/v1/web/people/") && request.method === "POST") {
                return await handlePeople(request, env, url.pathname);
            }
            if (url.pathname === "/v1/admin/backfill-schools" && request.method === "POST") {
                return await handleSchoolBackfill(request, env);
            }
            return errorResponse("not_found", "Unknown endpoint.", 404);
        } catch (error) {
            // Never leak internals to the client; the detail goes to the log.
            console.error("unhandled", error);
            return errorResponse("internal", "Something went wrong. Try again.", 500);
        }
    },

    async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
        ctx.waitUntil(runSweep(env));
    },
};

// MARK: - School registry

async function handleSchoolSearch(url: URL, env: Env): Promise<Response> {
    const query = (url.searchParams.get("q") ?? "").trim();
    if (query.length < 2) {
        return json({ schools: [] });
    }

    const rows = await env.DB.prepare(
        `SELECT id, name, short_name, state FROM schools
         WHERE enabled = 1 AND (name LIKE ?1 OR short_name LIKE ?1)
         ORDER BY name LIMIT 25`,
    )
        .bind(`%${query}%`)
        .all<{ id: string; name: string; short_name: string | null; state: string | null }>();

    return json({
        schools: (rows.results ?? []).map((row) => ({
            id: row.id,
            name: row.name,
            shortName: row.short_name,
            state: row.state,
        })),
    });
}

// MARK: - Request a code

async function handleVerifyRequest(request: Request, env: Env): Promise<Response> {
    const body = await readJSON(request);
    if (!body) return errorResponse("bad_request", "Malformed body.", 400);

    const email = normalizeEmail(String(body.email ?? ""));
    const userRecordName = String(body.userRecordName ?? "").trim();
    // Enthusiast accounts confirm any address they control, not a school one.
    // They get no school and can't post, so the registry check doesn't apply.
    const isEnthusiast = body.purpose === "enthusiast";

    if (!email) return errorResponse("invalid_email", "That doesn't look like an email address.", 400);
    if (!userRecordName) return errorResponse("bad_request", "Missing userRecordName.", 400);

    const domain = domainOf(email);
    const emailHash = await hmacHex(env.CODE_PEPPER, `email:${email}`);

    // Rate limits, cheapest dimension first. Per-domain is what stops one
    // school being used to burn the sending reputation for everyone else.
    const limited = await checkAllRateLimits(env, [
        { dimension: "ip", value: clientIP(request), limit: 10, windowSeconds: 3600 },
        { dimension: "email", value: emailHash, limit: 5, windowSeconds: 3600 },
        { dimension: "user", value: userRecordName, limit: 10, windowSeconds: 3600 },
        { dimension: "domain", value: domain, limit: 200, windowSeconds: 3600 },
    ]);
    if (limited) {
        return errorResponse("rate_limited", "Too many attempts. Try again later.", 429);
    }

    // Domain must resolve to a school in the registry (except for enthusiasts).
    const match: DomainMatch | null = isEnthusiast
        ? { schoolID: "", schoolName: "Nexus", kind: "enthusiast" }
        : await lookupDomain(env, domain);
    if (!match) {
        return errorResponse(
            "unsupported_domain",
            "We don't recognise that school's email domain yet.",
            422,
        );
    }
    if (match.kind === "alumni") {
        return errorResponse(
            "alumni_domain",
            "Alumni addresses aren't eligible. Use your student email.",
            422,
        );
    }

    // One account per address.
    const existing = await env.DB.prepare(
        `SELECT user_record_name FROM verified_emails WHERE email_hash = ? AND revoked_at IS NULL`,
    )
        .bind(emailHash)
        .first<{ user_record_name: string }>();
    if (existing && existing.user_record_name !== userRecordName) {
        return errorResponse("email_taken", "That email is already linked to another account.", 409);
    }

    const code = randomCode();
    const pendingID = randomToken();
    const nonce = randomToken();
    const now = nowSeconds();

    await env.DB.prepare(
        `INSERT INTO pending_verifications
           (id, email_normalized, email_hash, code_hash, school_id, domain_kind,
            user_record_name, nonce, attempts, created_at, expires_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)`,
    )
        .bind(
            pendingID,
            email,
            emailHash,
            await hmacHex(env.CODE_PEPPER, `code:${pendingID}:${code}`),
            match.schoolID,
            match.kind,
            userRecordName,
            nonce,
            now,
            now + CODE_TTL_SECONDS,
        )
        .run();

    await sendVerificationCode(env, { to: email, code, schoolName: match.schoolName });

    return json({
        pendingID,
        nonce,
        expiresAt: now + CODE_TTL_SECONDS,
        school: { id: match.schoolID, name: match.schoolName },
    });
}

// MARK: - Confirm a code

async function handleVerifyConfirm(request: Request, env: Env): Promise<Response> {
    const body = await readJSON(request);
    if (!body) return errorResponse("bad_request", "Malformed body.", 400);

    const pendingID = String(body.pendingID ?? "").trim();
    const code = String(body.code ?? "").trim();
    if (!pendingID || !/^\d{6}$/.test(code)) {
        return errorResponse("bad_request", "Missing or malformed code.", 400);
    }

    if (await checkAllRateLimits(env, [
        { dimension: "confirm_ip", value: clientIP(request), limit: 20, windowSeconds: 3600 },
    ])) {
        return errorResponse("rate_limited", "Too many attempts. Try again later.", 429);
    }

    const pending = await env.DB.prepare(
        `SELECT * FROM pending_verifications WHERE id = ?`,
    )
        .bind(pendingID)
        .first<any>();

    if (!pending) return errorResponse("invalid_code", "That code isn't valid.", 400);
    if (pending.consumed_at) return errorResponse("invalid_code", "That code was already used.", 400);
    if (pending.expires_at < nowSeconds()) {
        return errorResponse("expired_code", "That code expired. Request a new one.", 400);
    }
    if (pending.attempts >= MAX_CODE_ATTEMPTS) {
        return errorResponse("too_many_attempts", "Too many wrong codes. Request a new one.", 429);
    }

    await env.DB.prepare(`UPDATE pending_verifications SET attempts = attempts + 1 WHERE id = ?`)
        .bind(pendingID)
        .run();

    const expected = await hmacHex(env.CODE_PEPPER, `code:${pendingID}:${code}`);
    if (!constantTimeEqual(expected, pending.code_hash)) {
        return errorResponse("invalid_code", "That code isn't valid.", 400);
    }

    // Ownership proof: the client claimed a CloudKit user at /request and was
    // handed a nonce. Only the owner of that account can write the nonce onto
    // its own UserProfile record (Creator-scoped). Reading it back here is what
    // stops someone verifying an account that isn't theirs.
    const profile = await fetchUserProfile(env, pending.user_record_name);
    if (!profile) {
        return errorResponse("profile_not_found", "Couldn't find your profile. Try again.", 409);
    }
    const writtenNonce = profile.fields?.verificationNonce?.value ?? "";
    if (writtenNonce !== pending.nonce) {
        return errorResponse("ownership_unproven", "Couldn't confirm account ownership.", 403);
    }

    const school = pending.school_id
        ? await env.DB.prepare(`SELECT id, name FROM schools WHERE id = ?`)
            .bind(pending.school_id)
            .first<{ id: string; name: string }>()
        : null;
    const domainKind: string = pending.domain_kind ?? "student";
    const now = nowSeconds();

    await writeVerificationRecord(env, {
        userRecordName: pending.user_record_name,
        emailHash: pending.email_hash,
        schoolID: pending.school_id,
        schoolName: school?.name ?? "",
        domainKind,
        verifiedAt: now,
    });

    await env.DB.batch([
        env.DB.prepare(
            `INSERT INTO verified_emails
               (email_hash, user_record_name, school_id, domain_kind, verified_at, method)
             VALUES (?, ?, ?, ?, ?, 'email')
             ON CONFLICT(email_hash) DO UPDATE SET
               user_record_name = excluded.user_record_name,
               school_id = excluded.school_id,
               domain_kind = excluded.domain_kind,
               verified_at = excluded.verified_at,
               revoked_at = NULL`,
        ).bind(pending.email_hash, pending.user_record_name, pending.school_id, domainKind, now),
        // Consume the row and drop the raw address — from here we only keep the hash.
        env.DB.prepare(
            `UPDATE pending_verifications SET consumed_at = ?, email_normalized = '' WHERE id = ?`,
        ).bind(now, pendingID),
    ]);

    await clearProfileNonce(env, pending.user_record_name, profile).catch((error) => {
        // Non-fatal: the nonce is single-use in D1 regardless.
        console.error("nonce clear failed", error);
    });

    return json({
        verified: true,
        school: { id: pending.school_id, name: school?.name ?? "" },
        domainKind,
        verifiedAt: now,
    });
}

// MARK: - Status

async function handleStatus(url: URL, env: Env): Promise<Response> {
    const userRecordName = (url.searchParams.get("user") ?? "").trim();
    if (!userRecordName) return errorResponse("bad_request", "Missing user.", 400);

    const row = await env.DB.prepare(
        `SELECT school_id, verified_at, enrollment_verified_at FROM verified_emails
         WHERE user_record_name = ? AND revoked_at IS NULL`,
    )
        .bind(userRecordName)
        .first<{ school_id: string; verified_at: number; enrollment_verified_at: number | null }>();

    if (!row) return json({ verified: false });
    return json({
        verified: true,
        schoolID: row.school_id,
        verifiedAt: row.verified_at,
        enrollmentVerified: row.enrollment_verified_at != null,
    });
}

// MARK: - Admin

/// One-off schoolID migration. Not part of the app's API surface — it exists
/// here rather than as a local script so the CloudKit server-to-server private
/// key never has to leave Worker secrets. See README, "Backfilling schoolID".
///
/// Defaults to a dry run: `dryRun` must be explicitly `false` to write.
async function handleSchoolBackfill(request: Request, env: Env): Promise<Response> {
    if (!env.ADMIN_TOKEN) {
        return errorResponse("not_configured", "Admin routes are disabled.", 404);
    }

    const presented = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!constantTimeEqual(presented, env.ADMIN_TOKEN)) {
        return errorResponse("forbidden", "Bad admin token.", 403);
    }

    const body = (await readJSON(request)) ?? {};
    const rawCursor = body.cursor as Partial<BackfillCursor> | undefined;
    const cursor: BackfillCursor | undefined = rawCursor?.recordType
        ? { recordType: String(rawCursor.recordType), marker: rawCursor.marker ? String(rawCursor.marker) : undefined }
        : undefined;

    const maxRecords = Number(body.maxRecords ?? 0);

    const result = await runBackfill(env, {
        dryRun: body.dryRun !== false,
        cursor,
        maxRecords: maxRecords > 0 ? maxRecords : undefined,
    });

    return json(result);
}

// MARK: - Helpers

async function readJSON(request: Request): Promise<Record<string, unknown> | null> {
    try {
        const parsed = await request.json();
        return typeof parsed === "object" && parsed !== null ? (parsed as Record<string, unknown>) : null;
    } catch {
        return null;
    }
}

interface DomainMatch {
    schoolID: string;
    schoolName: string;
    kind: string;
}

/// Matches most-specific suffix first so mail.utexas.edu resolves via
/// utexas.edu without needing a row for every subdomain.
async function lookupDomain(env: Env, domain: string): Promise<DomainMatch | null> {
    const candidates = domainCandidates(domain);
    if (candidates.length === 0) return null;

    const placeholders = candidates.map(() => "?").join(",");
    const rows = await env.DB.prepare(
        `SELECT d.domain, d.kind, s.id AS school_id, s.name AS school_name
         FROM school_domains d JOIN schools s ON s.id = d.school_id
         WHERE d.domain IN (${placeholders}) AND s.enabled = 1`,
    )
        .bind(...candidates)
        .all<{ domain: string; kind: string; school_id: string; school_name: string }>();

    for (const candidate of candidates) {
        const hit = (rows.results ?? []).find((row) => row.domain === candidate);
        if (hit) return { schoolID: hit.school_id, schoolName: hit.school_name, kind: hit.kind };
    }
    return null;
}
