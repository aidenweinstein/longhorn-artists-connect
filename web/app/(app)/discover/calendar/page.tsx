import DiscoverCalendar from "@/components/DiscoverCalendar";
import { calendarEntries } from "@/lib/calendarEntries";
import { discoverItems } from "@/lib/content";
import { discoverMatches } from "@/lib/search";

// Filtered per request by ?type and ?q, so this route blocks until it renders.
export const instant = false;

/** The calendar of shoots, releases and events, reached from its own button on Discover's bar. */
export default async function DiscoverCalendarPage(props: PageProps<"/discover/calendar">) {
  const params = await props.searchParams;
  const type = typeof params.type === "string" ? params.type : undefined;
  const q = typeof params.q === "string" ? params.q : "";
  const items = (await discoverItems()).filter(
    (i) => (!type || i.kind === type) && discoverMatches(i, q),
  );
  return <DiscoverCalendar entries={calendarEntries(items)} />;
}
