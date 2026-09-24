/**
 * Stage 2: load the exported data into Supabase.
 *
 *     npm run load
 *
 * Re-runnable. Every write is an upsert keyed on a stable id, so a failed run can
 * simply be repeated without duplicating rows.
 *
 * Uses the SERVICE ROLE key, which bypasses RLS. That is required — the loader
 * writes rows on behalf of users who have not authenticated yet, and RLS
 * correctly forbids that for any normal client. It also means this script has no
 * safety net: it can write anything. Run it against staging first, and revoke the
 * key when the migration is finished.
 */

import 'dotenv/config';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import pLimit from 'p-limit';

import type {
    ConversationRow,
    CreditRow,
    LikeRow,
    MessageRow,
    PostRow,
    ProfileRow,
} from './mapping.js';

const EXPORT_DIR = process.env['EXPORT_DIR'] ?? './out';
const CONCURRENCY = Number(process.env['CONCURRENCY'] ?? 4);
const SKIP_ASSETS = process.env['SKIP_ASSETS'] === '1';
const BATCH = 500;

const url = process.env['SUPABASE_URL'];
const serviceKey = process.env['SUPABASE_SERVICE_ROLE_KEY'];
if (!url || !serviceKey) {
    console.error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required. See .env.example.');
    process.exit(1);
}

const db = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
});

interface AssetManifestEntry {
    post_id: string;
    kind: string;
    sort_order: number;
    local_path: string;
    storage_path: string;
    mime_type: string;
    byte_size: number;
}

async function readJSON<T>(name: string): Promise<T> {
    return JSON.parse(await readFile(join(EXPORT_DIR, name), 'utf8')) as T;
}

/** Inserts in batches so a large table does not exceed the request size limit. */
async function upsert(table: string, rows: unknown[], conflictTarget: string): Promise<void> {
    if (rows.length === 0) {
        console.log(`  ${table.padEnd(16)} nothing to load`);
        return;
    }
    for (let i = 0; i < rows.length; i += BATCH) {
        const chunk = rows.slice(i, i + BATCH);
        const { error } = await db.from(table).upsert(chunk as never, { onConflict: conflictTarget });
        if (error) {
            throw new Error(`${table} upsert failed at row ${i}: ${error.message}`);
        }
    }
    console.log(`  ${table.padEnd(16)} ${rows.length}`);
}

