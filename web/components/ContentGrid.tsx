import { getCategory } from "@/lib/categories";
import type { Post } from "@/lib/mockContent";
import { thumbSources } from "@/lib/smallImage";
import MaskImage from "./MaskImage";
import HoverPreview from "./HoverPreview";
import AvatarStack from "./AvatarStack";
import { MainArtistLinks } from "./PersonLink";
import PostLink from "./PostLink";
import Timecode from "./Timecode";

const PLAYABLE = new Set(["film", "performance", "music"]);

export const TINT: Record<string, string> = {
  film: "from-[#3a1d08] to-[#bf5700]",
  music: "from-[#2b1240] to-[#c2410c]",
  performance: "from-[#3b0a1a] to-[#d97706]",
  design: "from-[#0f2a2a] to-[#b45309]",
  photography: "from-[#1c1917] to-[#9a3412]",
};

export const DEFAULT_PREFIX: Record<Post["category"], string> = {
  film: "Directed by",
  music: "by",
  performance: "Performed by",
  design: "Directed by",
  photography: "Shot by",
};

/** Words before the main credit, e.g. "Directed by", "Shot by". */
export function creditPrefix(post: Post) {
  return post.creditPrefix ?? DEFAULT_PREFIX[post.category];
}

/** Every main artist by name: "Ana Ruiz", "Ana Ruiz & Ben Ode", "Ana, Ben & Cy Lo". */
export function mainArtistNames(post: Post) {
  const names = post.mainCredits?.map((c) => c.name) ?? [post.creator];
  return names.length > 1 ? `${names.slice(0, -1).join(", ")} & ${names.at(-1)}` : names[0];
}


