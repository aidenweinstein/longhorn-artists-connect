/// People pages: picks and applications, against a real SQLite database behind a D1 shim.

import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";

import { handlePeople } from "../src/people.ts";

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

const TOKEN = "test-web-client-token";
let db: DatabaseSync;
let env: any;

beforeEach(() => {
    db = new DatabaseSync(":memory:");
    db.exec(readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));
    env = { DB: d1(db), WEB_CLIENT_TOKEN: TOKEN };
});

afterEach(() => db.close());

async function call(path: string, body: unknown, token: string | null = TOKEN) {
    const res = await handlePeople(
        new Request(`https://worker.test${path}`, {
            method: "POST",
            headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
            body: JSON.stringify(body),
        }),
        env,
        path,
    );
    return { status: res.status, body: (await res.json()) as any };
}

const save = (category: string, profileID: string, name: string, extra: object = {}) =>
    call("/v1/web/people/admin/save", { category, profileID, name, blurb: "", postIDs: [], ...extra });

test("only the website can read or change People pages", async () => {
    assert.equal((await call("/v1/web/people/list", { category: "actors" }, null)).status, 403);
    assert.equal((await call("/v1/web/people/admin/save", {}, "wrong")).status, 403);
});

test("an approved application puts the artist on the page and closes the application", async () => {
    const applied = await call("/v1/web/people/apply", {
        category: "filmmakers", email: "Ana@UTexas.edu", profileID: "UserProfile_ana", name: "Ana Ruiz", message: "My thesis film", links: "",
    });
    assert.equal(applied.status, 200);

    const pending = await call("/v1/web/people/admin/applications", {});
    assert.equal(pending.body.applications.length, 1);
    assert.equal(pending.body.applications[0].email, "ana@utexas.edu");

    await save("filmmakers", "UserProfile_ana", "Ana Ruiz", { blurb: "Watch her.", postIDs: ["p1", "p2"], applicationID: applied.body.id });
    const page = await call("/v1/web/people/list", { category: "filmmakers" });
    assert.deepEqual(page.body.features.map((f: any) => [f.name, f.blurb, f.postIDs]), [["Ana Ruiz", "Watch her.", ["p1", "p2"]]]);
    assert.equal((await call("/v1/web/people/admin/applications", {})).body.applications.length, 0);
    assert.equal((await call("/v1/web/people/admin/applications", { status: "approved" })).body.applications.length, 1);
});

test("one pending application per page per person", async () => {
    const app = { category: "actors", email: "ben@utexas.edu", name: "Ben", message: "Reel attached" };
    assert.equal((await call("/v1/web/people/apply", app)).status, 200);
    assert.equal((await call("/v1/web/people/apply", app)).status, 409);
    assert.equal((await call("/v1/web/people/apply", { ...app, category: "musicians" })).status, 200);
});

test("saving someone already featured edits them instead of adding a duplicate", async () => {
    await save("actors", "UserProfile_ben", "Ben");
    await save("actors", "UserProfile_ben", "Ben", { blurb: "Updated" });
    const page = await call("/v1/web/people/list", { category: "actors" });
    assert.equal(page.body.features.length, 1);
    assert.equal(page.body.features[0].blurb, "Updated");
});

test("featured people can be reordered and removed", async () => {
    await save("musicians", "UserProfile_a", "A");
    await save("musicians", "UserProfile_b", "B");
    const [a] = (await call("/v1/web/people/list", { category: "musicians" })).body.features;
    await call("/v1/web/people/admin/move", { id: a.id, direction: "down" });
    assert.deepEqual((await call("/v1/web/people/list", { category: "musicians" })).body.features.map((f: any) => f.name), ["B", "A"]);
    await call("/v1/web/people/admin/remove", { id: a.id });
    assert.deepEqual((await call("/v1/web/people/list", { category: "musicians" })).body.features.map((f: any) => f.name), ["B"]);
});

