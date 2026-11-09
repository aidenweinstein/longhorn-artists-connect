import type { SampleProfile } from "./sampleProfiles";

/*
 * SAMPLE CASTING CALL — the upcoming film the Actors page filters for.
 *
 * Until filmmakers can post their own roles, the Actors page opens filtered to
 * the first role below. Edit the project or roles freely. Every rule is optional:
 *   gender            — "Female", "Male", "Non-binary"… (matches the actor's Gender row)
 *   ageMin / ageMax   — the actor's Age, or their Age range, must overlap this
 *   ethnicAppearance  — any of these words in the actor's Ethnic appearance row
 *   skills            — every one must appear in their Special skills or Languages
 */
export type CastingRole = {
  slug: string;
  name: string;
  description: string;
  gender?: string;
  ageMin?: number;
  ageMax?: number;
  ethnicAppearance?: string[];
  skills?: string[];
};

export type CastingCall = { project: string; filmmaker: string; logline: string; roles: CastingRole[] };

export const SAMPLE_CASTING_CALL: CastingCall | null = {
  project: "Paper Saints",
  filmmaker: "Maya Castillo",
  logline: "Two sisters run their late mother's botánica on the West Side while their brother plots to sell it.",
  roles: [
    {
      slug: "rosa",
      name: "Rosa",
      description: "The younger sister. Stubborn, funny, bilingual. Lead.",
      gender: "Female",
      ageMin: 18,
      ageMax: 25,
      ethnicAppearance: ["Latina", "Latino", "Hispanic"],
      skills: ["Spanish"],
    },
    {
      slug: "teresa",
      name: "Teresa",
      description: "The older sister holding the shop together. Lead.",
      gender: "Female",
      ageMin: 20,
      ageMax: 30,
    },
    {
      slug: "danny",
      name: "Danny",
      description: "Their brother, a charming would-be musician. Plays guitar on screen. Supporting.",
      gender: "Male",
      ageMin: 18,
      ageMax: 24,
      skills: ["Guitar"],
    },
  ],
};

const detail = (p: SampleProfile, label: string) =>
  p.details?.find((d) => d.label.toLowerCase() === label.toLowerCase())?.value ?? "";

/** [low, high] from the Age row, widened by the Age range row ("18–26"). */
function ages(p: SampleProfile): [number, number] | null {
  const nums = [detail(p, "Age"), detail(p, "Age range")].flatMap((v) => v.match(/\d+/g) ?? []).map(Number);
  return nums.length ? [Math.min(...nums), Math.max(...nums)] : null;
}

/** Does this actor fit the role? Actors missing a detail a role asks for don't match. */
export function fitsRole(p: SampleProfile, role: CastingRole): boolean {
  if (role.gender && detail(p, "Gender").toLowerCase() !== role.gender.toLowerCase()) return false;
  if (role.ageMin !== undefined || role.ageMax !== undefined) {
    const range = ages(p);
    if (!range) return false;
    if (range[1] < (role.ageMin ?? 0) || range[0] > (role.ageMax ?? 200)) return false;
  }
  if (role.ethnicAppearance?.length) {
    const look = detail(p, "Ethnic appearance").toLowerCase();
    if (!role.ethnicAppearance.some((e) => look.includes(e.toLowerCase()))) return false;
  }
  if (role.skills?.length) {
    const have = [...(p.skills ?? []), detail(p, "Languages")].join(" | ").toLowerCase();
    if (!role.skills.every((s) => have.includes(s.toLowerCase()))) return false;
  }
  return true;
}
