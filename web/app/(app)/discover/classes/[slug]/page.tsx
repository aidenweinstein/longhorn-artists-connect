import Link from "next/link";
import { notFound } from "next/navigation";
import DiscoverGrid from "@/components/DiscoverGrid";
import PostGrid from "@/components/PostGrid";
import { discoverItems, feedPosts } from "@/lib/content";
import type { DiscoverItem, Project } from "@/lib/discoverContent";
import { CLASSES, classFilms, classForSlug, classProjects } from "@/lib/productionClasses";

// Reads the address and live data per request, so this route blocks until it renders.
export const instant = false;

export function generateStaticParams() {
  return CLASSES.map((c) => ({ slug: c.slug }));
}

/** One production class: the films posted under it, then its projects on Discover. */
export default async function ClassPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const cls = classForSlug(slug);
  if (!cls) notFound();

  const [posts, items] = await Promise.all([feedPosts(), discoverItems().catch((): DiscoverItem[] => [])]);
  const films = classFilms(cls, posts);
  const projects = classProjects(cls, items.filter((i): i is Project => i.kind === "project"));

  return (
    <div className="space-y-8">
      <div>
        <Link href="/discover/classes" className="text-sm font-medium text-muted hover:text-foreground">
          ← All classes
        </Link>
        <p className="mt-3 text-sm font-semibold text-brand">{cls.code}</p>
        <h1 className="text-4xl font-bold leading-tight">{cls.name}</h1>
      </div>

      <section>
        <h2 className="mb-3 text-2xl font-bold">Films</h2>
        {films.length ? <PostGrid posts={films} /> : <p className="text-sm text-muted">No films posted under this class yet.</p>}
      </section>

      {projects.length > 0 && (
        <section>
          <h2 className="mb-3 text-2xl font-bold">Projects</h2>
          <DiscoverGrid items={projects} />
        </section>
      )}
    </div>
  );
}
