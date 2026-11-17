"use client";

import { useEffect, useRef, useState } from "react";
import type { Post } from "@/lib/mockContent";
import { Masonry } from "./ContentGrid";
import { useWideLayout } from "./useWideLayout";

const PAGE = 24;

/**
 * A grid of posts that lays out the first cards only and adds the next ones shortly
 * before you scroll to the end. For pages that already have their whole list
 * (portfolios, school pages); Home fetches its pages instead (FeedGrid).
 */
export default function PagedGrid({ posts }: { posts: Post[] }) {
  const [count, setCount] = useState(PAGE);
  const wide = useWideLayout();
  const sentinel = useRef<HTMLDivElement>(null);
  const hasMore = count < posts.length;

  // The page's <main> is what scrolls, not the window. Re-made after each step so it
  // fires again if the end is still in reach.
  useEffect(() => {
    const el = sentinel.current;
    if (!el || !hasMore) return;
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) setCount((c) => c + PAGE);
      },
      { root: document.getElementById("app-scroll"), rootMargin: "1200px 0px" },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [count, hasMore]);

  const shown = posts.slice(0, count);
  return (
    <>
      {wide !== true && <Masonry posts={shown} columns={2} stackOnPhones className={wide === null ? "lg:hidden" : ""} />}
      {wide !== false && <Masonry posts={shown} columns={3} className={wide === null ? "hidden lg:flex" : "flex"} />}
      {hasMore && <div ref={sentinel} aria-hidden className="h-px" />}
    </>
  );
}
