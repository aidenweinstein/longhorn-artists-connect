"use client";

import { useEffect } from "react";

// On reload, start at the top instead of restoring the old scroll position.
export default function ScrollToTop() {
  useEffect(() => {
    if ("scrollRestoration" in history) history.scrollRestoration = "manual";
    window.scrollTo(0, 0);
    // The app pages scroll inside <main id="app-scroll">, not the window.
    document.getElementById("app-scroll")?.scrollTo(0, 0);
  }, []);
  return null;
}
