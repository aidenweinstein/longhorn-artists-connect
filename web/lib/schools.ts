// Schools other than the viewer's own, listed under "Other Schools" in the sidebar.
// Each one gets its own Home feed at /school/<slug>, tinted in its school colors.
export const OTHER_SCHOOLS = [
  { slug: "berkeley", name: "UC Berkeley", short: "Cal", color: "#003262", accent: "#FDB515" },
  { slug: "usc", name: "USC", short: "SC", color: "#990000", accent: "#FFCC00" },
] as const;

export type School = (typeof OTHER_SCHOOLS)[number];

export function schoolForSlug(slug: string): School | undefined {
  return OTHER_SCHOOLS.find((s) => s.slug === slug);
}

/** The other school whose feed this path shows, if any. */
export function schoolForPath(pathname: string): School | undefined {
  const m = pathname.match(/^\/school\/([^/]+)/);
  return m ? schoolForSlug(m[1]) : undefined;
}
