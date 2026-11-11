import { NextResponse, type NextRequest } from "next/server";
import { SESSION_COOKIE, decodeSession } from "@/lib/session";
import { discoverItems, feedPosts } from "@/lib/content";
import { isCloudKitConfigured, profileDirectory } from "@/lib/cloudkit/content";
import { getCategory } from "@/lib/categories";
import { personHref } from "@/lib/people";
import { MAX_RESULTS, MIN_QUERY_LENGTH, searchOrderFor, type SearchKind, type SearchResult } from "@/lib/search";

const fold = (s: string | undefined) =>
  (s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

/**
 * How well a result matches, lower is better: 0 name starts with the query,
 * 1 a word in the name does, 2 the name contains it, 3 only other details do.
 */
function matchTier(q: string, name: string, extra: (string | undefined)[]): number | null {
  const n = fold(name);
  if (n.startsWith(q)) return 0;
  if (n.split(/[^a-z0-9]+/).some((w) => w.startsWith(q))) return 1;
  if (n.includes(q)) return 2;
  if (extra.some((e) => fold(e).includes(q))) return 3;
  return null;
}

// GET /api/search?q=...&from=/current/path
// API routes skip the sign-in proxy, so this checks the session itself: the live
// site never shows students' work to anyone who hasn't signed in.
export async function GET(request: NextRequest) {
  const signedIn = decodeSession(request.cookies.get(SESSION_COOKIE)?.value) !== null;
  const guest = process.env.NODE_ENV !== "production" && request.cookies.has("nexus_guest");
  if (!signedIn && !guest) return NextResponse.json({ results: [] }, { status: 401 });

  const q = fold(request.nextUrl.searchParams.get("q")?.trim());
  if (q.length < MIN_QUERY_LENGTH) return NextResponse.json({ results: [] });
  const order = searchOrderFor(request.nextUrl.searchParams.get("from") ?? "/");
  const rank = (k: SearchKind) => order.indexOf(k);

  const [posts, items, people] = await Promise.all([
    feedPosts().catch(() => []),
    discoverItems().catch(() => []),
    isCloudKitConfigured() ? profileDirectory().catch(() => []) : Promise.resolve([]),
  ]);

  const scored: { tier: number; result: SearchResult }[] = [];
  const add = (tier: number | null, result: SearchResult) => {
    if (tier !== null) scored.push({ tier, result });
  };

  for (const p of posts) {
    add(matchTier(q, p.title, [p.creator, p.meta]), {
      kind: "content",
      id: p.id,
      title: p.title,
      subtitle: p.creator ? `${p.creditPrefix ?? "by"} ${p.creator}` : undefined,
      label: getCategory(p.category)?.label ?? "Post",
      imageUrl: p.thumbnailUrl ?? p.images?.[0],
      href: `/post/${encodeURIComponent(p.id)}`,
    });
  }
  for (const i of items) {
    if (i.kind === "project") {
      add(matchTier(q, i.title, [i.logline, i.postedBy, i.studio, ...(i.genres ?? [])]), {
        kind: "project",
        id: i.id,
        title: i.title,
        subtitle: [i.projectType, i.studio || i.postedBy].filter(Boolean).join(" · "),
        label: "Project",
        imageUrl: i.posterUrl ?? i.slides?.[0],
        href: `/discover/${encodeURIComponent(i.id)}`,
      });
    } else {
      add(matchTier(q, i.title, [i.logline, i.host, i.location, i.category, ...(i.lineup ?? [])]), {
        kind: "event",
        id: i.id,
        title: i.title,
        subtitle: [i.when, i.host].filter(Boolean).join(" · "),
        label: "Event",
        imageUrl: i.flyerUrl,
        href: `/discover/${encodeURIComponent(i.id)}`,
      });
    }
  }
  for (const a of people) {
    add(matchTier(q, a.name, a.roles), {
      kind: "artist",
      id: a.id,
      title: a.name,
      subtitle: a.roles.slice(0, 3).join(", ") || undefined,
      label: "Artist",
      imageUrl: a.imageUrl,
      href: personHref(a.name, a.id),
    });
  }

  // Name matches beat matches on other details; within each, this page's priority decides.
  scored.sort(
    (a, b) =>
      Math.min(a.tier, 2) - Math.min(b.tier, 2) ||
      rank(a.result.kind) - rank(b.result.kind) ||
      a.tier - b.tier ||
      a.result.title.localeCompare(b.result.title),
  );
  return NextResponse.json(
    { results: scored.slice(0, MAX_RESULTS).map((s) => s.result) },
    { headers: { "Cache-Control": "private, no-store" } },
  );
}
