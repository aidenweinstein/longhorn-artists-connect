// Prints the CloudKit user this website's server-to-server key writes as: the
// `created` user on every post the website makes. verification-service needs it
// in SERVER_CREATORS so its nightly sweep judges website posts by their userID.
//
// Run from web/:  node scripts/cloudkit-caller.mjs
import { createHash, createSign } from "node:crypto";
import { readFileSync } from "node:fs";

const keyID = readFileSync(".secrets/cloudkit.env", "utf8").match(/CLOUDKIT_KEY_ID\s*=\s*(\S+)/)[1];
const privateKey = readFileSync(".secrets/cloudkit-s2s-key.pem", "utf8");
const subpath = "/database/1/iCloud.LAA.Longhorn-Artists-Connect/production/public/users/caller";
const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
const bodyHash = createHash("sha256").update("").digest("base64");
const signature = createSign("SHA256").update(`${date}:${bodyHash}:${subpath}`).sign(privateKey, "base64");

const res = await fetch(`https://api.apple-cloudkit.com${subpath}`, {
  headers: {
    "X-Apple-CloudKit-Request-KeyID": keyID,
    "X-Apple-CloudKit-Request-ISO8601Date": date,
    "X-Apple-CloudKit-Request-SignatureV1": signature,
  },
});
const json = await res.json().catch(() => ({}));
if (!res.ok || !json.userRecordName) {
  console.error(`CloudKit ${res.status}:`, JSON.stringify(json));
  process.exit(1);
}
console.log(json.userRecordName);
