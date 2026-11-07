import { cleanWorkStatus } from "./workStatus";

/** The profile fields the website can edit, named exactly as the app's UserProfile record stores them. */
export type ProfileFields = {
  firstName: string;
  lastName: string;
  bio: string;
  /** The app's role tags, e.g. ["Director", "Editor"]. */
  roles: string[];
  isIndustryProfessional: boolean;
  major: string;
  minor: string;
  certificate: string;
  graduationYear: string;
  company: string;
  companyRole: string;
  industry: string;
  instagramHandle: string;
  websiteURL: string;
  /** "Looking for Work", "Busy", "Booked until YYYY-MM-DD", or "" for none (UserProfile.workStatus). */
  workStatus: string;
};

/** Every role tag the app offers (UserType in UserProfileModel.swift), in its order. */
export const ROLE_TAGS = [
  "Actor", "Director", "Producer", "Writer", "Editor", "Cinematographer", "Photographer", "Composer",
  "Sound Mixer", "Animator", "VFX Artist", "Graphic Designer", "Game Designer", "Painter", "Dancer",
  "Singer", "Musician", "Manager", "Agent", "Enthusiast",
] as const;

/** Cleans what the form sends: trims, caps lengths, keeps only known role tags. */
export function cleanProfile(raw: Partial<Record<keyof ProfileFields, unknown>>): ProfileFields {
  const t = (v: unknown, max: number) => String(v ?? "").trim().slice(0, max);
  const roles = Array.isArray(raw.roles) ? raw.roles : String(raw.roles ?? "").split(",");
  return {
    firstName: t(raw.firstName, 60),
    lastName: t(raw.lastName, 60),
    bio: String(raw.bio ?? "").replace(/\r\n/g, "\n").trim().slice(0, 1000),
    roles: ROLE_TAGS.filter((tag) => roles.some((r) => String(r).trim() === tag)),
    isIndustryProfessional: raw.isIndustryProfessional === true || raw.isIndustryProfessional === "true" || raw.isIndustryProfessional === "on",
    major: t(raw.major, 80),
    minor: t(raw.minor, 80),
    certificate: t(raw.certificate, 80),
    graduationYear: /^\d{4}$/.test(t(raw.graduationYear, 4)) ? t(raw.graduationYear, 4) : "",
    company: t(raw.company, 80),
    companyRole: t(raw.companyRole, 80),
    industry: t(raw.industry, 80),
    instagramHandle: t(raw.instagramHandle, 60).replace(/^@+/, "").replace(/^https?:\/\/(www\.)?instagram\.com\//i, "").replace(/\/.*$/, ""),
    websiteURL: t(raw.websiteURL, 300),
    workStatus: cleanWorkStatus(raw.workStatus),
  };
}
