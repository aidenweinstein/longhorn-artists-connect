/// Apple TV sign-in and watch time.
///
/// The TV app is watch-only, but it signs in so that every view it records is
/// some real account's: an anonymous device can't add watch time. Two ways in:
///
/// Pairing (QR code). The TV starts a pairing and shows its short code, plus a
/// QR code for https://nexusbylac.com/tv?code=<code>. That link opens the iPhone
/// app when it's installed (a universal link) and the website when it isn't.
/// Either one approves the pairing as its signed-in account, and the TV's next
/// poll collects a session token.
///   POST /v1/tv/pair/start    {}                         -> { pairingID, code, approveURL, expiresAt }
///   POST /v1/tv/pair/poll     { pairingID }              -> { status: "pending" } | { status: "approved", token, viewer }
///   POST /v1/tv/pair/claim    { code, userRecordName }   -> { nonce }        (iPhone app, step 1)
///   POST /v1/tv/pair/approve  { code, userRecordName }   -> { approved }     (iPhone app, step 2)
///   POST /v1/web/tv/approve   { code, userRecordName }   -> { approved }     (website, WEB_CLIENT_TOKEN)
///
/// The app proves it owns `userRecordName` the way /v1/verify does: it writes
/// the claim's nonce to `verificationNonce` on its own UserProfile (only the
/// account's creator can), and approve reads it back. The website is trusted to
/// name its own signed-in account, like everywhere else under /v1/web/.
///
/// Email. The email on an existing account gets a 6-digit code; entering it on
/// the TV signs in as that account. No account is ever created from a TV.
///   POST /v1/tv/email/request { email }                  -> { pendingID, expiresAt }
///   POST /v1/tv/email/confirm { pendingID, code }        -> { token, viewer }
///
/// A signed-in TV:
///   POST /v1/tv/me            { token }                  -> { viewer }
///   POST /v1/tv/signout       { token }                  -> { signedOut }
///   POST /v1/tv/view          { token, postID, kind }    -> { recorded }
///
/// /view writes the same `NewPostView` record the iPhone app does, under the
/// same deterministic name (`view_<kind>_<postID>_<user>_<yyyyMMdd>`), so one
/// person counts once per post per day whichever device they watch on.

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
    checkAllRateLimits,
    clientIP,
} from "./util";
import { sendVerificationCode } from "./email";
import { fetchUserProfile, modifyRecords } from "./cloudkit";
import { authorizeWebClient } from "./webSession";

export const TV_PAIRING_TTL_SECONDS = 600;
export const TV_CODE_TTL_SECONDS = 600;
export const TV_MAX_CODE_ATTEMPTS = 5;
export const TV_APPROVE_URL = "https://nexusbylac.com/tv";

/// No 0/O, 1/I/L: the code is read off a TV across a room.
const PAIRING_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const PAIRING_CODE_LENGTH = 8;

/// What /view accepts. `profileVisit` and `message` can't happen on a TV.
const TV_VIEW_KINDS = new Set(["open", "play", "engaged"]);
const UUID_PATTERN = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/;

export interface Viewer {
    userRecordName: string;
    name: string;
}

/// The CloudKit calls, swappable in tests.
export interface TVDeps {
    /// The account's UserProfile record (web-services JSON), or null when it has none.
    fetchProfile(env: Env, userRecordName: string): Promise<any | null>;
    /// Creates a NewPostView record. False when it already exists.
    createView(env: Env, record: { recordName: string; fields: Record<string, { value: string | number }> }): Promise<boolean>;
}

export const defaultTVDeps: TVDeps = {
    fetchProfile: fetchUserProfile,
    async createView(env, record) {
        const outcome = await modifyRecords(env, [
            { operationType: "create", record: { recordType: "NewPostView", ...record } },
        ]);
        if (outcome.saved > 0) return true;
        const reason = outcome.errors[0]?.reason ?? "";
        // Already counted today, from this TV or the viewer's iPhone.
        if (reason.startsWith("RECORD_EXISTS") || reason.startsWith("CONFLICT")) return false;
        throw new Error(`NewPostView create failed: ${reason}`);
    },
};

// MARK: - Routing

