/// Website sign-in: proves control of a school email address and nothing else.
///
/// Routes (called server-to-server by the Nexus website, never by a browser):
///   POST /v1/web/session/request   { email, purpose? }  -> { pendingID, expiresAt, school }
///   POST /v1/web/session/confirm   { pendingID, code, appleTicket? }
///                                                       -> { email, schoolID, schoolName, domainKind, userRecordName? | accountToken?, apple? }
///   POST /v1/web/account/create    { accountToken, firstName, lastName, major, graduationYear, appleTicket? }
///                                                       -> { userRecordName, schoolName, created }
///
/// Unlike /v1/verify/*, there is no userRecordName and no nonce. A web session
/// claims no CloudKit account, so there is no account ownership to prove — and
/// for the same reason a confirmed web session must never be treated as an app
/// identity or used as authority over any user's records.
///
/// Website accounts (added 2026-11-12): when the confirmed email has no account
/// yet, confirm also returns a one-time `accountToken`. Spending it at
/// /v1/web/account/create makes a Nexus account owned by the website, named
/// `web_<id>`: its CloudKit `UserProfile_web_<id>` and `Verification_web_<id>`
/// are written here with the server key, and the email is linked to it in
/// verified_emails exactly as the app's flow links an iCloud account. From then
/// on, signing in on the website with that email returns `userRecordName:
/// "web_<id>"`. These accounts exist for people who can't run the iOS app.
///
/// Guests (added 2026-11-16): `purpose: "guest"` on request confirms ANY address
/// the visitor controls, not a school one, like the app's Enthusiast flow. Its
/// confirm returns `domainKind: "guest"` with no school, no account and no
/// `accountToken`: a guest can browse the website and nothing else, so proving a
/// personal address must never lead to a school account.
///
/// Alumni (added 2026-11-20): `purpose: "alumni"` with a `schoolID` confirms any
/// address too, for someone who graduated from that school. It works like a
/// school sign-in, but the account it creates is "alumni_pending" until a
/// moderator approves it (src/alumni.ts). Later sign-ins with that address need
/// no purpose: an address already linked to an account always signs in to it.
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
import { createUserProfile, writeVerificationRecord } from "./cloudkit";
import { applyPlan, defaultAppleDeps, linkNewWebAccount, planForEmail, readTicket, type AppleDeps } from "./apple";
import { ALUMNI_PENDING_KIND, alumniKindFor, alumniSchool, isAlumniKind, queueAlumniReview } from "./alumni";

export const WEB_CODE_TTL_SECONDS = 600;
export const WEB_MAX_CODE_ATTEMPTS = 5;
/// How long after signing in someone has to finish creating their account.
export const WEB_ACCOUNT_TOKEN_TTL_SECONDS = 24 * 3600;
/// Every website account's userRecordName starts with this.
export const WEB_ACCOUNT_PREFIX = "web_";

/// `domain_kind` of a guest's pending session: any email, no school.
export const WEB_GUEST_KIND = "guest";

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

    // Guests confirm any address they control, so the school registry doesn't apply,
    // and so do alumni, who name their school instead (src/alumni.ts).
    const isGuest = body.purpose === WEB_GUEST_KIND;
    const isAlumni = body.purpose === "alumni";
    let match: DomainMatch | null = isGuest
        ? { schoolID: "", schoolName: "", kind: WEB_GUEST_KIND }
        : isAlumni
            ? await alumniSchool(env, String(body.schoolID ?? ""))
            : await lookupDomain(env, domain);
    if (!match && isAlumni) {
        return errorResponse("unknown_school", "Pick the school you graduated from.", 422);
    }
    // Not a school address, but it already belongs to an alum's account (their
    // personal email): signing in with it opens that account.
    const alumAccount = !match && !isGuest ? await alumniSignIn(env, emailHash) : null;
    if (alumAccount) match = alumAccount;
    if (!match) {
        return errorResponse(
            "unsupported_domain",
            "We don't recognise that school's email domain yet.",
            422,
        );
    }
    // A school's alumni address (e.g. @alumni.utexas.edu) isn't a student one. Alumni
    // sign up with purpose "alumni" instead, and then sign in with that address.
    if (match.kind === "alumni" && !alumAccount) {
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

    await sendVerificationCode(env, { to: email, code, schoolName: match.schoolName, context: isGuest ? "guest" : "web" });

    return json({
        pendingID,
        expiresAt: now + WEB_CODE_TTL_SECONDS,
        school: { id: match.schoolID, name: match.schoolName },
    });
}

