/// Sign in with Apple: one Apple ID for the app and the website (added 2026-11-19).
///
/// Apple gives every Apple ID one stable user ID (`sub`) per developer team, so
/// the app (audience: its bundle ID) and the website (audience: its Services
/// ID) see the same `sub` for the same person. This file links that `sub` to a
/// Nexus account, so signing in with Apple on the website opens the same
/// account as the app.
///
/// Route:
///   POST /v1/web/apple/session    { idToken, nonce }                    -> { signedIn } | { needsEmail, appleTicket, reason }
///       Called by the website (WEB_CLIENT_TOKEN). Signs straight in when the
///       Apple ID is linked to an account whose school email this service can
///       name; otherwise hands back an `appleTicket`, and the website asks for
///       the school email code. /v1/web/session/confirm and /v1/web/account/create
///       take that ticket and link the Apple ID once the email is proven.
///
/// The app doesn't sign in with Apple (it uses the iCloud account), so the first
/// Apple sign-in on the website always goes through the school email: if an app
/// account verified that email, the Apple ID is linked to the app account; if
/// nobody has it, the website account created next gets the Apple ID. From then
/// on Sign in with Apple alone opens that account. When the app later verifies
/// the email of a website account, the merge moves its Apple ID along
/// (moveAppleLink, called from /v1/verify/confirm).
///
/// Nothing here trusts the website about who someone is: identity tokens are
/// checked against Apple's published keys, audience and nonce.
/// Apple IDs are stored only as an HMAC, like emails. The school email for
/// Apple sign-in is kept AES-GCM encrypted under a key derived from
/// CODE_PEPPER, because a website session needs the address itself and the
/// rest of this service deliberately keeps only hashes.

import type { Env } from "./util";
import {
    json,
    errorResponse,
    nowSeconds,
    hmacHex,
    constantTimeEqual,
    randomToken,
    checkAllRateLimits,
    base64Encode,
    base64Decode,
} from "./util";
import { writeVerificationRecord } from "./cloudkit";
import { mergeWebAccount, type MergeReport } from "./accountMerge";

export const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";
/// How long the website has to finish the email step after an Apple sign-in.
export const APPLE_TICKET_TTL_SECONDS = 30 * 60;
const WEB_PREFIX = "web_";

// MARK: - Dependencies (swapped for fakes in tests)

export type KeyFetcher = (refresh: boolean) => Promise<JsonWebKey[]>;

export interface AppleDeps {
    keys: KeyFetcher;
    writeVerification: typeof writeVerificationRecord;
    merge: (env: Env, webUser: string, appUser: string) => Promise<MergeReport>;
}

let cachedKeys: { keys: JsonWebKey[]; fetchedAt: number } | null = null;

/// Apple's signing keys, cached for an hour; `refresh` forces a re-fetch (a new `kid`).
const appleKeys: KeyFetcher = async (refresh) => {
    if (!refresh && cachedKeys && Date.now() - cachedKeys.fetchedAt < 3_600_000) return cachedKeys.keys;
    const res = await fetch(APPLE_KEYS_URL);
    if (!res.ok) throw new Error(`Apple keys ${res.status}`);
    const body = (await res.json()) as { keys?: JsonWebKey[] };
    cachedKeys = { keys: body.keys ?? [], fetchedAt: Date.now() };
    return cachedKeys.keys;
};

export const defaultAppleDeps: AppleDeps = {
    keys: appleKeys,
    writeVerification: writeVerificationRecord,
    merge: mergeWebAccount,
};

// MARK: - Identity tokens

export interface AppleClaims {
    sub: string;
    aud: string | string[];
    nonce?: string;
    email?: string;
}

export class AppleTokenError extends Error {}

function base64urlDecode(value: string): Uint8Array {
    const padded = value.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (value.length % 4)) % 4);
    return base64Decode(padded);
}

function toBuffer(view: Uint8Array): ArrayBuffer {
    return view.buffer.slice(view.byteOffset, view.byteOffset + view.byteLength) as ArrayBuffer;
}

