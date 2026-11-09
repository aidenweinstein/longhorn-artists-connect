"use server";

import { creditedPosts, currentSession, personAccount } from "@/lib/account";
import { updateTag } from "next/cache";
import { PEOPLE_PAGES, PeopleServiceError, callPeople, featuresFor, isAdmin, peoplePage } from "@/lib/featured";
import { CREATIVE_ALL_TAG, writeListing } from "@/lib/cloudkit/creative";
import { styleForSlug } from "@/lib/profileStyle";

/**
 * Mirrors a People-page decision into CloudKit (DirectoryListing), so the app's
 * public Actors / Filmmakers / Musicians pages match the website's. Best effort:
 * the website's own list (verification-service) stays the source for the site.
 */
async function mirrorListing(category: string, profileID: string, status: "approved" | "declined") {
  const style = styleForSlug(category);
  if (!style || !profileID.startsWith("UserProfile_")) return;
  try {
    await writeListing(profileID, style, status);
    updateTag(CREATIVE_ALL_TAG);
  } catch (error) {
    console.error("[people] listing mirror:", error instanceof Error ? error.message : error);
  }
}

// Every action re-checks that the signed-in person is an admin: the page hiding
// the buttons isn't enough, since server actions can be called directly.

type Result = { ok: true } | { ok: false; message: string };

async function asAdmin(run: () => Promise<unknown>): Promise<Result> {
  if (!isAdmin(await currentSession())) return { ok: false, message: "Only admins can do that." };
  try {
    await run();
    return { ok: true };
  } catch (error) {
    return { ok: false, message: error instanceof PeopleServiceError ? error.message : "Something went wrong. Try again." };
  }
}

export type PickablePost = { id: string; title: string; thumbnailUrl?: string; category: string };

/** The work a person is credited on, to choose what shows beside them. */
export async function postsFor(profileID: string): Promise<PickablePost[]> {
  if (!isAdmin(await currentSession())) return [];
  const account = await personAccount(profileID).catch(() => null);
  if (!account) return [];
  return (await creditedPosts(account)).map((p) => ({ id: p.id, title: p.title, thumbnailUrl: p.thumbnailUrl, category: p.category }));
}

export async function saveFeature(input: {
  category: string;
  profileID: string;
  name: string;
  blurb: string;
  postIDs: string[];
  applicationID?: string;
}): Promise<Result> {
  if (!peoplePage(input.category)) return { ok: false, message: "Pick a page." };
  if (!input.profileID) return { ok: false, message: "Pick someone's Nexus profile." };
  return asAdmin(async () => {
    await callPeople("admin/save", { ...input, postIDs: input.postIDs.slice(0, 6) });
    await mirrorListing(input.category, input.profileID, "approved");
  });
}

/**
 * Add several people to one page at once. Each gets an empty blurb and no posts;
 * fill those in later with Edit. Saved one at a time so they land in the order picked.
 */
export async function saveFeatures(input: {
  category: string;
  people: { profileID: string; name: string }[];
}): Promise<Result & { added?: number }> {
  if (!peoplePage(input.category)) return { ok: false, message: "Pick a page." };
  const page = peoplePage(input.category)!;
  const people = input.people.filter((p) => p.profileID).slice(0, 100);
  if (people.length === 0) return { ok: false, message: "Pick at least one person." };
  let added = 0;
  const res = await asAdmin(async () => {
    // Saving someone already on the page would wipe their blurb and posts, so skip them.
    const already = new Set((await featuresFor(page.slug)).map((f) => f.profileID));
    for (const p of people) {
      if (already.has(p.profileID)) continue;
      await callPeople("admin/save", { category: input.category, profileID: p.profileID, name: p.name, blurb: "", postIDs: [] });
      await mirrorListing(input.category, p.profileID, "approved");
      added++;
    }
  });
  if (!res.ok && added > 0) return { ok: false, message: `Added ${added} of ${people.length}, then stopped: ${res.message}` };
  return res.ok ? { ok: true, added } : res;
}

export async function removeFeature(id: string): Promise<Result> {
  return asAdmin(async () => {
    const lists = await Promise.all(PEOPLE_PAGES.map((p) => featuresFor(p.slug)));
    const feature = lists.flat().find((f) => f.id === id);
    await callPeople("admin/remove", { id });
    if (feature) await mirrorListing(feature.category, feature.profileID, "declined");
  });
}

export async function moveFeature(id: string, direction: "up" | "down"): Promise<Result> {
  return asAdmin(() => callPeople("admin/move", { id, direction }));
}

export async function decideApplication(applicationID: string, status: "declined" | "pending"): Promise<Result> {
  return asAdmin(() => callPeople("admin/decide", { applicationID, status }));
}

export async function savePick(postID: string, note: string): Promise<Result> {
  if (!postID) return { ok: false, message: "Pick a post." };
  return asAdmin(() => callPeople("picks/admin/save", { postID, note }));
}

export async function removePick(postID: string): Promise<Result> {
  return asAdmin(() => callPeople("picks/admin/remove", { postID }));
}

export async function movePick(postID: string, direction: "up" | "down"): Promise<Result> {
  return asAdmin(() => callPeople("picks/admin/move", { postID, direction }));
}

// MARK: - Featured collections

export async function saveCollection(input: { id?: string; title: string; description: string }): Promise<Result> {
  if (!input.title.trim()) return { ok: false, message: "Give the collection a title." };
  return asAdmin(() => callPeople("collections/admin/save", input));
}

export async function removeCollection(id: string): Promise<Result> {
  return asAdmin(() => callPeople("collections/admin/remove", { id }));
}

export async function moveCollection(id: string, direction: "up" | "down"): Promise<Result> {
  return asAdmin(() => callPeople("collections/admin/move", { id, direction }));
}

/** Adds a post to a collection, or edits its note there. */
export async function saveCollectionItem(collectionID: string, postID: string, note: string): Promise<Result> {
  if (!postID) return { ok: false, message: "Pick a post." };
  return asAdmin(() => callPeople("collections/admin/add", { collectionID, postID, note }));
}

export async function removeCollectionItem(collectionID: string, postID: string): Promise<Result> {
  return asAdmin(() => callPeople("collections/admin/remove-item", { collectionID, postID }));
}

export async function moveCollectionItem(collectionID: string, postID: string, direction: "up" | "down"): Promise<Result> {
  return asAdmin(() => callPeople("collections/admin/move-item", { collectionID, postID, direction }));
}