export async function handleTV(request: Request, env: Env, path: string, deps: TVDeps = defaultTVDeps): Promise<Response> {
    const body = await readJSON(request);
    if (!body) return errorResponse("bad_request", "Malformed body.", 400);

    switch (path) {
        case "/v1/tv/pair/start": return pairStart(request, env);
        case "/v1/tv/pair/poll": return pairPoll(request, env, body, deps);
        case "/v1/tv/pair/claim": return pairClaim(request, env, body);
        case "/v1/tv/pair/approve": return pairApproveFromApp(request, env, body, deps);
        case "/v1/web/tv/approve": return pairApproveFromWeb(request, env, body, deps);
        case "/v1/tv/email/request": return emailRequest(request, env, body);
        case "/v1/tv/email/confirm": return emailConfirm(request, env, body, deps);
        case "/v1/tv/me": return me(env, body, deps);
        case "/v1/tv/signout": return signOut(env, body);
        case "/v1/tv/view": return view(env, body, deps);
        default: return errorResponse("not_found", "Unknown endpoint.", 404);
    }
}

// MARK: - Pairing

async function pairStart(request: Request, env: Env): Promise<Response> {
    if (await checkAllRateLimits(env, [
        { dimension: "tv_start_ip", value: clientIP(request), limit: 30, windowSeconds: 3600 },
    ])) {
        return errorResponse("rate_limited", "Too many attempts. Try again later.", 429);
    }

    const pairingID = randomToken();
    const code = pairingCode();
    const now = nowSeconds();
    await env.DB.prepare(
        `INSERT INTO tv_pairings (id, code, created_at, expires_at) VALUES (?, ?, ?, ?)`,
    )
        .bind(pairingID, code, now, now + TV_PAIRING_TTL_SECONDS)
        .run();

    return json({
        pairingID,
        code,
        approveURL: `${TV_APPROVE_URL}?code=${code}`,
        expiresAt: now + TV_PAIRING_TTL_SECONDS,
    });
}

async function pairPoll(request: Request, env: Env, body: Record<string, unknown>, deps: TVDeps): Promise<Response> {
    const pairingID = String(body.pairingID ?? "").trim();
    if (!pairingID) return errorResponse("bad_request", "Missing pairingID.", 400);

    // A TV polls every few seconds for up to ten minutes.
    if (await checkAllRateLimits(env, [
        { dimension: "tv_poll_ip", value: clientIP(request), limit: 2000, windowSeconds: 3600 },
    ])) {
        return errorResponse("rate_limited", "Too many attempts. Try again later.", 429);
    }

    const pairing = await env.DB.prepare(`SELECT * FROM tv_pairings WHERE id = ?`)
        .bind(pairingID)
        .first<any>();
    if (!pairing || pairing.token_issued_at) {
        return errorResponse("expired_pairing", "That sign-in code is no longer valid.", 410);
    }
    if (!pairing.approved_user) {
        if (pairing.expires_at < nowSeconds()) {
            return errorResponse("expired_pairing", "That sign-in code expired.", 410);
        }
        return json({ status: "pending" });
    }

    // Spend the pairing before issuing, so two racing polls can't both get a token.
    const spent = await env.DB.prepare(
        `UPDATE tv_pairings SET token_issued_at = ? WHERE id = ? AND token_issued_at IS NULL`,
    )
        .bind(nowSeconds(), pairingID)
        .run();
    if (spent.meta.changes !== 1) {
        return errorResponse("expired_pairing", "That sign-in code is no longer valid.", 410);
    }

    const viewer = await viewerFor(env, pairing.approved_user, deps);
    const token = await issueSession(env, pairing.approved_user);
    return json({ status: "approved", token, viewer });
}

