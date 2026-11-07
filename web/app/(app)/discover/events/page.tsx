import Link from "next/link";
import DiscoverGrid from "@/components/DiscoverGrid";
import { discoverItems } from "@/lib/content";
import type { NexusEvent } from "@/lib/discoverContent";

// Filtered per request by ?q and ?past, so this route blocks until it renders.
export const instant = false;

/** When an event is over: the end of its last showing, else its end, else its start. Undated events count as upcoming. */
function endsAt(e: NexusEvent) {
  const lastShowing = e.showings?.length ? Math.max(...e.showings.map(([, end]) => end)) : undefined;
  return lastShowing ?? e.endsAt ?? e.startsAt;
}

/** Ended before right now. */
function hasEnded(e: NexusEvent) {
  const end = endsAt(e);
  return end !== undefined && end < Date.now();
}

function startsAt(e: NexusEvent) {
  const firstShowing = e.showings?.length ? Math.min(...e.showings.map(([start]) => start)) : undefined;
  return firstShowing ?? e.startsAt ?? e.endsAt ?? Infinity;
}

/**
 * Events on Discover as cards (Discover itself is the calendar). Shows only events
 * that haven't ended yet, soonest first; "Past events" switches to the ones that
 * have, most recent first.
 */
export default async function DiscoverEvents(props: PageProps<"/discover/events">) {
  const params = await props.searchParams;
  const q = typeof params.q === "string" ? params.q.toLowerCase() : "";
  const past = params.past === "1";

  const events = (await discoverItems()).filter(
    (i): i is NexusEvent => i.kind === "event" && (!q || `${i.title} ${i.logline}`.toLowerCase().includes(q)),
  );
  const shown = past
    ? events.filter(hasEnded).sort((a, b) => (endsAt(b) ?? 0) - (endsAt(a) ?? 0))
    : events.filter((e) => !hasEnded(e)).sort((a, b) => startsAt(a) - startsAt(b));

  const toggle = new URLSearchParams();
  if (q) toggle.set("q", q);
  if (!past) toggle.set("past", "1");
  const toggleHref = `/discover/events${toggle.size ? `?${toggle}` : ""}`;

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-3xl font-bold">{past ? "Past Events" : "Events"}</h1>
        <Link
          href={toggleHref}
          className="rounded-full border border-border px-4 py-1.5 text-sm font-medium text-muted transition hover:bg-surface hover:text-foreground"
        >
          {past ? "Upcoming events" : "Past events"}
        </Link>
      </div>
      {shown.length === 0 ? (
        <p className="py-20 text-center text-muted">{past ? "No past events." : "No upcoming events."}</p>
      ) : (
        <DiscoverGrid items={shown} />
      )}
    </div>
  );
}
