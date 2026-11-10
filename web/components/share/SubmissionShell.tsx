"use client";

import Link from "next/link";
import { useState, type ReactNode } from "react";

/**
 * Page frame for every Share form: back link, title, the form's sections, and the Post
 * button. `missing` lists what still has to be filled in; Post stays disabled until it's
 * empty. Posting from the web isn't connected to CloudKit yet, so Post explains that
 * instead of pretending to upload.
 */
export default function SubmissionShell({
  title,
  missing,
  children,
}: {
  title: string;
  missing: string[];
  children: ReactNode;
}) {
  const [tried, setTried] = useState(false);
  const ready = missing.length === 0;

  return (
    <form
      className="w-full space-y-6 pb-24"
      onSubmit={(e) => {
        e.preventDefault();
        setTried(true);
      }}
    >
      <header className="flex items-center justify-between gap-4">
        <Link href="/share" className="text-sm text-muted hover:text-foreground">
          ← Share
        </Link>
        <button
          type="submit"
          disabled={!ready}
          className="rounded-full bg-brand px-5 py-2 text-sm font-semibold text-white hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
        >
          Post
        </button>
      </header>
      <h1 className="text-3xl font-bold">{title}</h1>

      <div className="grid gap-6 lg:grid-cols-2 lg:items-start">{children}</div>

      <div aria-live="polite" className="text-sm">
        {!ready && <p className="px-4 text-muted">To post, add: {missing.join(", ")}.</p>}
        {ready && tried && (
          <p className="rounded-2xl border border-border p-4 text-muted">
            Posting from the website is coming soon. For now, post this from the Nexus app.
          </p>
        )}
      </div>
    </form>
  );
}
