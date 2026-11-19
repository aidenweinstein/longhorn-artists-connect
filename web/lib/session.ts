import { createHmac, timingSafeEqual } from "node:crypto";

export const SESSION_COOKIE = "nexus_session";
/** Signed in for a year on this device; any visit after a week renews it (see proxy.ts), so regular use never expires. */
export const SESSION_MAX_AGE = 60 * 60 * 24 * 365;
/** A session older than this is re-issued with a fresh date the next time its owner visits. */
export const SESSION_RENEW_AFTER = 60 * 60 * 24 * 7;

/** Cookie settings shared by sign-in and renewal. maxAge makes it persist after the browser closes. */
export const SESSION_COOKIE_OPTIONS = {
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "lax" as const,
  path: "/",
  maxAge: SESSION_MAX_AGE,
};

/**
 * A web session proves control of a school email address. When an account owns
 * that address, `userRecordName` names it: an app account (verified in the app)
 * or a website account (`web_<id>`, made at sign-up on the site). When no
 * account owns it yet, `accountToken` lets this visitor create one; see
 * createAccountAction in app/auth/actions.ts.
 */
export interface Session {
  email: string;
  schoolID: string;
  schoolName: string;
  domainKind: string;
  issuedAt: number;
  userRecordName?: string;
  /** One-time token from verification-service to create an account for `email`. */
  accountToken?: string;
}

function secret(): string {
  const value = process.env.SESSION_SECRET;
  if (value && value.length >= 32) return value;
  if (process.env.NODE_ENV !== "production") return "dev-only-session-secret-not-for-production-use";
  throw new Error("SESSION_SECRET must be set (32+ characters).");
}

function sign(payload: string): string {
  return createHmac("sha256", secret()).update(payload).digest("base64url");
}

/** An HMAC of `value` under the session secret, for tokens handed to the browser. */
export function signValue(value: string): string {
  return sign(value);
}

export function encodeSession(session: Session): string {
  const payload = Buffer.from(JSON.stringify(session)).toString("base64url");
  return `${payload}.${sign(payload)}`;
}

/**
 * A guest pass proves the visitor confirmed an email address (any address, by the
 * same 6-digit code as sign-in) and lets them browse without an account. It is
 * signed differently from a session, so it can never be presented as one.
 */
export const GUEST_COOKIE = "nexus_guest";
export const GUEST_COOKIE_OPTIONS = SESSION_COOKIE_OPTIONS;

export interface GuestPass {
  email: string;
  issuedAt: number;
}

export function encodeGuestPass(email: string): string {
  const payload = Buffer.from(JSON.stringify({ email, issuedAt: Math.floor(Date.now() / 1000) })).toString("base64url");
  return `${payload}.${sign(`guest:${payload}`)}`;
}

/**
 * The guest pass this site issued, if it's unexpired. An unsigned cookie (the old "1") is not one.
 * Like a session it lasts a year and proxy.ts renews it after a week, so a guest confirms
 * their email once per device and stays in as long as they keep visiting.
 */
export function decodeGuestPass(value: string | undefined): GuestPass | null {
  if (!value) return null;
  const [payload, signature] = value.split(".");
  if (!payload || !signature) return null;

  const expected = Buffer.from(sign(`guest:${payload}`));
  const presented = Buffer.from(signature);
  if (expected.length !== presented.length || !timingSafeEqual(expected, presented)) return null;

  try {
    const pass = JSON.parse(Buffer.from(payload, "base64url").toString()) as Partial<GuestPass>;
    const issuedAt = Number(pass.issuedAt);
    const ageSeconds = Date.now() / 1000 - issuedAt;
    return pass.email && ageSeconds >= 0 && ageSeconds < SESSION_MAX_AGE ? { email: pass.email, issuedAt } : null;
  } catch {
    return null;
  }
}

/** True for an unexpired guest pass this site issued. */
export function hasGuestPass(value: string | undefined): boolean {
  return decodeGuestPass(value) !== null;
}

/**
 * Guests (a guest pass, no sign-in) only see the Home feed with every school's posts,
 * each school's own home page, and the posts opened from those feeds. Everything else
 * (Discover, Share, Network, Portfolio, people pages...) needs an account.
 */
export function guestCanSee(pathname: string): boolean {
  const path = pathname.replace(/\/+$/, "") || "/";
  return path === "/" || path.startsWith("/school/") || path.startsWith("/post/");
}

export function decodeSession(value: string | undefined): Session | null {
  if (!value) return null;
  const [payload, signature] = value.split(".");
  if (!payload || !signature) return null;

  const expected = Buffer.from(sign(payload));
  const presented = Buffer.from(signature);
  if (expected.length !== presented.length || !timingSafeEqual(expected, presented)) return null;

  try {
    const session = JSON.parse(Buffer.from(payload, "base64url").toString()) as Session;
    const ageSeconds = Date.now() / 1000 - session.issuedAt;
    return ageSeconds >= 0 && ageSeconds < SESSION_MAX_AGE ? session : null;
  } catch {
    return null;
  }
}
