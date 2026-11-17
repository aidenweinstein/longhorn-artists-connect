"use client";

import { useEffect, useState, useTransition } from "react";
import { devSkipSignInAction } from "@/app/auth/devActions";

const STORE_KEY = "nexus-dev-signin-name";

/**
 * TESTING ONLY, shown under `npm run dev` and never on the live site: signs in with one
 * click, no email code. The name box picks which Nexus account to be and is remembered
 * in this browser, so after the first time it is a single click.
 */
export default function DevSkipSignIn() {
  const [name, setName] = useState("");
  const [error, setError] = useState("");
  const [busy, start] = useTransition();

  useEffect(() => {
    try {
      const saved = localStorage.getItem(STORE_KEY);
      // eslint-disable-next-line react-hooks/set-state-in-effect
      if (saved) setName(saved);
    } catch {}
  }, []);

  if (process.env.NODE_ENV !== "development") return null;

  function skip() {
    setError("");
    start(async () => {
      const result = await devSkipSignInAction(name);
      if (!result.ok) return setError(result.message);
      try {
        localStorage.setItem(STORE_KEY, name.trim());
      } catch {}
      // A full load, so every part of the site picks up the new session.
      // eslint-disable-next-line @next/next/no-location-assign-relative-destination
      window.location.assign("/");
    });
  }

  return (
    <div className="mt-6 space-y-2 rounded-2xl border border-dashed border-yellow-400/50 p-4">
      <p className="text-xs font-semibold uppercase tracking-wider text-yellow-300">Testing only · not on the live site</p>
      <input
        value={name}
        onChange={(e) => setName(e.target.value)}
        placeholder="Sign in as (profile name), or leave blank"
        aria-label="Profile name to sign in as"
        className="h-10 w-full rounded-xl border border-white/15 bg-black/30 px-3 text-sm text-white outline-none placeholder:text-white/40 focus:border-yellow-300"
      />
      <button
        type="button"
        onClick={skip}
        disabled={busy}
        className="h-10 w-full rounded-full bg-yellow-300 text-sm font-semibold text-black transition hover:brightness-110 disabled:opacity-50"
      >
        {busy ? "Signing in…" : "Skip sign-in"}
      </button>
      {error && <p role="alert" className="text-sm text-red-400">{error}</p>}
    </div>
  );
}
