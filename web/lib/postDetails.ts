import type { Post } from "./mockContent";

// Placeholder details until real records come from CloudKit. Field names and
// sections mirror the app's detail views (FilmDetailView, MusicDetailView,
// ReelDetailView, and the Photography and Design models in MediaModels.swift).

export type Credit = { role: string; name: string; avatarUrl?: string; profileID?: string };
export type CreditGroup = { title: string; credits: Credit[] };

export type PostDetails = {
  /** Artist / photographer line under the title. */
  byline?: string;
  ageRating?: string;
  genres: string[];
  explicit?: boolean;
  /** Studio and release year, shown like the app's "Collective • 2025". */
  studio?: string;
  releaseYear?: string;
  /** Music's category or design's category, e.g. "Single", "Poster". */
  kindLabel?: string;
  logline?: string;
  description: string;
  creditGroups: CreditGroup[];
  /** Music "Also On" streaming services (placeholder posts, names only). */
  alsoOn?: string[];
  /** Music "Also On" links for real posts: [service, url]. */
  links?: [string, string][];
  lyrics?: string;
  /** Photography gear. */
  equipment?: { label: string; value: string }[];
  /** Reel "Featured Work". */
  featuredWork?: string[];
  hasTrailer?: boolean;
  trailerUrl?: string;
  submittedBy: string;
};

const NAMES = ["Alex Romero", "Taylor Brooks", "Jamie Chen", "Morgan Diaz", "Casey Park", "Riley Patel", "Sam Okafor"];
const pick = (post: Post, i: number) => NAMES[(Number(post.id) * 3 + i) % NAMES.length];

export function detailsFor(post: Post): PostDetails {
  switch (post.category) {
    case "film":
      return {
        ageRating: "PG-13",
        genres: ["Drama", "Thriller"],
        studio: "Collective",
        releaseYear: "2026",
        logline: "A night-shift nurse discovers her patients are dreaming the same dream.",
        description:
          "Shot on location in Austin over three weekends with a crew of RTF students. Made for the Fall showcase.",
        creditGroups: [
          { title: "Cast", credits: [
            { role: "Dana", name: pick(post, 0) },
            { role: "Marcus", name: pick(post, 1) },
            { role: "Night Manager", name: pick(post, 2) },
          ] },
          { title: "Crew", credits: [
            { role: "Director", name: post.creator },
            { role: "Cinematographer", name: pick(post, 3) },
            { role: "Editor", name: pick(post, 4) },
            { role: "Sound Mixer", name: pick(post, 5) },
          ] },
        ],
        hasTrailer: true,
        submittedBy: post.creator,
      };
    case "music":
      return {
        byline: post.creator,
        genres: ["Indie", "Lo-fi"],
        explicit: Number(post.id) % 2 === 1,
        releaseYear: "2026",
        kindLabel: "EP",
        description: "Recorded and mixed in a dorm-room studio, then mastered at the Moody College audio lab.",
        creditGroups: [
          { title: "Recording", credits: [
            { role: "Vocals", name: post.creator },
            { role: "Guitar", name: pick(post, 0) },
            { role: "Drums", name: pick(post, 1) },
          ] },
          { title: "Production", credits: [
            { role: "Producer", name: pick(post, 2) },
            { role: "Mix Engineer", name: pick(post, 3) },
            { role: "Mastering", name: pick(post, 4) },
          ] },
        ],
        alsoOn: ["Spotify", "Apple Music", "SoundCloud", "YouTube Music"],
        lyrics: "Lyrics will appear here when the post includes them.",
        submittedBy: post.creator,
      };
    case "performance":
      return {
        byline: post.creator,
        genres: [],
        kindLabel: "Acting Reel",
        description: "Captured live at the spring showcase in front of a full house.",
        creditGroups: [
          { title: "Crew", credits: [
            { role: "Performer", name: post.creator },
            { role: "Choreographer", name: pick(post, 0) },
            { role: "Videographer", name: pick(post, 1) },
          ] },
        ],
        featuredWork: ["Night Shift — Short Film", "Spring Showcase: Contemporary Set"],
        submittedBy: post.creator,
      };
    case "photography":
      return {
        byline: post.creator,
        genres: [],
        releaseYear: "2026",
        description: "Shot on 35mm and scanned at home. A look at the city in the in-between hours.",
        equipment: [
          { label: "Camera", value: "Canon AE-1" },
          { label: "Lens", value: "FD 50mm f/1.8" },
          { label: "Lighting", value: "Natural light" },
          { label: "Filters", value: "None" },
        ],
        creditGroups: [
          { title: "Credits", credits: [
            { role: "Photographer", name: post.creator },
            { role: "Model", name: pick(post, 0) },
            { role: "Stylist", name: pick(post, 1) },
          ] },
        ],
        submittedBy: post.creator,
      };
    case "design":
      return {
        genres: [],
        kindLabel: "Poster",
        releaseYear: "2026",
        description: "A series exploring bold type and the burnt-orange palette, built for a campus event.",
        creditGroups: [
          { title: "Credits", credits: [
            { role: "Designer", name: post.creator },
            { role: "Art Director", name: pick(post, 0) },
          ] },
        ],
        submittedBy: post.creator,
      };
  }
}
