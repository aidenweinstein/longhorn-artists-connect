//
//  FeedVideoPreloader.swift
//  Longhorn Artists Connect
//
//  Preloading and inline autoplay previews (with sound) for film, reel, and music
//  posts in the home feed.
//    - `FeedVideoPreloader` resolves a post's stream and warms it up ahead of
//      time (container metadata on every device; a paused, buffering player on
//      hover-capable devices) so a preview or detail view starts fast.
//    - `HoverPreviewController` drives one card's inline preview, started either
//      by a 1.5 s pointer hover or by the card being scrolled mostly into view
//      for 1 s (YouTube-style autoplay). It gates the first frame on buffer
//      depth, loops on end, and pauses-and-refills on stall so the preview
//      never stutters. Only one card autoplays at a time.
//    - `FeedPreviewSurface` renders the preview over the card's thumbnail.
//

import SwiftUI
import AVKit
import Observation
import Network

// MARK: - Network conditions

/// Tracks whether the current network path is *constrained* — the user has Low Data
/// Mode on for this Wi-Fi or cellular connection. Autoplaying feed video is exactly
/// the kind of background traffic that setting asks apps to skip.
@MainActor
final class NetworkConditions {
    static let shared = NetworkConditions()

    /// True while the active path is in Low Data Mode.
    private(set) var isConstrained = false

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let constrained = path.isConstrained
            Task { @MainActor in
                NetworkConditions.shared.isConstrained = constrained
            }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkConditions.monitor", qos: .utility))
    }
}

// MARK: - Preloader

/// Warms up film/reel streams for the home feed so playback starts quickly.
///
/// Two levels of warmth, chosen per device:
///   - **Metadata** (every device): resolve the CDN URL and load the asset's
///     container metadata. This is the slow part of opening a stream (a CloudKit
///     lookup plus the `moov` atom fetch) and costs only a few small requests.
///   - **Player** (iPad / Mac, where a pointer can hover): additionally attach the
///     asset to a paused `AVPlayer`, which buffers `StreamPlaybackBuffer.previewSeconds`
///     of media in the background. A hover preview — or the detail view, which
///     takes the buffered item over — can then start almost immediately.
///
/// Only a handful of entries are kept (most recently used), and a card drops its
/// entry when it scrolls off screen, so memory and bandwidth stay bounded.
@MainActor
final class FeedVideoPreloader {
    static let shared = FeedVideoPreloader()

    /// One warmed stream. `player` is nil for metadata-only warmth.
    final class Entry {
        let url: URL
        let asset: AVURLAsset
        private(set) var player: AVPlayer?
        private(set) var item: AVPlayerItem?
        var lastTouched = Date()
        /// True while a hover preview is actively using the player.
        var isCheckedOut = false

        init(url: URL, asset: AVURLAsset, player: AVPlayer?, item: AVPlayerItem?) {
            self.url = url
            self.asset = asset
            self.player = player
            self.item = item
        }

        /// Hands the buffered item to a new owner and stops the warm player.
        fileprivate func detachItem() -> AVPlayerItem? {
            guard let item else { return nil }
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            self.item = nil
            self.player = nil
            return item
        }

        /// Drops the warm player. The actual teardown happens off the main thread:
        /// pausing and clearing an `AVPlayer` whose item is still loading from the
        /// network blocks the calling thread until that load is cancelled, and this
        /// runs as cards leave the screen mid-scroll (`cancelPreload`, eviction) —
        /// doing it on the main actor stalled the feed's scrolling.
        fileprivate func tearDown() {
            guard let player else {
                item = nil
                return
            }
            item = nil
            self.player = nil
            let released = player
            DispatchQueue.global(qos: .utility).async {
                released.pause()
                released.replaceCurrentItem(with: nil)
            }
        }
    }

    /// Most warm players kept at once. Each holds a buffered window of video.
    private static let maxWarmPlayers = 4
    /// Most metadata-only entries kept at once. These are cheap.
    private static let maxWarmAssets = 12

    private var entries: [UUID: Entry] = [:]
    private var warming: [UUID: Task<Entry?, Never>] = [:]

    private init() {}

