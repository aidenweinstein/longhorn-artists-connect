"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { LABEL } from "./Sidebar";

/**
 * Featured, at the very top of the sidebar above Home: the white Nexus graph icon, opening /featured, the page admins pick from Manage. Signed-in visitors only.
 */
export default function FeaturedLink() {
  const pathname = usePathname();
  const selected = pathname === "/featured" || pathname.startsWith("/featured/");
  return (
    <Link
      href="/featured"
      aria-label="Featured"
      aria-current={selected ? "page" : undefined}
      className={`group relative flex items-center gap-4 rounded-xl px-2.5 py-3 text-base font-medium transition-colors ${
        selected ? "bg-brand/15 text-brand" : "text-muted hover:bg-surface hover:text-foreground"
      }`}
    >
      <span
        aria-hidden
        className={`absolute -left-2 top-1/2 h-7 w-1 -translate-y-1/2 rounded-r-full bg-brand transition-opacity ${selected ? "opacity-100" : "opacity-0"}`}
      />
      {/* The plain graph icon, tinted like the other page icons (gray, or the school color when selected). */}
      <span
        aria-hidden
        className="h-7 w-7 shrink-0 bg-current"
        style={{ mask: "url(/brand/nexus-graph.png) center / contain no-repeat", WebkitMask: "url(/brand/nexus-graph.png) center / contain no-repeat" }}
      />
      <span className={LABEL}>Featured</span>
    </Link>
  );
}
