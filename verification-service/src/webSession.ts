/// Website sign-in: proves control of a school email address and nothing else.
///
/// Routes (called server-to-server by the Nexus website, never by a browser):
///   POST /v1/web/session/request   { email }            -> { pendingID, expiresAt, school }
///   POST /v1/web/session/confirm   { pendingID, code }  -> { email, schoolID, schoolName, domainKind, userRecordName? }
///
/// Unlike /v1/verify/*, there is no userRecordName and no nonce. A web session
/// claims no CloudKit account, so there is no account ownership to prove — and
/// for the same reason a confirmed web session must never be treated as an app
/// identity or used as authority over any user's records.
///
/// Both routes require `Authorization: Bearer <WEB_CLIENT_TOKEN>` and 404 when
/// the token is unset, so the Worker can't be used as an open mail relay. The
/// website forwards the end user's IP in `x-nexus-client-ip`, which is trusted
/// only on an authenticated request (otherwise every user would share the
/// website server's IP bucket).

import type { Env } from "./util";
import {
    json,
    errorResponse,
    nowSeconds,
    hmacHex,
    constantTimeEqual,
    randomCode,
    randomToken,
    normalizeEmail,
    domainOf,
    checkAllRateLimits,
} from "./util";
import { sendVerificationCode } from "./email";

export const WEB_CODE_TTL_SECONDS = 600;
export const WEB_MAX_CODE_ATTEMPTS = 5;

export interface DomainMatch {
    schoolID: string;
    schoolName: string;
    kind: string;
}

export type DomainLookup = (env: Env, domain: string) => Promise<DomainMatch | null>;

/// Returns an error response when the caller isn't the website, else null.
export function authorizeWebClient(request: Request, env: Env): Response | null {
    if (!env.WEB_CLIENT_TOKEN) {
        return errorResponse("not_found", "Unknown endpoint.", 404);
    }
    const presented = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!constantTimeEqual(presented, env.WEB_CLIENT_TOKEN)) {
        return errorResponse("forbidden", "Bad client token.", 403);
    }
    return null;
}

function endUserIP(request: Request): string {
    return (request.headers.get("x-nexus-client-ip") ?? "").trim() || "unknown";
}

export async function handleWebSessionRequest(
    request: Request,
    env: Env,
    lookupDomain: DomainLookup,
): Promise<Response> {
    const denied = authorizeWebClient(request, env);
    if (denied) return denied;

    const body = await readJSON(request);
    if (!body) return errorResponse("bad_request", "Malformed body.", 400);

    const email = normalizeEmail(String(body.email ?? ""));
    if (!email) return errorResponse("invalid_email", "That doesn't look like an email address.", 400);

    const domain = domainOf(email);
    const emailHash = await hmacHex(env.CODE_PEPPER, `email:${email}`);

    const limited = await checkAllRateLimits(env, [
        { dimension: "web_ip", value: endUserIP(request), limit: 10, windowSeconds: 3600 },
        { dimension: "web_email", value: emailHash, limit: 5, windowSeconds: 3600 },
        // Shared with the app's flow on purpose: one per-domain sending budget.
        { dimension: "domain", value: domain, limit: 200, windowSeconds: 3600 },
    ]);
    if (limited) {
        return errorResponse("rate_limited", "Too many attempts. Try again later.", 429);
    }

    const match = await lookupDomain(env, domain);
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

    const code = randomCode();
    const pendingID = randomToken();
    const now = nowSeconds();

    await env.DB.prepare(
        `INSERT INTO pending_web_sessions
           (id, email_normalized, email_hash, code_hash, school_id, domain_kind,
            attempts, created_at, expires_at)
         VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)`,
    )
        .bind(
            pendingID,
            email,
            emailHash,
            await hmacHex(env.CODE_PEPPER, `webcode:${pendingID}:${code}`),
            match.schoolID,
            match.kind,
            now,
            now + WEB_CODE_TTL_SECONDS,
        )
        .run();

    await sendVerificationCode(env, { to: email, code, schoolName: match.schoolName, context: "web" });

    return json({
        pendingID,
        expiresAt: now + WEB_CODE_TTL_SECONDS,
        school: { id: match.schoolID, name: match.schoolName },
    });
}

export async function handleWebSessionConfirm(request: Request, env: Env): Promise<Response> {
    const denied = authorizeWebClient(request, env);
    if (denied) return denied;

    const body = await readJSON(request);
    if (!body) return errorResponse("bad_request", "Malformed body.", 400);

    const pendingID = String(body.pendingID ?? "").trim();
    const code = String(body.code ?? "").trim();
    if (!pendingID || !/^\d{6}$/.test(code)) {
        return errorResponse("bad_request", "Missing or malformed code.", 400);
    }

    if (await checkAllRateLimits(env, [
        { dimension: "web_confirm_ip", value: endUserIP(request), limit: 20, windowSeconds: 3600 },
    ])) {
        return errorResponse("rate_limited", "Too many attempts. Try again later.", 429);
    }

    const pending = await env.DB.prepare(`SELECT * FROM pending_web_sessions WHERE id = ?`)
        .bind(pendingID)
        .first<any>();

    if (!pending) return errorResponse("invalid_code", "That code isn't valid.", 400);
    if (pending.consumed_at) return errorResponse("invalid_code", "That code was already used.", 400);
    if (pending.expires_at < nowSeconds()) {
        return errorResponse("expired_code", "That code expired. Request a new one.", 400);
    }
    if (pending.attempts >= WEB_MAX_CODE_ATTEMPTS) {
        return errorResponse("too_many_attempts", "Too many wrong codes. Request a new one.", 429);
    }

    await env.DB.prepare(`UPDATE pending_web_sessions SET attempts = attempts + 1 WHERE id = ?`)
        .bind(pendingID)
        .run();

    const expected = await hmacHex(env.CODE_PEPPER, `webcode:${pendingID}:${code}`);
    if (!constantTimeEqual(expected, pending.code_hash)) {
        return errorResponse("invalid_code", "That code isn't valid.", 400);
    }

    // Consume only if still unconsumed, so two concurrent confirms can't both succeed.
    const consumed = await env.DB.prepare(
        `UPDATE pending_web_sessions SET consumed_at = ?, email_normalized = ''
         WHERE id = ? AND consumed_at IS NULL`,
    )
        .bind(nowSeconds(), pendingID)
        .run();
    if (!consumed.meta?.changes) {
        return errorResponse("invalid_code", "That code was already used.", 400);
    }

    const school = await env.DB.prepare(`SELECT id, name FROM schools WHERE id = ?`)
        .bind(pending.school_id)
        .first<{ id: string; name: string }>();

    // The app account that verified this same address, if any. Proving control of
    // the email now is the same proof the app accepted, so the website may use this
    // to SHOW that account's profile. It is not authority to write to the account.
    const linked = await env.DB.prepare(
        `SELECT user_record_name FROM verified_emails WHERE email_hash = ? AND revoked_at IS NULL`,
    )
        .bind(pending.email_hash)
        .first<{ user_record_name: string }>();

    return json({
        email: pending.email_normalized,
        schoolID: pending.school_id,
        schoolName: school?.name ?? "",
        domainKind: pending.domain_kind,
        ...(linked ? { userRecordName: linked.user_record_name } : {}),
    });
}

async function readJSON(request: Request): Promise<Record<string, unknown> | null> {
    try {
        const parsed = await request.json();
        return typeof parsed === "object" && parsed !== null ? (parsed as Record<string, unknown>) : null;
    } catch {
        return null;
    }
}
