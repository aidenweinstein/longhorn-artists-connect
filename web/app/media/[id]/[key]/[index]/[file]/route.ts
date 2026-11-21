import { cacheLife } from "next/cache";
import { NextResponse, type NextRequest } from "next/server";
import { GUEST_COOKIE, SESSION_COOKIE, decodeSession, hasGuestPass } from "@/lib/session";
import { isCloudKitConfigured, lookup } from "@/lib/cloudkit/client";
import { MEDIA_FIELDS } from "@/lib/cloudkit/media";

// GET /media/<post ID>/<field>/<index>/<media.mp4>
//
// A post's video or audio file, at an address that never goes stale. CloudKit's
// download links expire, and pages (and the post list behind them, cached for up to an
// hour) would otherwise hand the player a dead link: the video only played after a
// reload. This looks up the post's current link and redirects the player to it.
// Big website uploads live on R2 at permanent links and never come through here.
//
// Like the other routes outside the pages, this checks the sign-in itself.

export async function GET(request: NextRequest, context: { params: Promise<{ id: string; key: string; index: string; file: string }> }) {
  const signedIn = decodeSession(request.cookies.get(SESSION_COOKIE)?.value) !== null;
  const guest = hasGuestPass(request.cookies.get(GUEST_COOKIE)?.value);
  if (!signedIn && !guest) return new NextResponse(null, { status: 401 });
  if (!isCloudKitConfigured()) return new NextResponse(null, { status: 404 });

  const { id, key, index: rawIndex, file } = await context.params;
  const index = Number(rawIndex);
  if (!MEDIA_FIELDS.has(key) || !Number.isInteger(index) || index < 0 || !/^[A-Za-z0-9-]{1,80}$/.test(id) || !/^media\.[a-z0-9]{1,5}$/.test(file)) {
    return new NextResponse(null, { status: 404 });
  }

  const url = await currentLink(id, key, index).catch(() => undefined);
  if (!url) return new NextResponse(null, { status: 404 });
  // The filename tells CloudKit's CDN which Content-Type to send.
  return NextResponse.redirect(url.replace("${f}", file), { status: 302, headers: { "cache-control": "no-store" } });
}

/**
 * The file's current CloudKit download link (with "${f}" still in it). Kept for a minute
 * in the shared cache, so a video's many range requests don't each look the post up,
 * and well before CloudKit's link could expire.
 */
async function currentLink(id: string, key: string, index: number): Promise<string | undefined> {
  "use cache: remote";
  cacheLife({ stale: 30, revalidate: 60, expire: 120 });
  const record = await lookup(id);
  const value = record?.fields[key]?.value as { downloadURL?: string } | { downloadURL?: string }[] | undefined;
  const asset = Array.isArray(value) ? value[index] : index === 0 ? value : undefined;
  return asset?.downloadURL || undefined;
}
