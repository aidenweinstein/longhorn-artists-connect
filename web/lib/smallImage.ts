/**
 * Addresses for small copies of pictures (served by app/img/[kind]/[id]/route.ts).
 * CloudKit only has the full-size upload, behind a link that changes every few minutes,
 * so browsers downloaded the big file again and again. These addresses name the picture
 * by its checksum instead: they stay the same until the picture itself changes, so a
 * browser keeps its copy.
 *
 * Kinds: t = a post's thumbnail, p = a profile picture, d = a project poster or event
 * flyer, g = one picture of a post's gallery (`i` is its place in the gallery).
 */

export const AVATAR_WIDTH = 96;
/** Profile pictures anywhere bigger than a feed avatar (cards, headers, the inbox). */
export const PROFILE_WIDTH = 256;
export const THUMB_WIDTHS = [480, 960] as const;
export const POSTER_WIDTH = 960;
/** Gallery pictures on a post page: sharp on a large screen, far smaller than the upload. */
export const GALLERY_WIDTH = 1600;
/** Every width the image route will make. Anything else is rounded to the nearest one. */
export const ALLOWED_WIDTHS = [AVATAR_WIDTH, PROFILE_WIDTH, ...THUMB_WIDTHS, GALLERY_WIDTH];

type Kind = "t" | "p" | "d" | "g";

function small(kind: Kind, id: string, key: string, width: number, index?: number) {
  const i = index === undefined ? "" : `&i=${index}`;
  return `/img/${kind}/${encodeURIComponent(id)}?w=${width}${i}&v=${encodeURIComponent(key)}`;
}

type Thumb = { id: string; thumbnailUrl?: string; thumbnailKey?: string };

/** A post thumbnail for a feed card: `src` plus a `srcSet` so sharp screens get the larger copy. */
export function thumbSources(post: Thumb): { src?: string; srcSet?: string } {
  if (!post.thumbnailUrl || !post.thumbnailKey) return { src: post.thumbnailUrl };
  const key = post.thumbnailKey;
  return {
    src: small("t", post.id, key, THUMB_WIDTHS[0]),
    srcSet: THUMB_WIDTHS.map((w) => `${small("t", post.id, key, w)} ${w}w`).join(", "),
  };
}

/** A post thumbnail at one size, for small tiles (480) or a wide banner (960). */
export function thumbSrc(post: Thumb, width: (typeof THUMB_WIDTHS)[number] = 480): string | undefined {
  if (!post.thumbnailUrl || !post.thumbnailKey) return post.thumbnailUrl;
  return small("t", post.id, post.thumbnailKey, width);
}

/** A profile picture at feed-avatar size, or the original when its checksum isn't known. */
export function avatarSource(person: { profileID?: string; avatarUrl?: string; avatarKey?: string }) {
  if (!person.avatarUrl || !person.avatarKey || !person.profileID) return person.avatarUrl;
  return small("p", person.profileID, person.avatarKey, AVATAR_WIDTH);
}

/** A profile picture for cards and headers. */
export function profileImage(profileID: string, key: string | undefined, url: string | undefined) {
  return url && key ? small("p", profileID, key, PROFILE_WIDTH) : url;
}

/** A project's poster or an event's flyer for cards and lists. */
export function posterSource(id: string, key: string | undefined, url: string | undefined) {
  return url && key ? small("d", id, key, POSTER_WIDTH) : url;
}

/** A post's gallery at screen size, in the same order as `images`. */
export function gallerySources(post: { id: string; images?: string[]; imageKeys?: (string | undefined)[] }): string[] {
  return (post.images ?? []).map((url, i) => {
    const key = post.imageKeys?.[i];
    return key ? small("g", post.id, key, GALLERY_WIDTH, i) : url;
  });
}
