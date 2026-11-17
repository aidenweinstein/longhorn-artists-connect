import type { CSSProperties } from "react";

/**
 * A playback crop, the same as the app's `VideoCrop`: a rect of the video's upright
 * frame in 0…1 units (origin top-left). The file itself is never re-encoded, so films
 * keep their full original quality; the player just zooms to the rect.
 *
 * Stored on posts as an "x,y,w,h" string (filmVideoCrop, reelVideoCrop, designVideoCrop).
 */
export type VideoCrop = { x: number; y: number; w: number; h: number };

const clamp01 = (n: number) => Math.min(1, Math.max(0, n));

/** `null` when the rect is (essentially) the whole frame, or too small to be real. */
export function normalizeCrop(c: VideoCrop | null | undefined): VideoCrop | null {
  if (!c || ![c.x, c.y, c.w, c.h].every(Number.isFinite)) return null;
  const x = clamp01(c.x);
  const y = clamp01(c.y);
  const w = Math.min(1 - x, Math.max(0, c.w));
  const h = Math.min(1 - y, Math.max(0, c.h));
  if (w <= 0.01 || h <= 0.01) return null;
  if (x < 0.001 && y < 0.001 && w > 0.999 && h > 0.999) return null;
  return { x, y, w, h };
}

/** Parses a stored crop; `null` for an empty or invalid string. */
export function parseCrop(encoded: string | null | undefined): VideoCrop | null {
  const parts = (encoded ?? "").split(",").map((p) => Number(p.trim()));
  if (parts.length !== 4 || parts.some((n) => !Number.isFinite(n))) return null;
  return normalizeCrop({ x: parts[0], y: parts[1], w: parts[2], h: parts[3] });
}

/** "0.1000,0.0000,0.8000,1.0000" — four decimals, like the app. */
export function encodeCrop(c: VideoCrop | null | undefined): string {
  const n = normalizeCrop(c);
  return n ? [n.x, n.y, n.w, n.h].map((v) => v.toFixed(4)).join(",") : "";
}

/** Width ÷ height of a video with `natural` aspect once cropped. */
export function croppedAspect(natural: number, c: VideoCrop | null | undefined): number {
  return c ? (natural * c.w) / c.h : natural;
}

/**
 * Positions a <video> inside a box that already has the cropped shape (and
 * `overflow: hidden`) so only the crop shows.
 */
export function cropStyle(c: VideoCrop): CSSProperties {
  return {
    position: "absolute",
    width: `${100 / c.w}%`,
    height: `${100 / c.h}%`,
    left: `${(-c.x / c.w) * 100}%`,
    top: `${(-c.y / c.h) * 100}%`,
    maxWidth: "none",
  };
}

/** Same as cropStyle, written onto an element made outside React. */
export function applyCropStyle(el: HTMLElement, c: VideoCrop | null) {
  const s = c ? cropStyle(c) : null;
  el.style.position = s ? "absolute" : "";
  el.style.width = (s?.width as string) ?? "";
  el.style.height = (s?.height as string) ?? "";
  el.style.left = (s?.left as string) ?? "";
  el.style.top = (s?.top as string) ?? "";
  el.style.maxWidth = s ? "none" : "";
}

/**
 * Places content of `contentAspect` as large as fits, centered, inside a box of
 * `boxAspect` — like object-fit: contain, but for a wrapper element.
 */
export function containStyle(boxAspect: number, contentAspect: number): CSSProperties {
  if (!(boxAspect > 0) || !(contentAspect > 0)) return { position: "absolute", inset: 0 };
  if (contentAspect >= boxAspect) {
    const h = (boxAspect / contentAspect) * 100;
    return { position: "absolute", left: 0, width: "100%", top: `${(100 - h) / 2}%`, height: `${h}%` };
  }
  const w = (contentAspect / boxAspect) * 100;
  return { position: "absolute", top: 0, height: "100%", left: `${(100 - w) / 2}%`, width: `${w}%` };
}
