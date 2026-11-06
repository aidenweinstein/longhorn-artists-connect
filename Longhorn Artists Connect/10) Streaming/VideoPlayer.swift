//
//  VideoPlayer.swift
//  Longhorn Artists Connect
//
//  The app's shared video playback stack, used by the film, reel and design
//  detail views:
//    - `VideoStreamStatus` / `VideoUnavailableView` / `VideoStreamingLoadingView`
//      the diagnostic placeholders shown in place of a player.
//    - `VideoPlayerModel` owns the AVPlayer and playback state for one submission.
//    - `CustomVideoPlayerView` is the inline player; `FullscreenVideoWindow` +
//      `FullscreenOverlay` present the rotated fullscreen presentation.
//    - `VolumeController` / `HiddenVolumeHost` / `HorizontalVolumeMeter` drive the
//      custom volume HUD.
//  Extracted from FilmCard.swift (now FilmDetailView.swift).
//

import SwiftUI
import AVKit
import Combine
import MediaPlayer

/// Why a submission's video isn't currently playing — drives the diagnostic placeholder
/// shown in place of the player, so it states exactly what's happening in production
/// instead of a blanket "Coming Soon". Shared by the film and reel detail cards.
enum VideoStreamStatus: Equatable {
    /// Nothing was ever attached — the post is genuinely awaiting its video.
    case comingSoon
    /// The record itself isn't in the CloudKit environment this build is querying. Almost
    /// always an environment mismatch: a Debug build hits the *development* environment,
    /// but the feed shows cached *production* posts, so their records aren't found here.
    case recordNotFound
    /// The record exists but carries no file in the video field, even though a video was
    /// expected (its length is synced) — i.e. the file itself is missing in CloudKit.
    case fileNonExistent
    /// The asset is present but CloudKit returned no `downloadURL` to stream from.
    case noDownloadURL
    /// A network / HTTP failure pulling the asset. `code` is the HTTP status, or a
    /// negative sentinel for a transport-level failure.
    case errorStreaming(Int)
    /// Streaming isn't configured for this build (no CloudKit Web Services API token).
    case notConfigured
    /// A file is present but has no playable video track (empty / corrupt upload).
    case unreadable

    /// The message shown on the placeholder.
    var label: String {
        switch self {
        case .comingSoon:            return "Coming Soon"
        case .recordNotFound:        return "Record Not Found (Wrong Env?)"
        case .fileNonExistent:       return "File Non-Existent"
        case .noDownloadURL:         return "No Streaming URL"
        case .errorStreaming(let c): return c > 0 ? "Error Streaming (\(c))" : "Error Streaming"
        case .notConfigured:         return "Streaming Unavailable"
        case .unreadable:            return "Video File Unreadable"
        }
    }

    /// Icon that matches the message's tone.
    var systemImage: String {
        switch self {
        case .comingSoon:      return "film.stack"
        case .recordNotFound:  return "icloud.and.arrow.down"
        case .fileNonExistent: return "questionmark.folder"
        case .noDownloadURL:   return "link.badge.plus"
        case .errorStreaming:  return "exclamationmark.icloud"
        case .notConfigured:   return "icloud.slash"
        case .unreadable:      return "exclamationmark.triangle"
        }
    }
}

/// Diagnostic placeholder shown in place of a video player when there's nothing to play.
/// States exactly why (submitted without a video, file missing in CloudKit, a streaming
/// error, …) rather than always saying "Coming Soon". Shared by film and reel cards.
struct VideoUnavailableView: View {
    let status: VideoStreamStatus
    let tintColor: Color
    /// Compact diagnostic of what the server handed this device (environment, HTTP status,
    /// field keys, …). Shown small under the label so a device-only failure can be read
    /// off the screen without a console. Tap to copy. Only shown in moderator mode.
    var detail: String? = nil
    /// The post's thumbnail, shown darkened behind the message. Falls back to the tint
    /// gradient when the post has no thumbnail.
    var thumbnailData: Data? = nil

    @AppStorage("isModeratorMode") private var isModeratorMode: Bool = false

