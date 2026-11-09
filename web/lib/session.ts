import { createHmac, timingSafeEqual } from "node:crypto";

export const SESSION_COOKIE = "nexus_session";
export const SESSION_MAX_AGE = 60 * 60 * 24 * 30;

/**
 * A web session proves control of a school email address. When the app already
 * verified that same address, `userRecordName` names that app account, so the
 * site can show its profile and record that account's own likes and reports (the
 * same proof the app accepted). It never edits anyone's posts or profile.
 */
export interface Session {
  email: string;
  schoolID: string;
  schoolName: string;
  domainKind: string;
  issuedAt: number;
  userRecordName?: string;
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

export function encodeSession(session: Session): string {
  const payload = Buffer.from(JSON.stringify(session)).toString("base64url");
  return `${payload}.${sign(payload)}`;
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
