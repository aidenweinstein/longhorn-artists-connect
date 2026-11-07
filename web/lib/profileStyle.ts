import type { Post } from "./mockContent";
import type { Credit } from "./postDetails";
import type { PeopleSlug } from "./featured";

/*
 * Profile styles: every artist picks a base style — Filmmaker, Actor or Musician.
 * It decides what Now shows, what Home leads with, and how their portfolio looks
 * (Actors Access, IMDb or Spotify). Mirrors the app's ProfileStyle.swift; both
 * read and write the same CloudKit `CreativeProfile` record, whose `details` field
 * is the JSON of `CreativeDetails` below (same keys as the Swift Codable types).
 */

export const PROFILE_STYLES = ["Filmmaker", "Actor", "Musician"] as const;
export type ProfileStyle = (typeof PROFILE_STYLES)[number];

export const isProfileStyle = (v: unknown): v is ProfileStyle => PROFILE_STYLES.includes(v as ProfileStyle);

export const STYLE_INFO: Record<ProfileStyle, { plural: string; slug: PeopleSlug; pitch: string; looksLike: string }> = {
  Filmmaker: {
    plural: "Filmmakers",
    slug: "filmmakers",
    pitch: "IMDb-style credits and stills. See the sets you're on and the crews you could join.",
    looksLike: "Like IMDb",
  },
  Actor: {
    plural: "Actors",
    slug: "actors",
    pitch: "Headshot, reel and resume. Track your auditions and find roles that fit you.",
    looksLike: "Like Actors Access",
  },
  Musician: {
    plural: "Musicians",
    slug: "musicians",
    pitch: "A discography of your releases. Find scoring work, gigs, open mics and jams.",
    looksLike: "Like Spotify",
  },
};

export const styleForSlug = (slug: string): ProfileStyle | undefined =>
  PROFILE_STYLES.find((s) => STYLE_INFO[s].slug === slug);

/** A starting suggestion from someone's role tags. */
export function suggestedStyle(tags: string[]): ProfileStyle | undefined {
  const t = new Set(tags.map((x) => x.toLowerCase()));
  if (t.has("actor") || t.has("dancer")) return "Actor";
  if (t.has("musician") || t.has("singer") || t.has("composer")) return "Musician";
  const film = ["director", "producer", "writer", "editor", "cinematographer", "sound mixer", "animator", "vfx artist"];
  if (film.some((f) => t.has(f))) return "Filmmaker";
  return undefined;
}

// MARK: - Details (same JSON as the app)

export type ResumeCredit = { id: string; category: string; project: string; role: string; company: string; year: string };
export const RESUME_CATEGORIES = ["Film", "Television", "Theatre", "Commercial", "New Media", "Other"];

export type ActorDetails = {
  ageMin?: number;
  ageMax?: number;
  gender: string;
  height: string;
  ethnicAppearance: string;
  hair: string;
  eyes: string;
  union: string;
  basedIn: string;
  languages: string;
  specialSkills: string;
  training: string;
  /** Post ID of the Performance or Film used as their reel. */
  reelPostID?: string;
  resume: ResumeCredit[];
};
export const GENDERS = ["Female", "Male", "Non-binary"];
export const UNIONS = ["Non-union", "SAG-AFTRA Eligible", "SAG-AFTRA", "AEA"];

export type MusicianDetails = {
  artistName: string;
  instruments: string;
  genres: string;
  availableForSessions: boolean;
  availableForGigs: boolean;
  availableForScoring: boolean;
};

export type FilmmakerDetails = { specialties: string; gear: string; openToCrew: boolean };

export type AuditionStatus = "Submitted" | "Callback" | "Booked" | "Not selected";
export const AUDITION_STATUSES: AuditionStatus[] = ["Submitted", "Callback", "Booked", "Not selected"];
/** A role the actor auditioned for. Kept with the profile so it follows them between devices. */
export type Audition = { id: string; projectID: string; projectTitle: string; role: string; date: number; status: AuditionStatus };

