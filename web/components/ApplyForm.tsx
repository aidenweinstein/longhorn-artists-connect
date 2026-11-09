"use client";

import { useState, useTransition } from "react";
import { applyAction } from "@/app/(app)/people/actions";

const field = "w-full rounded-xl border border-border bg-background p-3 text-sm outline-none focus:border-brand";

export default function ApplyForm({ category, defaultName, email }: { category: string; defaultName: string; email: string }) {
  const [name, setName] = useState(defaultName);
  const [message, setMessage] = useState("");
  const [links, setLinks] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);
  const [pending, start] = useTransition();

  if (sent) {
    return (
      <div className="mt-8 rounded-2xl bg-surface p-6 text-center">
        <p className="text-lg font-semibold">Application sent</p>
        <p className="mt-1 text-muted">Thanks! We&rsquo;ll take a look.</p>
      </div>
    );
  }

  return (
    <form
      className="mt-8 space-y-5"
      onSubmit={(e) => {
        e.preventDefault();
        setError(null);
        start(async () => {
          const res = await applyAction(category, { name, message, links });
          if (res.ok) setSent(true);
          else setError(res.message);
        });
      }}
    >
      <label className="block">
        <span className="mb-1.5 block text-sm font-medium">Name</span>
        <input value={name} onChange={(e) => setName(e.target.value)} maxLength={120} className={field} />
      </label>
      <p className="text-sm text-muted">Applying as {email}</p>
      <label className="block">
        <span className="mb-1.5 block text-sm font-medium">About your work</span>
        <textarea
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          rows={6}
          maxLength={3000}
          placeholder="What you make, what you're proud of, and what you're working on next."
          className={field}
        />
      </label>
      <label className="block">
        <span className="mb-1.5 block text-sm font-medium">
          Links <span className="font-normal text-muted">(optional)</span>
        </span>
        <textarea
          value={links}
          onChange={(e) => setLinks(e.target.value)}
          rows={2}
          maxLength={1000}
          placeholder="Reel, website, Instagram…"
          className={field}
        />
      </label>
      {error && <p className="text-sm text-red-500">{error}</p>}
      <button
        type="submit"
        disabled={pending || !message.trim()}
        className="rounded-full bg-brand px-6 py-2.5 text-sm font-semibold text-white hover:brightness-110 disabled:opacity-60"
      >
        {pending ? "Sending…" : "Send application"}
      </button>
    </form>
  );
}
