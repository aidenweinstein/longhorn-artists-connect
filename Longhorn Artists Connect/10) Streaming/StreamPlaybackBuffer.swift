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

    /// How much media must already be loaded ahead of the playhead before a
    /// full video player starts (or resumes after a stall) **when the network is
    /// not clearly outpacing playback**. Starting on a thin buffer is what produces
    /// the stutter a second into playback; waiting for this much means a brief dip
    /// in throughput is covered by data already here. On a fast connection the
    /// gate releases much sooner — see `minimumStartAheadSeconds`.
    static let videoStartAheadSeconds: TimeInterval = 10

    /// Read-ahead for the home feed's inline previews. Smaller than a full player
    /// because several previews may be warm at once.
    static let previewSeconds: TimeInterval = 12

    /// How much must be loaded ahead before a feed preview begins playing (on a
    /// slow connection). A preview that hiccups once costs little — it loops and
    /// the thumbnail is right behind it — so this is far lower than the detail
    /// player's gate and autoplay lands quickly.
    static let previewStartAheadSeconds: TimeInterval = 3

    /// The smallest cushion any player starts on, used when the stream is being
    /// loaded faster than it plays (`fastFillRatio`). If the network delivers 1.5 s
    /// of video per second, the buffer only grows during playback, so waiting for
    /// 10 s of it would be pure delay.
    static let minimumStartAheadSeconds: TimeInterval = 2

    /// Seconds of media loaded per wall-clock second above which the network is
    /// treated as outpacing playback. Measured over `fillRateWindow`, so a single
    /// burst doesn't count.
    static let fastFillRatio: Double = 1.5

    /// How long a fill-rate measurement must span before it's trusted.
    static let fillRateWindow: TimeInterval = 1.0

    /// Upper bound on how long `waitUntilBuffered` holds out for the deep buffer
    /// before settling for AVFoundation's own "likely to keep up" estimate. Keeps
    /// a player from waiting forever if the pipeline never fills past a point.
    static let maximumBufferWait: TimeInterval = 25

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

    // MARK: - Buffer gating

    /// Seconds of media loaded contiguously ahead of the item's playhead.
    static func secondsBufferedAhead(_ item: AVPlayerItem) -> TimeInterval {
        let now = item.currentTime().seconds
        guard now.isFinite else { return 0 }
        var best: TimeInterval = 0
        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            let start = range.start.seconds
            let end = range.end.seconds
            // A range that begins at or just before the playhead counts; a small
            // tolerance covers keyframe alignment after a seek.
            guard start.isFinite, end.isFinite, start <= now + 0.5, end > now else { continue }
            best = max(best, end - now)
        }
        return best
    }

    /// Suspends until `item` has enough media loaded past its playhead to start
    /// without stuttering, then returns `true`. "Enough" depends on how fast the
    /// stream is arriving:
    ///
    ///   - If the measured fill rate over the last `fillRateWindow` is at least
    ///     `fastFillRatio` (media loading faster than it plays), the buffer can only
    ///     grow during playback, so `minimumStartAheadSeconds` is enough.
    ///   - Otherwise the full `secondsAhead` cushion is required, so a dip in
    ///     throughput is absorbed by what's already loaded.
    ///
    /// Also returns `true` as soon as the whole remainder of the file is loaded or
    /// AVFoundation reports the buffer full, and falls back to the player's own
    /// keep-up estimate once `maximumBufferWait` elapses.
    ///
    /// Returns `false` if the item failed or the calling task was cancelled, in
    /// which case the caller should not start playback.
    @MainActor
    static func waitUntilBuffered(_ item: AVPlayerItem, secondsAhead: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(maximumBufferWait)
        // Recent (wall-clock, buffered-end position) samples for the fill-rate measure.
        // The buffered end is `currentTime + ahead`, so it tracks how far the download
        // has reached whether or not the player is moving.
        var samples: [(at: Date, bufferedEnd: TimeInterval)] = []
        while !Task.isCancelled {
            switch item.status {
            case .failed:
                return false
            case .readyToPlay:
                if item.isPlaybackBufferFull { return true }
                let now = Date()
                let position = item.currentTime().seconds
                let duration = item.duration.seconds
                let remaining = duration.isFinite && position.isFinite
                    ? max(0, duration - position)
                    : TimeInterval.infinity
                let ahead = secondsBufferedAhead(item)

                // Never demand more than what's left of the file.
                if ahead + 0.25 >= min(secondsAhead, remaining) { return true }

                // Fast network: start on the small cushion as soon as the stream has
                // proven, over a full window, that it's arriving faster than it plays.
                if position.isFinite {
                    samples.append((now, position + ahead))
                    samples.removeAll { now.timeIntervalSince($0.at) > fillRateWindow + 0.25 }
                    if let first = samples.first, let last = samples.last {
                        let span = last.at.timeIntervalSince(first.at)
                        if span >= fillRateWindow * 0.9 {
                            let fillRate = (last.bufferedEnd - first.bufferedEnd) / span
                            if fillRate >= fastFillRatio,
                               ahead + 0.25 >= min(minimumStartAheadSeconds, remaining) {
                                return true
                            }
                        }
                    }
                }

                if now >= deadline, item.isPlaybackLikelyToKeepUp { return true }
            default:
                break
            }
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return false
            }
        }
        return false
    }
}
