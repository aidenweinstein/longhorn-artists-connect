// Search: shared types, the per-page priority order, and the text each kind of
// thing is matched against. Safe to import from client components (no server-only code).

import { getCategory } from "./categories";
import type { DiscoverItem } from "./discoverContent";
import type { Post } from "./mockContent";

export type SearchKind = "content" | "artist" | "project" | "event" | "organization";

export type SearchResult = {
  kind: SearchKind;
  id: string;
  title: string;
  subtitle?: string;
  /** Small label on the right: the type, e.g. "Film", "Actor", "Project", "Organization". */
  label: string;
  /** Profile picture for people; poster, flyer or thumbnail for everything else. */
  imageUrl?: string;
  href: string;
};

/** Autofill starts after this many typed characters. */
export const MIN_QUERY_LENGTH = 3;
/** Most results the API returns; the dropdown shows five at a time and scrolls. */
export const MAX_RESULTS = 20;

/** Which kinds come first, depending on the page being searched from. */
export function searchOrderFor(pathname: string): SearchKind[] {
  if (/^\/discover\/(organizations|classes)(\/|$)/.test(pathname)) return ["organization", "project", "event", "content", "artist"];
  if (/^\/discover\/events(\/|$)/.test(pathname)) return ["event", "project", "organization", "content", "artist"];
  if (/^\/discover(\/|$)/.test(pathname)) return ["project", "event", "organization", "content", "artist"];
  if (/^\/(network|portfolio|people)(\/|$)/.test(pathname)) return ["artist", "organization", "content", "project", "event"];
  // Home, posts, Share, schools and everything else: work first.
  return ["content", "artist", "organization", "project", "event"];
}

/**
 * Pages whose own list narrows to what was typed when Enter is pressed (the feeds and
 * Discover's lists). Everywhere else, Enter opens the best match.
 */
export function filtersInPlace(pathname: string): boolean {
  return pathname === "/" || /^\/school\/[^/]+\/?$/.test(pathname) || /^\/discover(\/(projects|events|calendar))?\/?$/.test(pathname);
}

/** Lowercased, accents removed, so "Beyonce" finds "Beyoncé". */
export const fold = (s: string | undefined) => (s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();

/** A type name and its plural, so "films" finds films and "actors" finds actors. */
export const typeWords = (label: string | undefined) => (label ? [label, `${label}s`] : []);

/** Everything about a post besides its title that a search can match. */
export function postSearchExtras(p: Post): (string | undefined)[] {
  const d = p.details;
  return [
    p.creator,
    p.meta,
    p.school,
    ...typeWords(getCategory(p.category)?.label),
    d?.byline,
    d?.kindLabel,
    d?.studio,
    d?.releaseYear,
    d?.logline,
    d?.submittedBy,
    ...(d?.genres ?? []),
    ...(p.mainCredits ?? []).map((c) => c.name),
    ...(d?.creditGroups ?? []).flatMap((g) => g.credits.map((c) => c.name)),
  ];
}

/** Everything about a project or event besides its title that a search can match. */
export function discoverSearchExtras(i: DiscoverItem): (string | undefined)[] {
  if (i.kind === "project") {
    return [
      ...typeWords("Project"),
      i.logline,
      i.postedBy,
      i.studio,
      i.projectType,
      i.writers,
      ...(i.genres ?? []),
      ...i.castNeeded,
      ...i.crewNeeded,
      ...(i.castAssembled ?? []).map((c) => c.name),
      ...(i.crewAssembled ?? []).map((c) => c.name),
    ];
  }
  return [...typeWords("Event"), i.logline, i.host, i.location, i.category, i.postedBy, ...(i.lineup ?? [])];
}

/** Whether a page's own list should keep this post / project / event for what was typed. */
export const postMatches = (p: Post, query: string) => {
  const q = fold(query.trim());
  return !q || [p.title, ...postSearchExtras(p)].some((t) => fold(t).includes(q));
};
export const discoverMatches = (i: DiscoverItem, query: string) => {
  const q = fold(query.trim());
  return !q || [i.title, ...discoverSearchExtras(i)].some((t) => fold(t).includes(q));
};
