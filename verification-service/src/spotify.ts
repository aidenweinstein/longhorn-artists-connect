/// Spotify catalog lookups for the app's music posts (SpotifyLookupService.swift).
///
///   GET /v1/music/spotify/lookup?isrc=<ISRC>        -> { match: TrackMatch | null }
///       The Spotify track for a recording, by ISRC. The Apple Music import calls this
///       to fill in the Spotify link next to the Apple Music one.
///   GET /v1/music/spotify/stats?track=<spotifyID>   -> { track, artist, fetchedAt }
///       Popularity for the track and followers + popularity for its primary artist,
///       shown next to the song. Spotify's API has no monthly listeners or play counts;
///       these are the public figures it does publish.
///
/// The Spotify credentials live here and only here (client-credentials flow, catalog
/// reads, no user sign-in). Set them with
///   wrangler secret put SPOTIFY_CLIENT_ID
///   wrangler secret put SPOTIFY_CLIENT_SECRET
/// and leave them unset to disable these routes entirely (they 404, and the app stops
/// asking after the first 404).
///
/// Caching, all in D1:
///   spotify_isrc_matches   ISRC -> track, kept 30 days (a "no match" is remembered too,
///                          so an unreleased song doesn't hit Spotify on every import).
///   spotify_stats          per track, served while under a day old; the nightly cron
///                          re-fetches every row somebody looked at in the last 30 days,
///                          so numbers on posts people open stay fresh without a request
///                          per view.

import { Env, json, errorResponse, nowSeconds, checkAllRateLimits, clientIP } from "./util";

// MARK: - Shapes

export interface TrackMatch {
    trackID: string;
    url: string;
    name: string;
    artistID: string | null;
    artistName: string | null;
    albumName: string | null;
}

export interface StatsPayload {
    track: { id: string; name: string; url: string; popularity: number };
    artist: { id: string; name: string; url: string; followers: number; popularity: number };
    /// Unix seconds when these were last fetched from Spotify.
    fetchedAt: number;
}

/// The parts of Spotify's track object this module reads.
export interface SpotifyTrack {
    id: string;
    name: string;
    popularity?: number;
    external_urls?: { spotify?: string };
    external_ids?: { isrc?: string };
    artists?: { id: string; name: string; external_urls?: { spotify?: string } }[];
    album?: { name?: string };
}

export interface SpotifyArtist {
    id: string;
    name: string;
    popularity?: number;
    followers?: { total?: number };
    external_urls?: { spotify?: string };
}

interface StatsRow {
    track_id: string;
    track_name: string;
    track_url: string;
    track_popularity: number;
    artist_id: string;
    artist_name: string;
    artist_url: string;
    artist_followers: number;
    artist_popularity: number;
    updated_at: number;
    last_requested_at: number;
}

const STATS_FRESH_SECONDS = 24 * 60 * 60;
/// The cron refreshes anything older than this that was requested recently, so a row
/// is never served stale by the request path during the day.
const STATS_REFRESH_AFTER_SECONDS = 20 * 60 * 60;
const STATS_INTEREST_WINDOW_SECONDS = 30 * 24 * 60 * 60;
const ISRC_MATCH_TTL_SECONDS = 30 * 24 * 60 * 60;
const CRON_BATCH = 50;

// MARK: - Pure helpers (unit-tested)

/// An ISRC is 12 characters: 2-letter country, 3 registrant, 2 year, 5 designation.
/// Accepts the hyphenated display form and lowercase.
export function normalizeISRC(raw: string | null | undefined): string | null {
    if (!raw) return null;
    const isrc = raw.replace(/[^A-Za-z0-9]/g, "").toUpperCase();
    return /^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$/.test(isrc) ? isrc : null;
}

/// Spotify IDs are 22 base-62 characters.
export function isSpotifyID(raw: string | null | undefined): raw is string {
    return !!raw && /^[A-Za-z0-9]{22}$/.test(raw);
}

