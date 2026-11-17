import Link from "next/link";
import ConnectionsList, { type ConnectionPerson } from "@/components/ConnectionsList";
import { currentAccount } from "@/lib/account";
import { isCloudKitConfigured } from "@/lib/cloudkit/client";
import { myConnections } from "@/lib/cloudkit/connections";
import { profileDirectory } from "@/lib/cloudkit/content";

// Private to the signed-in visitor and always current.
export const instant = false;

/** Network → Connections: requests waiting on you, and everyone you're connected with. */
export default async function Connections() {
  return (
    <div className="w-full">
      <header className="mt-4">
        <h1 className="text-3xl font-bold">Connections</h1>
        <p className="mt-1 text-muted">Requests waiting on you, and the people you&apos;re connected with.</p>
      </header>
      <Body />
    </div>
  );
}

async function Body() {
  if (!isCloudKitConfigured()) return <Notice text="Connections aren't available on this copy of the site." />;
  const current = await currentAccount();
  if (!current) return <Notice text="Sign in with your school email to see your connections." href="/signin" cta="Sign in" />;
  const me = current.session.userRecordName;
  if (!me) return <Notice text="This email doesn't have a Nexus account yet. Create one to connect with people." href="/signup/finish" cta="Create your account" />;
  if (!current.account) return <Notice text="Your account couldn't be loaded right now. Try again in a moment." />;

  let ids: Awaited<ReturnType<typeof myConnections>>;
  try {
    ids = await myConnections(me);
  } catch (error) {
    console.error("[connections] list:", error instanceof Error ? error.message : error);
    return <Notice text="Your connections couldn't be loaded right now. Try again in a moment." />;
  }

  // Only people with a profile on Nexus can be listed (and linked to).
  const directory = await profileDirectory().catch(() => []);
  const people = new Map(directory.map((p) => [p.id.replace(/^UserProfile_/, ""), p]));
  const toPeople = (list: string[]): ConnectionPerson[] =>
    list.flatMap((id) => {
      const p = people.get(id);
      return p ? [{ profileID: p.id, name: p.name || "Nexus member", imageUrl: p.imageUrl, roles: p.roles }] : [];
    });

  return <ConnectionsList requests={toPeople(ids.requests)} connected={toPeople(ids.connected).sort((a, b) => a.name.localeCompare(b.name))} />;
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
    </div>
  );
}
