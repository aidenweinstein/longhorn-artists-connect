"use server";

import { cookies, headers } from "next/headers";
import { updateTag } from "next/cache";
import { PROFILES_TAG, accountTag } from "@/lib/cloudkit/content";
import { CREATIVE_ALL_TAG, creativeTag, writeCreativeProfile } from "@/lib/cloudkit/creative";
import { callPeople } from "@/lib/featured";
import { updateFields, uploadAsset } from "@/lib/cloudkit/client";
import { ROLE_TAGS } from "@/lib/profileFields";
import { STYLE_INFO, emptyDetails, isProfileStyle } from "@/lib/profileStyle";
import {
  GUEST_COOKIE,
  GUEST_COOKIE_OPTIONS,
  SESSION_COOKIE,
  SESSION_COOKIE_OPTIONS,
  decodeSession,
  encodeGuestPass,
  encodeSession,
  type Session,
} from "@/lib/session";
import { domainList, isAnyEmail, isSchoolEmail, isSignupRole, signupSchool, type AccountRole, type SignupRole } from "@/lib/signupSchools";
import { isAlumniKind } from "@/lib/alumni";
import { confirmCode, createAccount, requestCode, type RequestResult } from "@/lib/verification";
import { APPLE_TICKET_COOKIE, decodeAppleTicket } from "@/lib/apple";

async function clientIP(): Promise<string> {
  const h = await headers();
  return h.get("x-forwarded-for")?.split(",")[0]?.trim() || h.get("x-real-ip") || "unknown";
}

/** Signed in with Apple and waiting on the school email step: the service's ticket. */
async function pendingAppleTicket(): Promise<string | undefined> {
  return decodeAppleTicket((await cookies()).get(APPLE_TICKET_COOKIE)?.value)?.ticket;
}

async function dropAppleTicket() {
  (await cookies()).delete(APPLE_TICKET_COOKIE);
}

async function startSession(session: Omit<Session, "issuedAt">) {
  (await cookies()).set(
    SESSION_COOKIE,
    encodeSession({ ...session, issuedAt: Math.floor(Date.now() / 1000) }),
    SESSION_COOKIE_OPTIONS,
  );
}

/**
 * Sends the email code. Sign-up passes the school the person picked and whether they're
 * a student or an educator, and the email must then be at that school's domain for them
 * (UT Austin students: @my.utexas.edu). Alumni use any address they control, with the
 * school they graduated from.
 */
export async function requestCodeAction(email: string, schoolID?: string, role?: AccountRole): Promise<RequestResult> {
  if (role === "alumni") {
    if (!signupSchool(schoolID)) return { ok: false, message: "Pick the school you graduated from." };
    if (!isAnyEmail(email)) return { ok: false, message: "That doesn't look like an email address." };
    return requestCode(email, await clientIP(), "alumni", schoolID);
  }
  if (schoolID !== undefined) {
    const school = signupSchool(schoolID);
    // Sign-in passes the school with no role: any of that school's domains will do.
    if (!school || (role !== undefined && !isSignupRole(role))) return { ok: false, message: "Pick your school first." };
    if (!isSchoolEmail(email, school, role)) {
      return { ok: false, message: `Use your ${domainList(school, role)} email address.` };
    }
  }
  return requestCode(email, await clientIP());
}

/**
 * Confirms the email code and signs the visitor in. `hasAccount` is false when no
 * Nexus account owns this email yet.
 * Sign-up passes the details it already collected as `account`: the account is then
 * created in this same request, straight from the verified code, so it never depends
 * on the session cookie making it back between two steps. `created` says it worked;
 * `createError` says why it didn't (the visitor is still signed in and can retry).
 * After Sign in with Apple, the code also links that Apple ID; `verifiedApp` says
 * this email just verified the person's app account too.
 */
export async function confirmCodeAction(
  pendingID: string,
  code: string,
  account?: NewAccount,
): Promise<
  | { ok: true; hasAccount: boolean; created?: boolean; createError?: string; signInAgain?: boolean; verifiedApp?: boolean }
  | { ok: false; message: string }
