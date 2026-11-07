/// People pages on the Nexus website: Filmmakers, Actors, Musicians.
///
/// Routes (server-to-server from the website only, behind WEB_CLIENT_TOKEN):
///   POST /v1/web/people/list           { category }                     -> { features }
///   POST /v1/web/people/apply          { category, email, profileID?, name, message, links } -> { id }
///   POST /v1/web/people/admin/applications { status? }                  -> { applications }
///   POST /v1/web/people/admin/save     { category, profileID, name, blurb, postIDs, applicationID? } -> { id }
///   POST /v1/web/people/admin/remove   { id }
///   POST /v1/web/people/admin/decide   { applicationID, status }
///   POST /v1/web/people/admin/move     { id, direction }
///
/// Staff Picks, managed the same way:
///   POST /v1/web/people/picks/list                                      -> { picks }
///   POST /v1/web/people/picks/admin/save   { postID, note }   adds, or edits the note
///   POST /v1/web/people/picks/admin/remove { postID }
///   POST /v1/web/people/picks/admin/move   { postID, direction }
///
/// Featured collections (named groups of posts below the main picks):
///   POST /v1/web/people/collections/list                                  -> { collections }
///   POST /v1/web/people/collections/admin/save        { id?, title, description } -> { id }
///   POST /v1/web/people/collections/admin/remove      { id }
///   POST /v1/web/people/collections/admin/move        { id, direction }
///   POST /v1/web/people/collections/admin/add         { collectionID, postID, note }  adds, or edits the note
///   POST /v1/web/people/collections/admin/remove-item { collectionID, postID }
///   POST /v1/web/people/collections/admin/move-item   { collectionID, postID, direction }
///
/// Who counts as an admin is decided by the website (its ADMIN_EMAILS setting,
/// checked against a signed-in session) before it calls the admin routes. The
/// token is what keeps anyone else out: nothing here is reachable from a browser.

import type { Env } from "./util";
import { json, errorResponse, nowSeconds, randomToken, checkAllRateLimits } from "./util";
import { authorizeWebClient } from "./webSession";

export const PEOPLE_CATEGORIES = ["filmmakers", "actors", "musicians"] as const;
type Category = (typeof PEOPLE_CATEGORIES)[number];

const isCategory = (v: unknown): v is Category => typeof v === "string" && (PEOPLE_CATEGORIES as readonly string[]).includes(v);
const text = (v: unknown, max: number) => String(v ?? "").trim().slice(0, max);

async function body(request: Request): Promise<Record<string, unknown>> {
    try {
        const parsed = await request.json();
        return typeof parsed === "object" && parsed !== null ? (parsed as Record<string, unknown>) : {};
    } catch {
        return {};
    }
}

function feature(row: any) {
    let postIDs: string[] = [];
    try {
        const v = JSON.parse(row.post_ids);
        if (Array.isArray(v)) postIDs = v.filter((x) => typeof x === "string");
    } catch {}
    return {
        id: row.id,
        category: row.category,
        profileID: row.profile_id,
        name: row.name,
        blurb: row.blurb,
        postIDs,
        position: row.position,
    };
}

