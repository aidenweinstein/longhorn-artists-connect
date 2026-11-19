"use client";

import { createContext, type ReactNode } from "react";

/**
 * The school whose feed a post was opened from. A school's page wraps its grid in this,
 * so its posts open at /school/<slug>/post/<id> and keep that school's colors and
 * sidebar selection; everywhere else posts open at /post/<id>.
 */
export const PostLinkSchool = createContext<string | undefined>(undefined);

export default function PostLinkScope({ school, children }: { school: string; children: ReactNode }) {
  return <PostLinkSchool value={school}>{children}</PostLinkSchool>;
}
