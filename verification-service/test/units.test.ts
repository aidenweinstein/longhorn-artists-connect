/// Tests for the pure logic that would otherwise only fail in production as an
/// opaque 401 or a silently-rejected email.
///
/// Run: npm test
///
/// Node's WebCrypto is the same API the Worker runtime exposes, so the DER
/// conversion is exercised against a real ECDSA P-256 signature here.

import { test } from "node:test";
import assert from "node:assert/strict";
import { createVerify, createPublicKey } from "node:crypto";

import { p1363ToDer } from "../src/cloudkit.ts";
import { domainCandidates, normalizeEmail, randomCode, constantTimeEqual } from "../src/util.ts";
import { classifyRecord, type CreatorVerification } from "../src/sweep.ts";

// MARK: - The signature conversion

test("p1363ToDer produces a DER signature Node can verify", async () => {
    const keyPair = await crypto.subtle.generateKey(
        { name: "ECDSA", namedCurve: "P-256" },
        true,
        ["sign", "verify"],
    );

    const message = new TextEncoder().encode("2026-09-22T00:00:00Z:hash:/database/1/x");

    // Run it 50 times: r or s having a leading zero byte, or a high bit set, are
    // the cases a naive implementation gets wrong, and they only show up in
    // maybe 1 signature in 128.
    for (let i = 0; i < 50; i++) {
        const raw = await crypto.subtle.sign(
            { name: "ECDSA", hash: "SHA-256" },
            keyPair.privateKey,
            message,
        );
        const der = p1363ToDer(new Uint8Array(raw));

        const spki = await crypto.subtle.exportKey("spki", keyPair.publicKey);
        const publicKey = createPublicKey({
            key: Buffer.from(spki),
            format: "der",
            type: "spki",
        });

        const verifier = createVerify("SHA256");
        verifier.update(message);
        assert.ok(
            verifier.verify(
                { key: publicKey, dsaEncoding: "der" },
                Buffer.from(der),
            ),
            `DER signature failed verification on iteration ${i}`,
        );
    }
});

test("p1363ToDer pads values whose high bit is set", () => {
    // r and s both 0xFF... — must each gain a 0x00 prefix or they decode negative.
    const raw = new Uint8Array(64).fill(0xff);
    const der = p1363ToDer(raw);

    assert.equal(der[0], 0x30, "must be a DER SEQUENCE");
    assert.equal(der[2], 0x02, "first element must be an INTEGER");
    assert.equal(der[3], 33, "33-byte INTEGER (32 + zero pad)");
    assert.equal(der[4], 0x00, "zero pad present");
});

test("p1363ToDer strips redundant leading zeros", () => {
    const raw = new Uint8Array(64);
    raw[31] = 0x01; // r = 1
    raw[63] = 0x01; // s = 1
    const der = p1363ToDer(raw);

    // SEQUENCE(len) INTEGER(1)[01] INTEGER(1)[01] = 8 bytes
    assert.equal(der.length, 8);
    assert.deepEqual([...der], [0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01]);
});

// MARK: - Domain matching

test("domainCandidates orders most-specific first and excludes the bare TLD", () => {
    assert.deepEqual(domainCandidates("mail.grad.utexas.edu"), [
        "mail.grad.utexas.edu",
        "grad.utexas.edu",
        "utexas.edu",
    ]);
    assert.deepEqual(domainCandidates("utexas.edu"), ["utexas.edu"]);
    // Critically: never yields "edu" on its own, which would match every school.
    assert.ok(!domainCandidates("a.b.utexas.edu").includes("edu"));
});

// MARK: - Email normalisation

test("normalizeEmail lowercases, strips plus tags, keeps dots", () => {
    assert.equal(normalizeEmail("  Aiden.Weinstein+test@UTexas.edu "), "aiden.weinstein@utexas.edu");
    // Dots are significant at many universities, unlike Gmail.
    assert.equal(normalizeEmail("a.b@utexas.edu"), "a.b@utexas.edu");
});

