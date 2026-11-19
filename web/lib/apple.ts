import { randomBytes, timingSafeEqual } from "node:crypto";
import { signValue } from "./session";

export { appleAuthorizeURL, appleClientID, appleEnabled, appleRedirectURI } from "./appleConfig";

/**
 * Sign in with Apple on the website (added 2026-11-19).
 *
 * `/auth/apple` sends the visitor to Apple; Apple posts back to
 * `/auth/apple/callback` with an identity token, which verification-service
 * checks (`/v1/web/apple/session`). An Apple ID linked before signs straight in.
 * The first time, the visitor gets an Apple ticket cookie and the usual school
 * email code; confirming it links the Apple ID to the account that owns that
 * email (the app account, if they have one), or to the account sign-up creates.
 *
 * Needs APPLE_WEB_CLIENT_ID (the Services ID) and verification-service. Apple only
 * redirects to the https return URL registered on that Services ID, so this can't
 * be tried on localhost.
 */

export const APPLE_STATE_COOKIE = "nexus_apple_state";
export const APPLE_TICKET_COOKIE = "nexus_apple";

/** Why the email step is still needed after Apple. */
export type AppleReason = "new" | "verify" | "confirm";

export const randomValue = () => randomBytes(24).toString("base64url");

// MARK: - Signed cookie values

function seal(value: object): string {
  const payload = Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${payload}.${signValue(`apple:${payload}`)}`;
}

function open<T extends { exp: number }>(value: string | undefined): T | null {
  if (!value) return null;
  const [payload, signature] = value.split(".");
  if (!payload || !signature) return null;
  const expected = Buffer.from(signValue(`apple:${payload}`));
  const presented = Buffer.from(signature);
  if (expected.length !== presented.length || !timingSafeEqual(expected, presented)) return null;
  try {
    const parsed = JSON.parse(Buffer.from(payload, "base64url").toString()) as T;
    return parsed.exp > Date.now() / 1000 ? parsed : null;
  } catch {
    return null;
  }
}

/** The round trip to Apple: our state and nonce, for 10 minutes. */
export type AppleState = { state: string; nonce: string; exp: number };

export const encodeAppleState = (state: string, nonce: string) => seal({ state, nonce, exp: Math.floor(Date.now() / 1000) + 600 });
export const decodeAppleState = (value: string | undefined) => open<AppleState>(value);

/**
 * Apple's callback is a cross-site POST, which only carries cookies marked
 * SameSite=None (and so Secure). Scoped to the callback path.
 */
export const APPLE_STATE_COOKIE_OPTIONS = {
  httpOnly: true,
  secure: true,
  sameSite: "none" as const,
  path: "/auth/apple",
  maxAge: 600,
};

/** Apple confirmed; the school email step is still to come (30 minutes, as the service allows). */
export type AppleTicket = { ticket: string; reason: AppleReason; exp: number };

export const encodeAppleTicket = (ticket: string, reason: AppleReason) =>
  seal({ ticket, reason, exp: Math.floor(Date.now() / 1000) + 1800 });
export const decodeAppleTicket = (value: string | undefined) => open<AppleTicket>(value);

export const APPLE_TICKET_COOKIE_OPTIONS = {
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "lax" as const,
  path: "/",
  maxAge: 1800,
};
