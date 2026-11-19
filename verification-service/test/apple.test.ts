/// Sign in with Apple: token checks, the app's link, and the website flow,
/// run against a real SQLite database (node:sqlite) behind a minimal D1 shim.

import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";

import { hmacHex } from "../src/util.ts";
import { verifyAppleToken, handleWebAppleSession, moveAppleLink, sealEmail, openEmail, type AppleDeps } from "../src/apple.ts";
import { handleWebSessionRequest, handleWebSessionConfirm, handleWebAccountCreate, type AccountWriter, type DomainMatch } from "../src/webSession.ts";

// MARK: - D1 shim (as in webSession.test.ts)

function d1(db: DatabaseSync) {
    const prepare = (sql: string) => {
        let args: unknown[] = [];
        const stmt = {
            bind(...values: unknown[]) {
                args = values;
                return stmt;
            },
            async first<T>() {
                return (db.prepare(sql).get(...(args as any[])) ?? null) as T | null;
            },
            async all<T>() {
                return { results: db.prepare(sql).all(...(args as any[])) as T[] };
            },
            async run() {
                const r = db.prepare(sql).run(...(args as any[]));
                return { meta: { changes: Number(r.changes) } };
            },
        };
        return stmt;
    };
    return {
        prepare,
        async batch(stmts: { run(): Promise<unknown> }[]) {
            for (const s of stmts) await s.run();
        },
    };
}

// MARK: - A fake Apple

const WEB = "LAA.Longhorn-Artists-Connect.web";
let signer: CryptoKey;
let publicJWK: JsonWebKey;

async function makeKeys() {
    const pair = (await crypto.subtle.generateKey(
        { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
        true,
        ["sign", "verify"],
    )) as CryptoKeyPair;
    signer = pair.privateKey;
    publicJWK = { ...(await crypto.subtle.exportKey("jwk", pair.publicKey)), kid: "kid-1" } as JsonWebKey;
}

const b64u = (bytes: Uint8Array) => Buffer.from(bytes).toString("base64url");
const part = (value: unknown) => b64u(new TextEncoder().encode(JSON.stringify(value)));

async function appleToken(claims: Record<string, unknown>, { kid = "kid-1", key }: { kid?: string; key?: CryptoKey } = {}) {
    const now = Math.floor(Date.now() / 1000);
    const head = part({ alg: "RS256", kid });
    const body = part({ iss: "https://appleid.apple.com", iat: now, exp: now + 600, ...claims });
    const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key ?? signer, new TextEncoder().encode(`${head}.${body}`));
    return `${head}.${body}.${b64u(new Uint8Array(sig))}`;
}

// MARK: - Fixtures

const TOKEN = "test-web-client-token";
let db: DatabaseSync;
let env: any;
let sent: { to: string; text: string }[];
let verifications: any[];
let merges: [string, string][];
const realFetch = globalThis.fetch;

const deps: AppleDeps = {
    keys: async () => [publicJWK],
    async writeVerification(_env, params) {
        verifications.push(params);
    },
    async merge(_env, from, to) {
        merges.push([from, to]);
        return { rewritten: 3, errors: [], profileDeleted: true };
    },
};

const lookup = async (_env: unknown, domain: string): Promise<DomainMatch | null> =>
    domain === "utexas.edu" ? { schoolID: "ut-austin", schoolName: "The University of Texas at Austin", kind: "student" } : null;

beforeEach(async () => {
    if (!signer) await makeKeys();
    db = new DatabaseSync(":memory:");
    db.exec(readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));
    db.exec(`INSERT INTO schools (id, name) VALUES ('ut-austin', 'The University of Texas at Austin')`);
    env = {
        DB: d1(db),
        CODE_PEPPER: "pepper",
        WEB_CLIENT_TOKEN: TOKEN,
        RESEND_API_KEY: "re_test",
        MAIL_FROM: "no-reply@example.org",
        MAIL_FROM_NAME: "Test",
        APPLE_WEB_CLIENT_ID: WEB,
    };
    sent = [];
    verifications = [];
    merges = [];
    globalThis.fetch = (async (_url: string, init: RequestInit) => {
        const body = JSON.parse(String(init.body));
        sent.push({ to: body.to[0], text: body.text });
        return new Response("{}", { status: 200 });
    }) as typeof fetch;
});

afterEach(() => {
    globalThis.fetch = realFetch;
    db.close();
});