export async function handlePeople(request: Request, env: Env, path: string): Promise<Response> {
    const denied = authorizeWebClient(request, env);
    if (denied) return denied;
    const b = await body(request);
    const now = nowSeconds();

    switch (path) {
        case "/v1/web/people/list": {
            const where = isCategory(b.category) ? `WHERE category = ?` : ``;
            const stmt = env.DB.prepare(`SELECT * FROM people_features ${where} ORDER BY position, created_at`);
            const { results } = await (where ? stmt.bind(b.category) : stmt).all();
            return json({ features: (results ?? []).map(feature) });
        }

        case "/v1/web/people/apply": {
            if (!isCategory(b.category)) return errorResponse("bad_request", "Pick Filmmakers, Actors or Musicians.", 400);
            const email = text(b.email, 254).toLowerCase();
            const name = text(b.name, 120);
            const message = text(b.message, 3000);
            if (!email || !name) return errorResponse("bad_request", "Sign in before applying.", 400);
            if (!message) return errorResponse("bad_request", "Tell us a bit about your work.", 400);
            if (await checkAllRateLimits(env, [{ dimension: "people_apply", value: email, limit: 3, windowSeconds: 86_400 }])) {
                return errorResponse("rate_limited", "You've applied a few times today. Try again tomorrow.", 429);
            }
            const existing = await env.DB.prepare(
                `SELECT id FROM people_applications WHERE email = ? AND category = ? AND status = 'pending'`,
            )
                .bind(email, b.category)
                .first();
            if (existing) return errorResponse("already_applied", "Your application for this page is already in review.", 409);
            const id = randomToken(12);
            await env.DB.prepare(
                `INSERT INTO people_applications (id, category, email, profile_id, name, message, links, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
            )
                .bind(id, b.category, email, text(b.profileID, 200) || null, name, message, text(b.links, 1000), now)
                .run();
            return json({ id });
        }

        case "/v1/web/people/admin/applications": {
            const status = ["pending", "approved", "declined"].includes(String(b.status)) ? String(b.status) : "pending";
            const { results } = await env.DB.prepare(
                `SELECT * FROM people_applications WHERE status = ? ORDER BY created_at DESC LIMIT 200`,
            )
                .bind(status)
                .all();
            return json({
                applications: (results ?? []).map((r: any) => ({
                    id: r.id,
                    category: r.category,
                    email: r.email,
                    profileID: r.profile_id ?? undefined,
                    name: r.name,
                    message: r.message,
                    links: r.links,
                    status: r.status,
                    createdAt: r.created_at,
                })),
            });
        }

        case "/v1/web/people/admin/save": {
            if (!isCategory(b.category)) return errorResponse("bad_request", "Unknown page.", 400);
            const profileID = text(b.profileID, 200);
            const name = text(b.name, 120);
            if (!profileID.startsWith("UserProfile_") || !name) return errorResponse("bad_request", "Pick a Nexus profile.", 400);
            const postIDs = (Array.isArray(b.postIDs) ? b.postIDs : []).map((x) => text(x, 200)).filter(Boolean).slice(0, 6);
            const blurb = text(b.blurb, 2000);
            const last = await env.DB.prepare(`SELECT MAX(position) AS p FROM people_features WHERE category = ?`)
                .bind(b.category)
                .first<{ p: number | null }>();
            const id = randomToken(12);
            // Saving someone already on the page updates their entry in place.
            await env.DB.prepare(
                `INSERT INTO people_features (id, category, profile_id, name, blurb, post_ids, position, created_at, updated_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                 ON CONFLICT(category, profile_id) DO UPDATE SET
                   name = excluded.name, blurb = excluded.blurb, post_ids = excluded.post_ids, updated_at = excluded.updated_at`,
            )
                .bind(id, b.category, profileID, name, blurb, JSON.stringify(postIDs), (last?.p ?? -1) + 1, now, now)
                .run();
            if (b.applicationID) {
                await env.DB.prepare(`UPDATE people_applications SET status = 'approved', decided_at = ? WHERE id = ?`)
                    .bind(now, text(b.applicationID, 64))
                    .run();
            }
            const saved = await env.DB.prepare(`SELECT id FROM people_features WHERE category = ? AND profile_id = ?`)
                .bind(b.category, profileID)
                .first<{ id: string }>();
            return json({ id: saved?.id ?? id });
        }

        case "/v1/web/people/admin/remove": {
            await env.DB.prepare(`DELETE FROM people_features WHERE id = ?`).bind(text(b.id, 64)).run();
            return json({ ok: true });
        }

        case "/v1/web/people/admin/decide": {
            const status = String(b.status);
            if (status !== "declined" && status !== "pending") return errorResponse("bad_request", "Unknown decision.", 400);
            await env.DB.prepare(`UPDATE people_applications SET status = ?, decided_at = ? WHERE id = ?`)
                .bind(status, status === "pending" ? null : now, text(b.applicationID, 64))
                .run();
            return json({ ok: true });
        }

        case "/v1/web/people/admin/move": {
            const row = await env.DB.prepare(`SELECT * FROM people_features WHERE id = ?`).bind(text(b.id, 64)).first<any>();
            if (!row) return errorResponse("not_found", "That person isn't on the page.", 404);
            const { results } = await env.DB.prepare(`SELECT id FROM people_features WHERE category = ? ORDER BY position, created_at`)
                .bind(row.category)
                .all<{ id: string }>();
            const order = (results ?? []).map((r) => r.id);
            const i = order.indexOf(row.id);
            const j = b.direction === "up" ? i - 1 : i + 1;
            if (i < 0 || j < 0 || j >= order.length) return json({ ok: true });
            [order[i], order[j]] = [order[j], order[i]];
            await env.DB.batch(order.map((id, n) => env.DB.prepare(`UPDATE people_features SET position = ? WHERE id = ?`).bind(n, id)));
            return json({ ok: true });
        }

        case "/v1/web/people/picks/list": {
            const { results } = await env.DB.prepare(`SELECT * FROM staff_picks ORDER BY position, created_at`).all();
            return json({ picks: (results ?? []).map((r: any) => ({ postID: r.post_id, note: r.note })) });
        }

        case "/v1/web/people/picks/admin/save": {
            const postID = text(b.postID, 200);
            if (!postID) return errorResponse("bad_request", "Pick a post.", 400);
            // New picks go to the top, where they're most visible; re-saving keeps the spot.
            const first = await env.DB.prepare(`SELECT MIN(position) AS p FROM staff_picks`).first<{ p: number | null }>();
            await env.DB.prepare(
                `INSERT INTO staff_picks (post_id, note, position, created_at) VALUES (?, ?, ?, ?)
                 ON CONFLICT(post_id) DO UPDATE SET note = excluded.note`,
            )
                .bind(postID, text(b.note, 500), (first?.p ?? 1) - 1, now)
                .run();
            return json({ ok: true });
        }

        case "/v1/web/people/picks/admin/remove": {
            await env.DB.prepare(`DELETE FROM staff_picks WHERE post_id = ?`).bind(text(b.postID, 200)).run();
            return json({ ok: true });
        }

        case "/v1/web/people/picks/admin/move": {
            const { results } = await env.DB.prepare(`SELECT post_id FROM staff_picks ORDER BY position, created_at`).all<{ post_id: string }>();
            const order = (results ?? []).map((r) => r.post_id);
            const i = order.indexOf(text(b.postID, 200));
            const j = b.direction === "up" ? i - 1 : i + 1;
            if (i < 0 || j < 0 || j >= order.length) return json({ ok: true });
            [order[i], order[j]] = [order[j], order[i]];
            await env.DB.batch(order.map((id, n) => env.DB.prepare(`UPDATE staff_picks SET position = ? WHERE post_id = ?`).bind(n, id)));
            return json({ ok: true });
        }

        case "/v1/web/people/collections/list": {
            const [collections, items] = await Promise.all([
                env.DB.prepare(`SELECT * FROM featured_collections ORDER BY position, created_at`).all(),
                env.DB.prepare(`SELECT * FROM featured_collection_items ORDER BY position, created_at`).all(),
            ]);
            return json({
                collections: (collections.results ?? []).map((c: any) => ({
                    id: c.id,
                    title: c.title,
                    description: c.description,
                    items: (items.results ?? [])
                        .filter((i: any) => i.collection_id === c.id)
                        .map((i: any) => ({ postID: i.post_id, note: i.note })),
                })),
            });
        }

        case "/v1/web/people/collections/admin/save": {
            const title = text(b.title, 120);
            if (!title) return errorResponse("bad_request", "Give the collection a title.", 400);
            const description = text(b.description, 500);
            const id = text(b.id, 100);
            if (id) {
                const r = await env.DB.prepare(`UPDATE featured_collections SET title = ?, description = ? WHERE id = ?`)
                    .bind(title, description, id)
                    .run();
                if (!r.meta?.changes) return errorResponse("not_found", "That collection is gone.", 404);
                return json({ id });
            }
            // New collections go first, where they're most visible.
            const first = await env.DB.prepare(`SELECT MIN(position) AS p FROM featured_collections`).first<{ p: number | null }>();
            const newID = randomToken(12);
            await env.DB.prepare(`INSERT INTO featured_collections (id, title, description, position, created_at) VALUES (?, ?, ?, ?, ?)`)
                .bind(newID, title, description, (first?.p ?? 1) - 1, now)
                .run();
            return json({ id: newID });
        }

        case "/v1/web/people/collections/admin/remove": {
            const id = text(b.id, 100);
            await env.DB.batch([
                env.DB.prepare(`DELETE FROM featured_collection_items WHERE collection_id = ?`).bind(id),
                env.DB.prepare(`DELETE FROM featured_collections WHERE id = ?`).bind(id),
            ]);
            return json({ ok: true });
        }

        case "/v1/web/people/collections/admin/move": {
            const { results } = await env.DB.prepare(`SELECT id FROM featured_collections ORDER BY position, created_at`).all<{ id: string }>();
            const order = (results ?? []).map((r) => r.id);
            const i = order.indexOf(text(b.id, 100));
            const j = b.direction === "up" ? i - 1 : i + 1;
            if (i < 0 || j < 0 || j >= order.length) return json({ ok: true });
            [order[i], order[j]] = [order[j], order[i]];
            await env.DB.batch(order.map((id, n) => env.DB.prepare(`UPDATE featured_collections SET position = ? WHERE id = ?`).bind(n, id)));
            return json({ ok: true });
        }

        case "/v1/web/people/collections/admin/add": {
            const collectionID = text(b.collectionID, 100);
            const postID = text(b.postID, 200);
            if (!postID) return errorResponse("bad_request", "Pick a post.", 400);
            const exists = await env.DB.prepare(`SELECT id FROM featured_collections WHERE id = ?`).bind(collectionID).first();
            if (!exists) return errorResponse("not_found", "That collection is gone.", 404);
            // New posts go to the end of the collection; re-saving keeps the spot and edits the note.
            const last = await env.DB.prepare(`SELECT MAX(position) AS p FROM featured_collection_items WHERE collection_id = ?`)
                .bind(collectionID)
                .first<{ p: number | null }>();
            await env.DB.prepare(
                `INSERT INTO featured_collection_items (collection_id, post_id, note, position, created_at) VALUES (?, ?, ?, ?, ?)
                 ON CONFLICT(collection_id, post_id) DO UPDATE SET note = excluded.note`,
            )
                .bind(collectionID, postID, text(b.note, 500), (last?.p ?? -1) + 1, now)
                .run();
            return json({ ok: true });
        }

        case "/v1/web/people/collections/admin/remove-item": {
            await env.DB.prepare(`DELETE FROM featured_collection_items WHERE collection_id = ? AND post_id = ?`)
                .bind(text(b.collectionID, 100), text(b.postID, 200))
                .run();
            return json({ ok: true });
        }

        case "/v1/web/people/collections/admin/move-item": {
            const collectionID = text(b.collectionID, 100);
            const { results } = await env.DB.prepare(
                `SELECT post_id FROM featured_collection_items WHERE collection_id = ? ORDER BY position, created_at`,
            )
                .bind(collectionID)
                .all<{ post_id: string }>();
            const order = (results ?? []).map((r) => r.post_id);
            const i = order.indexOf(text(b.postID, 200));
            const j = b.direction === "up" ? i - 1 : i + 1;
            if (i < 0 || j < 0 || j >= order.length) return json({ ok: true });
            [order[i], order[j]] = [order[j], order[i]];
            await env.DB.batch(
                order.map((id, n) =>
                    env.DB.prepare(`UPDATE featured_collection_items SET position = ? WHERE collection_id = ? AND post_id = ?`).bind(n, collectionID, id),
                ),
            );
            return json({ ok: true });
        }
    }
    return errorResponse("not_found", "Unknown endpoint.", 404);
}
