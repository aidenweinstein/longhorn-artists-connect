"use client";

import Link from "next/link";
import type { ComponentProps } from "react";
import { primePlayback } from "@/lib/primedPlayback";

/** A link that opens a post and readies its video or song to play with sound. */
export default function PostLink({
  postID,
  mediaUrl,
  ...props
}: Omit<ComponentProps<typeof Link>, "href"> & { postID: string; mediaUrl?: string }) {
  return (
    <Link
      {...props}
      href={`/post/${postID}`}
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
