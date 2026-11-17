"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import MaskImage from "./MaskImage";
import { DISCOVER_TYPES } from "@/lib/discoverTypes";

/**
 * `also` are other addresses that keep this tab lit; `under` lights it for every page
 * beneath its address too. `icon` is a brand glyph shown before the label, `glyph` a drawn one.
 */
type Tab = { href: string; label: string; also?: string[]; under?: boolean; icon?: { src: string; ratio: number }; glyph?: ReactNode };

const typeIcon = (id: "project" | "event") => {
  const t = DISCOVER_TYPES.find((d) => d.id === id)!;
  return { src: t.icon, ratio: t.ratio };
};

const stroke = { width: 16, height: 16, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 1.8, strokeLinecap: "round", strokeLinejoin: "round" } as const;

const CALENDAR_GLYPH = (
  <svg {...stroke} aria-hidden>
    <rect x="3.5" y="5" width="17" height="15.5" rx="2.5" />
    <path d="M3.5 10h17M8 3v4M16 3v4" />
  </svg>
);

const BUILDING_GLYPH = (
  <svg {...stroke} aria-hidden>
    <path d="M4 20.5V5.5a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v15M14 10h4a2 2 0 0 1 2 2v8.5M2.5 20.5h19M8 8h2M8 12h2M8 16h2" />
  </svg>
);

// Discover's bar: one Projects / Events toggle (Discover opens on Projects), then
// Calendar and Groups (Organizations and Classes) as buttons of their own. Every Discover button has an
// icon, so on a narrow window (under 1280px) the labels drop away and only the icons show.
const DISCOVER_GROUPS: Tab[][] = [
  [
    { href: "/discover/projects", label: "Projects", icon: typeIcon("project"), also: ["/discover"] },
    { href: "/discover/events", label: "Events", icon: typeIcon("event") },
  ],
  [{ href: "/discover/calendar", label: "Calendar", glyph: CALENDAR_GLYPH }],
  [{ href: "/discover/organizations", label: "Groups", glyph: BUILDING_GLYPH, under: true, also: ["/discover/classes"] }],
];

// Network's bar: Messages, Connections and Directory as buttons of their own, then
// the Actors / Filmmakers / Musicians people pages joined in one toggle.
const NETWORK_GROUPS: Tab[][] = [
  [{ href: "/network", label: "Messages" }],
  [{ href: "/network/connections", label: "Connections" }],
  [{ href: "/people/directory", label: "Directory" }],
  [
    { href: "/people/actors", label: "Actors" },
    { href: "/people/filmmakers", label: "Filmmakers" },
    { href: "/people/musicians", label: "Musicians" },
  ],
];

const PORTFOLIO_TABS: Tab[] = [
  // Edit Profile and Sign Out are buttons of their own on the bar (PortfolioBarActions).
  { href: "/portfolio", label: "Portfolio", also: ["/portfolio/edit", "/portfolio/style"] },
  { href: "/liked", label: "Liked" },
  { href: "/playlists", label: "Saved" },
];

const isOn = (t: Tab, pathname: string) =>
  pathname === t.href || !!t.also?.includes(pathname) || (!!t.under && pathname.startsWith(`${t.href}/`));

/** Your own Portfolio pages (Portfolio, Liked, Saved, Edit profile), which carry Portfolio's tabs and buttons. */
export const isPortfolioSection = (pathname: string) => PORTFOLIO_TABS.some((t) => t.href === pathname || !!t.also?.includes(pathname));

/** The tab groups for the page the visitor is on, or none (Home, Share and the rest have no tabs). */
function groupsFor(pathname: string): Tab[][] | null {
  if (DISCOVER_GROUPS.flat().some((t) => isOn(t, pathname))) return DISCOVER_GROUPS;
  if (pathname === "/network" || pathname === "/network/connections" || (pathname.startsWith("/people/") && !pathname.endsWith("/apply") && !pathname.endsWith("/sample"))) {
    return NETWORK_GROUPS;
  }
  if (isPortfolioSection(pathname)) return [PORTFOLIO_TABS];
  return null;
}

/**
 * Each main page's sections on the page bar, beside the search box: Discover's views,
 * Network's lists, Portfolio's pages. Each group is one segmented control; a group of
 * one reads as a button on its own. Styled like the category filter that shares the bar.
 */
export default function SubNav({ path }: { path?: string }) {
  // `path` shows another page's tabs: TopBar uses it to measure every page's bar.
  const here = usePathname();
  const pathname = (path ?? here).replace(/\/$/, "") || "/";
  const groups = groupsFor(pathname);
  if (!groups) return null;
  return (
    <nav aria-label="Section" className="flex min-w-0 shrink-0 items-center gap-2 overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
      {groups.map((tabs) => (
        <div key={tabs[0].href} className="flex w-max items-center gap-0.5 rounded-full bg-black/20 p-1">
          {tabs.map((t) => {
            const on = isOn(t, pathname);
            return (
              <Link
                key={t.href}
                href={t.href}
                aria-current={on ? "page" : undefined}
                aria-label={t.label}
                title={t.label}
                className={`flex items-center gap-2 whitespace-nowrap rounded-full px-3 py-1.5 text-sm font-medium transition-colors ${
                  on ? "bg-brand-foreground text-brand shadow-sm" : "text-brand-foreground/85 hover:bg-white/15 hover:text-brand-foreground"
                }`}
              >
                {t.icon && <MaskImage src={t.icon.src} ratio={t.icon.ratio} className="h-4" />}
                {t.glyph}
                {/* Tabs with an icon keep only the icon when the window is narrow: the same
                    width Home's category filter drops its labels, so the search box
                    beside them stays the size it is on Home (see TopBar). */}
                <span className={t.icon || t.glyph ? "hidden xl:inline" : undefined}>{t.label}</span>
              </Link>
            );
          })}
        </div>
      ))}
    </nav>
  );
}