/// Search results for `isrc:` can include re-releases and other regions' copies. Prefer
/// a track whose own ISRC is the one asked for, then the most popular.
export function pickBestMatch(tracks: SpotifyTrack[], isrc: string): SpotifyTrack | null {
    if (tracks.length === 0) return null;
    const exact = tracks.filter((t) => (t.external_ids?.isrc ?? "").toUpperCase() === isrc);
    const pool = exact.length > 0 ? exact : tracks;
    return pool.slice().sort((a, b) => (b.popularity ?? 0) - (a.popularity ?? 0))[0] ?? null;
}

export function shapeMatch(track: SpotifyTrack): TrackMatch {
    const artist = track.artists?.[0];
    return {
        trackID: track.id,
        url: track.external_urls?.spotify ?? `https://open.spotify.com/track/${track.id}`,
        name: track.name,
        artistID: artist?.id ?? null,
        artistName: artist?.name ?? null,
        albumName: track.album?.name ?? null,
    };
}

export function shapeStats(track: SpotifyTrack, artist: SpotifyArtist, fetchedAt: number): StatsPayload {
    return {
        track: {
            id: track.id,
            name: track.name,
            url: track.external_urls?.spotify ?? `https://open.spotify.com/track/${track.id}`,
            popularity: track.popularity ?? 0,
        },
        artist: {
            id: artist.id,
            name: artist.name,
            url: artist.external_urls?.spotify ?? `https://open.spotify.com/artist/${artist.id}`,
            followers: artist.followers?.total ?? 0,
            popularity: artist.popularity ?? 0,
        },
        fetchedAt,
    };
}

function rowToPayload(row: StatsRow): StatsPayload {
    return {
        track: { id: row.track_id, name: row.track_name, url: row.track_url, popularity: row.track_popularity },
        artist: {
            id: row.artist_id,
            name: row.artist_name,
            url: row.artist_url,
            followers: row.artist_followers,
            popularity: row.artist_popularity,
        },
        fetchedAt: row.updated_at,
    };
}

// MARK: - Configuration

export function spotifyConfigured(env: Env): boolean {
    return !!env.SPOTIFY_CLIENT_ID && !!env.SPOTIFY_CLIENT_SECRET;
}

// MARK: - Spotify API

class SpotifyUpstreamError extends Error {
    constructor(
        public readonly status: number,
        message: string,
    ) {
        super(message);
    }
}

/// Client-credentials token, cached in the isolate until shortly before it expires.
let tokenCache: { token: string; expiresAt: number } | null = null;

async function accessToken(env: Env, force = false): Promise<string> {
    const now = nowSeconds();
    if (!force && tokenCache && tokenCache.expiresAt > now + 30) return tokenCache.token;

    const basic = btoa(`${env.SPOTIFY_CLIENT_ID}:${env.SPOTIFY_CLIENT_SECRET}`);
    const response = await fetch("https://accounts.spotify.com/api/token", {
        method: "POST",
        headers: {
            authorization: `Basic ${basic}`,
            "content-type": "application/x-www-form-urlencoded",
        },
        body: "grant_type=client_credentials",
    });
    if (!response.ok) {
        throw new SpotifyUpstreamError(response.status, `token request failed: ${response.status}`);
    }
    const payload = (await response.json()) as { access_token: string; expires_in: number };
    tokenCache = { token: payload.access_token, expiresAt: now + (payload.expires_in ?? 3600) };
    return tokenCache.token;
}

/// GET from api.spotify.com. Null for a 404 (no such track/artist); throws for
/// anything else, after one retry with a fresh token on a 401.
async function spotifyGET<T>(env: Env, path: string, retried = false): Promise<T | null> {
    const token = await accessToken(env, retried);
    const response = await fetch(`https://api.spotify.com/v1${path}`, {
        headers: { authorization: `Bearer ${token}` },
    });
    if (response.status === 404) return null;
    if (response.status === 401 && !retried) return spotifyGET<T>(env, path, true);
    if (!response.ok) {
        throw new SpotifyUpstreamError(response.status, `spotify ${path} -> ${response.status}`);
    }
    return (await response.json()) as T;
}

