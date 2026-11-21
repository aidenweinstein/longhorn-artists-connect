"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { SCHOOLS, schoolForPath } from "@/lib/schools";
import { LABEL } from "./Sidebar";

/**
 * The sidebar's other schools: every school but yours (`mine`), which sits on its own
 * at the top of the sidebar. A guest has no school (`mine` null) and sees them all. A Berkeley student sees UT Austin here, not Berkeley.
 * All of them are listed; there's no "More" dropdown. `order` (school slugs, most posts
 * first) sets the order; without it they're in the usual order.
 */
export default function OtherSchools({ mine, heading, order }: { mine: string | null; heading?: string; order?: string[] }) {
  const viewing = schoolForPath(usePathname());
  const rank = (slug: string) => {
    const i = order?.indexOf(slug) ?? -1;
    return i < 0 ? Number.MAX_SAFE_INTEGER : i;
  };
  const schools = SCHOOLS.filter((s) => s.slug !== mine).sort((a, b) => rank(a.slug) - rank(b.slug));
  if (!schools.length) return null;
  return (
    <div className="flex flex-col gap-0.5">
      {heading && (
        <p className="mb-1 h-4 whitespace-nowrap px-3 text-[11px] font-semibold uppercase tracking-wider text-muted opacity-0 transition-opacity group-data-[open=true]/nav:opacity-100">
          {heading}
        </p>
      )}
      {schools.map((school) => {
        const selected = viewing?.slug === school.slug;
        return (
          <Link
            key={school.slug}
            href={`/school/${school.slug}`}
            aria-label={school.name}
            aria-current={selected ? "page" : undefined}
            // The school you're viewing is shown in its own colors: main color behind, secondary (gold) text.
            style={selected ? { backgroundColor: school.color, color: school.accent } : undefined}
            className={`flex items-center gap-3 rounded-lg px-3 py-2 text-[13px] font-medium transition-colors ${
              selected ? "" : "text-muted hover:bg-surface hover:text-foreground"
            }`}
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={school.logo} alt="" className="h-6 w-6 shrink-0 rounded-full object-cover" />
            <span className={LABEL}>{school.name}</span>
          </Link>
        );
      })}
    </div>
  );
}
