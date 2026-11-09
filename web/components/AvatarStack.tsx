import Avatar from "./Avatar";
import PersonLink from "./PersonLink";
import type { Post } from "@/lib/mockContent";

/** Linked main artists' profile pictures, or overlapping pictures when several share the credit. Each opens that person's portfolio. */
export default function AvatarStack({ post, size }: { post: Post; size: "feed" | "md" }) {
  // Only people linked to a Nexus account get a picture.
  const people = (
    post.mainCredits?.length
      ? post.mainCredits
      : [{ name: post.creator, avatarUrl: post.creatorAvatarUrl, profileID: post.creatorProfileID }]
  ).filter((p) => p.profileID);
  if (people.length === 0) return null;
  return (
    <span className="flex shrink-0">
      {people.map((p, i) => (
        <span key={p.name} title={p.name} className={`rounded-full ring-2 ring-background ${i > 0 ? (size === "md" ? "-ml-3" : "-ml-2.5") : ""}`}>
          <PersonLink name={p.name} profileID={p.profileID} className="block rounded-full hover:no-underline">
            <Avatar name={p.name} src={p.avatarUrl} size={size} />
          </PersonLink>
        </span>
      ))}
    </span>
  );
}
