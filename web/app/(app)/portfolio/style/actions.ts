"use server";

import { cookies } from "next/headers";
import { updateTag } from "next/cache";
import { currentAccount, currentSession } from "@/lib/account";
import { uploadAsset, type CKField } from "@/lib/cloudkit/client";
import { CREATIVE_ALL_TAG, creativeTag, getCreativeProfile, writeCreativeProfile } from "@/lib/cloudkit/creative";
import { callPeople, featuresFor } from "@/lib/featured";
import { STYLE_COOKIE } from "@/lib/myStyle";
import {
  AUDITION_STATUSES,
  GENDERS,
  RESUME_CATEGORIES,
  STYLE_INFO,
  UNIONS,
  emptyDetails,
  isProfileStyle,
  type AuditionStatus,
  type CreativeDetails,
  type ProfileStyle,
} from "@/lib/profileStyle";

type Result = { ok: true } | { ok: false; message: string };

const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
const YEAR = 60 * 60 * 24 * 365;

async function rememberStyle(style: ProfileStyle) {
  (await cookies()).set(STYLE_COOKIE, style, { httpOnly: true, sameSite: "lax", secure: process.env.NODE_ENV === "production", maxAge: YEAR, path: "/" });
}

function refresh(userRecordName: string) {
  updateTag(creativeTag(userRecordName));
  updateTag(CREATIVE_ALL_TAG);
}

/**
 * Sends the profile to the moderators' queue for its style's public page, unless
 * they're already on it. Best effort: the queue lives in verification-service.
 */
async function applyForPage(style: ProfileStyle, profileID: string, name: string, email: string) {
  const slug = STYLE_INFO[style].slug;
  try {
    const featured = await featuresFor(slug);
    if (featured.some((f) => f.profileID === profileID)) return;
    await callPeople("apply", {
      category: slug,
      email,
      profileID: profileID || undefined,
      name,
      message: `Picked the ${style} profile style on Nexus.`,
      links: "",
    });
  } catch (error) {
    console.error("[style] apply:", error instanceof Error ? error.message : error);
  }
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

const text = (form: FormData, key: string, max = 200) => String(form.get(key) ?? "").replace(/\r\n/g, "\n").trim().slice(0, max);
const pick = (value: string, options: string[]) => (options.includes(value) ? value : "");
const age = (value: string) => {
  const v = Number.parseInt(value, 10);
  return Number.isFinite(v) && v > 0 && v < 100 ? v : undefined;
};

/** The full style editor (/portfolio/style). */
export async function saveStyle(form: FormData): Promise<Result> {
  const current = await currentAccount();
  const user = current?.session.userRecordName;
  if (!current?.account || !user) {
    return { ok: false, message: "Sign in with an email linked to your Nexus account to edit your profile." };
  }
  const style = text(form, "style");
  if (!isProfileStyle(style)) return { ok: false, message: "Pick Filmmaker, Actor or Musician." };

  const existing = await getCreativeProfile(user);
  const base = existing?.details ?? emptyDetails();

  let ageMin = age(text(form, "ageMin"));
  let ageMax = age(text(form, "ageMax"));
  if (ageMin !== undefined && ageMax !== undefined && ageMin > ageMax) [ageMin, ageMax] = [ageMax, ageMin];

  const projects = form.getAll("resumeProject").map(String);
  const resume = projects
    .map((project, i) => ({
      id: String(form.getAll("resumeID")[i] ?? "") || crypto.randomUUID(),
      category: pick(String(form.getAll("resumeCategory")[i] ?? ""), RESUME_CATEGORIES) || "Film",
      project: project.trim().slice(0, 120),
      role: String(form.getAll("resumeRole")[i] ?? "").trim().slice(0, 120),
      company: String(form.getAll("resumeCompany")[i] ?? "").trim().slice(0, 120),
      year: String(form.getAll("resumeYear")[i] ?? "").trim().slice(0, 4),
    }))
    .filter((c) => c.project)
    .slice(0, 60);

  const details: CreativeDetails = {
    ...base,
    actor: {
      ageMin,
      ageMax,
      gender: pick(text(form, "gender"), GENDERS),
      height: text(form, "height", 40),
      ethnicAppearance: text(form, "ethnicAppearance", 120),
      hair: text(form, "hair", 40),
      eyes: text(form, "eyes", 40),
      union: pick(text(form, "union"), UNIONS),
      basedIn: text(form, "basedIn", 80),
      languages: text(form, "languages", 300),
      specialSkills: text(form, "specialSkills", 600),
      training: text(form, "training", 600),
      reelPostID: text(form, "reelPostID", 80) || undefined,
      resume,
    },
    musician: {
      artistName: text(form, "artistName", 80),
      instruments: text(form, "instruments", 200),
      genres: text(form, "genres", 200),
      availableForGigs: form.get("availableForGigs") === "on",
      availableForSessions: form.get("availableForSessions") === "on",
      availableForScoring: form.get("availableForScoring") === "on",
    },
    filmmaker: {
      specialties: text(form, "specialties", 400),
      gear: text(form, "gear", 400),
      openToCrew: form.get("openToCrew") === "on",
    },
  };

  let headshot: CKField | undefined;
  const photo = form.get("headshot");
  if (photo instanceof File && photo.size > 0) {
    if (photo.size > MAX_PHOTO_BYTES) return { ok: false, message: "That headshot is too large. Try one under 5 MB." };
    if (!/^image\/(jpeg|png)$/.test(photo.type)) return { ok: false, message: "Use a JPEG or PNG headshot." };
    try {
      headshot = await uploadAsset("CreativeProfile", `CreativeProfile_${user}`, "headshot", new Uint8Array(await photo.arrayBuffer()), photo.type);
    } catch (error) {
      console.error("[style] headshot:", error instanceof Error ? error.message : error);
      return { ok: false, message: "Couldn't upload your headshot. Try again." };
    }
  }

  const error = await writeCreativeProfile(user, style, details, headshot);
  if (error) return { ok: false, message: error };
  await rememberStyle(style);
  refresh(user);
  if (existing?.style !== style) await applyForPage(style, current.account.profileID, current.account.name, current.session.email);
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
