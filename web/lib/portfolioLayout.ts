import type { Post } from "./mockContent";

/**
 * A portfolio's custom grid. The ORDER lives in UserProfile.portfolioOrder, the same
 * field the app reads and writes. Tile SIZES live in UserProfile.portfolioLayout as
 * JSON ({"<postID>": "medium"}); posts not listed there are small.
 */
export const TILE_SIZES = ["small", "medium", "large"] as const;
export type TileSize = (typeof TILE_SIZES)[number];
export type TileSizes = Record<string, TileSize>;

export const isTileSize = (v: unknown): v is TileSize => TILE_SIZES.includes(v as TileSize);

export function parseTileSizes(raw: string): TileSizes {
  if (!raw) return {};
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
    const out: TileSizes = {};
    for (const [id, size] of Object.entries(parsed)) if (isTileSize(size)) out[id.toUpperCase()] = size;
    return out;
  } catch {
    return {};
  }
}

/** Only non-default sizes are stored, so the field stays small. */
export function serializeTileSizes(sizes: TileSizes): string {
  const kept = Object.fromEntries(Object.entries(sizes).filter(([, s]) => s !== "small"));
  return Object.keys(kept).length ? JSON.stringify(kept) : "";
}

/**
 * Mirrors the app's portfolioSorted(): posts in `order` first, in that order;
 * anything not listed (a new post, say) keeps its existing place after them.
 */
export function sortByOrder(posts: Post[], order: string[]): Post[] {
  if (order.length === 0) return posts;
  const index = new Map<string, number>();
  order.forEach((id, i) => {
    const key = id.toUpperCase();
    if (!index.has(key)) index.set(key, i);
  });
  const listed = posts.filter((p) => index.has(p.id.toUpperCase()));
  const rest = posts.filter((p) => !index.has(p.id.toUpperCase()));
  listed.sort((a, b) => index.get(a.id.toUpperCase())! - index.get(b.id.toUpperCase())!);
  return [...listed, ...rest];
}
