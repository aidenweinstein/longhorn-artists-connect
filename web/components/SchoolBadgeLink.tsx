"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import { usePathname } from "next/navigation";
import { schoolForPath, schoolForSlug } from "@/lib/schools";

/**
 * Your school at the top of the sidebar. Opens your school's own feed (only its posts;
 * Home has every school), and shows in your school's colors while you're on that feed
 * or one of its posts.
 */
export default function SchoolBadgeLink({ slug, label, className, children }: { slug: string; label: string; className: string; children: ReactNode }) {
  const selected = schoolForPath(usePathname())?.slug === slug;
  const school = schoolForSlug(slug);
  return (
    <Link
      href={`/school/${slug}`}
      aria-label={label}
      aria-current={selected ? "page" : undefined}
      style={selected && school ? { backgroundColor: school.color, color: school.accent } : undefined}
      className={className}
    >
      {children}
    </Link>
  );
}
