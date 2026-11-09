import { cookies } from "next/headers";
import { currentSession } from "./account";
import { getCreativeProfile } from "./cloudkit/creative";
import { isCloudKitConfigured } from "./cloudkit/client";
import { emptyDetails, isProfileStyle, type CreativeProfile, type ProfileStyle } from "./profileStyle";

/** Holds the style picked at sign-up until the visitor's email is linked to an app account. */
export const STYLE_COOKIE = "nexus_profile_style";

/**
 * The signed-in visitor's profile style: their CloudKit `CreativeProfile` when their
 * email is linked to an app account, otherwise the style they picked at sign-up.
 * `profile` is null when nothing is saved in CloudKit yet. Server-only.
 */
export async function myStyle(): Promise<{
  style: ProfileStyle | null;
  profile: CreativeProfile | null;
  userRecordName?: string;
}> {
  const session = await currentSession();
  if (!session) return { style: null, profile: null };
  const profile =
    session.userRecordName && isCloudKitConfigured() ? await getCreativeProfile(session.userRecordName) : null;
  const cookie = (await cookies()).get(STYLE_COOKIE)?.value;
  const style = profile?.style ?? (isProfileStyle(cookie) ? cookie : null);
  return { style, profile, userRecordName: session.userRecordName };
}

/** The visitor's details, or empty ones to start from. */
export async function myDetails() {
  const { profile } = await myStyle();
  return profile?.details ?? emptyDetails();
}
