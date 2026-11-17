import NetworkInbox, { type InboxThread, type OpenThread } from "@/components/NetworkInbox";
import { currentAccount } from "@/lib/account";
import { isCloudKitConfigured } from "@/lib/cloudkit/client";
import { getAllPosts, profileDirectory } from "@/lib/cloudkit/content";
import { discoverItems } from "@/lib/content";
import { groupAutoName, messagesIn, threadsFor } from "@/lib/cloudkit/messages";
import { CONVERSATIONS } from "@/lib/mockConversations";
import { posterSource, thumbSrc } from "@/lib/smallImage";

// Private to the signed-in visitor and always current.
export const instant = false;

const tz = "America/Chicago";
const timeFmt = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit", timeZone: tz });
const dayFmt = new Intl.DateTimeFormat("en-US", { weekday: "short", timeZone: tz });
const dateFmt = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", timeZone: tz });
const dayKey = new Intl.DateTimeFormat("en-CA", { year: "numeric", month: "2-digit", day: "2-digit", timeZone: tz });

type SharedPost = NonNullable<OpenThread["messages"][number]["post"]>;

/**
 * What a shared post's bubble shows, for each shared ID in a thread: its picture, title
 * and page. The app shares posts, projects and events the same way, so all three are
 * looked up. An ID that matches nothing (removed, not approved) is left out.
 */
async function sharedPosts(ids: string[]): Promise<Map<string, SharedPost>> {
  const out = new Map<string, SharedPost>();
  if (ids.length === 0) return out;
  const wanted = new Set(ids.map((id) => id.toUpperCase()));
  const [posts, items] = await Promise.all([
    getAllPosts().then((r) => r.posts).catch(() => []),
    discoverItems().catch(() => []),
  ]);
  for (const post of posts) {
    const key = post.id.toUpperCase();
    if (!wanted.has(key)) continue;
    const thumbnailUrl = post.thumbnailUrl ?? post.images?.[0];
    out.set(key, { title: post.title, imageUrl: thumbSrc({ id: post.id, thumbnailUrl, thumbnailKey: post.thumbnailKey }), href: `/post/${post.id}` });
  }
  for (const item of items) {
    const key = item.id.toUpperCase();
    if (!wanted.has(key) || out.has(key)) continue;
    const imageUrl = item.kind === "project" ? posterSource(item.id, item.posterKey, item.posterUrl) : posterSource(item.id, item.flyerKey, item.flyerUrl);
    out.set(key, { title: item.title, imageUrl, href: `/discover/${item.id}` });
  }
  return out;
}

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
        title="Create your Nexus account"
        body="This email doesn't have a Nexus account yet. Create one to see and send messages."
        href="/signup/finish"
        cta="Create your account"
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
  // A thread just started from someone's profile Message button has no messages yet,
  // so threadsFor leaves it out. Put it at the top so it opens ready to type in.
  if (wanted && !summaries.some((t) => t.id === wanted.toUpperCase())) {
    const id = wanted.toUpperCase();
    const fresh = await messagesIn(me, id).catch(() => null);
    if (fresh) {
      summaries = [
        { id, otherUserID: fresh.other, lastMessage: "", lastAt: 0, unread: 0, isGroup: fresh.isGroup, groupName: fresh.groupName, memberIDs: fresh.members },
        ...summaries,
      ];
    }
  }
  const directory = await profileDirectory().catch(() => []);
  const rawID = (id: string) => id.replace(/^UserProfile_/, "");
  const people = new Map(directory.map((p) => [rawID(p.id), p]));
  const meRaw = rawID(me);

  const threads: InboxThread[] = summaries.map((t) => {
    if (t.isGroup) {
      // Groups: their name, or the other members' first names, like the app.
      const others = t.memberIDs.filter((id) => id !== meRaw);
      const name = t.groupName || groupAutoName(others.map((id) => (people.get(id)?.name ?? "").split(" ")[0]));
      return { id: t.id, name, lastMessage: t.lastMessage, time: listTime(t.lastAt), unread: t.unread, isGroup: true, memberCount: t.memberIDs.length };
    }
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

  const openID = (wanted && threads.find((t) => t.id === wanted.toUpperCase())?.id) || threads[0]?.id;
  let open: OpenThread | null = null;
  if (openID) {
    const thread = await messagesIn(me, openID).catch(() => null);
    const summary = threads.find((t) => t.id === openID)!;
    if (thread) {
      const shared = await sharedPosts(thread.messages.flatMap((m) => (m.postID ? [m.postID] : [])));
      open = {
        id: openID,
        name: summary.name,
        imageUrl: summary.imageUrl,
        profileID: summary.profileID,
        isGroup: summary.isGroup,
        memberCount: summary.memberCount,
        messages: thread.messages.map((m) => ({
          ...m,
          // In a group, received bubbles are labelled with who sent them.
          senderName: thread.isGroup && !m.fromMe ? people.get(m.senderID)?.name || "Nexus member" : undefined,
          post: m.postID ? shared.get(m.postID.toUpperCase()) : undefined,
          time: m.at ? `${dateFmt.format(m.at)}, ${timeFmt.format(m.at)}` : "",
        })),
      };
    }
  }

  if (failed) return <Notice title="Couldn't load messages" body="Your messages couldn't be loaded right now. Try again in a moment." />;
  if (threads.length === 0) return <Notice title="No messages yet" body="Start a conversation from someone's profile in the Nexus app and it shows up here." />;
  return <NetworkInbox threads={threads} open={open} openOnPhone={!!wanted} canSend />;
}
