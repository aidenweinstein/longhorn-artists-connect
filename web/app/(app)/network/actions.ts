"use server";

import { currentAccount } from "@/lib/account";
import { createGroupThread, markRead, sendMessage, threadWith } from "@/lib/cloudkit/messages";

type Result = { ok: true } | { ok: false; message: string };

/** Sends a reply as the signed-in visitor's app account. */
export async function sendAction(threadID: string, text: string): Promise<Result> {
  const current = await currentAccount();
  const me = current?.session.userRecordName;
  if (!me || !current?.account) return { ok: false, message: "Finish creating your Nexus account to send messages." };
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
): Promise<{ ok: true; threadID: string } | { ok: false; message: string }> {
  const current = await currentAccount();
  const me = current?.session.userRecordName;
  if (!me || !current?.account) return { ok: false, message: "Finish creating your Nexus account to send messages." };
  const ids = [...new Set(profileIDs.filter(isProfileID))];
  if (ids.length === 0) return { ok: false, message: "Add someone to message." };
  if (ids.length > 50) return { ok: false, message: "Groups can have up to 50 people." };
  const content = text.trim();
  if (!content) return { ok: false, message: "Write a message first." };
  let threadID: string;
  try {
    threadID = ids.length === 1 ? await threadWith(me, ids[0]) : await createGroupThread(me, ids, groupName);
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
