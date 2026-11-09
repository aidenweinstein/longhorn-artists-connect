"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState, useSyncExternalStore } from "react";
import type { CalendarEntry } from "@/lib/calendarEntries";

/*
 * Discover's calendar: Month, Week and Agenda views of events, shoots and releases.
 * Like Google or Apple Calendar: Today / back / forward, jump to any month, calendar
 * toggles with colors, search, "+N more" per day, a day panel, event details, and
 * Add to Google Calendar or Apple Calendar (.ics). Keys: ← → move, T today,
 * M / W / A switch views, Esc closes details.
 */

type View = "month" | "week" | "agenda";
type Kind = CalendarEntry["kind"];

const KINDS: { id: Kind; label: string; color: string }[] = [
  { id: "event", label: "Events", color: "#8b5cf6" },
  { id: "shoot", label: "Shoots", color: "#bf5700" },
  { id: "release", label: "Releases", color: "#0d9488" },
];
const COLOR = Object.fromEntries(KINDS.map((k) => [k.id, k.color])) as Record<Kind, string>;
const KIND_LABEL: Record<Kind, string> = { event: "Event", shoot: "Shoot day", release: "Release" };
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MAX_CHIPS = 3;
const STORE = "nexus:calendar";

/** The view and calendar toggles this browser last used. */
function saved(): { view?: View; hidden?: Kind[] } {
  try {
    return typeof window === "undefined" ? {} : JSON.parse(localStorage.getItem(STORE) ?? "{}");
  } catch {
    return {};
  }
}

// The calendar depends on the visitor's own clock and time zone, so it only draws
// in the browser; the server sends a placeholder of the same size.
const noop = () => () => {};
const useInBrowser = () => useSyncExternalStore(noop, () => true, () => false);

/* ---------- dates ---------- */

const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
const addDays = (d: Date, n: number) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
const addMonths = (d: Date, n: number) => new Date(d.getFullYear(), d.getMonth() + n, 1);
const dayKey = (d: Date) => `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
const sameDay = (a: Date, b: Date) => dayKey(a) === dayKey(b);
const startOfWeek = (d: Date) => addDays(startOfDay(d), -d.getDay());

/** All-day dates are stored at midnight UTC; read them as that calendar date, not shifted a day by time zone. */
function entryStart(e: CalendarEntry) {
  const d = new Date(e.start);
  return e.allDay ? new Date(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) : d;
}
function entryEnd(e: CalendarEntry) {
  if (!e.end || e.end <= e.start) return entryStart(e);
  const d = new Date(e.end);
  return e.allDay ? new Date(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) : d;
}

const timeFmt = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" });
const shortTime = (d: Date) => timeFmt.format(d).replace(":00", "").replace(" ", "").toLowerCase();
const longDate = (d: Date) => d.toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric", year: "numeric" });

function whenText(e: CalendarEntry) {
  const s = entryStart(e);
  const f = entryEnd(e);
  if (e.allDay) return sameDay(s, f) ? longDate(s) : `${longDate(s)} – ${longDate(f)}`;
  const end = e.end && e.end > e.start ? (sameDay(s, f) ? ` – ${timeFmt.format(f)}` : ` – ${longDate(f)}, ${timeFmt.format(f)}`) : "";
  return `${longDate(s)} · ${timeFmt.format(s)}${end}`;
}

/* ---------- add to calendar ---------- */

const utcStamp = (ms: number) => new Date(ms).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
const dateStamp = (d: Date) => `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, "0")}${String(d.getDate()).padStart(2, "0")}`;

function title(e: CalendarEntry) {
  return e.kind === "event" ? e.title : `${KIND_LABEL[e.kind]}: ${e.title}`;
}

function googleLink(e: CalendarEntry) {
  const dates = e.allDay
    ? `${dateStamp(entryStart(e))}/${dateStamp(addDays(entryEnd(e), 1))}`
    : `${utcStamp(e.start)}/${utcStamp(e.end && e.end > e.start ? e.end : e.start + 3_600_000)}`;
  const q = new URLSearchParams({ action: "TEMPLATE", text: title(e), dates, details: e.logline ?? "", location: e.location ?? "" });
  return `https://calendar.google.com/calendar/render?${q}`;
}

const icsEscape = (s: string) => s.replace(/\\/g, "\\\\").replace(/\n/g, "\\n").replace(/[,;]/g, (m) => `\\${m}`);