/// Checks an Apple identity token: Apple's signature, issuer, audience, expiry
/// and (when given) the nonce. Throws AppleTokenError when any check fails.
export async function verifyAppleToken(
    token: string,
    options: { audience: string; nonce?: string; keys: KeyFetcher; now?: number },
): Promise<AppleClaims> {
    const parts = token.split(".");
    if (parts.length !== 3) throw new AppleTokenError("malformed token");
    let header: { alg?: string; kid?: string };
    let claims: Record<string, unknown>;
    try {
        header = JSON.parse(new TextDecoder().decode(base64urlDecode(parts[0])));
        claims = JSON.parse(new TextDecoder().decode(base64urlDecode(parts[1])));
    } catch {
        throw new AppleTokenError("malformed token");
    }
    if (header.alg !== "RS256" || !header.kid) throw new AppleTokenError("unexpected algorithm");

    let jwk = (await options.keys(false)).find((k) => (k as { kid?: string }).kid === header.kid);
    if (!jwk) jwk = (await options.keys(true)).find((k) => (k as { kid?: string }).kid === header.kid);
    if (!jwk) throw new AppleTokenError("unknown signing key");

    const key = await crypto.subtle.importKey(
        "jwk",
        { kty: jwk.kty, n: jwk.n, e: jwk.e },
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
        false,
        ["verify"],
    );
    const valid = await crypto.subtle.verify(
        "RSASSA-PKCS1-v1_5",
        key,
        toBuffer(base64urlDecode(parts[2])),
        toBuffer(new TextEncoder().encode(`${parts[0]}.${parts[1]}`)),
    );
    if (!valid) throw new AppleTokenError("bad signature");

    const now = options.now ?? nowSeconds();
    const aud = claims.aud;
    const audOK = Array.isArray(aud) ? aud.includes(options.audience) : aud === options.audience;
    if (claims.iss !== APPLE_ISSUER) throw new AppleTokenError("wrong issuer");
    if (!options.audience || !audOK) throw new AppleTokenError("wrong audience");
    if (typeof claims.exp !== "number" || claims.exp < now - 60) throw new AppleTokenError("expired");
    if (typeof claims.sub !== "string" || !claims.sub) throw new AppleTokenError("no subject");
    if (options.nonce !== undefined && (typeof claims.nonce !== "string" || !constantTimeEqual(claims.nonce, options.nonce))) {
        throw new AppleTokenError("wrong nonce");
    }
    return claims as unknown as AppleClaims;
}

// MARK: - Stored email (encrypted)

async function emailKey(env: Env): Promise<CryptoKey> {
    const base = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.CODE_PEPPER), "HKDF", false, ["deriveKey"]);
    return crypto.subtle.deriveKey(
        { name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info: new TextEncoder().encode("nexus apple email v1") },
        base,
        { name: "AES-GCM", length: 256 },
        false,
        ["encrypt", "decrypt"],
    );
}

export async function sealEmail(env: Env, email: string): Promise<string> {
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const sealed = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await emailKey(env), new TextEncoder().encode(email));
    const out = new Uint8Array(iv.length + sealed.byteLength);
    out.set(iv);
    out.set(new Uint8Array(sealed), iv.length);
    return base64Encode(out);
}

export async function openEmail(env: Env, cipher: string | null | undefined): Promise<string | null> {
    if (!cipher) return null;
    try {
        const bytes = base64Decode(cipher);
        const plain = await crypto.subtle.decrypt(
            { name: "AES-GCM", iv: toBuffer(bytes.slice(0, 12)) },
            await emailKey(env),
            toBuffer(bytes.slice(12)),
        );
        return new TextDecoder().decode(plain);
    } catch {
        return null;
    }
}

// MARK: - Lookups

const appleHashOf = (env: Env, sub: string) => hmacHex(env.CODE_PEPPER, `apple:${sub}`);
const emailHashOf = (env: Env, email: string) => hmacHex(env.CODE_PEPPER, `email:${email}`);

interface AppleLink {
    apple_hash: string;
    user_record_name: string;
    email_cipher: string | null;
}

interface VerifiedEmail {
    email_hash: string;
    school_id: string;
    domain_kind: string;
}

