import { NextResponse, type NextRequest } from "next/server";
import {
  GUEST_COOKIE,
  SESSION_COOKIE,
  SESSION_COOKIE_OPTIONS,
  SESSION_RENEW_AFTER,
  decodeSession,
  encodeSession,
  hasGuestPass,
} from "@/lib/session";

// Anyone without a valid sign-in (or guest pass) lands on the welcome page first.
export function proxy(request: NextRequest) {
  const session = decodeSession(request.cookies.get(SESSION_COOKIE)?.value);
  const signedIn = session !== null;
  // A guest pass is only issued after an email code (app/guest), so nobody sees
  // students' work without having verified an email address.
  const guest = hasGuestPass(request.cookies.get(GUEST_COOKIE)?.value);
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
  // Run on app pages only, not on the welcome, sign-in or guest pages, API routes, or static files.
  matcher: ["/((?!welcome|signin|signup|guest|api|_next|brand|favicon.ico|.*\\..*).*)"],
};
