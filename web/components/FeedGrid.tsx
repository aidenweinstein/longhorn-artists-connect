"use client";

import { useEffect, useRef, useState } from "react";
import type { Post } from "@/lib/mockContent";
import { Masonry } from "./ContentGrid";
import { useWideLayout } from "./useWideLayout";

/**
 * The Home feed. It arrives with the first cards only and fetches the next ones from
 * /api/feed shortly before you scroll to the end, so opening Home never means
 * downloading and laying out every post on Nexus.
 */
export default function FeedGrid({
  initial,
  hasMore: initialHasMore,
  seed,
  category,
  q,
}: {
  initial: Post[];
  hasMore: boolean;
  /** This visit's shuffle, so later pages continue the same order. */
  seed: number;
  category?: string;
  q?: string;
}) {
  const [posts, setPosts] = useState(initial);
  const [hasMore, setHasMore] = useState(initialHasMore);
  const [failed, setFailed] = useState(false);
  const loading = useRef(false);
  const sentinel = useRef<HTMLDivElement>(null);

  const wide = useWideLayout();

  async function loadMore() {
    if (loading.current) return;
    loading.current = true;
    setFailed(false);
    try {
      const params = new URLSearchParams({ seed: String(seed), offset: String(posts.length) });
      if (category) params.set("category", category);
      if (q) params.set("q", q);
      const res = await fetch(`/api/feed?${params}`);
      if (!res.ok) throw new Error(String(res.status));
      const page = (await res.json()) as { cards: Post[]; hasMore: boolean };
      setPosts((shown) => {
        const have = new Set(shown.map((p) => p.id));
        return [...shown, ...page.cards.filter((p) => !have.has(p.id))];
      });
      setHasMore(page.hasMore && page.cards.length > 0);
    } catch {
      setFailed(true);
    } finally {
      loading.current = false;
    }
  }

  // Fetch the next cards a couple of screens before the end comes into view. The page's
  // <main> is what scrolls, not the window. Re-made after each page so it fires again
  // if the end is still in reach.
  useEffect(() => {
    const el = sentinel.current;
    if (!el || !hasMore || failed) return;
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) loadMore();
      },
      { root: document.getElementById("app-scroll"), rootMargin: "1200px 0px" },
    );
    io.observe(el);
    return () => io.disconnect();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [posts.length, hasMore, failed]);

  if (posts.length === 0) {
    return <p className="py-20 text-center text-muted">Nothing here yet.</p>;
  }
  return (
    <>
      {wide !== true && <Masonry posts={posts} columns={2} stackOnPhones className={wide === null ? "lg:hidden" : ""} />}
      {wide !== false && <Masonry posts={posts} columns={3} className={wide === null ? "hidden lg:flex" : "flex"} />}
      {hasMore && <div ref={sentinel} aria-hidden className="h-px" />}
      {failed && (
        <p className="py-8 text-center text-sm text-muted">
          Couldn&apos;t load more posts.{" "}
          <button type="button" onClick={loadMore} className="font-medium text-foreground underline">
            Try again
          </button>
        </p>
      )}
    </>
  );
}
