import DiscoverGrid from "@/components/DiscoverGrid";
import { discoverItems } from "@/lib/content";
import { discoverMatches } from "@/lib/search";

// Filtered per request by ?q, so this route blocks until it renders.
export const instant = false;

/** Every projects on Discover as cards (Discover itself is the calendar). */
export default async function DiscoverProjects(props: PageProps<"/discover/projects">) {
  const params = await props.searchParams;
  const q = typeof params.q === "string" ? params.q : "";
  const items = (await discoverItems()).filter(
    (i) => i.kind === "project" && discoverMatches(i, q),
  );
  return <DiscoverGrid items={items} />;
}