export type CreativeDetails = {
  actor: ActorDetails;
  musician: MusicianDetails;
  filmmaker: FilmmakerDetails;
  auditions: Audition[];
};

export type CreativeProfile = {
  /** Raw iCloud user record name (no UserProfile_ prefix). */
  userID: string;
  style: ProfileStyle;
  details: CreativeDetails;
  headshotUrl?: string;
  updatedAt: number;
};

const s = (v: unknown) => (typeof v === "string" ? v : "");
const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : undefined);
const b = (v: unknown, fallback: boolean) => (typeof v === "boolean" ? v : fallback);
const obj = (v: unknown): Record<string, unknown> => (v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {});

export function emptyDetails(): CreativeDetails {
  return parseDetails("");
}

/** Reads the `details` JSON, tolerating anything missing (older saves, either platform). */
export function parseDetails(raw: string): CreativeDetails {
  let j: Record<string, unknown> = {};
  try {
    j = obj(raw ? JSON.parse(raw) : {});
  } catch {
    /* keep empty */
  }
  const a = obj(j.actor);
  const m = obj(j.musician);
  const f = obj(j.filmmaker);
  return {
    actor: {
      ageMin: n(a.ageMin),
      ageMax: n(a.ageMax),
      gender: s(a.gender),
      height: s(a.height),
      ethnicAppearance: s(a.ethnicAppearance),
      hair: s(a.hair),
      eyes: s(a.eyes),
      union: s(a.union),
      basedIn: s(a.basedIn),
      languages: s(a.languages),
      specialSkills: s(a.specialSkills),
      training: s(a.training),
      reelPostID: s(a.reelPostID) || undefined,
      resume: (Array.isArray(a.resume) ? a.resume : []).map((x) => {
        const c = obj(x);
        return {
          id: s(c.id) || crypto.randomUUID(),
          category: s(c.category) || "Film",
          project: s(c.project),
          role: s(c.role),
          company: s(c.company),
          year: s(c.year),
        };
      }),
    },
    musician: {
      artistName: s(m.artistName),
      instruments: s(m.instruments),
      genres: s(m.genres),
      availableForSessions: b(m.availableForSessions, false),
      availableForGigs: b(m.availableForGigs, true),
      availableForScoring: b(m.availableForScoring, false),
    },
    filmmaker: { specialties: s(f.specialties), gear: s(f.gear), openToCrew: b(f.openToCrew, true) },
    auditions: (Array.isArray(j.auditions) ? j.auditions : []).flatMap((x) => {
      const c = obj(x);
      const status = AUDITION_STATUSES.includes(c.status as AuditionStatus) ? (c.status as AuditionStatus) : "Submitted";
      return s(c.projectID)
        ? [{ id: s(c.id) || crypto.randomUUID(), projectID: s(c.projectID), projectTitle: s(c.projectTitle), role: s(c.role), date: n(c.date) ?? Date.now(), status }]
        : [];
    }),
  };
}

export function ageRangeText(a: ActorDetails): string {
  if (a.ageMin !== undefined && a.ageMax !== undefined) return a.ageMin === a.ageMax ? `${a.ageMin}` : `${a.ageMin}–${a.ageMax}`;
  if (a.ageMin !== undefined) return `${a.ageMin}+`;
  if (a.ageMax !== undefined) return `Up to ${a.ageMax}`;
  return "";
}

/** The rows beside an actor's headshot, skipping blanks. */
export function actorStats(a: ActorDetails): { label: string; value: string }[] {
  return [
    { label: "Age range", value: ageRangeText(a) },
    { label: "Gender", value: a.gender },
    { label: "Height", value: a.height },
    { label: "Ethnic appearance", value: a.ethnicAppearance },
    { label: "Hair", value: a.hair },
    { label: "Eyes", value: a.eyes },
    { label: "Union", value: a.union },
    { label: "Based in", value: a.basedIn },
  ].filter((r) => r.value.trim());
}

export function musicianAvailability(m: MusicianDetails): string[] {
  return [m.availableForGigs && "Live gigs", m.availableForSessions && "Session work", m.availableForScoring && "Scoring"].filter(
    (x): x is string => !!x,
  );
}

