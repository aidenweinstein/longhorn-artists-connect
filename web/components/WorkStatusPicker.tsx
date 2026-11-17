"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, useTransition } from "react";
import { saveWorkStatus } from "@/app/(app)/portfolio/edit/actions";
import { WORK_STATUSES, parseWorkStatus, workStatusDisplay, workStatusValue, type WorkStatusKind } from "@/lib/workStatus";

/** Today in Austin as "YYYY-MM-DD". */
const today = () => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Chicago" }).format(new Date());
const inTwoWeeks = () => new Date(Date.parse(`${today()}T12:00:00Z`) + 14 * 864e5).toISOString().slice(0, 10);

/**
 * The status pill on your own profile. Clicking it opens a small menu to pick
 * Looking for Work, Booked (until a date) or Busy, or to clear it. Saves right away.
 */
export default function WorkStatusPicker({ status: initial, className = "" }: { status?: string; className?: string }) {
  const router = useRouter();
  const [status, setStatus] = useState(initial ?? "");
  const [open, setOpen] = useState(false);
  const [until, setUntil] = useState(() => parseWorkStatus(initial)?.until ?? inTwoWeeks());
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const box = useRef<HTMLDivElement>(null);

  // A fresh value from the server (after saving, or elsewhere) replaces the local one.
  const [seen, setSeen] = useState(initial);
  if (seen !== initial) {
    setSeen(initial);
    setStatus(initial ?? "");
  }

  // Close on a click outside or Escape.
  useEffect(() => {
    if (!open) return;
    const onDown = (e: PointerEvent) => {
      if (!box.current?.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("pointerdown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  function save(next: string) {
    const before = status;
    setStatus(next);
    setError(null);
    setOpen(false);
    start(async () => {
      const res = await saveWorkStatus(next);
      if (!res.ok) {
        setStatus(before);
        setError(res.message);
        return;
      }
      router.refresh();
    });
  }

  function pick(kind: WorkStatusKind | null) {
    if (kind === null) return save("");
    if (kind === "Booked") return save(workStatusValue("Booked", until));
    save(workStatusValue(kind));
  }

  const shown = workStatusDisplay(status);
  const current = parseWorkStatus(status);

  return (
    <div ref={box} className={`relative inline-block ${className}`}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="menu"
        aria-expanded={open}
        title="Change your status"
        className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-semibold transition hover:brightness-110 ${
          shown ? shown.tone : "border border-dashed border-border text-muted hover:text-foreground"
        } ${pending ? "opacity-60" : ""}`}
      >
        {shown && <span aria-hidden className={`h-1.5 w-1.5 rounded-full ${shown.dot}`} />}
        {shown ? shown.label : "Set status"}
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className="h-3 w-3 opacity-70" aria-hidden>
          <path d="m6 9 6 6 6-6" />
        </svg>
      </button>

      {open && (
        <div role="menu" className="absolute left-0 top-full z-30 mt-2 w-60 rounded-xl border border-border bg-background p-1.5 shadow-xl">
          {WORK_STATUSES.map((s) => {
            const on = current?.kind === s.kind;
            return (
              <div key={s.kind}>
                <button
                  type="button"
                  role="menuitemradio"
                  aria-checked={on}
                  onClick={() => pick(s.kind)}
                  className={`flex w-full items-center gap-2 rounded-lg px-2.5 py-2 text-left text-sm hover:bg-surface ${on ? "font-semibold" : ""}`}
                >
                  <span aria-hidden className={`h-2 w-2 rounded-full ${s.dot}`} />
                  {s.needsDate ? "Booked until…" : s.kind}
                  {on && <span className="ml-auto text-brand">✓</span>}
                </button>
                {s.needsDate && (
                  <div className="flex items-center gap-2 px-2.5 pb-2 pl-7">
                    <input
                      type="date"
                      value={until}
                      min={today()}
                      onChange={(e) => setUntil(e.target.value)}
                      aria-label="Booked until"
                      className="min-w-0 flex-1 rounded-lg border border-border bg-background px-2 py-1 text-xs outline-none focus:border-brand"
                    />
                    <button
                      type="button"
                      onClick={() => pick("Booked")}
                      disabled={!until}
                      className="rounded-full bg-brand px-3 py-1 text-xs font-semibold text-white hover:brightness-110 disabled:opacity-50"
                    >
                      Set
                    </button>
                  </div>
                )}
              </div>
            );
          })}
          {current && (
            <button
              type="button"
              role="menuitem"
              onClick={() => pick(null)}
              className="mt-1 w-full rounded-lg border-t border-border px-2.5 py-2 text-left text-sm text-muted hover:bg-surface hover:text-foreground"
            >
              Clear status
            </button>
          )}
        </div>
      )}
      {error && <p className="mt-1 text-xs text-red-500">{error}</p>}
    </div>
  );
}
