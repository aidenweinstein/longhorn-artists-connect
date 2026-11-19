import { createHash } from "node:crypto";
import { asset, createRecord, list, lookup, modify, num, queryWhere, str, updateFields, type CKField, type CKRecord } from "./client";
import { profileDirectory } from "./content";

/*
 * The app's messages, from the same CloudKit records the app uses
 * (MessageRecordHandling.swift):
 *
 *   Conversation  record name = deterministic UUID of the two participants (1:1), or a
 *                 random UUID for a group
 *     participant1UserID, participant2UserID (raw user record names),
 *     lastMessageTimestamp, lastMessagePreview, unreadCount
 *     groups: isGroup = 1, participantUserIDs (everyone, creator included), groupName,
 *             createdByUserID; participant2UserID is "" on a group
 *   Message       record name = UUID
 *     conversationID, content, timestamp, senderUserID, recipientUserID, isRead,
 *     senderName, messagePreview, attachmentType, attachment (asset), attachmentFileString
 *     groups: recipientUserIDs (everyone but the sender), readByUserIDs (who has opened
 *             it), groupName (the push title); recipientUserID is "" on a group message
 *
 * Never cached: these are private to the people in each thread. Every function takes
 * the signed-in visitor's own user record name and only returns or changes threads
 * they're part of.
 */

const raw = (id: string) => id.replace(/^UserProfile_/, "");

const CONVERSATION_KEYS = [
  "participant1UserID",
  "participant2UserID",
  "lastMessageTimestamp",
  "lastMessagePreview",
  "unreadCount",
  "isGroup",
  "participantUserIDs",
  "groupName",
  "createdByUserID",
];
const MESSAGE_KEYS = [
  "conversationID",
  "content",
  "timestamp",
  "senderUserID",
  "recipientUserID",
  "isRead",
  "attachmentType",
  "attachment",
  "attachmentFileString",
  "recipientUserIDs",
  "readByUserIDs",
];

export type ThreadSummary = {
  id: string;
  /** The other person in a 1:1 thread; "" for a group. */
  otherUserID: string;
  lastMessage: string;
  lastAt: number;
  unread: number;
  isGroup: boolean;
  /** Group chats: the name members gave it, if any. */
  groupName?: string;
  /** Group chats: every member (the visitor included), raw user record names. */
  memberIDs: string[];
};

export type ThreadMessage = {
  id: string;
  fromMe: boolean;
  /** Raw user record name of the sender, so group threads can label bubbles. */
  senderID: string;
  text: string;
  at: number;
  attachmentType?: "image" | "video" | "document" | "post";
  attachmentUrl?: string;
  /** For shared posts: the post's ID. */
  postID?: string;
};

function isGroupRecord(r: CKRecord) {
  return num(r, "isGroup") === 1;
}

function participants(r: CKRecord) {
  return [raw(str(r, "participant1UserID")), raw(str(r, "participant2UserID"))];
}

/** Everyone in a thread: both people of a 1:1 chat, or the group's member list. */
function memberIDs(r: CKRecord): string[] {
  const ids = isGroupRecord(r) ? list(r, "participantUserIDs").map(raw) : participants(r);
  return [...new Set(ids.filter(Boolean))];
}

/** "Sam", "Sam & Alex", "Sam, Alex & Jo" — how an unnamed group is titled. */
export function groupAutoName(names: string[]): string {
  const n = names.filter(Boolean);
  if (n.length === 0) return "Group";
  if (n.length === 1) return n[0];
  return `${n.slice(0, -1).join(", ")} & ${n[n.length - 1]}`;
}

/** Every conversation the visitor is in, newest first, with their unread counts. */
export async function threadsFor(me: string): Promise<ThreadSummary[]> {
  const user = raw(me);
  // The group queries use list fields the schema may not have yet; losing them must
  // not lose the 1:1 threads, so their failures are swallowed here.
  const [asOne, asTwo, incoming, groups, groupIncoming] = await Promise.all([
    queryWhere("Conversation", "participant1UserID", user, CONVERSATION_KEYS),
    queryWhere("Conversation", "participant2UserID", user, CONVERSATION_KEYS),
    queryWhere("Message", "recipientUserID", user, ["conversationID", "isRead"]),
    queryWhere("Conversation", "participantUserIDs", user, CONVERSATION_KEYS, 5000, "LIST_CONTAINS").catch((error) => {
      console.warn("[messages] group threads:", error instanceof Error ? error.message : error);
      return [] as CKRecord[];
    }),
    queryWhere("Message", "recipientUserIDs", user, ["conversationID", "readByUserIDs"], 5000, "LIST_CONTAINS").catch(() => [] as CKRecord[]),
  ]);
  const unread = new Map<string, number>();
  for (const m of incoming) {
    if (num(m, "isRead") === 1) continue;
    const id = str(m, "conversationID").toUpperCase();
    unread.set(id, (unread.get(id) ?? 0) + 1);
  }
  for (const m of groupIncoming) {
    if (list(m, "readByUserIDs").map(raw).includes(user)) continue;
    const id = str(m, "conversationID").toUpperCase();
    unread.set(id, (unread.get(id) ?? 0) + 1);
  }

  const seen = new Set<string>();
  const out: ThreadSummary[] = [];
  for (const r of [...asOne, ...asTwo, ...groups]) {
    const id = r.recordName.toUpperCase();
    if (seen.has(id)) continue;
    seen.add(id);
    const base = { id, lastMessage: str(r, "lastMessagePreview"), lastAt: num(r, "lastMessageTimestamp") ?? 0, unread: unread.get(id) ?? 0 };
    if (isGroupRecord(r)) {
      const members = memberIDs(r);
      // A group the visitor has left (or been removed from) is theirs no more.
      if (!members.includes(user)) continue;
      out.push({ ...base, otherUserID: "", isGroup: true, groupName: str(r, "groupName") || undefined, memberIDs: members });
      continue;
    }
    const [a, b] = participants(r);
    const other = a === user ? b : a;
    if (!other || other === user) continue;
    out.push({ ...base, otherUserID: other, isGroup: false, memberIDs: [a, b] });
  }
  // Threads with no messages yet stay out of the list, like the app.
  return out.filter((t) => t.lastAt > 0 || t.lastMessage).sort((x, y) => y.lastAt - x.lastAt);
}

