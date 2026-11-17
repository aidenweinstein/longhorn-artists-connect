"use client";

import { useRouter } from "next/navigation";
import { useTransition, type ReactNode } from "react";
import { signOutAction } from "@/app/auth/actions";

/** Signs out and returns to the welcome page. The top bar passes its own look, icon and label. */
export default function SignOutButton({
  className = "rounded-full border border-border px-4 py-1.5 text-sm font-medium text-muted transition hover:bg-surface hover:text-foreground disabled:opacity-60",
  label = "Sign out",
  labelClassName,
  glyph,
}: {
  className?: string;
  label?: string;
  labelClassName?: string;
  glyph?: ReactNode;
}) {
  const router = useRouter();
  const [pending, start] = useTransition();
  return (
    <button
      type="button"
      disabled={pending}
      aria-label={label}
      title={label}
      onClick={() =>
        start(async () => {
          await signOutAction();
          router.replace("/welcome");
          router.refresh();
        })
      }
      className={className}
    >
      {glyph}
      <span className={labelClassName}>{pending ? "Signing out…" : label}</span>
    </button>
  );
}
