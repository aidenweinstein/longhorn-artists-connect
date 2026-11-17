"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { SCHOOLS, schoolForPath } from "@/lib/schools";
import { LABEL } from "./Sidebar";

/**
 * The sidebar's "Other Schools": every school but yours (`mine`), which sits on its own
 * at the top of the sidebar. A Berkeley student sees UT Austin here, not Berkeley.
 */
export default function OtherSchools({ mine }: { mine: string }) {
  const viewing = schoolForPath(usePathname());
  return (
    <div className="flex flex-col gap-0.5">
      {SCHOOLS.filter((s) => s.slug !== mine).map((school) => {
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
