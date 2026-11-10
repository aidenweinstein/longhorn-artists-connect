"use client";

import { useEffect, useState, type ReactNode } from "react";
import { savedGrid } from "@/app/(app)/playlists/actions";
import ComingSoon from "./ComingSoon";

// Same key PostActions saves under. The app keeps saves on each phone, so the website keeps them in the browser.
const SAVED_KEY = "nexus_saved_posts";

const PLACEHOLDER = <ComingSoon title="Saved" body="Your saved posts will show up here." />;

/** The posts saved in this browser. Anything that goes wrong shows the page as it was before. */
export default function SavedPosts() {
  const [view, setView] = useState<ReactNode>(null);

  useEffect(() => {
    let live = true;
    (async () => {
      let ids: string[] = [];
      try {
        const v = JSON.parse(localStorage.getItem(SAVED_KEY) ?? "[]");
        if (Array.isArray(v)) ids = v.filter((x): x is string => typeof x === "string");
      } catch {
        // Storage blocked: nothing to show.
      }
      if (ids.length === 0) return live && setView(<ComingSoon title="Saved" body="Nothing saved yet. Tap Save on a post and it shows up here." />);
      const res = await savedGrid(ids).catch(() => null);
      if (!live) return;
      if (!res) return setView(PLACEHOLDER);
      setView(
        res.grid ? (
          <div className="w-full">
            <h1 className="mt-4 text-3xl font-bold">Saved</h1>
            <div className="mt-5">{res.grid}</div>
          </div>
        ) : (
          <ComingSoon title="Saved" body="The posts you saved aren't available anymore." />
        ),
      );
    })();
    return () => {
      live = false;
    };
  }, []);

  return view ?? null;
}
