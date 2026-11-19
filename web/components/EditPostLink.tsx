"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { canEditPost } from "@/app/(app)/share/editActions";
import type { ShareTypeID } from "@/lib/sharePost";

/**
 * "Edit" on a post's page, shown only to the account that made the post. Checked after
 * the page loads, so the post page itself stays the same (and cached) for everyone.
 */
export default function EditPostLink({
  postID,
  type,
  makerProfileID,
  className = "",
}: {
  postID: string;
  type: ShareTypeID;
  /** The post's maker ("UserProfile_<id>"), from the page. */
  makerProfileID?: string;
  className?: string;
}) {
  const [mine, setMine] = useState(false);
  useEffect(() => {
    let live = true;
    if (makerProfileID) canEditPost(makerProfileID).then((ok) => live && setMine(ok), () => {});
    return () => {
      live = false;
    };
  }, [makerProfileID]);
  if (!mine) return null;
  return (
    <Link
      href={`/share/${type}?edit=${encodeURIComponent(postID)}`}
      className={`inline-flex items-center rounded-full border border-border px-4 py-1.5 text-sm font-semibold hover:bg-foreground/5 ${className}`}
    >
      Edit
    </Link>
  );
}
