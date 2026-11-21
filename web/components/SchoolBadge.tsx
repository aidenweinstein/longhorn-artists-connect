import { currentSession } from "@/lib/account";
import { feedPosts } from "@/lib/content";
import { SCHOOLS, schoolForID, schoolSlugForName } from "@/lib/schools";
import OtherSchools from "./OtherSchools";
import SchoolBadgeLink from "./SchoolBadgeLink";

const row = "flex items-center gap-3.5 rounded-xl px-2 py-2 transition-colors hover:bg-surface";

/** Holds the spot while the session loads. */
export function SchoolBadgePlaceholder() {
  return (
    <div aria-hidden className={row}>
      <span className="h-9 w-9 shrink-0 rounded-full bg-surface" />
    </div>
  );
}

/**
 * Your school's logo and name, at the top of the sidebar above the five main pages.
 * It's the school you signed in with. Guests get none (see VisitorOtherSchools).
 * Opens that school's own feed, with only its posts (the same posts as Home).
 */
export default async function SchoolBadge() {
  const session = await currentSession();
  // A guest has no school of their own: Home is at the top, with every school under it.
  if (!session) return null;
  const school = schoolForID(session.schoolID);
  return (
    <SchoolBadgeLink slug={school.slug} label={`${school.name}, your school`} className={row}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={school.logo} alt="" className="h-9 w-9 shrink-0 rounded-full object-cover" />
      <span className="whitespace-nowrap font-display text-base font-bold leading-tight opacity-0 transition-opacity duration-150 group-data-[open=true]/nav:opacity-100">
        {school.name}
      </span>
    </SchoolBadgeLink>
  );
}

/**
 * Every school's slug, the one with the most posts on its feed first (counted the way
 * /school/<slug> picks them: made or credited by someone there). Ties keep the usual order.
 */
async function schoolsByPosts(): Promise<string[]> {
  const counts = new Map<string, number>();
  try {
    for (const post of await feedPosts()) {
      for (const slug of new Set(post.schoolSlugs ?? [schoolSlugForName(post.school)])) {
        if (slug) counts.set(slug, (counts.get(slug) ?? 0) + 1);
      }
    }
  } catch (error) {
    // Couldn't load the posts: the usual order.
    console.error("[sidebar] school order:", error instanceof Error ? error.message : error);
  }
  return SCHOOLS.map((s, i) => ({ slug: s.slug, n: counts.get(s.slug) ?? 0, i }))
    .sort((a, b) => b.n - a.n || a.i - b.i)
    .map((s) => s.slug);
}

/**
 * The sidebar's other schools: all but the visitor's own (the home school when signed out).
 * Every one is listed, under "Other Schools", the school with the most posts first.
 */
export async function VisitorOtherSchools() {
  const [session, order] = await Promise.all([currentSession(), schoolsByPosts()]);
  // Guests have no school of their own, so every school is listed, under "Schools".
  if (!session) return <OtherSchools mine={null} heading="Schools" order={order} />;
  return <OtherSchools mine={schoolForID(session.schoolID).slug} heading="Other Schools" order={order} />;
}
