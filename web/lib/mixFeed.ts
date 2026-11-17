import type { Post } from "./mockContent";

/** A small repeatable random-number generator (mulberry32): the same seed gives the same numbers. */
function seeded(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** A new shuffle for one visit. Call it at request time, not while a page is being prerendered. */
export function newFeedSeed(): number {
  return Math.floor(Math.random() * 2 ** 31);
}

/**
 * A fresh order on every visit that still leans toward newer posts: each post draws
 * a random key weighted by how recent it is (newest weight 1, oldest ~0.25), and the
 * feed sorts by that key. Posts arrive newest-first.
 *
 * The order comes from `seed`, so the later pages of one visit (loaded as you scroll)
 * continue the same shuffle. Each post's draw depends on its own ID, so a post added
 * or removed mid-visit barely moves the others (FeedGrid drops any repeat).
 */
export function mixFeed(posts: Post[], seed: number): Post[] {
  const n = posts.length;
  return posts
    .map((post, i) => {
      const weight = 1 - (0.75 * i) / Math.max(1, n - 1);
      let h = seed >>> 0;
      for (let c = 0; c < post.id.length; c++) h = (Math.imul(h, 31) + post.id.charCodeAt(c)) >>> 0;
      return { post, key: seeded(h)() ** (1 / weight) };
    })
    .sort((a, b) => b.key - a.key)
    .map((x) => x.post);
}