function post(path: string, body: unknown) {
    return new Request(`https://worker.test${path}`, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${TOKEN}`, "x-nexus-client-ip": "203.0.113.7" },
        body: JSON.stringify(body),
    });
}

const lastCode = () => sent.at(-1)!.text.match(/\b(\d{6})\b/)![1];

/// The website: Apple's callback hands the id_token to the service.
async function webApple(sub: string) {
    const nonce = "web-nonce-123";
    const idToken = await appleToken({ aud: WEB, sub, nonce });
    const res = await handleWebAppleSession(post("/v1/web/apple/session", { idToken, nonce }), env, deps);
    return { status: res.status, body: (await res.json()) as any };
}

/// The website's email step, carrying the Apple ticket.
async function webEmail(email: string, appleTicket?: string) {
    const req = (await (await handleWebSessionRequest(post("/v1/web/session/request", { email }), env, lookup)).json()) as any;
    const res = await handleWebSessionConfirm(post("/v1/web/session/confirm", { pendingID: req.pendingID, code: lastCode(), appleTicket }), env, deps);
    return { status: res.status, body: (await res.json()) as any };
}

async function verifiedInApp(email: string, user: string) {
    db.prepare(`INSERT INTO verified_emails (email_hash, user_record_name, school_id, verified_at) VALUES (?, ?, 'ut-austin', 1)`).run(
        await hmacHex("pepper", `email:${email}`),
        user,
    );
}

// MARK: - Token checks

test("a genuine Apple token passes; wrong audience, nonce, key, issuer or age don't", async () => {
    const keys = deps.keys;
    const good = await appleToken({ aud: WEB, sub: "001.abc", nonce: "n1" });
    assert.equal((await verifyAppleToken(good, { audience: WEB, nonce: "n1", keys })).sub, "001.abc");

    await assert.rejects(verifyAppleToken(good, { audience: "LAA.Longhorn-Artists-Connect", nonce: "n1", keys }), /audience/);
    await assert.rejects(verifyAppleToken(good, { audience: WEB, nonce: "n2", keys }), /nonce/);
    await assert.rejects(verifyAppleToken(await appleToken({ aud: WEB, sub: "x", iss: "https://evil.example" }), { audience: WEB, keys }), /issuer/);
    await assert.rejects(verifyAppleToken(await appleToken({ aud: WEB, sub: "x", exp: 1000 }), { audience: WEB, keys }), /expired/);
    await assert.rejects(verifyAppleToken(await appleToken({ aud: WEB, sub: "x" }, { kid: "other" }), { audience: WEB, keys }), /unknown signing key/);

    const forged = (await crypto.subtle.generateKey(
        { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
        true,
        ["sign", "verify"],
    )) as CryptoKeyPair;
    await assert.rejects(verifyAppleToken(await appleToken({ aud: WEB, sub: "x" }, { key: forged.privateKey }), { audience: WEB, keys }), /signature/);
    await assert.rejects(verifyAppleToken("not.a.token", { audience: WEB, keys }), /malformed/);
});

test("stored emails are encrypted and read back", async () => {
    const sealed = await sealEmail(env, "jane@utexas.edu");
    assert.ok(!sealed.includes("jane"));
    assert.equal(await openEmail(env, sealed), "jane@utexas.edu");
    assert.equal(await openEmail({ ...env, CODE_PEPPER: "other" }, sealed), null);
});

// MARK: - Website flow

test("an app account's verified email links the Apple ID, then Apple alone signs in", async () => {
    await verifiedInApp("jane@utexas.edu", "_app_user");

    const apple = await webApple("001.jane");
    assert.equal(apple.body.needsEmail, true);
    assert.equal(apple.body.reason, "new", "iCloud and Apple IDs can't be matched: the email finds the account");

    const confirmed = await webEmail("jane@utexas.edu", apple.body.appleTicket);
    assert.equal(confirmed.status, 200);
    assert.equal(confirmed.body.userRecordName, "_app_user", "the website opens the app account");
    assert.ok(!("accountToken" in confirmed.body));
    assert.deepEqual(confirmed.body.apple, { linked: true, verifiedApp: false });
    assert.equal(verifications.length, 0, "nothing about the app account changes");

    const again = await webApple("001.jane");
    assert.deepEqual(again.body.signedIn, {
        email: "jane@utexas.edu",
        schoolID: "ut-austin",
        schoolName: "The University of Texas at Austin",
        domainKind: "student",
        userRecordName: "_app_user",
    });
});

test("a new Apple ID creates a website account that Sign in with Apple then opens", async () => {
    const apple = await webApple("001.new");
    assert.equal(apple.body.reason, "new");

    const confirmed = await webEmail("new@utexas.edu", apple.body.appleTicket);
    assert.equal(typeof confirmed.body.accountToken, "string");
    assert.deepEqual(confirmed.body.apple, { linked: false, verifiedApp: false });

    const writer: AccountWriter = { async createProfile() { return []; }, async writeVerification() {} };
    const created = (await (await handleWebAccountCreate(
        post("/v1/web/account/create", { accountToken: confirmed.body.accountToken, appleTicket: apple.body.appleTicket, firstName: "New", lastName: "Person", major: "RTF", graduationYear: "2028" }),
        env,
        writer,
    )).json()) as any;
    assert.equal(created.appleLinked, true);

    const again = await webApple("001.new");
    assert.equal(again.body.signedIn?.userRecordName, created.userRecordName);
    assert.equal(again.body.signedIn?.email, "new@utexas.edu");
});

test("once the app merges a website account, its Apple ID opens the app account", async () => {
    await verifiedInApp("jane@utexas.edu", "web_abc");
    const apple = await webApple("001.jane");
    await webEmail("jane@utexas.edu", apple.body.appleTicket);

    // What /v1/verify/confirm does when the app verifies this email: the email and the Apple ID move.
    db.prepare(`UPDATE verified_emails SET user_record_name = '_app_user'`).run();
    await moveAppleLink(env, "web_abc", "_app_user");

    assert.equal((await webApple("001.jane")).body.signedIn?.userRecordName, "_app_user");
});

test("a different school email than the Apple ID's account is refused, and the code stays usable", async () => {
    await verifiedInApp("jane@utexas.edu", "_app_user");
    const apple = await webApple("001.jane");
    await webEmail("jane@utexas.edu", apple.body.appleTicket);

    // Signed out, the Apple ID's email isn't on file any more (e.g. a new pepper): asked once more.
    db.prepare(`UPDATE apple_accounts SET email_cipher = NULL`).run();
    const again = await webApple("001.jane");
    assert.equal(again.body.reason, "confirm");

    await verifiedInApp("bob@utexas.edu", "_app_bob");
    const req = (await (await handleWebSessionRequest(post("/v1/web/session/request", { email: "bob@utexas.edu" }), env, lookup)).json()) as any;
    const code = lastCode();
    const refused = await handleWebSessionConfirm(post("/v1/web/session/confirm", { pendingID: req.pendingID, code, appleTicket: again.body.appleTicket }), env, deps);
    assert.equal(refused.status, 409);
    assert.equal(((await refused.json()) as any).error, "apple_email_mismatch");

    const plain = await handleWebSessionConfirm(post("/v1/web/session/confirm", { pendingID: req.pendingID, code }), env, deps);
    assert.equal(plain.status, 200, "the code still works without the Apple ID");
});

test("an account already linked to another Apple ID isn't taken over", async () => {
    await verifiedInApp("jane@utexas.edu", "_app_user");
    const first = await webApple("001.jane");
    await webEmail("jane@utexas.edu", first.body.appleTicket);

    const other = await webApple("001.someone-else");
    const res = await webEmail("jane@utexas.edu", other.body.appleTicket);
    assert.equal(res.status, 409);
    assert.equal(res.body.error, "apple_taken");
});

test("website Apple routes need the website's token and the Services ID", async () => {
    const idToken = await appleToken({ aud: WEB, sub: "x", nonce: "n" });
    const bad = await handleWebAppleSession(
        new Request("https://worker.test/v1/web/apple/session", { method: "POST", headers: { authorization: "Bearer nope" }, body: JSON.stringify({ idToken, nonce: "n" }) }),
        env,
        deps,
    );
    assert.equal(bad.status, 403);
    env.APPLE_WEB_CLIENT_ID = "";
    assert.equal((await handleWebAppleSession(post("/v1/web/apple/session", { idToken, nonce: "n" }), env, deps)).status, 404);
});

test("an expired Apple ticket is refused rather than ignored", async () => {
    const apple = await webApple("001.jane");
    db.prepare(`UPDATE apple_tickets SET expires_at = 0`).run();
    const res = await webEmail("jane@utexas.edu", apple.body.appleTicket);
    assert.equal(res.status, 401);
    assert.equal(res.body.error, "apple_expired");
});
