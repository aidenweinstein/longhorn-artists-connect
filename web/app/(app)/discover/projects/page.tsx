import DiscoverGrid from "@/components/DiscoverGrid";
import { currentSession } from "@/lib/account";
import { discoverItems } from "@/lib/content";
import { HOME_SCHOOL, schoolForID } from "@/lib/schools";
import { discoverMatches } from "@/lib/search";

// Filtered per request by ?q, so this route blocks until it renders.
export const instant = false;

/** The projects on Discover as cards: only ones from the signed-in person's school. */
export default async function DiscoverProjects(props: PageProps<"/discover/projects">) {
  const [params, session, all] = await Promise.all([props.searchParams, currentSession(), discoverItems()]);
  const q = typeof params.q === "string" ? params.q : "";
  const school = schoolForID(session?.schoolID).slug;
  // A project with no school worked out (sample data) counts as the home school's, UT Austin.
  const items = all.filter(
    (i) => i.kind === "project" && (i.schoolSlugs ?? [HOME_SCHOOL.slug]).includes(school) && discoverMatches(i, q),
  );
  return <DiscoverGrid items={items} />;
}