/// `appleTicket` (from /v1/web/apple/session) links the visitor's Apple ID once
/// the email is proven; see planForEmail in src/apple.ts. When that Apple ID
/// belongs to an app account with no verified email, this email verifies the
/// app account too.
export async function handleWebSessionConfirm(request: Request, env: Env, appleDeps: AppleDeps = defaultAppleDeps): Promise<Response> {
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

    // Sign in with Apple came first: decide what this email means for that Apple ID
    // before spending the code, so a conflict leaves it usable with another address.
    const wantsApple = !!body.appleTicket && pending.domain_kind !== WEB_GUEST_KIND;
    const appleTicket = wantsApple ? await readTicket(env, body.appleTicket) : null;
    if (wantsApple && !appleTicket) {
        return errorResponse("apple_expired", "Your Sign in with Apple timed out. Start again.", 401);
    }
    const plan = appleTicket ? await planForEmail(env, appleTicket, pending.email_hash) : null;
    if (plan?.kind === "error") return errorResponse(plan.code, plan.message, plan.status);

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

    // A guest proved an address and nothing more: no school, no account lookup,
    // and above all no token that could create an account.
    if (pending.domain_kind === WEB_GUEST_KIND) {
        return json({ email: pending.email_normalized, schoolID: "", schoolName: "", domainKind: WEB_GUEST_KIND });
    }

    // Link the Apple ID (and, for an unverified app account, verify it with this email).
    const apple = plan && appleTicket
        ? await applyPlan(env, appleDeps, plan, appleTicket, {
            address: pending.email_normalized,
            hash: pending.email_hash,
            schoolID: pending.school_id,
            domainKind: pending.domain_kind,
        })
        : null;

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

    // No account owns this email yet: hand back a token that can create one.
    let accountToken: string | undefined;
    if (!linked) {
        accountToken = randomToken();
        const now = nowSeconds();
        await env.DB.prepare(
            `INSERT INTO web_account_claims
               (token_hash, email_hash, school_id, domain_kind, created_at, expires_at)
             VALUES (?, ?, ?, ?, ?, ?)`,
        )
            .bind(
                await hmacHex(env.CODE_PEPPER, `claim:${accountToken}`),
                pending.email_hash,
                pending.school_id,
                pending.domain_kind,
                now,
                now + WEB_ACCOUNT_TOKEN_TTL_SECONDS,
            )
            .run();
    }

    return json({
        email: pending.email_normalized,
        schoolID: pending.school_id,
        schoolName: school?.name ?? "",
        domainKind: pending.domain_kind,
        ...(linked ? { userRecordName: linked.user_record_name } : {}),
        ...(accountToken ? { accountToken } : {}),
        ...(apple
            ? { apple: { linked: !!apple.user, verifiedApp: apple.verifiedApp, ...(apple.mergedWebAccount ? { mergedWebAccount: apple.mergedWebAccount } : {}) } }
            : {}),
    });
}

// MARK: - Website accounts

/// The CloudKit writes account creation needs; swapped for fakes in tests.
export interface AccountWriter {
    createProfile: typeof createUserProfile;
    writeVerification: typeof writeVerificationRecord;
}

const cloudKitWriter: AccountWriter = {
    createProfile: createUserProfile,
    writeVerification: writeVerificationRecord,
};

