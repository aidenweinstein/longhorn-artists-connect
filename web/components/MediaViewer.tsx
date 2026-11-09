"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";

/** Media frame with a fullscreen toggle. Keeps the post's aspect ratio in both modes. */
export default function MediaViewer({ aspect, children }: { aspect: number; children: ReactNode }) {
  const frame = useRef<HTMLDivElement>(null);
  const [full, setFull] = useState(false);

  useEffect(() => {
    const onChange = () => setFull(document.fullscreenElement === frame.current);
    document.addEventListener("fullscreenchange", onChange);
    return () => document.removeEventListener("fullscreenchange", onChange);
  }, []);

  function toggle() {
    if (document.fullscreenElement) document.exitFullscreen();
    else frame.current?.requestFullscreen();
  }

  return (
    <div
      ref={frame}
      // Sized to the media itself so there are never bars beside or above it.
      style={full ? undefined : { width: `min(100%, calc((100vh - 9rem) * ${aspect}))` }}
      className={`group relative flex items-center justify-center ${full ? "h-screen w-screen bg-black" : "mx-auto overflow-hidden rounded-2xl"}`}
    >
      <div
        className="relative overflow-hidden transition-[aspect-ratio] duration-300"
        style={{ aspectRatio: aspect, width: full ? `min(100%, calc(100vh * ${aspect}))` : "100%" }}
      >
        {children}
      </div>
      <button
        type="button"
        onClick={toggle}
        aria-label={full ? "Exit fullscreen" : "Enter fullscreen"}
        title={full ? "Exit fullscreen (Esc)" : "Fullscreen"}
        className="absolute bottom-3 right-3 flex h-10 w-10 items-center justify-center rounded-full bg-black/60 text-white opacity-80 backdrop-blur transition hover:bg-black/80 hover:opacity-100"
      >
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
          {full ? (
            <path d="M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5" />
          ) : (
            <path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5" />
          )}
        </svg>
      </button>
    </div>
  );
}
