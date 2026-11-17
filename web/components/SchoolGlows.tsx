"use client";

import { useState } from "react";

/**
 * The colored glows behind the launch and sign-in screens. Before a school is picked
 * there is one per school, in that school's color, and they are the only color on the
 * screen. Once a school is picked (`only`), every glow is that school's color.
 *
 * Drawn as soft radial gradients, not as blurred circles: with
 * `filter: blur`, browsers left an unlit black box behind the buttons on top of a glow.
 */
const glow = (rgb: string, strength: number, at: string) =>
  `radial-gradient(circle 60vh at ${at}, rgba(${rgb}, ${strength}) 0%, rgba(${rgb}, ${strength * 0.55}) 40%, rgba(${rgb}, 0) 100%)`;

const TOP = "50% 6%";
const BOTTOM_LEFT = "13vh 94%";
const BOTTOM_RIGHT = "calc(100% - 13vh) 94%";

const ALL_SCHOOLS = [
  // UT Austin burnt orange, top center.
  glow("191, 87, 0", 0.3, TOP),
  // UC Berkeley blue, bottom left. Berkeley Blue is dark, so it needs more strength to read on black.
  glow("0, 50, 98", 0.8, BOTTOM_LEFT),
  // USC cardinal, bottom right.
  glow("153, 0, 0", 0.45, BOTTOM_RIGHT),
].join(", ");

/** "#bf5700" -> "191, 87, 0" */
const rgb = (hex: string) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16)).join(", ");

type Glow = { color: string; glow: number };

const schoolGlows = (school: Glow) =>
  [TOP, BOTTOM_LEFT, BOTTOM_RIGHT].map((at) => glow(rgb(school.color), at === TOP ? school.glow : school.glow * 0.6, at)).join(", ");

const LAYER = "pointer-events-none absolute inset-0 transition-opacity duration-700 ease-in-out";

export default function SchoolGlows({ only }: { only?: Glow }) {
  // Gradients can't animate from one to another, so the two looks are separate layers
  // that cross-fade. The school layer keeps the last school's colors while it fades out.
  const [last, setLast] = useState(only);
  if (only && only !== last) setLast(only);
  const school = only ?? last;
  return (
    <>
      <div aria-hidden className={LAYER} style={{ backgroundImage: ALL_SCHOOLS, opacity: only ? 0 : 1 }} />
      <div aria-hidden className={LAYER} style={{ backgroundImage: school ? schoolGlows(school) : undefined, opacity: only ? 1 : 0 }} />
    </>
  );
}
