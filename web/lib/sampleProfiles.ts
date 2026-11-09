import type { Account } from "./cloudkit/content";
import type { PeopleSlug } from "./featured";
import { emptyDetails, type CreativeProfile, type ResumeCredit } from "./profileStyle";

/*
 * SAMPLE PROFILES — edit these freely.
 *
 * They appear at the top of each People page (Filmmakers, Actors, Musicians),
 * above the people you feature from Manage. Change any text below, save, and the
 * page updates. To hide every sample at once, set SHOW_SAMPLE_PROFILES to false.
 *
 * Fields:
 *   name         — shown as the heading
 *   headshot     — profile photo: a URL, or a file in web/public such as
 *                  "/headshots/priya.jpg". Leave it out to show initials.
 *                  Shown at its full shape, uncropped.
 *   major        — e.g. "Radio-Television-Film" (its own row)
 *   classOf      — graduation year, e.g. "2027" → shows "Class of 2027"
 *   school       — only shown when it isn't the viewer's own school
 *   union        — union status, shown under the role tags, e.g.
 *                  "SAG-AFTRA", "SAG-AFTRA Eligible", "Non-union"
 *   roles        — tag pills under the name
 *   blurb        — your write-up (line breaks are kept)
 *   details      — ACTORS ONLY. Facts shown as a list, e.g. Gender,
 *                  Ethnic appearance, Height, Age, Age range, Languages. Add, remove, or
 *                  rename any row.
 *   workStatus   — "Looking for Work", "Busy" or "Booked until 2026-12-12"
 *   training     — ACTORS ONLY. Classes and programs, one per line (\n).
 *   resume       — ACTORS ONLY. Credits: category (Film, Television, Theatre,
 *                  Commercial, New Media, Other), project, role, company, year.
 *                  Actor samples open a full profile page built from all of this.
 *   skills       — actors and musicians: special skills shown as tags
 *                  (instruments, dance styles, accents, stage combat…)
 *   current      — FILMMAKERS ONLY. "Currently working on" column.
 *   past         — FILMMAKERS ONLY. "Past projects" column.
 *                  Each project: title, and optional role, year, note.
 *   sample       — true shows a small "Sample" tag; set false once it's real
 */
export const SHOW_SAMPLE_PROFILES = true;

export type SampleProject = {
  title: string;
  role?: string;
  year?: string;
  note?: string;
  /** Where the title links: the post or Discover project page. Samples have none. */
  href?: string;
};

export type SampleProfile = {
  id: string;
  name: string;
  headshot?: string;
  major?: string;
  classOf?: string;
  school?: string;
  union?: string;
  roles: string[];
  blurb: string;
  details?: { label: string; value: string }[];
  skills?: string[];
  /** "Looking for Work", "Busy" or "Booked until YYYY-MM-DD" (see lib/workStatus.ts). */
  workStatus?: string;
  /** ACTORS ONLY: training lines, one per line. */
  training?: string;
  /** ACTORS ONLY: resume credits outside Nexus. */
  resume?: Omit<ResumeCredit, "id">[];
  current?: SampleProject[];
  past?: SampleProject[];
  sample: boolean;
};

