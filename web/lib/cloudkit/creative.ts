import { cacheLife, cacheTag } from "next/cache";
import { asset, lookup, modify, num, queryAll, str, updateFields, type CKField, type CKRecord } from "./client";
import { isProfileStyle, parseDetails, type CreativeDetails, type CreativeProfile, type ProfileStyle } from "../profileStyle";

/*
 * Profile styles in CloudKit, shared with the app (CreativeProfileStore.swift):
 *
 *   CreativeProfile   "CreativeProfile_<userRecordName>"
 *     style STRING · details STRING (JSON) · headshot ASSET · updatedAt TIMESTAMP
 *   DirectoryListing  "listing_<userRecordName>"   (moderator decisions)
 *     userID STRING · style STRING · status STRING ("approved"/"declined") · modifiedAt TIMESTAMP
 *
 * Both types have to exist in the Production schema (with recordName queryable) before
 * saves work; until then reads come back empty and saves return a clear message.
 */

export const creativeTag = (userRecordName: string) => `creative:${userRecordName}`;
export const CREATIVE_ALL_TAG = "creative:all";

const rawID = (id: string) => id.replace(/^(UserProfile_|CreativeProfile_|listing_)/, "");

function parse(r: CKRecord): CreativeProfile | null {
  const style = str(r, "style");
  if (!isProfileStyle(style)) return null;
  return {
    userID: rawID(r.recordName),
    style,
    details: parseDetails(str(r, "details")),
    headshotUrl: asset(r, "headshot", "media.jpg"),
    updatedAt: num(r, "updatedAt") ?? r.created?.timestamp ?? 0,
  };
}

/** One person's style profile, by user record name or profile ID. */
export async function getCreativeProfile(id: string): Promise<CreativeProfile | null> {
  "use cache";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  const user = rawID(id);
  cacheTag(creativeTag(user));
  try {
    const r = await lookup(`CreativeProfile_${user}`);
    return r ? parse(r) : null;
  } catch (error) {
    console.error("[creative] lookup:", error instanceof Error ? error.message : error);
    return null;
  }
}

/** Every style profile, keyed by user record name. Empty until the record type exists. */
export async function allCreativeProfiles(): Promise<Map<string, CreativeProfile>> {
  "use cache";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  cacheTag(CREATIVE_ALL_TAG);
  const out = new Map<string, CreativeProfile>();
  try {
    for (const r of await queryAll("CreativeProfile")) {
      const p = parse(r);
      if (p) out.set(p.userID, p);
    }
  } catch (error) {
    console.error("[creative] query:", error instanceof Error ? error.message : error);
  }
  return out;
}

export type Listing = { userID: string; style: ProfileStyle; status: "approved" | "declined"; modifiedAt: number };

/** Moderator decisions, keyed by user record name. */
export async function allListings(): Promise<Map<string, Listing>> {
  "use cache";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  cacheTag(CREATIVE_ALL_TAG);
  const out = new Map<string, Listing>();
  try {
    for (const r of await queryAll("DirectoryListing")) {
      const style = str(r, "style");
      const status = str(r, "status");
      if (!isProfileStyle(style) || (status !== "approved" && status !== "declined")) continue;
      const userID = rawID(str(r, "userID") || r.recordName);
      out.set(userID, { userID, style, status, modifiedAt: num(r, "modifiedAt") ?? 0 });
    }
  } catch (error) {
    console.error("[creative] listings:", error instanceof Error ? error.message : error);
  }
  return out;
}

/**
 * Saves someone's style and details. Updates the record when it exists (so an
 * existing headshot is kept unless a new one is given), otherwise creates it.
 * Returns a message on failure.
 */
export async function writeCreativeProfile(
  userRecordName: string,
  style: ProfileStyle,
  details: CreativeDetails,
  headshot?: CKField,
): Promise<string | null> {
  const recordName = `CreativeProfile_${userRecordName}`;
  const fields: Record<string, CKField> = {
    style: { value: style, type: "STRING" },
    details: { value: JSON.stringify(details), type: "STRING" },
    updatedAt: { value: Date.now(), type: "TIMESTAMP" },
  };
  if (headshot) fields.headshot = headshot;
  try {
    const existing = await lookup(recordName);
    if (existing) {
      const error = await updateFields("CreativeProfile", recordName, fields);
      if (error) return describe(error.code, error.reason);
    } else {
      await modify([{ kind: "save", recordType: "CreativeProfile", recordName, fields }]);
    }
    return null;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("[creative] save:", message);
    return describe("", message);
  }
}

function describe(code: string, reason: string): string {
  const text = `${code} ${reason}`;
  if (/did not find record type|unknown.*type|BAD_REQUEST.*CreativeProfile|Cannot create new type/i.test(text)) {
    return "Profile styles aren't set up in CloudKit yet. Add the CreativeProfile record type in CloudKit Dashboard, then try again.";
  }
  return "Couldn't save your profile style. Try again in a moment.";
}

/** Moderator decision: puts a profile on (or keeps it off) its style's page in the app too. */
export async function writeListing(userRecordName: string, style: ProfileStyle, status: "approved" | "declined"): Promise<void> {
  const user = rawID(userRecordName);
  await modify([
    {
      kind: "save",
      recordType: "DirectoryListing",
      recordName: `listing_${user}`,
      fields: {
        userID: { value: user, type: "STRING" },
        style: { value: style, type: "STRING" },
        status: { value: status, type: "STRING" },
        modifiedAt: { value: Date.now(), type: "TIMESTAMP" },
      },
    },
  ]);
}
