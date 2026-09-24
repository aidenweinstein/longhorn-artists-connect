/**
 * Stage 1 of the migration: export everything out of CloudKit to local disk.
 *
 * Deliberately split from the load stage. The export is the slow, rate-limited,
 * failure-prone half (it downloads every video in the app), and you will want to
 * re-run the load several times against a staging database without paying for
 * the download again.
 *
 *     npm run export
 *
 * Output:
 *     out/records/<RecordType>.json    raw CloudKit records, verbatim
 *     out/rows/*.json                  transformed Postgres-shaped rows
 *     out/assets/<post_id>/<kind>_<n>.<ext>
 *     out/manifest.json                asset inventory + MIME types
 *     out/report.json                  counts and anomalies — READ THIS
 */

import 'dotenv/config';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import pLimit from 'p-limit';

import { CloudKitClient, type CKRecord, asset } from './cloudkit.js';
import { detectType, fallbackType, mimeForExtension } from './mime.js';
import {
    POST_TRANSFORMS,
    type ConversationRow,
    type CreditRow,
    type LikeRow,
    type MessageRow,
    type ModerationEditRow,
    type ModerationRow,
    type PendingAsset,
    type PostRow,
    type ProfileRow,
    transformConversation,
    transformLike,
    transformMessage,
    transformModerationAction,
    transformModerationEdit,
    transformProfile,
} from './mapping.js';

const EXPORT_DIR = process.env['EXPORT_DIR'] ?? './out';
const CONCURRENCY = Number(process.env['CONCURRENCY'] ?? 4);
const SKIP_ASSETS = process.env['SKIP_ASSETS'] === '1';

const client = new CloudKitClient({
    apiToken: process.env['CK_API_TOKEN'] ?? '',
    containerID: process.env['CK_CONTAINER_ID'] ?? 'iCloud.LAA.Longhorn-Artists-Connect',
    environment: process.env['CK_ENVIRONMENT'] ?? 'production',
});

interface AssetManifestEntry {
    post_id: string;
    kind: string;
    sort_order: number;
    local_path: string;
    storage_path: string;
    mime_type: string;
    byte_size: number;
    /** True when the sniffed type disagreed with what the record claimed. */
    type_corrected: boolean;
}

interface Report {
    environment: string;
    exported_at: string;
    counts: Record<string, number>;
    anomalies: {
        posts_without_creator: string[];
        posts_with_unparseable_credits: number;
        assets_failed_to_download: string[];
        assets_with_corrected_type: number;
        profiles_skipped_no_name: number;
        likes_orphaned: number;
        messages_orphaned: number;
    };
    notes: string[];
}

async function writeJSON(relativePath: string, data: unknown): Promise<void> {
    const path = join(EXPORT_DIR, relativePath);
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, JSON.stringify(data, null, 2), 'utf8');
}

async function fetchType(recordType: string): Promise<CKRecord[]> {
    process.stdout.write(`  ${recordType} … `);
    const records = await client.fetchAll(recordType);
    process.stdout.write(`${records.length}\n`);
    await writeJSON(`records/${recordType}.json`, records);
    return records;
}

