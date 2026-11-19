"use server";

import { updateTag } from "next/cache";
import { currentAccount, currentSession } from "@/lib/account";
import { isCloudKitConfigured, list, modify, str, updateRecord, type CKRecord } from "@/lib/cloudkit/client";
import { POSTS_TAG, accountTag, profileDirectory } from "@/lib/cloudkit/content";
import { EDITORS_FIELD, MAX_EDITORS, accountOf, editablePost, editorAccounts, formFields, keptFormFiles, mayEdit, ownedPost } from "@/lib/editPost";
import { deleteObject, keyFromPublicURL } from "@/lib/r2";
import type { ShareTypeID } from "@/lib/sharePost";

/** The signed-in Nexus account's record name, or null. */
async function me(): Promise<string | null> {
  if (!isCloudKitConfigured()) return null;
  const current = await currentAccount().catch(() => null);
  return current?.account ? (current.session.userRecordName ?? null) : null;
}

/**
 * Whether to show Edit on a post: the person looking made it, or its maker shared edit
 * access with them. Only compares the sign-in with the IDs on the page (no CloudKit
 * request), since this runs on every post view; opening and saving the edit check the
 * post itself. `isMaker` also shows "Edit access", which only the maker can change.
 */
export async function postAccess(
  makerProfileID: string | undefined,
  editorIDs: string[] | undefined,
): Promise<{ canEdit: boolean; isMaker: boolean }> {
  const user = (await currentSession().catch(() => null))?.userRecordName;
  const isMaker = !!user && !!makerProfileID && accountOf(makerProfileID) === user;
  return { canEdit: mayEdit(makerProfileID, Array.isArray(editorIDs) ? editorIDs.map(String) : [], user), isMaker };
}

export type EditStart =
  | { ok: true; type: ShareTypeID; fields: Record<string, unknown>; kept: string[]; isMaker: boolean }
  | { ok: false; message: string };

/** A post's current values for the Share form, for its maker and anyone they shared edit access with. */
export async function loadPostForEdit(postID: string): Promise<EditStart> {
  const user = await me();
  if (!user) return { ok: false, message: "Sign in to edit your posts." };
  try {
    const owned = await editablePost(postID, user);
    if (!owned) return { ok: false, message: "You can only edit posts you made or were given edit access to." };
    return {
      ok: true,
      type: owned.type,
      fields: formFields(owned.type, owned.record),
      kept: keptFormFiles(owned.type, owned.record),
      isMaker: owned.isMaker,
    };
  } catch (error) {
    console.error("[edit] load:", error);
    return { ok: false, message: "Couldn't open this post. Try again in a moment." };
  }
}

/** Someone with edit access, as the Edit access panel lists them. */
export type Editor = { id: string; name: string; imageUrl?: string };

export type EditorsResult = { ok: true; editors: Editor[] } | { ok: false; message: string };

/** Everyone the post's maker shared edit access with (the maker only). */
export async function getEditors(postID: string): Promise<EditorsResult> {
  const user = await me();
  if (!user) return { ok: false, message: "Sign in to manage edit access." };
  try {
    const owned = await ownedPost(postID, user);
    if (!owned) return { ok: false, message: "Only the person who posted this can change who can edit it." };
    return { ok: true, editors: await namesFor(editorAccounts(owned.record)) };
  } catch (error) {
    console.error("[edit] editors:", error);
    return { ok: false, message: "Couldn't load who can edit this. Try again in a moment." };
  }
}

/** Profiles for account record names, in the order given (unknown ones keep a placeholder name). */
async function namesFor(accounts: string[]): Promise<Editor[]> {
  const byID = new Map((await profileDirectory().catch(() => [])).map((p) => [p.id, p]));
  return accounts.map((a) => {
    const p = byID.get(`UserProfile_${a}`);
    return { id: `UserProfile_${a}`, name: p?.name || "Nexus member", imageUrl: p?.imageUrl };
  });
}

/**
 * Replaces who else can edit the post (the maker only). Only that one field changes;
 * the post's other fields, owner and dates stay as they are.
 */
export async function setEditors(postID: string, profileIDs: string[]): Promise<EditorsResult> {
  const user = await me();
  if (!user) return { ok: false, message: "Sign in to manage edit access." };
  if (!Array.isArray(profileIDs)) return { ok: false, message: "Something went wrong. Try again." };
  const owned = await ownedPost(postID, user).catch(() => null);
  if (!owned) return { ok: false, message: "Only the person who posted this can change who can edit it." };

  // Real Nexus members only, never the maker, each once.
  const members = new Set((await profileDirectory().catch(() => [])).map((p) => accountOf(p.id)));
  const current = new Set(editorAccounts(owned.record));
  const accounts = [
    ...new Set(
      profileIDs
        .map((id) => accountOf(String(id)))
        .filter((a) => /^[\w-]{1,100}$/.test(a) && a !== user && (members.has(a) || current.has(a))),
    ),
  ];
  if (accounts.length > MAX_EDITORS) return { ok: false, message: `A post can be shared with up to ${MAX_EDITORS} editors.` };

  try {
    await updateRecord(
      owned.record.recordType,
      owned.record.recordName,
      { [EDITORS_FIELD]: { value: accounts.map((a) => `UserProfile_${a}`), type: "STRING_LIST" } },
      [EDITORS_FIELD],
    );
  } catch (error) {
    console.error("[edit] setEditors:", error);
    const message = error instanceof Error ? error.message : String(error);
    if (message.includes(EDITORS_FIELD)) {
      return { ok: false, message: `Edit access can't be saved yet: add ${EDITORS_FIELD} (String List) to ${owned.record.recordType} in CloudKit first.` };
    }
    return { ok: false, message: "Couldn't save who can edit this. Try again in a moment." };
  }
  updateTag(POSTS_TAG);
  return { ok: true, editors: await namesFor(accounts) };
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
  if (!owned) return { ok: false, message: "Only the person who posted this can delete it." };
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