async function main(): Promise<void> {
    console.log(`\nLoading into ${url}\n`);

    const skipped = {
        posts_no_author: 0,
        credits_unresolved_profile: 0,
        likes_no_profile: 0,
        conversations_missing_participant: 0,
        messages_no_sender: 0,
        assets_failed_upload: [] as string[],
    };

    // -----------------------------------------------------------------------
    // 1. Profiles — everything else keys off these
    // -----------------------------------------------------------------------
    console.log('Profiles:');
    const profiles = await readJSON<ProfileRow[]>('rows/profiles.json');
    await upsert('profiles', profiles, 'legacy_cloudkit_user_id');

    // Build legacy CloudKit user id -> new profile uuid.
    const profileByLegacyID = new Map<string, string>();
    {
        let from = 0;
        for (;;) {
            const { data, error } = await db
                .from('profiles')
                .select('id, legacy_cloudkit_user_id')
                .not('legacy_cloudkit_user_id', 'is', null)
                .range(from, from + 999);
            if (error) throw new Error(`profile id lookup failed: ${error.message}`);
            if (!data || data.length === 0) break;
            for (const row of data) {
                profileByLegacyID.set(row.legacy_cloudkit_user_id as string, row.id as string);
            }
            if (data.length < 1000) break;
            from += 1000;
        }
    }
    console.log(`  resolved ${profileByLegacyID.size} legacy profile ids`);

    // -----------------------------------------------------------------------
    // 2. Posts
    // -----------------------------------------------------------------------
    console.log('\nPosts:');
    const posts = await readJSON<PostRow[]>('rows/posts.json');
    const postRows = posts.map((post) => {
        const legacy = post.legacy_author_cloudkit_id;
        const authorId = legacy ? profileByLegacyID.get(legacy) ?? null : null;
        if (!authorId) skipped.posts_no_author++;
        // author_id stays null when unresolved; legacy_author_cloudkit_id is kept
        // so claim_legacy_profile() can backfill it when the owner signs in.
        return { ...post, author_id: authorId };
    });
    await upsert('posts', postRows, 'id');
    const postIDs = new Set(posts.map((p) => p.id));

    // -----------------------------------------------------------------------
    // 3. Credits
    // -----------------------------------------------------------------------
    console.log('\nCredits:');
    const credits = await readJSON<CreditRow[]>('rows/credits.json');
    const creditRows = credits.map((credit) => {
        const legacy = credit.legacy_profile_cloudkit_id;
        const profileId = legacy ? profileByLegacyID.get(legacy) ?? null : null;
        if (legacy && !profileId) skipped.credits_unresolved_profile++;
        return { ...credit, profile_id: profileId };
    });
    // post_credits has a surrogate key and no natural unique constraint, so a
    // re-run would duplicate. Clear and reinsert instead.
    {
        const { error } = await db.from('post_credits').delete().in('post_id', [...postIDs]);
        if (error) throw new Error(`clearing post_credits failed: ${error.message}`);
    }
    for (let i = 0; i < creditRows.length; i += BATCH) {
        const { error } = await db.from('post_credits').insert(creditRows.slice(i, i + BATCH) as never);
        if (error) throw new Error(`post_credits insert failed at ${i}: ${error.message}`);
    }
    console.log(`  post_credits     ${creditRows.length}`);

    // -----------------------------------------------------------------------
    // 4. Media — upload files, then write post_media rows
    // -----------------------------------------------------------------------
    const manifest = await readJSON<AssetManifestEntry[]>('manifest.json');

    // Populated by the media stage, consumed by the messaging stage below.
    const attachmentByMessageID = new Map<string, string>();

    if (SKIP_ASSETS) {
        console.log('\nMedia: skipped (SKIP_ASSETS=1)');
    } else {
        console.log(`\nMedia: uploading ${manifest.length} files (concurrency ${CONCURRENCY})`);
        const limit = pLimit(CONCURRENCY);
        let done = 0;

        const mediaRows: Record<string, unknown>[] = [];
        const avatarByLegacyID = new Map<string, string>();

        await Promise.all(
            manifest.map((entry) =>
                limit(async () => {
                    const bytes = await readFile(join(EXPORT_DIR, entry.local_path));

                    // Three destinations, distinguished by the synthetic prefixes
                    // the exporter used for non-post assets.
                    const isAvatar = entry.post_id.startsWith('avatar_');
                    const isAttachment = entry.post_id.startsWith('message_');
                    const bucket = isAvatar ? 'avatars' : 'media';

                    let path = entry.storage_path;
                    if (isAvatar) {
                        const legacyID = entry.post_id.slice('avatar_'.length);
                        const profileId = profileByLegacyID.get(legacyID);
                        if (!profileId) return; // profile was skipped (no name)
                        // avatars policies key on "<profile_id>.<ext>".
                        const ext = entry.storage_path.split('.').pop() ?? 'jpg';
                        path = `${profileId}.${ext}`;
                        avatarByLegacyID.set(legacyID, path);
                    }

                    const { error } = await db.storage.from(bucket).upload(path, bytes, {
                        contentType: entry.mime_type,
                        upsert: true,
                    });
                    done++;
                    if (done % 25 === 0) process.stdout.write(`  ${done}/${manifest.length}\n`);

                    if (error) {
                        skipped.assets_failed_upload.push(`${entry.post_id}/${entry.kind}`);
                        return;
                    }

                    if (isAttachment) {
                        attachmentByMessageID.set(entry.post_id.slice('message_'.length), path);
                    } else if (!isAvatar && postIDs.has(entry.post_id)) {
                        mediaRows.push({
                            post_id: entry.post_id,
                            kind: entry.kind,
                            storage_path: path,
                            mime_type: entry.mime_type,
                            byte_size: entry.byte_size,
                            sort_order: entry.sort_order,
                        });
                    }
                }),
            ),
        );
        console.log(`  ${done}/${manifest.length} uploaded`);

        // Same surrogate-key situation as credits.
        {
            const { error } = await db.from('post_media').delete().in('post_id', [...postIDs]);
            if (error) throw new Error(`clearing post_media failed: ${error.message}`);
        }
        for (let i = 0; i < mediaRows.length; i += BATCH) {
            const { error } = await db.from('post_media').insert(mediaRows.slice(i, i + BATCH) as never);
            if (error) throw new Error(`post_media insert failed at ${i}: ${error.message}`);
        }
        console.log(`  post_media       ${mediaRows.length}`);

        // Patch avatar paths onto profiles.
        for (const [legacyID, path] of avatarByLegacyID) {
            const profileId = profileByLegacyID.get(legacyID);
            if (!profileId) continue;
            await db.from('profiles').update({ avatar_path: path }).eq('id', profileId);
        }
        console.log(`  avatars          ${avatarByLegacyID.size}`);
    }

    // -----------------------------------------------------------------------
    // 5. Likes
    // -----------------------------------------------------------------------
    console.log('\nLikes:');
    const likes = await readJSON<LikeRow[]>('rows/likes.json');
    const likeRows = likes
        .map((like) => {
            const profileId = profileByLegacyID.get(like.legacy_user_id);
            if (!profileId) {
                skipped.likes_no_profile++;
                return null;
            }
            return { post_id: like.post_id, profile_id: profileId, created_at: like.created_at };
        })
        .filter((row): row is NonNullable<typeof row> => row !== null);
    await upsert('post_likes', likeRows, 'post_id,profile_id');

    // -----------------------------------------------------------------------
    // 6. Conversations and messages
    // -----------------------------------------------------------------------
    console.log('\nMessaging:');
    const conversations = await readJSON<ConversationRow[]>('rows/conversations.json');
    const conversationRows = conversations
        .map((conversation) => {
            const a = profileByLegacyID.get(conversation.legacy_participant_a);
            const b = profileByLegacyID.get(conversation.legacy_participant_b);
            // Both participants must exist; the FK is not nullable and a
            // one-sided conversation is meaningless.
            if (!a || !b || a === b) {
                skipped.conversations_missing_participant++;
                return null;
            }
            // Match the normalized ordering enforced by conversations_pair_idx.
            const [first, second] = a < b ? [a, b] : [b, a];
            return {
                id: conversation.id,
                participant_a: first,
                participant_b: second,
                last_message_preview: conversation.last_message_preview,
                last_message_at: conversation.last_message_at,
                created_at: conversation.created_at,
            };
        })
        .filter((row): row is NonNullable<typeof row> => row !== null);
    await upsert('conversations', conversationRows, 'id');

    const loadedConversations = new Set(conversationRows.map((c) => c.id));

    const messages = await readJSON<MessageRow[]>('rows/messages.json');
    const messageRows = messages
        .map((message) => {
            const senderId = profileByLegacyID.get(message.legacy_sender_id);
            if (!senderId || !loadedConversations.has(message.conversation_id)) {
                skipped.messages_no_sender++;
                return null;
            }
            return {
                id: message.id,
                conversation_id: message.conversation_id,
                sender_id: senderId,
                body: message.body,
                attachment_path: attachmentByMessageID.get(message.id) ?? null,
                attachment_type: message.attachmentType,
                created_at: message.created_at,
                read_at: message.read_at,
            };
        })
        .filter((row): row is NonNullable<typeof row> => row !== null);

    // The messages_touch_conversation trigger would rewrite every conversation
    // preview from whichever historical message happened to load last. Load the
    // rows, then restore the previews CloudKit recorded.
    await upsert('messages', messageRows, 'id');
    for (const conversation of conversationRows) {
        await db
            .from('conversations')
            .update({
                last_message_preview: conversation.last_message_preview,
                last_message_at: conversation.last_message_at,
            })
            .eq('id', conversation.id);
    }
    console.log('  conversation previews restored');

    // -----------------------------------------------------------------------
    console.log('\n─────────── Load summary ───────────');
    console.log(`  posts without a resolvable author   ${skipped.posts_no_author}`);
    console.log(`  credits with unresolved profile     ${skipped.credits_unresolved_profile}`);
    console.log(`  likes dropped (no profile)          ${skipped.likes_no_profile}`);
    console.log(`  conversations dropped               ${skipped.conversations_missing_participant}`);
    console.log(`  messages dropped                    ${skipped.messages_no_sender}`);
    console.log(`  asset uploads failed                ${skipped.assets_failed_upload.length}`);
    console.log('\nNow run: npm run verify\n');
}

main().catch((error) => {
    console.error('\n❌ Load failed:', error);
    process.exit(1);
});
