"use server";

import { randomUUID } from "node:crypto";
import { currentAccount } from "@/lib/account";
import { createRecord, isCloudKitConfigured, lookup, modify, uploadAsset, type CKField } from "@/lib/cloudkit/client";
import { isAdmin } from "@/lib/featured";
import {
  abortMultipartUpload,
  completeMultipartUpload,
  createMultipartUpload,
  deleteObject,
  getObject,
  isR2Configured,
  objectSize,
  partUploadURLs,
  publicURLFor,
} from "@/lib/r2";
import { SCHOOLS } from "@/lib/schools";
import { SIGNUP_SCHOOLS } from "@/lib/signupSchools";

/**
 * Admin → System check. Runs what a real website submission does, once per school:
 * an upload from the browser to R2, finishing it, moving it on to CloudKit, and saving
 * a post tagged with that school. Each test post is unapproved (never shown on any feed)
 * and is deleted, with its file, before the check finishes.
 */

export type CheckStep = { name: string; ok: boolean; detail?: string };

const RECORD_TYPE = "DesignSubmission";
const s = (value: string): CKField => ({ value, type: "STRING" });
const int = (value: number): CKField => ({ value, type: "INT64" });
const why = (error: unknown) => (error instanceof Error ? error.message : String(error)).slice(0, 400);

async function signedInAdmin() {
  const current = await currentAccount();
  return current && isAdmin(current.session) ? current : null;
}

/** The test file's text for a school: the browser uploads exactly this. */
const testBody = (slug: string) => `Nexus system check for ${slug}. Safe to delete.`;

/** Settings and accounts every submission depends on, whatever the school. */
export async function checkSetup(): Promise<CheckStep[]> {
  const who = await signedInAdmin();
  if (!who) return [{ name: "Admin", ok: false, detail: "Only admins can run the system check." }];
  const steps: CheckStep[] = [];

  steps.push(
    who.account && who.session.userRecordName
      ? { name: "Your account can post", ok: true }
      : { name: "Your account can post", ok: false, detail: "Your admin email has no Nexus account, so the check can't make test posts. Sign in with an email that has one." },
  );

  const r2Vars = ["R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET", "R2_PUBLIC_URL"];
  const missing = r2Vars.filter((v) => !(process.env[v] ?? "").trim());
  const badURL = !missing.includes("R2_PUBLIC_URL") && !/^https:\/\//.test(process.env.R2_PUBLIC_URL ?? "");
  steps.push(
    missing.length || badURL || !isR2Configured()
      ? {
          name: "R2 settings (file uploads)",
          ok: false,
          detail: missing.length
            ? `Missing on this server: ${missing.join(", ")}. Add them in Vercel → Settings → Environment Variables (Production), then redeploy. Until then every upload shows "File uploads aren't set up on this server yet."`
            : "R2_PUBLIC_URL has to start with https://",
        }
      : { name: "R2 settings (file uploads)", ok: true, detail: `Bucket: ${process.env.R2_BUCKET}` },
  );

  steps.push(
    isCloudKitConfigured()
      ? { name: "CloudKit settings (saving posts)", ok: true }
      : { name: "CloudKit settings (saving posts)", ok: false, detail: "The CloudKit server key isn't set on this server, so no post can be saved." },
  );

  const signupIDs = new Set(SIGNUP_SCHOOLS.map((x) => x.id));
  const siteIDs = new Set<string>(SCHOOLS.map((x) => x.slug));
  const noSignup = SCHOOLS.filter((x) => !signupIDs.has(x.slug)).map((x) => x.name);
  const noPage = SIGNUP_SCHOOLS.filter((x) => !siteIDs.has(x.id)).map((x) => x.name);
  steps.push(
    noSignup.length || noPage.length
      ? {
          name: "Schools match between sign-up and the site",
          ok: false,
          detail: [noSignup.length && `No sign-up option: ${noSignup.join(", ")}.`, noPage.length && `Sign-up but no school page: ${noPage.join(", ")}.`]
            .filter(Boolean)
            .join(" "),
        }
      : { name: "Schools match between sign-up and the site", ok: true },
  );
  return steps;
}

export type StartedCheck =
  | { ok: true; key: string; uploadID: string; url: string; body: string }
  | { ok: false; steps: CheckStep[] };

/** Step one for a school: an upload link, the way the Share page gets one. */
export async function startSchoolCheck(slug: string): Promise<StartedCheck> {
  if (!(await signedInAdmin())) return { ok: false, steps: [{ name: "Admin", ok: false, detail: "Only admins can run the system check." }] };
  if (!SCHOOLS.some((x) => x.slug === slug)) return { ok: false, steps: [{ name: "School", ok: false, detail: `Unknown school ${slug}.` }] };
  if (!isR2Configured()) {
    return { ok: false, steps: [{ name: "Start the upload", ok: false, detail: "R2 isn't set up on this server (see Setup above)." }] };
  }
  try {
    const body = testBody(slug);
    const key = `checks/${slug}/${randomUUID()}.txt`;
    const uploadID = await createMultipartUpload(key, "text/plain");
    const [url] = partUploadURLs(key, uploadID, [Buffer.byteLength(body)], 600);
    return { ok: true, key, uploadID, url, body };
  } catch (error) {
    return { ok: false, steps: [{ name: "Start the upload", ok: false, detail: why(error) }] };
  }
}

