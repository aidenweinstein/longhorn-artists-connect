import type { Session } from "./session";

/*
 * People pages (Filmmakers, Actors, Musicians): who's featured, and applications to
 * be featured. Stored by verification-service (src/people.ts) and only reachable
 * server-side with WEB_CLIENT_TOKEN, like sign-in.
 */

/**
 * `tags` are the app's profile role tags (UserType in UserProfileModel.swift) whose
 * holders can be picked for that page in Manage. Sound Mixer fits film and music both.
 */
export const PEOPLE_PAGES = [
  {
    slug: "filmmakers",
    label: "Filmmakers",
    singular: "filmmaker",
    icon: "film",
    tags: ["Director", "Producer", "Writer", "Editor", "Cinematographer", "Sound Mixer", "Animator", "VFX Artist"],
  },
  { slug: "actors", label: "Actors", singular: "actor", icon: "performance", tags: ["Actor"] },
  { slug: "musicians", label: "Musicians", singular: "musician", icon: "music", tags: ["Musician", "Singer", "Composer", "Sound Mixer"] },
] as const;

export type PeopleSlug = (typeof PEOPLE_PAGES)[number]["slug"];
export const peoplePage = (slug: string) => PEOPLE_PAGES.find((p) => p.slug === slug);

export type Feature = { id: string; category: PeopleSlug; profileID: string; name: string; blurb: string; postIDs: string[] };
export type Application = {
  id: string;
  category: PeopleSlug;
  email: string;
  profileID?: string;
  name: string;
  message: string;
  links: string;
  status: "pending" | "approved" | "declined";
  createdAt: number;
};

/** Admins are the signed-in school emails listed in ADMIN_EMAILS (comma-separated). */
export function isAdmin(session: Session | null): boolean {
  if (!session) return false;
  const admins = (process.env.ADMIN_EMAILS ?? "").split(",").map((e) => e.trim().toLowerCase()).filter(Boolean);
  return admins.includes(session.email.toLowerCase());
}

export class PeopleServiceError extends Error {}

export async function callPeople<T>(path: string, body: unknown): Promise<T> {
  const url = process.env.VERIFICATION_URL?.replace(/\/$/, "");
  const token = process.env.WEB_CLIENT_TOKEN;
  if (!url || !token) throw new PeopleServiceError("People pages aren't set up yet.");
  let res: Response;
  try {
    res = await fetch(`${url}/v1/web/people/${path}`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
      body: JSON.stringify(body),
      cache: "no-store",
    });
  } catch {
    throw new PeopleServiceError("Couldn't reach the server. Try again.");
  }
  const json = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok) throw new PeopleServiceError(String(json.message ?? "Something went wrong. Try again."));
  return json as T;
}

export async function featuresFor(category: PeopleSlug): Promise<Feature[]> {
  try {
    return (await callPeople<{ features: Feature[] }>("list", { category })).features;
  } catch (error) {
    console.error("[people]", error instanceof Error ? error.message : error);
    return [];
  }
}

export type StaffPick = { postID: string; note: string };

/** A named group of posts on the Featured page, below the main picks. */
export type FeaturedCollection = { id: string; title: string; description: string; items: StaffPick[] };

export async function featuredCollections(): Promise<FeaturedCollection[]> {
  try {
    return (await callPeople<{ collections: FeaturedCollection[] }>("collections/list", {})).collections;
  } catch (error) {
    console.error("[featured collections]", error instanceof Error ? error.message : error);
    return [];
  }
}

export async function staffPicks(): Promise<StaffPick[]> {
  try {
    return (await callPeople<{ picks: StaffPick[] }>("picks/list", {})).picks;
  } catch (error) {
    console.error("[staff picks]", error instanceof Error ? error.message : error);
    return [];
  }
}
