import Link from "next/link";
import { currentSession } from "@/lib/account";
import { isAdmin } from "@/lib/featured";
import { RocketGlyph } from "./icons";

/**
 * Sidebar button for the Mock launch walkthrough (`/welcome/mock`): the launch page and
 * every sign-up screen, with no email sent and no account created. Shown in development,
 * and on the live site only to admins (ADMIN_EMAILS).
 */
export default async function MockLaunchLink() {
  if (process.env.NODE_ENV !== "development" && !isAdmin(await currentSession())) return null;
  return (
    <Link
      href="/welcome/mock"
      aria-label="Mock launch"
      className="flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium text-muted transition-colors hover:bg-surface hover:text-foreground"
    >
      <RocketGlyph className="h-6 w-6 shrink-0" />
      <span className="whitespace-nowrap opacity-0 transition-opacity duration-150 group-data-[open=true]/nav:opacity-100">Mock launch</span>
    </Link>
  );
}