/// Fields the app writes only once Production's schema has them; see
/// `writeAccountKindFields` in UserProfileModel.swift.
const OPTIONAL_PROFILE_FIELDS = ["accountKind", "schoolRole"] as const;

const cleanText = (value: unknown, max: number) =>
    String(value ?? "").replace(/\s+/g, " ").trim().slice(0, max);

export async function handleWebAccountCreate(
    request: Request,
    env: Env,
    writer: AccountWriter = cloudKitWriter,
): Promise<Response> {
    const denied = authorizeWebClient(request, env);
    if (denied) return denied;

    const body = await readJSON(request);
    if (!body) return errorResponse("bad_request", "Malformed body.", 400);

    const token = String(body.accountToken ?? "").trim();
    const firstName = cleanText(body.firstName, 50);
    const lastName = cleanText(body.lastName, 50);
    const major = cleanText(body.major, 100);
    const graduationYear = cleanText(body.graduationYear, 4);
    // Role tags picked at sign-up, as the app stores them: "Director, Editor".
    const userTypes = cleanText(body.userTypes, 400);
    if (!token) return errorResponse("bad_request", "Missing account token.", 400);
    if (!firstName || !lastName) return errorResponse("bad_request", "Enter your first and last name.", 400);
    // Educators (chosen at sign-up) have no graduation year and are made Professors.
    const educator = body.role === "educator";
    // Alumni (an "alumni" sign-in, see src/alumni.ts) give the year they graduated.
    if (!educator && !/^\d{4}$/.test(graduationYear)) return errorResponse("bad_request", "Pick your graduation year.", 400);

    if (await checkAllRateLimits(env, [
        { dimension: "web_account_ip", value: endUserIP(request), limit: 10, windowSeconds: 3600 },
    ])) {
        return errorResponse("rate_limited", "Too many attempts. Try again later.", 429);
    }

    const tokenHash = await hmacHex(env.CODE_PEPPER, `claim:${token}`);
    const claim = await env.DB.prepare(`SELECT * FROM web_account_claims WHERE token_hash = ?`)
        .bind(tokenHash)
        .first<any>();
    if (!claim || claim.expires_at < nowSeconds()) {
        return errorResponse("expired_token", "Your sign-in expired. Sign in again to finish creating your account.", 401);
    }

    // Already linked (a double submit, or the app verified this email meanwhile):
    // never make a second account for one address.
    const existing = await env.DB.prepare(
        `SELECT user_record_name FROM verified_emails WHERE email_hash = ? AND revoked_at IS NULL`,
    )
        .bind(claim.email_hash)
        .first<{ user_record_name: string }>();
    if (existing) {
        return json({ userRecordName: existing.user_record_name, schoolName: "", created: false });
    }
    // Signed in with Apple first: the new account gets that Apple ID (below).
    const appleTicket = body.appleTicket ? await readTicket(env, body.appleTicket) : null;

    // Spend the token. The conditional update means two concurrent creates can't both proceed.
    const spent = await env.DB.prepare(
        `UPDATE web_account_claims SET used_at = ? WHERE token_hash = ? AND used_at IS NULL`,
    )
        .bind(nowSeconds(), tokenHash)
        .run();
    if (!spent.meta?.changes) {
        return errorResponse("token_used", "This account is already being created. Refresh the page.", 409);
    }

    const school = await env.DB.prepare(`SELECT name FROM schools WHERE id = ?`)
        .bind(claim.school_id)
        .first<{ name: string }>();
    const schoolName = school?.name ?? "";
    const domainKind: string = claim.domain_kind ?? "student";
    const alumni = isAlumniKind(domainKind);
    const userRecordName = `${WEB_ACCOUNT_PREFIX}${crypto.randomUUID().replace(/-/g, "")}`;
    const now = nowSeconds();

    // Link the email first: the UNIQUE email_hash key is the final guard against a duplicate.
    try {
        await env.DB.prepare(
            `INSERT INTO verified_emails
               (email_hash, user_record_name, school_id, domain_kind, verified_at, method)
             VALUES (?, ?, ?, ?, ?, 'web')`,
        )
            .bind(claim.email_hash, userRecordName, claim.school_id, domainKind, now)
            .run();
    } catch {
        return errorResponse("email_taken", "That email already has an account. Sign in again.", 409);
    }

    try {
        // Mirrors UserProfileModel.toCloudKitRecord for a new school member.
        await writer.createProfile(env, `UserProfile_${userRecordName}`, {
            firstName: { value: firstName },
            lastName: { value: lastName },
            major: { value: major },
            minor: { value: "" },
            certificate: { value: "" },
            graduationYear: { value: educator ? "" : graduationYear },
            userTypes: { value: userTypes },
            bio: { value: "" },
            instagramHandle: { value: "" },
            websiteURL: { value: "" },
            isUTStudent: { value: 1 },
            school: { value: schoolName },
            industry: { value: "" },
            company: { value: "" },
            companyRole: { value: "" },
            isIndustryProfessional: { value: 0 },
            accountKind: { value: "Artist" },
            schoolRole: { value: alumni ? "Alumni" : educator || domainKind === "staff" ? "Professor" : "Student" },
        }, OPTIONAL_PROFILE_FIELDS);
        await writer.writeVerification(env, {
            userRecordName,
            emailHash: claim.email_hash,
            schoolID: claim.school_id,
            schoolName,
            domainKind,
            verifiedAt: now,
            method: "web",
        });
    } catch (error) {
        console.error("web account create failed", error);
        // Undo the link and give the token back so the person can simply retry.
        await env.DB.batch([
            env.DB.prepare(`DELETE FROM verified_emails WHERE email_hash = ? AND user_record_name = ?`)
                .bind(claim.email_hash, userRecordName),
            env.DB.prepare(`UPDATE web_account_claims SET used_at = NULL WHERE token_hash = ?`).bind(tokenHash),
        ]);
        return errorResponse("create_failed", "Couldn't create your account. Try again in a moment.", 502);
    }

    // A new alum waits for a moderator. The website passes the address they signed in
    // with (this service only keeps its hash) so moderators can tell who they are.
    if (domainKind === ALUMNI_PENDING_KIND) {
        await queueAlumniReview(env, userRecordName, claim.school_id, cleanText(body.email, 254)).catch((error) => {
            console.error("alumni review queue failed", error);
        });
    }

    const appleLinked = appleTicket
        ? await linkNewWebAccount(env, appleTicket, userRecordName).catch((error) => {
            console.error("apple link after create failed", error);
            return false;
        })
        : false;

    return json({ userRecordName, schoolName, created: true, ...(appleTicket ? { appleLinked } : {}) });
}

async function readJSON(request: Request): Promise<Record<string, unknown> | null> {
    try {
        const parsed = await request.json();
        return typeof parsed === "object" && parsed !== null ? (parsed as Record<string, unknown>) : null;
    } catch {
        return null;
    }
}

/// An address that isn't a school one but belongs to an alum's account: signing in
/// with it opens that account, as the alum's school (and approval) on file.
async function alumniSignIn(env: Env, emailHash: string): Promise<DomainMatch | null> {
    const row = await env.DB.prepare(
        `SELECT v.user_record_name, v.school_id, v.domain_kind, s.name AS school_name
         FROM verified_emails v LEFT JOIN schools s ON s.id = v.school_id
         WHERE v.email_hash = ? AND v.revoked_at IS NULL`,
    )
        .bind(emailHash)
        .first<{ user_record_name: string; school_id: string; domain_kind: string; school_name: string | null }>();
    if (!row || !isAlumniKind(row.domain_kind)) return null;
    return { schoolID: row.school_id, schoolName: row.school_name ?? "", kind: await alumniKindFor(env, row.user_record_name) };
}
