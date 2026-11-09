import { POSTS, type Post } from "./mockContent";

export function filterPosts(
  params: Record<string, string | string[] | undefined>,
  source: Post[] = POSTS,
) {
  const category = typeof params.category === "string" ? params.category : undefined;
  const q = typeof params.q === "string" ? params.q.toLowerCase() : "";
  return source.filter(
    (p) =>
      (!category || p.category === category) &&
      (!q || `${p.title} ${p.creator}`.toLowerCase().includes(q)),
  );
}
