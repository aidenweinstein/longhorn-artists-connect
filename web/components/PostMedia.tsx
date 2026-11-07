import { getCategory } from "@/lib/categories";
import type { Post } from "@/lib/mockContent";
import { TINT } from "./ContentGrid";
import { Video } from "./Media";
import MaskImage from "./MaskImage";

/** The main media for a post's detail page: video, cover art, or the first image. */
export default function PostMedia({ post }: { post: Post }) {
  const cat = getCategory(post.category)!;
  if (post.videoUrl) {
    return (
      <Video
        autoStart
        controls
        playsInline
        preload="metadata"
        poster={post.thumbnailUrl}
        src={post.videoUrl}
        className="h-full w-full object-contain"
      />
    );
  }
  const still = post.thumbnailUrl ?? post.images?.[0];
  if (still) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={still} alt="" className="h-full w-full object-contain" />;
  }
  return (
    <div className={`flex h-full w-full items-center justify-center bg-gradient-to-br ${TINT[post.category]}`}>
      <MaskImage src={cat.icon} ratio={cat.ratio} className="h-20 text-white/35" />
    </div>
  );
}
