"use client";

import { useRouter } from "next/navigation";
import { primaryBtn } from "./AuthShell";

/** Dead-end screen for flows the website can't complete yet, with a way in as a guest. */
export default function NotConnected({ heading, body }: { heading: string; body: string }) {
  const router = useRouter();
  function continueAsGuest() {
    document.cookie = "nexus_guest=1; path=/; max-age=31536000; samesite=lax";
    router.replace("/");
  }
  return (
    <div className="space-y-4 text-center">
      <p className="text-lg font-semibold">{heading}</p>
      <p className="text-sm text-white/65">
        {body}
      </p>
      <button onClick={continueAsGuest} className={primaryBtn}>
        Continue as guest
      </button>
    </div>
  );
}
