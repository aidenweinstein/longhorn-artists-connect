import { isCloudKitConfigured, lookup, str } from "@/lib/cloudkit/client";
import type { Session } from "@/lib/session";

/**
 * Alumni (added 2026-11-20). Alumni sign up with any email and the school they graduated
 * from, and can only look around until a moderator approves them on /admin/alumni: no
 * posting, connecting or messaging. verification-service records them as
 * "alumni_pending" until then and "alumni" after (verification-service/src/alumni.ts).
 */
export const ALUMNI_PENDING = "alumni_pending";
export const ALUMNI = "alumni";

export const isAlumniKind = (kind: string | undefined) => kind === ALUMNI || kind === ALUMNI_PENDING;

/** What a waiting alum sees when they try to post, connect or message. */
export const ALUMNI_WAITING =
  "Your alumni account is waiting for a moderator to approve it. Until then you can look around, but not post, connect or message.";

/**
 * Whether this visitor is an alum a moderator hasn't approved yet. The session says what
 * they were when they signed in, so an alum's approval is read fresh from their
 * Verification record, which the service updates when they're approved.
 */
export async function isPendingAlum(session: Session | null | undefined): Promise<boolean> {
  if (!session?.userRecordName || !isAlumniKind(session.domainKind)) return false;
  if (!isCloudKitConfigured()) return session.domainKind === ALUMNI_PENDING;
  try {
    const record = await lookup(`Verification_${session.userRecordName}`);
    return !record || str(record, "domainKind") !== ALUMNI;
  } catch {
    // Can't tell right now: go by the sign-in rather than lock out an approved alum.
    return session.domainKind === ALUMNI_PENDING;
  }
}

/** ALUMNI_WAITING for a waiting alum, else null. */
export async function alumniHold(session: Session | null | undefined): Promise<string | null> {
  return (await isPendingAlum(session)) ? ALUMNI_WAITING : null;
}
