"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import MaskImage from "./MaskImage";
import { DISCOVER_TYPES } from "@/lib/discoverTypes";

/** `also` are other addresses that keep this tab lit; `icon` is a brand glyph shown before the label. */
type Tab = { href: string; label: string; also?: string[]; icon?: { src: string; ratio: number } };

const typeIcon = (id: "project" | "event") => {
  const t = DISCOVER_TYPES.find((d) => d.id === id)!;
  return { src: t.icon, ratio: t.ratio };
};

const DISCOVER_TABS: Tab[] = [
  { href: "/discover", label: "Calendar" },
  { href: "/discover/projects", label: "Projects", icon: typeIcon("project") },
  { href: "/discover/events", label: "Events", icon: typeIcon("event") },
  { href: "/discover/organizations", label: "Organizations" },
];

const NETWORK_TABS: Tab[] = [
  { href: "/network", label: "Messages" },
  { href: "/people/directory", label: "Directory" },
  { href: "/people/actors", label: "Actors" },
  { href: "/people/filmmakers", label: "Filmmakers" },
  { href: "/people/musicians", label: "Musicians" },
];

const PORTFOLIO_TABS: Tab[] = [
  // Edit profile and Profile style are buttons on the portfolio page itself.
  { href: "/portfolio", label: "Portfolio", also: ["/portfolio/edit", "/portfolio/style"] },
  { href: "/liked", label: "Liked" },
  { href: "/playlists", label: "Saved" },
];

/** The tabs for the page the visitor is on, or none (Home, Share and the rest have no tabs). */
function tabsFor(pathname: string): Tab[] | null {
  if (DISCOVER_TABS.some((t) => t.href === pathname)) return DISCOVER_TABS;
  if (pathname === "/network" || (pathname.startsWith("/people/") && !pathname.endsWith("/apply") && !pathname.endsWith("/sample"))) {
    return NETWORK_TABS;
  }
  if (PORTFOLIO_TABS.some((t) => t.href === pathname || t.also?.includes(pathname))) return PORTFOLIO_TABS;
  return null;
}

/**
 * Each main page's sections as one segmented control on the page bar, beside the search
 * box: Discover's views, Network's lists, Portfolio's pages. Styled like the category
 * filter that shares the bar.
 */
export default function SubNav() {
  const pathname = usePathname().replace(/\/$/, "") || "/";
  const tabs = tabsFor(pathname);
  if (!tabs) return null;
  return (
    <nav aria-label="Section" className="flex min-w-0 shrink-0 items-center overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
      <div className="flex w-max items-center gap-0.5 rounded-full bg-black/20 p-1">
        {tabs.map((t) => {
          const on = pathname === t.href || !!t.also?.includes(pathname);
          return (
            <Link
              key={t.href}
              href={t.href}
              aria-current={on ? "page" : undefined}
              className={`flex items-center gap-2 whitespace-nowrap rounded-full px-3 py-1.5 text-sm font-medium transition-colors ${
                on ? "bg-brand-foreground text-brand shadow-sm" : "text-brand-foreground/85 hover:bg-white/15 hover:text-brand-foreground"
              }`}
            >
              {t.icon && <MaskImage src={t.icon.src} ratio={t.icon.ratio} className="h-4" />}
              {t.label}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
