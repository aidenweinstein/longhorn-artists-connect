import { callPeople, featuresFor } from "./featured";
import {
  GENDERS,
  RESUME_CATEGORIES,
  STYLE_INFO,
  STREAMING_SERVICES,
  UNIONS,
  type CreativeDetails,
  type ProfileStyle,
} from "./profileStyle";

/*
 * Reads the Actor Info, Filmmaker Info and Musician Info sections of Edit profile
 * into the CreativeProfile `details` JSON (same keys as the app). Auditions and
 * anything else the form doesn't send are kept from `base`.
 */

const text = (form: FormData, key: string, max = 200) => String(form.get(key) ?? "").replace(/\r\n/g, "\n").trim().slice(0, max);
const pick = (value: string, options: string[]) => (options.includes(value) ? value : "");
const age = (value: string) => {
  const v = Number.parseInt(value, 10);
  return Number.isFinite(v) && v > 0 && v < 100 ? v : undefined;
};

export function detailsFromForm(form: FormData, base: CreativeDetails): CreativeDetails {
  let ageMin = age(text(form, "ageMin"));
  let ageMax = age(text(form, "ageMax"));
  if (ageMin !== undefined && ageMax !== undefined && ageMin > ageMax) [ageMin, ageMax] = [ageMax, ageMin];

  const all = (key: string) => form.getAll(key).map(String);
  const ids = all("resumeID");
  const cats = all("resumeCategory");
  const roles = all("resumeRole");
  const companies = all("resumeCompany");
  const years = all("resumeYear");
  const resume = all("resumeProject")
    .map((project, i) => ({
      id: (ids[i] ?? "").slice(0, 80) || crypto.randomUUID(),
      category: pick(cats[i] ?? "", RESUME_CATEGORIES) || "Film",
      project: project.trim().slice(0, 120),
      role: (roles[i] ?? "").trim().slice(0, 120),
      company: (companies[i] ?? "").trim().slice(0, 120),
      year: (years[i] ?? "").replace(/\D/g, "").slice(0, 4),
    }))
    .filter((c) => c.project)
    .slice(0, 60);

  return {
    ...base,
    actor: {
      ageMin,
      ageMax,
      gender: pick(text(form, "gender"), GENDERS),
      height: text(form, "height", 40),
      ethnicAppearance: text(form, "ethnicAppearance", 120),
      hair: text(form, "hair", 40),
      eyes: text(form, "eyes", 40),
      // A union saved before the list changed (e.g. "SAG-AFTRA") is kept until they pick another.
      union: text(form, "union") === base.actor.union ? base.actor.union : pick(text(form, "union"), UNIONS),
      // No longer edited; kept as saved.
      basedIn: base.actor.basedIn,
      languages: text(form, "languages", 300),
      specialSkills: text(form, "specialSkills", 600),
      training: text(form, "training", 600),
      reelPostID: text(form, "reelPostID", 80) || undefined,
      resume,
    },
    musician: {
      soloName: text(form, "soloName", 80),
      bandName: text(form, "bandName", 80),
      instruments: text(form, "instruments", 400),
      genres: text(form, "genres", 400),
      streamingLinks: Object.fromEntries(
        STREAMING_SERVICES.map(({ name }) => [name, text(form, `stream:${name}`, 300)] as const).filter(([, v]) => v),
      ),
    },
    filmmaker: {
      studios: text(form, "studios", 400),
      certifications: text(form, "certifications", 400),
      gear: text(form, "gear", 400),
    },
  };
}

/**
 * Sends the profile to the moderators' queue for its type's public page, unless
 * they're already on it. Best effort: the queue lives in verification-service.
 */
export async function applyForPage(style: ProfileStyle, profileID: string, name: string, email: string) {
  const slug = STYLE_INFO[style].slug;
  try {
    const featured = await featuresFor(slug);
    if (featured.some((f) => f.profileID === profileID)) return;
    await callPeople("apply", {
      category: slug,
      email,
      profileID: profileID || undefined,
      name,
      message: `Picked the ${style} profile on Nexus.`,
      links: "",
    });
  } catch (error) {
    console.error("[style] apply:", error instanceof Error ? error.message : error);
  }
}
