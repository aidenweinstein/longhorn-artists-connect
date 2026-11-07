import type { Account } from "./cloudkit/content";
import type { PeopleSlug } from "./featured";
import type { Post } from "./mockContent";
import type { CreditGroup } from "./postDetails";

/*
 * SAMPLE PORTFOLIOS — one per People page, opened from its "View sample portfolio"
 * button. They show what a filmmaker, actor, or musician's portfolio looks like
 * once it's full of work. Nothing here is real; edit freely.
 *
 * Each post: [title, category, aspect, seconds, genres, role on it, description].
 * Categories: film, music, performance, design, photography.
 * Aspect is width / height: 16/9 widescreen, 2.39 scope, 1 square, 4/5 portrait.
 */

type Row = [title: string, category: Post["category"], aspect: number, seconds: number, genres: string[], role: string, description: string];

const CREW = ["Alex Romero", "Taylor Brooks", "Jamie Chen", "Morgan Diaz", "Casey Park", "Riley Patel", "Sam Okafor", "Nina Hale", "Theo Grant", "Ava Lin"];
const SCHOOL = "The University of Texas at Austin";

type Sample = { account: Account; rows: Row[] };

const SAMPLES: Record<PeopleSlug, Sample> = {
  filmmakers: {
    account: {
      profileID: "",
      name: "Maya Castillo",
      bio: "Director and writer. Quiet, character-driven shorts about family and home.\nCurrently in pre-production on my thesis film, Paper Saints.",
      academicLine: "Class of '27 • Radio-Television-Film",
      major: "Radio-Television-Film",
      classOf: "2027",
      school: SCHOOL,
      roles: ["Director", "Writer"],
      instagram: "mayacastillo.films",
      website: "mayacastillo.com",
      portfolioOrder: [],
      portfolioLayout: {},
    },
    rows: [
      ["What the House Keeps", "film", 16 / 9, 1080, ["Drama"], "Director", "Three sisters clear out their late grandmother's house in San Antonio."],
      ["Porch Light", "film", 16 / 9, 420, ["Drama"], "Director", "A teenager waits up for a father who isn't coming home."],
      ["Sunday Drive", "film", 2.39, 300, ["Comedy"], "Writer", "A family road trip told entirely from the back seat."],
      ["Paper Saints (Teaser)", "film", 2.39, 75, ["Drama"], "Director", "Teaser for the upcoming thesis film."],
      ["Low Water", "film", 16 / 9, 1560, ["Drama", "Mystery"], "Writer", "A drought uncovers a town's buried secret."],
      ["Lucha", "film", 16 / 9, 720, ["Documentary"], "Director", "A short documentary about a family-run wrestling gym on the East Side."],
      ["Night Swim", "film", 2.39, 540, ["Thriller"], "Director", "Two friends sneak into a closed public pool."],
      ["Abuela's Kitchen", "film", 4 / 5, 90, ["Documentary"], "Director", "A one-take portrait made for a vertical-film challenge."],
      ["Dust Season", "film", 16 / 9, 2700, ["Drama"], "Writer", "Feature-length student drama shot over a summer in West Texas."],
      ["What the House Keeps (Poster)", "design", 2 / 3, 0, ["Poster"], "Art Director", "Theatrical poster for the festival run."],
      ["Stills: Porch Light", "photography", 3 / 2, 0, ["Film Stills"], "Director", "Behind-the-scenes and frame grabs from Porch Light."],
      ["Lucha (Trailer)", "film", 16 / 9, 120, ["Documentary"], "Editor", "Trailer cut for festival submissions."],
      ["The Interview", "film", 16 / 9, 360, ["Comedy"], "Director", "A job interview that goes sideways fast."],
      ["Location Scouts: Marfa", "photography", 4 / 5, 0, ["Landscape"], "Director", "Scouting photos for Dust Season."],
    ],
  },
  actors: {
    account: {
      profileID: "",
      name: "Priya Raman",
      bio: "Actor for film and stage. Leads in four student films and two mainstage productions.\nSAG-AFTRA eligible. Fluent in English and Tamil.",
      academicLine: "Class of '27 • Theatre & Dance",
      major: "Theatre & Dance",
      classOf: "2027",
      school: SCHOOL,
      roles: ["Actor"],
      instagram: "priyaraman.acts",
      portfolioOrder: [],
      portfolioLayout: {},
    },
    rows: [
      ["Acting Reel 2026", "performance", 16 / 9, 110, ["Reel"], "Actor", "Selected scenes from film and stage work this year."],
      ["Self-Tape: Contemporary Monologue", "performance", 16 / 9, 95, ["Monologue"], "Actor", "From 'Mud' by María Irene Fornés."],
      ["Self-Tape: Comedic Monologue", "performance", 16 / 9, 80, ["Monologue", "Comedy"], "Actor", "Original comedic piece."],
      ["Two Truths", "film", 16 / 9, 840, ["Drama"], "Lead — Anjali", "A college student lies to her parents about dropping pre-med."],
      ["After Hours on 6th", "film", 2.39, 720, ["Thriller"], "Supporting — Lena", "A bartender's last shift turns dangerous."],
      ["Headshots 2026", "photography", 4 / 5, 0, ["Headshots"], "Subject", "Commercial and theatrical looks."],
      ["Scene Study: Proof", "performance", 16 / 9, 240, ["Scene"], "Catherine", "Scene from David Auburn's Proof with a classroom partner."],
      ["The Interview", "film", 16 / 9, 360, ["Comedy"], "Lead — Interviewer", "A job interview that goes sideways fast."],
      ["Bharatanatyam Solo", "performance", 9 / 16, 180, ["Dance"], "Dancer", "Classical solo performed at the spring showcase."],
      ["Static Bloom", "film", 2.39, 1320, ["Drama", "Sci-Fi"], "Lead — Iris", "A radio host starts hearing tomorrow's news."],
      ["Accent Reel", "performance", 16 / 9, 70, ["Reel"], "Actor", "British RP, General American, and Indian English."],
      ["Stage Combat Demo", "performance", 16 / 9, 60, ["Stage Combat"], "Actor", "Unarmed and rapier choreography from the combat intensive."],
      ["Night Swim", "film", 2.39, 540, ["Thriller"], "Supporting — Dev", "Two friends sneak into a closed public pool."],
    ],
  },
  musicians: {
    account: {
      profileID: "",
      name: "Lena Brooks",
      bio: "Singer-songwriter writing folk-pop out of Austin. I also score short films.\nDebut EP Hill Country Static out now.",
      academicLine: "Class of '26 • Butler School of Music",
      major: "Butler School of Music",
      classOf: "2026",
      school: SCHOOL,
      roles: ["Singer", "Composer"],
      instagram: "lenabrooksmusic",
      website: "lenabrooks.com",
      portfolioOrder: [],
      portfolioLayout: {},
    },
    rows: [
      ["Hill Country Static", "music", 1, 214, ["Folk", "Pop"], "Vocals, Songwriter", "Title track from the debut EP."],
      ["Riverside", "music", 16 / 9, 232, ["Folk"], "Vocals, Guitar", "Official music video, shot along Lady Bird Lake."],
      ["Live at Cactus Cafe", "performance", 16 / 9, 480, ["Live"], "Vocals, Guitar", "Three-song acoustic set."],
      ["Slow Burn", "music", 1, 198, ["Pop"], "Vocals, Producer", "Single."],
      ["Score: What the House Keeps", "music", 1, 186, ["Score"], "Composer", "Main theme from Maya Castillo's short film."],
      ["Porch Song", "music", 1, 171, ["Folk"], "Vocals, Songwriter", "B-side from Hill Country Static."],
      ["Headlights (Music Video)", "music", 2.39, 245, ["Indie"], "Vocals", "Music video directed by a classmate in RTF."],
      ["Spring Showcase", "performance", 16 / 9, 600, ["Concert"], "Vocals, Piano", "Full set at the Butler School spring showcase."],
      ["Small Hours", "music", 1, 203, ["Folk", "Indie"], "Vocals, Songwriter", "Single."],
      ["Score: Night Swim", "music", 1, 142, ["Score"], "Composer", "Tension cue from the short film Night Swim."],
      ["Hill Country Static (Cover Art)", "design", 1, 0, ["Album Art"], "Art Director", "EP artwork."],
      ["Tour Photos: Texas Run", "photography", 3 / 2, 0, ["Live"], "Subject", "Shots from a five-city run of house shows."],
      ["Gone by Morning", "music", 1, 226, ["Pop"], "Vocals, Producer", "Single."],
      ["Covers Session: Live Loop", "performance", 9 / 16, 150, ["Live"], "Vocals", "Loop-pedal cover recorded for social."],
    ],
  },
};