    var body: some View {
        ZStack {
            if let thumbnailData, let thumbnail = UIImage(data: thumbnailData) {
                // Tinted thumbnail: fill the 16:9 frame, then darken so the white text
                // stays legible over any artwork.
                Color.clear
                    .overlay(
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    )
                    .clipped()
                    .overlay(Color.black.opacity(0.55))
            } else {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
            VStack(spacing: 10) {
                Image(systemName: status.systemImage)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(status.label)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                // Raw diagnostics (env=…, field=…) are for moderators only.
                if let detail, isModeratorMode, ModeratorAccess.isModerator {
                    Text(detail)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 12)
                        .onTapGesture { UIPasteboard.general.string = detail }
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0/9.0, contentMode: .fit)
        .clipped()
    }
}

/// The spinner shown while a video is still being pulled from CloudKit. Labeled so the
/// in-progress fetch is distinguishable from the failure states above.
struct VideoStreamingLoadingView: View {
    let tintColor: Color
    /// The shape the player will take once the stream resolves, so the box doesn't
    /// jump when the video appears. Defaults to 16:9 when the shape isn't known.
    var aspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        ZStack {
            // Plain black backdrop (not the per-post tint) so the loading state reads as a
            // video that's about to play rather than a random colored placeholder.
            Rectangle()
                .fill(Color.black)
                .frame(maxWidth: .infinity)
                .aspectRatio(aspectRatio, contentMode: .fit)
            VStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                Text("Streaming Loading...")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

// MARK: - Shared Video Player Model

/// Owns the `AVPlayer` and playback state for one submission's video. A single model
/// is shared between the inline player and the rotated fullscreen presentation, so
/// playback stays continuous across the transition and there is exactly one periodic
/// time observer (registering a second one on the same player, then tearing either
/// down, was the source of the old "observer still registered" crashes).
final class VideoPlayerModel: ObservableObject {
    let player: AVPlayer
    let submissionID: UUID
    private let submission: Submission

    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 1

    private var timeObserver: Any?
    private var stallObserver: NSObjectProtocol?
    private var startTask: Task<Void, Never>?
    private var stallRecovery: Task<Void, Never>?
    /// Set once the owning view is gone, so a start still waiting on the buffer
    /// can't begin playing into a view that no longer exists.
    private var isTornDown = false
    private var engagement = PlaybackEngagementTracker()

    init(url: URL, submission: Submission) {
        // Prefer whatever the home feed already warmed for this stream: a player
        // item that's been buffering since the card was hovered (instant start),
        // else an asset whose container metadata is already loaded. The feed only
        // builds these on the main thread, which is where SwiftUI constructs us.
        var warmItem: AVPlayerItem?
        var warmAsset: AVURLAsset?
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                warmItem = FeedVideoPreloader.shared.takeWarmItem(for: url)
                if warmItem == nil { warmAsset = FeedVideoPreloader.shared.warmedAsset(for: url) }
            }
        }
        if let warmItem {
            self.player = AVPlayer(playerItem: warmItem)
        } else if let warmAsset {
            self.player = AVPlayer(playerItem: AVPlayerItem(asset: warmAsset))
        } else {
            self.player = AVPlayer(url: url)
        }
        self.submissionID = submission.id
        self.submission = submission

        // Read far enough ahead that a dip in CDN throughput mid-film is covered
        // by media already buffered, instead of stopping playback for a moment.
        StreamPlaybackBuffer.tuneForVideo(player)

        // If the stream does stall, hold the frame and refill a deep buffer before
        // resuming rather than letting it limp along in fits and starts.
        if let item = player.currentItem {
            stallObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.playbackStalledNotification, object: item, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.recoverFromStall() }
            }
        }

        // Drives the scrubber. The observer fires on the main queue, so updating the
        // published state directly here is safe.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds
            // Moderator analytics: count real plays, not just the auto-started load.
            let crossed = self.engagement.update(time: time.seconds, duration: self.duration)
            if !crossed.isEmpty {
                let submission = self.submission
                MainActor.assumeIsolated {
                    crossed.forEach { PostAnalytics.shared.record($0, for: submission) }
                }
            }
        }

