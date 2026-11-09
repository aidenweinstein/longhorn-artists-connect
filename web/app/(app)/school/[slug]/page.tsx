import { connection } from "next/server";
import { notFound } from "next/navigation";
import ContentGrid from "@/components/ContentGrid";
import { feedPosts } from "@/lib/content";
import { filterPosts } from "@/lib/filterPosts";
import { mixFeed } from "@/lib/mixFeed";
import { schoolForSlug } from "@/lib/schools";

export const instant = false;

// Another school's Home feed: only posts from that school.
export default async function SchoolHome(props: PageProps<"/school/[slug]">) {
  const { slug } = await props.params;
  const school = schoolForSlug(slug);
  if (!school) notFound();

  const params = await props.searchParams;
  await connection();
  const posts = (await feedPosts()).filter((p) => p.school === school.name);

  return (
    <>
      <h1 className="mb-3 px-1 text-xl font-bold">{school.name}</h1>
      {posts.length === 0 ? (
        <div className="mx-auto mt-16 max-w-md rounded-2xl border border-border bg-surface p-10 text-center">
          <h2 className="text-2xl font-bold">Nothing from {school.name} yet</h2>
          <p className="mt-2 text-muted">Work shared by {school.name} students will show up here.</p>
        </div>
      ) : (
        <ContentGrid posts={mixFeed(filterPosts(params, posts))} />
      )}
    </>
  );
}
