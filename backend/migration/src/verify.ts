/**
 * Stage 3: prove the load was complete and faithful.
 *
 *     npm run verify
 *
 * Exits non-zero on any failure, so it can gate the production cutover.
 *
 * The checks that matter most are the byte-size spot check (proves media
 * actually transferred rather than uploading zero-length files) and the ID
 * preservation check (proves nothing in the shipped app's cached references
 * broke).
 */

import 'dotenv/config';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

import type { PostRow, ProfileRow } from './mapping.js';

const EXPORT_DIR = process.env['EXPORT_DIR'] ?? './out';
const SKIP_ASSETS = process.env['SKIP_ASSETS'] === '1';
const SPOT_CHECK_COUNT = 20;

const url = process.env['SUPABASE_URL'];
const serviceKey = process.env['SUPABASE_SERVICE_ROLE_KEY'];
if (!url || !serviceKey) {
    console.error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.');
    process.exit(1);
}

const db = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
});

let failures = 0;

function check(label: string, ok: boolean, detail = ''): void {
    if (ok) {
        console.log(`  ✓ ${label}`);
    } else {
        failures++;
        console.log(`  ✗ ${label}${detail ? ` — ${detail}` : ''}`);
    }
}

async function countRows(table: string): Promise<number> {
    const { count, error } = await db.from(table).select('*', { count: 'exact', head: true });
    if (error) throw new Error(`count(${table}) failed: ${error.message}`);
    return count ?? 0;
}

async function readJSON<T>(name: string): Promise<T> {
    return JSON.parse(await readFile(join(EXPORT_DIR, name), 'utf8')) as T;
}

interface AssetManifestEntry {
    post_id: string;
    kind: string;
    storage_path: string;
    mime_type: string;
    byte_size: number;
}

async function main(): Promise<void> {
    console.log(`\nVerifying ${url}\n`);

    const exportedPosts = await readJSON<PostRow[]>('rows/posts.json');
    const exportedProfiles = await readJSON<ProfileRow[]>('rows/profiles.json');
    const manifest = await readJSON<AssetManifestEntry[]>('manifest.json');

    // -----------------------------------------------------------------------
    console.log('Row counts:');
    const postCount = await countRows('posts');
    check(`posts: ${postCount} == ${exportedPosts.length} exported`, postCount === exportedPosts.length);

    const profileCount = await countRows('profiles');
    check(
        `profiles: ${profileCount} >= ${exportedProfiles.length} exported`,
        profileCount >= exportedProfiles.length,
        'fewer profiles than exported',
    );

    // -----------------------------------------------------------------------
    console.log('\nPer-type counts:');
    for (const type of ['film', 'music', 'reel', 'project', 'event', 'photography'] as const) {
        const expected = exportedPosts.filter((p) => p.type === type).length;
        const { count, error } = await db
            .from('posts')
            .select('*', { count: 'exact', head: true })
            .eq('type', type);
        if (error) throw new Error(error.message);
        check(`${type}: ${count} == ${expected}`, count === expected);
    }

    // -----------------------------------------------------------------------
    console.log('\nID preservation:');
    // Cached media filenames, featured_work_ids cross-references and every
    // locally stored id in the shipped app depend on these being unchanged.
    const sample = exportedPosts.slice(0, 50).map((p) => p.id);
    const { data: found, error: idError } = await db.from('posts').select('id').in('id', sample);
    if (idError) throw new Error(idError.message);
    check(
        `all ${sample.length} sampled post UUIDs preserved verbatim`,
        (found?.length ?? 0) === sample.length,
        `${sample.length - (found?.length ?? 0)} missing`,
    );

    // -----------------------------------------------------------------------
    console.log('\nModeration state:');
    const expectedRemoved = exportedPosts.filter((p) => p.is_removed).length;
    const { count: removedCount, error: removedError } = await db
        .from('posts')
        .select('*', { count: 'exact', head: true })
        .eq('is_removed', true);
    if (removedError) throw new Error(removedError.message);
    check(
        `${removedCount} posts marked removed == ${expectedRemoved} ModerationAction removals`,
        removedCount === expectedRemoved,
    );

    // -----------------------------------------------------------------------
    console.log('\nReferential integrity:');
    const { count: orphanCredits } = await db
        .from('post_credits')
        .select('*', { count: 'exact', head: true })
        .is('post_id', null);
    check('no credits without a post', (orphanCredits ?? 0) === 0);

    const { count: unattributed } = await db
        .from('posts')
        .select('*', { count: 'exact', head: true })
        .is('author_id', null);
    console.log(
        `  ℹ ${unattributed} posts are unattributed (author_id null). These are ` +
        `backfilled by claim_legacy_profile() when each author signs in — not a failure, ` +
        `but the number should shrink after the cutover.`,
    );

    // -----------------------------------------------------------------------
    if (SKIP_ASSETS) {
        console.log('\nMedia: skipped (SKIP_ASSETS=1)');
    } else {
        console.log(`\nMedia spot check (${SPOT_CHECK_COUNT} random files):`);

        const mediaCount = await countRows('post_media');
        const expectedMedia = manifest.filter(
            (m) => !m.post_id.startsWith('avatar_') && !m.post_id.startsWith('message_'),
        ).length;
        check(`post_media: ${mediaCount} == ${expectedMedia} uploaded`, mediaCount === expectedMedia);

        // Byte-for-byte size comparison against what CloudKit served. A truncated
        // or zero-length upload is the failure mode that would otherwise ship
        // silently and only surface as unplayable posts.
        const shuffled = [...manifest].sort(() => Math.random() - 0.5).slice(0, SPOT_CHECK_COUNT);
        let sizeMismatches = 0;
        let downloadFailures = 0;

        for (const entry of shuffled) {
            const bucket = entry.post_id.startsWith('avatar_') ? 'avatars' : 'media';
            const { data, error } = await db.storage.from(bucket).download(entry.storage_path);
            if (error || !data) {
                downloadFailures++;
                console.log(`    ✗ ${entry.storage_path}: ${error?.message ?? 'no data'}`);
                continue;
            }
            const size = (await data.arrayBuffer()).byteLength;
            if (size !== entry.byte_size) {
                sizeMismatches++;
                console.log(`    ✗ ${entry.storage_path}: ${size} bytes, expected ${entry.byte_size}`);
            }
        }

        check(`all ${shuffled.length} sampled files downloadable`, downloadFailures === 0);
        check('all sampled files byte-size identical to source', sizeMismatches === 0);

        // Content-Type is what made music unplayable under CloudKit; confirm it
        // survived the upload.
        const audioSample = manifest.filter((m) => m.kind === 'audio').slice(0, 5);
        if (audioSample.length > 0) {
            const { data: mediaRows, error } = await db
                .from('post_media')
                .select('storage_path, mime_type')
                .in('storage_path', audioSample.map((a) => a.storage_path));
            if (error) throw new Error(error.message);
            const wrong = (mediaRows ?? []).filter(
                (row) => !String(row.mime_type).startsWith('audio/'),
            );
            check(
                `audio rows carry an audio/* MIME type (${audioSample.length} sampled)`,
                wrong.length === 0,
                wrong.map((w) => `${w.storage_path}=${w.mime_type}`).join(', '),
            );
        }
    }

    // -----------------------------------------------------------------------
    console.log('\n─────────────────────────────────────');
    if (failures === 0) {
        console.log('All verification checks passed.\n');
    } else {
        console.log(`${failures} check(s) FAILED. Do not cut over.\n`);
        process.exit(1);
    }
}

main().catch((error) => {
    console.error('\n❌ Verification failed:', error);
    process.exit(1);
});