test("unknown pages and non-profile IDs are refused", async () => {
    assert.equal((await save("dancers", "UserProfile_x", "X")).status, 400);
    assert.equal((await save("actors", "not-a-profile", "X")).status, 400);
    assert.equal((await call("/v1/web/people/apply", { category: "actors", email: "x@utexas.edu", name: "X", message: "" })).status, 400);
});

test("staff picks: new picks go first, notes can be edited, order can change", async () => {
    await call("/v1/web/people/picks/admin/save", { postID: "p1", note: "" });
    await call("/v1/web/people/picks/admin/save", { postID: "p2", note: "Gorgeous" });
    const ids = async () => (await call("/v1/web/people/picks/list", {})).body.picks.map((p: any) => p.postID);
    assert.deepEqual(await ids(), ["p2", "p1"]);

    await call("/v1/web/people/picks/admin/save", { postID: "p1", note: "Edited" });
    const picks = (await call("/v1/web/people/picks/list", {})).body.picks;
    assert.deepEqual(picks.map((p: any) => [p.postID, p.note]), [["p2", "Gorgeous"], ["p1", "Edited"]]);

    await call("/v1/web/people/picks/admin/move", { postID: "p1", direction: "up" });
    assert.deepEqual(await ids(), ["p1", "p2"]);
    await call("/v1/web/people/picks/admin/remove", { postID: "p1" });
    assert.deepEqual(await ids(), ["p2"]);
});

test("featured collections: create, fill, reorder, edit, remove", async () => {
    const a = (await call("/v1/web/people/collections/admin/save", { title: "Fall Showcase", description: "From the fall showcase" })).body.id;
    const b = (await call("/v1/web/people/collections/admin/save", { title: "Best of RTF" })).body.id;
    const list = async () => (await call("/v1/web/people/collections/list", {})).body.collections;
    assert.deepEqual((await list()).map((c: any) => c.title), ["Best of RTF", "Fall Showcase"]);

    await call("/v1/web/people/collections/admin/add", { collectionID: a, postID: "p1", note: "" });
    await call("/v1/web/people/collections/admin/add", { collectionID: a, postID: "p2", note: "Wow" });
    await call("/v1/web/people/collections/admin/add", { collectionID: a, postID: "p1", note: "Edited" });
    const items = async () => (await list()).find((c: any) => c.id === a).items;
    assert.deepEqual((await items()).map((i: any) => [i.postID, i.note]), [["p1", "Edited"], ["p2", "Wow"]]);

    await call("/v1/web/people/collections/admin/move-item", { collectionID: a, postID: "p2", direction: "up" });
    assert.deepEqual((await items()).map((i: any) => i.postID), ["p2", "p1"]);
    await call("/v1/web/people/collections/admin/remove-item", { collectionID: a, postID: "p2" });
    assert.deepEqual((await items()).map((i: any) => i.postID), ["p1"]);

    await call("/v1/web/people/collections/admin/move", { id: a, direction: "up" });
    assert.deepEqual((await list()).map((c: any) => c.id), [a, b]);
    await call("/v1/web/people/collections/admin/save", { id: a, title: "Fall Showcase 2026", description: "" });
    assert.equal((await list())[0].title, "Fall Showcase 2026");

    await call("/v1/web/people/collections/admin/remove", { id: a });
    assert.deepEqual((await list()).map((c: any) => c.id), [b]);
    assert.equal((await call("/v1/web/people/collections/admin/add", { collectionID: a, postID: "p9" })).status, 404);
    assert.equal((await call("/v1/web/people/collections/admin/save", { title: "" })).status, 400);
});

test("only the website can change featured collections", async () => {
    assert.equal((await call("/v1/web/people/collections/admin/save", { title: "x" }, null)).status, 403);
});

test("only the website can change staff picks", async () => {
    assert.equal((await call("/v1/web/people/picks/admin/save", { postID: "p1" }, null)).status, 403);
});
