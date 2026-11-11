import { cookies } from "next/headers";
import { connection } from "next/server";
import { getAccount, getAllPosts, isCloudKitConfigured, profileDirectory, type Account } from "./cloudkit/content";
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

// MARK: - Collaborators

/** One person someone has been credited alongside: a row in the Collabs pop-up. */
export type CollaboratorRow = {
  /** Stable identity: their linked profile when there is one, otherwise their name. */
  key: string;
  name: string;
  /** `UserProfile_<id>` for people on Nexus, so the row links to their portfolio. */
  profileID?: string;
  avatarUrl?: string;
  /** How many of these posts the two of them share. */
  sharedPosts: number;
  /** Titles of those shared posts, in the order given. */
  titles: string[];
};

/** Everyone credited alongside a person, split by whether they have a Nexus account. */
export type Collaborators = {
  /** On Nexus: these are the ones the Collabs number counts. */
  members: CollaboratorRow[];
  /** Names typed into credits that don't match a Nexus account: listed, not counted. */
  others: CollaboratorRow[];
};

/** A Nexus account, as far as matching credits needs. */
type DirectoryEntry = { id: string; name: string; imageUrl?: string };
type CreditedPerson = { name: string; profileID?: string; avatarUrl?: string };

const ID_PREFIX = "UserProfile_";
/** Profile IDs are stored both with and without the `UserProfile_` prefix; compare them bare. */
const bareID = (id?: string) => {
  const t = id?.trim();
  if (!t) return undefined;
  return t.startsWith(ID_PREFIX) ? t.slice(ID_PREFIX.length) : t;
};
const nameKey = (name: string) => name.trim().toLowerCase();

/** Everyone credited on a post: every credit, plus a photography post's photographer (its byline), like the app. */
function creditedPeople(post: Post): CreditedPerson[] {
  const d = post.details ?? detailsFor(post);
  const people: CreditedPerson[] = d.creditGroups.flatMap((g) => g.credits);
  if (post.category === "photography" && d.byline?.trim()) people.push({ name: d.byline });
  return people;
}

type Row = CollaboratorRow & { onNexus: boolean };

/**
 * Everyone this account has been credited alongside on `posts`, each person once no
 * matter how many posts or roles they share. Matches the app's CollaborationStats:
 * a credit typed by name on one post and linked to a profile on another is the same
 * person. Only people with a Nexus account count; pass `directory` (every Nexus
 * account) to decide that. Without it, anyone linked to a profile counts.
 */
export function collaboratorList(posts: Post[], account: Account, directory?: DirectoryEntry[]): Collaborators {
  const byID = new Map<string, DirectoryEntry>();
  const nameCounts = new Map<string, number>();
  const byName = new Map<string, DirectoryEntry>();
  for (const entry of directory ?? []) {
    const id = bareID(entry.id);
    if (id) byID.set(id, entry);
    const key = nameKey(entry.name);
    if (!key) continue;
    nameCounts.set(key, (nameCounts.get(key) ?? 0) + 1);
    byName.set(key, entry);
  }
  // Two accounts with the same name can't be told apart by name alone.
  for (const [key, count] of nameCounts) if (count > 1) byName.delete(key);

  // Name → profile, learned from every linked credit, so a typed name joins its linked twin.
  const linkedNames = new Map<string, string>();
  for (const post of posts) {
    for (const c of creditedPeople(post)) {
      const id = bareID(c.profileID);
      const key = nameKey(c.name);
      if (id && key && !linkedNames.has(key)) linkedNames.set(key, id);
    }
  }

  const selfName = nameKey(account.name);
  const selfID = bareID(account.profileID) ?? (selfName ? linkedNames.get(selfName) : undefined);
  const rows = new Map<string, Row>();

  for (const post of posts) {
    const seen = new Set<string>();
    for (const c of creditedPeople(post)) {
      const name = c.name.trim();
      const key = nameKey(name);
      const id = bareID(c.profileID) ?? (key ? linkedNames.get(key) ?? bareID(byName.get(key)?.id) : undefined);
      if (!name && !id) continue;
      // When both sides are linked, trust the IDs: a namesake picked from the directory is someone else.
      const isSelf = selfID && id ? id === selfID : !!selfName && key === selfName;
      if (isSelf) continue;

      const identity = id ? `id:${id}` : `name:${key}`;
      if (seen.has(identity)) continue; // several roles on one post count once
      seen.add(identity);

      const row = rows.get(identity);
      if (row) {
        row.sharedPosts += 1;
        if (post.title) row.titles.push(post.title);
        if (!row.name && name) row.name = name;
        if (!row.avatarUrl) row.avatarUrl = c.avatarUrl;
        continue;
      }
      const member = id ? byID.get(id) : undefined;
      const onNexus = directory ? !!member : !!id;
      rows.set(identity, {
        key: identity,
        name: member?.name || name,
        profileID: onNexus && id ? `${ID_PREFIX}${id}` : undefined,
        avatarUrl: member?.imageUrl ?? c.avatarUrl,
        sharedPosts: 1,
        titles: post.title ? [post.title] : [],
        onNexus,
      });
    }
  }

  const sorted = [...rows.values()].sort((a, b) => b.sharedPosts - a.sharedPosts || a.name.localeCompare(b.name));
  const strip = ({ onNexus, ...row }: Row): CollaboratorRow => (void onNexus, row);
  return {
    members: sorted.filter((r) => r.onNexus).map(strip),
    others: sorted.filter((r) => !r.onNexus).map(strip),
  };
}

/** collaboratorList checked against every Nexus account (live CloudKit when configured). */
export async function collaboratorsFor(posts: Post[], account: Account): Promise<Collaborators> {
  const directory = isCloudKitConfigured() ? await profileDirectory().catch(() => undefined) : undefined;
  return collaboratorList(posts, account, directory);
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
