/*
 * SAMPLE "NOW" DATA — what the Now pages show until sets, auditions and shoots
 * live in the app. Edit freely. Dates are written as "YYYY-MM-DD"; times as text.
 */

export type Call = { date: string; time: string; location: string; note?: string };

/* ---------- Filmmakers ---------- */

export type MySet = {
  id: string;
  project: string;
  logline: string;
  director: string;
  myRole: string;
  status: "Pre-production" | "Shooting" | "Post-production";
  nextCall?: Call;
  /** Shoot days left, e.g. "3 of 6 days left". */
  progress?: string;
};


export const MY_SETS: MySet[] = [
  {
    id: "paper-saints",
    project: "Paper Saints",
    logline: "Two sisters run their late mother's botánica while their brother plots to sell it.",
    director: "Maya Castillo",
    myRole: "Director",
    status: "Pre-production",
    nextCall: { date: "2026-11-09", time: "2:00 PM", location: "CMB Studio 4B", note: "Table read with full cast" },
  },
  {
    id: "static-bloom",
    project: "Static Bloom",
    logline: "A late-night radio host starts hearing tomorrow's news.",
    director: "Nina Hale",
    myRole: "1st AD",
    status: "Shooting",
    progress: "3 of 6 days left",
    nextCall: { date: "2026-11-07", time: "6:30 AM", location: "KVRX studio, Hearst Student Media", note: "Night exteriors after lunch" },
  },
  {
    id: "lucha",
    project: "Lucha",
    logline: "A family-run wrestling gym on the East Side fights to keep its doors open.",
    director: "Maya Castillo",
    myRole: "Director, Editor",
    status: "Post-production",
    nextCall: { date: "2026-11-12", time: "7:00 PM", location: "Edit Bay 2, CMB", note: "Picture lock review" },
  },
];

/* ---------- Actors ---------- */

export type Shoot = {
  id: string;
  project: string;
  director: string;
  character: string;
  characterNote: string;
  calls: Call[];
  scriptID: string;
};

export type Audition = {
  id: string;
  project: string;
  director: string;
  character: string;
  date: string;
  status: "Submitted" | "Callback" | "Booked" | "Not selected";
  scriptID?: string;
};

export const MY_SHOOTS: Shoot[] = [
  {
    id: "static-bloom",
    project: "Static Bloom",
    director: "Nina Hale",
    character: "Iris (Lead)",
    characterNote: "A late-night radio host, sharp and tired, who starts hearing tomorrow's news.",
    calls: [
      { date: "2026-11-07", time: "7:00 AM", location: "KVRX studio, Hearst Student Media", note: "Scenes 12, 14, 15" },
      { date: "2026-11-08", time: "4:00 PM", location: "South Congress Bridge", note: "Night exterior, scene 22" },
    ],
    scriptID: "static-bloom",
  },
  {
    id: "paper-saints",
    project: "Paper Saints",
    director: "Maya Castillo",
    character: "Teresa (Lead)",
    characterNote: "The older sister holding the family shop together.",
    calls: [
      { date: "2026-11-09", time: "2:00 PM", location: "CMB Studio 4B", note: "Table read" },
      { date: "2026-12-05", time: "8:00 AM", location: "Botánica set, West Side", note: "Day 1 of 5" },
    ],
    scriptID: "paper-saints",
  },
];

export const MY_AUDITIONS: Audition[] = [
  { id: "a1", project: "Paper Saints", director: "Maya Castillo", character: "Teresa", date: "2026-10-20", status: "Booked", scriptID: "paper-saints" },
  { id: "a2", project: "The Long Quiet", director: "Theo Grant", character: "June", date: "2026-11-05", status: "Callback", scriptID: "the-long-quiet" },
  { id: "a3", project: "First Draft", director: "Casey Park", character: "Mel", date: "2026-11-03", status: "Submitted" },
  { id: "a4", project: "After Hours on 6th", director: "Jordan Okafor", character: "Lena", date: "2026-10-02", status: "Not selected" },
];

