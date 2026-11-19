// Read-only check that the Production schema accepts the website's lookups:
// org record types and the group-chat list fields. Run from web/:  node scripts/check-schema.mjs
import { createHash, createSign } from "node:crypto";
import { readFileSync } from "node:fs";
const web = ".";
const keyID = readFileSync(`${web}/.secrets/cloudkit.env`, "utf8").match(/CLOUDKIT_KEY_ID\s*=\s*(\S+)/)[1];
const privateKey = readFileSync(`${web}/.secrets/cloudkit-s2s-key.pem`, "utf8");
const subpath = "/database/1/iCloud.LAA.Longhorn-Artists-Connect/production/public/records/query";
async function q(label, query) {
  const body = JSON.stringify({ query, resultsLimit: 1 });
  const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const bodyHash = createHash("sha256").update(body).digest("base64");
  const sig = createSign("SHA256").update(`${date}:${bodyHash}:${subpath}`).sign(privateKey, "base64");
  const res = await fetch(`https://api.apple-cloudkit.com${subpath}`, { method: "POST", body, headers: {
    "Content-Type": "application/json", "X-Apple-CloudKit-Request-KeyID": keyID,
    "X-Apple-CloudKit-Request-ISO8601Date": date, "X-Apple-CloudKit-Request-SignatureV1": sig } });
  const j = await res.json().catch(() => ({}));
  console.log(res.ok ? "OK  " : "FAIL", label, res.ok ? `(${(j.records||[]).length} rec)` : `${j.serverErrorCode}: ${j.reason}`);
}
const lc = (f) => [{ fieldName: f, comparator: "LIST_CONTAINS", fieldValue: { value: "nobody" } }];
await q("Organization (recordName queryable)", { recordType: "Organization" });
await q("OrgContentLink (recordName queryable)", { recordType: "OrgContentLink" });
await q("Conversation.participantUserIDs queryable", { recordType: "Conversation", filterBy: lc("participantUserIDs") });
await q("Message.recipientUserIDs queryable", { recordType: "Message", filterBy: lc("recipientUserIDs") });