export function initials(name: string) {
  return name
    .split(" ")
    .map((w) => w[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();
}

export function ContentCard({ post, priority = false }: { post: Post; priority?: boolean }) {
  const cat = getCategory(post.category)!;
  const thumb = thumbSources(post);
  const imageCount = post.imageCount ?? post.images?.length ?? 0;
  // The picture and title open the post; names and profile pictures open portfolios.
  return (
    <div className="group block">
      <PostLink postID={post.id} mediaUrl={post.videoUrl ?? post.audioUrl} className="block">
        <HoverPreview
          playable={PLAYABLE.has(post.category)}
          videoUrl={post.videoUrl}
          videoCrop={post.videoCrop}
          audioUrl={post.audioUrl}
          thumbnailUrl={thumb.src}
          thumbnailSrcSet={thumb.srcSet}
          aspect={post.aspect}
          priority={priority}
          // The category color is only for cards with no thumbnail. Behind a thumbnail it
          // would peek out along the rounded edges, so those cards sit on black.
          className={`relative overflow-hidden rounded-xl ${thumb.src ? "bg-black" : `bg-gradient-to-br ${TINT[post.category]}`} transition-transform duration-200 group-hover:scale-[1.015]`}
        >
          <MaskImage src={cat.icon} ratio={cat.ratio} className="h-14 text-white/35" />
          {post.duration || post.videoUrl || post.audioUrl ? (
            <Timecode seconds={post.duration} src={post.videoUrl ?? post.audioUrl} kind={post.videoUrl ? "video" : "audio"} />
          ) : imageCount > 1 ? (
            // Photo and design galleries: how many pictures are inside.
            <span
              title={`${imageCount} images`}
              className="absolute z-[1] bottom-2 right-2 flex items-center gap-1 rounded-md bg-black/75 px-1.5 py-0.5 font-mono text-xs font-semibold text-white"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" className="h-3.5 w-3.5" aria-hidden>
                <rect x="7" y="3" width="14" height="14" rx="2" />
                <path d="M17 21H5a2 2 0 0 1-2-2V7" />
              </svg>
              {imageCount}
            </span>
          ) : null}
        </HoverPreview>
      </PostLink>
      <div className="mt-3 flex gap-3">
        <span className="flex h-9 shrink-0 items-center" title={cat.label}>
          <MaskImage src={cat.icon} ratio={cat.ratio} label={cat.label} className="h-4 text-muted" />
        </span>
        <AvatarStack post={post} size="feed" />
        <div className="min-w-0">
          <PostLink postID={post.id} mediaUrl={post.videoUrl ?? post.audioUrl} className="block">
            <h3 className="line-clamp-2 text-[15px] font-semibold leading-snug">{post.title}</h3>
          </PostLink>
          <p className="mt-1 text-sm text-muted">
            {creditPrefix(post)} <MainArtistLinks post={post} className="hover:text-foreground" />
          </p>
          {post.school && <p className="text-sm text-muted">{post.school}</p>}
        </div>
      </div>
    </div>
  );
}

/** Greedy masonry: each post goes into the currently shortest column. */
function toColumns(posts: Post[], count: number): Post[][] {
  const cols: Post[][] = Array.from({ length: count }, () => []);
  const heights = new Array(count).fill(0);
  for (const post of posts) {
    const i = heights.indexOf(Math.min(...heights));
    cols[i].push(post);
    heights[i] += 1 / post.aspect + 0.45;
  }
  return cols;
}

/** Cards in the first rows, which load right away instead of waiting to be scrolled to. */
const ABOVE_THE_FOLD = 6;

/**
 * One masonry layout. `columns` sets how many columns it has at its widest; with
 * `stackOnPhones`, the columns dissolve on phones (display: contents) and every card
 * falls back into one list in feed order, so phones need no copy of their own.
 */
export function Masonry({
  posts,
  columns,
  stackOnPhones,
  className,
}: {
  posts: Post[];
  columns: number;
  stackOnPhones?: boolean;
  className: string;
}) {
  const order = new Map(posts.map((p, i) => [p.id, i]));
  return (
    <div className={`${stackOnPhones ? "flex flex-col gap-8 sm:flex-row sm:items-start sm:gap-4" : "items-start gap-4"} ${className}`}>
      {toColumns(posts, columns).map((col, i) => (
        <div key={i} className={stackOnPhones ? "contents sm:flex sm:min-w-0 sm:flex-1 sm:flex-col sm:gap-8" : "flex min-w-0 flex-1 flex-col gap-8"}>
          {col.map((p) => {
            const n = order.get(p.id) ?? 0;
            return (
              <div key={p.id} style={{ order: n }}>
                <ContentCard post={p} priority={n < ABOVE_THE_FOLD} />
              </div>
            );
          })}
        </div>
      ))}
    </div>
  );
}

export default function ContentGrid({ posts }: { posts: Post[] }) {
  if (posts.length === 0) {
    return <p className="py-20 text-center text-muted">Nothing here yet.</p>;
  }
  // Two copies instead of three: the 2-column layout doubles as the phone layout.
  return (
    <>
      <Masonry posts={posts} columns={2} stackOnPhones className="lg:hidden" />
      <Masonry posts={posts} columns={3} className="hidden lg:flex" />
    </>
  );
}

/** Placeholder cards shown while the feed loads. */
export function FeedSkeleton() {
  const shapes = [16 / 9, 4 / 5, 1, 16 / 9, 1, 4 / 5, 16 / 9, 16 / 9, 1];
  return (
    <div aria-busy="true" aria-label="Loading" className="grid animate-pulse grid-cols-1 items-start gap-x-4 gap-y-8 sm:grid-cols-2 lg:grid-cols-3">
      {shapes.map((aspect, i) => (
        <div key={i} className={i >= 3 ? "hidden sm:block" : undefined}>
          <div className="w-full rounded-xl bg-surface" style={{ aspectRatio: aspect }} />
          <div className="mt-3 flex gap-3">
            <div className="h-9 w-9 shrink-0 rounded-full bg-surface" />
            <div className="flex-1 space-y-2 pt-1">
              <div className="h-3.5 w-3/4 rounded bg-surface" />
              <div className="h-3 w-1/2 rounded bg-surface" />
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}
