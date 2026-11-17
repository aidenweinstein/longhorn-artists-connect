import type { Post } from "./mockContent";

/**
 * Only what a feed card shows. A full post also carries its description, lyrics,
 * credits and every gallery picture, none of which the feed uses; leaving them out
 * keeps the page small.
 */
export function toCard(post: Post): Post {
  return {
    id: post.id,
    title: post.title,
    creator: post.creator,
    school: post.school,
    category: post.category,
    meta: post.meta,
    aspect: post.aspect,
    videoUrl: post.videoUrl,
    videoCrop: post.videoCrop,
    audioUrl: post.audioUrl,
    thumbnailUrl: post.thumbnailUrl ?? post.images?.[0],
    thumbnailKey: post.thumbnailKey,
    creatorAvatarUrl: post.creatorAvatarUrl,
    creatorAvatarKey: post.creatorAvatarKey,
    creatorProfileID: post.creatorProfileID,
    mainCredits: post.mainCredits?.map((c) => ({ name: c.name, avatarUrl: c.avatarUrl, avatarKey: c.avatarKey, profileID: c.profileID })),
    creditPrefix: post.creditPrefix,
    duration: post.duration,
    imageCount: post.images?.length,
  };
}
