import { cookies } from "next/headers";
import { APPLE_TICKET_COOKIE, appleEnabled, decodeAppleTicket, type AppleReason } from "@/lib/apple";
import AppleSignInButton from "./AppleSignInButton";

const STEP_NOTE: Record<AppleReason, string> = {
  new: "Apple ID confirmed. Now enter your school email (the one you use in the Nexus app, if you have it) to sign in or create your account. After this, Sign in with Apple is all you need.",
  verify: "Apple ID confirmed. Verify your school email to finish signing in.",
  confirm: "Apple ID confirmed. Enter your school email once to finish linking it. After this, Sign in with Apple is all you need.",
};

/**
 * Above the sign-in form: the Sign in with Apple button, or, when Apple is done
 * and the school email step is next, what that step is for.
 */
export default async function AppleSignIn({ searchParams }: { searchParams: Promise<{ [key: string]: string | string[] | undefined }> }) {
  const [params, jar] = await Promise.all([searchParams, cookies()]);
  const apple = typeof params.apple === "string" ? params.apple : undefined;
  const ticket = decodeAppleTicket(jar.get(APPLE_TICKET_COOKIE)?.value);

  if (ticket) {
    return (
      <p className="mb-5 rounded-2xl border border-white/15 bg-white/5 px-4 py-3 text-sm text-white/80">{STEP_NOTE[ticket.reason]}</p>
    );
  }
  if (!appleEnabled()) {
    return apple === "off" ? <p role="alert" className="mb-5 text-sm text-red-400">Sign in with Apple isn&apos;t set up yet. Use your school email.</p> : null;
  }
  return (
    <div className="mb-5 space-y-4">
      {apple === "error" && (
        <p role="alert" className="text-sm text-red-400">Sign in with Apple didn&apos;t go through. Try again, or use your school email.</p>
      )}
      <AppleSignInButton />
      <div className="flex items-center gap-3 text-xs uppercase tracking-wider text-white/40">
        <span className="h-px flex-1 bg-white/15" />
        or use your school email
        <span className="h-px flex-1 bg-white/15" />
      </div>
    </div>
  );
}
