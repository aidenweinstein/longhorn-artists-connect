"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { chooseStyle, recordAudition, updateAudition } from "@/app/(app)/portfolio/style/actions";
import { AUDITION_STATUSES, PROFILE_STYLES, STYLE_INFO, type AuditionStatus, type ProfileStyle } from "@/lib/profileStyle";

/** Shown on Now until the visitor has a base profile style. */
export function StylePicker({ suggested }: { suggested?: ProfileStyle }) {
  const router = useRouter();
  const [style, setStyle] = useState<ProfileStyle | null>(suggested ?? null);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  return (
    <section className="mt-6 max-w-3xl rounded-2xl border border-border p-6">
      <h2 className="text-xl font-bold">Choose your profile style</h2>
      <p className="mt-1 text-sm text-muted">It decides what Now shows you, what Nexus recommends, and how your profile looks to everyone else.</p>
      <div className="mt-4 grid gap-3 sm:grid-cols-3">
        {PROFILE_STYLES.map((s) => (
          <button
            key={s}
            type="button"
            aria-pressed={style === s}
            onClick={() => setStyle(s)}
            className={`rounded-xl border p-4 text-left transition ${style === s ? "border-brand bg-brand/10" : "border-border hover:bg-surface"}`}
          >
            <p className="font-semibold">{s}</p>
            <p className="text-xs text-brand">{STYLE_INFO[s].looksLike}</p>
            <p className="mt-1.5 text-xs text-muted">{STYLE_INFO[s].pitch}</p>
          </button>
        ))}
      </div>
      {error && <p className="mt-3 text-sm text-red-500">{error}</p>}
      <button
        type="button"
        disabled={!style || pending}
        onClick={() =>
          style &&
          start(async () => {
            const res = await chooseStyle(style);
            if (!res.ok) return setError(res.message);
            router.refresh();
          })
        }
        className="mt-4 rounded-full bg-brand px-6 py-2 text-sm font-semibold text-white hover:brightness-110 disabled:opacity-60"
      >
        {pending ? "Saving…" : "Continue"}
      </button>
    </section>
  );
}

/** "Audition" on a role that fits: logs it, then opens the project (or its sign-up link). */
export function AuditionButton({ projectID, projectTitle, role, done }: { projectID: string; projectTitle: string; role: string; done: boolean }) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  if (done) {
    return <span className="rounded-full bg-foreground/10 px-4 py-1.5 text-xs font-semibold text-muted">Auditioned</span>;
  }
  return (
    <span className="flex flex-col items-end gap-1">
      <button
        type="button"
        disabled={pending}
        onClick={() =>
          start(async () => {
            const res = await recordAudition({ projectID, projectTitle, role });
            if (!res.ok) return setError(res.message);
            router.push(`/discover/${projectID}`);
          })
        }
        className="rounded-full bg-brand px-4 py-1.5 text-xs font-semibold text-white hover:brightness-110 disabled:opacity-60"
      >
        {pending ? "…" : "Audition"}
      </button>
      {error && <span className="max-w-48 text-right text-[11px] text-red-500">{error}</span>}
    </span>
  );
}

/** Status menu for one logged audition. */
export function AuditionStatusSelect({ id, status, booked }: { id: string; status: AuditionStatus; booked: boolean }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const shown = booked ? "Booked" : status;
  const tone =
    shown === "Booked" ? "bg-brand text-white" : shown === "Callback" ? "bg-brand/15 text-brand" : shown === "Not selected" ? "border border-border text-muted" : "bg-foreground/10";
  return (
    <select
      aria-label="Audition status"
      disabled={pending || booked}
      value={shown}
      onChange={(e) => {
        const v = e.target.value;
        start(async () => {
          await updateAudition(id, v === "__remove" ? null : (v as AuditionStatus));
          router.refresh();
        });
      }}
      className={`w-fit cursor-pointer rounded-full px-2.5 py-1 text-[11px] font-semibold outline-none ${tone}`}
    >
      {AUDITION_STATUSES.map((s) => (
        <option key={s} value={s}>
          {s}
        </option>
      ))}
      <option value="__remove">Remove</option>
    </select>
  );
}
