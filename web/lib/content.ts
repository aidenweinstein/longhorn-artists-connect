import { findSamplePost } from "./samplePortfolios";
import { getAllPosts, getDiscoverItems, isCloudKitConfigured, postByID } from "./cloudkit/content";
import { getOrgLinks, getOrgOverrides, type OrgLink } from "./cloudkit/organizations";
import { DISCOVER_ITEMS } from "./discoverContent";
import { ORGANIZATIONS, type Organization } from "./organizations";
import { POSTS, type Post } from "./mockContent";

/** Real posts from CloudKit; empty when it isn't configured. */
export async function feedPosts(): Promise<Post[]> {
  if (!isCloudKitConfigured()) return POSTS;
  const { posts, festivalBound, inPlaylist } = await getAllPosts();
  // Posts inside a playlist show only there, not on their own in the feeds.
  return posts.filter((p) => !festivalBound.has(p.id) && !inPlaylist.has(p.id));
}

/** Any post by ID, including festival-bound films (reachable directly, as in the app). */
export async function findPost(id: string): Promise<Post | undefined> {
  const sample = findSamplePost(id);
  if (sample) return sample;
  if (!isCloudKitConfigured()) return POSTS.find((p) => p.id === id);
  // A post made moments ago may not be in the feed's list yet: look it up directly.
  return (await getAllPosts()).posts.find((p) => p.id === id) ?? (await postByID(id));
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

/** The app's organizations, with any description or picture set in CloudKit on top. */
export async function organizations(): Promise<Organization[]> {
  if (!isCloudKitConfigured()) return ORGANIZATIONS;
  const overrides = await getOrgOverrides();
  return ORGANIZATIONS.map((o) => ({
    ...o,
    description: overrides[o.slug]?.description ?? o.description,
    imageUrl: overrides[o.slug]?.imageUrl ?? o.imageUrl,
  }));
}

/** Posts moderators have added to org sections in the app. */
export async function orgLinks(): Promise<OrgLink[]> {
  return isCloudKitConfigured() ? getOrgLinks() : [];
}
