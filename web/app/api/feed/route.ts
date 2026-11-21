import { NextResponse, type NextRequest } from "next/server";
import { GUEST_COOKIE, SESSION_COOKIE, decodeSession, hasGuestPass } from "@/lib/session";
import { feedPage } from "@/lib/feedPage";
import { schoolForID } from "@/lib/schools";

// GET /api/feed?seed=...&offset=24&category=film&q=...
// The next cards of the Home feed, continuing the shuffle the page started with.
// API routes skip the sign-in proxy, so this checks the session itself: the live
// site never shows students' work to anyone who hasn't signed in.
export async function GET(request: NextRequest) {
  const session = decodeSession(request.cookies.get(SESSION_COOKIE)?.value);
  const signedIn = session !== null;
  const guest = hasGuestPass(request.cookies.get(GUEST_COOKIE)?.value);
  if (!signedIn && !guest) return NextResponse.json({ cards: [], hasMore: false }, { status: 401 });

  const q = request.nextUrl.searchParams;
  const seed = Number(q.get("seed")) || 0;
  const offset = Math.max(0, Math.floor(Number(q.get("offset")) || 0));
  // The same feed as Home's first page: your own school's posts, or every school's for a guest.
  const school = session ? schoolForID(session.schoolID).slug : undefined;
  const page = await feedPage({ category: q.get("category") ?? undefined, q: q.get("q") ?? undefined, school }, seed, offset);
  return NextResponse.json(page, { headers: { "cache-control": "no-store" } });
}
