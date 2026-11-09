import { findSamplePost } from "./samplePortfolios";
import { getAllPosts, getDiscoverItems, isCloudKitConfigured } from "./cloudkit/content";
import { DISCOVER_ITEMS } from "./discoverContent";
import { POSTS, type Post } from "./mockContent";

/** Real posts from CloudKit; empty when it isn't configured. */
export async function feedPosts(): Promise<Post[]> {
  if (!isCloudKitConfigured()) return POSTS;
  const { posts, festivalBound } = await getAllPosts();
  return posts.filter((p) => !festivalBound.has(p.id));
}

/** Any post by ID, including festival-bound films (reachable directly, as in the app). */
export async function findPost(id: string): Promise<Post | undefined> {
  const sample = findSamplePost(id);
  if (sample) return sample;
  if (!isCloudKitConfigured()) return POSTS.find((p) => p.id === id);
  return (await getAllPosts()).posts.find((p) => p.id === id);
}

export async function allPostIDs(): Promise<string[]> {
  if (!isCloudKitConfigured()) return ["__none__"];
  const ids = (await getAllPosts()).posts.map((p) => p.id);
  return ids.length ? ids : ["__none__"];
}

export async function discoverItems() {
  if (!isCloudKitConfigured()) return DISCOVER_ITEMS;
  return getDiscoverItems();
}

export async function findDiscoverItem(id: string) {
  return (await discoverItems()).find((i) => i.id === id);
}

export async function allDiscoverIDs(): Promise<string[]> {
  const ids = (await discoverItems()).map((i) => i.id);
  return ids.length ? ids : ["__none__"];
}