function icsEvent(e: CalendarEntry) {
  const when = e.allDay
    ? [`DTSTART;VALUE=DATE:${dateStamp(entryStart(e))}`, `DTEND;VALUE=DATE:${dateStamp(addDays(entryEnd(e), 1))}`]
    : [`DTSTART:${utcStamp(e.start)}`, `DTEND:${utcStamp(e.end && e.end > e.start ? e.end : e.start + 3_600_000)}`];
  return [
    "BEGIN:VEVENT",
    `UID:${e.id}@nexusbylac.com`,
    `DTSTAMP:${utcStamp(Date.now())}`,
    ...when,
    `SUMMARY:${icsEscape(title(e))}`,
    e.location ? `LOCATION:${icsEscape(e.location)}` : "",
    e.logline ? `DESCRIPTION:${icsEscape(e.logline)}` : "",
    "END:VEVENT",
  ].filter(Boolean);
}

function downloadIcs(entries: CalendarEntry[], name: string) {
  const body = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Nexus//Discover//EN", "CALSCALE:GREGORIAN", ...entries.flatMap(icsEvent), "END:VCALENDAR"].join("\r\n");
  const url = URL.createObjectURL(new Blob([body], { type: "text/calendar" }));
  const a = Object.assign(document.createElement("a"), { href: url, download: `${name.replace(/[^\w-]+/g, "-").toLowerCase()}.ics` });
  a.click();
  URL.revokeObjectURL(url);
}

/* ---------- pieces ---------- */

function Chip({ e, day, onOpen }: { e: CalendarEntry; day: Date; onOpen: (e: CalendarEntry) => void }) {
  const s = entryStart(e);
  const continues = !sameDay(s, day);
  const timed = !e.allDay && !continues;
  return (
    <button
      type="button"
      onClick={(ev) => {
        ev.stopPropagation();
        onOpen(e);
      }}
      title={`${title(e)}${timed ? ` · ${timeFmt.format(s)}` : ""}`}
      className="flex w-full min-w-0 items-center gap-1 rounded px-1 py-px text-left text-[11px] leading-tight hover:bg-foreground/10"
      style={timed ? undefined : { backgroundColor: COLOR[e.kind], color: "white" }}
    >
      {timed && <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: COLOR[e.kind] }} />}
      {timed && <span className="shrink-0 text-muted">{shortTime(s)}</span>}
      <span className="truncate font-medium">
        {continues && "↳ "}
        {e.kind === "event" ? e.title : `${e.kind === "shoot" ? "🎬" : "★"} ${e.title}`}
      </span>
    </button>
  );
}

function Detail({ e, onClose }: { e: CalendarEntry; onClose: () => void }) {
  return (
    <div className="rounded-xl border border-border bg-background p-4 shadow-sm">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide" style={{ color: COLOR[e.kind] }}>
            <span className="h-2 w-2 rounded-full" style={{ backgroundColor: COLOR[e.kind] }} />
            {KIND_LABEL[e.kind]}
            {e.label && <span className="text-muted">· {e.label}</span>}
          </p>
          <h3 className="mt-1 text-lg leading-tight">{e.title}</h3>
        </div>
        <button type="button" onClick={onClose} aria-label="Close" className="rounded-full p-1 text-muted hover:bg-surface hover:text-foreground">
          ✕
        </button>
      </div>
      {e.image && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={e.image} alt="" className="mt-3 max-h-56 w-auto rounded-md" />
      )}
      <dl className="mt-3 space-y-1.5 text-sm">
        <div className="flex gap-2">
          <dt className="w-5 shrink-0 text-muted">🕑</dt>
          <dd>{whenText(e)}</dd>
        </div>
        {e.location && (
          <div className="flex gap-2">
            <dt className="w-5 shrink-0 text-muted">📍</dt>
            <dd>{e.location}</dd>
          </div>
        )}
        {e.host && (
          <div className="flex gap-2">
            <dt className="w-5 shrink-0 text-muted">👤</dt>
            <dd>{e.host}</dd>
          </div>
        )}
      </dl>
      {e.logline && <p className="mt-3 line-clamp-4 text-sm text-foreground/85">{e.logline}</p>}
      <div className="mt-4 flex flex-wrap gap-2">
        <Link href={`/discover/${e.itemID}`} className="rounded-full bg-brand px-4 py-1.5 text-sm font-semibold text-white hover:brightness-110">
          Open
        </Link>
        <a href={googleLink(e)} target="_blank" rel="noopener noreferrer" className="rounded-full border border-border px-4 py-1.5 text-sm font-semibold hover:bg-surface">
          Google Calendar
        </a>
        <button type="button" onClick={() => downloadIcs([e], e.title)} className="rounded-full border border-border px-4 py-1.5 text-sm font-semibold hover:bg-surface">
          Apple Calendar (.ics)
        </button>
      </div>
    </div>
  );
}

