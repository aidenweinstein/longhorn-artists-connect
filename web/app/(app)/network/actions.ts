"use server";

import { currentAccount } from "@/lib/account";
import { connectWith, disconnectFrom, type ConnectionState } from "@/lib/cloudkit/connections";
import { markRead, sendMessage, startThread } from "@/lib/cloudkit/messages";

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

const rawID = (id: string) => id.replace(/^UserProfile_/, "");
const NEEDS_LINK = "Link this email to your Nexus app account first.";

/** Opens (creating if needed) the thread with someone, returning its ID. */
export async function startConversationAction(otherProfileID: string): Promise<{ ok: true; threadID: string } | { ok: false; message: string }> {
  const current = await currentAccount();
  const me = current?.session.userRecordName;
  if (!me || !current?.account) return { ok: false, message: NEEDS_LINK };
  try {
    return { ok: true, threadID: await startThread(me, rawID(otherProfileID)) };
  } catch (error) {
    console.error("[messages] start:", error instanceof Error ? error.message : error);
    return { ok: false, message: "Couldn't start that conversation. Try again." };
  }
}

type ConnectResult = { ok: true; state: ConnectionState } | { ok: false; message: string };

/** Sends a connection request, or accepts the one waiting. */
export async function connectAction(otherProfileID: string): Promise<ConnectResult> {
  const current = await currentAccount();
  const me = current?.session.userRecordName;
  if (!me || !current?.account) return { ok: false, message: NEEDS_LINK };
  try {
    return { ok: true, state: await connectWith(me, current.account.name, rawID(otherProfileID)) };
  } catch (error) {
    console.error("[connections] connect:", error instanceof Error ? error.message : error);
    return { ok: false, message: "Couldn't connect right now. Try again." };
  }
}

/** Withdraws a request or disconnects. */
export async function disconnectAction(otherProfileID: string): Promise<ConnectResult> {
  const current = await currentAccount();
  const me = current?.session.userRecordName;
  if (!me || !current?.account) return { ok: false, message: NEEDS_LINK };
  try {
    await disconnectFrom(me, rawID(otherProfileID));
    return { ok: true, state: "none" };
  } catch (error) {
    console.error("[connections] disconnect:", error instanceof Error ? error.message : error);
    return { ok: false, message: "Couldn't update that. Try again." };
  }
}