async function fetchStats(env: Env, trackID: string): Promise<StatsPayload | null> {
    const track = await spotifyGET<SpotifyTrack>(env, `/tracks/${encodeURIComponent(trackID)}`);
    if (!track) return null;
    const artistID = track.artists?.[0]?.id;
    if (!artistID) return null;
    const artist = await spotifyGET<SpotifyArtist>(env, `/artists/${encodeURIComponent(artistID)}`);
    if (!artist) return null;
    return shapeStats(track, artist, nowSeconds());
}

async function storeStats(env: Env, stats: StatsPayload, lastRequestedAt: number | null): Promise<void> {
    const now = nowSeconds();
    await env.DB.prepare(
        `INSERT INTO spotify_stats (track_id, track_name, track_url, track_popularity,
                                    artist_id, artist_name, artist_url, artist_followers, artist_popularity,
                                    updated_at, last_requested_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
         ON CONFLICT(track_id) DO UPDATE SET
            track_name = excluded.track_name, track_url = excluded.track_url,
            track_popularity = excluded.track_popularity,
            artist_id = excluded.artist_id, artist_name = excluded.artist_name, artist_url = excluded.artist_url,
            artist_followers = excluded.artist_followers, artist_popularity = excluded.artist_popularity,
            updated_at = excluded.updated_at,
            last_requested_at = MAX(spotify_stats.last_requested_at, excluded.last_requested_at)`,
    )
        .bind(
            stats.track.id,
            stats.track.name,
            stats.track.url,
            stats.track.popularity,
            stats.artist.id,
            stats.artist.name,
            stats.artist.url,
            stats.artist.followers,
            stats.artist.popularity,
            stats.fetchedAt,
            lastRequestedAt ?? now,
        )
        .run();
}

// MARK: - Routes

export async function handleSpotify(request: Request, env: Env, url: URL): Promise<Response> {
    if (request.method !== "GET") return errorResponse("not_found", "Unknown endpoint.", 404);
    if (!spotifyConfigured(env)) {
        return errorResponse("not_configured", "Spotify lookups aren't set up on the server yet.", 404);
    }

    const limited = await checkAllRateLimits(env, [
        { dimension: "spotify_ip", value: clientIP(request), limit: 60, windowSeconds: 60 },
    ]);
    if (limited) return errorResponse("rate_limited", "Too many lookups. Try again in a minute.", 429);

    try {
        switch (url.pathname) {
            case "/v1/music/spotify/lookup":
                return await handleLookup(url, env);
            case "/v1/music/spotify/stats":
                return await handleStats(url, env);
            default:
                return errorResponse("not_found", "Unknown endpoint.", 404);
        }
    } catch (error) {
        if (error instanceof SpotifyUpstreamError) {
            console.error("spotify upstream", error.status, error.message);
            const status = error.status === 429 ? 429 : 502;
            return errorResponse("spotify_unavailable", "Spotify isn't answering right now. Try again later.", status);
        }
        throw error;
    }
}

