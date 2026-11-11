import { Suspense } from "react";
import Avatar from "@/components/Avatar";
import CategoryFilter from "@/components/CategoryFilter";
import PersonLink from "@/components/PersonLink";
import { CATEGORY_ROLES } from "@/lib/categories";
import { profileDirectory } from "@/lib/cloudkit/content";

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

  if (people.length === 0) {
    return (
      <p className="py-24 text-center text-muted">
        {everyone.length === 0 ? "The directory isn't available right now. Try again in a moment." : "No one with that role yet."}
      </p>
    );
  }
  return (
    <ul className="mt-5 grid grid-cols-1 gap-x-6 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-4">
      {people.map((p) => (
        <li key={p.id} className="border-b border-border">
          <PersonLink name={p.name} profileID={p.id} className="flex items-center gap-3 py-2 no-underline hover:bg-surface">
            <Avatar name={p.name} src={p.imageUrl} size="feed" />
            <span className="min-w-0">
              <span className="block truncate text-sm font-semibold">{p.name}</span>
              {p.roles.length > 0 && <span className="block truncate text-xs text-muted">{p.roles.join(", ")}</span>}
            </span>
          </PersonLink>
        </li>
      ))}
    </ul>
  );
}
