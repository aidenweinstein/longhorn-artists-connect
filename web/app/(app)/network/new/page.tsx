import Link from "next/link";
import NewMessage, { type Recipient } from "@/components/NewMessage";
import { currentAccount } from "@/lib/account";
import { isCloudKitConfigured } from "@/lib/cloudkit/client";
import { myConnections } from "@/lib/cloudkit/connections";
import { profileDirectory } from "@/lib/cloudkit/content";

// Private to the signed-in visitor and always current.
export const instant = false;

/** Network → New message: pick one person for a 1:1 chat, or several for a group. */
export default async function NewMessagePage(props: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const to = (await props.searchParams).to;
  const preset = (Array.isArray(to) ? to : to ? [to] : []).filter((id) => typeof id === "string");

  if (!isCloudKitConfigured()) return <Notice text="Messages aren't available on this copy of the site." />;
  const current = await currentAccount();
  if (!current) return <Notice text="Sign in with your school email to send messages." href="/signin" cta="Sign in" />;
  const me = current.session.userRecordName;
  if (!me || !current.account) {
    return <Notice text="This email doesn't have a Nexus account yet. Create one to send messages." href="/signup/finish" cta="Create your account" />;
  }

  const rawID = (id: string) => id.replace(/^UserProfile_/, "");
  const meRaw = rawID(me);
  const [directory, connections] = await Promise.all([
    profileDirectory().catch(() => []),
    myConnections(me).catch(() => ({ requests: [] as string[], connected: [] as string[] })),
  ]);
  const connected = new Set(connections.connected);

  // Everyone on Nexus but the visitor; their connections are suggested first.
  const people: Recipient[] = directory
    .filter((p) => rawID(p.id) !== meRaw)
    .map((p) => ({ profileID: p.id, name: p.name, imageUrl: p.imageUrl, roles: p.roles ?? [], school: p.school || undefined, connected: connected.has(rawID(p.id)) }));

  return <NewMessage people={people} preset={preset.filter((id) => people.some((p) => p.profileID === id))} />;
}

function Notice({ text, href, cta }: { text: string; href?: string; cta?: string }) {
  return (
    <div className="py-24 text-center text-muted">
      <p>{text}</p>
      {href && cta && (
        <Link href={href} className="mt-4 inline-block rounded-full bg-brand px-5 py-2 text-sm font-semibold text-white hover:brightness-110">
          {cta}
        </Link>
      )}
      <Link href="/network" className="mt-4 block text-sm font-semibold text-brand">
        ‹ Back to messages
      </Link>
    </div>
  );
}
