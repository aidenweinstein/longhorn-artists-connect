import { Suspense } from "react";
import Avatar from "@/components/Avatar";
import CategoryFilter from "@/components/CategoryFilter";
import PersonLink from "@/components/PersonLink";
import { CATEGORY_ROLES } from "@/lib/categories";
import { ConnectButton } from "@/components/ProfileActionButtons";
import { currentAccount } from "@/lib/account";
import { connectionLists } from "@/lib/cloudkit/connections";
import { isCloudKitConfigured, profileDirectory } from "@/lib/cloudkit/content";

/** Everyone on Nexus in one dense, alphabetical list, so as many profiles as possible fit on screen. */
export default function Directory(props: PageProps<"/people/directory">) {
  return (
    <div className="w-full">
      <header className="mt-4">
        <h1 className="text-3xl font-bold">Directory</h1>
        <p className="mt-1 text-muted">Everything on Nexus, A to Z.</p>
        <div className="mt-4 overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          <Suspense>
            <CategoryFilter set="category" variant="page" />
          </Suspense>
        </div>
      </header>
      <Suspense fallback={null}>
        <People searchParams={props.searchParams} />
      </Suspense>
    </div>
  );
}

async function People({ searchParams }: { searchParams: PageProps<"/people/directory">["searchParams"] }) {
  const { category } = await searchParams;
  const wanted = typeof category === "string" ? CATEGORY_ROLES[category] : undefined;
  const everyone = await profileDirectory().catch(() => []);
  const people = wanted ? everyone.filter((p) => p.roles.some((r) => wanted.includes(r))) : everyone;

  // The visitor's own connections and the requests waiting on them, above everyone else.
  // Hidden while a category filter is on, so the filter only narrows the full list.
  const current = !wanted && isCloudKitConfigured() ? await currentAccount() : null;
  const me = current?.account ? current.session.userRecordName : undefined;
  const lists = me ? await connectionLists(me).catch(() => null) : null;
  const byID = new Map(everyone.map((p) => [p.id.replace(/^UserProfile_/, ""), p]));
  const requests = (lists?.pending ?? []).flatMap((id) => byID.get(id) ?? []);
  const connections = (lists?.connected ?? []).flatMap((id) => byID.get(id) ?? []).sort((a, b) => a.name.localeCompare(b.name));

  const row = (p: (typeof everyone)[number], action?: React.ReactNode) => (
    <li key={p.id} className="flex items-center justify-between gap-3 border-b border-border">
      <PersonLink name={p.name} profileID={p.id} className="flex min-w-0 flex-1 items-center gap-3 py-2 no-underline hover:bg-surface">
        <Avatar name={p.name} src={p.imageUrl} size="feed" />
        <span className="min-w-0">
          <span className="block truncate text-sm font-semibold">{p.name}</span>
          {p.roles.length > 0 && <span className="block truncate text-xs text-muted">{p.roles.join(", ")}</span>}
        </span>
      </PersonLink>
      {action}
    </li>
  );

  if (people.length === 0) {
    return (
      <p className="py-24 text-center text-muted">
        {everyone.length === 0 ? "The directory isn't available right now. Try again in a moment." : "No one with that role yet."}
      </p>
    );
  }
  return (
    <>
      {requests.length > 0 && (
        <section className="mt-6">
          <h2 className="text-lg font-bold">Requests</h2>
          <ul className="mt-2 grid grid-cols-1 gap-x-6 sm:grid-cols-2 lg:grid-cols-3">
            {requests.map((p) => row(p, <ConnectButton profileID={p.id} name={p.name} initial="incoming" />))}
          </ul>
        </section>
      )}
      {connections.length > 0 && (
        <section className="mt-6">
          <h2 className="text-lg font-bold">Connections</h2>
          <ul className="mt-2 grid grid-cols-1 gap-x-6 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-4">{connections.map((p) => row(p))}</ul>
        </section>
      )}
      {(requests.length > 0 || connections.length > 0) && <h2 className="mt-8 text-lg font-bold">Everyone</h2>}
      <ul className="mt-3 grid grid-cols-1 gap-x-6 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-4">{people.map((p) => row(p))}</ul>
    </>
  );
}
