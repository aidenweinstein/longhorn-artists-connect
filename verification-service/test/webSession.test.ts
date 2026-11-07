/// End-to-end tests for website sign-in, run against a real SQLite database
/// (node:sqlite) behind a minimal D1 shim, with Resend stubbed out.

import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";

import { hmacHex } from "../src/util.ts";
import { handleWebSessionRequest, handleWebSessionConfirm, type DomainMatch } from "../src/webSession.ts";

// MARK: - D1 shim

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

// MARK: - Fixtures

const TOKEN = "test-web-client-token";
let db: DatabaseSync;
let env: any;
let sent: { to: string; text: string }[];
const realFetch = globalThis.fetch;

const lookup = async (_env: unknown, domain: string): Promise<DomainMatch | null> => {
    if (domain === "utexas.edu") return { schoolID: "ut-austin", schoolName: "The University of Texas at Austin", kind: "student" };
    if (domain === "alumni.utexas.edu") return { schoolID: "ut-austin", schoolName: "The University of Texas at Austin", kind: "alumni" };
    return null;
};

beforeEach(() => {
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
    };
    sent = [];
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

function post(path: string, body: unknown, { token = TOKEN, ip = "203.0.113.7" } = {}) {
    return new Request(`https://worker.test${path}`, {
        method: "POST",
        headers: {
            "content-type": "application/json",
            ...(token ? { authorization: `Bearer ${token}` } : {}),
            "x-nexus-client-ip": ip,
        },
        body: JSON.stringify(body),
    });
}

async function requestCode(email: string) {
    const res = await handleWebSessionRequest(post("/v1/web/session/request", { email }), env, lookup);
    return { res, body: (await res.json()) as any };
}

function lastCode(): string {
    return sent.at(-1)!.text.match(/\b(\d{6})\b/)![1];
}

// MARK: - Tests

test("a school email receives a code that signs in once", async () => {
    const { res, body } = await requestCode("Jane.Doe+web@UTexas.edu");
    assert.equal(res.status, 200);
    assert.equal(body.school.id, "ut-austin");
    assert.equal(sent[0].to, "jane.doe@utexas.edu");
    assert.match(sent[0].text, /Nexus website/);

    const confirm = () => handleWebSessionConfirm(post("/v1/web/session/confirm", { pendingID: body.pendingID, code: lastCode() }), env);
    const ok = await confirm();
    assert.equal(ok.status, 200);
    assert.deepEqual(await ok.json(), {
        email: "jane.doe@utexas.edu",
        schoolID: "ut-austin",
        schoolName: "The University of Texas at Austin",
        domainKind: "student",
    });

    const again = await confirm();
    assert.equal(again.status, 400, "a code can't be reused");

    const row = db.prepare(`SELECT email_normalized FROM pending_web_sessions`).get() as any;
    assert.equal(row.email_normalized, "", "raw address is dropped after confirming");
});

async function signIn(email: string) {
    const { body } = await requestCode(email);
    const ok = await handleWebSessionConfirm(post("/v1/web/session/confirm", { pendingID: body.pendingID, code: lastCode() }), env);
    return (await ok.json()) as Record<string, unknown>;
}

async function verifyInApp(email: string, userRecordName: string, revokedAt: number | null = null) {
    const hash = await hmacHex("pepper", `email:${email}`);
    db.prepare(
        `INSERT INTO verified_emails (email_hash, user_record_name, school_id, verified_at, revoked_at) VALUES (?, ?, 'ut-austin', 1, ?)`,
    ).run(hash, userRecordName, revokedAt);
}

test("an email never verified in the app returns no app account", async () => {
    assert.ok(!("userRecordName" in (await signIn("jane@utexas.edu"))));
});

test("an email verified in the app returns that app account", async () => {
    await verifyInApp("jane@utexas.edu", "_app_user_123");
    assert.equal((await signIn("Jane@UTexas.edu")).userRecordName, "_app_user_123");
});

test("a revoked app verification returns no app account", async () => {
    await verifyInApp("jane@utexas.edu", "_app_user_123", 5);
    assert.ok(!("userRecordName" in (await signIn("jane@utexas.edu"))));
});

test("wrong codes are capped at five attempts", async () => {
    const { body } = await requestCode("jane@utexas.edu");
    const right = lastCode();
    const wrong = right === "000000" ? "111111" : "000000";
    for (let i = 0; i < 5; i++) {
        const r = await handleWebSessionConfirm(post("/v1/web/session/confirm", { pendingID: body.pendingID, code: wrong }), env);
        assert.equal(r.status, 400);
    }
    const r = await handleWebSessionConfirm(post("/v1/web/session/confirm", { pendingID: body.pendingID, code: right }), env);
    assert.equal(r.status, 429, "even the right code fails once attempts are exhausted");
});

test("expired codes are refused", async () => {
    const { body } = await requestCode("jane@utexas.edu");
    db.prepare(`UPDATE pending_web_sessions SET expires_at = 0`).run();
    const r = await handleWebSessionConfirm(post("/v1/web/session/confirm", { pendingID: body.pendingID, code: lastCode() }), env);
    assert.equal(r.status, 400);
    assert.equal(((await r.json()) as any).error, "expired_code");
});

test("unknown and alumni domains are refused without sending mail", async () => {
    assert.equal((await requestCode("someone@gmail.com")).res.status, 422);
    assert.equal((await requestCode("old@alumni.utexas.edu")).res.status, 422);
    assert.equal(sent.length, 0);
});

test("a code from the app's flow can't confirm a web sign-in", async () => {
    const { body } = await requestCode("jane@utexas.edu");
    // Same pendingID and code, but hashed the way /v1/verify/* hashes it.
    const code = lastCode();
    db.prepare(`UPDATE pending_web_sessions SET code_hash = ?`).run(
        await (await import("../src/util.ts")).hmacHex("pepper", `code:${body.pendingID}:${code}`),
    );
    const r = await handleWebSessionConfirm(post("/v1/web/session/confirm", { pendingID: body.pendingID, code }), env);
    assert.equal(r.status, 400);
});

test("requests without the website's token are rejected", async () => {
    const bad = await handleWebSessionRequest(post("/v1/web/session/request", { email: "jane@utexas.edu" }, { token: "nope" }), env, lookup);
    assert.equal(bad.status, 403);
    const none = await handleWebSessionRequest(post("/v1/web/session/request", { email: "jane@utexas.edu" }, { token: "" }), env, lookup);
    assert.equal(none.status, 403);

    env.WEB_CLIENT_TOKEN = "";
    const disabled = await handleWebSessionRequest(post("/v1/web/session/request", { email: "jane@utexas.edu" }), env, lookup);
    assert.equal(disabled.status, 404, "routes are off until a token is configured");
    assert.equal(sent.length, 0);
});

test("rate limits are per end user, not per website server", async () => {
    for (let i = 0; i < 10; i++) {
        const r = await handleWebSessionRequest(post("/v1/web/session/request", { email: `s${i}@utexas.edu` }, { ip: "198.51.100.1" }), env, lookup);
        assert.equal(r.status, 200);
    }
    const limited = await handleWebSessionRequest(post("/v1/web/session/request", { email: "s99@utexas.edu" }, { ip: "198.51.100.1" }), env, lookup);
    assert.equal(limited.status, 429);
    const otherUser = await handleWebSessionRequest(post("/v1/web/session/request", { email: "s100@utexas.edu" }, { ip: "198.51.100.2" }), env, lookup);
    assert.equal(otherUser.status, 200);
});