/// The iPhone app, step 1: hands out the nonce to write on the account's UserProfile.
async function pairClaim(request: Request, env: Env, body: Record<string, unknown>): Promise<Response> {
    const code = normalizePairingCode(body.code);
    const userRecordName = String(body.userRecordName ?? "").trim();
    if (!code || !userRecordName) return errorResponse("bad_request", "Missing code or account.", 400);

    if (await checkAllRateLimits(env, [
        { dimension: "tv_claim_ip", value: clientIP(request), limit: 30, windowSeconds: 3600 },
        { dimension: "tv_claim_user", value: userRecordName, limit: 20, windowSeconds: 3600 },
    ])) {
        return errorResponse("rate_limited", "Too many attempts. Try again later.", 429);
    }

    const pairing = await openPairing(env, code);
    if (!pairing) return errorResponse("invalid_pairing", "That code isn't on any Apple TV right now.", 404);

    const nonce = randomToken();
    await env.DB.prepare(`UPDATE tv_pairings SET claim_user = ?, claim_nonce = ? WHERE id = ?`)
        .bind(userRecordName, nonce, pairing.id)
        .run();
    return json({ nonce, expiresAt: pairing.expires_at });
}

/// The iPhone app, step 2: the nonce is on the account's UserProfile, so it's theirs.
async function pairApproveFromApp(request: Request, env: Env, body: Record<string, unknown>, deps: TVDeps): Promise<Response> {
    const code = normalizePairingCode(body.code);
    const userRecordName = String(body.userRecordName ?? "").trim();
    if (!code || !userRecordName) return errorResponse("bad_request", "Missing code or account.", 400);

    if (await checkAllRateLimits(env, [
        { dimension: "tv_approve_ip", value: clientIP(request), limit: 30, windowSeconds: 3600 },
    ])) {
        return errorResponse("rate_limited", "Too many attempts. Try again later.", 429);
    }

    const pairing = await openPairing(env, code);
    if (!pairing || pairing.claim_user !== userRecordName || !pairing.claim_nonce) {
        return errorResponse("invalid_pairing", "That code isn't on any Apple TV right now.", 404);
    }

    const profile = await deps.fetchProfile(env, userRecordName);
    if (!profile) return errorResponse("profile_not_found", "Couldn't find your profile. Try again.", 409);
    const writtenNonce = profile.fields?.verificationNonce?.value ?? "";
    if (!constantTimeEqual(writtenNonce, pairing.claim_nonce)) {
        return errorResponse("ownership_unproven", "Couldn't confirm account ownership.", 403);
    }

    return approve(env, pairing.id, userRecordName);
}

/// The website, for whoever is signed in there.
async function pairApproveFromWeb(request: Request, env: Env, body: Record<string, unknown>, deps: TVDeps): Promise<Response> {
    const denied = authorizeWebClient(request, env);
    if (denied) return denied;

    const code = normalizePairingCode(body.code);
    const userRecordName = String(body.userRecordName ?? "").trim();
    if (!code || !userRecordName) return errorResponse("bad_request", "Missing code or account.", 400);

    const pairing = await openPairing(env, code);
    if (!pairing) return errorResponse("invalid_pairing", "That code isn't on any Apple TV right now.", 404);
    if (!(await deps.fetchProfile(env, userRecordName))) {
        return errorResponse("profile_not_found", "Couldn't find your profile.", 409);
    }

    return approve(env, pairing.id, userRecordName);
}

async function approve(env: Env, pairingID: string, userRecordName: string): Promise<Response> {
    const result = await env.DB.prepare(
        `UPDATE tv_pairings SET approved_user = ?, approved_at = ?
         WHERE id = ? AND approved_user IS NULL AND expires_at >= ?`,
    )
        .bind(userRecordName, nowSeconds(), pairingID, nowSeconds())
        .run();
    if (result.meta.changes !== 1) {
        return errorResponse("invalid_pairing", "That code isn't on any Apple TV right now.", 404);
    }
    return json({ approved: true });
}

/// A pairing that can still be approved.
async function openPairing(env: Env, code: string): Promise<any | null> {
    return env.DB.prepare(
        `SELECT * FROM tv_pairings WHERE code = ? AND approved_user IS NULL AND expires_at >= ?`,
    )
        .bind(code, nowSeconds())
        .first<any>();
}

function pairingCode(): string {
    const bytes = new Uint8Array(PAIRING_CODE_LENGTH);
    let code = "";
    while (code.length < PAIRING_CODE_LENGTH) {
        crypto.getRandomValues(bytes);
        for (const byte of bytes) {
            // Rejection sampling keeps every character equally likely.
            if (byte < 256 - (256 % PAIRING_ALPHABET.length) && code.length < PAIRING_CODE_LENGTH) {
                code += PAIRING_ALPHABET[byte % PAIRING_ALPHABET.length];
            }
        }
    }
    return code;
}

