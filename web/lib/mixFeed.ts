import type { Post } from "./mockContent";

/**
 * A fresh order on every visit that still leans toward newer posts: each post draws
 * a random key weighted by how recent it is (newest weight 1, oldest ~0.25), and the
 * feed sorts by that key. Posts arrive newest-first.
 */
export function mixFeed(posts: Post[]): Post[] {
  const n = posts.length;
  return posts
    .map((post, i) => {
      const weight = 1 - (0.75 * i) / Math.max(1, n - 1);
      return { post, key: Math.random() ** (1 / weight) };
    })
    .sort((a, b) => b.key - a.key)
    .map((x) => x.post);
}
