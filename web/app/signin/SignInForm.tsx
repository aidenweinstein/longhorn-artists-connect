"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition, type FormEvent } from "react";
import { requestCodeAction } from "@/app/auth/actions";
import { field, labelCls, primaryBtn } from "@/components/AuthShell";
import CodeStep from "@/components/CodeStep";

export default function SignInForm() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [pendingID, setPendingID] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, startTransition] = useTransition();
  const valid = /\S+@\S+\.\S+/.test(email.trim()) && !busy;

  function submit(e: FormEvent) {
    e.preventDefault();
    if (!valid) return;
    setError(null);
    startTransition(async () => {
      const result = await requestCodeAction(email.trim());
      if (result.ok) setPendingID(result.pendingID);
      else setError(result.message);
    });
  }

  if (pendingID) {
    return (
      <CodeStep
        email={email.trim()}
        pendingID={pendingID}
        onBack={() => setPendingID(null)}
        onVerified={() => router.replace("/")}
      />
    );
  }

  return (
    <div className="space-y-5">
      <button
        type="button"
        disabled
        title="Coming soon"
        className="flex h-12 w-full items-center justify-center gap-2 rounded-full bg-white text-[15px] font-semibold text-black disabled:opacity-50"
      >
        <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
          <path d="M16.4 12.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9-1.7 0-3.3 1-4.2 2.6-1.8 3.1-.5 7.7 1.3 10.2.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8s2 .8 3.4.8c1.4 0 2.3-1.3 3.1-2.5 1-1.4 1.4-2.8 1.4-2.9 0 0-2.7-1-2.7-4.1zM13.8 4.9c.7-.9 1.2-2 1.1-3.2-1 0-2.3.7-3 1.6-.7.8-1.2 2-1.1 3.1 1.1.1 2.3-.6 3-1.5z" />
        </svg>
        Sign in with Apple
      </button>

      <div className="flex items-center gap-3 text-xs uppercase tracking-wide text-white/40">
        <span className="h-px flex-1 bg-white/15" /> or <span className="h-px flex-1 bg-white/15" />
      </div>

      <form onSubmit={submit} className="space-y-4">
        <div>
          <label htmlFor="email" className={labelCls}>School email</label>
          <input
            id="email"
            type="email"
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@school.edu"
            className={field}
          />
        </div>
        {error && <p role="alert" className="text-sm text-red-400">{error}</p>}
        <button type="submit" disabled={!valid} className={primaryBtn}>
          {busy ? "Sending…" : "Send code"}
        </button>
      </form>
    </div>
  );
}
