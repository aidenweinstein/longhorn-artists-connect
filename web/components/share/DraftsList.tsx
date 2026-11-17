"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { deleteDraft, listDrafts, type ShareDraft } from "@/lib/shareDrafts";
import { SHARE_TYPES } from "@/lib/shareTypes";

const typeName = (id: string) => SHARE_TYPES.find((t) => t.id === id)?.title ?? "Post";
const savedFmt = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });

/** The drafts saved in this browser, newest first: open one to keep going, or delete it. */
export default function DraftsList() {
  const [drafts, setDrafts] = useState<ShareDraft[] | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    listDrafts().then(setDrafts, () => setFailed(true));
  }, []);

  async function remove(d: ShareDraft) {
    if (!confirm(`Delete the draft "${d.title || `Untitled ${typeName(d.type)}`}"?`)) return;
    await deleteDraft(d.id).catch(() => undefined);
    setDrafts((all) => all?.filter((x) => x.id !== d.id) ?? null);
  }

  if (failed) return <Empty text="Drafts couldn't be opened in this browser." />;
  if (!drafts) return null;
  if (!drafts.length) return <Empty text="No drafts yet" />;
  return (
    <div className="space-y-6">
      <ul className="divide-y divide-border overflow-hidden rounded-2xl border border-border bg-surface">
        {drafts.map((d) => (
          <li key={d.id} className="flex items-center gap-3 px-5 py-4">
            <Link href={`/share/${d.type}?draft=${encodeURIComponent(d.id)}`} className="min-w-0 flex-1">
              <p className="truncate font-semibold">{d.title || `Untitled ${typeName(d.type)}`}</p>
              <p className="text-sm text-muted">
                {typeName(d.type)} · Saved {savedFmt.format(new Date(d.savedAt))}
              </p>
            </Link>
            <button type="button" onClick={() => void remove(d)} className="rounded-full px-3 py-1.5 text-sm text-red-500 hover:bg-red-500/10">
              Delete
            </button>
          </li>
        ))}
      </ul>
      <p className="px-1 text-sm text-muted">Drafts are kept in this browser, so they show up only here.</p>
    </div>
  );
}

function Empty({ text }: { text: string }) {
  return (
    <div className="rounded-2xl border border-border bg-surface px-6 py-16 text-center">
      <p className="text-muted">{text}</p>
    </div>
  );
}
