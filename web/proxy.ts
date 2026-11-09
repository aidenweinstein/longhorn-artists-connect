import { NextResponse, type NextRequest } from "next/server";
import { SESSION_COOKIE, decodeSession } from "@/lib/session";

// Anyone without a valid sign-in (or guest pass) lands on the welcome page first.
export function proxy(request: NextRequest) {
  const signedIn = decodeSession(request.cookies.get(SESSION_COOKIE)?.value) !== null;
  // Guest browsing is a development convenience only: the live site is sign-in only,
  // so real students' work is never visible to someone who hasn't verified.
  const guest = process.env.NODE_ENV !== "production" && request.cookies.has("nexus_guest");
  if (!signedIn && !guest) {
    return NextResponse.redirect(new URL("/welcome", request.url));
  }
  return NextResponse.next();
}

export const config = {
  // Run on app pages only, not on the welcome or sign-in pages, API routes, or static files.
  matcher: ["/((?!welcome|signin|signup|api|_next|brand|favicon.ico|.*\\..*).*)"],
};
