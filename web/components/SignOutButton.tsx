"use client";

import { useRouter } from "next/navigation";
import { useTransition } from "react";
import { signOutAction } from "@/app/auth/actions";

export default function SignOutButton() {
  const router = useRouter();
  const [pending, start] = useTransition();
  return (
    <button
      type="button"
      disabled={pending}
      onClick={() =>
        start(async () => {
          await signOutAction();
          router.replace("/welcome");
          router.refresh();
        })
      }
      className="rounded-full border border-border px-4 py-1.5 text-sm font-medium text-muted transition hover:bg-surface hover:text-foreground disabled:opacity-60"
    >
      {pending ? "Signing out…" : "Sign out"}
    </button>
  );
}
