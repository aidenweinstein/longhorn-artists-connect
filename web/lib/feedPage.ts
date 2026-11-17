import { feedPosts } from "./content";
import { toCard } from "./feedCard";
import { filterPosts } from "./filterPosts";
import { mixFeed } from "./mixFeed";
import type { Post } from "./mockContent";
import { myStyle } from "./myStyle";
import { recommend } from "./profileStyle";

/** Cards sent at a time: the first screens' worth, then more as you scroll. */
export const FEED_PAGE_SIZE = 24;

export type FeedFilter = { category?: string; q?: string };

/**
 * One page of the Home feed, in this visit's shuffle. Server-only: the first page is
 * rendered with the page (app/(app)/page.tsx) and the rest come from /api/feed.
 */
export async function feedPage(filter: FeedFilter, seed: number, offset: number): Promise<{ cards: Post[]; hasMore: boolean }> {
  const [posts, { style }] = await Promise.all([feedPosts(), myStyle().catch(() => ({ style: null }))]);
  const mixed = mixFeed(filterPosts(filter, posts), seed);
  // On the unfiltered feed, lead with the kind of work the viewer's profile style is about.
  const ordered = style && !filter.category ? recommend(style, mixed) : mixed;
  const start = Math.max(0, offset);
  return { cards: ordered.slice(start, start + FEED_PAGE_SIZE).map(toCard), hasMore: start + FEED_PAGE_SIZE < ordered.length };
}
