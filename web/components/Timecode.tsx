"use client";

import { useEffect, useRef, useState } from "react";

/** 75 → "1:15", 3725 → "1:02:05". */
export function timecode(seconds: number) {
  const total = Math.round(seconds);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = String(total % 60).padStart(2, "0");
  return h ? `${h}:${String(m).padStart(2, "0")}:${s}` : `${m}:${s}`;
}

// Lengths already read this visit, so scrolling back doesn't fetch again.
const known = new Map<string, number>();
const pending = new Map<string, Promise<number | undefined>>();

/** Reads just the file's header (not the whole video) to learn how long it is. */
function readLength(src: string, kind: "video" | "audio"): Promise<number | undefined> {
  if (known.has(src)) return Promise.resolve(known.get(src));
  if (!pending.has(src)) {
    pending.set(
      src,
      new Promise((resolve) => {
        const el = document.createElement(kind);
        el.preload = "metadata";
        el.muted = true;
        const done = (value?: number) => {
          el.removeAttribute("src");
          el.load();
          if (value) known.set(src, value);
          resolve(value);
        };
        el.addEventListener("loadedmetadata", () => done(Number.isFinite(el.duration) && el.duration > 0 ? el.duration : undefined), { once: true });
        el.addEventListener("error", () => done(), { once: true });
        el.src = src;
      }),
    );
  }
  return pending.get(src)!;
}

/**
 * The length badge on a post's picture. Uses the saved length when the post has
 * one; otherwise reads it from the video or song once the card scrolls into view.
 */
export default function Timecode({
  seconds,
  src,
  kind = "video",
  small = false,
}: {
  seconds?: number;
  src?: string;
  kind?: "video" | "audio";
  /** For little thumbnails, like the post page's "More on Nexus" list. */
  small?: boolean;
}) {
  const [read, setRead] = useState<number | undefined>(() => (src ? known.get(src) : undefined));
  const ref = useRef<HTMLSpanElement>(null);
  const length = seconds && seconds > 0 ? seconds : read;

  useEffect(() => {
    if (length || !src || !ref.current) return;
    const io = new IntersectionObserver(
      (entries) => {
        if (!entries.some((e) => e.isIntersecting)) return;
        io.disconnect();
        readLength(src, kind).then(setRead);
      },
      { rootMargin: "300px" },
    );
    io.observe(ref.current);
    return () => io.disconnect();
  }, [length, src, kind]);

  return (
    <span
      ref={ref}
      className={`absolute rounded-md bg-black/75 font-mono font-semibold text-white ${
        small ? "bottom-1 right-1 px-1 py-px text-[10px]" : "bottom-2 right-2 px-1.5 py-0.5 text-xs"
      } ${length ? "" : "invisible"}`}
    >
      {length ? timecode(length) : "0:00"}
    </span>
  );
}
