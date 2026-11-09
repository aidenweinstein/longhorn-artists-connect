import DiscoverGrid from "@/components/DiscoverGrid";
import { discoverItems } from "@/lib/content";

// Filtered per request by ?q, so this route blocks until it renders.
export const instant = false;

/** Every projects on Discover as cards (Discover itself is the calendar). */
export default async function DiscoverProjects(props: PageProps<"/discover/projects">) {
  const params = await props.searchParams;
  const q = typeof params.q === "string" ? params.q.toLowerCase() : "";
  const items = (await discoverItems()).filter(
    (i) => i.kind === "project" && (!q || `${i.title} ${i.logline}`.toLowerCase().includes(q)),
  );
  return (
    <div>
      <h1 className="mb-4 text-3xl font-bold">Projects</h1>
      <DiscoverGrid items={items} />
    </div>
  );
}