async function main(): Promise<void> {
    const report: Report = {
        environment: process.env['CK_ENVIRONMENT'] ?? 'production',
        exported_at: new Date().toISOString(),
        counts: {},
        anomalies: {
            posts_without_creator: [],
            posts_with_unparseable_credits: 0,
            assets_failed_to_download: [],
            assets_with_corrected_type: 0,
            profiles_skipped_no_name: 0,
            likes_orphaned: 0,
            messages_orphaned: 0,
        },
        notes: [],
    };

    console.log(`\nExporting from CloudKit [${report.environment}]\n`);

    // -----------------------------------------------------------------------
    // Posts
    // -----------------------------------------------------------------------
    const posts: PostRow[] = [];
    const credits: CreditRow[] = [];
    const pendingAssets: PendingAsset[] = [];

    console.log('Submissions:');
    for (const [recordType, spec] of Object.entries(POST_TRANSFORMS)) {
        const records = await fetchType(recordType);
        report.counts[recordType] = records.length;

        for (const record of records) {
            const result = spec.fn(record);
            posts.push(result.post);
            credits.push(...result.credits);
            pendingAssets.push(...result.assets);

            if (!result.post.legacy_author_cloudkit_id) {
                report.anomalies.posts_without_creator.push(result.post.id);
            }
        }
    }

    // -----------------------------------------------------------------------
    // Moderation — folded into posts, then retired
    // -----------------------------------------------------------------------
    console.log('\nModeration:');
    const moderationActions: ModerationRow[] = [];
    for (const record of await fetchType('ModerationAction')) {
        const row = transformModerationAction(record);
        if (row) moderationActions.push(row);
    }
    report.counts['ModerationAction'] = moderationActions.length;

    const removedIDs = new Set(moderationActions.filter((m) => m.is_removed).map((m) => m.post_id));
    let applied = 0;
    for (const post of posts) {
        if (removedIDs.has(post.id)) {
            post.is_removed = true;
            applied++;
        }
    }
    report.notes.push(
        `Applied ${applied} ModerationAction removals directly to posts.is_removed. ` +
        `The record type is retired — nothing in the new schema reads it.`,
    );

    const moderationEdits: ModerationEditRow[] = [];
    for (const record of await fetchType('ModerationEdit')) {
        const row = transformModerationEdit(record);
        if (row) moderationEdits.push(row);
    }
    report.counts['ModerationEdit'] = moderationEdits.length;
    if (moderationEdits.length > 0) {
        report.notes.push(
            `${moderationEdits.length} ModerationEdit overlays exported to rows/moderation_edits.json. ` +
            `These are NOT auto-applied: each payload is a JSON Submission that overrode fields on ` +
            `another user's post, and the field mapping is lossy. Review and apply them manually ` +
            `after loading, then delete the file.`,
        );
    }

    // -----------------------------------------------------------------------
    // Profiles
    // -----------------------------------------------------------------------
    console.log('\nProfiles:');
    const profiles: ProfileRow[] = [];
    const avatarAssets: PendingAsset[] = [];
    for (const record of await fetchType('UserProfile')) {
        const result = transformProfile(record);
        if (!result) {
            report.anomalies.profiles_skipped_no_name++;
            continue;
        }
        profiles.push(result.profile);
        if (result.avatar) {
            avatarAssets.push({
                postId: `avatar_${result.profile.legacy_cloudkit_user_id}`,
                kind: 'thumbnail',
                sortOrder: 0,
                ck: result.avatar,
                extensionHint: null,
            });
        }
    }
    report.counts['UserProfile'] = profiles.length;

    // -----------------------------------------------------------------------
    // Likes
    // -----------------------------------------------------------------------
    console.log('\nLikes:');
    const postIDs = new Set(posts.map((p) => p.id));
    const likes: LikeRow[] = [];
    for (const record of await fetchType('PostLike')) {
        const row = transformLike(record);
        if (!row) continue;
        // A like on a post that no longer exists cannot be loaded (FK).
        if (!postIDs.has(row.post_id)) {
            report.anomalies.likes_orphaned++;
            continue;
        }
        likes.push(row);
    }
    report.counts['PostLike'] = likes.length;

    // -----------------------------------------------------------------------
    // Messaging
    // -----------------------------------------------------------------------
    console.log('\nMessaging:');
    const conversations: ConversationRow[] = [];
    for (const record of await fetchType('Conversation')) {
        const row = transformConversation(record);
        if (row) conversations.push(row);
    }
    report.counts['Conversation'] = conversations.length;

    const conversationIDs = new Set(conversations.map((c) => c.id));
    const messages: MessageRow[] = [];
    for (const record of await fetchType('Message')) {
        const result = transformMessage(record);
        if (!result) continue;
        if (!conversationIDs.has(result.message.conversation_id)) {
            report.anomalies.messages_orphaned++;
            continue;
        }
        messages.push(result.message);
        if (result.attachment) {
            pendingAssets.push({
                postId: `message_${result.message.id}`,
                kind: 'gallery',
                sortOrder: 0,
                ck: result.attachment,
                extensionHint: null,
            });
        }
    }
    report.counts['Message'] = messages.length;

    // -----------------------------------------------------------------------
    // Assets
    // -----------------------------------------------------------------------
    const manifest: AssetManifestEntry[] = [];
    const allAssets = [...pendingAssets, ...avatarAssets];

    if (SKIP_ASSETS) {
        report.notes.push(`SKIP_ASSETS=1 — skipped ${allAssets.length} asset downloads (metadata-only run).`);
        console.log(`\nAssets: skipped (${allAssets.length} would have been downloaded)`);
    } else {
        console.log(`\nAssets: downloading ${allAssets.length} files (concurrency ${CONCURRENCY})`);
        const limit = pLimit(CONCURRENCY);
        let done = 0;

        await Promise.all(
            allAssets.map((pending) =>
                limit(async () => {
                    const bytes = await client.downloadAsset(pending.ck);
                    done++;
                    if (done % 25 === 0) {
                        process.stdout.write(`  ${done}/${allAssets.length}\n`);
                    }

                    if (!bytes) {
                        report.anomalies.assets_failed_to_download.push(
                            `${pending.postId}/${pending.kind}`,
                        );
                        return;
                    }

                    const isAudio = pending.kind === 'audio';
                    const sniffed = detectType(bytes, isAudio);
                    const resolved = sniffed ?? fallbackType(pending.kind);

                    // Record when the sniffed container disagreed with the stored
                    // hint — the exact mismatch that made music unplayable.
                    const hinted = pending.extensionHint?.toLowerCase().replace(/^\./, '');
                    const corrected = !!hinted && !!sniffed && hinted !== sniffed.extension;
                    if (corrected) report.anomalies.assets_with_corrected_type++;

                    const fileName = `${pending.kind}_${pending.sortOrder}.${resolved.extension}`;
                    const localPath = join('assets', pending.postId, fileName);
                    const fullPath = join(EXPORT_DIR, localPath);
                    await mkdir(dirname(fullPath), { recursive: true });
                    await writeFile(fullPath, bytes);

                    manifest.push({
                        post_id: pending.postId,
                        kind: pending.kind,
                        sort_order: pending.sortOrder,
                        local_path: localPath,
                        // Matches the path convention enforced by the storage
                        // policies in 0004_storage.sql: first segment = post id.
                        storage_path: `${pending.postId}/${pending.kind}/${fileName}`,
                        mime_type: resolved.mime || mimeForExtension(resolved.extension),
                        byte_size: bytes.length,
                        type_corrected: corrected,
                    });
                }),
            ),
        );
        console.log(`  ${done}/${allAssets.length} done`);
    }

    // -----------------------------------------------------------------------
    // Write everything out
    // -----------------------------------------------------------------------
    await writeJSON('rows/posts.json', posts);
    await writeJSON('rows/credits.json', credits);
    await writeJSON('rows/profiles.json', profiles);
    await writeJSON('rows/likes.json', likes);
    await writeJSON('rows/conversations.json', conversations);
    await writeJSON('rows/messages.json', messages);
    await writeJSON('rows/moderation_edits.json', moderationEdits);
    await writeJSON('manifest.json', manifest);

    report.counts['posts_total'] = posts.length;
    report.counts['credits_total'] = credits.length;
    report.counts['assets_downloaded'] = manifest.length;

    report.notes.push(
        'Script PDFs were NOT exported. They were never uploaded to CloudKit — ' +
        'Submission.scriptURL reads only the local Documents directory ' +
        '(SubmissionStore.swift:360-372) — so they exist solely on their authors\' devices ' +
        'and cannot be recovered server-side.',
    );
    report.notes.push(
        'Film and music releaseYear were NOT exported: the field exists on Submission ' +
        'but is only ever persisted for photography (photographyReleaseYear). ' +
        'This data was already being lost before the migration.',
    );

    await writeJSON('report.json', report);

    // -----------------------------------------------------------------------
    console.log('\n─────────── Export summary ───────────');
    for (const [key, value] of Object.entries(report.counts)) {
        console.log(`  ${key.padEnd(28)} ${value}`);
    }
    const a = report.anomalies;
    console.log('\nAnomalies:');
    console.log(`  posts with no resolvable creator   ${a.posts_without_creator.length}`);
    console.log(`  assets that failed to download     ${a.assets_failed_to_download.length}`);
    console.log(`  assets whose type was corrected    ${a.assets_with_corrected_type}`);
    console.log(`  profiles skipped (no name)         ${a.profiles_skipped_no_name}`);
    console.log(`  orphaned likes                     ${a.likes_orphaned}`);
    console.log(`  orphaned messages                  ${a.messages_orphaned}`);

    if (a.posts_without_creator.length > 0) {
        console.log(
            `\n⚠️  ${a.posts_without_creator.length} posts have no creator user record name. ` +
            `Their authors cannot be auto-linked by claim_legacy_profile(), so those posts will ` +
            `stay unattributed. See out/report.json for the list, and read the "Attribution" ` +
            `section of backend/migration/README.md before loading.`,
        );
    }
    console.log(`\nWrote ${EXPORT_DIR}/. Review report.json, then: npm run load\n`);
}

main().catch((error) => {
    console.error('\n❌ Export failed:', error);
    process.exit(1);
});
