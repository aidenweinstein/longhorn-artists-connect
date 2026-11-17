"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

/**
 * Share's Drafts button on the page bar. Opens the Drafts page and stays lit while it's
 * open, like the bar's tabs. Same capsule as the bar's other buttons (PageActions).
 */
export default function DraftsButton() {
  const on = usePathname().replace(/\/$/, "") === "/share/drafts";
  return (
    <div className="flex w-max items-center rounded-full bg-black/20 p-1">
      <Link
        href="/share/drafts"
        aria-current={on ? "page" : undefined}
        title="Drafts"
        className={`flex items-center gap-2 whitespace-nowrap rounded-full px-3 py-1.5 text-sm font-medium transition-colors ${
          on ? "bg-brand-foreground text-brand shadow-sm" : "text-brand-foreground/85 hover:bg-white/15 hover:text-brand-foreground"
        }`}
      >
        Drafts
      </Link>
    </div>
  );
}