/// Accepts the code however it was typed: lowercase, with the dash, with spaces.
export function normalizePairingCode(raw: unknown): string | null {
    const code = String(raw ?? "").toUpperCase().replace(/[\s-]/g, "");
    if (code.length !== PAIRING_CODE_LENGTH) return null;
    return [...code].every((c) => PAIRING_ALPHABET.includes(c)) ? code : null;
}

// MARK: - Email

async function emailRequest(request: Request, env: Env, body: Record<string, unknown>): Promise<Response> {
    const email = normalizeEmail(String(body.email ?? ""));
    if (!email) return errorResponse("invalid_email", "That doesn't look like an email address.", 400);

    const emailHash = await hmacHex(env.CODE_PEPPER, `email:${email}`);
    if (await checkAllRateLimits(env, [
        { dimension: "tv_email_ip", value: clientIP(request), limit: 10, windowSeconds: 3600 },
        { dimension: "tv_email", value: emailHash, limit: 5, windowSeconds: 3600 },
    ])) {
        return errorResponse("rate_limited", "Too many attempts. Try again later.", 429);
    }

    const owner = await env.DB.prepare(
        `SELECT user_record_name FROM verified_emails WHERE email_hash = ? AND revoked_at IS NULL`,
    )
        .bind(emailHash)
        .first<{ user_record_name: string }>();
    if (!owner) {
        return errorResponse(
            "no_account",
            "No Nexus account uses that email. Make one in the Nexus app or at nexusbylac.com first.",
            404,
        );
    }

    const code = randomCode();
    const pendingID = randomToken();
    const now = nowSeconds();
    await env.DB.prepare(
        `INSERT INTO pending_tv_emails (id, email_hash, code_hash, user_record_name, attempts, created_at, expires_at)
         VALUES (?, ?, ?, ?, 0, ?, ?)`,
    )
        .bind(
            pendingID,
            emailHash,
            await hmacHex(env.CODE_PEPPER, `tvcode:${pendingID}:${code}`),
            owner.user_record_name,
            now,
            now + TV_CODE_TTL_SECONDS,
        )
        .run();

    await sendVerificationCode(env, { to: email, code, schoolName: "", context: "tv" });
    return json({ pendingID, expiresAt: now + TV_CODE_TTL_SECONDS });
}

async function emailConfirm(request: Request, env: Env, body: Record<string, unknown>, deps: TVDeps): Promise<Response> {
    const pendingID = String(body.pendingID ?? "").trim();
    const code = String(body.code ?? "").trim();
    if (!pendingID || !/^\d{6}$/.test(code)) {
        return errorResponse("bad_request", "Missing or malformed code.", 400);
    }

    if (await checkAllRateLimits(env, [
        { dimension: "tv_confirm_ip", value: clientIP(request), limit: 20, windowSeconds: 3600 },
    ])) {
        return errorResponse("rate_limited", "Too many attempts. Try again later.", 429);
    }

    const pending = await env.DB.prepare(`SELECT * FROM pending_tv_emails WHERE id = ?`)
        .bind(pendingID)
        .first<any>();
    if (!pending) return errorResponse("invalid_code", "That code isn't valid.", 400);
    if (pending.consumed_at) return errorResponse("invalid_code", "That code was already used.", 400);
    if (pending.expires_at < nowSeconds()) {
        return errorResponse("expired_code", "That code expired. Request a new one.", 400);
    }
    if (pending.attempts >= TV_MAX_CODE_ATTEMPTS) {
        return errorResponse("too_many_attempts", "Too many wrong codes. Request a new one.", 429);
    }

    await env.DB.prepare(`UPDATE pending_tv_emails SET attempts = attempts + 1 WHERE id = ?`)
        .bind(pendingID)
        .run();
    const expected = await hmacHex(env.CODE_PEPPER, `tvcode:${pendingID}:${code}`);
    if (!constantTimeEqual(expected, pending.code_hash)) {
        return errorResponse("invalid_code", "That code isn't valid.", 400);
    }

    const consumed = await env.DB.prepare(
        `UPDATE pending_tv_emails SET consumed_at = ? WHERE id = ? AND consumed_at IS NULL`,
    )
        .bind(nowSeconds(), pendingID)
        .run();
    if (consumed.meta.changes !== 1) return errorResponse("invalid_code", "That code was already used.", 400);

    const viewer = await viewerFor(env, pending.user_record_name, deps);
    const token = await issueSession(env, pending.user_record_name);
    return json({ token, viewer });
}