    /// Whether this device has a pointer that can hover a card (iPad trackpad or
    /// mouse, Mac). Only then is it worth buffering media ahead of time; on iPhone
    /// a card can only be tapped, so just the metadata is warmed.
    static var supportsHoverPreview: Bool {
        if ProcessInfo.processInfo.isiOSAppOnMac { return true }
        switch UIDevice.current.userInterfaceIdiom {
        case .pad, .mac: return true
        default: return false
        }
    }

    /// Whether a post can be previewed/preloaded at all: a film or reel whose
    /// video isn't withheld, or a music post (its track autoplays, audibly, over
    /// the album art).
    static func isPreviewable(_ post: Submission) -> Bool {
        switch post.type {
        case .film, .reel: return !post.festivalBound
        case .music: return true
        default: return false
        }
    }

    /// Whether a post's preview is sound-only — a music track — rather than video.
    static func isAudioPreview(_ post: Submission) -> Bool {
        post.type == .music
    }

    // MARK: Public API

    /// Starts warming `post` in the background (no-op if already warm or in flight).
    func preload(_ post: Submission) {
        guard Self.isPreviewable(post) else { return }
        if let entry = entries[post.id] {
            entry.lastTouched = Date()
            return
        }
        guard warming[post.id] == nil else { return }
        _ = startWarming(post, forcePlayer: false)
    }

    /// Launches a warm-up task for `post`, replacing any in flight, and clears it
    /// from `warming` when it finishes (only if it's still the current task, so a
    /// superseded task can't knock out its replacement).
    private func startWarming(_ post: Submission, forcePlayer: Bool) -> Task<Entry?, Never> {
        warming[post.id]?.cancel()
        let task = Task { [weak self] in
            await self?.warmUp(post, forcePlayer: forcePlayer)
        }
        warming[post.id] = task
        Task { [weak self] in
            _ = await task.value
            if self?.warming[post.id] == task { self?.warming[post.id] = nil }
        }
        return task
    }

    /// Stops warming `id` and releases its warm player unless a preview is using it.
    /// Called when a card leaves the screen.
    ///
    /// A metadata-only entry is kept: it holds no buffered media, just the resolved URL
    /// and container metadata, and `maxWarmAssets` already bounds how many there are.
    /// Dropping it here meant that scrolling a card off and back on repeated its
    /// CloudKit lookup and metadata fetch every time.
    func cancelPreload(for id: UUID) {
        warming[id]?.cancel()
        warming[id] = nil
        if let entry = entries[id], !entry.isCheckedOut, entry.player != nil {
            entry.tearDown()
            entries[id] = nil
        }
    }

    /// Returns the warm, buffering player for `post` (warming it now if needed)
    /// and marks it in use. Nil when the post can't be streamed on this device.
    func checkOut(_ post: Submission) async -> Entry? {
        if let entry = entries[post.id], entry.player != nil {
            entry.isCheckedOut = true
            entry.lastTouched = Date()
            return entry
        }
        // Not warm (or only metadata-warm): warm a full player now.
        let task = startWarming(post, forcePlayer: true)
        guard let entry = await task.value, entry.player != nil else { return nil }
        entry.isCheckedOut = true
        entry.lastTouched = Date()
        return entry
    }

    /// Returns a checked-out player to the pool, rewound and paused.
    func checkIn(_ id: UUID) {
        guard let entry = entries[id] else { return }
        entry.player?.pause()
        entry.item?.seek(to: .zero, completionHandler: nil)
        entry.isCheckedOut = false
        entry.lastTouched = Date()
        evictIfNeeded()
    }

    /// The stream URL for `id` if it's already warm and the stream has proven
    /// playable — safe for a detail view to use without a fresh CloudKit lookup.
    func readyStreamURL(for id: UUID) -> URL? {
        guard let entry = entries[id] else { return nil }
        if let item = entry.item {
            return item.status == .readyToPlay ? entry.url : nil
        }
        // Metadata-only warmth: the asset loaded its tracks, so the URL is live.
        return entry.url
    }

    /// The already-buffered player item for `url`, if a warm player holds one.
    /// Ownership transfers to the caller; the warm player is released.
    func takeWarmItem(for url: URL) -> AVPlayerItem? {
        guard let (id, entry) = entries.first(where: { $0.value.url == url }),
              let item = entry.detachItem() else { return nil }
        // Rewind so the new owner starts from the top. The buffered range starts
        // at zero, so this keeps what's loaded.
        item.seek(to: .zero, completionHandler: nil)
        entries[id] = nil
        return item
    }