        startTask = Task { @MainActor in await self.restoreAndPlay() }
    }

    @MainActor
    private func restoreAndPlay() async {
        if let loaded = try? await player.currentItem?.asset.load(.duration) {
            duration = max(loaded.seconds, 1)
            if let saved = SubmissionStore_3_2.shared.getPlaybackPosition(for: submissionID),
               saved > 0, saved < duration - 1 {
                await player.seek(to: CMTime(seconds: saved, preferredTimescale: 600))
                currentTime = saved
            }
        }
        // Don't start on a thin buffer: wait until enough is loaded ahead of the
        // playhead to ride out a dip in throughput. A slightly later start beats a
        // stutter a second in.
        if let item = player.currentItem {
            _ = await StreamPlaybackBuffer.waitUntilBuffered(
                item, secondsAhead: StreamPlaybackBuffer.videoStartAheadSeconds
            )
        }
        guard !isTornDown, !Task.isCancelled else { return }
        player.play()
        isPlaying = true
    }

    /// Pauses on the current frame and resumes only once a deep buffer is back.
    @MainActor
    private func recoverFromStall() {
        guard isPlaying, !isTornDown, stallRecovery == nil, let item = player.currentItem else { return }
        player.pause()
        stallRecovery = Task { @MainActor [weak self] in
            defer { self?.stallRecovery = nil }
            let ready = await StreamPlaybackBuffer.waitUntilBuffered(
                item, secondsAhead: StreamPlaybackBuffer.videoStartAheadSeconds
            )
            // `isPlaying` is the user's intent; if they paused meanwhile, stay paused.
            guard ready, !Task.isCancelled, let self, self.isPlaying, !self.isTornDown else { return }
            self.player.play()
        }
    }

    func togglePlay() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        // A manual pause/play supersedes any stall recovery in progress.
        stallRecovery?.cancel()
        stallRecovery = nil
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        currentTime = seconds
    }

    /// Persists the playback position and stops playback. Called when the detail view
    /// is dismissed — NOT when merely entering fullscreen, which shares this player.
    @MainActor
    func teardown() {
        if currentTime > 0, currentTime < duration - 1 {
            SubmissionStore_3_2.shared.savePlaybackPosition(for: submissionID, position: currentTime)
        }
        isTornDown = true
        startTask?.cancel()
        stallRecovery?.cancel()
        player.pause()
        removeObserver()
    }

    private func removeObserver() {
        if let token = timeObserver {
            player.removeTimeObserver(token)
            timeObserver = nil
        }
        if let stallObserver {
            NotificationCenter.default.removeObserver(stallObserver)
            self.stallObserver = nil
        }
    }

    deinit {
        removeObserver()
    }
}

/// Corner radius of the inline video card. The fullscreen overlay rounds back to
/// this exact value as it collapses, so the two match with no corner pop.
private let inlineVideoCornerRadius: CGFloat = 36

/// Formats a playback time (seconds) as `m:ss`.
private func formatVideoTime(_ time: Double) -> String {
    guard time.isFinite, time >= 0 else { return "0:00" }
    let total = Int(time)
    return String(format: "%d:%02d", total / 60, total % 60)
}

// MARK: - AVPlayerLayer Wrapper

/// A lightweight `AVPlayerLayer`-backed view, used by the fullscreen player so the
/// video can be sized with `.resizeAspect` inside the rotated container.
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

// MARK: - Cropped Playback

/// Plays `player` showing only the post's `crop` region. The crop is applied at display
/// time (the file is never re-encoded): the full frame is scaled up so the crop area fills
/// the largest rect of the crop's shape that fits here, offset so the crop sits in it, and
/// everything outside is clipped away. Any leftover space is letterboxed in black.
struct CroppedPlayerSurface: View {
    let player: AVPlayer
    let crop: VideoCrop
    /// The video's upright width ÷ height if already known (from `VideoAspectCache`),
    /// so the crop is placed correctly on the first frame rather than after the
    /// track loads. Falls back to 16:9 when nil.
    var initialAspect: CGFloat? = nil

    /// The video's upright width ÷ height, read from its track once it loads.
    @State private var videoAspect: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let rect = crop.rect
            let frameAspect = videoAspect ?? initialAspect ?? (16.0 / 9.0)
            let cropAspect = frameAspect * rect.width / rect.height
            let visible = Self.fit(aspect: cropAspect, in: proxy.size)
            let full = CGSize(width: visible.width / rect.width, height: visible.height / rect.height)

            PlayerLayerView(player: player)
                .frame(width: full.width, height: full.height)
                .offset(x: -rect.minX * full.width, y: -rect.minY * full.height)
                .frame(width: visible.width, height: visible.height, alignment: .topLeading)
                .clipped()
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .background(Color.black)
        .task { await loadVideoAspect() }
    }

    /// Largest size with the given width ÷ height that fits inside `container`.
    private static func fit(aspect: CGFloat, in container: CGSize) -> CGSize {
        guard aspect > 0, container.width > 0, container.height > 0 else { return container }
        if container.width / container.height > aspect {
            return CGSize(width: container.height * aspect, height: container.height)
        }
        return CGSize(width: container.width, height: container.width / aspect)
    }

    private func loadVideoAspect() async {
        guard let asset = player.currentItem?.asset,
              let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return }
        let upright = size.applying(transform)
        guard upright.height != 0 else { return }
        videoAspect = abs(upright.width / upright.height)
    }
}

