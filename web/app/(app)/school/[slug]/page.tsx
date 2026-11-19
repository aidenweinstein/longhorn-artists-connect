import { connection } from "next/server";
import { notFound } from "next/navigation";
import type { CSSProperties } from "react";
import PostGrid from "@/components/PostGrid";
import PostLinkScope from "@/components/PostLinkScope";
import { feedPosts } from "@/lib/content";
import { filterPosts } from "@/lib/filterPosts";
import { mixFeed, newFeedSeed } from "@/lib/mixFeed";
import { creditForSchool } from "@/lib/schoolCredit";
import { schoolForSlug, schoolSlugForName } from "@/lib/schools";

export const instant = false;

// A school's feed: only posts by people at that school.
export default async function SchoolHome(props: PageProps<"/school/[slug]">) {
  const { slug } = await props.params;
  const school = schoolForSlug(slug);
  if (!school) notFound();

  const params = await props.searchParams;
  await connection();
  // Posts made or credited by people at this school (an early app post with no school is UT Austin's).
  // Each card credits someone from this school, e.g. "Sound by …" when the director is from elsewhere.
  const posts = (await feedPosts())
    .filter((p) => (p.schoolSlugs ?? [schoolSlugForName(p.school)]).includes(school.slug))
    .map((p) => creditForSchool(p, school.slug));

  return (
    // The school's secondary color (gold for USC, Berkeley and Michigan) stands in for the brand color on its feed, e.g. preview progress bars.
    <div style={{ "--brand": school.accent } as CSSProperties}>
      <h1 className="mb-3 px-1 text-xl font-bold">{school.name}</h1>
      {posts.length === 0 ? (
        <div className="mx-auto mt-16 max-w-md rounded-2xl border border-border bg-surface p-10 text-center">
          <h2 className="text-2xl font-bold">Nothing from {school.name} yet</h2>
          <p className="mt-2 text-muted">Come on {school.mascot}, show us what you&apos;ve got!</p>
        </div>
      ) : (
        // Posts open under this school's address, so they keep its colors.
        <PostLinkScope school={school.slug}>
          <PostGrid posts={mixFeed(filterPosts(params, posts), newFeedSeed())} />
        </PostLinkScope>
      )}
    </div>
  );
}
