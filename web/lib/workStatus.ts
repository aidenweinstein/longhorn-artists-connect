/**
 * Whether someone is taking on work, shown on their People card and portfolio.
 * Stored as the UserProfile `workStatus` STRING field (add it to the CloudKit schema in
 * both environments):
 *   "Looking for Work" · "Busy" · "Booked until 2026-12-12" (the date is part of the text)
 * To add a status, add it here: the editor, cards and portfolio all read this list.
 */
export const WORK_STATUSES = [
  { kind: "Looking for Work", dot: "bg-emerald-500", tone: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-400", needsDate: false },
  { kind: "Booked", dot: "bg-sky-500", tone: "bg-sky-500/15 text-sky-700 dark:text-sky-400", needsDate: true },
  { kind: "Busy", dot: "bg-amber-500", tone: "bg-amber-500/15 text-amber-700 dark:text-amber-400", needsDate: false },
] as const;

export type WorkStatusKind = (typeof WORK_STATUSES)[number]["kind"];

const BOOKED = /^Booked until (\d{4}-\d{2}-\d{2})$/;
const dayFmt = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", timeZone: "UTC" });
const yearFmt = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" });

/** The stored text for a status: "Booked until 2026-12-12" for Booked, else the status itself. */
export function workStatusValue(kind: WorkStatusKind, until?: string): string {
  return kind === "Booked" ? `Booked until ${until ?? ""}` : kind;
}

/** Reads a stored status into its kind and (for Booked) its "YYYY-MM-DD" date. */
export function parseWorkStatus(value: string | undefined): { kind: WorkStatusKind; until?: string } | null {
  const v = (value ?? "").trim();
  const booked = v.match(BOOKED);
  if (booked && !Number.isNaN(Date.parse(booked[1]))) return { kind: "Booked", until: booked[1] };
  const plain = WORK_STATUSES.find((s) => !s.needsDate && s.kind === v);
  return plain ? { kind: plain.kind } : null;
}

/** A stored or submitted status, kept only if it's valid ("" otherwise). */
export function cleanWorkStatus(value: unknown): string {
  const parsed = parseWorkStatus(String(value ?? ""));
  return parsed ? workStatusValue(parsed.kind, parsed.until) : "";
}

/**
 * What to show for a status: its label and colors. Nothing for no status, and nothing
 * once a Booked date has passed (Austin time), so nobody looks booked forever.
 */
export function workStatusDisplay(value: string | undefined): { label: string; dot: string; tone: string } | null {
  const parsed = parseWorkStatus(value);
  if (!parsed) return null;
  const info = WORK_STATUSES.find((s) => s.kind === parsed.kind)!;
  if (parsed.kind !== "Booked" || !parsed.until) return { label: info.kind, dot: info.dot, tone: info.tone };
  const today = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Chicago" }).format(Date.now());
  if (parsed.until < today) return null;
  const date = new Date(`${parsed.until}T00:00:00Z`);
  const sameYear = parsed.until.slice(0, 4) === today.slice(0, 4);
  return { label: `Booked until ${(sameYear ? dayFmt : yearFmt).format(date)}`, dot: info.dot, tone: info.tone };
}
