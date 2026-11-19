import { NextResponse, type NextRequest } from "next/server";
import { SESSION_COOKIE, decodeSession } from "@/lib/session";
import { isCloudKitConfigured, profileDirectory } from "@/lib/cloudkit/content";
import { fold } from "@/lib/search";
import type { PersonMatch } from "@/lib/sharePost";

const MAX = 6;

// GET /api/people?q=...
// Nexus members whose name matches what's being typed, for the Share forms' cast, crew
// and credit name boxes. Names only: best match first (the name starts with it, then a
// word in the name does). API routes skip the sign-in proxy, so this checks the session.
export async function GET(request: NextRequest) {
  // Only for the Share forms, which guests can't open: guests get nothing.
  const signedIn = decodeSession(request.cookies.get(SESSION_COOKIE)?.value) !== null;
  if (!signedIn) return NextResponse.json({ people: [] }, { status: 401 });

  const q = fold(request.nextUrl.searchParams.get("q")?.trim());
  if (q.length < 2 || !isCloudKitConfigured()) return NextResponse.json({ people: [] });

  const everyone = await profileDirectory().catch(() => []);
  const scored: { tier: number; person: PersonMatch }[] = [];
  for (const p of everyone) {
    const name = fold(p.name);
    const tier = name.startsWith(q) ? 0 : name.split(/[^a-z0-9]+/).some((w) => w.startsWith(q)) ? 1 : null;
    if (tier === null) continue;
    scored.push({ tier, person: { id: p.id, name: p.name, imageUrl: p.imageUrl, subtitle: p.roles.slice(0, 3).join(", ") || undefined } });
  }
  scored.sort((a, b) => a.tier - b.tier || a.person.name.localeCompare(b.person.name));
  return NextResponse.json(
    { people: scored.slice(0, MAX).map((s) => s.person) },
    { headers: { "Cache-Control": "private, no-store" } },
  );
}
