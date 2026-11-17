// Student organizations, carried over from the app (OrganizationCard.swift and
// CollectiveStudios.swift): the same list and order, descriptions, page colors,
// sections and hardcoded catalogs. CloudKit can override a description or picture
// (see lib/cloudkit/organizations.ts); everything else lives here, as it does in the app.

export type OrgSection =
  | "weeklyShortSeasons"
  | "shortFilms"
  | "magazines"
  | "pilots"
  | "photography"
  | "graphicDesign"
  | "music"
  | "events";

export const SECTION_TITLES: Record<OrgSection, string> = {
  weeklyShortSeasons: "Weekly Shorts",
  shortFilms: "Short Films",
  magazines: "Magazines",
  pilots: "Pilots",
  photography: "Photography",
  graphicDesign: "Graphic Design",
  music: "Music",
  events: "Events",
};

export type Organization = {
  /** Stable slug, the same key the app uses ("collective", "dka"...). */
  slug: string;
  name: string;
  description: string;
  /** Page colors: background, and text/icons on top of it. */
  background: string;
  text: string;
  imageUrl: string;
  sections: OrgSection[];
};

const org = (
  slug: string,
  name: string,
  description: string,
  background: string,
  text: string,
  sections: OrgSection[] = [],
): Organization => ({ slug, name, description, background, text, imageUrl: `/orgs/${slug}.jpg`, sections });

/** In the app's display order. */
export const ORGANIZATIONS: Organization[] = [
  org("longhorn-artists-connect", "Longhorn Artists Connect", "Fostering collaboration between creatives at UT Austin.", "#bf5700", "#ffffff"),
  org("collective", "Collective", "A creative studio.", "#2a2ae3", "#ffffff", ["weeklyShortSeasons", "shortFilms", "magazines"]),
  org("incubator", "Incubator", "A select group of students creating five original pilots.", "#545fc5", "#f3fe61", ["pilots"]),
  org("texas-supports-live-music", "Texas Supports Live Music", "Bringing students together through live music and support for local artists.", "#101010", "#ecebeb"),
  org("dka", "DKA", "Delta Kappa Alpha — national professional cinematic society.", "#0a2365", "#f4cb49", ["shortFilms"]),
  org("the-new-project", "The New Project", "Multimedia creative collective/agency — redefining creative spaces at UT Austin.", "#9d342b", "#ffffff", ["shortFilms", "photography", "graphicDesign", "music"]),
  org("black-lens", "Black Lens", "What we create changes the world.", "#000000", "#ffffff"),
  org("paradise-music-group", "Paradise Music Group", "Welcome to Paradise ATX.", "#67ae4d", "#dbb756"),
  org("longhorn-late-night", "Longhorn Late Night", "UT Austin’s Best and Only Sketch Comedy Variety Show", "#42558c", "#ffffff"),
  org("utalent-records", "UTalent Records", "the only student-run record label at the university of texas at austin!", "#eaeaec", "#bf5700"),
  org("texas-entertainment-association", "Texas Entertainment Association", "A preprofessional org for students interested in the business side of entertainment.", "#000000", "#ffffff"),
  org("spark-magazine", "Spark Magazine", "It takes a SPARK. ✧", "#ffffff", "#000000"),
  org("longhorn-music-business-club", "Longhorn Music Business Club", "Home to the next generation of industry leaders, learning from the live music capital of the world", "#f1e8d7", "#251f16"),
  org("next-week-now", "Next Week Now", "When you know what comes next, everything feels like a joke! | Live every Thursday at 11 P.M.", "#af52de", "#000000", ["events"]),
];

export function findOrganization(slug: string) {
  return ORGANIZATIONS.find((o) => o.slug === slug);
}

/** Hardcoded projects under an org's section, each matched to a real post by title. */
const CATALOG: Record<string, string[]> = {
  "collective/shortFilms": ["Pandorox", "Coyote", "Delinquents"],
  "collective/magazines": ["collective magazine vol. 1", "collective magazine vol. 2", "collective magazine vol. 3"],
  "incubator/pilots": ["Wine to Water", "Student Film", "The Queen", "This Call May Be Recorded", "Pulse"],
};

export function catalogTitles(slug: string, section: OrgSection): string[] {
  return CATALOG[`${slug}/${section}`] ?? [];
}

/** Collective's Weekly Shorts by season, in episode order. Titles match the real posts. */
export const COLLECTIVE_SEASONS: { season: number; titles: string[] }[] = [
  {
    season: 1,
    titles: [
      "The Creative Life", "Collective on Wheels", "Out of My Mind", "Just Getting Started", "Slow Down",
      "Seeing Double", "Out the Basement", "Fake Faith", "The Special", "Cowboy",
    ],
  },
  {
    season: 2,
    titles: [
      "excursion", "free lemonade?", "summer’s overrated anyways", "game over", "gonna give you the slip",
      "in your own way, on your own time", "crashout", "hell of a life", "passing notes", "psycho",
      "tote bag + matcha?", "live. fit. go. celsius.", "pov you’re a lighter", "hive.", "dorm drop",
      "the rubber penalty", "best take", "running out of time",
    ],
  },
  {
    season: 3,
    titles: [
      "NEXT BIG THING.", "NEW YEAR.", "STRUCK BY LOVE.", "PERFECT by Marc Jacobs.", "BLEED OUT.", "MATCH POINT",
      "LOOF & GLOOM.", "HITCH.", "KNOCKOUT.", "UP IN THE SKY.", "HEAT RISES.", "AQUAMARINE.",
    ],
  },
];

/** The app's title matching: case, curly quotes, trailing periods and extra spaces don't count. */
export function normalizeTitle(raw: string) {
  return raw
    .toLowerCase()
    .replace(/[‘’]/g, "'")
    .trim()
    .replace(/[. ]+$/, "")
    .split(/\s+/)
    .join(" ");
}
