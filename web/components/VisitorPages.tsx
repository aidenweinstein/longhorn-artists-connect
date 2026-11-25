import { currentSession } from "@/lib/account";
import { schoolForID } from "@/lib/schools";
import FeaturedLink from "./FeaturedLink";
import { SidebarPages } from "./Sidebar";

/** Guests (browsing with a guest pass, not signed in) only get Home; school pages are listed below it. */
export const GUEST_PAGES = ["/"] as const;

/** Holds the spot while the session loads: Home, which everyone gets. */
export function VisitorPagesPlaceholder() {
  return <SidebarPages only={GUEST_PAGES} pathname={null} />;
}

/** The sidebar's main pages: all five when signed in, only Home for a guest (see guestCanSee in lib/session.ts). */
export default async function VisitorPages() {
  const session = await currentSession();
  // Signed in, Home is your school's feed, so it wears your school's logo.
  return session ? <SidebarPages homeLogo={schoolForID(session.schoolID).logo} /> : <SidebarPages only={GUEST_PAGES} />;
}

/** Featured (the Nexus graph icon) above Home, for signed-in visitors; guests only get Home. */
export async function VisitorFeatured() {
  return (await currentSession()) ? <FeaturedLink /> : null;
}
