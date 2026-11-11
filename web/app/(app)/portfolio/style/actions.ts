"use server";

import { cookies } from "next/headers";
import { updateTag } from "next/cache";
import { currentAccount, currentSession } from "@/lib/account";
import { CREATIVE_ALL_TAG, creativeTag, getCreativeProfile, writeCreativeProfile } from "@/lib/cloudkit/creative";
import { applyForPage } from "@/lib/creativeForm";
import { STYLE_COOKIE } from "@/lib/myStyle";
import {
  AUDITION_STATUSES,
  emptyDetails,
  isProfileStyle,
  type AuditionStatus,
  type CreativeDetails,
  type ProfileStyle,
} from "@/lib/profileStyle";

type Result = { ok: true } | { ok: false; message: string };

const YEAR = 60 * 60 * 24 * 365;

async function rememberStyle(style: ProfileStyle) {
  (await cookies()).set(STYLE_COOKIE, style, { httpOnly: true, sameSite: "lax", secure: process.env.NODE_ENV === "production", maxAge: YEAR, path: "/" });
}

function refresh(userRecordName: string) {
  updateTag(creativeTag(userRecordName));
  updateTag(CREATIVE_ALL_TAG);
}

/**
 * The required style choice at sign-up (and the first-time picker on Now). Saves to
 * the app account when the email is linked to one; always remembered on this browser.
 */
export async function chooseStyle(style: string): Promise<Result> {
  if (!isProfileStyle(style)) return { ok: false, message: "Pick Filmmaker, Actor or Musician." };
  const session = await currentSession();
  if (!session) return { ok: false, message: "Sign in first." };
  await rememberStyle(style);

  const current = await currentAccount();
  const user = session.userRecordName;
  if (user && current?.account) {
    const existing = await getCreativeProfile(user);
    const error = await writeCreativeProfile(user, style, existing?.details ?? emptyDetails());
    if (error) return { ok: false, message: error };
    refresh(user);
    if (existing?.style !== style) await applyForPage(style, current.account.profileID, current.account.name, session.email);
  }
  return { ok: true };
}

/** Logs an audition from Now ("Audition" on a role that fits). */
export async function recordAudition(input: { projectID: string; projectTitle: string; role: string }): Promise<Result> {
  const current = await currentAccount();
  const user = current?.session.userRecordName;
  if (!current?.account || !user) return { ok: false, message: "Link your Nexus account to track auditions." };
  const existing = await getCreativeProfile(user);
  if (!existing) return { ok: false, message: "Pick your profile style first." };
  if (existing.details.auditions.some((a) => a.projectID === input.projectID && a.role === input.role)) return { ok: true };
  const details: CreativeDetails = {
    ...existing.details,
    auditions: [
      { id: crypto.randomUUID(), projectID: input.projectID, projectTitle: input.projectTitle.slice(0, 120), role: input.role.slice(0, 200), date: Date.now(), status: "Submitted" as const },
      ...existing.details.auditions,
    ].slice(0, 200),
  };
  const error = await writeCreativeProfile(user, existing.style, details);
  if (error) return { ok: false, message: error };
  refresh(user);
  return { ok: true };
}

/** Changes an audition's status, or removes it (`status: null`). */
export async function updateAudition(id: string, status: AuditionStatus | null): Promise<Result> {
  const current = await currentAccount();
  const user = current?.session.userRecordName;
  if (!user) return { ok: false, message: "Sign in first." };
  const existing = await getCreativeProfile(user);
  if (!existing) return { ok: false, message: "Nothing to update." };
  if (status !== null && !AUDITION_STATUSES.includes(status)) return { ok: false, message: "Unknown status." };
  const auditions =
    status === null
      ? existing.details.auditions.filter((a) => a.id !== id)
      : existing.details.auditions.map((a) => (a.id === id ? { ...a, status } : a));
  const error = await writeCreativeProfile(user, existing.style, { ...existing.details, auditions });
  if (error) return { ok: false, message: error };
  refresh(user);
  return { ok: true };
}