async function linkByApple(env: Env, appleHash: string): Promise<AppleLink | null> {
    return env.DB.prepare(`SELECT * FROM apple_accounts WHERE apple_hash = ?`).bind(appleHash).first<AppleLink>();
}

async function linkByUser(env: Env, user: string): Promise<AppleLink | null> {
    return env.DB.prepare(`SELECT * FROM apple_accounts WHERE user_record_name = ?`).bind(user).first<AppleLink>();
}

async function verifiedEmailOf(env: Env, user: string): Promise<VerifiedEmail | null> {
    return env.DB.prepare(
        `SELECT email_hash, school_id, domain_kind FROM verified_emails WHERE user_record_name = ? AND revoked_at IS NULL`,
    )
        .bind(user)
        .first<VerifiedEmail>();
}

async function ownerOfEmail(env: Env, emailHash: string): Promise<string | null> {
    const row = await env.DB.prepare(
        `SELECT user_record_name FROM verified_emails WHERE email_hash = ? AND revoked_at IS NULL`,
    )
        .bind(emailHash)
        .first<{ user_record_name: string }>();
    return row?.user_record_name ?? null;
}

async function schoolName(env: Env, schoolID: string): Promise<string> {
    if (!schoolID) return "";
    const row = await env.DB.prepare(`SELECT name FROM schools WHERE id = ?`).bind(schoolID).first<{ name: string }>();
    return row?.name ?? "";
}

/// Links an Apple ID to an account (or updates the stored email). Callers have
/// already ruled out a conflicting link.
async function saveLink(env: Env, appleHash: string, user: string, via: "web", emailCipher: string | null) {
    await env.DB.prepare(
        `INSERT INTO apple_accounts (apple_hash, user_record_name, email_cipher, linked_via, linked_at)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(apple_hash) DO UPDATE SET
           user_record_name = excluded.user_record_name,
           email_cipher = COALESCE(excluded.email_cipher, apple_accounts.email_cipher),
           linked_at = excluded.linked_at`,
    )
        .bind(appleHash, user, emailCipher, via, nowSeconds())
        .run();
}

/// After a website account is merged into an app account: its Apple ID now
/// opens the app account, unless the app account already has one of its own.
export async function moveAppleLink(env: Env, fromUser: string, toUser: string): Promise<void> {
    if (await linkByUser(env, toUser)) {
        await env.DB.prepare(`DELETE FROM apple_accounts WHERE user_record_name = ?`).bind(fromUser).run();
    } else {
        await env.DB.prepare(`UPDATE apple_accounts SET user_record_name = ? WHERE user_record_name = ?`).bind(toUser, fromUser).run();
    }
}

/// Verifies `user` with an email already proven by a code: the same Verification
/// record and verified_emails row the app's own flow writes.
async function verifyAccount(
    env: Env,
    deps: AppleDeps,
    user: string,
    email: { hash: string; schoolID: string; domainKind: string },
    method: string,
) {
    const now = nowSeconds();
    await deps.writeVerification(env, {
        userRecordName: user,
        emailHash: email.hash,
        schoolID: email.schoolID,
        schoolName: await schoolName(env, email.schoolID),
        domainKind: email.domainKind,
        verifiedAt: now,
        method,
    });
    await env.DB.prepare(
        `INSERT INTO verified_emails (email_hash, user_record_name, school_id, domain_kind, verified_at, method)
         VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(email_hash) DO UPDATE SET
           user_record_name = excluded.user_record_name,
           school_id = excluded.school_id,
           domain_kind = excluded.domain_kind,
           verified_at = excluded.verified_at,
           method = excluded.method,
           revoked_at = NULL`,
    )
        .bind(email.hash, user, email.schoolID, email.domainKind, now, method)
        .run();
}

/// Moves a website account into an app account; never fails the caller.
async function mergeQuietly(env: Env, deps: AppleDeps, webUser: string, appUser: string) {
    try {
        const report = await deps.merge(env, webUser, appUser);
        if (report.errors.length) console.error(`merge ${webUser} -> ${appUser}:`, report.errors.slice(0, 20));
        await moveAppleLink(env, webUser, appUser);
        return { rewritten: report.rewritten, complete: report.profileDeleted };
    } catch (error) {
        console.error(`merge ${webUser} -> ${appUser} failed`, error);
        return { rewritten: 0, complete: false };
    }
}

