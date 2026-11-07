"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { PAGES } from "@/lib/pages";
import { OTHER_SCHOOLS, schoolForPath } from "@/lib/schools";
import { Suspense, type ReactNode } from "react";
import { EyeGlyph, HeartGlyph, PageGlyph, PlaylistGlyph, RocketGlyph, StarGlyph } from "./icons";
import MaskImage from "./MaskImage";
import { getCategory } from "@/lib/categories";
import { DISCOVER_TYPES } from "@/lib/discoverTypes";

type Child = { href: string; label: string; icon: ReactNode };

const smallIcon = (src: string, ratio: number) => (
  <span className="flex h-5 w-5 shrink-0 items-center justify-center">
    <MaskImage src={src} ratio={ratio} className="h-4" />
  </span>
);
const categoryIcon = (id: string) => {
  const cat = getCategory(id)!;
  return smallIcon(cat.icon, cat.ratio);
};
const discoverIcon = (id: string) => {
  const t = DISCOVER_TYPES.find((d) => d.id === id)!;
  return smallIcon(t.icon, t.ratio);
};

/**
 * What sits under each main page in the sidebar. A main page is selected only when
 * none of its own sub-pages is.
 */
const CHILDREN: Record<string, Child[]> = {
  "/": [
    { href: "/featured", label: "Featured", icon: <StarGlyph className="h-5 w-5" /> },
    { href: "/liked", label: "Liked", icon: <HeartGlyph className="h-5 w-5" /> },
    { href: "/playlists", label: "Playlists", icon: <PlaylistGlyph className="h-5 w-5" /> },
  ],
  "/discover": [
    { href: "/discover/projects", label: "Projects", icon: discoverIcon("project") },
    { href: "/discover/events", label: "Events", icon: discoverIcon("event") },
  ],
  "/network": [
    { href: "/people/filmmakers", label: "Filmmakers", icon: categoryIcon("film") },
    { href: "/people/actors", label: "Actors", icon: categoryIcon("performance") },
    { href: "/people/musicians", label: "Musicians", icon: categoryIcon("music") },
  ],
  "/portfolio": [
    { href: "/portfolio/style", label: "Profile style", icon: <StarGlyph className="h-5 w-5" /> },
    { href: "/portfolio/edit", label: "Edit profile", icon: <PageGlyph icon="portfolio" className="h-5 w-5" /> },
  ],
};

/**
 * `account` is the server-rendered Sign in button, or "Signed in as" once signed in.
 *
 * The current address is only known at request time, so reading it here would block
 * prerendering on dynamic routes. The sidebar renders right away with nothing
 * highlighted, and the highlight streams in a moment later.
 */
export default function Sidebar({ account }: { account: ReactNode }) {
  return (
    <Suspense fallback={<SidebarView account={account} pathname={null} />}>
      <CurrentSidebar account={account} />
    </Suspense>
  );
}

function CurrentSidebar({ account }: { account: ReactNode }) {
  return <SidebarView account={account} pathname={usePathname()} />;
}

