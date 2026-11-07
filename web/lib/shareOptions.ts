// Option lists for the Share forms, copied from the app so a post made on the web
// stores the same values (FilmSubmissionView, MusicSubmissionView, ReelSubmissionView,
// DesignSubmissionView, ProjectSubmissionView, EventSubmissionView, SharedSubmissionTypes).

export const FILM_CATEGORIES = ["Org Project", "Class Project", "Independent Project"] as const;
export type FilmCategory = (typeof FILM_CATEGORIES)[number];

export const FILM_STUDIOS = ["Collective", "Incubator", "Beyond Frame Productions", "DKA", "Black Lens"];

export const PRODUCTION_CLASSES = [
  "RTF 304D Intro to Production",
  "RTF 366K Narrative Production",
  "RTF 343 Advanced Narrative Production",
  "RTF 367D Directing Workshop",
];

export const FILM_GENRES = [
  "Action", "Adventure", "Advertisement", "Animation", "Biographical", "Comedy", "Coming-of-Age", "Crime",
  "Documentary", "Drama", "Epic", "Fantasy", "Feel-Good", "Heist", "Historical", "Horror", "Musical", "Mystery",
  "Puppetry", "Romance", "Satire", "Sci-Fi", "Sports", "Stop-Motion", "Thriller", "Western", "Experimental",
];

export const AGE_RATINGS = ["G", "PG", "PG-13", "R"] as const;

export const CREW_ROLES = [
  "Director", "Producer", "Writer", "Editor",
  "Director of Photography", "1st Assistant Camera", "2nd Assistant Camera",
  "Gaffer", "Key Grip", "Grip", "BBE",
  "Composer", "On-Set Mixer", "Boom Operator", "SFX Designer", "Sound Mixer",
  "Production Designer", "Wardrobe", "Hair and Makeup", "Set Dresser",
  "Stunt Coordinator", "Colorist", "Production Assistant",
];

export const MUSIC_CATEGORIES = ["Song", "EP", "Album", "Performance"];
export const MUSIC_GENRES = [
  "Pop", "Rock", "Hip Hop", "R&B", "Country", "Jazz", "Classical", "Electronic", "Folk", "Blues",
  "Reggae", "Metal", "Punk", "Soul", "Funk", "Latin", "Gospel", "Indie", "Alternative",
];
export const RECORDING_ROLES = ["Vocalist", "Lead Guitar", "Rhythm Guitar", "Bass Guitar", "Drums"];
export const PRODUCTION_ROLES = ["Producer", "Mixer", "Engineer"];
export const STREAMING_SERVICES = ["Spotify", "Apple Music", "YouTube Music", "SoundCloud"];

export const PERFORMANCE_CATEGORIES = ["Acting Reel", "Dancing Reel", "Actor Showcase", "Dance Showcase"];

export const DESIGN_CATEGORIES = ["Graphic", "Magazine", "Drawing", "Painting", "Modeling"];

export const PHOTO_EQUIPMENT = [
  { key: "camera", label: "Camera", placeholder: "e.g., Canon EOS R5" },
  { key: "lens", label: "Lens", placeholder: "e.g., RF 24-70mm f/2.8" },
  { key: "lighting", label: "Lighting", placeholder: "e.g., Godox AD200, natural light" },
  { key: "filters", label: "Filters", placeholder: "e.g., Polarizer, ND1000" },
  { key: "support", label: "Support", placeholder: "e.g., Tripod, gimbal, monopod" },
  { key: "accessories", label: "Other equipment", placeholder: "e.g., Drone, editing software" },
] as const;

export const PROJECT_CATEGORIES = ["Cast & Crew Call", "Script", "In-Development"] as const;
export type ProjectCategory = (typeof PROJECT_CATEGORIES)[number];
export const SCRIPT_GENRES = ["Action", "Comedy", "Drama", "Horror", "Mystery", "Romance", "Sci-Fi", "Thriller", "Western", "Documentary"];

export const EVENT_CATEGORIES = [
  "Concert", "Showcase", "Theatre Performance", "Film Festival",
  "Artist Mixer", "Recruitment Schedule", "Info Session", "Speaker",
] as const;
export type EventCategory = (typeof EVENT_CATEGORIES)[number];

/** Which fields each event category shows — EventCategoryKind in the app. */
export function eventRules(kind: EventCategory) {
  return {
    usesDateRange: kind === "Recruitment Schedule",
    usesDateTime: kind !== "Recruitment Schedule" && kind !== "Theatre Performance",
    usesShowings: kind === "Theatre Performance",
    showsLocation: kind !== "Recruitment Schedule",
    showsExpectations: kind === "Recruitment Schedule",
    showsApplicationLink: kind === "Recruitment Schedule",
    showsTicketLink: kind === "Concert" || kind === "Theatre Performance",
    lineupLabel: ({ Concert: "Artists", Showcase: "Actors", "Theatre Performance": "Cast", "Film Festival": "Films", Speaker: "Speakers" } as Record<string, string>)[kind],
  };
}

/** Next year down through nine years back, like the app's release-year menu. */
export function releaseYears(): string[] {
  const current = new Date().getFullYear();
  return Array.from({ length: 11 }, (_, i) => String(current + 1 - i));
}
