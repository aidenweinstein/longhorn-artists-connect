"use client";

import Link from "next/link";
import { useRouter, usePathname, useSearchParams } from "next/navigation";
import { useState, type FormEvent } from "react";
import { pageForPath } from "@/lib/pages";
import { schoolForPath } from "@/lib/schools";
import MaskImage from "./MaskImage";
import CategoryFilter from "./CategoryFilter";
import PageActions from "./PageActions";
import { SearchGlyph } from "./icons";

export default function TopBar() {
  const pathname = usePathname();
  const params = useSearchParams();
  const router = useRouter();
  const page = pageForPath(pathname);
  const school = schoolForPath(pathname);
  const barColor = school?.color ?? "var(--brand)";
  const [query, setQuery] = useState(params.get("q") ?? "");

  function onSearch(e: FormEvent) {
    e.preventDefault();
    const next = new URLSearchParams(params.toString());
    if (query.trim()) next.set("q", query.trim());
    else next.delete("q");
    const qs = next.toString();
    router.push(qs ? `${pathname}?${qs}` : pathname);
  }

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

      <form onSubmit={onSearch} role="search" className="flex flex-1 justify-end max-w-2xl sm:min-w-[120px] sm:justify-start">
        <input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search"
          className="hidden h-10 min-w-0 flex-1 rounded-l-full sm:block border border-white/25 bg-black/20 px-5 text-[15px] text-brand-foreground outline-none placeholder:text-brand-foreground/65 focus:border-brand-foreground/80"
        />
        <button
          type="submit"
          aria-label="Search"
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full border sm:w-16 sm:rounded-l-none sm:border-l-0 border-white/25 bg-white/15 text-brand-foreground hover:bg-white/25"
        >
          <SearchGlyph className="h-5 w-5" />
        </button>
      </form>

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
