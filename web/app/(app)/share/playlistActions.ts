"use server";

import { currentSession } from "@/lib/account";
import { getAllPosts, isCloudKitConfigured } from "@/lib/cloudkit/content";
import { isAdmin } from "@/lib/featured";
import { fold } from "@/lib/search";
import { thumbSrc } from "@/lib/smallImage";

/** A post that can go in a playlist: anything on Nexus with a video. */
export type PlaylistCandidate = { id: string; title: string; creator: string; thumb?: string };

/** Whether the signed-in visitor may build playlists from existing posts (admins only: ADMIN_EMAILS). */
export async function canBuildPlaylists(): Promise<boolean> {
  return isAdmin(await currentSession());
}

/** Admins only: posts with a video whose title or main credit matches `q`, newest first. */
export async function searchPlaylistPosts(q: string): Promise<PlaylistCandidate[]> {
  if (!isAdmin(await currentSession()) || !isCloudKitConfigured()) return [];
  const query = fold(typeof q === "string" ? q.trim().slice(0, 100) : "");
  const { posts, festivalBound } = await getAllPosts();
  return posts
    .filter((p) => p.videoUrl && !festivalBound.has(p.id) && !p.playlistPostIDs?.length)
    .filter((p) => !query || fold(p.title).includes(query) || fold(p.creator).includes(query))
    .slice(0, 24)
    .map((p) => ({ id: p.id, title: p.title, creator: p.creator, thumb: thumbSrc(p) }));
}
