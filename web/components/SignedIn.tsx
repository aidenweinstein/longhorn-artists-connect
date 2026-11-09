"use client";

import { useRouter } from "next/navigation";
import { primaryBtn } from "./AuthShell";

export default function SignedIn({ heading, note }: { heading: string; note?: string }) {
  const router = useRouter();
  return (
    <div className="space-y-4 text-center">
      <p className="text-lg font-semibold">{heading}</p>
      {note && <p className="text-sm text-white/65">{note}</p>}
      <button onClick={() => router.replace("/")} className={primaryBtn}>
        Go to Nexus
      </button>
    </div>
  );
}