    /// The asset with its container metadata already loaded for `url`, if warm.
    func warmedAsset(for url: URL) -> AVURLAsset? {
        entries.values.first(where: { $0.url == url })?.asset
    }

    // MARK: Warming

    /// Resolves the stream URL and loads the asset's metadata; on hover-capable
    /// devices (or when forced) also attaches it to a paused, buffering player.
    private func warmUp(_ post: Submission, forcePlayer: Bool) async -> Entry? {
        let wantsPlayer = forcePlayer || Self.supportsHoverPreview

        // Reuse a metadata-only entry's asset when upgrading to a full player.
        let existing = entries[post.id]
        if let existing, existing.player != nil || !wantsPlayer {
            return existing
        }

        let url: URL
        let asset: AVURLAsset
        if let existing {
            url = existing.url
            asset = existing.asset
        } else {
            guard let resolved = await resolveURL(for: post) else { return nil }
            if Task.isCancelled { return nil }
            url = resolved
            let isAudio = Self.isAudioPreview(post)
            // Music streams state their container type outright (see
            // `MusicModel.playbackAsset`) so a CDN `Content-Type` mismatch can't
            // fail the track that the detail view would otherwise play fine.
            asset = isAudio ? MusicModel.playbackAsset(for: resolved) : AVURLAsset(url: resolved)
            // Loading the tracks pulls the container metadata — the expensive
            // part of opening a stream — and proves the file is actually playable.
            guard let tracks = try? await asset.loadTracks(withMediaType: isAudio ? .audio : .video),
                  !tracks.isEmpty else { return nil }
            // The track's natural size is in the metadata just fetched; remember
            // the video's shape so the detail view opens its player at the right
            // aspect ratio immediately. (Audio has no shape.)
            if !isAudio {
                let track = tracks[0]
                Task {
                    if let aspect = await VideoAspectCache.naturalAspect(of: track) {
                        VideoAspectCache.shared.store(aspect, for: post.id)
                    }
                }
            }
        }
        if Task.isCancelled { return nil }

        var player: AVPlayer?
        var item: AVPlayerItem?
        if wantsPlayer {
            let newItem = AVPlayerItem(asset: asset)
            StreamPlaybackBuffer.tune(newItem, forwardBufferDuration: StreamPlaybackBuffer.previewSeconds)
            let newPlayer = AVPlayer(playerItem: newItem)
            newPlayer.automaticallyWaitsToMinimizeStalling = true
            // Previews play with sound — a film's audio as well as a music
            // track — and loop; never end playback on the item's end.
            newPlayer.isMuted = false
            newPlayer.actionAtItemEnd = .none
            newPlayer.preventsDisplaySleepDuringVideoPlayback = false
            player = newPlayer
            item = newItem
        }

        let entry = Entry(url: url, asset: asset, player: player, item: item)
        entries[post.id] = entry
        evictIfNeeded()
        return entry
    }

    /// A local copy if the post has one, otherwise the CDN stream URL.
    private func resolveURL(for post: Submission) async -> URL? {
        let localCopy = Self.isAudioPreview(post) ? post.audioURL : post.videoURL
        if let local = localCopy, FileManager.default.fileExists(atPath: local.path) {
            return local
        }
        let (resolution, _) = await CloudKitManager.shared.streamResolutionDetailed(
            submissionID: post.id, type: post.type
        )
        if case .streaming(let url) = resolution { return url }
        return nil
    }

    /// Drops the least recently used entries beyond the caps, never one in use.
    private func evictIfNeeded() {
        let idle = entries
            .filter { !$0.value.isCheckedOut }
            .sorted { $0.value.lastTouched < $1.value.lastTouched }

        var players = entries.values.filter { $0.player != nil }.count
        var total = entries.count
        for (id, entry) in idle {
            guard players > Self.maxWarmPlayers || total > Self.maxWarmAssets else { break }
            if entry.player != nil {
                players -= 1
            } else if players > Self.maxWarmPlayers {
                // Only players are over the cap; skip metadata-only entries.
                continue
            }
            entry.tearDown()
            entries[id] = nil
            total -= 1
        }
    }
}

// MARK: - Hover preview controller

