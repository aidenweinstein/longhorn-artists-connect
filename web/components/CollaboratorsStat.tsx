"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import Avatar from "./Avatar";
import type { CollaboratorRow, Collaborators } from "@/lib/account";
import { personHref } from "@/lib/people";

/**
 * The profile header's Collabs number: unique collaborators who have a Nexus account.
 * Clicking it opens the list of everyone they've been credited with, members first,
 * then names that aren't on Nexus (listed, but not counted).
 */
export default function CollaboratorsStat({ label, collaborators }: { label: string; collaborators: Collaborators }) {
  const [open, setOpen] = useState(false);
  const { members, others } = collaborators;
  const total = members.length + others.length;

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    window.addEventListener("keydown", onKey);
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = overflow;
    };
  }, [open]);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="flex flex-col-reverse items-center rounded-lg px-1 transition hover:opacity-75"
        aria-haspopup="dialog"
      >
        <span className="text-xs text-muted">{label}</span>
        <span className="text-xl font-bold leading-tight tabular-nums">{members.length}</span>
      </button>

      {open && (
        <div
          className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/50 p-4 sm:p-10"
          onClick={() => setOpen(false)}
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-labelledby="collaborators-title"
            className="w-full max-w-md rounded-2xl bg-background p-6 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between gap-4">
              <h2 id="collaborators-title" className="text-xl font-bold">
                {members.length} {members.length === 1 ? "collaborator" : "collaborators"}{" "}
                <span className="font-normal text-muted">({total} total)</span>
              </h2>
              <button className="text-muted hover:text-foreground" onClick={() => setOpen(false)} aria-label="Close">
                ✕
              </button>
            </div>

            {total === 0 ? (
              <p className="py-10 text-center text-muted">No collaborators yet.</p>
            ) : (
              <div className="mt-4 max-h-[65vh] space-y-5 overflow-y-auto">
                {members.length > 0 && (
                  <ul className="space-y-1">
                    {members.map((row) => (
                      <li key={row.key}>
                        <Link
                          href={personHref(row.name, row.profileID)}
                          onClick={() => setOpen(false)}
                          className="flex items-center gap-3 rounded-xl p-2 transition hover:bg-surface"
                        >
                          <Row row={row} />
                        </Link>
                      </li>
                    ))}
                  </ul>
                )}
                {others.length > 0 && (
                  <section>
                    <h3 className="mb-1 px-2 text-xs font-semibold uppercase tracking-wide text-muted">Not on Nexus</h3>
                    <ul className="space-y-1">
                      {others.map((row) => (
                        <li key={row.key} className="flex items-center gap-3 p-2 opacity-70">
                          <Row row={row} />
                        </li>
                      ))}
                    </ul>
                  </section>
                )}
              </div>
            )}
          </div>
        </div>
      )}
    </>
  );
}

/** Avatar, name, and "3 posts together · Film A, Film B +1". */
function Row({ row }: { row: CollaboratorRow }) {
  const shown = row.titles.slice(0, 2).join(", ");
  const extra = row.titles.length > 2 ? ` +${row.titles.length - 2}` : "";
  return (
    <>
      <Avatar name={row.name || "?"} src={row.avatarUrl} size="md" />
      <span className="min-w-0 flex-1">
        <span className="block truncate font-semibold">{row.name || "Unknown"}</span>
        <span className="block truncate text-sm text-muted">
          {row.sharedPosts === 1 ? "1 post together" : `${row.sharedPosts} posts together`}
          {shown && ` · ${shown}${extra}`}
        </span>
      </span>
    </>
  );
}