// MARK: - Tickets (website: Apple first, then the email code)

async function issueTicket(env: Env, appleHash: string): Promise<string> {
    const ticket = randomToken();
    const now = nowSeconds();
    await env.DB.prepare(
        `INSERT INTO apple_tickets (ticket_hash, apple_hash, created_at, expires_at) VALUES (?, ?, ?, ?)`,
    )
        .bind(await hmacHex(env.CODE_PEPPER, `appleticket:${ticket}`), appleHash, now, now + APPLE_TICKET_TTL_SECONDS)
        .run();
    return ticket;
}

export interface AppleTicket {
    ticket_hash: string;
    apple_hash: string;
    email_cipher: string | null;
    expires_at: number;
    used_at: number | null;
}

/// The unexpired, unused ticket, or null.
export async function readTicket(env: Env, ticket: unknown): Promise<AppleTicket | null> {
    const value = String(ticket ?? "").trim();
    if (!value) return null;
    const row = await env.DB.prepare(`SELECT * FROM apple_tickets WHERE ticket_hash = ?`)
        .bind(await hmacHex(env.CODE_PEPPER, `appleticket:${value}`))
        .first<AppleTicket>();
    if (!row || row.used_at || row.expires_at < nowSeconds()) return null;
    return row;
}

async function spendTicket(env: Env, ticket: AppleTicket) {
    await env.DB.prepare(`UPDATE apple_tickets SET used_at = ? WHERE ticket_hash = ?`).bind(nowSeconds(), ticket.ticket_hash).run();
}

/// What a proven school email means for the Apple ID that came with it. Decided
/// before the email code is spent, so a conflict leaves the code usable with
/// another address.
export type ApplePlan =
    | { kind: "error"; status: number; code: string; message: string }
    /// Link the Apple ID to `user`. `verify`: the account (an app account whose
    /// email was never verified) gets this email as its verified school email.
    /// `mergeWeb`: a website account that already owns this email, merged in.
    | { kind: "account"; user: string; verify: boolean; mergeWeb?: string }
    /// Nobody owns the email: link once the website account is created.
    | { kind: "new" };

export async function planForEmail(env: Env, ticket: AppleTicket, emailHash: string): Promise<ApplePlan> {
    const linked = (await linkByApple(env, ticket.apple_hash))?.user_record_name ?? null;
    const owner = await ownerOfEmail(env, emailHash);

    if (linked) {
        const theirs = await verifiedEmailOf(env, linked);
        if (theirs && theirs.email_hash !== emailHash) {
            return {
                kind: "error",
                status: 409,
                code: "apple_email_mismatch",
                message: "Your Apple ID belongs to a Nexus account with a different school email. Use that email.",
            };
        }
        if (theirs) return { kind: "account", user: linked, verify: false };
        // The app account was never verified: this email verifies it.
        if (owner && owner !== linked && !owner.startsWith(WEB_PREFIX)) {
            return { kind: "error", status: 409, code: "email_taken", message: "That email is already linked to another Nexus account." };
        }
        return { kind: "account", user: linked, verify: true, ...(owner && owner !== linked ? { mergeWeb: owner } : {}) };
    }

    if (owner) {
        const other = await linkByUser(env, owner);
        if (other && other.apple_hash !== ticket.apple_hash) {
            return {
                kind: "error",
                status: 409,
                code: "apple_taken",
                message: "That Nexus account is already linked to a different Apple ID. Sign in with your email instead.",
            };
        }
        return { kind: "account", user: owner, verify: false };
    }
    return { kind: "new" };
}

