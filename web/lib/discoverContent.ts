// Placeholder projects and events for Discover until CloudKit is connected.
// Fields mirror the app's ProjectCard and EventCard.

export type Project = {
  kind: "project";
  id: string;
  title: string;
  projectType: "Cast & Crew Call" | "Script" | "In Development";
  logline: string;
  postedBy: string;
  shootDates?: string;
  castNeeded: string[];
  crewNeeded: string[];
  posterUrl?: string;
  /** Pictures shown before the poster on the detail page, like the app's slideshow. */
  slides?: string[];
  genres?: string[];
  /** Shoot start and expected release, in ms, when the poster picked a date rather than typed text. */
  shootStart?: number;
  releaseDate?: string;
  releaseDateAt?: number;
  /** People already on the team. */
  castAssembled?: { role: string; name: string; profileID?: string }[];
  crewAssembled?: { role: string; name: string; profileID?: string }[];
  /** Script posts (older records). */
  writers?: string;
  scriptPages?: number;
  postedByProfileID?: string;
  createdAt?: number;
  editedAt?: number;
};

export type NexusEvent = {
  kind: "event";
  id: string;
  title: string;
  host: string;
  location: string;
  when: string;
  logline: string;
  ticketed: boolean;
  flyerUrl?: string;
  /** Start time in ms, when known. */
  startsAt?: number;
  endsAt?: number;
  /** e.g. "Concert", "Film Festival", "Recruitment Schedule". */
  category?: string;
  lineup?: string[];
  /** Entry requirements, for recruitment schedules. */
  expectations?: string;
  ticketsUrl?: string;
  applyUrl?: string;
  /** Every performance in a run, as [start, end] in ms. */
  showings?: [number, number][];
  postedBy?: string;
  postedByProfileID?: string;
  createdAt?: number;
  editedAt?: number;
};

export type DiscoverItem = Project | NexusEvent;

export const DISCOVER_ITEMS: DiscoverItem[] = [];