> {
  if (!/^\d{6}$/.test(code)) return { ok: false, message: "Enter the 6-digit code." };

  const appleTicket = await pendingAppleTicket();
  const result = await confirmCode(pendingID, code, await clientIP(), appleTicket);
  if (!result.ok) {
    // Apple's half timed out: drop it, so the next try is a plain email sign-in.
    if (result.error === "apple_expired") await dropAppleTicket();
    return { ok: false, message: result.message };
  }
  // A guest's code proves a personal address, never a school one: it can't sign anyone in.
  if (result.domainKind === "guest") return { ok: false, message: "Sign in with your school email address." };

  const session: Omit<Session, "issuedAt"> = {
    email: result.email,
    schoolID: result.schoolID,
    schoolName: result.schoolName,
    domainKind: result.domainKind,
    userRecordName: result.userRecordName,
    accountToken: result.userRecordName ? undefined : result.accountToken,
  };
  await startSession(session);
  if (result.apple?.linked) await dropAppleTicket();
  if (result.userRecordName) return { ok: true, hasAccount: true, verifiedApp: result.apple?.verifiedApp };
  if (!account) return { ok: true, hasAccount: false };

  const created = await createFromSession(session, account);
  if (created.ok) return { ok: true, hasAccount: false, created: true };
  return { ok: true, hasAccount: false, createError: created.message, signInAgain: created.signInAgain };
}

/** "Continue as guest", step 1: emails a code to any address the visitor gives. */
export async function requestGuestCodeAction(email: string): Promise<RequestResult> {
  return requestCode(email, await clientIP(), "guest");
}

/**
 * "Continue as guest", step 2: the code is right, so the visitor may browse. They get a
 * guest pass, not a session: no account, and nothing that needs one.
 */
export async function confirmGuestCodeAction(
  pendingID: string,
  code: string,
): Promise<{ ok: true } | { ok: false; message: string }> {
  if (!/^\d{6}$/.test(code)) return { ok: false, message: "Enter the 6-digit code." };

  const result = await confirmCode(pendingID, code, await clientIP());
  if (!result.ok) return result;

  (await cookies()).set(GUEST_COOKIE, encodeGuestPass(result.email), GUEST_COOKIE_OPTIONS);
  return { ok: true };
}

export type NewAccount = {
  firstName: string;
  lastName: string;
  major: string;
  classOf: string;
  /** Role tags picked at sign-up ("Director", "Editor"...); only the app's known tags are kept. */
  tags?: string[];
  /** Sign-up no longer asks for a profile style; one passed here is still saved. */
  style?: string;
  /** Educators give a department as `major` and have no class year; alumni give the year they graduated. */
  role?: AccountRole;
  /**
   * The profile picture, already resized to a JPEG by the browser. Required for a new
   * account: sign-up won't create one without it.
   */
  photo?: File;
};

const MAX_PHOTO_BYTES = 5 * 1024 * 1024;

/** Why this sign-up photo can't be used, or null when it's fine. */
function photoProblem(photo: unknown): string | null {
  if (!(photo instanceof Blob) || photo.size === 0) return "Add a profile picture.";
  if (photo.size > MAX_PHOTO_BYTES) return "That photo is too large. Try a smaller one.";
  if (!/^image\/(jpeg|png)$/.test(photo.type)) return "Use a JPEG or PNG photo.";
  return null;
}

/** Saves the profile picture on the account's UserProfile record, where the app reads it. */
async function savePhoto(user: string, photo: Blob): Promise<boolean> {
  const recordName = `UserProfile_${user}`;
  try {
    const profileImage = await uploadAsset("UserProfile", recordName, "profileImage", new Uint8Array(await photo.arrayBuffer()), photo.type);
    const error = await updateFields("UserProfile", recordName, { profileImage });
    if (error) console.error("[signup] photo:", error.code, error.reason);
    return !error;
  } catch (e) {
    console.error("[signup] photo:", e instanceof Error ? e.message : e);
    return false;
  }
}

const PHOTO_RETRY = "Your account was created, but your profile picture didn't upload. Try again.";

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
  return createFromSession(session, input);
}

