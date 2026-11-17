import { toCard } from "@/lib/feedCard";
import type { Post } from "@/lib/mockContent";
import PagedGrid from "./PagedGrid";

/**
 * A grid of posts for pages that have their whole list in hand (portfolios, school
 * pages). The browser gets only what a card shows, lays out the first 24, and adds
 * more as you scroll.
 */
export default function PostGrid({ posts }: { posts: Post[] }) {
  if (posts.length === 0) {
    return <p className="py-20 text-center text-muted">Nothing here yet.</p>;
  }
  return <PagedGrid posts={posts.map(toCard)} />;
}
