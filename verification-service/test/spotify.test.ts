import { test } from "node:test";
import assert from "node:assert/strict";
import { normalizeISRC, isSpotifyID, pickBestMatch, shapeMatch, shapeStats, SpotifyTrack } from "../src/spotify";

test("ISRCs normalise from display form and reject junk", () => {
    assert.equal(normalizeISRC("US-RC1-76-07839"), "USRC17607839");
    assert.equal(normalizeISRC("usrc17607839"), "USRC17607839");
    assert.equal(normalizeISRC("GBAYE0601498"), "GBAYE0601498");
    assert.equal(normalizeISRC("USRC1760783"), null); // 11 chars
    assert.equal(normalizeISRC("1234567890AB"), null); // no country code
    assert.equal(normalizeISRC(""), null);
    assert.equal(normalizeISRC(null), null);
});

test("Spotify IDs are 22 base-62 characters", () => {
    assert.equal(isSpotifyID("4uLU6hMCjMI75M1A2tKUQC"), true);
    assert.equal(isSpotifyID("4uLU6hMCjMI75M1A2tKUQ"), false);
    assert.equal(isSpotifyID("4uLU6hMCjMI75M1A2tKUQC?si=x"), false);
    assert.equal(isSpotifyID(null), false);
});

const tracks: SpotifyTrack[] = [
    { id: "a".repeat(22), name: "Song (Remaster)", popularity: 70, external_ids: { isrc: "USXXX9900001" } },
    { id: "b".repeat(22), name: "Song", popularity: 40, external_ids: { isrc: "USXXX0000001" }, artists: [{ id: "c".repeat(22), name: "Band" }], album: { name: "LP" } },
    { id: "d".repeat(22), name: "Song", popularity: 55, external_ids: { isrc: "usxxx0000001" } },
];

test("exact ISRC matches win over more popular near-misses, most popular exact first", () => {
    const best = pickBestMatch(tracks, "USXXX0000001");
    assert.equal(best?.id, "d".repeat(22));
});

test("with no exact match the most popular result is used; empty stays null", () => {
    assert.equal(pickBestMatch(tracks, "GBZZZ1111111")?.id, "a".repeat(22));
    assert.equal(pickBestMatch([], "GBZZZ1111111"), null);
});

test("shapes fall back to canonical open.spotify.com links", () => {
    const match = shapeMatch(tracks[1]);
    assert.deepEqual(match, {
        trackID: "b".repeat(22),
        url: `https://open.spotify.com/track/${"b".repeat(22)}`,
        name: "Song",
        artistID: "c".repeat(22),
        artistName: "Band",
        albumName: "LP",
    });
    const stats = shapeStats(tracks[1], { id: "c".repeat(22), name: "Band", followers: { total: 1234 }, popularity: 31 }, 1700000000);
    assert.equal(stats.artist.followers, 1234);
    assert.equal(stats.artist.url, `https://open.spotify.com/artist/${"c".repeat(22)}`);
    assert.equal(stats.track.popularity, 40);
    assert.equal(stats.fetchedAt, 1700000000);
});