// MARK: - Recommendations

/** Whether a feed post is the kind of work this style is about. */
export function prefers(style: ProfileStyle, post: Post): boolean {
  switch (style) {
    case "Filmmaker":
      return post.category === "film";
    case "Actor":
      return post.category === "performance" || post.category === "film";
    case "Musician":
      return post.category === "music";
  }
}

/** Leads a feed with the style's kind of work: three of those, then one other, repeating. Nothing is dropped. */
export function recommend(style: ProfileStyle, posts: Post[]): Post[] {
  const preferred = posts.filter((p) => prefers(style, p));
  const other = posts.filter((p) => !prefers(style, p));
  const out: Post[] = [];
  let i = 0;
  let j = 0;
  while (i < preferred.length || j < other.length) {
    for (let k = 0; k < 3 && i < preferred.length; k++) out.push(preferred[i++]);
    if (j < other.length) out.push(other[j++]);
  }
  return out;
}

// MARK: - Cast role matching

/**
 * What a casting line asks for, read from the poster's free-form wording —
 * "Rosa (F, 18–25, Latina, Spanish-speaking)" or "Danny — male, early 20s, plays guitar".
 * Same rules as CastRoleRequirements in the app.
 */
export type RoleRequirements = {
  gender?: string;
  ageMin?: number;
  ageMax?: number;
  ethnicityGroups: string[][];
  skills: string[];
};

const ETHNICITIES: string[][] = [
  ["latina", "latino", "latinx", "latine", "hispanic"],
  ["black", "african american"],
  ["asian", "east asian", "south asian", "southeast asian"],
  ["white", "caucasian"],
  ["middle eastern", "arab"],
  ["indigenous", "native american"],
  ["pacific islander"],
  ["biracial", "multiracial"],
];

const SKILLS: { label: string; pattern: RegExp; stems: string[] }[] = [
  { label: "Singing", pattern: /\b(sing|sings|singing|singer|vocals?)\b/, stems: ["sing", "vocal"] },
  { label: "Dance", pattern: /\b(dance|dances|dancer|dancing)\b/, stems: ["danc", "ballet", "tap", "hip hop", "hip-hop"] },
  { label: "Guitar", pattern: /\bguitar/, stems: ["guitar"] },
  { label: "Piano", pattern: /\b(piano|keys|keyboard)\b/, stems: ["piano", "keys", "keyboard"] },
  { label: "Drums", pattern: /\bdrum/, stems: ["drum"] },
  { label: "Violin", pattern: /\bviolin/, stems: ["violin"] },
  { label: "Spanish", pattern: /\bspanish/, stems: ["spanish"] },
  { label: "French", pattern: /\bfrench\b/, stems: ["french"] },
  { label: "Mandarin", pattern: /\bmandarin/, stems: ["mandarin", "chinese"] },
  { label: "Cantonese", pattern: /\bcantonese/, stems: ["cantonese"] },
  { label: "Japanese", pattern: /\bjapanese/, stems: ["japanese"] },
  { label: "Korean", pattern: /\bkorean/, stems: ["korean"] },
  { label: "German", pattern: /\bgerman\b/, stems: ["german"] },
  { label: "Italian", pattern: /\bitalian/, stems: ["italian"] },
  { label: "Portuguese", pattern: /\bportuguese/, stems: ["portuguese"] },
  { label: "Arabic", pattern: /\barabic/, stems: ["arabic"] },
  { label: "Hindi", pattern: /\bhindi/, stems: ["hindi"] },
  { label: "ASL", pattern: /\b(asl|sign language)\b/, stems: ["asl", "sign language"] },
  { label: "Stunts", pattern: /\bstunts?\b/, stems: ["stunt"] },
  { label: "Stage combat", pattern: /\b(stage combat|fight choreography|combat)\b/, stems: ["combat", "fight"] },
  { label: "Martial arts", pattern: /\b(martial arts?|karate|kung fu|taekwondo|jiu[- ]?jitsu)\b/, stems: ["martial", "karate", "kung fu", "taekwondo", "jitsu"] },
  { label: "Skateboarding", pattern: /\bskat(e|ing|eboard)/, stems: ["skate"] },
  { label: "Horseback riding", pattern: /\b(horse|horseback|equestrian)/, stems: ["horse", "equestrian"] },
  { label: "Improv", pattern: /\bimprov/, stems: ["improv"] },
  { label: "Juggling", pattern: /\bjuggl/, stems: ["juggl"] },
  { label: "Swimming", pattern: /\bswim/, stems: ["swim"] },
];