function toPost(slug: PeopleSlug, account: Account, row: Row, i: number): Post {
  const [title, category, aspect, seconds, genres, role, description] = row;
  const crew = (n: number) => CREW[(i * 3 + n) % CREW.length];
  const me = { role, name: account.name };
  const groups: CreditGroup[] =
    category === "music"
      ? [{ title: "Credits", credits: [me, { role: "Mixing", name: crew(0) }, { role: "Mastering", name: crew(1) }] }]
      : category === "film"
        ? [
            { title: "Cast", credits: slug === "actors" ? [me, { role: "Supporting", name: crew(0) }] : [{ role: "Lead", name: crew(0) }, { role: "Supporting", name: crew(1) }] },
            { title: "Crew", credits: [...(slug === "actors" ? [] : [me]), { role: "Cinematographer", name: crew(2) }, { role: "Editor", name: crew(3) }, { role: "Sound Mixer", name: crew(4) }] },
          ]
        : [{ title: "Credits", credits: [me, { role: category === "performance" ? "Camera" : "Photographer", name: crew(2) }] }];

  return {
    id: `sample-${slug}-${i + 1}`,
    title,
    creator: account.name,
    school: account.school,
    category,
    meta: "",
    aspect,
    duration: seconds || undefined,
    details: {
      byline: category === "music" ? account.name : undefined,
      genres,
      releaseYear: "2026",
      description,
      creditGroups: groups,
      submittedBy: account.name,
    },
  };
}

const POSTS_BY_SLUG = Object.fromEntries(
  (Object.keys(SAMPLES) as PeopleSlug[]).map((slug) => [slug, SAMPLES[slug].rows.map((r, i) => toPost(slug, SAMPLES[slug].account, r, i))]),
) as Record<PeopleSlug, Post[]>;

export function samplePortfolio(slug: PeopleSlug): { account: Account; posts: Post[] } {
  return { account: SAMPLES[slug].account, posts: POSTS_BY_SLUG[slug] };
}

/** Lets a sample tile open its own post page. */
export function findSamplePost(id: string): Post | undefined {
  if (!id.startsWith("sample-")) return undefined;
  return Object.values(POSTS_BY_SLUG).flat().find((p) => p.id === id);
}
