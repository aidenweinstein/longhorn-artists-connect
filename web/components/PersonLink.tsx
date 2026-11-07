import Link from "next/link";
import type { Post } from "@/lib/mockContent";
import { isLinkable, personHref } from "@/lib/people";

/** Hover styles only belong on names that can be clicked. */
function withoutHover(className: string) {
  return className
    .split(/\s+/)
    .filter((c) => c && !c.startsWith("hover:") && !c.startsWith("group-hover") && !c.startsWith("group/"))
    .join(" ");
}

/**
 * A person's name that opens their portfolio, only when it's linked to a Nexus
 * account. Anyone else is plain text: not clickable, and no hover underline or colour.
 */
export default function PersonLink({
  name,
  profileID,
  className = "",
  children,
}: {
  name: string;
  profileID?: string;
  className?: string;
  children?: React.ReactNode;
}) {
  if (!profileID || !isLinkable(name)) return <span className={withoutHover(className)}>{children ?? name}</span>;
  return (
    <Link href={personHref(name, profileID)} className={`hover:underline ${className}`}>
      {children ?? name}
    </Link>
  );
}

/** Every main artist, each linked: "Ana Ruiz", "Ana Ruiz & Ben Ode", "Ana, Ben & Cy Lo". */
export function MainArtistLinks({ post, className = "" }: { post: Post; className?: string }) {
  const people = post.mainCredits?.length
    ? post.mainCredits
    : [{ name: post.creator, profileID: post.creatorProfileID }];
  return (
    <>
      {people.map((p, i) => (
        <span key={p.name}>
          {i > 0 && (i === people.length - 1 ? " & " : ", ")}
          <PersonLink name={p.name} profileID={p.profileID} className={className} />
        </span>
      ))}
    </>
  );
}
