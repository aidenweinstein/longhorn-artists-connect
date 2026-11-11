// Search autocomplete: shared types and the per-page priority order.
// Safe to import from client components (no server-only code here).

export type SearchKind = "content" | "artist" | "project" | "event";

export type SearchResult = {
  kind: SearchKind;
  id: string;
  title: string;
  subtitle?: string;
  /** Small label on the right, e.g. "Film", "Artist", "Project". */
  label: string;
  /** Profile picture for artists; poster, flyer or thumbnail for everything else. */
  imageUrl?: string;
  href: string;
};

/** Autofill starts after this many typed characters. */
export const MIN_QUERY_LENGTH = 3;
/** Most results the API returns; the dropdown shows five at a time and scrolls. */
export const MAX_RESULTS = 20;

/** Which kinds come first, depending on the page being searched from. */
export function searchOrderFor(pathname: string): SearchKind[] {
  if (/^\/discover\/events(\/|$)/.test(pathname)) return ["event", "project", "content", "artist"];
  if (/^\/discover(\/|$)/.test(pathname)) return ["project", "event", "content", "artist"];
  if (/^\/(network|portfolio|people)(\/|$)/.test(pathname)) return ["artist", "content", "project", "event"];
  // Home, posts, Share, schools and everything else: work first.
  return ["content", "artist", "project", "event"];
}