test("normalizeEmail rejects malformed input", () => {
    for (const bad of ["", "nope", "no@domain", "@utexas.edu", "+tag@utexas.edu", "a b@utexas.edu"]) {
        assert.equal(normalizeEmail(bad), null, `should reject ${JSON.stringify(bad)}`);
    }
});

// MARK: - Codes

test("randomCode is always six digits and reasonably distributed", () => {
    const seen = new Set<string>();
    for (let i = 0; i < 5000; i++) {
        const code = randomCode();
        assert.match(code, /^\d{6}$/);
        seen.add(code);
    }
    // 5000 draws from 1e6 should almost never collide much.
    assert.ok(seen.size > 4900, `too many collisions: ${seen.size} unique of 5000`);
});

test("constantTimeEqual matches only identical strings", () => {
    assert.ok(constantTimeEqual("abc123", "abc123"));
    assert.ok(!constantTimeEqual("abc123", "abc124"));
    assert.ok(!constantTimeEqual("abc", "abc123"));
    assert.ok(!constantTimeEqual("", "a"));
});

// MARK: - Sweep classification
//
// The sweep can delete real student work, so its rules are tested here rather
// than discovered on a live container.

/// A CloudKit query result, shaped the way `records/query` returns one.
function ckRecord(options: {
    creator?: string;
    createdAtMillis?: number;
    schoolID?: string;
} = {}): any {
    const { creator = "user-1", createdAtMillis = 2_000_000_000_000, schoolID } = options;
    return {
        recordName: "post-1",
        created: { userRecordName: creator, timestamp: createdAtMillis },
        fields: schoolID === undefined ? {} : { schoolID: { value: schoolID } },
    };
}

const verified = (schoolID: string): CreatorVerification => ({ verified: true, schoolID });
const unverified: CreatorVerification = { verified: false, schoolID: null };

test("classifyRecord flags a post whose creator has no verification", () => {
    assert.equal(classifyRecord(ckRecord(), unverified, 0), "creator-unverified");
});

test("classifyRecord passes a verified creator's correctly stamped post", () => {
    const record = ckRecord({ schoolID: "ut-austin" });
    assert.equal(classifyRecord(record, verified("ut-austin"), 0), null);
});

test("classifyRecord flags a post stamped with someone else's school", () => {
    const record = ckRecord({ schoolID: "berkeley" });
    assert.equal(classifyRecord(record, verified("ut-austin"), 0), "school-mismatch");
});

test("classifyRecord does NOT treat an unstamped post as a mismatch", () => {
    // Every record is unstamped until the backfill runs. Flagging these would
    // flag the entire container on the first night.
    assert.equal(classifyRecord(ckRecord(), verified("ut-austin"), 0), null);
    const empty = ckRecord({ schoolID: "" });
    assert.equal(classifyRecord(empty, verified("ut-austin"), 0), null);
});

test("classifyRecord grandfathers posts created before the cutoff", () => {
    const cutoff = 1_700_000_000;
    const old = ckRecord({ createdAtMillis: (cutoff - 60) * 1000 });
    assert.equal(classifyRecord(old, unverified, cutoff), null);

    const fresh = ckRecord({ createdAtMillis: (cutoff + 60) * 1000 });
    assert.equal(classifyRecord(fresh, unverified, cutoff), "creator-unverified");
});

test("classifyRecord ignores the cutoff when grandfathering is off", () => {
    // SWEEP_GRANDFATHER_BEFORE defaults to "0", which must mean "no exemption"
    // and not "exempt everything created after the epoch".
    assert.equal(classifyRecord(ckRecord(), unverified, 0), "creator-unverified");
});

test("classifyRecord skips records with no creator", () => {
    // System-created or malformed records: there's nobody to hold responsible,
    // and deleting them on a hunch is worse than leaving them.
    const orphan = { recordName: "post-1", created: { timestamp: 1 }, fields: {} };
    assert.equal(classifyRecord(orphan, unverified, 0), null);
});

test("classifyRecord tolerates a record with no fields or no created block", () => {
    assert.equal(classifyRecord({ recordName: "x" }, unverified, 0), null);
    assert.equal(
        classifyRecord({ recordName: "x", created: { userRecordName: "u" } }, verified("ut-austin"), 0),
        null,
    );
});
