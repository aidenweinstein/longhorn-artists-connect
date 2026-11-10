import NetworkInbox, { type InboxThread, type OpenThread, type PickerPerson } from "@/components/NetworkInbox";
import { currentAccount } from "@/lib/account";
import { isCloudKitConfigured } from "@/lib/cloudkit/client";
import { profileDirectory } from "@/lib/cloudkit/content";
import { connectionLists } from "@/lib/cloudkit/connections";
import { messagesIn, threadsFor } from "@/lib/cloudkit/messages";
import { CONVERSATIONS } from "@/lib/mockConversations";

// Private to the signed-in visitor and always current.
export const instant = false;

const tz = "America/Chicago";
const timeFmt = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit", timeZone: tz });
const dayFmt = new Intl.DateTimeFormat("en-US", { weekday: "short", timeZone: tz });
const dateFmt = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", timeZone: tz });
const dayKey = new Intl.DateTimeFormat("en-CA", { year: "numeric", month: "2-digit", day: "2-digit", timeZone: tz });

/** "2:14 PM" today, "Yesterday", "Mon" this week, else "Oct 28" — like the app's list. */
function listTime(at: number): string {
  if (!at) return "";
  const now = Date.now();
  const days = Math.round((Date.parse(dayKey.format(now)) - Date.parse(dayKey.format(at))) / 864e5);
  if (days <= 0) return timeFmt.format(at);
  if (days === 1) return "Yesterday";
  if (days < 7) return dayFmt.format(at);
  return dateFmt.format(at);
}

/** The two-pane inbox with nothing open, and a message in the right pane. */
function Notice(notice: { title: string; body: string; href?: string; cta?: string }) {
  return <NetworkInbox threads={[]} open={null} openOnPhone={false} canSend={false} notice={notice} />;
}

export default async function Network(props: PageProps<"/network">) {
  const c = (await props.searchParams).c;
  const wanted = typeof c === "string" ? c : undefined;

  // Without CloudKit (a local copy with no keys) show the placeholder threads.
  if (!isCloudKitConfigured()) {
    const threads: InboxThread[] = CONVERSATIONS.map((t) => ({ id: t.id, name: t.name, lastMessage: t.lastMessage, time: t.timestamp, unread: t.unread ? 1 : 0 }));
    const pick = CONVERSATIONS.find((t) => t.id === wanted) ?? CONVERSATIONS[0];
    const open: OpenThread | null = pick
      ? {
          id: pick.id,
          name: pick.name,
          messages: (pick.messages ?? [{ fromMe: pick.lastMessage.startsWith("You: "), text: pick.lastMessage.replace(/^You: /, "") }]).map((m, i) => ({ id: String(i), fromMe: m.fromMe, text: m.text, at: 0 })),
        }
      : null;
    return <NetworkInbox threads={threads} open={open} openOnPhone={!!wanted} canSend={false} />;
  }

  const current = await currentAccount();
  if (!current) return <Notice title="Sign in to see your messages" body="Sign in with your school email to see and reply to your Nexus messages." href="/signin" cta="Sign in" />;
  const me = current.session.userRecordName;
  if (!me || !current.account) {
    return (
      <Notice
        title="Link your Nexus account"
        body="This email isn't linked to a Nexus account yet. Verify it in the Nexus app, then sign out and back in here to see your messages."
      />
    );
  }

  let summaries: Awaited<ReturnType<typeof threadsFor>> = [];
  let failed = false;
  try {
    summaries = await threadsFor(me);
  } catch (error) {
    console.error("[messages] list:", error instanceof Error ? error.message : error);
    failed = true;
  }
  const directory = await profileDirectory().catch(() => []);
  const people = new Map(directory.map((p) => [p.id.replace(/^UserProfile_/, ""), p]));
  const connected = new Set((await connectionLists(me).catch(() => ({ connected: [] as string[] }))).connected);
  // Everyone the visitor can start a conversation with, their connections first.
  const picker: PickerPerson[] = directory
    .filter((p) => p.id.replace(/^UserProfile_/, "") !== me)
    .map((p) => ({ id: p.id, name: p.name, imageUrl: p.imageUrl, roles: p.roles.join(", "), connected: connected.has(p.id.replace(/^UserProfile_/, "")) }))
    .sort((a, b) => Number(b.connected) - Number(a.connected) || a.name.localeCompare(b.name));

  const threads: InboxThread[] = summaries.map((t) => {
    const person = people.get(t.otherUserID);
    return {
      id: t.id,
      name: person?.name || "Nexus member",
      imageUrl: person?.imageUrl,
      profileID: person?.id,
      lastMessage: t.lastMessage,
      time: listTime(t.lastAt),
      unread: t.unread,
    };
  });

  // A thread started from a profile or the picker has no messages yet, so it isn't in the list: add it.
  if (wanted && !threads.some((t) => t.id === wanted.toUpperCase())) {
    const fresh = await messagesIn(me, wanted).catch(() => null);
    if (fresh) {
      const person = people.get(fresh.other);
      threads.unshift({ id: wanted.toUpperCase(), name: person?.name || "Nexus member", imageUrl: person?.imageUrl, profileID: person?.id, lastMessage: "", time: "", unread: 0 });
    }
  }

  const openID = (wanted && threads.find((t) => t.id === wanted.toUpperCase())?.id) || threads[0]?.id;
  let open: OpenThread | null = null;
  if (openID) {
    const thread = await messagesIn(me, openID).catch(() => null);
    const summary = threads.find((t) => t.id === openID)!;
    if (thread) {
      open = {
        id: openID,
        name: summary.name,
        imageUrl: summary.imageUrl,
        profileID: summary.profileID,
        messages: thread.messages.map((m) => ({ ...m, time: m.at ? `${dateFmt.format(m.at)}, ${timeFmt.format(m.at)}` : "" })),
      };
    }
  }

  if (failed) return <Notice title="Couldn't load messages" body="Your messages couldn't be loaded right now. Try again in a moment." />;
  if (threads.length === 0) return <NetworkInbox threads={[]} open={null} openOnPhone={false} canSend people={picker} notice={{ title: "No messages yet", body: "Press New message, or open someone's portfolio and press Message." }} />;
  return <NetworkInbox threads={threads} open={open} openOnPhone={!!wanted} canSend people={picker} />;
}
