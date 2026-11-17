import { cacheLife, cacheTag } from "next/cache";
import { asset, lookup, queryAll, str, updateFields, type CKField, type CKRecord } from "./client";
import { isProfileStyle, parseDetails, type CreativeDetails, type CreativeProfile, type ProfileStyle } from "../profileStyle";

/*
 * Profile styles in CloudKit, shared with the app (CreativeProfileStore.swift):
 *
 *   On the person's own UserProfile record, "UserProfile_<userRecordName>" (2026-11-16;
 *   there is no separate CreativeProfile record type):
 *     style STRING · details STRING (JSON) · headshot ASSET (no updatedAt field: the
 *     record's own modified time is used)
 *   Also on the UserProfile record: directoryGroups STRING, "Actor,Filmmaker,Musician" —
 *     which People pages the app's moderators have put the person on (read here, written
 *     only by the app; see DirectoryPeopleGrid.swift).
 *
 * The style fields have to be in the Production schema before saves work; until then
 * reads come back empty and saves return a clear message.
 */

export const creativeTag = (userRecordName: string) => `creative:${userRecordName}`;
export const CREATIVE_ALL_TAG = "creative:all";

const rawID = (id: string) => id.replace(/^(UserProfile_|CreativeProfile_)/, "");

function parse(r: CKRecord): CreativeProfile | null {
  const style = str(r, "style");
  if (!isProfileStyle(style)) return null;
  return {
    userID: rawID(r.recordName),
    style,
    details: parseDetails(str(r, "details")),
    headshotUrl: asset(r, "headshot", "media.jpg"),
    updatedAt: r.modified?.timestamp ?? r.created?.timestamp ?? 0,
  };
}

/** One person's style profile, by user record name or profile ID. */
export async function getCreativeProfile(id: string): Promise<CreativeProfile | null> {
  "use cache";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  const user = rawID(id);
  cacheTag(creativeTag(user));
  try {
    const r = await lookup(`UserProfile_${user}`);
    return r ? parse(r) : null;
  } catch (error) {
    console.error("[creative] lookup:", error instanceof Error ? error.message : error);
    return null;
  }
}

/** Every style profile, keyed by user record name. Profiles with no style saved are skipped. */
export async function allCreativeProfiles(): Promise<Map<string, CreativeProfile>> {
  "use cache: remote";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  cacheTag(CREATIVE_ALL_TAG);
  const out = new Map<string, CreativeProfile>();
  try {
    for (const r of await queryAll("UserProfile")) {
      const p = parse(r);
      if (p) out.set(p.userID, p);
    }
  } catch (error) {
    console.error("[creative] query:", error instanceof Error ? error.message : error);
  }
  return out;
}

/**
 * The People pages the app's moderators have put each person on, keyed by user record
 * name: the `directoryGroups` field on UserProfile, "Actor,Filmmaker,Musician". People
 * with none are left out.
 */
export async function allDirectoryGroups(): Promise<Map<string, Set<ProfileStyle>>> {
  "use cache: remote";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  cacheTag(CREATIVE_ALL_TAG);
  const out = new Map<string, Set<ProfileStyle>>();
  try {
    for (const r of await queryAll("UserProfile")) {
      const groups = new Set(str(r, "directoryGroups").split(",").map((g) => g.trim()).filter(isProfileStyle));
      if (groups.size) out.set(rawID(r.recordName), groups);
    }
  } catch (error) {
    console.error("[creative] directory groups:", error instanceof Error ? error.message : error);
  }
  return out;
}

/**
 * Saves someone's style and details onto their UserProfile record. Only these fields
 * are written, so the rest of the profile (and an existing headshot, unless a new one
 * is given) is kept. Returns a message on failure.
 */
export async function writeCreativeProfile(
  userRecordName: string,
  style: ProfileStyle,
  details: CreativeDetails,
  headshot?: CKField,
): Promise<string | null> {
  const recordName = `UserProfile_${rawID(userRecordName)}`;
  const fields: Record<string, CKField> = {
    style: { value: style, type: "STRING" },
    details: { value: JSON.stringify(details), type: "STRING" },
  };
  if (headshot) fields.headshot = headshot;
  try {
    const error = await updateFields("UserProfile", recordName, fields);
    if (error) {
      console.error("[creative] save:", error.code, error.reason);
      return describe(error.code, error.reason);
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
  if (/NOT_FOUND|record not found/i.test(text) && !/field|type/i.test(reason)) {
    return "Couldn't find your Nexus profile to save this on.";
  }
  if (/field|schema|record.?type|BAD_REQUEST/i.test(text)) {
    return "CloudKit's UserProfile is missing a field in Production. It needs style (String), details (String) and headshot (Asset), deployed to Production.";
  }
  return "Couldn't save your actor, filmmaker and musician info. Try again in a moment.";
}