/** The rest for a school, after the browser sent the file (or failed to). Always cleans up. */
export async function finishSchoolCheck(
  slug: string,
  upload: { key: string; uploadID: string; etag: string | null; browserError: string | null } | null,
): Promise<CheckStep[]> {
  const who = await signedInAdmin();
  if (!who) return [{ name: "Admin", ok: false, detail: "Only admins can run the system check." }];
  if (!SCHOOLS.some((x) => x.slug === slug)) return [{ name: "School", ok: false, detail: `Unknown school ${slug}.` }];
  if (upload && !upload.key.startsWith(`checks/${slug}/`)) return [{ name: "School", ok: false, detail: "That upload isn't a system check file." }];

  const steps: CheckStep[] = [];
  const body = testBody(slug);
  let stored = false;

  if (upload) {
    steps.push({ name: "Start the upload", ok: true });
    if (upload.browserError) {
      steps.push({ name: "Upload from this browser", ok: false, detail: upload.browserError });
    } else if (!upload.etag) {
      steps.push({
        name: "Upload from this browser",
        ok: false,
        detail: "The file went up, but R2 hid its ETag, so the Share page can't finish uploads. Add ETag to exposeHeaders in the bucket's CORS rule (web/scripts/r2-cors.json).",
      });
    } else {
      steps.push({ name: "Upload from this browser", ok: true });
      try {
        await completeMultipartUpload(upload.key, upload.uploadID, [{ partNumber: 1, etag: upload.etag }]);
        const size = await objectSize(upload.key);
        stored = size === Buffer.byteLength(body);
        steps.push(stored ? { name: "Finish the upload", ok: true } : { name: "Finish the upload", ok: false, detail: `Stored size is ${size ?? "missing"}, expected ${Buffer.byteLength(body)}.` });
      } catch (error) {
        steps.push({ name: "Finish the upload", ok: false, detail: why(error) });
      }
      if (stored) {
        try {
          const res = await fetch(publicURLFor(upload.key), { cache: "no-store" });
          const text = res.ok ? await res.text() : "";
          steps.push(
            res.ok && text === body
              ? { name: "File plays from its public address", ok: true }
              : { name: "File plays from its public address", ok: false, detail: `${publicURLFor(upload.key)} answered ${res.status}. Check R2_PUBLIC_URL and that the bucket's public access is on.` },
          );
        } catch (error) {
          steps.push({ name: "File plays from its public address", ok: false, detail: why(error) });
        }
      }
    }
    if (!stored) await abortMultipartUpload(upload.key, upload.uploadID).catch(() => {});
  }

  // Small files go on from R2 to CloudKit when a post is published; then the post is saved.
  const recordName = randomUUID().toUpperCase();
  let saved = false;
  if (!isCloudKitConfigured()) {
    steps.push({ name: "Save a post tagged " + slug, ok: false, detail: "CloudKit isn't set up on this server (see Setup above)." });
  } else if (!who.session.userRecordName) {
    steps.push({ name: "Save a post tagged " + slug, ok: false, detail: "Your admin email has no Nexus account (see Setup above)." });
  } else {
    let asset: CKField | undefined;
    try {
      const bytes = stored && upload ? (await getObject(upload.key)).bytes : new TextEncoder().encode(body);
      asset = await uploadAsset(RECORD_TYPE, recordName, "designThumbnail", bytes, "text/plain");
      steps.push({ name: "Move the file to CloudKit", ok: true });
    } catch (error) {
      steps.push({ name: "Move the file to CloudKit", ok: false, detail: why(error) });
    }
    try {
      const fields: Record<string, CKField> = {
        designTitle: s(`[System check] ${slug}`),
        designCreatedDate: { value: Date.now(), type: "TIMESTAMP" },
        isApproved: int(0), // never on any feed
        submittedBy: s("System check"),
        userID: s(who.session.userRecordName),
        schoolID: s(slug),
      };
      if (asset) fields.designThumbnail = asset;
      const dropped = await createRecord(RECORD_TYPE, recordName, fields, ["designTitle", "isApproved", "submittedBy", "userID", "schoolID"]);
      saved = true;
      steps.push({ name: `Save a post tagged ${slug}`, ok: true, detail: dropped.length ? `CloudKit left off: ${dropped.join(", ")}` : undefined });
    } catch (error) {
      steps.push({ name: `Save a post tagged ${slug}`, ok: false, detail: why(error) });
    }
    if (saved) {
      try {
        const r = await lookup(recordName);
        const school = r?.fields.schoolID?.value;
        const problems = [
          !r && "the post wasn't found",
          r && school !== slug && `its school is "${school ?? "(none)"}"`,
          r && asset && !r.fields.designThumbnail && "its file is missing",
        ].filter(Boolean);
        steps.push(problems.length ? { name: "Read the post back", ok: false, detail: `Saved, but ${problems.join(" and ")}.` } : { name: "Read the post back", ok: true });
      } catch (error) {
        steps.push({ name: "Read the post back", ok: false, detail: why(error) });
      }
    }
  }

  // Clean up: the test post and its file.
  const leftovers: string[] = [];
  if (saved) {
    try {
      await modify([{ kind: "delete", recordName }]);
    } catch (error) {
      leftovers.push(`post ${recordName} (${why(error)})`);
    }
  }
  if (stored && upload) {
    try {
      await deleteObject(upload.key);
    } catch (error) {
      leftovers.push(`file ${upload.key} (${why(error)})`);
    }
  }
  steps.push(leftovers.length ? { name: "Clean up", ok: false, detail: `Couldn't delete: ${leftovers.join("; ")}` } : { name: "Clean up", ok: true });
  return steps;
}
