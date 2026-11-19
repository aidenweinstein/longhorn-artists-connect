"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { postAccess } from "@/app/(app)/share/editActions";
import EditAccess from "@/components/EditAccess";
import type { ShareTypeID } from "@/lib/sharePost";

/**
 * "Edit" on a post's page, shown to the account that made the post and to anyone it
 * shared edit access with. The maker also gets "Edit access", to choose those people.
 * Checked after the page loads, so the post page itself stays the same (and cached) for
 * everyone.
 */
export default function EditPostLink({
  postID,
  type,
  makerProfileID,
  editorIDs,
  className = "",
}: {
  postID: string;
  type: ShareTypeID;
  /** The account that posted it ("UserProfile_<id>"), from the page. */
  makerProfileID?: string;
  /** Who else may edit it (profile IDs), from the page. */
  editorIDs?: string[];
  className?: string;
}) {
  const [access, setAccess] = useState({ canEdit: false, isMaker: false });
  const editorsKey = (editorIDs ?? []).join(",");
  useEffect(() => {
    let live = true;
    if (makerProfileID || editorsKey) {
      postAccess(makerProfileID, editorsKey ? editorsKey.split(",") : []).then((a) => live && setAccess(a), () => {});
    }
    return () => {
      live = false;
    };
  }, [makerProfileID, editorsKey]);
  if (!access.canEdit) return null;
  return (
    <div className={`flex items-center gap-2 ${className}`}>
      <Link
        href={`/share/${type}?edit=${encodeURIComponent(postID)}`}
        className="inline-flex items-center rounded-full border border-border px-4 py-1.5 text-sm font-semibold hover:bg-foreground/5"
      >
        Edit
      </Link>
      {access.isMaker && <EditAccess postID={postID} />}
    </div>
  );
}
