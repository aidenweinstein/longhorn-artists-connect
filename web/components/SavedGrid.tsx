"use client";

import { useEffect, useState } from "react";
import { savedCards } from "@/app/(app)/playlists/actions";
import type { Post } from "@/lib/mockContent";
import PagedGrid from "./PagedGrid";

// Same key PostActions writes to: saves live in this browser, as they live on each phone in the app.
const SAVED_KEY = "nexus_saved_posts";

export default function SavedGrid() {
  const [posts, setPosts] = useState<Post[] | null>(null);

  useEffect(() => {
    let live = true;
    let ids: string[] = [];
    try {
      const v = JSON.parse(localStorage.getItem(SAVED_KEY) ?? "[]");
      if (Array.isArray(v)) ids = v.filter((x): x is string => typeof x === "string");
    } catch {
      // Storage blocked (private window): nothing saved to show.
    }
    savedCards(ids)
      .then((cards) => live && setPosts(cards))
      .catch(() => live && setPosts([]));
    return () => {
      live = false;
    };
  }, []);

  if (posts === null) return null;
  if (posts.length === 0) {
    return <p className="py-20 text-center text-muted">Posts you save will show up here. Saves stay in this browser.</p>;
  }
  return <PagedGrid posts={posts} />;
}