// MARK: - Volume Control (custom, replaces the system HUD in fullscreen)

/// Tracks and drives the device output volume while the fullscreen player is open.
///
/// Hardware volume presses are detected by KVO-observing `AVAudioSession.outputVolume`.
/// The custom meter sets the volume through a hidden `MPVolumeView`'s embedded slider —
/// the only supported way to set system volume programmatically. While that hidden
/// `MPVolumeView` sits in the visible window (see `HiddenVolumeHost`), iOS suppresses
/// its own volume HUD, so ours is the only volume UI shown in fullscreen.
@MainActor
final class VolumeController: ObservableObject {
    /// Current output volume, 0...1.
    @Published var volume: Float = AVAudioSession.sharedInstance().outputVolume
    /// Increments whenever a hardware button changes the volume, so the UI can flash the meter.
    @Published var hardwareChangeTick = 0

    private var observation: NSKeyValueObservation?
    /// The hidden `MPVolumeView`, whose embedded slider is the only supported way to set
    /// system output volume. We hold the view (not the slider) and locate the slider
    /// fresh on each change: `MPVolumeView` creates the slider lazily, so a reference
    /// grabbed at setup time is often still nil when the user first drags the meter —
    /// which would silently no-op the write while the meter's fill still moved.
    fileprivate weak var volumeView: MPVolumeView?
    /// True while we're setting the volume ourselves, so the KVO echo doesn't get
    /// mistaken for a hardware-button press (which would re-flash the meter).
    private var isSelfUpdating = false

    func start() {
        try? AVAudioSession.sharedInstance().setActive(true)
        volume = AVAudioSession.sharedInstance().outputVolume
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let newValue = change.newValue else { return }
            Task { @MainActor [weak self] in
                guard let self, !self.isSelfUpdating else { return }
                self.volume = newValue
                self.hardwareChangeTick &+= 1
            }
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
    }

    /// Sets the system volume (what the video plays at). Read-only `outputVolume` can
    /// only be changed via the MPVolumeView's embedded slider.
    func setVolume(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        volume = clamped
        // Locate the slider fresh (see `volumeView`); a nil here means the hidden
        // MPVolumeView hasn't materialized its slider yet — the fill still tracks the
        // drag via `volume` above, we just can't push to system volume this frame.
        guard let slider = volumeView.flatMap({ Self.embeddedSlider(in: $0) }) else { return }
        isSelfUpdating = true
        slider.setValue(clamped, animated: false)
        slider.sendActions(for: .valueChanged)
        // Let the KVO echo from the line above land, then re-arm hardware detection.
        Task { @MainActor in self.isSelfUpdating = false }
    }

    /// Recursively finds the `MPVolumeView`'s embedded `UISlider`. It isn't always a
    /// direct subview across iOS versions, and it's the only supported way to set the
    /// system output volume programmatically.
    fileprivate static func embeddedSlider(in view: UIView) -> UISlider? {
        if let slider = view as? UISlider { return slider }
        for sub in view.subviews {
            if let found = embeddedSlider(in: sub) { return found }
        }
        return nil
    }
}

/// A near-invisible `MPVolumeView` kept in the hierarchy so iOS hides its own volume
/// HUD while fullscreen is open, and so the custom meter can drive system volume.
struct HiddenVolumeHost: UIViewRepresentable {
    let controller: VolumeController

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.alpha = 0.001   // must be in a visible window (not `.isHidden`) to suppress the HUD
        // Hold the view; the controller finds its (lazily created) slider on demand.
        controller.volumeView = view
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        controller.volumeView = uiView
    }
}

/// A horizontal, draggable volume meter (fill grows rightward), echoing the pill shape
/// of the system HUD it replaces. Laid out horizontally so it stays clear of the Dynamic
/// Island in the rotated fullscreen player. Dragging anywhere sets the value from the
/// touch's x-position.
struct HorizontalVolumeMeter: View {
    @Binding var value: Float   // 0...1

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.25))
                Rectangle().fill(.white)
                    .frame(width: CGFloat(min(max(value, 0), 1)) * geo.size.width)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let fraction = g.location.x / geo.size.width
                        value = Float(min(max(fraction, 0), 1))
                    }
            )
        }
        .clipShape(Capsule())
    }
}

// MARK: - Inline Custom Video Player

