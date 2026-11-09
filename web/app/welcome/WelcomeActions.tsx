"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";

const GUEST_COOKIE = "nexus_guest";

export default function WelcomeActions() {
  const router = useRouter();

  function continueAsGuest() {
    document.cookie = `${GUEST_COOKIE}=1; path=/; max-age=31536000; samesite=lax`;
    router.replace("/");
  }

  return (
    <div className="flex w-full max-w-xs flex-col items-stretch gap-3">
      <Link
        href="/signup"
        className="rounded-full bg-brand px-6 py-3 text-center text-[15px] font-semibold text-white transition hover:brightness-110"
      >
        Create account
      </Link>
      <Link
        href="/signin"
        className="rounded-full border border-white/25 px-6 py-3 text-center text-[15px] font-semibold text-white transition hover:bg-white/10"
      >
        Sign in
      </Link>
      <button
        onClick={continueAsGuest}
        className="mt-1 text-sm font-medium text-white/70 underline-offset-4 hover:text-white hover:underline"
      >
        Continue as guest
      </button>
    </div>
  );
}
