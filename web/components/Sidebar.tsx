"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { PAGES } from "@/lib/pages";
import { OTHER_SCHOOLS, schoolForPath } from "@/lib/schools";
import { Suspense, useState, type ReactNode } from "react";
import { PageGlyph, RocketGlyph } from "./icons";

/** Paths that belong to a main page without starting with its address. */
const ALSO_UNDER: Record<string, string[]> = {
  "/network": ["/people"],
  "/portfolio": ["/liked", "/playlists"],
};

// Labels fade in only while the bar is open (data-open on the <nav>).
const LABEL = "whitespace-nowrap leading-tight opacity-0 transition-opacity duration-150 group-data-[open=true]/nav:opacity-100";

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
  const underPage = (href: string) => [href, ...(ALSO_UNDER[href] ?? [])].some((p) => pathname === p || pathname.startsWith(`${p}/`));
  // A post counts as Home; pages outside the sidebar, like Manage, light nothing up.
  const onPage = (href: string) => (href === "/" ? pathname === "/" || pathname.startsWith("/post") : underPage(href));

  // The bar opens while the pointer is over it, and closes the moment something is
  // picked, staying closed until the pointer leaves and comes back.
  const [hovering, setHovering] = useState(false);
  const [picked, setPicked] = useState(false);
  const open = hovering && !picked;

  return (
    // The slot keeps the page's layout at icon width; the bar grows over the page when open.
    <div className="relative z-20 h-full w-[68px] shrink-0">
      <nav
        aria-label="Main"
        data-open={open}
        onMouseEnter={() => setHovering(true)}
        onMouseLeave={() => {
          setHovering(false);
          setPicked(false);
        }}
        onClickCapture={() => setPicked(true)}
        // Keyboard users: tabbing into the bar opens it.
        onFocus={(e) => {
          if (e.target.matches(":focus-visible")) setHovering(true);
        }}
        onBlur={(e) => {
          if (!e.currentTarget.contains(e.relatedTarget as Node | null)) {
            setHovering(false);
            setPicked(false);
          }
        }}
        className="group/nav absolute inset-y-0 left-0 flex w-[68px] flex-col gap-1 overflow-y-auto overflow-x-hidden border-r border-border bg-background px-2 py-3 transition-[width,box-shadow] duration-200 [scrollbar-width:none] data-[open=true]:w-56 data-[open=true]:shadow-xl [&::-webkit-scrollbar]:hidden"
      >
        {PAGES.map((page) => {
          const selected = known && !otherSchool && onPage(page.href);
          return (
            <Link
              key={page.href}
              href={page.href}
              aria-label={page.label}
              aria-current={selected ? "page" : undefined}
              className={`group relative flex items-center gap-4 rounded-xl px-2.5 py-3 text-base font-medium transition-colors ${
                selected ? "bg-brand/15 text-brand" : "text-muted hover:bg-surface hover:text-foreground"
              }`}
            >
              {/* Toggle indicator on the selected page */}
              <span
                aria-hidden
                className={`absolute -left-2 top-1/2 h-7 w-1 -translate-y-1/2 rounded-r-full bg-brand transition-opacity ${
                  selected ? "opacity-100" : "opacity-0"
                }`}
              />
              <PageGlyph icon={page.icon} className="h-7 w-7 shrink-0" />
              <span className={LABEL}>{page.label}</span>
            </Link>
          );
        })}

        <div className="mt-3 border-t border-border pt-3">
          <p className="mb-1 h-4 whitespace-nowrap px-3 text-[11px] font-semibold uppercase tracking-wider text-muted opacity-0 transition-opacity group-data-[open=true]/nav:opacity-100">
            Other Schools
          </p>
          <div className="flex flex-col gap-0.5">
            {OTHER_SCHOOLS.map((school) => {
              const selected = otherSchool?.slug === school.slug;
              return (
                <Link
                  key={school.slug}
                  href={`/school/${school.slug}`}
                  aria-label={school.name}
                  aria-current={selected ? "page" : undefined}
                  className={`flex items-center gap-3 rounded-lg px-3 py-2 text-[13px] font-medium transition-colors ${
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
                  <span className={LABEL}>{school.name}</span>
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
              className="flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium text-muted transition-colors hover:bg-surface hover:text-foreground"
            >
              <RocketGlyph className="h-6 w-6 shrink-0" />
              <span className={LABEL}>Launch page</span>
            </Link>
          )}

          {account}
        </div>
      </nav>
    </div>
  );
}