/// Drives one feed card's inline preview — hover-to-play on pointer devices, and
/// scroll-to-play (YouTube-style autoplay) everywhere.
///
/// Hovering for `hoverDelay`, or sitting mostly on screen for `autoplayDelay`,
/// starts the preview. The first frame isn't shown until
/// `StreamPlaybackBuffer.previewStartAheadSeconds` of video is buffered, and if
/// the stream stalls mid-preview it pauses on the current frame and refills to
/// the same depth before resuming — a short wait instead of a stutter.
///
/// Only one card autoplays at a time: when a card scrolls into view it claims the
/// slot and the previous autoplaying card stops, so two cards that happen to both
/// be mostly visible (two 16:9 films on a tall phone) never play at once. As you
/// scroll down, the card you just reached takes over — like YouTube's feed.
@Observable
@MainActor
final class HoverPreviewController {
    /// How long the pointer must rest on a card before its video starts.
    static let hoverDelay: Duration = .seconds(1.5)
    /// How long a card must stay mostly on screen before its video starts.
    static let autoplayDelay: Duration = .seconds(1)
    /// The fraction of the card's media that must be on screen for it to count as
    /// "scrolled to" — high enough that a card half off the top or bottom edge
    /// doesn't start playing.
    static let autoplayVisibilityThreshold: Double = 0.7

    /// What started (or is about to start) the current preview.
    private enum Trigger { case hover, scroll }

    /// The card currently holding the single autoplay slot.
    private static weak var activeAutoplay: HoverPreviewController?

    /// The player to render over the thumbnail, once it's ready to play smoothly.
    private(set) var player: AVPlayer?
    /// True from the moment the start delay elapses until the preview is playing,
    /// and again while refilling after a stall.
    private(set) var isBuffering = false

    private var post: Submission?
    private var trigger: Trigger?
    private var hoverTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    /// Whether scroll autoplay should run at all right now. Autoplaying video is
    /// skipped in Low Power Mode and in Low Data Mode (a constrained network path),
    /// the same way YouTube and Instagram back off. Hover previews and tapping a
    /// post are unaffected — those are the user asking for the video.
    static var autoplayAllowed: Bool {
        !ProcessInfo.processInfo.isLowPowerModeEnabled && !NetworkConditions.shared.isConstrained
    }

    /// Call with each `onHover` change.
    func hoverChanged(_ hovering: Bool, post: Submission) {
        guard FeedVideoPreloader.isPreviewable(post) else { return }
        if hovering {
            // Already playing or counting down from a scroll — leave it be.
            guard player == nil, trigger == nil else { return }
            begin(post, trigger: .hover, after: Self.hoverDelay)
        } else if trigger == .hover {
            // Only a hover-started preview ends when the pointer leaves; an
            // autoplaying card keeps going until it scrolls away.
            stop()
        }
    }

    /// Call with each `onScrollVisibilityChange` of the card's media, using
    /// `autoplayVisibilityThreshold`. After `autoplayDelay` of being mostly on
    /// screen the video plays inline; scrolling it back out stops it.
    func scrollVisibilityChanged(_ visible: Bool, post: Submission) {
        guard FeedVideoPreloader.isPreviewable(post) else { return }
        if visible {
            guard Self.autoplayAllowed else { return }
            // Take over the single autoplay slot from whichever card held it.
            if let previous = Self.activeAutoplay, previous !== self {
                previous.stop()
            }
            Self.activeAutoplay = self
            // A hover may already be playing this card; just mark it as the
            // autoplaying one so leaving with the pointer no longer stops it.
            if player != nil || trigger == .hover {
                trigger = .scroll
                return
            }
            guard trigger == nil else { return }
            begin(post, trigger: .scroll, after: Self.autoplayDelay)
        } else if trigger == .scroll {
            stop()
        }
    }

    /// Resumes a preview the system paused (e.g. the app went to the background
    /// mid-autoplay and came back) while the card is still on screen.
    func resumeIfNeeded() {
        guard let player, stallTask == nil, player.timeControlStatus == .paused else { return }
        player.play()
    }

