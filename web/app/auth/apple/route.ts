import { NextResponse, type NextRequest } from "next/server";
import {
  APPLE_STATE_COOKIE,
  APPLE_STATE_COOKIE_OPTIONS,
  appleAuthorizeURL,
  appleEnabled,
  encodeAppleState,
  randomValue,
} from "@/lib/apple";

/** "Sign in with Apple": off to Apple, with a fresh state and nonce to check on the way back. */
export async function GET(request: NextRequest) {
  if (!appleEnabled()) return NextResponse.redirect(new URL("/signin?apple=off", request.url));

  const state = randomValue();
  const nonce = randomValue();
  const response = NextResponse.redirect(appleAuthorizeURL(request.nextUrl.origin, state, nonce));
  response.cookies.set(APPLE_STATE_COOKIE, encodeAppleState(state, nonce), APPLE_STATE_COOKIE_OPTIONS);
  return response;
}
