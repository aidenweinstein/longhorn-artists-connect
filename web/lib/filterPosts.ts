import { POSTS, type Post } from "./mockContent";
import { postMatches } from "./search";

export function filterPosts(
  params: Record<string, string | string[] | undefined>,
  source: Post[] = POSTS,
) {
  const category = typeof params.category === "string" ? params.category : undefined;
  const q = typeof params.q === "string" ? params.q : "";
  return source.filter((p) => (!category || p.category === category) && postMatches(p, q));
}
