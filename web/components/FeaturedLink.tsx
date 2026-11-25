"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { LABEL } from "./Sidebar";

/**
 * Featured, at the very top of the sidebar above Home: the Nexus graph icon (the app's
 * icon), opening /featured, the page admins pick from Manage. Signed-in visitors only.
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
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src="/brand/nexus-icon.png" alt="" className="h-7 w-7 shrink-0 rounded-full object-cover" />
      <span className={LABEL}>Featured</span>
    </Link>
  );
}