// MARK: - Sessions

async function issueSession(env: Env, userRecordName: string): Promise<string> {
    const token = randomToken(32);
    const now = nowSeconds();
    await env.DB.prepare(
        `INSERT INTO tv_sessions (token_hash, user_record_name, created_at, last_seen_at) VALUES (?, ?, ?, ?)`,
    )
        .bind(await tokenHash(env, token), userRecordName, now, now)
        .run();
    return token;
}

/// The account a TV token belongs to, or null when it's unknown or signed out.
async function sessionUser(env: Env, token: string): Promise<string | null> {
    if (!token) return null;
    const hash = await tokenHash(env, token);
    const row = await env.DB.prepare(
        `SELECT user_record_name FROM tv_sessions WHERE token_hash = ? AND revoked_at IS NULL`,
    )
        .bind(hash)
        .first<{ user_record_name: string }>();
    if (!row) return null;
    await env.DB.prepare(`UPDATE tv_sessions SET last_seen_at = ? WHERE token_hash = ?`)
        .bind(nowSeconds(), hash)
        .run();
    return row.user_record_name;
}

function tokenHash(env: Env, token: string): Promise<string> {
    return hmacHex(env.CODE_PEPPER, `tv:${token}`);
}

async function viewerFor(env: Env, userRecordName: string, deps: TVDeps): Promise<Viewer> {
    const profile = await deps.fetchProfile(env, userRecordName).catch(() => null);
    const first = String(profile?.fields?.firstName?.value ?? "");
    const last = String(profile?.fields?.lastName?.value ?? "");
    return { userRecordName, name: `${first} ${last}`.trim() };
}

async function me(env: Env, body: Record<string, unknown>, deps: TVDeps): Promise<Response> {
    const user = await sessionUser(env, String(body.token ?? ""));
    if (!user) return errorResponse("signed_out", "Sign in again.", 401);
    return json({ viewer: await viewerFor(env, user, deps) });
}

async function signOut(env: Env, body: Record<string, unknown>): Promise<Response> {
    const token = String(body.token ?? "");
    if (token) {
        await env.DB.prepare(`UPDATE tv_sessions SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL`)
            .bind(nowSeconds(), await tokenHash(env, token))
            .run();
    }
    return json({ signedOut: true });
}

// MARK: - Watch time

async function view(env: Env, body: Record<string, unknown>, deps: TVDeps): Promise<Response> {
    const kind = String(body.kind ?? "");
    const postID = String(body.postID ?? "").toUpperCase();
    if (!TV_VIEW_KINDS.has(kind) || !UUID_PATTERN.test(postID)) {
        return errorResponse("bad_request", "Unknown view.", 400);
    }

    const user = await sessionUser(env, String(body.token ?? ""));
    if (!user) return errorResponse("signed_out", "Sign in again.", 401);

    // Three kinds a post, so this is far above anyone actually watching.
    if (await checkAllRateLimits(env, [
        { dimension: "tv_view_user", value: user, limit: 600, windowSeconds: 3600 },
    ])) {
        return errorResponse("rate_limited", "Too many views. Try again later.", 429);
    }

    const day = new Date().toISOString().slice(0, 10).replace(/-/g, "");
    const recorded = await deps.createView(env, {
        recordName: `view_${kind}_${postID}_${user}_${day}`,
        fields: {
            postID: { value: postID },
            userID: { value: user },
            eventKind: { value: kind },
            createdDate: { value: Date.now() },
        },
    });
    return json({ recorded });
}

async function readJSON(request: Request): Promise<Record<string, unknown> | null> {
    try {
        const text = await request.text();
        if (!text) return {};
        const parsed = JSON.parse(text);
        return typeof parsed === "object" && parsed !== null ? (parsed as Record<string, unknown>) : null;
    } catch {
        return null;
    }
}
