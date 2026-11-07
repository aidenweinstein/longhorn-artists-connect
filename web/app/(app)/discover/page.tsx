import DiscoverCalendar from "@/components/DiscoverCalendar";
import { calendarEntries } from "@/lib/calendarEntries";
import { discoverItems } from "@/lib/content";

// Filtered per request by ?type and ?q, so this route blocks until it renders.
export const instant = false;

/** Discover is the calendar of shoots, releases and events. Projects and Events have their own grid pages. */
export default async function Discover(props: PageProps<"/discover">) {
  const params = await props.searchParams;
  const type = typeof params.type === "string" ? params.type : undefined;
  const q = typeof params.q === "string" ? params.q.toLowerCase() : "";
  const items = (await discoverItems()).filter(
    (i) => (!type || i.kind === type) && (!q || `${i.title} ${i.logline}`.toLowerCase().includes(q)),
  );
  return <DiscoverCalendar entries={calendarEntries(items)} />;
}
