"use server";

import { currentAccount } from "@/lib/account";
import { isCloudKitConfigured, lookup, modify, queryWhere } from "@/lib/cloudkit/client";
import { findPost } from "@/lib/content";
import type { Post } from "@/lib/mockContent";
import { FLAG_REASONS } from "@/lib/flags";

/*
 * Likes and flags from the website, stored exactly as the app stores them, so they
 * count in both places. The signed-in account comes from the session: its email was
 * verified by that same app account, which is the proof these writes rest on. Each
 * action only ever writes the signed-in person's own like, never anyone else's.
 */

export type ActionState = { likes: number; liked: boolean; canLike: boolean; canFlag: boolean };

// The app stores post IDs as Swift UUID strings, which are uppercase.
const postKey = (id: string) => id.toUpperCase();
const likeRecord = (postID: string, user: string) => `like_${postKey(postID)}_${user}`;

const APP_TYPE: Record<Post["category"], string> = {
  film: "Film",
  music: "Music",
  performance: "Reel",
  photography: "Photography",
  design: "Design",
};

export async function postActionState(postID: string): Promise<ActionState> {
  const current = await currentAccount();
  const user = current?.session.userRecordName;
  if (!isCloudKitConfigured()) return { likes: 0, liked: false, canLike: false, canFlag: !!current };
  try {
    const [likes, mine] = await Promise.all([
      queryWhere("PostLike", "postID", postKey(postID)),
      user ? lookup(likeRecord(postID, user)) : null,
    ]);
    return { likes: likes.length, liked: !!mine, canLike: !!user, canFlag: !!current };
  } catch (error) {
    console.error("[likes]", error instanceof Error ? error.message : error);
    return { likes: 0, liked: false, canLike: !!user, canFlag: !!current };
  }
}

export async function setLike(postID: string, liked: boolean): Promise<{ ok: true; state: ActionState } | { ok: false; message: string }> {
  const current = await currentAccount();
  const user = current?.session.userRecordName;
  if (!user) return { ok: false, message: "Verify this email in the Nexus app to like posts here." };
  if (!(await findPost(postID))) return { ok: false, message: "That post isn't available." };
  try {
    await modify([
      liked
        ? {
            kind: "save",
            recordType: "PostLike",
            recordName: likeRecord(postID, user),
            fields: {
              postID: { value: postKey(postID) },
              userID: { value: user },
              createdDate: { value: Date.now(), type: "TIMESTAMP" },
            },
          }
        : { kind: "delete", recordName: likeRecord(postID, user) },
    ]);
    return { ok: true, state: await postActionState(postID) };
  } catch (error) {
    console.error("[likes]", error instanceof Error ? error.message : error);
    return { ok: false, message: "Couldn't save your like. Try again." };
  }
}

export async function flagPost(postID: string, reason: string, reasoning: string): Promise<{ ok: true } | { ok: false; message: string }> {
  const current = await currentAccount();
  if (!current) return { ok: false, message: "Sign in to report a post." };
  if (!(FLAG_REASONS as readonly string[]).includes(reason)) return { ok: false, message: "Pick a reason." };
  const why = reasoning.trim().slice(0, 2000);
  if (!why) return { ok: false, message: "Add a few words about what's wrong." };
  const post = await findPost(postID);
  if (!post) return { ok: false, message: "That post isn't available." };
  if (!isCloudKitConfigured()) return { ok: false, message: "Reporting isn't available here yet." };
  try {
    await modify([
      {
        kind: "save",
        recordType: "Flag",
        recordName: crypto.randomUUID().toUpperCase(),
        fields: {
          reason: { value: reason },
          reasoning: { value: why },
          postID: { value: postKey(postID) },
          postTitle: { value: post.title },
          postType: { value: APP_TYPE[post.category] },
          submittedBy: { value: current.account?.name || "Anonymous" },
          submittedByUserID: { value: current.session.userRecordName ?? "" },
          createdDate: { value: Date.now(), type: "TIMESTAMP" },
        },
      },
    ]);
    return { ok: true };
  } catch (error) {
    console.error("[flags]", error instanceof Error ? error.message : error);
    return { ok: false, message: "Couldn't send your report. Try again." };
  }
}
