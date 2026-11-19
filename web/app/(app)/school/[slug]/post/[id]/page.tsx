import { connection } from "next/server";
import { notFound, redirect } from "next/navigation";
import PostView from "../../../../post/[id]/PostView";
import { findPost } from "@/lib/content";
import { schoolForSlug, schoolSlugForName } from "@/lib/schools";

export const instant = false;

// A post opened from a school's feed: the same page as /post/<id>, but the address keeps
// the school, so the top bar stays in its colors and the sidebar keeps it selected.
export default async function SchoolPost(props: PageProps<"/school/[slug]/post/[id]">) {
  const { slug, id } = await props.params;
  const school = schoolForSlug(slug);
  if (!school) notFound();
  await connection();
  const post = await findPost(id);
  if (!post) notFound();
  // Not this school's post: show it at its plain address instead.
  if (!(post.schoolSlugs ?? [schoolSlugForName(post.school)]).includes(school.slug)) redirect(`/post/${id}`);
  return <PostView id={id} school={school} />;
}
