import { NextResponse, type NextRequest } from "next/server";
import { SESSION_COOKIE, SESSION_COOKIE_OPTIONS, SESSION_RENEW_AFTER, decodeSession, encodeSession } from "@/lib/session";

// Anyone without a valid sign-in (or guest pass) lands on the welcome page first.
export function proxy(request: NextRequest) {
  const session = decodeSession(request.cookies.get(SESSION_COOKIE)?.value);
  const signedIn = session !== null;
  // Already signed in: the welcome page is for newcomers, so go straight to the feed.
  if (signedIn && request.nextUrl.pathname === "/welcome") {
    return NextResponse.redirect(new URL("/", request.url));
  }
  if (request.nextUrl.pathname === "/welcome") return NextResponse.next();
  // Guest browsing is a development convenience only: the live site is sign-in only,
  // so real students' work is never visible to someone who hasn't verified.
  const guest = process.env.NODE_ENV !== "production" && request.cookies.has("nexus_guest");
  if (!signedIn && !guest) {
    return NextResponse.redirect(new URL("/welcome", request.url));
  }
  const response = NextResponse.next();
  // Keep people signed in while they use the site: re-issue an aging session with a fresh date.
  if (session && Date.now() / 1000 - session.issuedAt > SESSION_RENEW_AFTER) {
    response.cookies.set(SESSION_COOKIE, encodeSession({ ...session, issuedAt: Math.floor(Date.now() / 1000) }), SESSION_COOKIE_OPTIONS);
  }
  return response;
}

export const config = {
  // Run on app pages only, not on the welcome or sign-in pages, API routes, or static files.
  matcher: ["/welcome", "/((?!welcome|signin|signup|api|_next|brand|favicon.ico|.*\\..*).*)"],
};