async function handleLookup(url: URL, env: Env): Promise<Response> {
    const isrc = normalizeISRC(url.searchParams.get("isrc"));
    if (!isrc) return errorResponse("bad_request", "That isn't a valid ISRC.", 400);
    const now = nowSeconds();

    const cached = await env.DB.prepare(`SELECT match_json, updated_at FROM spotify_isrc_matches WHERE isrc = ?`)
        .bind(isrc)
        .first<{ match_json: string | null; updated_at: number }>();
    if (cached && cached.updated_at > now - ISRC_MATCH_TTL_SECONDS) {
        return json({ match: cached.match_json ? (JSON.parse(cached.match_json) as TrackMatch) : null });
    }

    const result = await spotifyGET<{ tracks?: { items?: SpotifyTrack[] } }>(
        env,
        `/search?q=${encodeURIComponent(`isrc:${isrc}`)}&type=track&limit=10`,
    );
    const best = pickBestMatch(result?.tracks?.items ?? [], isrc);
    const match = best ? shapeMatch(best) : null;

    await env.DB.prepare(
        `INSERT INTO spotify_isrc_matches (isrc, match_json, updated_at) VALUES (?1, ?2, ?3)
         ON CONFLICT(isrc) DO UPDATE SET match_json = excluded.match_json, updated_at = excluded.updated_at`,
    )
        .bind(isrc, match ? JSON.stringify(match) : null, now)
        .run();

    return json({ match });
}

async function handleStats(url: URL, env: Env): Promise<Response> {
    const trackID = url.searchParams.get("track");
    if (!isSpotifyID(trackID)) return errorResponse("bad_request", "That isn't a Spotify track ID.", 400);
    const now = nowSeconds();

    const row = await env.DB.prepare(`SELECT * FROM spotify_stats WHERE track_id = ?`).bind(trackID).first<StatsRow>();
    if (row && row.updated_at > now - STATS_FRESH_SECONDS) {
        // Note the interest so the nightly refresh keeps this one current.
        await env.DB.prepare(`UPDATE spotify_stats SET last_requested_at = ?1 WHERE track_id = ?2`).bind(now, trackID).run();
        return json(rowToPayload(row));
    }

    try {
        const fresh = await fetchStats(env, trackID);
        if (!fresh) return errorResponse("not_found", "Spotify has no track with that ID.", 404);
        await storeStats(env, fresh, now);
        return json(fresh);
    } catch (error) {
        // Spotify down or rate-limiting: yesterday's numbers beat none.
        if (row && error instanceof SpotifyUpstreamError) {
            console.error("spotify stats: serving stale row", trackID, error.status);
            return json(rowToPayload(row));
        }
        throw error;
    }
}

// MARK: - Nightly refresh

/// Re-fetches the figures for every track somebody looked at in the last 30 days, so a
/// post that's opened during the day shows numbers at most a day old without waiting on
/// Spotify. Stops at the first upstream failure; the next night picks up the rest.
export async function refreshSpotifyStats(env: Env): Promise<void> {
    if (!spotifyConfigured(env)) return;
    const now = nowSeconds();
    const { results } = await env.DB.prepare(
        `SELECT track_id, last_requested_at FROM spotify_stats
         WHERE last_requested_at > ?1 AND updated_at < ?2
         ORDER BY last_requested_at DESC LIMIT ?3`,
    )
        .bind(now - STATS_INTEREST_WINDOW_SECONDS, now - STATS_REFRESH_AFTER_SECONDS, CRON_BATCH)
        .all<{ track_id: string; last_requested_at: number }>();

    let refreshed = 0;
    for (const row of results ?? []) {
        try {
            const fresh = await fetchStats(env, row.track_id);
            if (fresh) {
                await storeStats(env, fresh, row.last_requested_at);
                refreshed += 1;
            } else {
                // The track vanished from Spotify; forget it rather than retrying nightly.
                await env.DB.prepare(`DELETE FROM spotify_stats WHERE track_id = ?`).bind(row.track_id).run();
            }
        } catch (error) {
            console.error("spotify refresh stopped", row.track_id, error);
            break;
        }
    }
    console.log(`spotify refresh: ${refreshed}/${results?.length ?? 0} rows`);

    // Expired ISRC matches are re-fetched on demand; drop them so the table can't grow forever.
    await env.DB.prepare(`DELETE FROM spotify_isrc_matches WHERE updated_at < ?`).bind(now - ISRC_MATCH_TTL_SECONDS).run();
}
