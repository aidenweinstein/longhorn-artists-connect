"use server";

import { currentAccount } from "@/lib/account";
import { alumniHold } from "@/lib/alumni";
import {
  createGroupThread,
  GROUP_PHOTO_SCHEMA_MESSAGE,
  markRead,
  sendMessage,
  setGroupPhoto,
  threadWith,
  type GroupPhotoUpload,
} from "@/lib/cloudkit/messages";

type Result = { ok: true } | { ok: false; message: string };

/** Sends a reply as the signed-in visitor's app account. */
export async function sendAction(threadID: string, text: string): Promise<Result> {
  const current = await currentAccount();
  const me = current?.session.userRecordName;
  if (!me || !current?.account) return { ok: false, message: "Finish creating your Nexus account to send messages." };
  // Alumni can't message until a moderator approves them.
  const held = await alumniHold(current.session);
  if (held) return { ok: false, message: held };
  try {
    const error = await sendMessage(me, current.account.name, threadID, text);
    return error ? { ok: false, message: error } : { ok: true };
  } catch (error) {
    console.error("[messages] send:", error instanceof Error ? error.message : error);
    return { ok: false, message: "Couldn't send that. Try again." };
  }
}

/** Marks the open thread read, like opening it in the app. */
export async function markReadAction(threadID: string): Promise<void> {
  const current = await currentAccount();
  const me = current?.session.userRecordName;
  if (!me) return;
  await markRead(me, threadID).catch((error) => console.error("[messages] read:", error instanceof Error ? error.message : error));
}

const MAX_GROUP_PHOTO_BYTES = 5 * 1024 * 1024;

/** The "photo" in a form, checked like profile photos. A string is an error to show. */
async function photoFrom(form: FormData | undefined): Promise<GroupPhotoUpload | string | undefined> {
  const photo = form?.get("photo");
  if (!(photo instanceof File) || photo.size === 0) return undefined;
  if (photo.size > MAX_GROUP_PHOTO_BYTES) return "That photo is too large. Try a smaller one.";
  if (!/^image\/(jpeg|png)$/.test(photo.type)) return "Use a JPEG or PNG photo.";
  return { bytes: new Uint8Array(await photo.arrayBuffer()), contentType: photo.type };
}

/** Only real Nexus profiles can be messaged. */
const isProfileID = (id: unknown): id is string => typeof id === "string" && /^UserProfile_[A-Za-z0-9_\-]+$/.test(id);

/**
 * The New message page's Send: one person opens (or reuses) the 1:1 thread with them;
 * two or more start a group chat. The first message goes in right away, then the page
 * opens the thread on Network.
 */
export async function startConversationAction(
  profileIDs: string[],
  text: string,
  groupName?: string,
  /** Group chats: a form holding the group's "photo", if one was chosen. */
  photoForm?: FormData,
): Promise<{ ok: true; threadID: string } | { ok: false; message: string }> {
  const current = await currentAccount();
  const me = current?.session.userRecordName;
  if (!me || !current?.account) return { ok: false, message: "Finish creating your Nexus account to send messages." };
  // Alumni can't message until a moderator approves them.
  const held = await alumniHold(current.session);
  if (held) return { ok: false, message: held };
  const ids = [...new Set(profileIDs.filter(isProfileID))];
  if (ids.length === 0) return { ok: false, message: "Add someone to message." };
  if (ids.length > 50) return { ok: false, message: "Groups can have up to 50 people." };
  const content = text.trim();
  if (!content) return { ok: false, message: "Write a message first." };
  const photo = ids.length > 1 ? await photoFrom(photoForm) : undefined;
  if (typeof photo === "string") return { ok: false, message: photo };
  let threadID: string;
  try {
    threadID = ids.length === 1 ? await threadWith(me, ids[0]) : await createGroupThread(me, ids, groupName, photo);
  } catch (error) {
    console.error("[messages] start:", error instanceof Error ? error.message : error);
    return { ok: false, message: ids.length === 1 ? "Couldn't start that conversation. Try again." : "Couldn't create the group. Try again." };
  }
  try {
    const error = await sendMessage(me, current.account.name, threadID, content);
    if (error) return { ok: false, message: error };
  } catch (error) {
    console.error("[messages] first message:", error instanceof Error ? error.message : error);
    // The thread exists; open it so they can try sending again from there.
    return { ok: true, threadID };
  }
  return { ok: true, threadID };
}

/**
 * A group's header photo menu: saves the form's "photo" as the group's picture, or
 * removes the picture when the form has remove=1 instead.
 */
export async function setGroupPhotoAction(threadID: string, form: FormData): Promise<Result> {
  const current = await currentAccount();
  const me = current?.session.userRecordName;
  if (!me || !current?.account) return { ok: false, message: "Finish creating your Nexus account to change group photos." };
  const photo = await photoFrom(form);
  if (typeof photo === "string") return { ok: false, message: photo };
  if (!photo && form.get("remove") !== "1") return { ok: false, message: "Choose a photo first." };
  try {
    const error = await setGroupPhoto(me, threadID, photo ?? null);
    return error ? { ok: false, message: error } : { ok: true };
  } catch (error) {
    const text = error instanceof Error ? error.message : String(error);
    console.error("[messages] group photo:", text);
    return { ok: false, message: /groupPhoto/i.test(text) ? GROUP_PHOTO_SCHEMA_MESSAGE : "Couldn't save the group photo. Try again." };
  }
}
