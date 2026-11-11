"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { pageForPath } from "@/lib/pages";
import { schoolForPath } from "@/lib/schools";
import MaskImage from "./MaskImage";
import CategoryFilter from "./CategoryFilter";
import PageActions from "./PageActions";
import SearchBox from "./SearchBox";

export default function TopBar() {
  const pathname = usePathname();
  const page = pageForPath(pathname);
  const school = schoolForPath(pathname);
  const barColor = school?.color ?? "var(--brand)";

  return (
    <header
      style={{ backgroundColor: barColor }}
      // In normal flow, not position: fixed: Safari tints its toolbar from a fixed
      // element at the top of the window, whatever its color. See app/(app)/layout.tsx.
      className="relative z-30 flex h-16 shrink-0 items-center gap-3 px-3 sm:gap-4 sm:px-4 text-brand-foreground shadow-sm lg:gap-6 lg:px-6">
      {/* Page wordmark, swaps per page */}
      <Link
        href={school ? `/school/${school.slug}` : page.href}
        className="flex shrink-0 items-center text-brand-foreground"
        aria-label={page.label}
      >
        <MaskImage
          key={page.wordmark}
          src={page.wordmark}
          ratio={page.ratio}
          label={page.label}
          className="h-7"
        />
      </Link>

      <SearchBox />

      {page.actions && <PageActions kind={page.actions} />}

      {/* Projects / Events filter Discover's calendar; their own pages are already one kind. */}
      {page.filter && !/^\/discover\/(projects|events)(\/|$)/.test(pathname) && (
        <div className="shrink-0">
          <CategoryFilter set={page.filter} />
        </div>
      )}

    </header>
  );
}
