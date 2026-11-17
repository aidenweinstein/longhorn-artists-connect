import { NextResponse, type NextRequest } from "next/server";
import { GUEST_COOKIE, SESSION_COOKIE, decodeSession, hasGuestPass } from "@/lib/session";
import { discoverItems, feedPosts, organizations } from "@/lib/content";
import { isCloudKitConfigured, profileDirectory } from "@/lib/cloudkit/content";
import { allCreativeProfiles } from "@/lib/cloudkit/creative";
import { getCategory } from "@/lib/categories";
import { SECTION_TITLES } from "@/lib/organizations";
import { personHref } from "@/lib/people";
import { thumbSrc } from "@/lib/smallImage";
import { STYLE_INFO, suggestedStyle, type CreativeProfile } from "@/lib/profileStyle";
import {
  MAX_RESULTS,
  MIN_QUERY_LENGTH,
  discoverSearchExtras,
  fold,
  postSearchExtras,
  searchOrderFor,
  typeWords,
  type SearchKind,
  type SearchResult,
} from "@/lib/search";

/**
 * How well a result matches, lower is better: 0 name starts with the query,
 * 1 a word in the name does, 2 the name contains it, 3 only other details do
 * (its type, genres, credits, roles...).
 */
function matchTier(q: string, name: string, extra: (string | undefined)[]): number | null {
  const n = fold(name);
  if (n.startsWith(q)) return 0;
  if (n.split(/[^a-z0-9]+/).some((w) => w.startsWith(q))) return 1;
  if (n.includes(q)) return 2;
  if (extra.some((e) => fold(e).includes(q))) return 3;
  return null;
}

/** What someone filled in under Actor Info, Filmmaker Info and Musician Info that's worth finding them by. */
function creativeExtras(c: CreativeProfile | undefined): string[] {
  if (!c) return [];
  const { actor, filmmaker, musician } = c.details;
  return [actor.specialSkills, actor.languages, filmmaker.studios, filmmaker.certifications, musician.bandName, musician.instruments, musician.genres];
}

// GET /api/search?q=...&from=/current/path
// Searches everything on Nexus: every kind of post (film, music, performance, design,
// photography), projects, events, organizations, and every profile (filmmakers, actors,
// musicians and anyone else with an account).
// API routes skip the sign-in proxy, so this checks the session itself: the live
// site never shows students' work to anyone who hasn't signed in.
export async function GET(request: NextRequest) {
  const signedIn = decodeSession(request.cookies.get(SESSION_COOKIE)?.value) !== null;
  const guest = hasGuestPass(request.cookies.get(GUEST_COOKIE)?.value);
  if (!signedIn && !guest) return NextResponse.json({ results: [] }, { status: 401 });

  const q = fold(request.nextUrl.searchParams.get("q")?.trim());
  if (q.length < MIN_QUERY_LENGTH) return NextResponse.json({ results: [] });
  const order = searchOrderFor(request.nextUrl.searchParams.get("from") ?? "/");
  const rank = (k: SearchKind) => order.indexOf(k);

  const live = isCloudKitConfigured();
  const [posts, items, orgs, people, creatives] = await Promise.all([
    feedPosts().catch(() => []),
    discoverItems().catch(() => []),
    organizations().catch(() => []),
    live ? profileDirectory().catch(() => []) : Promise.resolve([]),
    live ? allCreativeProfiles().catch(() => new Map<string, CreativeProfile>()) : Promise.resolve(new Map<string, CreativeProfile>()),
  ]);

  const scored: { tier: number; result: SearchResult }[] = [];
  const add = (tier: number | null, result: SearchResult) => {
    if (tier !== null) scored.push({ tier, result });
  };

  for (const p of posts) {
    add(matchTier(q, p.title, postSearchExtras(p)), {
      kind: "content",
      id: p.id,
      title: p.title,
      subtitle: p.creator ? `${p.creditPrefix ?? "by"} ${p.creator}` : undefined,
      label: getCategory(p.category)?.label ?? "Post",
      imageUrl: thumbSrc(p) ?? p.images?.[0],
      href: `/post/${encodeURIComponent(p.id)}`,
    });
  }
  for (const i of items) {
    if (i.kind === "project") {
      add(matchTier(q, i.title, discoverSearchExtras(i)), {
        kind: "project",
        id: i.id,
        title: i.title,
        subtitle: [i.projectType, i.studio || i.postedBy].filter(Boolean).join(" · "),
        label: "Project",
        imageUrl: i.posterSmallUrl ?? i.posterUrl ?? i.slides?.[0],
        href: `/discover/${encodeURIComponent(i.id)}`,
      });
    } else {
      add(matchTier(q, i.title, discoverSearchExtras(i)), {
        kind: "event",
        id: i.id,
        title: i.title,
        subtitle: [i.when, i.host].filter(Boolean).join(" · "),
        label: "Event",
        imageUrl: i.flyerSmallUrl ?? i.flyerUrl,
        href: `/discover/${encodeURIComponent(i.id)}`,
      });
    }
  }
  for (const o of orgs) {
    add(matchTier(q, o.name, [...typeWords("Organization"), o.description, ...o.sections.map((s) => SECTION_TITLES[s])]), {
      kind: "organization",
      id: o.slug,
      title: o.name,
      subtitle: o.description || undefined,
      label: "Organization",
      imageUrl: o.imageUrl,
      href: `/discover/organizations/${encodeURIComponent(o.slug)}`,
    });
  }
  for (const a of people) {
    // Their profile type: the one they chose, or else the one their role tags point to.
    const creative = creatives.get(a.id.replace(/^UserProfile_/, ""));
    const style = creative?.style ?? suggestedStyle(a.roles);
    const stageName = creative?.details.musician.soloName.trim();
    const extras = [...a.roles, ...(style ? [style, STYLE_INFO[style].plural] : []), ...typeWords("Artist"), ...creativeExtras(creative)];
    // A musician's artist name counts as a name too.
    const tiers = [matchTier(q, a.name, extras), stageName ? matchTier(q, stageName, []) : null].filter((t) => t !== null);
    add(tiers.length ? Math.min(...tiers) : null, {
      kind: "artist",
      id: a.id,
      title: a.name,
      subtitle: [stageName && fold(stageName) !== fold(a.name) ? stageName : "", a.roles.slice(0, 3).join(", ")].filter(Boolean).join(" · ") || undefined,
      label: style ?? "Artist",
      imageUrl: a.imageUrl,
      href: personHref(a.name, a.id),
    });
  }

  // Name matches come first; within them, this page's priority decides.
  const byName = scored
    .filter((s) => s.tier < 3)
    .sort((a, b) => rank(a.result.kind) - rank(b.result.kind) || a.tier - b.tier || a.result.title.localeCompare(b.result.title));
  // Matches on other details (typing a type like "music" or "actors", a genre, a credit)
  // take turns by kind in this page's order, so one big kind can't crowd out the rest.
  const queues = order.map((kind) =>
    scored.filter((s) => s.tier === 3 && s.result.kind === kind).sort((a, b) => a.result.title.localeCompare(b.result.title)),
  );
  const byDetail: typeof scored = [];
  for (let turn = 0; queues.some((queue) => turn < queue.length); turn++) {
    for (const queue of queues) if (turn < queue.length) byDetail.push(queue[turn]);
  }

  return NextResponse.json(
    { results: [...byName, ...byDetail].slice(0, MAX_RESULTS).map((s) => s.result) },
    { headers: { "Cache-Control": "private, no-store" } },
  );
}
