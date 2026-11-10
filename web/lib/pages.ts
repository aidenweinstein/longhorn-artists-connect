// The five main pages, in sidebar order. Wordmarks come from the iOS app's
// asset catalog (converted to white-on-transparent so they can be tinted).
export const PAGES = [
  { href: "/", label: "Home", icon: "home", wordmark: "/brand/nexus-wordmark.png", ratio: 636 / 120, filter: "category", actions: null },
  { href: "/discover", label: "Discover", icon: "discover", wordmark: "/brand/discover-wordmark.png", ratio: 918 / 120, filter: null, actions: null },
  { href: "/share", label: "Share", icon: "share", wordmark: "/brand/share-wordmark.png", ratio: 633 / 120, filter: null, actions: "share" },
  { href: "/network", label: "Network", icon: "network", wordmark: "/brand/network-wordmark.png", ratio: 963 / 120, filter: null, actions: null },
  { href: "/portfolio", label: "Portfolio", icon: "portfolio", wordmark: "/brand/portfolio-wordmark.png", ratio: 1066 / 120, filter: null, actions: null },
] as const;

export type PageIcon = (typeof PAGES)[number]["icon"];

// Pages that live outside a main page's address but belong to it.
const BELONGS_TO: Record<string, string> = { "/people": "/network", "/liked": "/portfolio", "/playlists": "/portfolio" };

export function pageForPath(pathname: string) {
  const owner = Object.entries(BELONGS_TO).find(([prefix]) => pathname === prefix || pathname.startsWith(`${prefix}/`))?.[1];
  const path = owner ?? pathname;
  return PAGES.find((p) => (p.href === "/" ? path === "/" : path.startsWith(p.href))) ?? PAGES[0];
}
