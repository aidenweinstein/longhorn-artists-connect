"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, type ReactNode } from "react";
import { publish, type PostDraft, type Progress } from "@/lib/shareUpload";
import type { ShareTypeID } from "@/lib/sharePost";

const STAGE_LABEL: Record<Progress["stage"], string> = {
  preparing: "Preparing files…",
  uploading: "Uploading",
  saving: "Publishing…",
};

/**
 * Page frame for every Share form: back link, title, the form's sections, and the Post
 * button. `missing` lists what still has to be filled in. Pressing Post with something
 * missing says what; otherwise the files upload straight to CloudKit and the post is
 * published to the app's feed, then the page opens the new post.
 */
export default function SubmissionShell({
  type,
  title,
  missing,
  draft,
  children,
}: {
  type: ShareTypeID;
  title: string;
  missing: string[];
  /** Builds what to post. May be async (reading durations, a video's first frame…). */
  draft: () => PostDraft | Promise<PostDraft>;
  children: ReactNode;
}) {
  const router = useRouter();
  const [tried, setTried] = useState(false);
  const [progress, setProgress] = useState<Progress | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const ready = missing.length === 0;
  const busy = progress !== null;

  async function post() {
    setTried(true);
    setError(null);
    if (!ready || busy) return;
    setProgress({ stage: "preparing", fraction: 0 });
    try {
      const result = await publish(type, await draft(), setProgress);
      if (!result.ok) {
        setError(result.message);
        setProgress(null);
        return;
      }
      if (result.note) setNote(result.note);
      router.push(result.href);
      router.refresh();
    } catch (e) {
      console.error(e);
      setError("Something went wrong while posting. Try again.");
      setProgress(null);
    }
  }

  return (
    <form
      className="mx-auto max-w-xl space-y-6 pb-24"
      onSubmit={(e) => {
        e.preventDefault();
        void post();
      }}
    >
      <header className="flex items-center justify-between gap-4">
        <Link href="/share" className="text-sm text-muted hover:text-foreground">
          ← Share
        </Link>
        <button
          type="submit"
          disabled={busy}
          aria-disabled={!ready}
          className={`rounded-full bg-brand px-5 py-2 text-sm font-semibold text-white hover:brightness-110 disabled:cursor-wait ${ready ? "" : "opacity-50"}`}
        >
          {busy ? "Posting…" : "Post"}
        </button>
      </header>
      <h1 className="text-3xl font-bold">{title}</h1>

      <fieldset disabled={busy} className="space-y-6">
        {children}
      </fieldset>

      <div aria-live="polite" className="space-y-3 text-sm">
        {!ready && <p className={`px-4 ${tried ? "text-red-500" : "text-muted"}`}>To post, add: {missing.join(", ")}.</p>}
        {progress && (
          <div className="rounded-2xl border border-border p-4">
            <p className="mb-2 text-muted">
              {STAGE_LABEL[progress.stage]}
              {progress.stage === "uploading" && ` ${Math.round(progress.fraction * 100)}%`}
            </p>
            <div className="h-1.5 overflow-hidden rounded-full bg-border">
              <div className="h-full bg-brand transition-[width]" style={{ width: `${Math.round(progress.fraction * 100)}%` }} />
            </div>
            {progress.stage === "uploading" && <p className="mt-2 text-xs text-muted">Keep this page open until it finishes.</p>}
          </div>
        )}
        {error && <p className="rounded-2xl border border-red-500/40 p-4 text-red-500">{error}</p>}
        {note && <p className="rounded-2xl border border-border p-4 text-muted">{note}</p>}
      </div>
    </form>
  );
}
