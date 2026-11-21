/// End-to-end tests for Apple TV sign-in and watch time, run against a real
/// SQLite database (node:sqlite) behind a minimal D1 shim, with Resend and
/// CloudKit stubbed out.

import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";

import { hmacHex } from "../src/util.ts";
import { handleTV, normalizePairingCode, type TVDeps } from "../src/tv.ts";

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

const WEB_TOKEN = "test-web-client-token";
let db: DatabaseSync;
let env: any;
let sent: { to: string; text: string }[];
let profiles: Map<string, any>;
let views: Map<string, Record<string, { value: string | number }>>;
const realFetch = globalThis.fetch;

const deps: TVDeps = {
    async fetchProfile(_env, user) {
        return profiles.get(user) ?? null;
    },
    async createView(_env, record) {
        if (views.has(record.recordName)) return false;
        views.set(record.recordName, record.fields);
        return true;
    },
};

beforeEach(() => {
    db = new DatabaseSync(":memory:");
    db.exec(readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));
    env = {
        DB: d1(db),
        CODE_PEPPER: "pepper",
        WEB_CLIENT_TOKEN: WEB_TOKEN,
        RESEND_API_KEY: "re_test",
        MAIL_FROM: "no-reply@example.org",
        MAIL_FROM_NAME: "Test",
    };
    sent = [];
    profiles = new Map([
        ["_alice", { fields: { firstName: { value: "Alice" }, lastName: { value: "Ng" } } }],
        ["web_bob", { fields: { firstName: { value: "Bob" }, lastName: { value: "Ray" } } }],
    ]);
    views = new Map();
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

async function call(path: string, body: unknown = {}, { webToken }: { webToken?: string } = {}) {
    const request = new Request(`https://worker.test${path}`, {
        method: "POST",
        headers: {
            "content-type": "application/json",
            "cf-connecting-ip": "203.0.113.9",
            ...(webToken ? { authorization: `Bearer ${webToken}` } : {}),
        },
        body: JSON.stringify(body),
    });
    const res = await handleTV(request, env, path, deps);
    return { status: res.status, body: (await res.json()) as any };
}

async function linkEmail(email: string, user: string) {
    db.prepare(
        `INSERT INTO verified_emails (email_hash, user_record_name, school_id, verified_at) VALUES (?, ?, 'ut-austin', 0)`,
    ).run(await hmacHex("pepper", `email:${email}`), user);
}

/// The iPhone app's two steps, writing the nonce onto the profile in between.
async function approveFromApp(code: string, user: string) {
    const claim = await call("/v1/tv/pair/claim", { code, userRecordName: user });
    assert.equal(claim.status, 200);
    profiles.get(user).fields.verificationNonce = { value: claim.body.nonce };
    return call("/v1/tv/pair/approve", { code, userRecordName: user });
}

// MARK: - Pairing

test("a TV signs in once the iPhone app approves its code", async () => {
    const start = await call("/v1/tv/pair/start");
    assert.equal(start.status, 200);
    assert.match(start.body.code, /^[A-HJKMNP-Z2-9]{8}$/);
    assert.equal(start.body.approveURL, `https://nexusbylac.com/tv?code=${start.body.code}`);

    const pending = await call("/v1/tv/pair/poll", { pairingID: start.body.pairingID });
    assert.deepEqual(pending.body, { status: "pending" });

    const approved = await approveFromApp(start.body.code.toLowerCase().replace(/^(....)/, "$1-"), "_alice");
    assert.equal(approved.status, 200);

    const poll = await call("/v1/tv/pair/poll", { pairingID: start.body.pairingID });
    assert.equal(poll.body.status, "approved");
    assert.deepEqual(poll.body.viewer, { userRecordName: "_alice", name: "Alice Ng" });

    const me = await call("/v1/tv/me", { token: poll.body.token });
    assert.equal(me.body.viewer.userRecordName, "_alice");

    const again = await call("/v1/tv/pair/poll", { pairingID: start.body.pairingID });
    assert.equal(again.status, 410, "a pairing hands out one token");
});

test("the app can't approve without writing the nonce to its own profile", async () => {
    const start = await call("/v1/tv/pair/start");
    await call("/v1/tv/pair/claim", { code: start.body.code, userRecordName: "_alice" });
    profiles.get("_alice").fields.verificationNonce = { value: "someone-elses-nonce" };

    const approve = await call("/v1/tv/pair/approve", { code: start.body.code, userRecordName: "_alice" });
    assert.equal(approve.status, 403);
    const poll = await call("/v1/tv/pair/poll", { pairingID: start.body.pairingID });
    assert.deepEqual(poll.body, { status: "pending" });
});

test("approving needs the claim made by the same account", async () => {
    const start = await call("/v1/tv/pair/start");
    await call("/v1/tv/pair/claim", { code: start.body.code, userRecordName: "_alice" });
    const approve = await call("/v1/tv/pair/approve", { code: start.body.code, userRecordName: "web_bob" });
    assert.equal(approve.status, 404);
});

test("the website approves for its signed-in account, and only with its token", async () => {
    const start = await call("/v1/tv/pair/start");

    const noToken = await call("/v1/web/tv/approve", { code: start.body.code, userRecordName: "web_bob" });
    assert.equal(noToken.status, 403);

    const ok = await call("/v1/web/tv/approve", { code: start.body.code, userRecordName: "web_bob" }, { webToken: WEB_TOKEN });
    assert.equal(ok.status, 200);

    const twice = await call("/v1/web/tv/approve", { code: start.body.code, userRecordName: "_alice" }, { webToken: WEB_TOKEN });
    assert.equal(twice.status, 404, "an approved code can't be taken over");

    const poll = await call("/v1/tv/pair/poll", { pairingID: start.body.pairingID });
    assert.equal(poll.body.viewer.name, "Bob Ray");
});

test("an expired pairing can't be approved or polled", async () => {
    const start = await call("/v1/tv/pair/start");
    db.prepare(`UPDATE tv_pairings SET expires_at = 0`).run();

    const approve = await call("/v1/web/tv/approve", { code: start.body.code, userRecordName: "web_bob" }, { webToken: WEB_TOKEN });
    assert.equal(approve.status, 404);
    const poll = await call("/v1/tv/pair/poll", { pairingID: start.body.pairingID });
    assert.equal(poll.status, 410);
});

test("pairing codes are normalized and validated", () => {
    assert.equal(normalizePairingCode("abcd-efgh"), "ABCDEFGH");
    assert.equal(normalizePairingCode(" ABCD EFGH "), "ABCDEFGH");
    assert.equal(normalizePairingCode("ABCD-EFG0"), null, "0 isn't in the alphabet");
    assert.equal(normalizePairingCode("ABC"), null);
});

// MARK: - Email

test("the email on an account signs a TV in as that account", async () => {
    await linkEmail("alice@utexas.edu", "_alice");

    const request = await call("/v1/tv/email/request", { email: "Alice+tv@UTexas.edu" });
    assert.equal(request.status, 200);
    assert.equal(sent[0].to, "alice@utexas.edu");
    assert.match(sent[0].text, /Apple TV/);
    const code = sent[0].text.match(/\b(\d{6})\b/)![1];

    const wrong = await call("/v1/tv/email/confirm", { pendingID: request.body.pendingID, code: code === "000000" ? "111111" : "000000" });
    assert.equal(wrong.status, 400);

    const ok = await call("/v1/tv/email/confirm", { pendingID: request.body.pendingID, code });
    assert.equal(ok.status, 200);
    assert.deepEqual(ok.body.viewer, { userRecordName: "_alice", name: "Alice Ng" });

    const reuse = await call("/v1/tv/email/confirm", { pendingID: request.body.pendingID, code });
    assert.equal(reuse.status, 400, "a code works once");
});

test("an email with no account gets no code", async () => {
    const request = await call("/v1/tv/email/request", { email: "nobody@utexas.edu" });
    assert.equal(request.status, 404);
    assert.equal(request.body.error, "no_account");
    assert.equal(sent.length, 0);
});

test("five wrong codes lock the attempt", async () => {
    await linkEmail("alice@utexas.edu", "_alice");
    const request = await call("/v1/tv/email/request", { email: "alice@utexas.edu" });
    const code = sent[0].text.match(/\b(\d{6})\b/)![1];
    const wrong = code === "000000" ? "111111" : "000000";
    for (let i = 0; i < 5; i++) {
        await call("/v1/tv/email/confirm", { pendingID: request.body.pendingID, code: wrong });
    }
    const locked = await call("/v1/tv/email/confirm", { pendingID: request.body.pendingID, code });
    assert.equal(locked.status, 429);
});

// MARK: - Watch time

async function signedInToken(): Promise<string> {
    const start = await call("/v1/tv/pair/start");
    await approveFromApp(start.body.code, "_alice");
    return (await call("/v1/tv/pair/poll", { pairingID: start.body.pairingID })).body.token;
}

test("a view is recorded once per kind, post and day, under the iPhone's record name", async () => {
    const token = await signedInToken();
    const postID = "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0";

    const first = await call("/v1/tv/view", { token, postID: postID.toLowerCase(), kind: "play" });
    assert.deepEqual(first.body, { recorded: true });
    const second = await call("/v1/tv/view", { token, postID, kind: "play" });
    assert.deepEqual(second.body, { recorded: false });

    const day = new Date().toISOString().slice(0, 10).replace(/-/g, "");
    const fields = views.get(`view_play_${postID}_alice_${day}`.replace("_alice", "__alice"));
    assert.ok(fields, "record name matches CloudKitManager.recordPostView");
    assert.equal(fields!.userID.value, "_alice");
    assert.equal(fields!.eventKind.value, "play");
});

test("views need a live session and a TV-possible kind", async () => {
    const postID = "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0";
    const anonymous = await call("/v1/tv/view", { token: "made-up", postID, kind: "play" });
    assert.equal(anonymous.status, 401);

    const token = await signedInToken();
    const message = await call("/v1/tv/view", { token, postID, kind: "message" });
    assert.equal(message.status, 400);

    await call("/v1/tv/signout", { token });
    const afterSignOut = await call("/v1/tv/view", { token, postID, kind: "open" });
    assert.equal(afterSignOut.status, 401);
    assert.equal(views.size, 0);
});