/// Styled inline video player (play/pause, scrubber, fullscreen) used by both films
/// and reels. The fullscreen button hands the shared player to `FullscreenVideoWindow`,
/// which grows the video out of this inline frame to fill the screen (rotated 90°) —
/// the app itself never leaves portrait.
struct CustomVideoPlayerView: View {
    let submission: Submission
    let videoURL: URL
    let thumbnailData: Data?
    let tintColor: Color

    @StateObject private var model: VideoPlayerModel
    @State private var showControls = false
    /// The inline video's on-screen rectangle (global coords), so the fullscreen
    /// overlay can grow out of / shrink back into exactly this frame.
    @State private var inlineFrame: CGRect = .zero
    @State private var controlsWorkItem: DispatchWorkItem?
    /// Tracks whether the phone was last held sideways, so tilt-to-fullscreen fires only
    /// on the portrait→landscape transition (not repeatedly while held sideways).
    @State private var wasLandscape = false

    init(submission: Submission, videoURL: URL, thumbnailData: Data? = nil, tintColor: Color = .orange) {
        self.submission = submission
        self.videoURL = videoURL
        self.thumbnailData = thumbnailData
        self.tintColor = tintColor
        _model = StateObject(wrappedValue: VideoPlayerModel(url: videoURL, submission: submission))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScreenshotProtectedView {
                if let crop = VideoCrop(submission.videoCrop) {
                    // Show only the cropped region of the (streamed) video.
                    CroppedPlayerSurface(
                        player: model.player,
                        crop: crop,
                        initialAspect: VideoAspectCache.shared.naturalAspect(for: submission.id)
                    )
                } else {
                    VideoPlayer(player: model.player)
                        .disabled(true)             // hide native controls; we draw our own
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleControls() }

            if showControls {
                controlsBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Round only the top corners so the video meets the info section flush below.
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: inlineVideoCornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: inlineVideoCornerRadius,
            style: .continuous
        ))
        // Continuously track this player's on-screen frame for the grow transition.
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { inlineFrame = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { _, newValue in
                        inlineFrame = newValue
                    }
            }
        )
        // Tilt-to-fullscreen: watch the phone's physical orientation (accelerometer-
        // driven) and grow into fullscreen the moment it's turned sideways.
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            wasLandscape = UIDevice.current.orientation.isLandscape
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            model.teardown()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            handleOrientationChange()
        }
    }

    /// Auto-presents fullscreen when the phone is first turned sideways. Only fires on
    /// the transition into landscape, so manually shrinking out of fullscreen while still
    /// holding the phone sideways doesn't immediately re-trigger it.
    private func handleOrientationChange() {
        switch UIDevice.current.orientation {
        case .landscapeLeft, .landscapeRight:
            guard !wasLandscape else { return }
            wasLandscape = true
            guard !FullscreenVideoWindow.shared.isPresented else { return }
            FullscreenVideoWindow.shared.present(model: model, startFrame: inlineFrame, submission: submission)
        case .portrait, .portraitUpsideDown:
            wasLandscape = false
        default:
            break   // faceUp / faceDown / unknown: leave the sideways state unchanged
        }
    }

    private var controlsBar: some View {
        HStack(spacing: 10) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
            }

            Slider(
                value: Binding(get: { model.currentTime }, set: { model.currentTime = $0 }),
                in: 0...max(model.duration, 1)
            ) { editing in
                if !editing { model.seek(to: model.currentTime) }
            }
            .tint(.white)

            Button {
                FullscreenVideoWindow.shared.present(model: model, startFrame: inlineFrame, submission: submission)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // Just the controls over the video — no black box behind them. A soft shadow
        // keeps the white buttons and scrubber legible over bright footage.
        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
    }

    private func toggleControls() {
        withAnimation { showControls.toggle() }
        controlsWorkItem?.cancel()
        guard showControls else { return }
        let item = DispatchWorkItem { withAnimation { showControls = false } }
        controlsWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }
}

// MARK: - Fullscreen Window (grows from the inline frame)

/// Hosts the fullscreen video overlay in its own transparent `UIWindow`. Using a
/// separate window (instead of a `fullScreenCover`) means there's no opaque system
/// backdrop to flash black — the video grows out of the inline player over the live
/// app, and shrinks back into it on the way out.
@MainActor
final class FullscreenVideoWindow {
    static let shared = FullscreenVideoWindow()
    private var window: UIWindow?

    /// Whether the fullscreen overlay is currently showing. Used by the inline player's
    /// tilt-to-fullscreen logic to avoid presenting a second time.
    var isPresented: Bool { window != nil }

    func present(model: VideoPlayerModel, startFrame: CGRect, submission: Submission) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else { return }

