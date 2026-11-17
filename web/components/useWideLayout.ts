"use client";

import { useEffect, useState } from "react";

/**
 * Whether the window is wide enough for the 3-column grid. `null` until the page has
 * loaded in the browser: the server can't know the width, so the first paint carries
 * both layouts (one hidden by CSS) and only the one in use is kept afterwards.
 */
export function useWideLayout(): boolean | null {
  const [wide, setWide] = useState<boolean | null>(null);
  useEffect(() => {
    const query = window.matchMedia("(min-width: 1024px)");
    const update = () => setWide(query.matches);
    update();
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);
  return wide;
}