/* ---------- Scripts (sides) ---------- */

/** One line of screenplay: scene heading, action, character cue, parenthetical, dialogue, or transition. */
export type ScriptLine = ["scene" | "action" | "character" | "paren" | "dialogue" | "transition", string];
export type Script = { id: string; title: string; writer: string; draft: string; pages: string; lines: ScriptLine[] };

export const SCRIPTS: Script[] = [
  {
    id: "static-bloom",
    title: "Static Bloom",
    writer: "Nina Hale",
    draft: "Shooting draft, Oct 28",
    pages: "Sides: scenes 12, 14, 15",
    lines: [
      ["scene", "12  INT. KVRX BROADCAST BOOTH - NIGHT"],
      ["action", "A cramped booth lit by one desk lamp and a wall of blinking meters. IRIS (22) leans into the mic, headphones half on."],
      ["character", "IRIS"],
      ["dialogue", "It's 2:14 in the morning, Austin. If you're still up, you're either studying or you're in love. Either way, I'm sorry."],
      ["action", "She cues a record. Static crackles under the music. Then a VOICE, faint, under the hiss."],
      ["character", "VOICE (V.O.)"],
      ["paren", "(through static)"],
      ["dialogue", "...the bridge on Congress closes at noon tomorrow..."],
      ["action", "Iris freezes. She pulls the headphones fully on."],
      ["character", "IRIS"],
      ["paren", "(off-mic)"],
      ["dialogue", "Who is that?"],
      ["transition", "CUT TO:"],
      ["scene", "14  INT. KVRX HALLWAY - CONTINUOUS"],
      ["action", "Iris pushes through the door. Empty hallway. A vending machine hums."],
      ["character", "IRIS"],
      ["dialogue", "Marcus? If this is a bit, it's not funny."],
      ["action", "Nobody answers. Behind her, through the booth window, the meters jump on their own."],
    ],
  },
  {
    id: "paper-saints",
    title: "Paper Saints",
    writer: "Maya Castillo",
    draft: "Draft 4, Oct 30",
    pages: "Sides: scene 3",
    lines: [
      ["scene", "3  INT. BOTÁNICA - DAY"],
      ["action", "Shelves of candles, saints, and dried herbs. TERESA (24) counts cash at the register. ROSA (19) balances on a ladder, dusting a statue of San Judas."],
      ["character", "ROSA"],
      ["dialogue", "Danny says a guy from a coffee chain came by again."],
      ["character", "TERESA"],
      ["paren", "(not looking up)"],
      ["dialogue", "Danny says a lot of things."],
      ["character", "ROSA"],
      ["dialogue", "He says they'd pay cash. Like, real cash."],
      ["action", "Teresa closes the register harder than she needs to."],
      ["character", "TERESA"],
      ["dialogue", "Mamá didn't keep this place open for thirty years so we could sell it for lattes."],
      ["character", "ROSA"],
      ["dialogue", "Mamá isn't the one paying the light bill."],
      ["action", "Silence. Rosa climbs down. The bell over the door rings."],
    ],
  },
  {
    id: "the-long-quiet",
    title: "The Long Quiet",
    writer: "Theo Grant",
    draft: "Audition sides",
    pages: "Sides: scene 7",
    lines: [
      ["scene", "7  EXT. LIGHTHOUSE GALLERY - DUSK"],
      ["action", "Wind. JUNE (20) grips the rail. Below, a technician's truck drives away."],
      ["character", "JUNE"],
      ["dialogue", "They put a computer in it. A computer, Dad. It doesn't even know what it's looking at."],
      ["action", "She waits for an answer that doesn't come."],
      ["character", "JUNE (CONT'D)"],
      ["dialogue", "Fine. Then I'll look for both of us."],
    ],
  },
];

export const findScript = (id: string) => SCRIPTS.find((s) => s.id === id);

/** "2026-11-07" → "Sat, Nov 7". */
export function shortDate(iso: string) {
  return new Date(`${iso}T12:00:00`).toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" });
}
