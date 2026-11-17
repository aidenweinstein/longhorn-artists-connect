"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition, type ReactNode } from "react";
import { connectAction, messageAction } from "@/app/(app)/portfolio/[person]/actions";
import Avatar from "./Avatar";
import PersonLink from "./PersonLink";

export type ConnectionPerson = { profileID: string; name: string; imageUrl?: string; roles: string[] };

/**
 * Network → Connections: requests waiting on the visitor (with Accept), then the people
 * they're connected with (with Message) — the website's version of the app's Connections
 * and Requests sections in the Network directory.
 */
export default function ConnectionsList({ requests, connected }: { requests: ConnectionPerson[]; connected: ConnectionPerson[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [, start] = useTransition();

  function run(profileID: string, action: () => Promise<string | void>) {
    setError(null);
    setBusy(profileID);
    start(async () => {
      const problem = await action();
      if (problem) setError(problem);
      setBusy(null);
    });
  }

  const accept = (p: ConnectionPerson) =>
    run(p.profileID, async () => {
      const res = await connectAction(p.profileID);
      if (!res.ok) return res.message;
      router.refresh();
    });

  const message = (p: ConnectionPerson) =>
    run(p.profileID, async () => {
      const res = await messageAction(p.profileID);
      if (!res.ok) return res.message;
      router.push(`/network?c=${res.threadID}`);
    });

  const pill = "shrink-0 rounded-full px-4 py-1.5 text-sm font-semibold transition disabled:opacity-50";

  const section = (title: string, people: ConnectionPerson[], button: (p: ConnectionPerson) => ReactNode) =>
    people.length > 0 && (
      <section className="mt-6">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-muted">
          {title} <span className="font-normal">· {people.length}</span>
        </h2>
        <ul className="mt-2 grid grid-cols-1 gap-x-6 sm:grid-cols-2 lg:grid-cols-3">
          {people.map((p) => (
            <li key={p.profileID} className="flex items-center gap-3 border-b border-border py-2">
              <PersonLink name={p.name} profileID={p.profileID} className="flex min-w-0 flex-1 items-center gap-3 no-underline hover:opacity-80">
                <Avatar name={p.name} src={p.imageUrl} size="feed" />
                <span className="min-w-0">
                  <span className="block truncate text-sm font-semibold">{p.name}</span>
                  {p.roles.length > 0 && <span className="block truncate text-xs text-muted">{p.roles.join(", ")}</span>}
                </span>
              </PersonLink>
              {button(p)}
            </li>
          ))}
        </ul>
      </section>
    );

  return (
    <>
      {error && <p className="mt-4 text-sm text-red-500">{error}</p>}
      {section("Requests", requests, (p) => (
        <button type="button" onClick={() => accept(p)} disabled={busy === p.profileID} className={`${pill} bg-brand text-white hover:brightness-110`}>
          {busy === p.profileID ? "…" : "Accept"}
        </button>
      ))}
      {section("Connections", connected, (p) => (
        <button type="button" onClick={() => message(p)} disabled={busy === p.profileID} className={`${pill} bg-brand/12 text-brand hover:bg-brand/20`}>
          {busy === p.profileID ? "…" : "Message"}
        </button>
      ))}
      {requests.length === 0 && connected.length === 0 && (
        <p className="py-24 text-center text-muted">No connections yet. Press Connect on someone&apos;s portfolio to send them a request.</p>
      )}
    </>
  );
}