type OwnedThread = { record: CKRecord; other: string; isGroup: boolean; members: string[] };

/** The conversation record, only if the visitor is in it. */
async function ownedThread(me: string, threadID: string): Promise<OwnedThread | null> {
  if (!/^[0-9A-Fa-f-]{36}$/.test(threadID)) return null;
  const record = await lookup(threadID.toUpperCase()).catch(() => null) ?? (await lookup(threadID.toLowerCase()).catch(() => null));
  if (!record || record.recordType !== "Conversation") return null;
  const user = raw(me);
  if (isGroupRecord(record)) {
    const members = memberIDs(record);
    if (!members.includes(user)) return null;
    return { record, other: "", isGroup: true, members };
  }
  const [a, b] = participants(record);
  if (a !== user && b !== user) return null;
  return { record, other: a === user ? b : a, isGroup: false, members: [a, b] };
}

/** One thread's messages, oldest first. Null when the visitor isn't in it. */
export async function messagesIn(
  me: string,
  threadID: string,
): Promise<{ other: string; isGroup: boolean; groupName?: string; members: string[]; messages: ThreadMessage[] } | null> {
  const thread = await ownedThread(me, threadID);
  if (!thread) return null;
  const user = raw(me);
  const records = await queryWhere("Message", "conversationID", thread.record.recordName, MESSAGE_KEYS);
  const messages = records
    .map((r): ThreadMessage => {
      const type = str(r, "attachmentType");
      const attachmentType = type === "image" || type === "video" || type === "document" || type === "post" ? type : undefined;
      const senderID = raw(str(r, "senderUserID"));
      return {
        id: r.recordName,
        fromMe: senderID === user,
        senderID,
        text: str(r, "content"),
        at: num(r, "timestamp") ?? r.created?.timestamp ?? 0,
        attachmentType,
        attachmentUrl:
          attachmentType === "image" ? asset(r, "attachment", "media.jpg") : attachmentType === "video" ? asset(r, "attachment", "media.mp4") : attachmentType === "document" ? asset(r, "attachment", "file.pdf") : undefined,
        postID: attachmentType === "post" ? str(r, "attachmentFileString") || undefined : undefined,
      };
    })
    .sort((a, b) => a.at - b.at);
  return { other: thread.other, isGroup: thread.isGroup, groupName: str(thread.record, "groupName") || undefined, members: thread.members, messages };
}

/**
 * The title stamped on a group message for the members' push banners: the group's
 * name, or everyone's first names (the full roster, since one record serves them all).
 */
async function groupPushTitle(thread: OwnedThread): Promise<string> {
  const name = str(thread.record, "groupName").trim();
  if (name) return name;
  const directory = await profileDirectory().catch(() => []);
  const people = new Map(directory.map((p) => [raw(p.id), p.name]));
  return groupAutoName(thread.members.map((id) => (people.get(id) ?? "").split(" ")[0]));
}