function SidebarView({ account, pathname: current }: { account: ReactNode; pathname: string | null }) {
  // `null` while the address is still streaming in: nothing is highlighted yet.
  const known = current !== null;
  const pathname = current ?? "";
  const otherSchool = schoolForPath(pathname);
  const childActive = (href: string) => pathname === href || pathname.startsWith(`${href}/`);
  // The sub-page the visitor is on, if any (it wins over its parent's highlight).
  const activeChild = Object.values(CHILDREN).flat().find((c) => childActive(c.href));
  // Only the page the address is actually under (a post counts as Home); pages outside
  // the sidebar, like Manage, light nothing up.
  const onPage = (href: string) => (href === "/" ? pathname === "/" || pathname.startsWith("/post") : childActive(href));

  return (
    <nav
      aria-label="Main"
      className="relative z-20 flex h-full w-[84px] shrink-0 flex-col gap-1 overflow-y-auto overflow-x-hidden border-r border-border bg-background px-1.5 py-3 [scrollbar-width:none] lg:w-44 lg:px-2 [&::-webkit-scrollbar]:hidden"
    >
      {/* Now: your current sets, shoots and auditions */}
      <Link
        href="/now"
        aria-current={known && pathname.startsWith("/now") ? "page" : undefined}
        className={`group relative flex flex-col items-center gap-1 rounded-xl px-2 py-2.5 text-[11px] font-medium transition-colors lg:flex-row lg:gap-3 lg:px-3 lg:text-sm ${
          known && pathname.startsWith("/now") ? "bg-brand/15 text-brand" : "text-muted hover:bg-surface hover:text-foreground"
        }`}
      >
        <span
          aria-hidden
          className={`absolute left-0 top-1/2 h-6 w-1 -translate-y-1/2 rounded-r-full bg-brand transition-opacity ${
            known && pathname.startsWith("/now") ? "opacity-100" : "opacity-0"
          }`}
        />
        <EyeGlyph className="h-6 w-6" />
        <span className="whitespace-nowrap text-center leading-tight lg:text-left">Now</span>
      </Link>

      {PAGES.map((page) => {
        const children = CHILDREN[page.href] ?? [];
        const selected =
          known && !otherSchool && !activeChild && onPage(page.href);
        return (
          <div key={page.href} className="mt-2 border-t border-border pt-2">
            <Link
              href={page.href}
              aria-current={selected ? "page" : undefined}
              className={`group relative flex flex-col items-center gap-1 rounded-xl px-2 py-2.5 text-[11px] font-medium transition-colors lg:flex-row lg:gap-3 lg:px-3 lg:text-sm ${
                selected ? "bg-brand/15 text-brand" : "text-muted hover:bg-surface hover:text-foreground"
              }`}
            >
              {/* Toggle indicator on the selected page */}
              <span
                aria-hidden
                className={`absolute left-0 top-1/2 h-6 w-1 -translate-y-1/2 rounded-r-full bg-brand transition-opacity ${
                  selected ? "opacity-100" : "opacity-0"
                }`}
              />
              <PageGlyph icon={page.icon} className="h-6 w-6" />
              <span className="whitespace-nowrap text-center leading-tight lg:text-left">{page.label}</span>
            </Link>
            {children.length > 0 && (
              <div className="mt-0.5 flex flex-col gap-0.5 lg:ml-3 lg:border-l lg:border-border lg:pl-1.5">
                {children.map((item) => {
                  const on = known && activeChild?.href === item.href;
                  return (
                    <Link
                      key={item.href}
                      href={item.href}
                      aria-current={on ? "page" : undefined}
                      className={`flex flex-col items-center gap-1 rounded-lg px-2 py-1.5 text-[10px] font-medium transition-colors lg:flex-row lg:gap-2.5 lg:px-2.5 lg:text-[13px] ${
                        on ? "bg-brand/15 text-brand" : "text-muted hover:bg-surface hover:text-foreground"
                      }`}
                    >
                      {item.icon}
                      <span className="max-w-full break-words text-center leading-tight lg:text-left">{item.label}</span>
                    </Link>
                  );
                })}
              </div>
            )}
          </div>
        );
      })}

      <div className="mt-3 border-t border-border pt-3">
        <p className="mb-1 hidden px-3 text-[11px] font-semibold uppercase tracking-wider text-muted lg:block">Other Schools</p>
        <div className="flex flex-col gap-0.5">
          {OTHER_SCHOOLS.map((school) => {
            const selected = otherSchool?.slug === school.slug;
            return (
              <Link
                key={school.slug}
                href={`/school/${school.slug}`}
                aria-current={selected ? "page" : undefined}
                className={`flex flex-col items-center gap-1 rounded-lg px-2 py-2 text-[10px] font-medium transition-colors lg:flex-row lg:gap-3 lg:px-3 lg:text-[13px] ${
                  selected ? "bg-brand/15 text-brand" : "text-muted hover:bg-surface hover:text-foreground"
                }`}
              >
                <span
                  aria-hidden
                  style={{ backgroundColor: school.color, color: school.accent }}
                  className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[8px] font-bold"
                >
                  {school.short}
                </span>
                <span className="max-w-full break-words text-center leading-tight lg:text-left">{school.name}</span>
              </Link>
            );
          })}
        </div>
      </div>

      <div className="mt-auto flex flex-col gap-1">
      {/* Development shortcut to the launch (welcome) page; not shown on the live site. */}
      {process.env.NODE_ENV === "development" && (
        <Link
          href="/welcome"
          className="flex flex-col items-center gap-1 rounded-xl px-2 py-2.5 text-[11px] font-medium text-muted transition-colors hover:bg-surface hover:text-foreground lg:flex-row lg:gap-3 lg:px-3 lg:text-sm"
        >
          <RocketGlyph className="h-6 w-6" />
          <span className="max-w-full break-words text-center leading-tight lg:text-left">Launch page</span>
        </Link>
      )}

      {account}
      </div>
    </nav>
  );
}
