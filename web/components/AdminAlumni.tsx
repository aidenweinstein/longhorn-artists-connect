"use client";

import Link from "next/link";
import { useState, useTransition } from "react";
import { decideAlum } from "@/app/(app)/admin/alumni/actions";
import type { PendingAlum } from "@/lib/alumniReview";

export type AlumRow = PendingAlum & { name: string; imageUrl?: string; profileID?: string; line: string };

const dateFmt = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: "America/Chicago" });

/** The alumni waiting list on /admin/alumni, each with Approve and Turn down. */
export default function AdminAlumni({ rows }: { rows: AlumRow[] }) {
  const [done, setDone] = useState<Record<string, "approved" | "declined">>({});
  const [error, setError] = useState<string | null>(null);
  const [busy, startTransition] = useTransition();

  function decide(row: AlumRow, approve: boolean) {
    setError(null);
    startTransition(async () => {
      const result = await decideAlum(row.userRecordName, approve);
      if (result.ok) setDone((d) => ({ ...d, [row.userRecordName]: approve ? "approved" : "declined" }));
      else setError(result.message);
    });
  }

  if (rows.length === 0) return <p className="rounded-2xl bg-surface p-6 text-center text-muted">No alumni waiting for approval.</p>;

  return (
    <div className="space-y-3">
      {error && <p role="alert" className="rounded-xl bg-red-500/10 p-3 text-sm text-red-500">{error}</p>}
      <ul className="divide-y divide-border rounded-2xl bg-surface">
        {rows.map((row) => {
          const outcome = done[row.userRecordName];
          return (
            <li key={row.userRecordName} className="flex flex-wrap items-center gap-4 p-4">
              {row.imageUrl ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={row.imageUrl} alt="" className="h-12 w-12 shrink-0 rounded-full object-cover" />
              ) : (
                <span aria-hidden className="h-12 w-12 shrink-0 rounded-full bg-foreground/10" />
              )}
              <div className="min-w-0 flex-1">
                <p className="font-semibold">
                  {row.profileID ? (
                    <Link href={`/portfolio/${row.profileID}`} className="hover:underline">{row.name}</Link>
                  ) : (
                    row.name
                  )}
                </p>
                <p className="truncate text-sm text-muted">
                  {[row.schoolName && `${row.schoolName} alum`, row.line].filter(Boolean).join(" · ")}
                </p>
                <p className="truncate text-sm text-muted">
                  {row.email || "No email on file"} · signed up {dateFmt.format(new Date(row.requestedAt * 1000))}
                </p>
              </div>
              {outcome ? (
                <span className={`text-sm font-semibold ${outcome === "approved" ? "text-emerald-500" : "text-muted"}`}>
                  {outcome === "approved" ? "Approved" : "Turned down"}
                </span>
              ) : (
                <div className="flex shrink-0 gap-2">
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => decide(row, false)}
                    className="rounded-full border border-border px-4 py-2 text-sm font-semibold hover:bg-background disabled:opacity-50"
                  >
                    Turn down
                  </button>
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => decide(row, true)}
                    className="rounded-full bg-brand px-4 py-2 text-sm font-semibold text-white hover:brightness-110 disabled:opacity-50"
                  >
                    Approve
                  </button>
                </div>
              )}
            </li>
          );
        })}
      </ul>
    </div>
  );
}
