"use server";

import { currentAccount } from "@/lib/account";
import { markRead, sendMessage } from "@/lib/cloudkit/messages";

type Result = { ok: true } | { ok: false; message: string };

/** Sends a reply as the signed-in visitor's app account. */
export async function sendAction(threadID: string, text: string): Promise<Result> {
  const current = await currentAccount();
  const me = current?.session.userRecordName;
  if (!me || !current?.account) return { ok: false, message: "Link this email to your Nexus app account to send messages." };
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