export const SAMPLE_PROFILES: Record<PeopleSlug, SampleProfile[]> = {
  filmmakers: [
    {
      id: "sample-film-1",
      name: "Maya Castillo",
      major: "Radio-Television-Film",
      classOf: "2027",
      school: "The University of Texas at Austin",
      roles: ["Director", "Writer"],
      blurb:
        "Maya writes and directs quiet, character-driven shorts about family and home. Her thesis film follows three sisters clearing out their late grandmother's house in San Antonio.\n\nShe's looking for a producer and a cinematographer for her next project.",
      current: [
        { title: "Paper Saints", role: "Director, Writer", note: "Thesis short. In pre-production, shooting spring 2027." },
        { title: "Untitled Documentary", role: "Producer", note: "Developing with a classmate." },
      ],
      past: [
        { title: "What the House Keeps", role: "Director, Writer", year: "2026" },
        { title: "Porch Light", role: "Director", year: "2025" },
        { title: "Sunday Drive", role: "Writer", year: "2024" },
      ],
      sample: true,
    },
    {
      id: "sample-film-2",
      name: "Jordan Okafor",
      major: "Radio-Television-Film",
      classOf: "2026",
      school: "The University of Texas at Austin",
      roles: ["Cinematographer", "Editor"],
      blurb:
        "Jordan shoots on anything from a Super 8 to an FX3 and has DP'd more than a dozen student shorts. Known for natural-light night work.",
      current: [{ title: "Static Bloom", role: "Cinematographer", note: "Shooting this month in East Austin." }],
      past: [
        { title: "After Hours on 6th", role: "Cinematographer", year: "2026" },
        { title: "Two Truths", role: "Cinematographer, Editor", year: "2025" },
        { title: "Low Water", role: "Editor", year: "2025" },
      ],
      sample: true,
    },
  ],
  actors: [
    {
      id: "sample-actor-1",
      name: "Priya Raman",
      major: "Theatre & Dance",
      classOf: "2027",
      school: "The University of Texas at Austin",
      roles: ["Actor"],
      union: "SAG-AFTRA Eligible",
      blurb:
        "Priya has played leads in four student films and two mainstage productions. Comfortable with comedy and drama, and fluent in English and Tamil.",
      details: [
        { label: "Gender", value: "Female" },
        { label: "Ethnic appearance", value: "South Asian" },
        { label: "Height", value: "5'6\"" },
        { label: "Age", value: "21" },
        { label: "Age range", value: "18–26" },
        { label: "Hair", value: "Black" },
        { label: "Eyes", value: "Brown" },
        { label: "Languages", value: "English, Tamil" },
        { label: "Based in", value: "Austin, TX" },
      ],
      skills: ["Bharatanatyam dance", "Violin", "British accent", "Stage combat"],
      workStatus: "Looking for Work",
      training: "BFA Acting, UT Austin (in progress)\nMeisner technique, two-year studio program\nBharatanatyam, 12 years",
      resume: [
        { category: "Film", project: "Monsoon Letters", role: "Lead (Asha)", company: "dir. Kavya Iyer", year: "2026" },
        { category: "Film", project: "The Quiet Floor", role: "Supporting (Nina)", company: "dir. Daniel Cho", year: "2025" },
        { category: "Theatre", project: "A Midsummer Night's Dream", role: "Hermia", company: "UT Theatre & Dance", year: "2025" },
        { category: "Theatre", project: "Our Town", role: "Emily Webb", company: "Austin youth company", year: "2023" },
        { category: "Commercial", project: "Campus Rec spring campaign", role: "Principal", company: "Longhorn Creative", year: "2025" },
      ],
      sample: true,
    },
    {
      id: "sample-actor-2",
      name: "Marcus Bell",
      major: "Radio-Television-Film",
      classOf: "2028",
      school: "Texas State University",
      roles: ["Actor", "Writer"],
      union: "Non-union",
      blurb: "Marcus is a stand-up and sketch performer who's started acting in short films. Open to student projects of any length.",
      details: [
        { label: "Gender", value: "Male" },
        { label: "Ethnic appearance", value: "White" },
        { label: "Height", value: "5'11\"" },
        { label: "Age", value: "19" },
        { label: "Age range", value: "18–25" },
        { label: "Hair", value: "Brown" },
        { label: "Eyes", value: "Blue" },
        { label: "Languages", value: "English" },
        { label: "Based in", value: "San Marcos, TX" },
      ],
      skills: ["Improv", "Guitar", "Southern accent", "Skateboarding"],
      workStatus: "Busy",
      training: "Improv, Level 4 performance track\nStand-up writing workshop\nOn-camera acting, Texas State",
      resume: [
        { category: "Film", project: "Last Bus to Lockhart", role: "Lead (Wes)", company: "dir. Hannah Pruitt", year: "2025" },
        { category: "New Media", project: "Dorm Room Diplomacy", role: "Series regular", company: "Bobcat Comedy Collective", year: "2026" },
        { category: "Theatre", project: "Noises Off", role: "Garry Lejeune", company: "Texas State Theatre", year: "2025" },
        { category: "Other", project: "Friday Night Sketch", role: "Writer / performer", company: "Campus comedy showcase", year: "2024" },
      ],
      sample: true,
    },
    {
      id: "sample-actor-3",
      name: "Elena Ruiz",
      major: "Theatre & Dance",
      classOf: "2026",
      school: "The University of Texas at Austin",
      roles: ["Actor", "Singer"],
      union: "Non-union",
      blurb: "Elena grew up doing community theater in El Paso and has played leads in three student films. Bilingual and loves comedy.",
      details: [
        { label: "Gender", value: "Female" },
        { label: "Ethnic appearance", value: "Latina" },
        { label: "Height", value: "5'3\"" },
        { label: "Age", value: "22" },
        { label: "Age range", value: "18–26" },
        { label: "Hair", value: "Brown" },
        { label: "Eyes", value: "Brown" },
        { label: "Languages", value: "English, Spanish" },
        { label: "Based in", value: "Austin, TX" },
      ],
      skills: ["Flamenco", "Singing (alto)", "Mexican Spanish dialect"],
      workStatus: "Booked until 2026-12-12",
      training: "BFA Theatre & Dance, UT Austin\nClassical voice (alto), 6 years\nFlamenco and folklórico, 10 years",
      resume: [
        { category: "Film", project: "Sunland", role: "Lead (Marisol)", company: "dir. Diego Salas", year: "2026" },
        { category: "Film", project: "Paper Saints", role: "Supporting (Lucía)", company: "dir. Ana Ortiz", year: "2025" },
        { category: "Film", project: "Border Radio", role: "Lead (Inés)", company: "dir. Mateo Vega", year: "2024" },
        { category: "Theatre", project: "In the Heights", role: "Vanessa", company: "El Paso community theater", year: "2022" },
        { category: "Commercial", project: "Regional furniture store spot", role: "Principal", company: "Sun City Media", year: "2024" },
      ],
      sample: true,
    },
    {
      id: "sample-actor-4",
      name: "Sofia Nguyen",
      major: "Radio-Television-Film",
      classOf: "2028",
      school: "The University of Texas at Austin",
      roles: ["Actor"],
      union: "Non-union",
      blurb: "Sofia is newer to screen acting and brings a background in competitive debate and improv.",
      details: [
        { label: "Gender", value: "Female" },
        { label: "Ethnic appearance", value: "East Asian" },
        { label: "Height", value: "5'2\"" },
        { label: "Age", value: "20" },
        { label: "Age range", value: "17–24" },
        { label: "Hair", value: "Black" },
        { label: "Eyes", value: "Brown" },
        { label: "Languages", value: "English, Vietnamese" },
        { label: "Based in", value: "Austin, TX" },
      ],
      skills: ["Improv", "Figure skating", "Piano"],
      workStatus: "Looking for Work",
      training: "Improv, Level 2\nScene study workshop, UT RTF\nCompetitive debate, 4 years",
      resume: [
        { category: "Film", project: "Overtime", role: "Supporting (Lin)", company: "dir. Marcus Tate", year: "2026" },
        { category: "New Media", project: "Study Break", role: "Lead", company: "Student web series", year: "2025" },
        { category: "Theatre", project: "The Importance of Being Earnest", role: "Cecily", company: "Staged reading, UT RTF", year: "2025" },
      ],
      sample: true,
    },
    {
      id: "sample-actor-5",
      name: "Andre Thomas",
      major: "Theatre & Dance",
      classOf: "2027",
      school: "Huston-Tillotson University",
      roles: ["Actor"],
      union: "SAG-AFTRA Eligible",
      blurb: "Andre has done two national commercials and a recurring role on a web series. Strong in physical comedy.",
      details: [
        { label: "Gender", value: "Male" },
        { label: "Ethnic appearance", value: "Black" },
        { label: "Height", value: "6'2\"" },
        { label: "Age", value: "21" },
        { label: "Age range", value: "19–27" },
        { label: "Hair", value: "Black" },
        { label: "Eyes", value: "Brown" },
        { label: "Languages", value: "English" },
        { label: "Based in", value: "Austin, TX" },
      ],
      skills: ["Basketball", "Tap dance", "Piano"],
      workStatus: "Booked until 2027-01-15",
      training: "BA Theatre, Huston-Tillotson (in progress)\nOn-camera commercial technique\nTap, 10 years",
      resume: [
        { category: "Film", project: "Fast Break", role: "Lead (Jalen)", company: "dir. Tyler Grant", year: "2026" },
        { category: "New Media", project: "Two Left Feet", role: "Recurring (DJ)", company: "Eastside Web Series", year: "2025" },
        { category: "Commercial", project: "National sporting goods spot", role: "Principal", company: "Fieldhouse Agency", year: "2025" },
        { category: "Commercial", project: "National quick-service restaurant spot", role: "Featured", company: "Bright Lane Productions", year: "2024" },
        { category: "Theatre", project: "The Wiz", role: "Tin Man", company: "Huston-Tillotson Theatre", year: "2024" },
      ],
      sample: true,
    },
  ],
  musicians: [
    {
      id: "sample-music-1",
      name: "Lena Brooks",
      major: "Butler School of Music",
      classOf: "2026",
      school: "The University of Texas at Austin",
      roles: ["Singer", "Composer"],
      blurb:
        "Lena writes folk-pop and scores short films on the side. Her debut EP was recorded in a dorm room over one spring break.\n\nOpen to scoring student films.",
      skills: ["Guitar", "Piano", "Logic Pro", "Film scoring"],
      sample: true,
    },
    {
      id: "sample-music-2",
      name: "Diego Alvarez",
      major: "Music Business",
      classOf: "2027",
      school: "The University of Texas at Austin",
      roles: ["Musician", "Sound Mixer"],
      blurb: "Diego produces beats, plays bass in two local bands, and mixes sound for student shoots.",
      skills: ["Ableton Live", "Location sound", "Salsa dancing"],
      sample: true,
    },
  ],
};

