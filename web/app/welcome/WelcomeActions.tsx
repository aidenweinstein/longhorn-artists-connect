import Link from "next/link";
import AppleSignInButton from "@/components/AppleSignInButton";
import { appleEnabled } from "@/lib/appleConfig";

export default function WelcomeActions({ mock = false }: { mock?: boolean }) {
  return (
    <div className="flex w-full max-w-xs flex-col items-stretch gap-3">
      {/* Same Apple ID as the app: opens the app account. Not in the Mock launch walkthrough. */}
      {!mock && appleEnabled() && <AppleSignInButton label="Continue with Apple" />}
      <Link
        href={mock ? "/signup/mock" : "/signup"}
        className="rounded-full bg-white px-6 py-3 text-center text-[15px] font-semibold text-black transition hover:bg-white/85"
      >
        Create account
      </Link>
      <Link
        href={mock ? "/signin/mock" : "/signin"}
        className="rounded-full border border-white/25 px-6 py-3 text-center text-[15px] font-semibold text-white transition hover:bg-white/10"
      >
        Sign in
      </Link>
      {/* Guests confirm an email first (app/guest). Mock launch only shows the page: no guest pass is set. */}
      <Link
        href={mock ? "/" : "/guest"}
        replace={mock}
        className="mt-1 text-center text-sm font-medium text-white/70 underline-offset-4 hover:text-white hover:underline"
      >
        Continue as guest
      </Link>
    </div>
  );
}
