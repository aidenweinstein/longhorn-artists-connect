// Every school on Nexus. `slug` is the school's ID at sign-up (lib/signupSchools.ts) and in
// a session (`schoolID`). `accent` is its secondary color, `mascot` what its students are
// called, and `logo` its mark as a square picture in public/schools/, shown in a circle.
// The logos are the schools' trademarks, used here without a license (Aiden's call, 2026-11-17);
// to drop one, swap its `logo` file for a plain colored circle.
export const SCHOOLS = [
  { slug: "ut-austin", name: "UT Austin", short: "UT", mascot: "Longhorns", color: "#bf5700", accent: "#ffffff", logo: "/schools/ut-austin.png" },
  { slug: "berkeley", name: "UC Berkeley", short: "Cal", mascot: "Bears", color: "#003262", accent: "#FDB515", logo: "/schools/berkeley.png" },
  { slug: "usc", name: "USC", short: "SC", mascot: "Trojans", color: "#990000", accent: "#FFCC00", logo: "/schools/usc.png" },
  { slug: "umich", name: "UMich", short: "M", mascot: "Wolverines", color: "#00274C", accent: "#FFCB05", logo: "/schools/umich.png" },
  { slug: "tamu", name: "Texas A&M", short: "A&M", mascot: "Aggies", color: "#500000", accent: "#ffffff", logo: "/schools/tamu.svg" },
] as const;

export type School = (typeof SCHOOLS)[number];

/** Every way a profile's `school` field names each school (the app and verification-service write the full name). */
const SCHOOL_NAMES: Record<string, string[]> = {
  "ut-austin": ["The University of Texas at Austin", "University of Texas at Austin", "UT Austin", "UT"],
  berkeley: ["University of California, Berkeley", "UC Berkeley", "Berkeley", "Cal"],
  usc: ["University of Southern California", "USC"],
  umich: ["University of Michigan", "UMich", "Michigan"],
  tamu: ["Texas A&M University", "Texas A&M"],
};

const normalized = (name: string) => name.toLowerCase().replace(/[^a-z0-9&]+/g, " ").trim();

/**
 * Which school a profile's `school` field means. Empty is UT Austin, as in the app: its
 * first accounts were all UT and never stored a school. A school not on the website is undefined.
 */
export function schoolSlugForName(name: string | undefined): string | undefined {
  const n = normalized(name ?? "");
  if (!n) return HOME_SCHOOL.slug;
  return Object.keys(SCHOOL_NAMES).find((slug) => SCHOOL_NAMES[slug].some((alias) => normalized(alias) === n));
}

/** The school the site is themed for: Home is its feed, and it's the badge shown to anyone not signed in. */
export const HOME_SCHOOL: School = SCHOOLS[0];

// Schools other than the home one, listed under "Other Schools" in the sidebar.
// Each one gets its own Home feed at /school/<slug>, tinted in its school colors.
export const OTHER_SCHOOLS: readonly School[] = SCHOOLS.filter((s) => s.slug !== HOME_SCHOOL.slug);

/** Any school by slug: every school, the home one included, has a feed at /school/<slug>. */
export function schoolForSlug(slug: string): School | undefined {
  return SCHOOLS.find((s) => s.slug === slug);
}

/** The school whose feed this path shows (/school/<slug>), if any. */
export function schoolForPath(pathname: string): School | undefined {
  const m = pathname.match(/^\/school\/([^/]+)/);
  return m ? schoolForSlug(m[1]) : undefined;
}

/** The school a signed-in visitor verified with (a session's `schoolID`), or the home school. */
export const schoolForID = (id: string | undefined | null): School => SCHOOLS.find((s) => s.slug === id) ?? HOME_SCHOOL;

/**
 * Colors for buttons that belong to someone at `slug` (Connect, Message on their
 * portfolio), as CSS variables, so they show that person's school whatever the
 * viewer's own school is. Uses a color that reads on the dark page: UT's orange,
 * and the other schools' bright accent (Berkeley gold, A&M white) with the school
 * color for text on it. Undefined when it's the viewer's own school.
 */
export function schoolButtonStyle(slug: string | undefined, viewerSlug: string | undefined): Record<string, string> | undefined {
  const school = slug ? schoolForSlug(slug) : undefined;
  if (!school || school.slug === (viewerSlug || HOME_SCHOOL.slug)) return undefined;
  return school.slug === HOME_SCHOOL.slug
    ? { "--brand": school.color, "--brand-foreground": "#ffffff" }
    : { "--brand": school.accent, "--brand-foreground": school.color };
}
