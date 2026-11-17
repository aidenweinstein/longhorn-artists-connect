"use server";

import { cookies } from "next/headers";
import { isCloudKitConfigured } from "@/lib/cloudkit/client";
import { profileDirectory } from "@/lib/cloudkit/content";
import { SESSION_COOKIE, SESSION_COOKIE_OPTIONS, encodeSession } from "@/lib/session";

const PROFILE_PREFIX = "UserProfile_";

/**
 * TESTING ONLY: signs in without an email code. Works only under `npm run dev`
 * (NODE_ENV "development"); on a deployed site it refuses, whoever calls it.
 *
 * `name` picks which Nexus account to be, by its profile name (blank: signed in with
 * no account, as a brand-new email would be). The session's email is the first of
 * ADMIN_EMAILS, so the admin pages can be tested too.
 */
export async function devSkipSignInAction(name: string): Promise<{ ok: true; as: string } | { ok: false; message: string }> {
  if (process.env.NODE_ENV !== "development") return { ok: false, message: "Skipping sign-in is only available in development." };

  const wanted = name.trim().toLowerCase();
  let userRecordName: string | undefined;
  let as = "no account";
  if (wanted) {
    if (!isCloudKitConfigured()) return { ok: false, message: "CloudKit isn't set up here, so accounts can't be looked up. Leave the name blank." };
    const matches = (await profileDirectory()).filter((p) => p.name.trim().toLowerCase() === wanted);
    if (matches.length === 0) return { ok: false, message: `No Nexus profile is named "${name.trim()}". Type the name exactly as it shows on the profile.` };
    if (matches.length > 1) return { ok: false, message: `${matches.length} profiles are named "${name.trim()}", so this can't tell which one you mean.` };
    userRecordName = matches[0].id.startsWith(PROFILE_PREFIX) ? matches[0].id.slice(PROFILE_PREFIX.length) : matches[0].id;
    as = matches[0].name;
  }

  const email = (process.env.ADMIN_EMAILS ?? "").split(",").map((e) => e.trim()).filter(Boolean)[0] ?? "dev@my.utexas.edu";
  (await cookies()).set(
    SESSION_COOKIE,
    encodeSession({ email, schoolID: "ut-austin", schoolName: "UT Austin", domainKind: "student", userRecordName, issuedAt: Math.floor(Date.now() / 1000) }),
    SESSION_COOKIE_OPTIONS,
  );
  return { ok: true, as };
}