/** Creates the account for a verified session that has an accountToken, then signs it in. */
async function createFromSession(
  session: Omit<Session, "issuedAt">,
  input: NewAccount,
): Promise<{ ok: true } | { ok: false; message: string; signInAgain?: boolean }> {
  if (session.userRecordName) {
    // Already made: this is Create account again after the profile picture didn't upload.
    if (!input.photo) return { ok: true };
    const problem = photoProblem(input.photo);
    if (problem) return { ok: false, message: problem };
    if (!(await savePhoto(session.userRecordName, input.photo))) return { ok: false, message: PHOTO_RETRY };
    updateTag(accountTag(session.userRecordName));
    updateTag(PROFILES_TAG);
    return { ok: true };
  }
  if (!session.accountToken) {
    return { ok: false, message: "Your sign-in expired. Sign in again to finish.", signInAgain: true };
  }

  // Alumni signed in with any address for the school they graduated from (purpose
  // "alumni"); everyone else with a school address.
  const alumni = isAlumniKind(session.domainKind);
  if (input.role === "alumni" && !alumni) {
    return { ok: false, message: "To join as an alum, start sign-up again and pick \"I'm an Alumni\".", signInAgain: true };
  }
  // Same rule as sign-up's email step, for someone who got here through Sign in:
  // at a sign-up school, a student needs its student address and an educator one of
  // its educator addresses.
  const role: SignupRole = input.role === "educator" ? "educator" : "student";
  const school = signupSchool(session.schoolID);
  if (!alumni && school && !isSchoolEmail(session.email, school, role)) {
    return {
      ok: false,
      message: `New ${school.name} ${role} accounts need an ${domainList(school, role)} email. Sign in again with that address.`,
      signInAgain: true,
    };
  }

  const firstName = input.firstName.trim();
  const lastName = input.lastName.trim();
  if (!firstName || !lastName) return { ok: false, message: "Enter your first and last name." };
  if ((alumni || role === "student") && !/^\d{4}$/.test(input.classOf)) return { ok: false, message: "Enter your graduation year as four digits, like 2028." };
  // Every new account needs a profile picture.
  const photoError = photoProblem(input.photo);
  if (photoError) return { ok: false, message: photoError };

  // Stored the way Edit profile stores them: the app's tags, sorted, comma-separated.
  const picked = Array.isArray(input.tags) ? input.tags : [];
  const userTypes = ROLE_TAGS.filter((tag) => picked.includes(tag)).sort().join(", ");

  const appleTicket = await pendingAppleTicket();
  const result = await createAccount(
    session.accountToken,
    alumni
      ? { firstName, lastName, major: input.major.trim(), graduationYear: input.classOf, userTypes, role: "alumni", email: session.email }
      : role === "educator"
        ? { firstName, lastName, major: input.major.trim(), graduationYear: "", userTypes, role }
        : { firstName, lastName, major: input.major.trim(), graduationYear: input.classOf, userTypes },
    await clientIP(),
    appleTicket,
  );
  if (!result.ok) return result;
  if (appleTicket) await dropAppleTicket();

  const user = result.userRecordName;
  await startSession({
    email: session.email,
    schoolID: session.schoolID,
    schoolName: session.schoolName,
    domainKind: session.domainKind,
    userRecordName: user, // and the spent accountToken is dropped
  });

  // The account exists now, so its UserProfile record can take the picture.
  const photoSaved = await savePhoto(user, input.photo!);

  const style = input.style;
  if (isProfileStyle(style)) {
    const error = await writeCreativeProfile(user, style, emptyDetails());
    if (error) console.error("[signup] style:", error);
    // Ask the moderators to list them on their style's People page, as picking a style does.
    try {
      await callPeople("apply", {
        category: STYLE_INFO[style].slug,
        email: session.email,
        profileID: `UserProfile_${user}`,
        name: `${firstName} ${lastName}`,
        message: `Picked the ${style} profile style on Nexus.`,
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
  // Signed in either way; Create account tries the picture again.
  if (!photoSaved) return { ok: false, message: PHOTO_RETRY };
  return { ok: true };
}

export async function signOutAction(): Promise<void> {
  const jar = await cookies();
  jar.delete(SESSION_COOKIE);
  // Signing out means out on this device: a guest pass from before the sign-in goes too.
  jar.delete(GUEST_COOKIE);
  await dropAppleTicket();
}
