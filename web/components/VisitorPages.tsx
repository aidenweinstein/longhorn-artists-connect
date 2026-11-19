import { currentSession } from "@/lib/account";
import { SidebarPages } from "./Sidebar";

/** Guests (browsing with a guest pass, not signed in) only get Home; school pages are listed below it. */
export const GUEST_PAGES = ["/"] as const;

/** Holds the spot while the session loads: Home, which everyone gets. */
export function VisitorPagesPlaceholder() {
  return <SidebarPages only={GUEST_PAGES} pathname={null} />;
}

/** The sidebar's main pages: all five when signed in, only Home for a guest (see guestCanSee in lib/session.ts). */
export default async function VisitorPages() {
  const signedIn = (await currentSession()) !== null;
  return <SidebarPages only={signedIn ? undefined : GUEST_PAGES} />;
}