        let overlay = FullscreenOverlay(model: model, startFrame: startFrame, submission: submission) { [weak self] in
            self?.dismiss()
        }
        let host = UIHostingController(rootView: overlay)
        host.view.backgroundColor = .clear

        let win = UIWindow(windowScene: scene)
        win.rootViewController = host
        win.backgroundColor = .clear
        win.windowLevel = .normal + 1
        win.isHidden = false
        window = win
    }

    /// Tears down the window. Called by the overlay once its collapse animation ends.
    func dismiss() {
        window?.isHidden = true
        window = nil
    }
}

// MARK: - Fullscreen Overlay

/// The fullscreen video. It animates a single `expanded` state between the inline
/// rectangle (upright, matching the small player) and the full screen (rotated 90°
/// to fill without leaving portrait). The rotation direction follows how the user
/// physically turns the phone (`UIDevice.orientation`); the interface orientation is
/// never changed.
struct FullscreenOverlay: View {
    @ObservedObject var model: VideoPlayerModel
    let startFrame: CGRect
    let submission: Submission
    let onClose: () -> Void

    @State private var expanded = false
    @State private var rotation: Angle = .degrees(90)
    // Start hidden so the playback controls don't automatically pop up when the video
    // grows into fullscreen — the user taps to reveal them.
    @State private var showControls = false
    @State private var controlsWorkItem: DispatchWorkItem?

    // Custom volume: replaces the system volume HUD while fullscreen (see VolumeController).
    @StateObject private var volume = VolumeController()
    @State private var showVolumeSlider = false

    private let anim: Animation = .spring(response: 0.42, dampingFraction: 0.86)
    private let animDuration: TimeInterval = 0.5

