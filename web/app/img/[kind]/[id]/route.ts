import { cacheLife } from "next/cache";
import { NextResponse, type NextRequest } from "next/server";
import { GUEST_COOKIE, SESSION_COOKIE, decodeSession, hasGuestPass } from "@/lib/session";
import { getAllPosts, getDiscoverItems, isCloudKitConfigured, profileImageSource } from "@/lib/cloudkit/content";
import { ALLOWED_WIDTHS } from "@/lib/smallImage";

// GET /img/t/<post ID>?w=480&v=<checksum>        a post's thumbnail
// GET /img/p/<profile ID>?w=96&v=<checksum>      a profile picture
// GET /img/d/<project or event ID>?w=960&v=...   a project poster or event flyer
// GET /img/g/<post ID>?i=2&w=1600&v=...          picture 2 of a post's gallery
//
// Small WebP copies of pictures that CloudKit only keeps at full size. `v` is the
// file's checksum: the same address always means the same picture, so the browser may
// keep it for a year. See lib/smallImage.ts.
//
// Like the other routes outside the pages, this checks the sign-in itself: the live
// site never shows students' work to anyone who hasn't signed in.

const KINDS = ["t", "p", "d", "g"] as const;
type Kind = (typeof KINDS)[number];

export async function GET(request: NextRequest, context: { params: Promise<{ kind: string; id: string }> }) {
  const signedIn = decodeSession(request.cookies.get(SESSION_COOKIE)?.value) !== null;
  const guest = hasGuestPass(request.cookies.get(GUEST_COOKIE)?.value);
  if (!signedIn && !guest) return new NextResponse(null, { status: 401 });
  if (!isCloudKitConfigured()) return new NextResponse(null, { status: 404 });

  const { kind: rawKind, id } = await context.params;
  const query = request.nextUrl.searchParams;
  const checksum = query.get("v") ?? "";
  const kind = KINDS.find((k) => k === rawKind);
  if (!kind || !checksum) return new NextResponse(null, { status: 404 });
  const index = Math.max(0, Math.floor(Number(query.get("i")) || 0));
  const asked = Number(query.get("w")) || ALLOWED_WIDTHS[0];
  const width = ALLOWED_WIDTHS.reduce((best, w) => (Math.abs(w - asked) < Math.abs(best - asked) ? w : best));

  try {
    // The usual case is one small cache read: no CloudKit, no download, no resizing.
    const small = Buffer.from(await smallCopy(kind, id, index, checksum, width), "base64");
    return new NextResponse(new Uint8Array(small), {
      headers: { "content-type": "image/webp", "cache-control": "private, max-age=31536000, immutable" },
    });
  } catch (error) {
    // The picture was replaced since this address was made, or resizing failed. Never
    // leave a hole in the page: send the browser to the current full-size picture.
    const now = await currentSource(kind, id, index).catch(() => undefined);
    if (!now?.url) return new NextResponse(null, { status: 404 });
    // An out-of-date address is expected; anything else is worth a line in the log.
    if (now.key === checksum) console.error("[img]", kind, id, error instanceof Error ? error.message : error);
    return NextResponse.redirect(now.url, { status: 302, headers: { "cache-control": "no-store" } });
  }
}

/** The picture's full-size link and checksum as they are now. */
async function currentSource(kind: Kind, id: string, index: number): Promise<{ url?: string; key?: string } | undefined> {
  if (kind === "p") return profileImageSource(id);
  if (kind === "d") {
    const item = (await getDiscoverItems()).find((i) => i.id === id);
    if (!item) return undefined;
    return item.kind === "project" ? { url: item.posterUrl, key: item.posterKey } : { url: item.flyerUrl, key: item.flyerKey };
  }
  const post = (await getAllPosts()).posts.find((p) => p.id === id);
  if (!post) return undefined;
  return kind === "t" ? { url: post.thumbnailUrl, key: post.thumbnailKey } : { url: post.images?.[index], key: post.imageKeys?.[index] };
}

/**
 * The small copy of one picture, as base64. Kept for two weeks under the picture's
 * checksum and width, in the cache every server shares, so after the first request
 * nobody waits on downloading and shrinking the original again. It only makes a copy of
 * the picture that post, profile, project or event has right now. A failure throws, and
 * errors aren't cached, so the next request simply tries again.
 */
async function smallCopy(kind: Kind, id: string, index: number, checksum: string, width: number): Promise<string> {
  "use cache: remote";
  cacheLife({ stale: 3600, revalidate: 604_800, expire: 1_209_600 });

  const source = await currentSource(kind, id, index);
  if (!source?.url || source.key !== checksum) throw new Error("not the current picture");
  const res = await fetch(source.url, { cache: "no-store" });
  if (!res.ok) throw new Error(`original ${res.status}`);
  const { default: sharp } = await import("sharp");
  const small = await sharp(Buffer.from(await res.arrayBuffer()))
    .rotate() // apply the camera's orientation before the EXIF data is dropped
    .resize({ width, withoutEnlargement: true })
    .webp({ quality: width >= 1600 ? 84 : 78 })
    .toBuffer();
  return small.toString("base64");
}
