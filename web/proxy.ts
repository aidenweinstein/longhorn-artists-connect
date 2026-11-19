import { NextResponse, type NextRequest } from "next/server";
import {
  GUEST_COOKIE,
  GUEST_COOKIE_OPTIONS,
  SESSION_COOKIE,
  SESSION_COOKIE_OPTIONS,
  SESSION_RENEW_AFTER,
  decodeGuestPass,
  decodeSession,
  encodeGuestPass,
  encodeSession,
  guestCanSee,
} from "@/lib/session";

// Anyone without a valid sign-in (or guest pass) lands on the welcome page first.
export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const session = decodeSession(request.cookies.get(SESSION_COOKIE)?.value);
  const signedIn = session !== null;
  // A guest pass is only issued after an email code (app/guest), so nobody sees
  // students' work without having verified an email address.
  const guestPass = signedIn ? null : decodeGuestPass(request.cookies.get(GUEST_COOKIE)?.value);
  const guest = guestPass !== null;

  // The welcome and guest pages are only for people who aren't in yet. Someone who already
  // signed in, or confirmed their email as a guest on this device, goes straight to Home.
  if (pathname === "/welcome" || pathname === "/guest") {
    return signedIn || guest ? NextResponse.redirect(new URL("/", request.url)) : NextResponse.next();
  }

  if (!signedIn && !guest) {
    return NextResponse.redirect(new URL("/welcome", request.url));
  }
  // Guests only see Home, the school home pages and posts (see guestCanSee).
  if (guest && !guestCanSee(pathname)) {
    return NextResponse.redirect(new URL("/", request.url));
  }

  const response = NextResponse.next();
  const now = Math.floor(Date.now() / 1000);
  // Keep people signed in while they use the site: re-issue an aging session with a fresh date.
  if (session && now - session.issuedAt > SESSION_RENEW_AFTER) {
    response.cookies.set(SESSION_COOKIE, encodeSession({ ...session, issuedAt: now }), SESSION_COOKIE_OPTIONS);
  }
  // Guests too: a guest confirms their email once on a device and never has to again while they keep visiting.
  if (guestPass && now - guestPass.issuedAt > SESSION_RENEW_AFTER) {
    response.cookies.set(GUEST_COOKIE, encodeGuestPass(guestPass.email), GUEST_COOKIE_OPTIONS);
  }
  return response;
}

export const config = {
  // Run on app pages only, not on the sign-in pages, Sign in with Apple (/auth/apple),
  // API routes, or static files. The welcome and guest pages are matched exactly, only to
  // send people who are already in to Home (the Mock launch walkthrough, /welcome/mock, isn't).
  matcher: ["/welcome", "/guest", "/((?!welcome|signin|signup|guest|auth|api|_next|brand|favicon.ico|.*\\..*).*)"],
};
