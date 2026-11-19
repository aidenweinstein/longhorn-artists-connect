// Adds the `editorIDs` field (String List) to every post record type in the DEVELOPMENT
// schema, for shared edit access. Development creates a field the first time a record is
// saved with it, so this saves one throwaway record per type with `editorIDs` set, then
// deletes it. Afterwards, deploy the schema to Production in CloudKit Dashboard.
//
// Run from web/:  node scripts/add-editor-ids-dev.mjs
import { createHash, createSign } from "node:crypto";
import { readFileSync } from "node:fs";

const CONTAINER = "iCloud.LAA.Longhorn-Artists-Connect";
const TYPES = [
  "FilmSubmission",
  "MusicSubmission",
  "ReelSubmission",
  "PhotographySubmission",
  "DesignSubmission",
  "ProjectSubmission",
  "EventSubmission",
];

const keyID = readFileSync(".secrets/cloudkit.env", "utf8").match(/CLOUDKIT_KEY_ID\s*=\s*(\S+)/)[1];
const privateKey = readFileSync(".secrets/cloudkit-s2s-key.pem", "utf8");
const subpath = `/database/1/${CONTAINER}/development/public/records/modify`;

async function modify(operations) {
  const body = JSON.stringify({ operations });
  const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const bodyHash = createHash("sha256").update(body).digest("base64");
  const signature = createSign("SHA256").update(`${date}:${bodyHash}:${subpath}`).sign(privateKey, "base64");
  const res = await fetch(`https://api.apple-cloudkit.com${subpath}`, {
    method: "POST",
    body,
    headers: {
      "Content-Type": "application/json",
      "X-Apple-CloudKit-Request-KeyID": keyID,
      "X-Apple-CloudKit-Request-ISO8601Date": date,
      "X-Apple-CloudKit-Request-SignatureV1": signature,
    },
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${json.serverErrorCode ?? ""} ${json.reason ?? ""}`.trim());
  const r = json.records?.[0];
  if (r?.serverErrorCode) throw new Error(`${r.serverErrorCode}: ${r.reason ?? ""}`);
  return r;
}

let failed = 0;
for (const recordType of TYPES) {
  const recordName = `SchemaSetup_editorIDs_${recordType}`;
  try {
    await modify([
      {
        operationType: "forceReplace",
        record: { recordType, recordName, fields: { editorIDs: { value: ["UserProfile_schema-setup"], type: "STRING_LIST" } } },
      },
    ]);
    await modify([{ operationType: "forceDelete", record: { recordName } }]);
    console.log(`OK    ${recordType}: editorIDs added`);
  } catch (error) {
    failed++;
    console.log(`FAIL  ${recordType}: ${error.message}`);
  }
}
console.log(
  failed
    ? `\n${failed} type(s) failed. Copy this output back to Claude.`
    : "\nDone. Now open CloudKit Dashboard and deploy the Development schema to Production.",
);
