"use server";

import { feedPosts } from "@/lib/content";
import { toCard } from "@/lib/feedCard";
import type { Post } from "@/lib/mockContent";

/** Cards for the posts saved in this browser, in the order given. Posts that are gone are skipped. */
export async function savedCards(ids: string[]): Promise<Post[]> {
  const wanted = ids.filter((id): id is string => typeof id === "string").slice(0, 500);
  if (wanted.length === 0) return [];
  const byID = new Map((await feedPosts()).map((p) => [p.id, p]));
  return wanted.flatMap((id) => {
    const post = byID.get(id);
    return post ? [toCard(post)] : [];
  });
}