/** Sends a text message as the visitor, and bumps the thread like the app does. */
export async function sendMessage(me: string, senderName: string, threadID: string, text: string): Promise<string | null> {
  const thread = await ownedThread(me, threadID);
  if (!thread) return "That conversation isn't yours.";
  const now = Date.now();
  const content = text.trim().slice(0, 4000);
  if (!content) return "Write a message first.";
  const user = raw(me);
  const preview = content.slice(0, 200);

  // Group messages list every other member (that's what their push subscriptions
  // match), start with the sender as the only reader, and carry the banner's title.
  const groupFields: Record<string, CKField> = thread.isGroup
    ? {
        recipientUserIDs: { value: thread.members.filter((id) => id !== user), type: "STRING_LIST" },
        readByUserIDs: { value: [user], type: "STRING_LIST" },
        groupName: { value: await groupPushTitle(thread), type: "STRING" },
      }
    : {};

  await modify([
    {
      kind: "save",
      recordType: "Message",
      recordName: crypto.randomUUID().toUpperCase(),
      fields: {
        conversationID: { value: thread.record.recordName, type: "STRING" },
        content: { value: content, type: "STRING" },
        timestamp: { value: now, type: "TIMESTAMP" },
        senderUserID: { value: user, type: "STRING" },
        recipientUserID: { value: thread.other, type: "STRING" },
        isRead: { value: 0, type: "INT64" },
        // These two power the push banner on the recipients' phones.
        senderName: { value: senderName, type: "STRING" },
        messagePreview: { value: preview, type: "STRING" },
        ...groupFields,
      },
    },
  ]);

  // Group previews lead with who said it, since the row is titled by the group.
  const rowPreview = thread.isGroup ? `${senderName.split(" ")[0]}: ${preview}`.slice(0, 200) : preview;
  const error = await updateFields("Conversation", thread.record.recordName, {
    lastMessageTimestamp: { value: now, type: "TIMESTAMP" },
    lastMessagePreview: { value: rowPreview, type: "STRING" },
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
  if (thread.isGroup) {
    // Groups: add the visitor to each unread message's readers (the shared isRead
    // flag would mark it read for everyone).
    const records = await queryWhere("Message", "conversationID", thread.record.recordName, ["senderUserID", "readByUserIDs"]);
    const unread = records.filter((r) => raw(str(r, "senderUserID")) !== user && !list(r, "readByUserIDs").map(raw).includes(user));
    await Promise.all(
      unread.map((r) =>
        updateFields("Message", r.recordName, { readByUserIDs: { value: [...list(r, "readByUserIDs"), user], type: "STRING_LIST" } }).catch(() => null),
      ),
    );
    return;
  }
  const records = await queryWhere("Message", "conversationID", thread.record.recordName, ["recipientUserID", "isRead"]);
  const unread = records.filter((r) => raw(str(r, "recipientUserID")) === user && num(r, "isRead") !== 1);
  await Promise.all(unread.map((r) => updateFields("Message", r.recordName, { isRead: { value: 1, type: "INT64" } }).catch(() => null)));
  if (unread.length) {
    await updateFields("Conversation", thread.record.recordName, { unreadCount: { value: 0, type: "INT64" } }).catch(() => null);
  }
}

/**
 * The app's deterministic thread ID for a pair (Conversation.deterministicID): MD5 of
 * the two bare IDs sorted and joined with "|", stamped as a v5-style UUID, uppercase.
 */
export function conversationIDFor(a: string, b: string): string {
  const key = [raw(a), raw(b)].sort().join("|");
  const bytes = createHash("md5").update(key, "utf8").digest();
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex").toUpperCase();
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/**
 * The visitor's thread with `other`, created the way the app creates it if neither of
 * them has messaged yet. Returns the thread ID to open on the Network page.
 */
export async function threadWith(me: string, other: string): Promise<string> {
  const user = raw(me);
  const them = raw(other);
  if (!user || !them || user === them) throw new Error("Can't message yourself.");
  const id = conversationIDFor(user, them);
  const existing = await lookup(id).catch(() => null);
  if (existing?.recordType === "Conversation") return id;
  // "create" (not replace) so a thread the other person made a moment ago is kept.
  await createRecord("Conversation", id, {
    participant1UserID: { value: user, type: "STRING" },
    participant2UserID: { value: them, type: "STRING" },
    unreadCount: { value: 0, type: "INT64" },
  }, ["participant1UserID", "participant2UserID"]).catch(async (error) => {
    if ((await lookup(id).catch(() => null))?.recordType === "Conversation") return [];
    throw error;
  });
  return id;
}

/**
 * Starts a group chat the way the app's createGroupConversation does: a random-UUID
 * Conversation with isGroup = 1, everyone in participantUserIDs (creator first), the
 * creator as participant1 and "" as participant2. Needs at least two other people;
 * with one, use threadWith. Returns the thread ID to open on the Network page.
 */
export async function createGroupThread(me: string, others: string[], name?: string): Promise<string> {
  const user = raw(me);
  const seen = new Set([user]);
  const members = others.map(raw).filter((id) => id && !seen.has(id) && seen.add(id));
  if (!user) throw new Error("Not signed in.");
  if (members.length < 2) throw new Error("A group needs at least two other people.");
  const id = crypto.randomUUID().toUpperCase();
  const groupName = name?.trim().slice(0, 100);
  await createRecord(
    "Conversation",
    id,
    {
      participant1UserID: { value: user, type: "STRING" },
      participant2UserID: { value: "", type: "STRING" },
      unreadCount: { value: 0, type: "INT64" },
      isGroup: { value: 1, type: "INT64" },
      participantUserIDs: { value: [user, ...members], type: "STRING_LIST" },
      createdByUserID: { value: user, type: "STRING" },
      ...(groupName ? { groupName: { value: groupName, type: "STRING" } } : {}),
    },
    // Without these the record wouldn't be a group anyone could find.
    ["participant1UserID", "isGroup", "participantUserIDs"],
  );
  return id;
}
