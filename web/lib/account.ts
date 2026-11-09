import { cookies } from "next/headers";
import { connection } from "next/server";
import { getAccount, getAllPosts, isCloudKitConfigured, type Account } from "./cloudkit/content";
import { detailsFor } from "./postDetails";
import { POSTS, type Post } from "./mockContent";
import { SESSION_COOKIE, decodeSession, type Session } from "./session";

/** The signed-in visitor, from the session cookie. Server-only. */
export async function currentSession(): Promise<Session | null> {
  const value = (await cookies()).get(SESSION_COOKIE)?.value;
  // decodeSession checks the session's age with Date.now(), so it must run at
  // request time, not while Next prerenders the shell or a runtime prefetch.
  await connection();
  return decodeSession(value);
}

/** The signed-in visitor's app profile, when their email is linked to an app account. */
export async function currentAccount(): Promise<{ session: Session; account: Account | null } | null> {
  const session = await currentSession();
  if (!session) return null;
  const account = session.userRecordName && isCloudKitConfigured() ? await getAccount(session.userRecordName) : null;
  return { session, account };
}

const same = (a: string, b: string) => a.trim().toLowerCase() === b.trim().toLowerCase();

/**
 * Posts this account is credited on, matched the way the app's PortfolioView does:
 * by the profile a credit links to, or by name. Being credited as the lead artist
 * (the byline) counts too. Includes festival-bound films, which stay off the feed.
 */
export async function creditedPosts(account: Account): Promise<Post[]> {
  const posts = isCloudKitConfigured() ? (await getAllPosts()).posts : POSTS;
  return posts.filter((post) => isCredited(post, account));
}

export function isCredited(post: Post, account: Account): boolean {
  const d = post.details ?? detailsFor(post);
  const credits = d.creditGroups.flatMap((g) => g.credits);
  const byName = account.name.length > 0;
  return (
    credits.some((c) => c.profileID === account.profileID || (byName && same(c.name, account.name))) ||
    (byName && !!d.byline && same(d.byline, account.name)) ||
    (byName && (post.mainCredits ?? []).some((c) => same(c.name, account.name)))
  );
}

/** Everyone else credited on these posts, counted once each. */
export function collaborators(posts: Post[], account: Account): number {
  const people = new Set<string>();
  for (const post of posts) {
    const d = post.details ?? detailsFor(post);
    for (const c of d.creditGroups.flatMap((g) => g.credits)) {
      if (c.profileID === account.profileID || same(c.name, account.name)) continue;
      people.add(c.profileID ?? `name:${c.name.trim().toLowerCase()}`);
    }
  }
  return people.size;
}

const PROFILE_PREFIX = "UserProfile_";

/**
 * The portfolio behind a /portfolio/<person> link. A linked person is their app
 * profile ID; anyone credited only by name gets a name-only portfolio of the work
 * they're credited on.
 */
export async function personAccount(person: string): Promise<Account | null> {
  if (person.startsWith(PROFILE_PREFIX)) {
    if (!isCloudKitConfigured()) return null;
    return getAccount(person.slice(PROFILE_PREFIX.length));
  }
  const name = person.trim();
  if (!name) return null;
  return { profileID: "", name, bio: "", academicLine: "", school: "", roles: [], portfolioOrder: [], portfolioLayout: {} };
}
