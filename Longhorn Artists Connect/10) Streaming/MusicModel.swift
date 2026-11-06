//
//  MusicModel.swift
//  Longhorn Artists Connect
//
//  The audio playback engine for music submissions, plus the submission actions
//  (like/collect/delete/update) that MusicDetailView drives. Lives here beside
//  VideoPlayer.swift so both playback engines sit together; it is a player view
//  model, not a data model (the CloudKit record types are in MediaModels.swift).
//

import Foundation
import AVKit
import SwiftUI
import Combine

class MusicModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isAudioPlaying = false
    @Published var currentTime: Double = 0
    /// Track length in seconds, or 0 while still unknown (a streamed track doesn't know
    /// its own length until the first bytes land). Never NaN — see `progress`.
    @Published var duration: Double = 0
    /// True while the player has been asked to play but is still filling its buffer.
    /// Streaming spends its first moments here, so the controls show a spinner instead
    /// of looking like a dead play button.
    @Published var isBuffering = false
    /// Set if the stream itself fails, so the UI can say so rather than sit silent.
    @Published var playbackError: String?
    @Published var isLoading = true
    @Published var contentLoaded = false

    /// Playback progress as 0...1. Always finite and in range, so it's safe to multiply
    /// into a frame width — a NaN/out-of-range value here breaks the whole layout.
    var progress: Double {
        guard duration > 0, currentTime.isFinite else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    // MARK: - Private Properties
    private var audioPlayer: AVPlayer?
    private var timeObserver: Any?
    /// The URL the current player was built for. A repeat `setupAudioPlayer` call (the
    /// controls re-appearing) reuses that player instead of stacking a second one behind it.
    private var currentURL: URL?
    /// The player the periodic observer was registered on. A time-observer token must be
    /// removed from the *same* player it was added to; removing it from a newer player
    /// throws. Weak, so a player that's already gone is simply skipped.
    private weak var observedPlayer: AVPlayer?
    /// Block-based notification observers are only removable by their token —
    /// `removeObserver(self, name:)` does not unregister them.
    private var endOfTrackObserver: NSObjectProtocol?
    private var playerStatusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    /// True while the user is dragging the scrubber, so the periodic time observer
    /// doesn't fight the drag by writing stale positions back over it.
    private var isScrubbing = false
    /// Turns playback time into moderator-analytics play/engaged events. Kept across
    /// EP/Album track changes, so a whole-record listen counts once.
    private var engagement = PlaybackEngagementTracker()

    /// Called when a track plays to its end. EP/Album cards use it to advance to the next
    /// song; when nil, the track simply rewinds to the start.
    var onTrackFinished: (() -> Void)?
    
    // MARK: - Dependencies
    let submission: Submission
    let store: SubmissionStore_3_2
    
    // MARK: - Initialization
    init(submission: Submission, store: SubmissionStore_3_2 = .shared) {
        self.submission = submission
        self.store = store
    }
    
    // MARK: - Permissions
    
    /// Check if the current user can edit or delete this submission
    var canEditOrDelete: Bool {
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        let isUserCreator = !currentUser.isEmpty && currentUser == submission.submittedBy
        
        let isModeratorMode = UserDefaults.standard.bool(forKey: "isModeratorMode")
        let canUseModerator = isModeratorMode && ModeratorAccess.isModerator

        return isUserCreator || canUseModerator
    }

    /// Check if moderator info should be shown
    var shouldShowModeratorInfo: Bool {
        guard UserDefaults.standard.bool(forKey: "isModeratorMode") else { return false }
        return ModeratorAccess.isModerator
    }
    
    // MARK: - Audio Player Management

    /// Builds the asset for a playback URL, stating the container type outright for
    /// remote streams.
    ///
    /// A streamed track's `Content-Type` comes from the CDN, which derives it from the
    /// filename in the signed URL — and AVFoundation trusts that header over the actual
    /// bytes. A mismatch (or a generic `application/octet-stream`) fails outright with
    /// "Cannot Open" (-11828) rather than playing. Overriding the MIME from the URL's own
    /// extension removes the dependency on the server getting the header right. The
    /// override is applied only when AVFoundation lists the type as supported, so a
    /// container we guessed wrong about falls back to normal sniffing instead of failing.
    /// Local files are left alone — those are read from the file itself.
    ///
    /// Shared with the feed's audio autoplay (`FeedVideoPreloader`) so a track that
    /// streams fine in the detail view also streams fine inline.
    static func playbackAsset(for url: URL) -> AVURLAsset {
        guard
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let mimeType = audioMIMEType(forExtension: url.pathExtension),
            AVURLAsset.audiovisualMIMETypes().contains(mimeType)
        else { return AVURLAsset(url: url) }
        return AVURLAsset(url: url, options: [AVURLAssetOverrideMIMETypeKey: mimeType])
    }

    /// MIME type for an audio container extension, covering the formats the app accepts
    /// for upload. Nil for anything unrecognized.
    private static func audioMIMEType(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "m4a", "m4b", "mp4", "aac": return "audio/mp4"
        case "mp3":                      return "audio/mpeg"
        case "wav", "wave":              return "audio/wav"
        case "aif", "aiff", "aifc":      return "audio/aiff"
        case "caf":                      return "audio/x-caf"
        case "flac":                     return "audio/flac"
        default:                         return nil
        }
    }
    
    /// Setup audio player with the provided URL. When `autoPlay` is true (the default),
    /// playback begins immediately so opening a music post starts the track.
    ///
    /// Safe to call repeatedly: the same URL reuses the existing player. Building a second
    /// player for a track that's already loaded left the first one playing underneath and
    /// stranded its time observer, which then crashed on teardown.
    ///
    /// `knownDuration` is the length synced with the record, used to draw an accurate
    /// scrubber before the stream reports its own duration.
    func setupAudioPlayer(url: URL, autoPlay: Bool = true, knownDuration: Double? = nil) {
        if let existing = audioPlayer, currentURL == url {
            if autoPlay, existing.timeControlStatus == .paused { existing.play() }
            return
        }
        // A different track: tear the old player down first so a token is never left
        // pointing at a player that's been replaced.
        cleanupAudioPlayer()

        // Route to playback so audio is audible even when the ringer switch is silenced.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(asset: Self.playbackAsset(for: url))
        let player = AVPlayer(playerItem: item)
        // Buffer most of the track ahead of the playhead so a stream doesn't
        // break up mid-song when throughput dips.
        StreamPlaybackBuffer.tuneForAudio(player)
        audioPlayer = player
        currentURL = url
        playbackError = nil
        currentTime = 0
        isScrubbing = false
        // Seed from the synced length so the total-time label and scrubber are usable
        // immediately; the asset's own duration overwrites it once loaded.
        duration = (knownDuration?.isFinite == true && (knownDuration ?? 0) > 0) ? (knownDuration ?? 0) : 0

        // Monitor playback time. A streaming player reports NaN/indefinite times before
        // the first bytes arrive — those must never reach the progress bar.
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        observedPlayer = player
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, !self.isScrubbing else { return }
            let seconds = time.seconds
            guard seconds.isFinite, seconds >= 0 else { return }
            self.currentTime = seconds
            // Moderator analytics: count real listens, not just the auto-started load.
            let crossed = self.engagement.update(time: seconds, duration: self.duration)
            if !crossed.isEmpty {
                let submission = self.submission
                MainActor.assumeIsolated {
                    crossed.forEach { PostAnalytics.shared.record($0, for: submission) }
                }
            }
        }

        // Mirror the player's real state rather than assuming `play()` took effect. A
        // streamed track sits in `waitingToPlayAtSpecifiedRate` while it buffers, so
        // blind-toggling a local flag is what left the button stuck out of sync.
        playerStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                // "Playing" from the button's point of view means playback was requested —
                // buffering included — so the icon doesn't flicker back to play mid-stall.
                self.isAudioPlaying = status != .paused
                self.isBuffering = status == .waitingToPlayAtSpecifiedRate
            }
        }

        // Surface a failed stream instead of leaving a silent, dead play button.
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Playback failed"
            Task { @MainActor [weak self] in
                self?.playbackError = message
                self?.isBuffering = false
            }
            print("🎵 ❌ Audio stream failed: \(message)")
        }

        // Read the duration off the player's own asset. Loading a separate AVURLAsset
        // here opened a second connection to the same CDN URL just to re-read headers.
        Task { @MainActor in
            do {
                let loaded = try await item.asset.load(.duration).seconds
                if loaded.isFinite, loaded > 0 {
                    self.duration = loaded
                } else {
                    print("🎵 Audio asset reported no usable duration (indefinite stream)")
                }
            } catch {
                print("🎵 ❌ Audio asset failed to load duration: \(error)")
            }
        }

        // Start playing right away so tapping into a track auto-plays it.
        if autoPlay { player.play() }

        // Listen for playback end. Held as a token — a block-based observer added this
        // way is not removed by `removeObserver(self, name:)`, so the old code leaked one
        // per setup and stale observers kept resetting the live player mid-track.
        endOfTrackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if let onTrackFinished = self.onTrackFinished {
                onTrackFinished()
            } else {
                self.audioPlayer?.seek(to: .zero)
                self.currentTime = 0
            }
        }
    }
    
    /// Toggle play/pause state
    func togglePlayPause() {
        guard let player = audioPlayer else { return }
        // Restart from the top if the track already ran to the end.
        if duration > 0, currentTime >= duration - 0.05 {
            player.seek(to: .zero)
            currentTime = 0
        }
        if player.timeControlStatus == .paused {
            player.play()
        } else {
            player.pause()
        }
        // `isAudioPlaying` follows `timeControlStatus` via KVO — don't second-guess it here.
    }

    /// Previews a scrub position without seeking. Called continuously while dragging:
    /// issuing a real seek per drag update cancels the stream's in-flight range requests
    /// and stalls playback, so the actual seek waits for `endScrubbing(at:)`.
    func scrub(to time: Double) {
        guard duration > 0, time.isFinite else { return }
        isScrubbing = true
        currentTime = min(max(time, 0), duration)
    }

    /// Commits a scrub: one accurate seek, and the time observer resumes only once it lands.
    func endScrubbing(at time: Double) {
        guard let player = audioPlayer, duration > 0, time.isFinite else {
            isScrubbing = false
            return
        }
        let target = min(max(time, 0), duration)
        currentTime = target
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.isScrubbing = false }
        }
    }

    /// Seek to a specific time in the audio, clamped to the track.
    func seek(to time: Double) {
        guard let player = audioPlayer, duration > 0, time.isFinite else { return }
        let target = min(max(time, 0), duration)
        currentTime = target
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }
    
    /// Clean up audio player resources
    func cleanupAudioPlayer() {
        removeObservers()
        audioPlayer?.pause()
        audioPlayer?.replaceCurrentItem(with: nil)
        audioPlayer = nil
        currentURL = nil
        isAudioPlaying = false
        isBuffering = false
        isScrubbing = false
        currentTime = 0
    }

    /// Unregisters everything attached to the current player. Kept separate from
    /// `cleanupAudioPlayer` so `deinit` can run it without touching published state.
    private func removeObservers() {
        if let observer = timeObserver {
            observedPlayer?.removeTimeObserver(observer)
            timeObserver = nil // a double-remove of the same token crashes
        }
        observedPlayer = nil
        if let endOfTrackObserver {
            NotificationCenter.default.removeObserver(endOfTrackObserver)
            self.endOfTrackObserver = nil
        }
        playerStatusObservation?.invalidate()
        playerStatusObservation = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
    }

    deinit {
        // Only unregister here: deallocation can happen off the main thread, and
        // mutating published state from there fires SwiftUI updates off-main.
        removeObservers()
        audioPlayer?.pause()
    }
    
    // MARK: - Data Formatting
    
    /// Format time in MM:SS format. Guards against the non-finite values a streaming
    /// player reports before it's ready — `Int(Double.nan)` is a hard trap.
    func formatTime(_ time: Double) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    
    /// Consolidate crew members who have multiple roles
    func consolidatedCrew(_ crew: [OrderedEntry]) -> [(name: String, roles: [String])] {
        var grouped: [String: [String]] = [:]
        var order: [String] = []
        
        for entry in crew {
            if grouped[entry.name] == nil {
                order.append(entry.name)
                grouped[entry.name] = []
            }
            grouped[entry.name]?.append(entry.role)
        }
        
        return order.map { name in
            (name: name, roles: grouped[name] ?? [])
        }
    }
    
    // MARK: - User Interactions
    
    /// Toggle like status for this submission
    func toggleLike() {
        store.toggleLike(for: submission)
    }
    
    /// Check if this submission is liked
    func isLiked() -> Bool {
        store.isLiked(submission)
    }
    
    /// Check if this submission is in any collection
    func isInAnyCollection() -> Bool {
        store.isInAnyCollection(submission)
    }
    
    /// Delete this submission
    func delete() {
        store.delete(submission)
    }
    
    /// Update this submission
    func update(_ updated: Submission) {
        store.update(updated)
    }
    
    /// Show portfolio or invite for a user
    func showPortfolioOrInvite(for name: String) {
        // TODO: Check if user exists in the system
        // For now, show an alert with invite option
        let alert = UIAlertController(
            title: "Invite \(name) to Nexus",
            message: "Would you like to invite \(name) to join Nexus?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Invite", style: .default) { _ in
            // TODO: Send invitation
            print("Inviting \(name) to Nexus")
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    // MARK: - Loading State
    
    /// Simulate loading with delay
    func simulateLoading(delay: TimeInterval = 0.3) async {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await MainActor.run {
            isLoading = false
            contentLoaded = true
        }
    }
    
    // MARK: - Color Utilities
    
    /// Generate a consistent tint color based on title hash
    var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(submission.title.hashValue)
        return colors[hash % colors.count]
    }
}
