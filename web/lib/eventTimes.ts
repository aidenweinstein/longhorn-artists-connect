import type { NexusEvent } from "./discoverContent";

/** When an event is over: the end of its last showing, else its end, else its start. */
export function eventEnd(e: NexusEvent) {
  const lastShowing = e.showings?.length ? Math.max(...e.showings.map(([, end]) => end)) : undefined;
  return lastShowing ?? e.endsAt ?? e.startsAt;
}

/** Ended before right now. Undated events count as upcoming. */
export function eventHasEnded(e: NexusEvent) {
  const end = eventEnd(e);
  return end !== undefined && end < Date.now();
}

export function eventStart(e: NexusEvent) {
  const firstShowing = e.showings?.length ? Math.min(...e.showings.map(([start]) => start)) : undefined;
  return firstShowing ?? e.startsAt ?? e.endsAt ?? Infinity;
}
