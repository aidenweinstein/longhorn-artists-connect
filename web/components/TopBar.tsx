"use client";

import Link from "next/link";
import type { CSSProperties, ReactNode } from "react";
import { usePathname } from "next/navigation";
import { PAGES, pageForPath } from "@/lib/pages";
import { schoolForPath } from "@/lib/schools";
import MaskImage from "./MaskImage";
import CategoryFilter from "./CategoryFilter";
import PageActions from "./PageActions";
import SearchBox from "./SearchBox";
import SubNav, { isPortfolioSection } from "./SubNav";

/** Wordmark height in rem (h-7); its width is this times the page's ratio. */
const WORDMARK_REM = 1.75;
/** The widest page wordmark (Portfolio's). Every page keeps this much room for its own, so the search box starts in the same place everywhere. */
const WORDMARK_SLOT = `${(WORDMARK_REM * Math.max(...PAGES.map((p) => p.ratio))).toFixed(4)}rem`;

/**
 * Trial (2026-11-16): the corner always reads "Nexus" and links Home, instead of the
 * page's own wordmark (Discover, Share...). Set to false to get the per-page wordmarks back.
 */
const ALWAYS_NEXUS = true;
const NEXUS = PAGES[0];

/** `portfolioActions` is Portfolio's Edit Profile and Sign Out, rendered on the server (it needs the session). */
export default function TopBar({ portfolioActions }: { portfolioActions?: ReactNode }) {
  const pathname = usePathname();
  const page = pageForPath(pathname);
  const school = schoolForPath(pathname);
  const barColor = school?.color ?? "var(--brand)";
  const mark = ALWAYS_NEXUS ? NEXUS : page;

  return (
    <header
      // On another school's feed the bar takes that school's two colors: its main color
      // behind, its secondary color (USC and Berkeley gold) for the wordmark, text and buttons.
      style={{ backgroundColor: barColor, ...(school ? { "--brand": school.color, "--brand-foreground": school.accent } : {}) } as CSSProperties}
      // In normal flow, not position: fixed: Safari tints its toolbar from a fixed
      // element at the top of the window, whatever its color. See app/(app)/layout.tsx.
      className="relative z-30 flex h-16 shrink-0 items-center gap-3 px-3 sm:gap-4 sm:px-4 text-brand-foreground shadow-sm lg:gap-6 lg:px-6">
      {/* Page wordmark, swaps per page */}
      <Link
        href={school ? `/school/${school.slug}` : mark.href}
        // With one wordmark everywhere it needs no reserved room: the search box starts right after it.
        className={`flex shrink-0 items-center text-brand-foreground ${ALWAYS_NEXUS ? "" : "sm:w-(--wordmark-slot)"}`}
        style={{ "--wordmark-slot": WORDMARK_SLOT } as CSSProperties}
        aria-label={ALWAYS_NEXUS ? "Nexus" : page.label}
      >
        <MaskImage
          key={mark.wordmark}
          src={mark.wordmark}
          ratio={mark.ratio}
          label={ALWAYS_NEXUS ? "Nexus" : page.label}
          className="h-7"
        />
      </Link>

      <SearchBox />

      {/*
        The search box takes whatever room is left, so it is sized by what sits on
        either side of it. To keep it the same length, in the same place, on every
        page, the wordmark always gets the widest wordmark's room and this side always
        reserves the room the widest page's buttons need (an invisible copy of every
        page's buttons). The page's own buttons sit on top of that space. Phones keep
        the plain row.
      */}
      <div className="grid shrink-0 items-center overflow-x-clip max-sm:contents">
        {PAGES.map((p) => (
          <div
            key={p.href}
            aria-hidden
            inert
            className="invisible col-start-1 row-start-1 hidden w-max items-center gap-2 sm:flex"
          >
            <SubNav path={p.href} />
            {p.actions && <PageActions kind={p.actions} />}
            {p.href === "/portfolio" && portfolioActions}
            {p.filter && <CategoryFilter set={p.filter} />}
          </div>
        ))}
        <div className="col-start-1 row-start-1 flex w-max items-center gap-2 max-sm:contents">
          <SubNav />

          {page.actions && <PageActions kind={page.actions} />}

          {isPortfolioSection(pathname.replace(/\/$/, "") || "/") && portfolioActions}

          {page.filter && (
            <div className="shrink-0">
              <CategoryFilter set={page.filter} />
            </div>
          )}
        </div>
      </div>

    </header>
  );
}
