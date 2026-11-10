"use server";

import { createElement } from "react";
import ContentGrid from "@/components/ContentGrid";
import { feedPosts, findPost } from "@/lib/content";
import type { Post } from "@/lib/mockContent";

/** The saved posts' grid, for the IDs this browser has saved. Null when they can't be loaded. */
export async function savedGrid(ids: string[]) {
  try {
    const wanted = ids.filter((id) => typeof id === "string" && /^[0-9A-Za-z-]{8,64}$/.test(id)).slice(0, 300);
    const feed = await feedPosts();
    const byID = new Map(feed.map((p) => [p.id.toUpperCase(), p]));
    const posts = (await Promise.all(wanted.map((id) => byID.get(id.toUpperCase()) ?? findPost(id)))).filter((p): p is Post => !!p);
    return { count: posts.length, grid: posts.length ? createElement(ContentGrid, { posts }) : null };
  } catch (error) {
    console.error("[saved]", error instanceof Error ? error.message : error);
    return null;
  }
}
