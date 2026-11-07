"use server";

import { updateTag } from "next/cache";
import { currentAccount } from "@/lib/account";
import { updateFields, uploadAsset, type CKField } from "@/lib/cloudkit/client";
import { accountTag } from "@/lib/cloudkit/content";
import { cleanProfile } from "@/lib/profileFields";

const MAX_PHOTO_BYTES = 5 * 1024 * 1024;

/**
 * Saves the signed-in visitor's own profile. Only the session's linked account, and
 * only the fields the app's Edit Profile has; school and verification are never
 * touched. The photo arrives already resized to a JPEG by the browser.
 */
export async function saveProfile(form: FormData): Promise<{ ok: true } | { ok: false; message: string }> {
  const current = await currentAccount();
  const userRecordName = current?.session.userRecordName;
  if (!current?.account || !userRecordName) {
    return { ok: false, message: "Sign in with an email linked to your Nexus account to edit your profile." };
  }

  const p = cleanProfile({
    firstName: form.get("firstName"),
    lastName: form.get("lastName"),
    bio: form.get("bio"),
    roles: form.getAll("roles").map(String),
    isIndustryProfessional: form.get("isIndustryProfessional"),
    major: form.get("major"),
    minor: form.get("minor"),
    certificate: form.get("certificate"),
    graduationYear: form.get("graduationYear"),
    company: form.get("company"),
    companyRole: form.get("companyRole"),
    industry: form.get("industry"),
    instagramHandle: form.get("instagramHandle"),
    websiteURL: form.get("websiteURL"),
    workStatus: form.get("workStatus"),
  });
  if (!p.firstName) return { ok: false, message: "Add your first name." };

  const s = (value: string): CKField => ({ value, type: "STRING" });
  const fields: Record<string, CKField> = {
    firstName: s(p.firstName),
    lastName: s(p.lastName),
    bio: s(p.bio),
    // The app stores roles sorted and comma-joined (rolesString).
    userTypes: s([...p.roles].sort().join(", ")),
    isIndustryProfessional: { value: p.isIndustryProfessional ? 1 : 0, type: "INT64" },
    major: s(p.major),
    minor: s(p.minor),
    certificate: s(p.certificate),
    graduationYear: s(p.graduationYear),
    company: s(p.company),
    companyRole: s(p.companyRole),
    industry: s(p.industry),
    instagramHandle: s(p.instagramHandle),
    websiteURL: s(p.websiteURL),
    workStatus: s(p.workStatus),
  };

  const recordName = `UserProfile_${userRecordName}`;
  try {
    const photo = form.get("photo");
    if (photo instanceof File && photo.size > 0) {
      if (photo.size > MAX_PHOTO_BYTES) return { ok: false, message: "That photo is too large. Try a smaller one." };
      if (!/^image\/(jpeg|png)$/.test(photo.type)) return { ok: false, message: "Use a JPEG or PNG photo." };
      fields.profileImage = await uploadAsset("UserProfile", recordName, "profileImage", new Uint8Array(await photo.arrayBuffer()), photo.type);
    }
    let error = await updateFields("UserProfile", recordName, fields);
    // Until workStatus is in the Production schema, save everything else and say so.
    if (error && /workStatus/i.test(`${error.code} ${error.reason}`)) {
      delete fields.workStatus;
      error = await updateFields("UserProfile", recordName, fields);
      if (!error) {
        updateTag(accountTag(userRecordName));
        return { ok: false, message: "Saved everything except your status. Status needs the workStatus field added in CloudKit first." };
      }
    }
    if (error) {
      console.error("[profile] save failed:", error.code, error.reason);
      return { ok: false, message: "Couldn't save your profile. Try again in a moment." };
    }
  } catch (e) {
    console.error("[profile] save failed:", e instanceof Error ? e.message : e);
    return { ok: false, message: "Couldn't save your profile. Try again in a moment." };
  }

  updateTag(accountTag(userRecordName));
  return { ok: true };
}
