import type { CategoryId } from "./categories";
import type { PostDetails } from "./postDetails";

// Placeholder posts until CloudKit is connected. Shape mirrors what the feed
// will need: title, creator, school, category.
export type Post = {
  id: string;
  title: string;
  creator: string;
  school: string;
  /** The schools (lib/schools.ts slugs) of the creator and everyone credited: the school feeds the post is on. */
  schoolSlugs?: string[];
  category: CategoryId;
  meta: string;
  /** Width / height of the media, e.g. 16 / 9. */
  aspect: number;
  videoUrl?: string;
  /** The video's playback crop ("x,y,w,h", see lib/videoCrop.ts), set in the app or on the website. */
  videoCrop?: string;
  thumbnailUrl?: string;
  audioUrl?: string;
  /** Performance posts with several videos (a showcase): every video in order, with its title (the first is videoUrl). */
  videos?: { url: string; title: string; /** Set when the video is an existing post added to a playlist. */ postID?: string }[];
  /** Performance posts that are a playlist of existing posts: those posts' IDs, in order. */
  playlistPostIDs?: string[];
  /** EP and album posts: every song in running order (the first is audioUrl). */
  tracks?: string[];
  creatorAvatarUrl?: string;
  /** Checksums of the thumbnail and the creator's picture: they name the files in small-image addresses. */
  thumbnailKey?: string;
  creatorAvatarKey?: string;
  /** Feed cards carry only how many gallery pictures there are, not the pictures. */
  imageCount?: number;
  /** The main credit's app profile, when it's linked to one (used for portfolio links). */
  creatorProfileID?: string;
  /** Everyone sharing the lead credit (co-directors, say), when there's more than one. */
  mainCredits?: { name: string; avatarUrl?: string; avatarKey?: string; profileID?: string }[];
  /** Words before the main credit in the feed, e.g. "Directed by". */
  creditPrefix?: string;
  /** Length of the video or audio in seconds, when it has one. */
  duration?: number;
  /** Photography and design galleries. */
  images?: string[];
  /** Checksums of `images`, in the same order (see lib/smallImage.ts). */
  imageKeys?: (string | undefined)[];
  /** Present for real posts; placeholder posts fall back to detailsFor(). */
  details?: PostDetails;
};

export const POSTS: Post[] = [];
