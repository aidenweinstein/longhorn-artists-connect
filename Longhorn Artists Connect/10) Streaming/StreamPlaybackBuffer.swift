//
//  StreamPlaybackBuffer.swift
//  Longhorn Artists Connect
//
//  Read-ahead tuning for media streamed straight off the CloudKit CDN.
//

import AVFoundation

/// Buffer tuning applied to every streaming player in the app.
///
/// Streamed posts are progressive-download files (a single signed CDN URL), not
/// HLS, so when throughput dips AVFoundation has no lower-bitrate variant to
/// step down to — its only defense is how far ahead it has already read. Left at
/// the default (`preferredForwardBufferDuration == 0`, i.e. "automatic") that
/// read-ahead is only a few seconds, which is plenty for a short reel but not for
/// a long, high-bitrate film: the buffer drains faster than the CDN refills it,
/// so playback halts for a moment every few seconds for the whole post.
///
/// Asking for a much deeper buffer keeps a large window of media in flight, so a
/// dip in throughput is absorbed by what's already loaded instead of becoming a
/// visible stop.
enum StreamPlaybackBuffer {
    /// Read-ahead for video. High-bitrate content, so this balances stall
    /// resistance against the memory the buffered window occupies — 30s of a
    /// heavy 4K upload is already a sizable chunk of data held in memory.
    static let videoSeconds: TimeInterval = 30

    /// Read-ahead for audio. A track is a fraction of a video's bitrate, so
    /// buffering most of a song ahead of the playhead costs very little.
    static let audioSeconds: TimeInterval = 120

    /// Tunes a video player (and its current item) for stall-free streaming.
    static func tuneForVideo(_ player: AVPlayer) {
        tune(player, forwardBufferDuration: videoSeconds)
    }

    /// Tunes an audio player (and its current item) for stall-free streaming.
    static func tuneForAudio(_ player: AVPlayer) {
        tune(player, forwardBufferDuration: audioSeconds)
    }

    private static func tune(_ player: AVPlayer, forwardBufferDuration: TimeInterval) {
        // Hold playback until the player estimates it can play through, rather
        // than starting on a thin buffer and stalling a second later. This is
        // the default, but it is the half of the behavior that the deeper buffer
        // below depends on, so it is stated outright.
        player.automaticallyWaitsToMinimizeStalling = true
        guard let item = player.currentItem else { return }
        tune(item, forwardBufferDuration: forwardBufferDuration)
    }

    /// Applies the read-ahead to an item directly, for callers that build the
    /// item themselves before handing it to a player.
    static func tune(_ item: AVPlayerItem, forwardBufferDuration: TimeInterval) {
        item.preferredForwardBufferDuration = forwardBufferDuration
        // No ceiling on how fast the buffer may fill (0 == unlimited). The
        // stream is one fixed-bitrate file, so capping the fetch rate can only
        // starve the buffer.
        item.preferredPeakBitRate = 0
    }
}
