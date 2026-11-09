"use client";

import { useState, useTransition, type FormEvent } from "react";
import { confirmCodeAction, requestCodeAction } from "@/app/auth/actions";
import { field, primaryBtn } from "./AuthShell";

/** Six-digit email code entry. Confirms with verification-service and starts a session. */
export default function CodeStep({ email, pendingID: initialID, onBack, onVerified }: {
  email: string;
  pendingID: string;
  onBack: () => void;
  onVerified: () => void;
}) {
  const [pendingID, setPendingID] = useState(initialID);
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, startTransition] = useTransition();
  const ready = code.length === 6 && !busy;

  function submit(e: FormEvent) {
    e.preventDefault();
    if (!ready) return;
    setError(null);
    startTransition(async () => {
      const result = await confirmCodeAction(pendingID, code);
      if (result.ok) onVerified();
      else setError(result.message);
    });
  }

  function resend() {
    setError(null);
    startTransition(async () => {
      const result = await requestCodeAction(email);
      if (result.ok) {
        setPendingID(result.pendingID);
        setCode("");
        setNotice("A new code is on its way.");
      } else setError(result.message);
    });
  }

  return (
    <form onSubmit={submit} className="space-y-4">
      <p className="text-sm text-white/70">
        We sent a 6-digit code to <span className="font-semibold text-white">{email}</span>. It expires in 10 minutes.
      </p>
      <input
        inputMode="numeric"
        autoComplete="one-time-code"
        maxLength={6}
        value={code}
        onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
        placeholder="000000"
        aria-label="Verification code"
        className={`${field} text-center font-mono text-2xl tracking-[0.5em]`}
        autoFocus
      />
      {error && <p role="alert" className="text-sm text-red-400">{error}</p>}
      {notice && !error && <p className="text-sm text-white/60">{notice}</p>}
      <button type="submit" disabled={!ready} className={primaryBtn}>
        {busy ? "Checking…" : "Verify"}
      </button>
      <div className="flex justify-between text-sm text-white/60">
        <button type="button" onClick={onBack} className="hover:text-white">Use a different email</button>
        <button type="button" onClick={resend} disabled={busy} className="hover:text-white">Resend code</button>
      </div>
    </form>
  );
}
