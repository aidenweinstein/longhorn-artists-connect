"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition, type FormEvent } from "react";
import { requestGuestCodeAction } from "@/app/auth/actions";
import { field, labelCls, primaryBtn } from "@/components/AuthShell";
import CodeStep from "@/components/CodeStep";

/** Guests browse without an account, but only after confirming an email address (any address). */
export default function GuestForm() {
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
      const result = await requestGuestCodeAction(email.trim());
      if (result.ok) setPendingID(result.pendingID);
      else setError(result.message);
    });
  }

  if (pendingID) {
    return (
      <CodeStep
        guest
        email={email.trim()}
        pendingID={pendingID}
        onBack={() => setPendingID(null)}
        onVerified={() => router.replace("/")}
      />
    );
  }

  return (
    <form onSubmit={submit} className="space-y-4">
      <div>
        <label htmlFor="email" className={labelCls}>Email</label>
        <input
          id="email"
          type="email"
          autoComplete="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="you@example.com"
          className={field}
        />
      </div>
      {error && <p role="alert" className="text-sm text-red-400">{error}</p>}
      <button type="submit" disabled={!valid} className={primaryBtn}>
        {busy ? "Sending…" : "Send code"}
      </button>
    </form>
  );
}
