"use client";

import Link from "next/link";
import { useContext, type ComponentProps } from "react";
import { primePlayback } from "@/lib/primedPlayback";
import { PostLinkSchool } from "./PostLinkScope";

/**
 * A link that opens a post and readies its video or song to play with sound. Inside a
 * school's feed (PostLinkScope), or given `school`, it opens under that school's address
 * so the page stays in that school's colors.
 */
export default function PostLink({
  postID,
  mediaUrl,
  school,
  ...props
}: Omit<ComponentProps<typeof Link>, "href"> & { postID: string; mediaUrl?: string; school?: string }) {
  const scoped = useContext(PostLinkSchool);
  const slug = school ?? scoped;
  return (
    <Link
      {...props}
      href={slug ? `/school/${slug}/post/${postID}` : `/post/${postID}`}
      onClick={(e) => {
        props.onClick?.(e);
        // Only for a plain click that navigates here, not a new-tab or modified click.
        if (mediaUrl && !e.defaultPrevented && e.button === 0 && !e.metaKey && !e.ctrlKey && !e.shiftKey && !e.altKey) {
          primePlayback(postID, mediaUrl);
        }
      }}
    />
  );
}
