import type { DiscoverItem } from "./discoverContent";

/** One thing on the Discover calendar. Times are ms; all-day entries use local midnight. */
export type CalendarEntry = {
  id: string;
  itemID: string;
  kind: "event" | "shoot" | "release";
  title: string;
  start: number;
  end?: number;
  allDay: boolean;
  location?: string;
  host?: string;
  logline?: string;
  image?: string;
  /** e.g. "Concert", "Cast & Crew Call". */
  label?: string;
};

/** Discover's projects and events as calendar entries: event showtimes, shoot starts and releases. */
export function calendarEntries(items: DiscoverItem[]): CalendarEntry[] {
  const out: CalendarEntry[] = [];
  for (const item of items) {
    if (item.kind === "event") {
      const base = {
        itemID: item.id,
        kind: "event" as const,
        title: item.title,
        location: item.location || undefined,
        host: item.host || undefined,
        logline: item.logline || undefined,
        image: item.flyerUrl,
        label: item.category,
        allDay: false,
      };
      if (item.showings?.length) {
        item.showings.forEach(([start, end], i) => out.push({ ...base, id: `${item.id}#${i}`, start, end }));
      } else if (item.startsAt) {
        out.push({ ...base, id: item.id, start: item.startsAt, end: item.endsAt });
      }
    } else {
      const base = {
        itemID: item.id,
        title: item.title,
        logline: item.logline || undefined,
        host: item.postedBy || undefined,
        image: item.posterUrl,
        label: item.projectType,
      };
      // Every shoot day, from the schedule text the app writes; the first day alone
      // (shootStart) only when the text can't be read.
      const days = parseShootSchedule(item.shootDates ?? "");
      if (days.length) {
        days.forEach((day, i) =>
          out.push({
            ...base,
            id: `${item.id}#shoot${i}`,
            kind: "shoot",
            start: day.start,
            end: day.end,
            allDay: day.allDay,
            label: days.length > 1 ? `Shoot day ${i + 1} of ${days.length}` : base.label,
          }),
        );
      } else if (item.shootStart) {
        out.push({ ...base, id: `${item.id}#shoot`, kind: "shoot", start: item.shootStart, allDay: true });
      }
      if (item.releaseDateAt) {
        out.push({ ...base, id: `${item.id}#release`, kind: "release", start: item.releaseDateAt, allDay: true });
      }
    }
  }
  return out.sort((a, b) => a.start - b.start);
}

// MARK: - Shoot schedules

/*
 * The app keeps a Cast & Crew Call's shoot days in its shoot-dates text
 * (ShootSchedule in SubmissionStore.swift): one "MMM d, yyyy h:mm a - h:mm a" entry
 * per day joined by " · ", e.g. "Jun 15, 2026 7:00 AM - 5:00 PM · Jun 16, 2026 8:30 AM - 6:00 PM".
 * Older entries have no wrap time, and older posts wrote a "start - end" range of dates.
 * Times are Austin wall-clock times.
 */

const ZONE = "America/Chicago";
const MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];

/** Milliseconds for a wall-clock time in Austin. */
function austinTime(y: number, mo: number, d: number, h: number, mi: number): number {
  const wall = Date.UTC(y, mo, d, h, mi);
  let guess = wall;
  for (let i = 0; i < 2; i++) {
    const parts = Object.fromEntries(
      new Intl.DateTimeFormat("en-US", { timeZone: ZONE, hourCycle: "h23", year: "numeric", month: "numeric", day: "numeric", hour: "numeric", minute: "numeric" })
        .formatToParts(guess)
        .map((p) => [p.type, p.value]),
    );
    const shown = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour % 24, +parts.minute);
    guess += wall - shown;
  }
  return guess;
}

function hour12(h: string, m: string, ampm: string): [number, number] {
  const hour = (+h % 12) + (ampm.toUpperCase() === "PM" ? 12 : 0);
  return [hour, +m];
}

/** "Jun 15, 2026", "June 15, 2026" or "06/15/2026" → [year, monthIndex, day]. */
function legacyDate(text: string): [number, number, number] | null {
  let m = text.trim().match(/^([A-Za-z]{3,9})\.? (\d{1,2}), (\d{4})$/);
  if (m) {
    const mo = MONTHS.indexOf(m[1].slice(0, 3).toLowerCase());
    return mo < 0 ? null : [+m[3], mo, +m[2]];
  }
  m = text.trim().match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  return m ? [+m[3], +m[1] - 1, +m[2]] : null;
}

export type ShootDay = { start: number; end?: number; allDay: boolean };

/** Every shoot day in a project's schedule text, soonest first. Empty for "TBD" and the like. */
export function parseShootSchedule(text: string): ShootDay[] {
  const trimmed = text.trim();
  if (!trimmed) return [];

  const entries = trimmed.split(" · ");
  const days: ShootDay[] = [];
  for (const entry of entries) {
    const m = entry.trim().match(/^([A-Za-z]{3}) (\d{1,2}), (\d{4}) (\d{1,2}):(\d{2}) ([AP]M)(?: - (\d{1,2}):(\d{2}) ([AP]M))?$/i);
    if (!m) break;
    const mo = MONTHS.indexOf(m[1].toLowerCase());
    if (mo < 0) break;
    const [h, mi] = hour12(m[4], m[5], m[6]);
    const start = austinTime(+m[3], mo, +m[2], h, mi);
    let end: number | undefined;
    if (m[7]) {
      const [eh, emi] = hour12(m[7], m[8], m[9]);
      end = austinTime(+m[3], mo, +m[2], eh, emi);
      if (end <= start) end = undefined;
    }
    days.push({ start, end, allDay: false });
  }
  if (days.length === entries.length) return days.sort((a, b) => a.start - b.start);

  // A legacy "start - end" range of dates: every day in it, all day (capped at 60 days).
  const [first, last] = trimmed.split(" - ");
  const a = first ? legacyDate(first) : null;
  if (!a) return [];
  const b = last ? legacyDate(last) : null;
  const from = Date.UTC(a[0], a[1], a[2]);
  const to = b ? Date.UTC(b[0], b[1], b[2]) : from;
  const out: ShootDay[] = [];
  for (let t = from; t <= to && out.length < 60; t += 864e5) out.push({ start: t, allDay: true });
  return out;
}
