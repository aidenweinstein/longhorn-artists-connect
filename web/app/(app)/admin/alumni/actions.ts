"use server";

import { updateTag } from "next/cache";
import { currentSession } from "@/lib/account";
import { PROFILES_TAG } from "@/lib/cloudkit/content";
import { isAdmin } from "@/lib/featured";
import { callAlumni } from "@/lib/alumniReview";

type Result = { ok: true } | { ok: false; message: string };

/**
 * Approves an alum (they can then post, connect and message) or turns them down (they
 * stay browse-only and leave the list). Re-checks that the caller is an admin: server
 * actions can be called directly, so the page hiding the buttons isn't enough.
 */
export async function decideAlum(userRecordName: string, approve: boolean): Promise<Result> {
  const session = await currentSession();
  if (!isAdmin(session)) return { ok: false, message: "Only admins can do that." };
  if (typeof userRecordName !== "string" || !userRecordName) return { ok: false, message: "Pick someone." };
  try {
    await callAlumni("decide", { userRecordName, approve: approve === true, by: session!.email });
    updateTag(PROFILES_TAG);
    return { ok: true };
  } catch (error) {
    return { ok: false, message: error instanceof Error ? error.message : "Something went wrong. Try again." };
  }
}
