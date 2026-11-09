import type { CategoryId } from "./categories";
import type { PostDetails } from "./postDetails";

// Placeholder posts until CloudKit is connected. Shape mirrors what the feed
// will need: title, creator, school, category.
export type Post = {
  id: string;
  title: string;
  creator: string;
  school: string;
  category: CategoryId;
  meta: string;
  /** Width / height of the media, e.g. 16 / 9. */
  aspect: number;
  videoUrl?: string;
  thumbnailUrl?: string;
  audioUrl?: string;
  /** EP and album posts: every song in running order (the first is audioUrl). */
  tracks?: string[];
  creatorAvatarUrl?: string;
  /** The main credit's app profile, when it's linked to one (used for portfolio links). */
  creatorProfileID?: string;
  /** Everyone sharing the lead credit (co-directors, say), when there's more than one. */
  mainCredits?: { name: string; avatarUrl?: string; profileID?: string }[];
  /** Words before the main credit in the feed, e.g. "Directed by". */
  creditPrefix?: string;
  /** Length of the video or audio in seconds, when it has one. */
  duration?: number;
  /** Photography and design galleries. */
  images?: string[];
  /** Present for real posts; placeholder posts fall back to detailsFor(). */
  details?: PostDetails;
};

export const POSTS: Post[] = [];
