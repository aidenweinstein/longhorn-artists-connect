/**
 * The schools offered at sign-up and the email domains someone there must verify
 * with. Mirrors the app's `OnboardingSchool.all` (OnboardingSchools.swift); `id`
 * is the school's ID in verification-service (`seed/schools.sql`).
 */
export type SignupRole = "student" | "educator";

export type SignupSchool = {
  id: string;
  name: string;
  studentDomain: string;
  /** Domains an educator there can verify with; the first is the one shown as the example. */
  educatorDomains: string[];
  /** Placeholder for the part before "@". */
  idPlaceholder: string;
  /** Well-known names shown as the example in the name box. Empty: the box has no example. */
  exampleNames: string[];
  /** The school's main color: its button on the school list, and buttons once it's picked. */
  color: string;
  /** Text on `color`. */
  onColor: string;
  /** A school color that reads on black, for thin things: outlines, links, the progress bar. */
  highlight: string;
  /** How strong the school's glow is once picked (darker colors need more to show on black). */
  glow: number;
};

export const SIGNUP_SCHOOLS: SignupSchool[] = [
  // UT issues students EID@my.utexas.edu; faculty and staff use @austin.utexas.edu or @utexas.edu.
  {
    id: "ut-austin",
    name: "UT Austin",
    studentDomain: "my.utexas.edu",
    educatorDomains: ["austin.utexas.edu", "utexas.edu"],
    idPlaceholder: "eid",
    exampleNames: ["Matthew McConaughey", "Wes Anderson", "Owen Wilson"],
    color: "#bf5700", onColor: "#ffffff", highlight: "#e0711a", glow: 0.35,
  },
  { id: "berkeley", name: "UC Berkeley", studentDomain: "berkeley.edu", educatorDomains: ["berkeley.edu"], idPlaceholder: "calnetid", exampleNames: [],
    color: "#003262", onColor: "#FDB515", highlight: "#FDB515", glow: 0.85 },
  {
    id: "usc",
    name: "USC",
    studentDomain: "usc.edu",
    educatorDomains: ["usc.edu"],
    idPlaceholder: "username",
    exampleNames: ["Steven Spielberg", "George Lucas"],
    color: "#990000", onColor: "#FFCC00", highlight: "#FFCC00", glow: 0.5,
  },
  { id: "umich", name: "UMich", studentDomain: "umich.edu", educatorDomains: ["umich.edu"], idPlaceholder: "uniqname", exampleNames: [],
    color: "#00274C", onColor: "#FFCB05", highlight: "#FFCB05", glow: 0.9 },
  { id: "tamu", name: "Texas A&M", studentDomain: "tamu.edu", educatorDomains: ["tamu.edu"], idPlaceholder: "netid", exampleNames: [],
    color: "#500000", onColor: "#ffffff", highlight: "#ffffff", glow: 0.8 },
];

export const signupSchool = (id: string | undefined | null) => SIGNUP_SCHOOLS.find((s) => s.id === id);

export const isSignupRole = (value: unknown): value is SignupRole => value === "student" || value === "educator";

/**
 * The domains `role` can verify with at `school`. With no role (signing in, where the
 * person may be either), every domain of the school.
 */
export const emailDomains = (school: SignupSchool, role?: SignupRole) =>
  role === "educator"
    ? school.educatorDomains
    : role === "student"
      ? [school.studentDomain]
      : [...new Set([school.studentDomain, ...school.educatorDomains])];

/** "@a.edu" or "@a.edu or @b.edu", for messages. */
export const domainList = (school: SignupSchool, role?: SignupRole) =>
  emailDomains(school, role).map((d) => `@${d}`).join(" or ");

/** True when `email` is an address at exactly one of the school's domains for `role`. */
export function isSchoolEmail(email: string, school: SignupSchool, role?: SignupRole): boolean {
  const [local, domain, ...extra] = email.trim().toLowerCase().split("@");
  return !!local && !/\s/.test(local) && extra.length === 0 && emailDomains(school, role).includes(domain);
}

/** True when `email` is an address at exactly the school's student domain. */
export const isStudentEmail = (email: string, school: SignupSchool) => isSchoolEmail(email, school, "student");

/** One of the school's example names, or "" when it has none. Call from an event, not during render. */
export function exampleName(school: SignupSchool): string {
  return school.exampleNames[Math.floor(Math.random() * school.exampleNames.length)] ?? "";
}