function ages(text: string): [number | undefined, number | undefined] {
  let m = text.match(/\b(\d{1,2})\s*(?:-|–|—|to)\s*(\d{1,2})\b/);
  if (m) {
    const lo = Number(m[1]);
    const hi = Number(m[2]);
    if (lo >= 5 && hi <= 99 && lo <= hi) return [lo, hi];
  }
  m = text.match(/\b(early|mid|late)?[\s-]*(\d)0'?s\b/);
  if (m) {
    const base = Number(m[2]) * 10;
    if (m[1] === "early") return [base, base + 4];
    if (m[1] === "mid") return [base + 3, base + 7];
    if (m[1] === "late") return [base + 6, base + 9];
    return [base, base + 9];
  }
  m = text.match(/\b(\d{2})\s*\+/);
  if (m) return [Number(m[1]), undefined];
  m = text.match(/\b(\d{2})\s*(?:yo|y\/o|years? old)\b/) ?? text.match(/\bage\s*(\d{2})\b/);
  if (m) return [Number(m[1]) - 2, Number(m[1]) + 2];
  if (/\bteens?\b|\bteenager/.test(text)) return [13, 19];
  return [undefined, undefined];
}

export function parseRole(wording: string): RoleRequirements {
  const text = ` ${wording.toLowerCase()} `;
  let gender: string | undefined;
  if (/\b(non[- ]?binary|enby)\b/.test(text)) gender = "Non-binary";
  else if (/\b(female|woman|women|girl|actress|she\/her)\b/.test(text) || /[\s(,/]f[\s),/]/.test(text)) gender = "Female";
  else if (/\b(male|man|men|boy|he\/him)\b/.test(text) || /[\s(,/]m[\s),/]/.test(text)) gender = "Male";
  const [ageMin, ageMax] = ages(text);
  return {
    gender,
    ageMin,
    ageMax,
    ethnicityGroups: ETHNICITIES.filter((g) => g.some((e) => new RegExp(`\\b${e}\\b`).test(text))),
    skills: SKILLS.filter((k) => k.pattern.test(text)).map((k) => k.label),
  };
}

export function roleChips(r: RoleRequirements): string[] {
  const chips: string[] = [];
  if (r.gender) chips.push(r.gender);
  if (r.ageMin !== undefined && r.ageMax !== undefined) chips.push(`${r.ageMin}–${r.ageMax}`);
  else if (r.ageMin !== undefined) chips.push(`${r.ageMin}+`);
  chips.push(...r.ethnicityGroups.map((g) => g[0][0].toUpperCase() + g[0].slice(1)));
  chips.push(...r.skills);
  return chips;
}

/**
 * Whether an actor could play this. Details the actor left blank don't rule them out,
 * except skills: a role that needs guitar only matches someone who listed it.
 */
export function fitsRole(r: RoleRequirements, a: ActorDetails): boolean {
  if (r.gender && a.gender && a.gender.toLowerCase() !== r.gender.toLowerCase()) return false;
  if ((r.ageMin !== undefined || r.ageMax !== undefined) && (a.ageMin !== undefined || a.ageMax !== undefined)) {
    const lo = a.ageMin ?? a.ageMax ?? 0;
    const hi = a.ageMax ?? a.ageMin ?? 200;
    if (hi < (r.ageMin ?? 0) || lo > (r.ageMax ?? 200)) return false;
  }
  const look = a.ethnicAppearance.toLowerCase();
  if (r.ethnicityGroups.length && look && !r.ethnicityGroups.some((g) => g.some((e) => look.includes(e)))) return false;
  if (r.skills.length) {
    const have = `${a.specialSkills} ${a.languages}`.toLowerCase();
    for (const label of r.skills) {
      const skill = SKILLS.find((k) => k.label === label);
      if (skill && !skill.stems.some((st) => have.includes(st))) return false;
    }
  }
  return true;
}

// MARK: - Crew and music openings

/** Which tags each kind of crew wording is for, so "DP" reaches Cinematographers and "Art Director" doesn't ping Directors. */
const CREW_WORDS: { pattern: RegExp; tags: string[] }[] = [
  { pattern: /\b(art director|production designer|set dresser|props)\b/, tags: ["Painter", "Graphic Designer"] },
  { pattern: /\b(director of photography|dp|cinematographer|camera|1st ac|2nd ac|\bac\b|gaffer|grip|operator)\b/, tags: ["Cinematographer"] },
  { pattern: /\b(assistant director|1st ad|2nd ad|\bad\b)\b/, tags: ["Director", "Producer"] },
  { pattern: /\bdirector\b/, tags: ["Director"] },
  { pattern: /\b(producer|line producer|production assistant|\bpa\b|production manager)\b/, tags: ["Producer"] },
  { pattern: /\b(writer|screenwriter|script)\b/, tags: ["Writer"] },
  { pattern: /\b(editor|editing|colorist|color grad)/, tags: ["Editor"] },
  { pattern: /\b(sound|boom|mixer|audio)\b/, tags: ["Sound Mixer"] },
  { pattern: /\b(compos|score|scoring|music)/, tags: ["Composer", "Musician"] },
  { pattern: /\b(vfx|visual effects|compositor)\b/, tags: ["VFX Artist"] },
  { pattern: /\b(animat|storyboard)/, tags: ["Animator"] },
  { pattern: /\b(still photographer|photographer|bts)\b/, tags: ["Photographer"] },
  { pattern: /\b(graphic|title design|poster)\b/, tags: ["Graphic Designer"] },
];

/** Crew openings someone with these tags would be called for. No tags means every opening. */
export function crewFor(crewNeeded: string[], tags: string[]): string[] {
  const roles = crewNeeded.map((c) => c.trim()).filter(Boolean);
  if (tags.length === 0) return roles;
  const mine = new Set(tags.map((t) => t.toLowerCase()));
  return roles.filter((role) => {
    const text = role.toLowerCase();
    const rule = CREW_WORDS.find((w) => w.pattern.test(text));
    if (rule) return rule.tags.some((t) => mine.has(t.toLowerCase()));
    return [...mine].some((t) => text.includes(t));
  });
}

export const isMusicRole = (wording: string) =>
  /compos|\bscor(e|ing)\b|\bmusic|songwrit|sound design|\bsinger|\bband\b|\bvocalist/.test(wording.toLowerCase());

export const GIG_PATTERN =
  /open mic|\bjam\b|jam session|\bgigs?\b|\bband\b|busk|karaoke|battle of the bands|musicians? wanted|songwriter|live music|recital/;

// MARK: - Credits

const same = (a: string, b: string) => !!a.trim() && a.trim().toLowerCase() === b.trim().toLowerCase();

/** This person's credits on a post: by linked profile when the credit has one, else by name. */
export function creditsFor(post: Post, person: { name: string; profileID: string }): { group: string; credit: Credit }[] {
  const out: { group: string; credit: Credit }[] = [];
  for (const g of post.details?.creditGroups ?? []) {
    for (const c of g.credits) {
      const match = c.profileID && person.profileID ? c.profileID === person.profileID : same(c.name, person.name);
      if (match) out.push({ group: g.title, credit: c });
    }
  }
  return out;
}

export const matchesPerson = (name: string, profileID: string | undefined, person: { name: string; profileID: string }) =>
  profileID && person.profileID ? profileID === person.profileID : same(name, person.name);