/* ---------- calendar ---------- */

export default function DiscoverCalendar({ entries }: { entries: CalendarEntry[] }) {
  if (!useInBrowser()) return <div aria-hidden className="h-[44rem] animate-pulse rounded-xl bg-surface" />;
  return <Calendar entries={entries} />;
}

function Calendar({ entries }: { entries: CalendarEntry[] }) {
  const [today, setToday] = useState(() => startOfDay(new Date()));
  const [cursor, setCursor] = useState(today);
  const [view, setView] = useState<View>(() => saved().view ?? "month");
  const [selectedDay, setSelectedDay] = useState<Date>(today);
  const [open, setOpen] = useState<CalendarEntry | null>(null);
  const [hidden, setHidden] = useState<Kind[]>(() => (Array.isArray(saved().hidden) ? saved().hidden! : []));
  const [query, setQuery] = useState("");

  useEffect(() => {
    // Keep "today" right if the page stays open past midnight.
    const t = setInterval(() => setToday(startOfDay(new Date())), 60_000);
    return () => clearInterval(t);
  }, []);
  // Remember view and calendar toggles for this browser.
  useEffect(() => {
    try {
      localStorage.setItem(STORE, JSON.stringify({ view, hidden }));
    } catch {}
  }, [view, hidden]);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return entries.filter(
      (e) => !hidden.includes(e.kind) && (!q || `${e.title} ${e.location ?? ""} ${e.host ?? ""} ${e.logline ?? ""}`.toLowerCase().includes(q)),
    );
  }, [entries, hidden, query]);

  // Each day's entries, multi-day ones on every day they cover (up to 60 days).
  const byDay = useMemo(() => {
    const map = new Map<string, CalendarEntry[]>();
    for (const e of visible) {
      const last = entryEnd(e);
      for (let d = startOfDay(entryStart(e)), n = 0; d <= last && n < 60; d = addDays(d, 1), n++) {
        const k = dayKey(d);
        map.set(k, [...(map.get(k) ?? []), e]);
      }
    }
    for (const list of map.values()) list.sort((a, b) => Number(b.allDay) - Number(a.allDay) || a.start - b.start);
    return map;
  }, [visible]);
  const on = useCallback((d: Date) => byDay.get(dayKey(d)) ?? [], [byDay]);

  const move = useCallback(
    (dir: number) => {
      setOpen(null);
      setCursor((c) => (view === "week" ? addDays(c, 7 * dir) : addMonths(c, dir)));
    },
    [view],
  );
  const goToday = useCallback(() => {
    setCursor(today);
    setSelectedDay(today);
    setOpen(null);
  }, [today]);

  useEffect(() => {
    const onKey = (ev: KeyboardEvent) => {
      const t = ev.target as HTMLElement;
      if (ev.metaKey || ev.ctrlKey || ev.altKey || t.closest("input, textarea, select, [contenteditable]")) return;
      if (ev.key === "ArrowLeft") move(-1);
      else if (ev.key === "ArrowRight") move(1);
      else if (ev.key === "t" || ev.key === "T") goToday();
      else if (ev.key === "m") setView("month");
      else if (ev.key === "w") setView("week");
      else if (ev.key === "a") setView("agenda");
      else if (ev.key === "Escape") setOpen(null);
      else return;
      ev.preventDefault();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [move, goToday]);

  const heading =
    view === "week"
      ? (() => {
          const s = startOfWeek(cursor);
          const f = addDays(s, 6);
          const mon = (d: Date) => d.toLocaleDateString("en-US", { month: "short" });
          // "Nov 1 – 7, 2026", "Oct 29 – Nov 4, 2026", "Dec 28, 2026 – Jan 3, 2027"
          if (s.getFullYear() !== f.getFullYear()) return `${mon(s)} ${s.getDate()}, ${s.getFullYear()} – ${mon(f)} ${f.getDate()}, ${f.getFullYear()}`;
          return s.getMonth() === f.getMonth()
            ? `${mon(s)} ${s.getDate()} – ${f.getDate()}, ${f.getFullYear()}`
            : `${mon(s)} ${s.getDate()} – ${mon(f)} ${f.getDate()}, ${f.getFullYear()}`;
        })()
      : cursor.toLocaleDateString("en-US", { month: "long", year: "numeric" });

  function pickDay(d: Date) {
    setSelectedDay(d);
    setOpen(null);
  }

  /* --- month --- */
  const monthStart = new Date(cursor.getFullYear(), cursor.getMonth(), 1);
  const gridStart = startOfWeek(monthStart);
  const weeks = Math.ceil((monthStart.getDay() + new Date(cursor.getFullYear(), cursor.getMonth() + 1, 0).getDate()) / 7);
  const monthDays = Array.from({ length: weeks * 7 }, (_, i) => addDays(gridStart, i));
  const monthCount = visible.filter((e) => {
    const s = entryStart(e);
    return s.getFullYear() === cursor.getFullYear() && s.getMonth() === cursor.getMonth();
  }).length;

  /* --- agenda: the next 90 days from the cursor's month (or today, if later) --- */
  const agendaStart = view === "agenda" ? (monthStart < today && today < addMonths(monthStart, 1) ? today : monthStart) : today;
  const agendaDays = Array.from({ length: 90 }, (_, i) => addDays(agendaStart, i)).filter((d) => on(d).length > 0);

  const dayList = on(selectedDay);

  return (
    <div className="flex flex-col gap-5 lg:flex-row">
      <div className="min-w-0 flex-1">
        {/* Toolbar */}
        <div className="flex flex-wrap items-center gap-2">
          <button type="button" onClick={goToday} className="rounded-full border border-border px-4 py-1.5 text-sm font-semibold hover:bg-surface" title="Today (T)">
            Today
          </button>
          <div className="flex">
            <button type="button" onClick={() => move(-1)} aria-label="Previous" title="Previous (←)" className="rounded-full p-2 hover:bg-surface">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                <path d="m15 18-6-6 6-6" />
              </svg>
            </button>
            <button type="button" onClick={() => move(1)} aria-label="Next" title="Next (→)" className="rounded-full p-2 hover:bg-surface">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                <path d="m9 18 6-6-6-6" />
              </svg>
            </button>
          </div>
          <h2 className="mr-auto text-xl sm:text-2xl">{heading}</h2>

          <input
            type="month"
            aria-label="Jump to month"
            value={`${cursor.getFullYear()}-${String(cursor.getMonth() + 1).padStart(2, "0")}`}
            onChange={(ev) => {
              const [y, m] = ev.target.value.split("-").map(Number);
              if (y && m) setCursor(new Date(y, m - 1, 1));
            }}
            className="rounded-full border border-border bg-background px-3 py-1.5 text-sm"
          />
          <div role="group" aria-label="View" className="flex rounded-full bg-surface p-1">
            {(["month", "week", "agenda"] as View[]).map((v) => (
              <button
                key={v}
                type="button"
                onClick={() => setView(v)}
                aria-pressed={view === v}
                title={`${v[0].toUpperCase()}${v.slice(1)} (${v[0].toUpperCase()})`}
                className={`rounded-full px-3 py-1 text-sm font-medium capitalize ${view === v ? "bg-brand text-white shadow-sm" : "text-muted hover:text-foreground"}`}
              >
                {v}
              </button>
            ))}
          </div>
        </div>

        {/* Calendars and search */}
        <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-2">
          {KINDS.map((k) => {
            const shown = !hidden.includes(k.id);
            return (
              <label key={k.id} className="flex cursor-pointer select-none items-center gap-1.5 text-sm">
                <input
                  type="checkbox"
                  checked={shown}
                  onChange={() => setHidden((h) => (shown ? [...h, k.id] : h.filter((x) => x !== k.id)))}
                  className="h-4 w-4 rounded"
                  style={{ accentColor: k.color }}
                />
                <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: k.color }} />
                {k.label}
              </label>
            );
          })}
          <input
            type="search"
            value={query}
            onChange={(ev) => setQuery(ev.target.value)}
            placeholder="Search calendar"
            className="ml-auto w-full rounded-full border border-border bg-background px-4 py-1.5 text-sm sm:w-56"
          />
          <button
            type="button"
            onClick={() => downloadIcs(visible.filter((e) => (e.end ?? e.start) >= Date.now() - 86_400_000), "nexus-discover")}
            className="text-sm font-semibold text-brand hover:underline"
            title="Download everything shown as an .ics file for Apple, Google or Outlook"
          >
            Export .ics
          </button>
        </div>

        {/* Month */}
        {view === "month" && (
          <div className="mt-4 overflow-hidden rounded-xl border border-border">
            <div className="grid grid-cols-7 border-b border-border bg-surface text-center text-[11px] font-semibold uppercase tracking-wide text-muted">
              {WEEKDAYS.map((w) => (
                <div key={w} className="py-2">
                  {w}
                </div>
              ))}
            </div>
            <div className="grid grid-cols-7">
              {monthDays.map((d, i) => {
                const list = on(d);
                const inMonth = d.getMonth() === cursor.getMonth();
                const isToday = sameDay(d, today);
                const isSelected = sameDay(d, selectedDay);
                return (
                  <div
                    key={dayKey(d)}
                    role="button"
                    tabIndex={0}
                    onClick={() => pickDay(d)}
                    onKeyDown={(ev) => ev.key === "Enter" && pickDay(d)}
                    className={`min-h-[6.5rem] cursor-pointer p-1 outline-none transition-colors sm:min-h-[7.5rem] ${i % 7 ? "border-l" : ""} ${i >= 7 ? "border-t" : ""} border-border ${
                      isSelected ? "bg-brand/[0.07]" : "hover:bg-surface"
                    } ${inMonth ? "" : "bg-foreground/[0.025]"}`}
                  >
                    <div className="mb-0.5 flex justify-center sm:justify-start">
                      <span
                        className={`flex h-6 min-w-6 items-center justify-center rounded-full px-1 text-xs font-semibold ${
                          isToday ? "bg-brand text-white" : inMonth ? "" : "text-muted/60"
                        }`}
                      >
                        {d.getDate() === 1 ? d.toLocaleDateString("en-US", { month: "short", day: "numeric" }) : d.getDate()}
                      </span>
                    </div>
                    <div className="space-y-0.5">
                      {list.slice(0, MAX_CHIPS).map((e) => (
                        <Chip key={e.id} e={e} day={d} onOpen={(x) => { setSelectedDay(d); setOpen(x); }} />
                      ))}
                      {list.length > MAX_CHIPS && (
                        <button
                          type="button"
                          onClick={(ev) => {
                            ev.stopPropagation();
                            pickDay(d);
                          }}
                          className="w-full rounded px-1 text-left text-[11px] font-semibold text-muted hover:bg-foreground/10 hover:text-foreground"
                        >
                          +{list.length - MAX_CHIPS} more
                        </button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Week */}
        {view === "week" && (
          <div className="mt-4 grid grid-cols-1 overflow-hidden rounded-xl border border-border sm:grid-cols-7">
            {Array.from({ length: 7 }, (_, i) => addDays(startOfWeek(cursor), i)).map((d, i) => {
              const list = on(d);
              const isToday = sameDay(d, today);
              return (
                <div
                  key={dayKey(d)}
                  onClick={() => pickDay(d)}
                  className={`min-h-[8rem] cursor-pointer p-2 sm:min-h-[22rem] ${i ? "border-t sm:border-l sm:border-t-0" : ""} border-border ${
                    sameDay(d, selectedDay) ? "bg-brand/[0.07]" : "hover:bg-surface"
                  }`}
                >
                  <div className="mb-2 flex items-baseline gap-2 sm:flex-col sm:items-center sm:gap-0">
                    <span className="text-[11px] font-semibold uppercase tracking-wide text-muted">{WEEKDAYS[d.getDay()]}</span>
                    <span className={`flex h-8 w-8 items-center justify-center rounded-full text-lg font-semibold ${isToday ? "bg-brand text-white" : ""}`}>{d.getDate()}</span>
                  </div>
                  <div className="space-y-1">
                    {list.map((e) => (
                      <button
                        key={e.id}
                        type="button"
                        onClick={(ev) => {
                          ev.stopPropagation();
                          setSelectedDay(d);
                          setOpen(e);
                        }}
                        className="block w-full rounded-md border-l-[3px] bg-surface px-2 py-1 text-left text-xs hover:bg-foreground/10"
                        style={{ borderColor: COLOR[e.kind] }}
                      >
                        <span className="block text-[11px] text-muted">{e.allDay || !sameDay(entryStart(e), d) ? KIND_LABEL[e.kind] : timeFmt.format(entryStart(e))}</span>
                        <span className="line-clamp-2 font-semibold">{e.title}</span>
                      </button>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* Agenda */}
        {view === "agenda" && (
          <div className="mt-4 overflow-hidden rounded-xl border border-border">
            {agendaDays.length === 0 ? (
              <p className="p-10 text-center text-sm text-muted">Nothing scheduled in the next 90 days.</p>
            ) : (
              agendaDays.map((d, i) => (
                <div key={dayKey(d)} className={`flex gap-4 p-3 ${i ? "border-t border-border" : ""}`}>
                  <button type="button" onClick={() => pickDay(d)} className="w-16 shrink-0 text-left">
                    <span className={`block text-2xl font-semibold leading-none ${sameDay(d, today) ? "text-brand" : ""}`}>{d.getDate()}</span>
                    <span className="text-[11px] font-semibold uppercase text-muted">
                      {d.toLocaleDateString("en-US", { month: "short" })} · {WEEKDAYS[d.getDay()]}
                    </span>
                  </button>
                  <div className="min-w-0 flex-1 space-y-1">
                    {on(d).map((e) => (
                      <button
                        key={e.id}
                        type="button"
                        onClick={() => {
                          setSelectedDay(d);
                          setOpen(e);
                        }}
                        className="flex w-full items-center gap-3 rounded-md px-2 py-1 text-left text-sm hover:bg-surface"
                      >
                        <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ backgroundColor: COLOR[e.kind] }} />
                        <span className="w-24 shrink-0 text-muted">{e.allDay ? KIND_LABEL[e.kind] : timeFmt.format(entryStart(e))}</span>
                        <span className="min-w-0 truncate font-medium">{e.title}</span>
                        {e.location && <span className="hidden min-w-0 truncate text-muted md:inline">· {e.location}</span>}
                      </button>
                    ))}
                  </div>
                </div>
              ))
            )}
          </div>
        )}

        <p className="mt-2 text-xs text-muted">
          {view === "month" && `${monthCount} ${monthCount === 1 ? "item" : "items"} this month · `}
          Keys: ← → to move, T for today, M W A to switch views.
        </p>

        {/* The picked day (today by default), with posters */}
        <section className="mt-8">
          <div className="flex flex-wrap items-baseline gap-x-3">
            <h2 className="text-2xl">{sameDay(selectedDay, today) ? "Today" : WEEKDAYS[selectedDay.getDay()]}</h2>
            <p className="text-muted">{selectedDay.toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" })}</p>
            {!sameDay(selectedDay, today) && (
              <button type="button" onClick={goToday} className="text-sm font-semibold text-brand hover:underline">
                Back to today
              </button>
            )}
          </div>
          {dayList.length === 0 ? (
            <p className="mt-3 rounded-xl border border-dashed border-border p-8 text-center text-sm text-muted">Nothing on this day.</p>
          ) : (
            <div className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
              {dayList.map((e) => (
                <button
                  key={e.id}
                  type="button"
                  onClick={() => setOpen(e)}
                  className={`flex gap-4 overflow-hidden rounded-xl bg-surface text-left transition-colors hover:bg-foreground/10 ${
                    open?.id === e.id ? "ring-2 ring-brand" : ""
                  }`}
                >
                  {e.image ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={e.image} alt="" loading="lazy" className="h-auto w-28 shrink-0 self-start sm:w-32" />
                  ) : (
                    <span
                      aria-hidden
                      className="aspect-[2/3] w-28 shrink-0 sm:w-32"
                      style={{ background: `linear-gradient(135deg, #1c1917, ${COLOR[e.kind]})` }}
                    />
                  )}
                  <span className="flex min-w-0 flex-1 flex-col py-3 pr-4">
                    <span className="flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide" style={{ color: COLOR[e.kind] }}>
                      <span className="h-2 w-2 rounded-full" style={{ backgroundColor: COLOR[e.kind] }} />
                      {e.allDay ? KIND_LABEL[e.kind] : `${timeFmt.format(entryStart(e))}${e.end && e.end > e.start ? ` – ${timeFmt.format(entryEnd(e))}` : ""}`}
                    </span>
                    <span className="mt-1 line-clamp-2 font-semibold leading-snug">{e.title}</span>
                    {e.logline && <span className="mt-1 line-clamp-2 text-sm text-muted">{e.logline}</span>}
                    <span className="mt-auto pt-2 text-sm text-muted">
                      {[e.location, e.host].filter(Boolean).join(" · ")}
                    </span>
                  </span>
                </button>
              ))}
            </div>
          )}
        </section>
      </div>

      {/* Side panel: details of the picked item */}
      {open && (
        <aside className="w-full shrink-0 lg:sticky lg:top-3 lg:w-80 lg:self-start">
          <Detail e={open} onClose={() => setOpen(null)} />
        </aside>
      )}
    </div>
  );
}