export const samplesFor = (slug: PeopleSlug): SampleProfile[] => (SHOW_SAMPLE_PROFILES ? SAMPLE_PROFILES[slug] : []);

/** Every sample, found by its id (e.g. "sample-actor-1"). */
export function sampleById(id: string): SampleProfile | undefined {
  if (!SHOW_SAMPLE_PROFILES) return undefined;
  return Object.values(SAMPLE_PROFILES).flat().find((p) => p.id === id);
}

const row = (p: SampleProfile, label: string) => p.details?.find((d) => d.label.toLowerCase() === label.toLowerCase())?.value ?? "";

/** An actor sample as a real actor profile, so it opens in the Actors Access layout. Nil for other samples. */
export function sampleCreative(p: SampleProfile): CreativeProfile | null {
  if (!p.id.startsWith("sample-actor")) return null;
  const details = emptyDetails();
  const [lo, hi] = (row(p, "Age range").match(/\d+/g) ?? []).map(Number);
  details.actor = {
    ...details.actor,
    ageMin: lo,
    ageMax: hi ?? lo,
    gender: row(p, "Gender"),
    height: row(p, "Height"),
    ethnicAppearance: row(p, "Ethnic appearance"),
    hair: row(p, "Hair"),
    eyes: row(p, "Eyes"),
    union: p.union ?? "",
    basedIn: row(p, "Based in"),
    languages: row(p, "Languages"),
    specialSkills: (p.skills ?? []).join(", "),
    training: p.training ?? "",
    resume: (p.resume ?? []).map((c, i) => ({ id: `${p.id}-${i}`, ...c })),
  };
  return { userID: p.id, style: "Actor", details, headshotUrl: p.headshot, updatedAt: 0 };
}

/** The portfolio header for a sample. */
export function sampleAccount(p: SampleProfile): Account {
  return {
    profileID: "",
    name: p.name,
    imageUrl: p.headshot,
    bio: p.blurb,
    academicLine: "",
    major: p.major,
    classOf: p.classOf,
    school: p.school ?? "",
    roles: p.roles,
    workStatus: p.workStatus,
    portfolioOrder: [],
    portfolioLayout: {},
  };
}
