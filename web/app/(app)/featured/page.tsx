import Link from "next/link";
import { ContentCard } from "@/components/ContentGrid";
import { currentSession } from "@/lib/account";
import { findPost } from "@/lib/content";
import { featuredCollections, isAdmin, staffPicks, type StaffPick } from "@/lib/featured";
import type { Post } from "@/lib/mockContent";

// Picks and collections change from the Manage page at any moment, so this renders per request.
export const instant = false;

/** Picks whose post still exists, with that post. A removed post simply drops off. */
async function resolve(picks: StaffPick[]): Promise<{ pick: StaffPick; post: Post }[]> {
  const posts = await Promise.all(picks.map((p) => findPost(p.postID).catch(() => undefined)));
  return picks.flatMap((pick, i) => (posts[i] ? [{ pick, post: posts[i] as Post }] : []));
}

function Grid({ items }: { items: { pick: StaffPick; post: Post }[] }) {
  return (
    <div className="grid grid-cols-1 gap-x-4 gap-y-10 sm:grid-cols-2 lg:grid-cols-3">
      {items.map(({ pick, post }) => (
        <div key={post.id}>
          <ContentCard post={post} />
          {pick.note && <p className="mt-2 pl-12 text-sm italic leading-relaxed text-foreground/80">&ldquo;{pick.note}&rdquo;</p>}
        </div>
      ))}
    </div>
  );
}

/** Featured: the team's picks, then each collection the admins have made. */
export default async function Featured() {
  const [picks, collections, session] = await Promise.all([staffPicks(), featuredCollections(), currentSession()]);
  const [shown, groups] = await Promise.all([
    resolve(picks),
    Promise.all(collections.map(async (c) => ({ collection: c, items: await resolve(c.items) }))),
  ]);
  // Empty collections stay hidden until they have something to show.
  const visible = groups.filter((g) => g.items.length > 0);

  return (
    <div className="mx-auto max-w-[1500px]">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold">Featured</h1>
          <p className="mt-1 text-muted">Work the Nexus team loves right now.</p>
        </div>
        {isAdmin(session) && (
          <Link href="/admin/people#featured" className="rounded-full border border-border px-5 py-2 text-sm font-semibold hover:bg-surface">
            Manage
          </Link>
        )}
      </header>

      {visible.length > 0 && (
        <nav aria-label="Collections" className="mt-5 flex flex-wrap gap-2">
          {visible.map(({ collection }) => (
            <a key={collection.id} href={`#${collection.id}`} className="rounded-full bg-surface px-4 py-1.5 text-sm font-medium hover:bg-foreground/10">
              {collection.title}
            </a>
          ))}
        </nav>
      )}

      {shown.length === 0 && visible.length === 0 ? (
        <p className="py-24 text-center text-muted">Nothing featured yet.</p>
      ) : (
        <div className="mt-8 space-y-14">
          {shown.length > 0 && <Grid items={shown} />}
          {visible.map(({ collection, items }) => (
            <section key={collection.id} id={collection.id} className="scroll-mt-20">
              <h2 className="text-2xl font-bold">{collection.title}</h2>
              {collection.description && <p className="mt-1 text-muted">{collection.description}</p>}
              <div className="mt-5">
                <Grid items={items} />
              </div>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}
