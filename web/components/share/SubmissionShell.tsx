"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, useSyncExternalStore, type ReactNode } from "react";
import { deletePost } from "@/app/(app)/share/editActions";
import { earlyStatus, earlyVersion, publish, subscribeEarly, timeLeftLabel, type PostDraft, type Progress } from "@/lib/shareUpload";
import type { ShareTypeID } from "@/lib/sharePost";
import { useDrafts, useEditing } from "./DraftContext";

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
  const drafts = useDrafts();
  const editPostID = useEditing();
  const [savingDraft, setSavingDraft] = useState(false);
  const [draftNote, setDraftNote] = useState<string | null>(null);
  const ready = missing.length === 0;
  const busy = progress !== null;
  // Videos and audio upload as soon as they're picked; this re-renders as they go.
  useSyncExternalStore(subscribeEarly, earlyVersion, () => 0);
  const early = busy ? null : earlyStatus();
  const earlyPercent = early ? Math.floor((early.sent / Math.max(1, early.total)) * 100) : 0;

  async function post() {
    setTried(true);
    setError(null);
    if (!ready || busy) return;
    setProgress({ stage: "preparing", fraction: 0 });
    try {
      const result = await publish(type, await draft(), setProgress, editPostID ?? undefined);
      if (!result.ok) {
        setError(result.message);
        setProgress(null);
        return;
      }
      if (result.note) setNote(result.note);
      // Posted: the draft it came from is done with.
      await drafts.clear();
      router.push(result.href);
      router.refresh();
    } catch (e) {
      console.error(e);
      setError("Something went wrong while posting. Try again.");
      setProgress(null);
    }
  }

  const [deleting, setDeleting] = useState(false);
  async function remove() {
    if (!editPostID || busy || deleting) return;
    if (!confirm("Delete this post? It will be removed from Nexus, on the website and in the app. This can't be undone.")) return;
    setDeleting(true);
    setError(null);
    try {
      const result = await deletePost(editPostID);
      if (!result.ok) {
        setError(result.message);
        return;
      }
      router.push(result.href);
      router.refresh();
    } catch (e) {
      console.error(e);
      setError("Couldn't delete the post. Try again.");
    } finally {
      setDeleting(false);
    }
  }

  async function saveDraft() {
    if (busy || savingDraft) return;
    setSavingDraft(true);
    setDraftNote(null);
    try {
      const { filesKept } = await drafts.save();
      setDraftNote(
        filesKept
          ? "Draft saved. Find it in Share → Drafts."
          : "Draft saved, but this browser hadn't room for the files. Pick them again when you resume it.",
      );
    } catch (e) {
      console.error(e);
      setDraftNote("Couldn't save the draft. Try again.");
    } finally {
      setSavingDraft(false);
    }
  }

  return (
    <form
      className="w-full space-y-6 px-3 pb-24 pt-3 sm:px-6 sm:pt-5 lg:px-10"
      onSubmit={(e) => {
        e.preventDefault();
        void post();
      }}
    >
      <header className="flex items-center justify-between gap-4">
        <Link
          href={editPostID ? (type === "project" || type === "event" ? `/discover/${editPostID}` : `/post/${editPostID}`) : "/share"}
          className="text-sm text-muted hover:text-foreground"
        >
          {editPostID ? "← Back to post" : "← Share"}
        </Link>
        <div className="flex items-center gap-2">
          {drafts.available && (
            <button
              type="button"
              onClick={() => void saveDraft()}
              disabled={busy || savingDraft}
              className="rounded-full border border-border px-4 py-2 text-sm font-semibold hover:bg-foreground/5 disabled:opacity-50"
            >
              {savingDraft ? "Saving…" : "Save draft"}
            </button>
          )}
        <button
          type="submit"
          disabled={busy}
          aria-disabled={!ready}
          className={`rounded-full bg-brand px-5 py-2 text-sm font-semibold text-white hover:brightness-110 disabled:cursor-wait ${ready ? "" : "opacity-50"}`}
        >
          {editPostID ? (busy ? "Saving…" : "Save") : busy ? "Posting…" : "Post"}
        </button>
        </div>
      </header>
      <div>
        <h1 className="text-3xl font-bold">{editPostID ? `Edit ${title}` : title}</h1>
        <p className="mt-1 text-muted">
          {editPostID
            ? "Files you don't replace stay as they are. Pick a new one only to change it."
            : "Remember to add yourself to the credits section."}
        </p>
      </div>

      {/* Disabled while posting, so nothing changes mid-upload. */}
      <fieldset disabled={busy} className="min-w-0">
        <div className="grid gap-6 lg:grid-cols-2 lg:items-start">{children}</div>
      </fieldset>

      <div aria-live="polite" className="space-y-3 text-sm">
        {!ready && <p className={`px-4 ${tried ? "text-red-500" : "text-muted"}`}>To {editPostID ? "save" : "post"}, add: {missing.join(", ")}.</p>}
        {progress && (
          <div className="rounded-2xl border border-border p-4">
            <p className="mb-2 text-muted">
              {STAGE_LABEL[progress.stage]}
              {progress.stage === "uploading" && ` ${Math.round(progress.fraction * 100)}%`}
              {progress.stage === "uploading" && timeLeftLabel(progress.secondsLeft) && ` · ${timeLeftLabel(progress.secondsLeft)}`}
            </p>
            <div className="h-1.5 overflow-hidden rounded-full bg-border">
              <div className="h-full bg-brand transition-[width]" style={{ width: `${Math.round(progress.fraction * 100)}%` }} />
            </div>
            {progress.stage === "uploading" && <p className="mt-2 text-xs text-muted">Keep this page open until it finishes.</p>}
          </div>
        )}
        {early && (
          <div className="rounded-2xl border border-border p-4">
            <p className="mb-2 text-muted">
              {early.failed
                ? "Background upload paused. Your file will upload when you post."
                : early.done
                  ? "Your file is uploaded. Post whenever you're ready."
                  : `Uploading your file while you fill this in: ${earlyPercent}%${timeLeftLabel(early.secondsLeft) ? ` · ${timeLeftLabel(early.secondsLeft)}` : ""}`}
            </p>
            {!early.failed && (
              <div className="h-1.5 overflow-hidden rounded-full bg-border">
                <div className="h-full bg-brand transition-[width]" style={{ width: `${earlyPercent}%` }} />
              </div>
            )}
          </div>
        )}
        {error && <p className="rounded-2xl border border-red-500/40 p-4 text-red-500">{error}</p>}
        {note && <p className="rounded-2xl border border-border p-4 text-muted">{note}</p>}
        {draftNote && <p className="rounded-2xl border border-border p-4 text-muted">{draftNote}</p>}
        {editPostID && (
          <div className="flex justify-end pt-6">
            <button
              type="button"
              onClick={() => void remove()}
              disabled={busy || deleting}
              className="rounded-full border border-red-500/40 px-5 py-2 text-sm font-semibold text-red-500 hover:bg-red-500/10 disabled:opacity-50"
            >
              {deleting ? "Deleting…" : "Delete post"}
            </button>
          </div>
        )}
      </div>
    </form>
  );
}
