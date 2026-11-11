"use server";

import { currentAccount } from "@/lib/account";
import { connect, disconnect, rawUserID, type ConnectionState } from "@/lib/cloudkit/connections";
import { threadWith } from "@/lib/cloudkit/messages";

/*
 * The Connect and Message buttons on someone else's portfolio. Both act as the
 * signed-in visitor's app account, the same way the app's ProfileActionButtons do.
 */

const NOT_LINKED = "Sign in with the school email linked to your Nexus app account first.";

async function visitor() {
  const current = await currentAccount();
  const me = current?.session.userRecordName;
  if (!me || !current?.account) return null;
  return { me: rawUserID(me), name: current.account.name };
}

/** Only real Nexus profiles can be connected with or messaged. */
const isProfileID = (id: unknown): id is string => typeof id === "string" && /^UserProfile_[A-Za-z0-9_\-]+$/.test(id);

export async function connectAction(profileID: string): Promise<{ ok: true; state: ConnectionState } | { ok: false; message: string }> {
  if (!isProfileID(profileID)) return { ok: false, message: "That person isn't on Nexus." };
  const who = await visitor();
  if (!who) return { ok: false, message: NOT_LINKED };
  try {
    return { ok: true, state: await connect(who.me, who.name, profileID) };
  } catch (error) {
    console.error("[connections] connect:", error instanceof Error ? error.message : error);
    return { ok: false, message: "Couldn't connect right now. Try again." };
  }
}

export async function disconnectAction(profileID: string): Promise<{ ok: true; state: ConnectionState } | { ok: false; message: string }> {
  if (!isProfileID(profileID)) return { ok: false, message: "That person isn't on Nexus." };
  const who = await visitor();
  if (!who) return { ok: false, message: NOT_LINKED };
  try {
    return { ok: true, state: await disconnect(who.me, profileID) };
  } catch (error) {
    console.error("[connections] disconnect:", error instanceof Error ? error.message : error);
    return { ok: false, message: "Couldn't update that right now. Try again." };
  }
}

/** Finds or starts the visitor's thread with this person; the button then opens it on Network. */
export async function messageAction(profileID: string): Promise<{ ok: true; threadID: string } | { ok: false; message: string }> {
  if (!isProfileID(profileID)) return { ok: false, message: "That person isn't on Nexus." };
  const who = await visitor();
  if (!who) return { ok: false, message: NOT_LINKED };
  try {
    return { ok: true, threadID: await threadWith(who.me, profileID) };
  } catch (error) {
    console.error("[messages] start thread:", error instanceof Error ? error.message : error);
    return { ok: false, message: "Couldn't open a conversation right now. Try again." };
  }
}
