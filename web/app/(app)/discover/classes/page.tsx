import Link from "next/link";
import GroupsToggle from "@/components/GroupsToggle";
import { discoverItems, feedPosts } from "@/lib/content";
import type { DiscoverItem, Project } from "@/lib/discoverContent";
import { CLASSES, classFilms, classProjects } from "@/lib/productionClasses";

// Reads live data per request, so this route blocks until it renders.
export const instant = false;

const count = (n: number, one: string) => `${n} ${one}${n === 1 ? "" : "s"}`;

/** Every production class (the app's "Class or Org" classes). Each card opens the class's films and projects. */
export default async function Classes() {
  const [posts, items] = await Promise.all([feedPosts(), discoverItems().catch((): DiscoverItem[] => [])]);
  const projects = items.filter((i): i is Project => i.kind === "project");
  return (
    <div>
      <GroupsToggle on="classes" />
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
      {CLASSES.map((c) => (
        <Link
          key={c.slug}
          href={`/discover/classes/${c.slug}`}
          className="flex min-h-24 flex-col justify-center rounded-[20px] border border-border bg-surface px-5 py-4 transition-transform duration-200 hover:scale-[1.015]"
        >
          <p className="text-sm font-semibold text-brand">{c.code}</p>
          <h2 className="line-clamp-1 text-xl font-bold leading-tight">{c.name}</h2>
          <p className="mt-0.5 text-sm text-muted">
            {count(classFilms(c, posts).length, "film")} · {count(classProjects(c, projects).length, "project")}
          </p>
        </Link>
      ))}
      </div>
    </div>
  );
}
