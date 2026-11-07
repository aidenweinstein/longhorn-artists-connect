"use client";

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import type { ReactNode } from "react";
import { CATEGORIES } from "@/lib/categories";
import { DISCOVER_TYPES } from "@/lib/discoverTypes";
import MaskImage from "./MaskImage";
import { GridGlyph } from "./icons";

type Variant = "bar" | "page";

const STYLES: Record<Variant, { group: string; on: string; off: string; label: string }> = {
  // On the school-colored top bar; labels collapse to icons when space is tight.
  bar: {
    group: "bg-black/20",
    on: "bg-brand-foreground text-brand shadow-sm",
    off: "text-brand-foreground/85 hover:bg-white/15 hover:text-brand-foreground",
    label: "hidden xl:inline",
  },
  page: {
    group: "bg-surface",
    on: "bg-brand text-white shadow-sm",
    off: "text-muted hover:bg-foreground/5 hover:text-foreground",
    label: "inline",
  },
};

const SETS = {
  category: { param: "category", options: CATEGORIES },
  discover: { param: "type", options: DISCOVER_TYPES },
} as const;

/** Segmented toggle bar. "All" is selected by default; clicking a selected option returns to All. */
export default function CategoryFilter({ set = "category", variant = "bar" }: { set?: keyof typeof SETS; variant?: Variant }) {
  const pathname = usePathname();
  const params = useSearchParams();
  const { param, options } = SETS[set];
  const current = pathname.startsWith("/post") ? null : params.get(param);
  const s = STYLES[variant];

  function hrefFor(id: string | null) {
    const next = new URLSearchParams(params.toString());
    if (id === null || current === id) next.delete(param);
    else next.set(param, id);
    const qs = next.toString();
    const base = pathname.startsWith("/post") ? "/" : pathname;
    return qs ? `${base}?${qs}` : base;
  }

  function item(key: string, id: string | null, label: string, icon: ReactNode) {
    const selected = id === null ? !current : current === id;
    return (
      <Link
        key={key}
        href={hrefFor(id)}
        scroll={false}
        aria-pressed={selected}
        aria-label={label}
        title={label}
        className={`flex items-center gap-2 rounded-full px-3 py-1.5 text-sm font-medium transition-colors ${
          selected ? s.on : s.off
        }`}
      >
        {icon}
        <span className={s.label}>{label}</span>
      </Link>
    );
  }

  return (
    <div
      role="group"
      aria-label="Filter by category"
      className={`flex w-max shrink-0 items-center gap-0.5 rounded-full p-1 ${s.group}`}
    >
      {item("all", null, "All", <GridGlyph className="h-4 w-4" />)}
      {options.map((cat) =>
        item(cat.id, cat.id, cat.label, <MaskImage src={cat.icon} ratio={cat.ratio} className="h-4" />),
      )}
    </div>
  );
}