/// Carries out a plan once the email code is spent. Returns the account the
/// website should sign in, and whether the app account was verified just now.
export async function applyPlan(
    env: Env,
    deps: AppleDeps,
    plan: Exclude<ApplePlan, { kind: "error" }>,
    ticket: AppleTicket,
    email: { address: string; hash: string; schoolID: string; domainKind: string },
): Promise<{ user?: string; verifiedApp: boolean; mergedWebAccount?: { rewritten: number; complete: boolean } }> {
    const cipher = await sealEmail(env, email.address);
    if (plan.kind === "new") {
        // Linked by /v1/web/account/create once the account exists.
        await env.DB.prepare(`UPDATE apple_tickets SET email_cipher = ? WHERE ticket_hash = ?`).bind(cipher, ticket.ticket_hash).run();
        return { verifiedApp: false };
    }
    if (plan.verify) await verifyAccount(env, deps, plan.user, email, "web");
    await saveLink(env, ticket.apple_hash, plan.user, "web", cipher);
    await spendTicket(env, ticket);
    const mergedWebAccount = plan.mergeWeb ? await mergeQuietly(env, deps, plan.mergeWeb, plan.user) : undefined;
    return { user: plan.user, verifiedApp: plan.verify, ...(mergedWebAccount ? { mergedWebAccount } : {}) };
}

/// After /v1/web/account/create: the new website account gets the Apple ID.
export async function linkNewWebAccount(env: Env, ticket: AppleTicket, user: string): Promise<boolean> {
    if ((await linkByApple(env, ticket.apple_hash)) || (await linkByUser(env, user))) return false;
    await saveLink(env, ticket.apple_hash, user, "web", ticket.email_cipher);
    await spendTicket(env, ticket);
    return true;
}

// MARK: - Website: sign in with Apple

function authorizedWebClient(request: Request, env: Env): Response | null {
    if (!env.WEB_CLIENT_TOKEN || !env.APPLE_WEB_CLIENT_ID) return errorResponse("not_found", "Unknown endpoint.", 404);
    const presented = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!constantTimeEqual(presented, env.WEB_CLIENT_TOKEN)) return errorResponse("forbidden", "Bad client token.", 403);
    return null;
}

export async function handleWebAppleSession(request: Request, env: Env, deps: AppleDeps = defaultAppleDeps): Promise<Response> {
    const denied = authorizedWebClient(request, env);
    if (denied) return denied;

    const body = await readJSON(request);
    const idToken = String(body?.idToken ?? "");
    const nonce = String(body?.nonce ?? "");
    if (!idToken || !nonce) return errorResponse("bad_request", "Missing token.", 400);

    const ip = (request.headers.get("x-nexus-client-ip") ?? "").trim() || "unknown";
    if (await checkAllRateLimits(env, [{ dimension: "web_apple_ip", value: ip, limit: 30, windowSeconds: 3600 }])) {
        return errorResponse("rate_limited", "Too many attempts. Try again later.", 429);
    }

    let claims: AppleClaims;
    try {
        claims = await verifyAppleToken(idToken, { audience: env.APPLE_WEB_CLIENT_ID!, nonce, keys: deps.keys });
    } catch (error) {
        console.warn("web apple token refused:", error instanceof Error ? error.message : error);
        return errorResponse("apple_refused", "Sign in with Apple didn't go through. Try again.", 401);
    }

    const appleHash = await appleHashOf(env, claims.sub);
    const link = await linkByApple(env, appleHash);
    if (link) {
        const verified = await verifiedEmailOf(env, link.user_record_name);
        const email = await openEmail(env, link.email_cipher);
        if (verified && email && constantTimeEqual(await emailHashOf(env, email), verified.email_hash)) {
            return json({
                signedIn: {
                    email,
                    schoolID: verified.school_id,
                    schoolName: await schoolName(env, verified.school_id),
                    domainKind: verified.domain_kind,
                    userRecordName: link.user_record_name,
                },
            });
        }
        // "verify": an app account with no school email yet. "confirm": verified,
        // but this service can't name the address, so it's asked for once.
        return json({ needsEmail: true, appleTicket: await issueTicket(env, appleHash), reason: verified ? "confirm" : "verify" });
    }
    return json({ needsEmail: true, appleTicket: await issueTicket(env, appleHash), reason: "new" });
}

async function readJSON(request: Request): Promise<Record<string, unknown> | null> {
    try {
        const parsed = await request.json();
        return typeof parsed === "object" && parsed !== null ? (parsed as Record<string, unknown>) : null;
    } catch {
        return null;
    }
}
