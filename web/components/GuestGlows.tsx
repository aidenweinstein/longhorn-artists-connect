"use client";

import { usePathname } from "next/navigation";
import { schoolForPath } from "@/lib/schools";
import SchoolGlows from "./SchoolGlows";

/**
 * The launch page's three school glows, fixed behind a guest's Home feed and the posts
 * opened from it. Not on a school's own page, which is in that school's colors. Sits
 * below everything in the page (-z-10): the top bar and sidebar are solid, so the glows
 * show around the feed.
 */
export default function GuestGlows() {
  if (schoolForPath(usePathname())) return null;
  return (
    <div aria-hidden className="pointer-events-none fixed inset-0 -z-10">
      <SchoolGlows />
    </div>
  );
}