    /// Starts the countdown to a preview of `post`, buffering it in the meantime.
    private func begin(_ post: Submission, trigger: Trigger, after delay: Duration) {
        hoverTask?.cancel()
        self.post = post
        self.trigger = trigger
        // Start buffering right away so the video is ready when the delay ends.
        FeedVideoPreloader.shared.preload(post)
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.start(post)
        }
    }

    /// Ends the preview and returns its player to the preload pool.
    func stop() {
        hoverTask?.cancel()
        hoverTask = nil
        stallTask?.cancel()
        stallTask = nil
        removeObservers()
        isBuffering = false
        if player != nil {
            withAnimation(.easeInOut(duration: 0.2)) { player = nil }
        }
        if let post {
            FeedVideoPreloader.shared.checkIn(post.id)
        }
        post = nil
        trigger = nil
        if Self.activeAutoplay === self { Self.activeAutoplay = nil }
    }

    private func start(_ post: Submission) async {
        isBuffering = true
        defer { isBuffering = false }

        guard let entry = await FeedVideoPreloader.shared.checkOut(post),
              let warmPlayer = entry.player, let item = entry.item else { return }
        // The hover may have ended while the stream was being resolved.
        if Task.isCancelled {
            FeedVideoPreloader.shared.checkIn(post.id)
            return
        }

        // Wait for a deep enough buffer that the preview plays through cleanly.
        let ready = await StreamPlaybackBuffer.waitUntilBuffered(
            item, secondsAhead: StreamPlaybackBuffer.previewStartAheadSeconds
        )
        guard ready, !Task.isCancelled else {
            FeedVideoPreloader.shared.checkIn(post.id)
            return
        }

        // Every preview is audible — a film's soundtrack as much as a music
        // track — so make sure the session is routed to playback; otherwise the
        // ringer switch silences it and the card appears to autoplay without a
        // sound. Done off the main thread: see `activatePlaybackAudioSession`.
        await Self.activatePlaybackAudioSession()
        guard !Task.isCancelled else {
            FeedVideoPreloader.shared.checkIn(post.id)
            return
        }

        installObservers(on: item, player: warmPlayer)
        withAnimation(.easeInOut(duration: 0.25)) { player = warmPlayer }
        warmPlayer.play()
        hoverTask = nil
    }

    /// Loop at the end; on a stall, hold the frame and refill before resuming.
    private func installObservers(on item: AVPlayerItem, player: AVPlayer) {
        removeObservers()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                item.seek(to: .zero, completionHandler: nil)
                player.play()
            }
        })
        observers.append(center.addObserver(
            forName: AVPlayerItem.playbackStalledNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recoverFromStall(item: item, player: player)
            }
        })
    }

    private func recoverFromStall(item: AVPlayerItem, player: AVPlayer) {
        guard stallTask == nil, self.player === player else { return }
        player.pause()
        isBuffering = true
        stallTask = Task { [weak self] in
            defer {
                self?.stallTask = nil
                self?.isBuffering = false
            }
            let ready = await StreamPlaybackBuffer.waitUntilBuffered(
                item, secondsAhead: StreamPlaybackBuffer.previewStartAheadSeconds
            )
            guard ready, !Task.isCancelled, let self, self.player === player else { return }
            player.play()
        }
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    /// Makes the shared audio session active for an audible preview, off the main
    /// thread.
    ///
    /// `setCategory`/`setActive` are synchronous round trips to the media server
    /// that routinely take hundreds of milliseconds (iOS logs them as an
    /// "AVAudioSession Hang Risk" when called on the main thread). Running them on
    /// the main actor froze the feed every time a music card began autoplaying
    /// mid-scroll. The category is already `.playback` from launch
    /// (`LonghornArtistsConnectApp`), so it's only re-applied if something changed
    /// it, and the mode is left alone — switching modes per card forces an audio
    /// route reconfiguration each time.
    private static func activatePlaybackAudioSession() async {
        await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playback {
                try? session.setCategory(.playback)
            }
            try? session.setActive(true)
        }.value
    }
}

// MARK: - Preview surface

/// Renders a hover preview's player over a feed card's thumbnail, honoring the
/// post's display-time crop if it has one. Screenshot-protected like the detail
/// players.
struct FeedPreviewSurface: View {
    let player: AVPlayer
    let crop: VideoCrop?

    var body: some View {
        ScreenshotProtectedView {
            if let crop {
                CroppedPlayerSurface(player: player, crop: crop)
            } else {
                PreviewPlayerLayer(player: player)
            }
        }
    }
}

/// `AVPlayerLayer` sized to fill the thumbnail frame (the thumbnail is a frame of
/// the same video, so filling matches it edge to edge).
private struct PreviewPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}
