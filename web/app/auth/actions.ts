"use server";

import { cookies, headers } from "next/headers";
import { updateTag } from "next/cache";
import { PROFILES_TAG, accountTag } from "@/lib/cloudkit/content";
import { CREATIVE_ALL_TAG, creativeTag, writeCreativeProfile } from "@/lib/cloudkit/creative";
import { callPeople } from "@/lib/featured";
import { STYLE_INFO, emptyDetails, isProfileStyle } from "@/lib/profileStyle";
import { SESSION_COOKIE, SESSION_COOKIE_OPTIONS, decodeSession, encodeSession, type Session } from "@/lib/session";
import { confirmCode, createAccount, requestCode, type RequestResult } from "@/lib/verification";

async function clientIP(): Promise<string> {
  const h = await headers();
  return h.get("x-forwarded-for")?.split(",")[0]?.trim() || h.get("x-real-ip") || "unknown";
}

async function startSession(session: Omit<Session, "issuedAt">) {
  (await cookies()).set(
    SESSION_COOKIE,
    encodeSession({ ...session, issuedAt: Math.floor(Date.now() / 1000) }),
    SESSION_COOKIE_OPTIONS,
  );
}

export async function requestCodeAction(email: string): Promise<RequestResult> {
  return requestCode(email, await clientIP());
}

/**
 * Confirms the email code and signs the visitor in. `hasAccount` is false when no
 * Nexus account owns this email yet; the visitor then finishes sign-up to create one.
 */
export async function confirmCodeAction(
  pendingID: string,
  code: string,
): Promise<{ ok: true; hasAccount: boolean } | { ok: false; message: string }> {
  if (!/^\d{6}$/.test(code)) return { ok: false, message: "Enter the 6-digit code." };

  const result = await confirmCode(pendingID, code, await clientIP());
  if (!result.ok) return result;

  await startSession({
    email: result.email,
    schoolID: result.schoolID,
    schoolName: result.schoolName,
    domainKind: result.domainKind,
    userRecordName: result.userRecordName,
    accountToken: result.userRecordName ? undefined : result.accountToken,
  });
  return { ok: true, hasAccount: !!result.userRecordName };
}

export type NewAccount = {
  firstName: string;
  lastName: string;
  major: string;
  classOf: string;
  style: string;
};

/**
 * The last step of sign-up: creates the visitor's Nexus account in CloudKit, the
 * same records the app reads, so it shows up in the app's directory and can post,
 * be credited and message from the website. Then saves their profile style.
 */
export async function createAccountAction(
  input: NewAccount,
): Promise<{ ok: true } | { ok: false; message: string; signInAgain?: boolean }> {
  const session = decodeSession((await cookies()).get(SESSION_COOKIE)?.value);
  if (!session) return { ok: false, message: "Your sign-in expired. Sign in again to finish.", signInAgain: true };
  if (session.userRecordName) return { ok: true }; // already has one
  if (!session.accountToken) {
    return { ok: false, message: "Your sign-in expired. Sign in again to finish.", signInAgain: true };
  }

  const firstName = input.firstName.trim();
  const lastName = input.lastName.trim();
  if (!firstName || !lastName) return { ok: false, message: "Enter your first and last name." };
  if (!/^\d{4}$/.test(input.classOf)) return { ok: false, message: "Pick your graduation year." };

  const result = await createAccount(
    session.accountToken,
    { firstName, lastName, major: input.major.trim(), graduationYear: input.classOf },
    await clientIP(),
  );
  if (!result.ok) return result;

  const user = result.userRecordName;
  await startSession({
    email: session.email,
    schoolID: session.schoolID,
    schoolName: session.schoolName,
    domainKind: session.domainKind,
    userRecordName: user, // and the spent accountToken is dropped
  });

  if (isProfileStyle(input.style)) {
    const error = await writeCreativeProfile(user, input.style, emptyDetails());
    if (error) console.error("[signup] style:", error);
    // Ask the moderators to list them on their style's People page, as picking a style does.
    try {
      await callPeople("apply", {
        category: STYLE_INFO[input.style].slug,
        email: session.email,
        profileID: `UserProfile_${user}`,
        name: `${firstName} ${lastName}`,
        message: `Picked the ${input.style} profile style on Nexus.`,
        links: "",
      });
    } catch (error) {
      console.error("[signup] apply:", error instanceof Error ? error.message : error);
    }
    updateTag(creativeTag(user));
    updateTag(CREATIVE_ALL_TAG);
  }
  updateTag(accountTag(user));
  updateTag(PROFILES_TAG);
  return { ok: true };
}

export async function signOutAction(): Promise<void> {
  (await cookies()).delete(SESSION_COOKIE);
}
