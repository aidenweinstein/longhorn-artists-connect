import { timingSafeEqual } from "node:crypto";
import { NextResponse, type NextRequest } from "next/server";
import {
  APPLE_STATE_COOKIE,
  APPLE_STATE_COOKIE_OPTIONS,
  APPLE_TICKET_COOKIE,
  APPLE_TICKET_COOKIE_OPTIONS,
  decodeAppleState,
  encodeAppleTicket,
} from "@/lib/apple";
import { SESSION_COOKIE, SESSION_COOKIE_OPTIONS, encodeSession } from "@/lib/session";
import { appleSession } from "@/lib/verification";

const same = (a: string, b: string) => {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};

/**
 * Where Apple posts back (response_mode=form_post). verification-service checks
 * Apple's identity token and says who this is: signed straight in, or on to the
 * school email step with an Apple ticket.
 */
export async function POST(request: NextRequest) {
  const form = await request.formData().catch(() => null);
  const saved = decodeAppleState(request.cookies.get(APPLE_STATE_COOKIE)?.value);

  // 303 so the browser follows with a GET. The state cookie is single-use.
  const go = (path: string) => {
    const response = NextResponse.redirect(new URL(path, request.url), 303);
    response.cookies.set(APPLE_STATE_COOKIE, "", { ...APPLE_STATE_COOKIE_OPTIONS, maxAge: 0 });
    return response;
  };

  // Cancelled on Apple's sheet: back to sign-in, nothing to say.
  if (!form || form.get("error")) return go("/signin");

  const state = String(form.get("state") ?? "");
  const idToken = String(form.get("id_token") ?? "");
  if (!saved || !state || !idToken || !same(state, saved.state)) return go("/signin?apple=error");

  const clientIP = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || request.headers.get("x-real-ip") || "unknown";
  const result = await appleSession(idToken, saved.nonce, clientIP);
  if (!result.ok) return go("/signin?apple=error");

  if (result.signedIn) {
    const response = go("/");
    response.cookies.set(
      SESSION_COOKIE,
      encodeSession({ ...result.signedIn, issuedAt: Math.floor(Date.now() / 1000) }),
      SESSION_COOKIE_OPTIONS,
    );
    response.cookies.set(APPLE_TICKET_COOKIE, "", { ...APPLE_TICKET_COOKIE_OPTIONS, maxAge: 0 });
    return response;
  }

  // Apple confirmed; the school email code finishes it (and links the Apple ID).
  const response = go(`/signin?apple=${result.reason}`);
  response.cookies.set(APPLE_TICKET_COOKIE, encodeAppleTicket(result.appleTicket, result.reason), APPLE_TICKET_COOKIE_OPTIONS);
  return response;
}
