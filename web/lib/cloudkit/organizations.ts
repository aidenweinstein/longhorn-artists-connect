import { cacheLife, cacheTag } from "next/cache";
import { asset, num, queryAll, str, type CKRecord } from "./client";

/**
 * The parts of an organization that live in CloudKit, shared with the app: a
 * description or profile picture set there, and the posts moderators have added to
 * an org's sections (`OrgContentLink`). Cached a few minutes like the rest.
 */

async function safe(type: string): Promise<CKRecord[]> {
  try {
    return await queryAll(type);
  } catch (error) {
    // Expected until the type is in the Production schema with recordName queryable;
    // the site then runs on the app's built-in organization details alone.
    console.warn(`[cloudkit] ${type} unavailable:`, (error instanceof Error ? error.message : String(error)).split("\n")[0]);
    return [];
  }
}

export type OrgOverride = { description?: string; imageUrl?: string };

export async function getOrgOverrides(): Promise<Record<string, OrgOverride>> {
  "use cache: remote";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  cacheTag("organizations");

  const out: Record<string, OrgOverride> = {};
  for (const r of await safe("Organization")) {
    const slug = str(r, "slug");
    if (!slug) continue;
    out[slug] = {
      description: str(r, "orgDescription").trim() || undefined,
      imageUrl: asset(r, "profileImage", "media.jpg"),
    };
  }
  return out;
}

export type OrgLink = { orgSlug: string; section: string; postID: string; season: string; order: number };

export async function getOrgLinks(): Promise<OrgLink[]> {
  "use cache: remote";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  cacheTag("organizations");

  return (await safe("OrgContentLink"))
    .map((r) => ({
      orgSlug: str(r, "orgSlug"),
      section: str(r, "section"),
      postID: str(r, "submissionID").toUpperCase(),
      season: str(r, "season"),
      order: num(r, "order") ?? 0,
    }))
    .filter((l) => l.orgSlug && l.section && l.postID)
    .sort((a, b) => a.order - b.order);
}
