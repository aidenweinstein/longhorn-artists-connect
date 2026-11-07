"use client";

import { useEffect, useState, useTransition } from "react";
import { flagPost, postActionState, setLike, type ActionState } from "@/app/(app)/post/[id]/actions";
import { FLAG_REASONS } from "@/lib/flags";

const SAVED_KEY = "nexus_saved_posts";

/** Saved posts live in this browser for now: the app keeps saves on each phone, not in CloudKit. */
function readSaved(): string[] {
  try {
    const v = JSON.parse(localStorage.getItem(SAVED_KEY) ?? "[]");
    return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];
  } catch {
    return [];
  }
}

function writeSaved(ids: string[]) {
  try {
    localStorage.setItem(SAVED_KEY, JSON.stringify(ids));
  } catch {
    // Storage blocked (private window); saving just won't persist.
  }
}

const pill =
  "flex h-10 items-center gap-2 rounded-full bg-foreground/10 px-4 text-sm font-semibold transition hover:bg-foreground/20 disabled:opacity-60";

export default function PostActions({ postID, title }: { postID: string; title: string }) {
  const [state, setState] = useState<ActionState | null>(null);
  const [saved, setSaved] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const [reporting, setReporting] = useState(false);
  const [pending, start] = useTransition();

  useEffect(() => {
    let live = true;
    postActionState(postID).then((s) => live && setState(s));
    const id = requestAnimationFrame(() => setSaved(readSaved().includes(postID)));
    return () => {
      live = false;
      cancelAnimationFrame(id);
    };
  }, [postID]);

  // Brief confirmations ("Link copied") fade on their own.
  useEffect(() => {
    if (!note) return;
    const t = setTimeout(() => setNote(null), 3000);
    return () => clearTimeout(t);
  }, [note]);

  function like() {
    if (!state) return;
    if (!state.canLike) return setNote("Verify this email in the Nexus app to like posts here.");
    const next = !state.liked;
    // Show it right away; settle on the server's count when it answers.
    setState({ ...state, liked: next, likes: Math.max(0, state.likes + (next ? 1 : -1)) });
    start(async () => {
      const res = await setLike(postID, next);
      if (res.ok) setState(res.state);
      else {
        setState(state);
        setNote(res.message);
      }
    });
  }

  async function share() {
    const url = window.location.href;
    if (navigator.share) {
      try {
        await navigator.share({ title, url });
        return;
      } catch (e) {
        if (e instanceof DOMException && e.name === "AbortError") return;
      }
    }
    try {
      await navigator.clipboard.writeText(url);
      setNote("Link copied");
    } catch {
      setNote(url);
    }
  }

  function toggleSave() {
    const ids = readSaved().filter((id) => id !== postID);
    if (!saved) ids.unshift(postID);
    writeSaved(ids);
    setSaved(!saved);
    setNote(saved ? "Removed from saved" : "Saved");
  }

  return (
    <div className="relative shrink-0">
      <div className="flex flex-wrap items-center gap-2">
        <button type="button" onClick={like} disabled={!state} aria-pressed={state?.liked ?? false} className={`${pill} ${state?.liked ? "text-brand" : ""}`}>
          <svg width="20" height="20" viewBox="0 0 24 24" fill={state?.liked ? "currentColor" : "none"} stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
            <path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8l1 1.1L12 21l7.8-7.5 1-1.1a5.5 5.5 0 0 0 0-7.8z" />
          </svg>
          {/* No public like counts: just whether you've liked it. */}
          <span>{state?.liked ? "Liked" : "Like"}</span>
        </button>

        <button type="button" onClick={share} className={pill}>
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
            <path d="M4 12v7a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-7M16 6l-4-4-4 4M12 2v14" />
          </svg>
          Share
        </button>

        <button type="button" onClick={toggleSave} aria-pressed={saved} className={`${pill} ${saved ? "text-brand" : ""}`}>
          <svg width="20" height="20" viewBox="0 0 24 24" fill={saved ? "currentColor" : "none"} stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
            <path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z" />
          </svg>
          {saved ? "Saved" : "Save"}
        </button>

        <button type="button" onClick={() => setReporting((r) => !r)} aria-expanded={reporting} className={pill}>
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
            <path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1zM4 22v-7" />
          </svg>
          Flag
        </button>

      </div>
      {note && (
        <span role="status" className="absolute right-0 top-full z-20 mt-2 whitespace-nowrap rounded-lg bg-foreground px-3 py-1.5 text-sm text-background shadow-lg">
          {note}
        </span>
      )}

      {reporting && <FlagForm postID={postID} onDone={(msg) => { setReporting(false); setNote(msg); }} />}
      {pending && <span className="sr-only">Saving…</span>}
    </div>
  );
}

function FlagForm({ postID, onDone }: { postID: string; onDone: (message: string) => void }) {
  const [reason, setReason] = useState<string>(FLAG_REASONS[0]);
  const [why, setWhy] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        setError(null);
        start(async () => {
          const res = await flagPost(postID, reason, why);
          if (res.ok) onDone("Thanks. A moderator will take a look.");
          else setError(res.message);
        });
      }}
      className="absolute right-0 top-full z-30 mt-2 w-[min(26rem,calc(100vw-2rem))] space-y-3 rounded-2xl border border-border bg-surface p-4 shadow-xl"
    >
      <p className="font-semibold">What&rsquo;s wrong with this post?</p>
      <div className="space-y-1.5">
        {FLAG_REASONS.map((r) => (
          <label key={r} className="flex cursor-pointer items-center gap-2.5 text-sm">
            <input type="radio" name="reason" value={r} checked={reason === r} onChange={() => setReason(r)} className="accent-[var(--brand)]" />
            {r}
          </label>
        ))}
      </div>
      <textarea
        value={why}
        onChange={(e) => setWhy(e.target.value)}
        rows={3}
        maxLength={2000}
        placeholder="Tell the moderators a bit more"
        className="w-full rounded-xl border border-border bg-background p-3 text-sm outline-none focus:border-brand"
      />
      {error && <p className="text-sm text-red-500">{error}</p>}
      <div className="flex gap-2">
        <button type="submit" disabled={pending || !why.trim()} className="rounded-full bg-brand px-5 py-2 text-sm font-semibold text-white hover:brightness-110 disabled:opacity-60">
          {pending ? "Sending…" : "Send report"}
        </button>
      </div>
    </form>
  );
}
