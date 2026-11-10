import { asset, lookup, modify, num, queryWhere, str, updateFields, type CKRecord } from "./client";

/*
 * The app's messages, from the same CloudKit records the app uses
 * (MessageRecordHandling.swift):
 *
 *   Conversation  record name = deterministic UUID of the two participants
 *     participant1UserID, participant2UserID (raw user record names),
 *     lastMessageTimestamp, lastMessagePreview, unreadCount
 *   Message       record name = UUID
 *     conversationID, content, timestamp, senderUserID, recipientUserID, isRead,
 *     senderName, messagePreview, attachmentType, attachment (asset), attachmentFileString
 *
 * Never cached: these are private to the two people in each thread. Every function
 * takes the signed-in visitor's own user record name and only returns or changes
 * threads they're part of.
 */

const raw = (id: string) => id.replace(/^UserProfile_/, "");

const CONVERSATION_KEYS = ["participant1UserID", "participant2UserID", "lastMessageTimestamp", "lastMessagePreview", "unreadCount"];
const MESSAGE_KEYS = ["conversationID", "content", "timestamp", "senderUserID", "recipientUserID", "isRead", "attachmentType", "attachment", "attachmentFileString"];

export type ThreadSummary = {
  id: string;
  otherUserID: string;
  lastMessage: string;
  lastAt: number;
  unread: number;
};

export type ThreadMessage = {
  id: string;
  fromMe: boolean;
  text: string;
  at: number;
  attachmentType?: "image" | "video" | "document" | "post";
  attachmentUrl?: string;
  /** For shared posts: the post's ID. */
  postID?: string;
};

function participants(r: CKRecord) {
  return [raw(str(r, "participant1UserID")), raw(str(r, "participant2UserID"))];
}

/** Every conversation the visitor is in, newest first, with their unread counts. */
export async function threadsFor(me: string): Promise<ThreadSummary[]> {
  const user = raw(me);
  const [asOne, asTwo, incoming] = await Promise.all([
    queryWhere("Conversation", "participant1UserID", user, CONVERSATION_KEYS),
    queryWhere("Conversation", "participant2UserID", user, CONVERSATION_KEYS),
    queryWhere("Message", "recipientUserID", user, ["conversationID", "isRead"]),
  ]);
  const unread = new Map<string, number>();
  for (const m of incoming) {
    if (num(m, "isRead") === 1) continue;
    const id = str(m, "conversationID").toUpperCase();
    unread.set(id, (unread.get(id) ?? 0) + 1);
  }

  const seen = new Set<string>();
  const out: ThreadSummary[] = [];
  for (const r of [...asOne, ...asTwo]) {
    const id = r.recordName.toUpperCase();
    if (seen.has(id)) continue;
    seen.add(id);
    const [a, b] = participants(r);
    const other = a === user ? b : a;
    if (!other || other === user) continue;
    out.push({
      id,
      otherUserID: other,
      lastMessage: str(r, "lastMessagePreview"),
      lastAt: num(r, "lastMessageTimestamp") ?? 0,
      unread: unread.get(id) ?? 0,
    });
  }
  // Threads with no messages yet stay out of the list, like the app.
  return out.filter((t) => t.lastAt > 0 || t.lastMessage).sort((x, y) => y.lastAt - x.lastAt);
}

/** The conversation record, only if the visitor is in it. */
async function ownedThread(me: string, threadID: string): Promise<{ record: CKRecord; other: string } | null> {
  if (!/^[0-9A-Fa-f-]{36}$/.test(threadID)) return null;
  const record = await lookup(threadID.toUpperCase()).catch(() => null) ?? (await lookup(threadID.toLowerCase()).catch(() => null));
  if (!record || record.recordType !== "Conversation") return null;
  const user = raw(me);
  const [a, b] = participants(record);
  if (a !== user && b !== user) return null;
  return { record, other: a === user ? b : a };
}

/** One thread's messages, oldest first. Null when the visitor isn't in it. */
export async function messagesIn(me: string, threadID: string): Promise<{ other: string; messages: ThreadMessage[] } | null> {
  const thread = await ownedThread(me, threadID);
  if (!thread) return null;
  const user = raw(me);
  const records = await queryWhere("Message", "conversationID", thread.record.recordName, MESSAGE_KEYS);
  const messages = records
    .map((r): ThreadMessage => {
      const type = str(r, "attachmentType");
      const attachmentType = type === "image" || type === "video" || type === "document" || type === "post" ? type : undefined;
      return {
        id: r.recordName,
        fromMe: raw(str(r, "senderUserID")) === user,
        text: str(r, "content"),
        at: num(r, "timestamp") ?? r.created?.timestamp ?? 0,
        attachmentType,
        attachmentUrl:
          attachmentType === "image" ? asset(r, "attachment", "media.jpg") : attachmentType === "video" ? asset(r, "attachment", "media.mp4") : attachmentType === "document" ? asset(r, "attachment", "file.pdf") : undefined,
        postID: attachmentType === "post" ? str(r, "attachmentFileString") || undefined : undefined,
      };
    })
    .sort((a, b) => a.at - b.at);
  return { other: thread.other, messages };
}

/** Sends a text message as the visitor, and bumps the thread like the app does. */
export async function sendMessage(me: string, senderName: string, threadID: string, text: string): Promise<string | null> {
  const thread = await ownedThread(me, threadID);
  if (!thread) return "That conversation isn't yours.";
  const now = Date.now();
  const content = text.trim().slice(0, 4000);
  if (!content) return "Write a message first.";

  await modify([
    {
      kind: "save",
      recordType: "Message",
      recordName: crypto.randomUUID().toUpperCase(),
      fields: {
        conversationID: { value: thread.record.recordName, type: "STRING" },
        content: { value: content, type: "STRING" },
        timestamp: { value: now, type: "TIMESTAMP" },
        senderUserID: { value: raw(me), type: "STRING" },
        recipientUserID: { value: thread.other, type: "STRING" },
        isRead: { value: 0, type: "INT64" },
        // These two power the push banner on the recipient's phone.
        senderName: { value: senderName, type: "STRING" },
        messagePreview: { value: content.slice(0, 200), type: "STRING" },
      },
    },
  ]);

  const error = await updateFields("Conversation", thread.record.recordName, {
    lastMessageTimestamp: { value: now, type: "TIMESTAMP" },
    lastMessagePreview: { value: content.slice(0, 200), type: "STRING" },
    unreadCount: { value: (num(thread.record, "unreadCount") ?? 0) + 1, type: "INT64" },
  });
  if (error) console.error("[messages] thread update:", error.code, error.reason);
  return null;
}

/** Marks the visitor's incoming messages in a thread as read. */
export async function markRead(me: string, threadID: string): Promise<void> {
  const thread = await ownedThread(me, threadID);
  if (!thread) return;
  const user = raw(me);
  const records = await queryWhere("Message", "conversationID", thread.record.recordName, ["recipientUserID", "isRead"]);
  const unread = records.filter((r) => raw(str(r, "recipientUserID")) === user && num(r, "isRead") !== 1);
  await Promise.all(unread.map((r) => updateFields("Message", r.recordName, { isRead: { value: 1, type: "INT64" } }).catch(() => null)));
  if (unread.length) {
    await updateFields("Conversation", thread.record.recordName, { unreadCount: { value: 0, type: "INT64" } }).catch(() => null);
  }
}
