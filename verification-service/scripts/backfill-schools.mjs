#!/usr/bin/env node
//
// Drives the schoolID backfill to completion.
//
// The Worker does the actual work (it holds the CloudKit server-to-server key);
// this just calls it in a loop, following the cursor it returns, and prints a
// running tally. Nothing here touches CloudKit or D1 directly, so the only
// credential it needs is the admin token.
//
// Usage:
//   BASE_URL=https://lac-verification.<sub>.workers.dev \
//   ADMIN_TOKEN=<token> \
//   node scripts/backfill-schools.mjs            # dry run (default)
//
//   ... node scripts/backfill-schools.mjs --write # actually stamp records
//
// Run the dry run first and check the per-school tally. Then run with --write,
// and finally run the dry run once more: it should report 0 left to stamp and
// an empty skippedTypes. Only then is it safe to ship a build that filters
// feeds by school.

const baseURL = process.env.BASE_URL;
const adminToken = process.env.ADMIN_TOKEN;
const write = process.argv.includes("--write");

if (!baseURL || !adminToken) {
    console.error("Set BASE_URL and ADMIN_TOKEN.");
    process.exit(1);
}

const endpoint = new URL("/v1/admin/backfill-schools", baseURL);

const total = { scanned: 0, stamped: 0, alreadyStamped: 0, failed: 0 };
const bySchool = {};
const skippedTypes = [];

let cursor = null;
let pass = 0;

while (true) {
    pass++;

    const response = await fetch(endpoint, {
        method: "POST",
        headers: {
            authorization: `Bearer ${adminToken}`,
            "content-type": "application/json",
        },
        body: JSON.stringify({ dryRun: !write, ...(cursor ? { cursor } : {}) }),
    });

    const text = await response.text();
    if (!response.ok) {
        console.error(`pass ${pass} failed: ${response.status} ${text}`);
        process.exit(1);
    }

    const result = JSON.parse(text);

    total.scanned += result.scanned;
    total.stamped += result.stamped;
    total.alreadyStamped += result.alreadyStamped;
    total.failed += result.failed;
    for (const [school, count] of Object.entries(result.bySchool ?? {})) {
        bySchool[school] = (bySchool[school] ?? 0) + count;
    }
    skippedTypes.push(...(result.skippedTypes ?? []));

    console.log(
        `pass ${pass}: scanned=${result.scanned} stamped=${result.stamped} ` +
            `already=${result.alreadyStamped} failed=${result.failed}` +
            (result.cursor ? ` → resuming at ${result.cursor.recordType}` : " → done"),
    );

    cursor = result.cursor;
    if (!cursor) break;
}

console.log(`\n${write ? "WROTE" : "DRY RUN — nothing written"}`);
console.log(`scanned          ${total.scanned}`);
console.log(`stamped          ${total.stamped}`);
console.log(`already stamped  ${total.alreadyStamped}`);
console.log(`failed           ${total.failed}`);
console.log("by school       ", bySchool);

if (skippedTypes.length > 0) {
    console.error("\n⚠️  These record types were SKIPPED — their records are still unstamped:");
    for (const skipped of skippedTypes) {
        console.error(`   ${skipped.recordType}: ${skipped.reason}`);
    }
    console.error("Do not ship school filtering until this list is empty.");
    process.exit(1);
}

if (total.failed > 0) process.exit(1);
