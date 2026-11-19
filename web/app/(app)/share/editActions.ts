"use server";

import { updateTag } from "next/cache";
import { currentAccount, currentSession } from "@/lib/account";
import { isCloudKitConfigured, list, modify, str, type CKRecord } from "@/lib/cloudkit/client";
import { POSTS_TAG, accountTag } from "@/lib/cloudkit/content";
import { formFields, keptFormFiles, ownedPost } from "@/lib/editPost";
import { deleteObject, keyFromPublicURL } from "@/lib/r2";
import type { ShareTypeID } from "@/lib/sharePost";

/** The signed-in Nexus account's record name, or null. */
async function me(): Promise<string | null> {
  if (!isCloudKitConfigured()) return null;
  const current = await currentAccount().catch(() => null);
  return current?.account ? (current.session.userRecordName ?? null) : null;
}

/**
 * Whether to show Edit on a post: the person looking is the account that made it. Only
 * compares the sign-in with the post's maker (no CloudKit request), since this runs on
 * every post view; opening and saving the edit check the post itself.
 */
export async function canEditPost(makerProfileID: string | undefined): Promise<boolean> {
  if (!makerProfileID) return false;
  const user = (await currentSession().catch(() => null))?.userRecordName;
  return !!user && makerProfileID === `UserProfile_${user}`;
}

export type EditStart =
  | { ok: true; type: ShareTypeID; fields: Record<string, unknown>; kept: string[] }
  | { ok: false; message: string };

/** A post's current values for the Share form, for its maker only. */
export async function loadPostForEdit(postID: string): Promise<EditStart> {
  const user = await me();
  if (!user) return { ok: false, message: "Sign in to edit your posts." };
  try {
    const owned = await ownedPost(postID, user);
    if (!owned) return { ok: false, message: "You can only edit posts you made." };
    return { ok: true, type: owned.type, fields: formFields(owned.type, owned.record), kept: keptFormFiles(owned.type, owned.record) };
  } catch (error) {
    console.error("[edit] load:", error);
    return { ok: false, message: "Couldn't open this post. Try again in a moment." };
  }
}

/** The post's files in R2: every `<field>URL` / `<field>URLs` link that points at the bucket. */
function r2Keys(r: CKRecord): string[] {
  const links = Object.keys(r.fields).flatMap((k) => (k.endsWith("URLs") ? list(r, k) : k.endsWith("URL") ? [str(r, k)] : []));
  return links.flatMap((url) => (url ? (keyFromPublicURL(url) ?? []) : []));
}

/**
 * Deletes one of your posts. The record is deleted outright when CloudKit allows it (posts
 * made on the website). A post made in the app belongs to the maker's iCloud account, which
 * only the app can delete, so the website removes it the way moderators do instead (a
 * ModerationAction the app and the site both honor): it disappears everywhere either way.
 * Its big files in R2 are deleted too.
 */
export async function deletePost(postID: string): Promise<{ ok: true; href: string } | { ok: false; message: string }> {
  const user = await me();
  if (!user) return { ok: false, message: "Sign in to delete your posts." };
  const owned = await ownedPost(postID, user).catch(() => null);
  if (!owned) return { ok: false, message: "You can only delete posts you made." };
  const { record, type } = owned;

  try {
    await modify([{ kind: "delete", recordName: record.recordName }]);
  } catch (error) {
    console.warn("[edit] delete refused, removing instead:", error instanceof Error ? error.message : error);
    try {
      await modify([
        {
          kind: "save",
          recordType: "ModerationAction",
          recordName: `moderation_${record.recordName.toUpperCase()}`,
          fields: {
            postID: { value: record.recordName.toUpperCase(), type: "STRING" },
            isRemoved: { value: 1, type: "INT64" },
            modifiedAt: { value: Date.now(), type: "TIMESTAMP" },
          },
        },
      ]);
    } catch (fallbackError) {
      console.error("[edit] delete:", fallbackError);
      return { ok: false, message: "Couldn't delete the post. Try again in a moment." };
    }
  }
  // A Script post's file lives on its own record in the Scripts collection.
  if (type === "project") await modify([{ kind: "delete", recordName: `Script_${record.recordName}` }]).catch(() => undefined);
  await Promise.all(r2Keys(record).map((key) => deleteObject(key)));

  // CloudKit's queries catch up with a deletion after a moment; refresh the feeds after that.
  await new Promise((r) => setTimeout(r, 2500));
  updateTag(POSTS_TAG);
  updateTag(accountTag(user));
  return { ok: true, href: "/portfolio" };
}
