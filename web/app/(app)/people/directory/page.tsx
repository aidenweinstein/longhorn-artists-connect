import { Suspense } from "react";
import Avatar from "@/components/Avatar";
import CategoryFilter from "@/components/CategoryFilter";
import PersonLink from "@/components/PersonLink";
import { CATEGORY_ROLES } from "@/lib/categories";
import { profileDirectory } from "@/lib/cloudkit/content";
import { currentSession } from "@/lib/account";
import { schoolForID, schoolForSlug, schoolSlugForName } from "@/lib/schools";

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
  const [everyone, session] = await Promise.all([profileDirectory().catch(() => []), currentSession()]);
  const people = wanted ? everyone.filter((p) => p.roles.some((r) => wanted.includes(r))) : everyone;

  if (people.length === 0) {
    return (
      <p className="py-24 text-center text-muted">
        {everyone.length === 0 ? "The directory isn't available right now. Try again in a moment." : "No one with that role yet."}
      </p>
    );
  }

  // Your own school first, then everyone at other schools (labeled with theirs).
  const mine = schoolForID(session?.schoolID);
  const slugOf = (p: (typeof people)[number]) => schoolSlugForName(p.school);
  const atMine = people.filter((p) => slugOf(p) === mine.slug);
  const atOthers = people.filter((p) => slugOf(p) !== mine.slug);

  return (
    <>
      <Section title={mine.name} people={atMine} empty={`No one from ${mine.name} with that role yet.`} />
      {atOthers.length > 0 && <Section title="Other Schools" people={atOthers} showSchool />}
    </>
  );
}

type Person = Awaited<ReturnType<typeof profileDirectory>>[number];

function Section({ title, people, empty, showSchool = false }: { title: string; people: Person[]; empty?: string; showSchool?: boolean }) {
  return (
    <section className="mt-8">
      <h2 className="text-xl font-semibold">
        {title} <span className="text-base font-normal text-muted">{people.length}</span>
      </h2>
      {people.length === 0 ? (
        <p className="mt-3 text-sm text-muted">{empty}</p>
      ) : (
        <ul className="mt-3 grid grid-cols-1 gap-x-6 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-4">
          {people.map((p) => {
            const school = showSchool ? schoolForSlug(schoolSlugForName(p.school) ?? "") : undefined;
            const detail = [school?.name ?? (showSchool && p.school ? p.school : ""), p.roles.join(", ")].filter(Boolean).join(" · ");
            return (
              <li key={p.id} className="border-b border-border">
                <PersonLink name={p.name} profileID={p.id} className="flex items-center gap-3 py-2 no-underline hover:bg-surface">
                  <Avatar name={p.name} src={p.imageUrl} size="feed" />
                  <span className="min-w-0">
                    <span className="block truncate text-sm font-semibold">{p.name}</span>
                    {detail && <span className="block truncate text-xs text-muted">{detail}</span>}
                  </span>
                </PersonLink>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}