    var body: some View {
        GeometryReader { geo in
            // True physical screen size (add safe-area insets back — see the inline
            // sizing note; a hosting controller's GeometryReader can report the
            // reduced size).
            let full = CGSize(
                width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            )
            // Expanded content is laid out in landscape dims; a 90° rotation fills the
            // portrait screen. Collapsed content matches the inline rectangle upright.
            let landscape = CGSize(width: full.height, height: full.width)
            let size = expanded ? landscape : startFrame.size
            let center = expanded
                ? CGPoint(x: full.width / 2 - geo.safeAreaInsets.leading,
                          y: full.height / 2 - geo.safeAreaInsets.top)
                : CGPoint(x: startFrame.midX - geo.safeAreaInsets.leading,
                          y: startFrame.midY - geo.safeAreaInsets.top)

            ZStack {
                Color.black
                    .ignoresSafeArea()
                    .opacity(expanded ? 1 : 0)

                videoContent(size: size)
                    .frame(width: size.width, height: size.height)
                    .rotationEffect(expanded ? rotation : .degrees(0))
                    .position(center)

                // Invisible; only here to suppress the system volume HUD and to let the
                // custom meter set system volume.
                HiddenVolumeHost(controller: volume)
                    .frame(width: 60, height: 40)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        // Hide the status bar (clock, Wi-Fi/cellular, battery around the Dynamic
        // Island) and home indicator while expanded.
        .statusBarHidden(expanded)
        .persistentSystemOverlays(expanded ? .hidden : .automatic)
        // Defer the system screen-edge gestures so a control near an edge takes the
        // first tap instead of Control Center / Home.
        .defersSystemGestures(on: .all)
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            updateRotation(animated: false)
            volume.start()
            withAnimation(anim) { expanded = true }
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            volume.stop()
            controlsWorkItem?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            handleOrientationChange()
        }
        // A hardware volume press (system HUD is suppressed) reveals the controls and
        // flashes the custom meter so there's still visible feedback.
        .onChange(of: volume.hardwareChangeTick) { _, _ in
            guard expanded else { return }
            flashVolumeMeter()
        }
    }

    private func videoContent(size: CGSize) -> some View {
        ZStack {
            ScreenshotProtectedView {
                if let crop = VideoCrop(submission.videoCrop) {
                    CroppedPlayerSurface(
                        player: model.player,
                        crop: crop,
                        initialAspect: VideoAspectCache.shared.naturalAspect(for: submission.id)
                    )
                } else {
                    PlayerLayerView(player: model.player)
                }
            }

            // Full-area tap target toggles the controls.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }

            if expanded && showControls {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        // Square while fullscreen; rounds back to the inline card's top-corner radius
        // as it collapses (bottom stays square to match the inline), so there's no
        // corner "pop" handing back to the inline player. Animates because `expanded`
        // toggles inside `withAnimation`.
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: expanded ? 0 : inlineVideoCornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: expanded ? 0 : inlineVideoCornerRadius,
            style: .continuous
        ))
    }

    private var controlsOverlay: some View {
        ZStack {
            // Grey, minimal scrim with rounded corners. Tapping it hides the controls.
            Color(white: 0.14).opacity(0.55)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }

            VStack(spacing: 0) {
                // Top: movie title and a single-line credits line.
                VStack(alignment: .leading, spacing: 4) {
                    Text(submission.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    creditsLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 24)

                Spacer()

                // Bottom: elapsed time — progress — remaining time.
                HStack(spacing: 12) {
                    Text(formatVideoTime(model.currentTime))
                        .font(.system(size: 12, weight: .regular).monospacedDigit())
                        .foregroundStyle(.white)

                    Slider(
                        value: Binding(get: { model.currentTime }, set: { model.currentTime = $0 }),
                        in: 0...max(model.duration, 1)
                    ) { editing in
                        if !editing { model.seek(to: model.currentTime) }
                    }
                    .tint(.white)

                    Text(formatVideoTime(max(model.duration - model.currentTime, 0)))
                        .font(.system(size: 12, weight: .regular).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }

            // Center play/pause button. A quick symbol replace keeps the icon swap snappy.
            Button {
                withAnimation(.easeInOut(duration: 0.1)) { model.togglePlay() }
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 88, height: 88)
                    .contentShape(Rectangle())
            }

            // Exit-fullscreen button in the bottom-right corner, sitting just above
            // the scrubber row.
            Button { dismiss() } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 20)
            .padding(.bottom, 56)

            // Custom volume control in the bottom-left corner, mirroring the exit
            // button on the right. Tapping toggles the vertical meter; the hardware
            // buttons and the meter both drive the (system) volume.
            volumeControl
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 20)
                .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Volume control

    private var volumeControl: some View {
        let binding = Binding<Float>(
            get: { volume.volume },
            set: { volume.setVolume($0) }
        )
        return HStack(spacing: 12) {
            Button {
                withAnimation(controlsFade) { showVolumeSlider.toggle() }
                controlsWorkItem?.cancel()
                if showVolumeSlider { scheduleControlsAutoHide() }
            } label: {
                Image(systemName: volumeIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            if showVolumeSlider {
                HorizontalVolumeMeter(value: binding)
                    .frame(width: 140, height: 36)
                    .transition(.opacity)
            }
        }
    }

    /// Speaker glyph that reflects the current volume level.
    private var volumeIcon: String {
        switch volume.volume {
        case ..<0.001: return "speaker.slash.fill"
        case ..<0.33:  return "speaker.fill"
        case ..<0.66:  return "speaker.wave.1.fill"
        default:       return "speaker.wave.2.fill"
        }
    }

    /// Reveals the controls and the volume meter (e.g. after a hardware volume press),
    /// then re-arms the auto-hide.
    private func flashVolumeMeter() {
        controlsWorkItem?.cancel()
        withAnimation(controlsFade) {
            showControls = true
            showVolumeSlider = true
        }
        scheduleControlsAutoHide()
    }

    // MARK: - Credits line

    /// A single-line credits line under the title. Shows as many actors (up to three)
    /// as fit the width, dropping actors before it would ever wrap or truncate.
    private var creditsLine: some View {
        ViewThatFits(in: .horizontal) {
            creditsText(maxActors: 3)
            creditsText(maxActors: 2)
            creditsText(maxActors: 1)
            creditsText(maxActors: 0)
        }
    }

    private func creditsText(maxActors: Int) -> some View {
        Text(creditsString(maxActors: maxActors))
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
    }

    /// Builds the credits sentence, e.g.
    /// "Directed & Edited by …, Produced by …, Starring A, B, and C".
    /// Roles held by the same person are consolidated ("Directed & Edited by Aiden
    /// Weinstein" rather than two separate segments). Only roles that exist are included;
    /// `maxActors` caps the "Starring" list.
    private func creditsString(maxActors: Int) -> String {
        // Ordered role → past-tense verb mapping for the crew credits we surface.
        // The Director of Photography (a.k.a. Cinematographer) reads as "Shot by".
        // Order here is the order the segments appear: Directed, Shot, Edited, …
        let roleVerbs: [(roles: [String], verb: String)] = [
            (["Director"],                                   "Directed"),
            (["Director of Photography", "Cinematographer"], "Shot"),
            (["Editor"],                                     "Edited"),
            (["Producer"],                                   "Produced"),
            (["Composer"],                                   "Composed")
        ]

        // Group verbs by person, preserving the order people first appear.
        var personVerbs: [(name: String, verbs: [String])] = []
        for (roles, verb) in roleVerbs {
            guard let name = crewName(roles) else { continue }
            if let idx = personVerbs.firstIndex(where: { $0.name == name }) {
                personVerbs[idx].verbs.append(verb)
            } else {
                personVerbs.append((name: name, verbs: [verb]))
            }
        }

        var parts = personVerbs.map { "\(joinVerbs($0.verbs)) by \($0.name)" }

        let actors = submission.orderedCast
            .prefix(maxActors)
            .map(\.name)
            .filter { !$0.isEmpty }
        if !actors.isEmpty {
            parts.append("Starring \(joinNames(Array(actors)))")
        }
        return joinSegments(parts)
    }

    /// Joins one person's role verbs, e.g. "Directed", "Directed & Edited", or
    /// "Directed, Produced & Edited".
    private func joinVerbs(_ verbs: [String]) -> String {
        switch verbs.count {
        case 0:  return ""
        case 1:  return verbs[0]
        case 2:  return "\(verbs[0]) & \(verbs[1])"
        default: return "\(verbs.dropLast().joined(separator: ", ")) & \(verbs.last!)"
        }
    }

    /// First crew member whose role matches any of `roles` (case-insensitively), if
    /// named. Multiple aliases let one credit cover synonymous role titles (e.g.
    /// "Director of Photography" and "Cinematographer" both read as "Shot by").
    private func crewName(_ roles: [String]) -> String? {
        let name = submission.orderedCrew.first { entry in
            roles.contains { entry.role.caseInsensitiveCompare($0) == .orderedSame }
        }?.name
        return (name?.isEmpty == false) ? name : nil
    }

    /// Joins names as "A", "A and B", or "A, B, and C".
    private func joinNames(_ names: [String]) -> String {
        switch names.count {
        case 0:  return ""
        case 1:  return names[0]
        case 2:  return "\(names[0]) and \(names[1])"
        default: return "\(names.dropLast().joined(separator: ", ")), and \(names.last!)"
        }
    }

    /// Joins credit segments with commas only — no "and" before the final segment
    /// (e.g. "Directed & Edited by …, Produced by …, Starring …").
    private func joinSegments(_ parts: [String]) -> String {
        parts.joined(separator: ", ")
    }

    /// Plays the shrink-back animation, then removes the window.
    private func dismiss() {
        controlsWorkItem?.cancel()
        withAnimation(anim) { expanded = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + animDuration) { onClose() }
    }

    /// Responds to the phone being physically turned: landscape re-aligns the video's
    /// rotation, while turning back upright to portrait collapses fullscreen back into
    /// the inline player.
    private func handleOrientationChange() {
        switch UIDevice.current.orientation {
        case .landscapeLeft, .landscapeRight:
            updateRotation(animated: true)
        case .portrait:
            if expanded { dismiss() }
        default:
            break   // portraitUpsideDown / faceUp / faceDown / unknown: do nothing
        }
    }

    /// Maps the phone's physical orientation to the content rotation that keeps the
    /// video upright. The interface stays portrait — this only rotates content.
    private func updateRotation(animated: Bool) {
        let target: Angle
        switch UIDevice.current.orientation {
        case .landscapeLeft:  target = .degrees(90)    // phone turned counter-clockwise
        case .landscapeRight: target = .degrees(-90)   // phone turned clockwise
        default:              return                    // portrait / flat: keep current
        }
        // Only animate while expanded; collapsed rotation is always 0 (upright).
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) { rotation = target }
        } else {
            rotation = target
        }
    }

    /// Duration of the controls' fade in/out. Kept short so the overlay just fades
    /// away quickly instead of lingering.
    private var controlsFade: Animation { .easeInOut(duration: 0.15) }

    private func toggleControls() {
        guard expanded else { return }
        controlsWorkItem?.cancel()
        if showControls {
            hideControls()
        } else {
            withAnimation(controlsFade) { showControls = true }
            scheduleControlsAutoHide()
        }
    }

    /// Hides the controls INSTANTLY (no fade). Fading them out left the scrim — which
    /// covers the letterbox bars beside the video — briefly visible as a translucent
    /// ghost over/behind the video; a clean cut removes that entirely.
    private func hideControls() {
        controlsWorkItem?.cancel()
        showControls = false
        showVolumeSlider = false
    }

    private func scheduleControlsAutoHide() {
        let item = DispatchWorkItem { hideControls() }
        controlsWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }
}
