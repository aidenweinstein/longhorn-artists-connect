//
//  FilmDetailView.swift
//  Longhorn Artists Connect
//
//  Detail view specifically for Film submissions
//

import SwiftUI
import AVKit

struct FilmDetailView: View {
    let film: Submission
    @Binding var liked: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: SubmissionStore_3_2 = .shared

    @State private var selectedPortfolioName: CreditedPerson?
    @State private var showSendMessage = false
    @State private var showDeleteConfirmation = false
    @State private var showReportSheet = false
    @State private var showEditSheet = false
    @State private var showCollectionPicker = false
    @State private var isLoading = true
    @State private var contentLoaded = false
    @State private var showFullScreenPoster = false
    
    // Icon color that adapts to light/dark mode
    private var iconColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    // Check if current user is the film creator or a moderator
    private var canEditOrDelete: Bool {
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        let isUserCreator = !currentUser.isEmpty && currentUser == film.submittedBy
        
        let isModeratorMode = UserDefaults.standard.bool(forKey: "isModeratorMode")
        let isAidenWeinstein = currentUser == "Aiden Weinstein"
        let canUseModerator = isModeratorMode && isAidenWeinstein
        
        return isUserCreator || canUseModerator
    }
    
    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(film.title.hashValue)
        return colors[hash % colors.count]
    }
    
    var body: some View {
        ZStack {
            if isLoading && !contentLoaded {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Video Player Section
                        VStack(alignment: .leading, spacing: 0) {
                            if let videoURL = film.videoURL {
                                FilmVideoPlayerView(
                                    submission: film,
                                    videoURL: videoURL
                                )
                                .aspectRatio(16.0/9.0, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .clipped()
                            } else {
                                // Fallback placeholder
                                Button {
                                    showFullScreenPoster = true
                                } label: {
                                    ZStack {
                                        Rectangle()
                                            .fill(LinearGradient(
                                                colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                            .frame(maxWidth: .infinity)
                                            .aspectRatio(16.0/9.0, contentMode: .fit)
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 60, weight: .bold))
                                            .foregroundStyle(.white.opacity(0.9))
                                    }
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                                .clipped()
                            }
                            
                            // Title, age rating, genres, and action buttons
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(film.title)
                                            .font(.system(size: 28, weight: .bold))
                                            .minimumScaleFactor(0.6)
                                            .lineLimit(2)
                                        
                                        // Age rating and genres for films
                                        HStack(spacing: 8) {
                                            if !film.ageRating.isEmpty {
                                                Text(film.ageRating)
                                                    .font(.subheadline)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(.secondary.opacity(0.2))
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                            }
                                            
                                            if !film.genres.isEmpty {
                                                Text(film.genres.joined(separator: " • "))
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true) // Allow wrapping
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // Action buttons
                                    HStack(spacing: 6) { // Reduced from 12 to 6
                                        Button {
                                            store.toggleLike(for: film)
                                        } label: {
                                            Image(systemName: store.isLiked(film) ? "heart.fill" : "heart")
                                                .font(.system(size: 20))
                                                .foregroundStyle(store.isLiked(film) ? .red : .primary)
                                                .frame(width: 32, height: 32)
                                        }
                                        
                                        Button {
                                            showCollectionPicker = true
                                        } label: {
                                            Image(systemName: store.isInAnyCollection(film) ? "bookmark.fill" : "bookmark")
                                                .font(.system(size: 20))
                                                .foregroundStyle(iconColor)
                                                .frame(width: 32, height: 32)
                                        }
                                        
                                        Button {
                                            showSendMessage = true
                                        } label: {
                                            Image(systemName: "paperplane")
                                                .font(.system(size: 20))
                                                .foregroundStyle(iconColor)
                                                .frame(width: 32, height: 32)
                                        }
                                        
                                        Button {
                                            showReportSheet = true
                                        } label: {
                                            Image(systemName: "flag")
                                                .font(.system(size: 20))
                                                .foregroundStyle(iconColor)
                                                .frame(width: 32, height: 32)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                        }
                        
                        // Film Information
                        VStack(alignment: .leading, spacing: 12) {
                            // Logline
                            if !film.logline.isEmpty {
                                Text(film.logline)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, 12)
                            }
                            
                            // Cast section
                            if !film.orderedCast.isEmpty {
                                Divider()
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Cast")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    
                                    ForEach(film.orderedCast, id: \.role) { entry in
                                        HStack(alignment: .center) {
                                            Text(entry.role)
                                                .font(.body)
                                                .foregroundStyle(.secondary)
                                            
                                            Spacer()

                                            CreditNameView(name: entry.name, selection: $selectedPortfolioName)
                                        }
                                    }
                                }
                            }
                            
                            // Crew section
                            if !film.orderedCrew.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Crew")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    
                                    ForEach(consolidatedCrew(film.orderedCrew), id: \.name) { consolidated in
                                        HStack(alignment: .top) {
                                            Text(consolidated.roles.joined(separator: ", "))
                                                .font(.body)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                            
                                            Spacer()

                                            CreditNameView(name: consolidated.name, selection: $selectedPortfolioName)
                                        }
                                    }
                                }
                            }
                            
                            // Studio info
                            if !film.studio.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Studio")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Text(film.studio)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            // Moderator info
                            if UserDefaults.standard.bool(forKey: "isModeratorMode") {
                                let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
                                let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
                                let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
                                
                                if currentUser == "Aiden Weinstein" {
                                    Text("Submitted by \(film.submittedBy)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal)
                                        .padding(.top, 16)
                                }
                            }
                            
                            // Edit and Delete buttons
                            if canEditOrDelete {
                                HStack(spacing: 12) {
                                    Button {
                                        showEditSheet = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "pencil")
                                            Text("Edit")
                                        }
                                        .font(.headline)
                                        .foregroundStyle(.orange)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.orange.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    
                                    Button {
                                        showDeleteConfirmation = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "trash")
                                            Text("Delete")
                                        }
                                        .font(.headline)
                                        .foregroundStyle(.red)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.red.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.top, 24)
                                .padding(.bottom)
                            }
                        }
                        .padding()
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    isLoading = false
                    contentLoaded = true
                }
            }
        }
        .sheet(item: $selectedPortfolioName) { person in
            PersonProfileView(name: person.name)
        }
        .sheet(isPresented: $showSendMessage) {
            SendPostMessageView(post: film)
        }
        .sheet(isPresented: $showReportSheet) {
            ReportContentView(post: film)
        }
        .sheet(isPresented: $showEditSheet) {
            FilmEditView(submission: film) { updatedSubmission in
                store.update(updatedSubmission)
            }
        }
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerView(post: film)
        }
        .fullScreenCover(isPresented: $showFullScreenPoster) {
            FullScreenPosterView(post: film, tintColor: tintColor)
        }
        .alert("Delete Film?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                store.delete(film)
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    // MARK: - Helper Functions
    
    private func consolidatedCrew(_ crew: [OrderedEntry]) -> [(name: String, roles: [String])] {
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
    
}

// MARK: - Film Video Player (native AVPlayerViewController)

/// Wraps `AVPlayerViewController` so films use Apple's native playback controls,
/// including a fullscreen button whose rotation and dismissal are handled by the
/// system — reliable even though the rest of the app is portrait-locked. Playback
/// position is restored on load and saved when the view goes away.
struct FilmVideoPlayerView: UIViewControllerRepresentable {
    let submission: Submission
    let videoURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(submissionID: submission.id)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: videoURL)
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.delegate = context.coordinator
        // Strip the "•••" more menu: no speed submenu, no Picture in Picture.
        controller.allowsPictureInPicturePlayback = false
        if #available(iOS 16.0, *) {
            controller.speeds = []
        }
        // Remove the Live Text / "Show Text" button (paused-frame analysis).
        controller.allowsVideoFrameAnalysis = false
        context.coordinator.player = player

        // Restore any saved position, then begin playback.
        let submissionID = submission.id
        Task { @MainActor in
            let store = SubmissionStore_3_2.shared
            if let durationTime = try? await player.currentItem?.asset.load(.duration) {
                let duration = durationTime.seconds
                if let saved = store.getPlaybackPosition(for: submissionID),
                   saved > 0, saved < duration - 1 {
                    await player.seek(to: CMTime(seconds: saved, preferredTimescale: 600))
                }
            }
            player.play()
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        guard let player = uiViewController.player else { return }
        let time = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        if time > 0, duration > 0, time < duration - 1 {
            SubmissionStore_3_2.shared.savePlaybackPosition(for: coordinator.submissionID, position: time)
        }
        player.pause()
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let submissionID: UUID
        var player: AVPlayer?

        init(submissionID: UUID) {
            self.submissionID = submissionID
            super.init()
        }

        // Entering fullscreen: allow and force landscape so the video fills the screen.
        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            OrientationManager.shared.allowLandscape = true
            // Lock fullscreen: block the interactive swipe-to-dismiss so the only
            // way out is the close (X) button.
            coordinator.viewController(forKey: .to)?.isModalInPresentation = true
            coordinator.animate(alongsideTransition: { _ in
                Self.requestOrientation(.landscapeRight)
            })
        }

        // Exiting fullscreen: return to portrait and re-lock orientation.
        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            coordinator.animate(alongsideTransition: nil) { _ in
                Self.requestOrientation(.portrait)
                OrientationManager.shared.allowLandscape = false
            }
        }

        private static func requestOrientation(_ orientation: UIInterfaceOrientationMask) {
            if #available(iOS 16.0, *) {
                let scene = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first { $0.activationState == .foregroundActive }
                    ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
                scene?.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
            } else {
                let value = (orientation == .portrait ? UIInterfaceOrientation.portrait : .landscapeRight).rawValue
                UIDevice.current.setValue(value, forKey: "orientation")
                UIViewController.attemptRotationToDeviceOrientation()
            }
        }
    }
}

// MARK: - Custom Video Player View

struct CustomVideoPlayerView: View {
    let submission: Submission
    let videoURL: URL
    let thumbnailData: Data?
    let tintColor: Color
    
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @State private var player: AVPlayer?
    @State private var showControls = false
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 1
    @State private var showFullScreen = false
    @State private var controlsWorkItem: DispatchWorkItem?
    @State private var timeObserverToken: Any?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Video Player
                if let player {
                    VideoPlayer(player: player)
                        .disabled(true) // Disable native controls
                        .contentShape(Rectangle()) // Make entire area tappable
                        .onTapGesture {
                            withAnimation {
                                showControls.toggle()
                            }
                            
                            // Cancel previous auto-hide
                            controlsWorkItem?.cancel()
                            
                            // Schedule auto-hide if controls are shown
                            if showControls {
                                let workItem = DispatchWorkItem {
                                    withAnimation {
                                        showControls = false
                                    }
                                }
                                controlsWorkItem = workItem
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
                            }
                        }
                } else {
                    // Thumbnail before play
                    ZStack {
                        if let thumbnailData,
                           let uiImage = UIImage(data: thumbnailData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Rectangle()
                                .fill(LinearGradient(colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        
                        ProgressView()
                            .tint(.white)
                    }
                }
                
                // Custom Controls Overlay - clipped to video bounds
                if showControls && player != nil {
                    VStack {
                        Spacer()
                        HStack(spacing: geometry.size.width > 375 ? 8 : 6) {
                            // Play/Pause Button
                            Button {
                                if isPlaying {
                                    player?.pause()
                                } else {
                                    player?.play()
                                }
                                isPlaying.toggle()
                            } label: {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                            }
                            
                            // Progress Bar
                            Slider(value: $currentTime, in: 0...duration) { editing in
                                if !editing {
                                    player?.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
                                }
                            }
                            .tint(.white)
                            
                            // Fullscreen Button
                            Button {
                                // Allow landscape *before* presenting so the very first
                                // rotation request succeeds instead of racing the scene.
                                OrientationManager.shared.allowLandscape = true
                                showFullScreen = true
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                            }
                        }
                        .padding(.horizontal, geometry.size.width > 375 ? 10 : 8)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.7))
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.width * (9.0/16.0))
        }
        .aspectRatio(16.0/9.0, contentMode: .fit)
        .clipShape(Rectangle()) // Clip everything to rectangle bounds
        .clipped() // Prevent controls from extending beyond video
        .onAppear {
            setupPlayer()
            playVideo()
        }
        .onDisappear {
            // Entering fullscreen fires onDisappear on this inline view. Don't pause
            // then — the fullscreen player shares this same AVPlayer and must keep
            // playing through the orientation change.
            guard !showFullScreen else { return }

            // Save playback position before actually leaving the detail view
            if currentTime > 0 && currentTime < duration - 1 {
                store.savePlaybackPosition(for: submission.id, position: currentTime)
            }
            player?.pause()
            controlsWorkItem?.cancel()
            // Remove the periodic time observer before the AVPlayer is deallocated;
            // leaving it registered crashes ("AVPlayer deallocated while a time
            // observer was still registered").
            if let token = timeObserverToken {
                player?.removeTimeObserver(token)
                timeObserverToken = nil
            }
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            if let player {
                FullScreenVideoPlayer(player: player, isPlaying: $isPlaying)
            }
        }
        .onChange(of: showFullScreen) { oldValue, newValue in
            // The fullscreen player shares this AVPlayer, so playback is already
            // continuous. On exit, just make sure the inline view keeps playing if
            // the video was playing when the user left fullscreen.
            if !newValue && isPlaying {
                player?.play()
            }
        }
    }
    
    private func setupPlayer() {
        guard player == nil else { return }
        player = AVPlayer(url: videoURL)
        
        // Monitor playback time (keep the token so we can remove it on teardown)
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in
            currentTime = time.seconds
        }
        
        // Get duration and restore saved position
        Task {
            if let duration = try? await player?.currentItem?.asset.load(.duration) {
                await MainActor.run {
                    self.duration = duration.seconds
                    
                    // Restore saved playback position if available
                    if let savedPosition = store.getPlaybackPosition(for: submission.id),
                       savedPosition > 0 && savedPosition < self.duration - 1 {
                        player?.seek(to: CMTime(seconds: savedPosition, preferredTimescale: 600))
                        currentTime = savedPosition
                    }
                }
            }
        }
    }
    
    private func playVideo() {
        player?.play()
        isPlaying = true
        // Don't show controls automatically - only show when user taps
    }
}

// MARK: - Full Screen Video Player

struct FullScreenVideoPlayer: View {
    let player: AVPlayer
    @Binding var isPlaying: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        FullScreenVideoPlayerWrapper(player: player, isPlaying: $isPlaying, dismiss: dismiss)
    }
}

// MARK: - Full Screen Video Player Wrapper (UIKit)

struct FullScreenVideoPlayerWrapper: UIViewControllerRepresentable {
    let player: AVPlayer
    @Binding var isPlaying: Bool
    let dismiss: DismissAction
    
    func makeUIViewController(context: Context) -> FullScreenVideoViewController {
        let controller = FullScreenVideoViewController()
        controller.player = player
        controller.isPlaying = isPlaying
        controller.onDismiss = { dismiss() }
        controller.onPlayingChanged = { isPlaying = $0 }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: FullScreenVideoViewController, context: Context) {
        // Update if needed
    }
}

// MARK: - Full Screen Video View Controller

class FullScreenVideoViewController: UIViewController {
    var player: AVPlayer!
    var isPlaying: Bool = false
    var onDismiss: (() -> Void)?
    var onPlayingChanged: ((Bool) -> Void)?
    
    private var playerLayer: AVPlayerLayer!
    private var showControls = true
    private var currentTime: Double = 0
    private var duration: Double = 1
    private var controlsWorkItem: DispatchWorkItem?
    private var timeObserverToken: Any?

    // UI Elements
    private let controlsContainer = UIView()
    private let topControlsContainer = UIView()
    private let bottomControlsContainer = UIView()
    private let closeButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let exitFullscreenButton = UIButton(type: .system)
    private let progressSlider = UISlider()
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeRight
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    override var shouldAutorotate: Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set background
        view.backgroundColor = .black
        
        // Setup player layer
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)
        
        // Setup controls
        setupControls()
        
        // Start monitoring playback
        startMonitoringPlayback()
        
        // Get duration
        Task {
            if let durationCMTime = try? await player.currentItem?.asset.load(.duration) {
                await MainActor.run {
                    self.duration = durationCMTime.seconds
                    self.durationLabel.text = formatTime(self.duration)
                }
            }
        }
        
        // Auto-hide controls
        scheduleControlsAutoHide()
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tapGesture)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Landscape is already enabled by the presenter, but ensure it here too.
        OrientationManager.shared.allowLandscape = true
        setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Rotate to landscape immediately now that the window/scene exists. This is
        // reliable on the first try because the presenter already flipped
        // `allowLandscape` before presenting.
        applyLandscapeOrientation()
    }

    /// Requests a landscape geometry update from the active window scene.
    private func applyLandscapeOrientation() {
        setNeedsUpdateOfSupportedInterfaceOrientations()

        if #available(iOS 16.0, *) {
            if let windowScene = view.window?.windowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
                    print("Orientation update error: \(error)")
                }
            }
        } else {
            let value = UIInterfaceOrientation.landscapeRight.rawValue
            UIDevice.current.setValue(value, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Intentionally do NOT pause here — the inline player shares this AVPlayer
        // and playback must continue seamlessly when returning to portrait.
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // Reset to portrait AFTER the view has fully disappeared
        OrientationManager.shared.allowLandscape = false
        
        if #available(iOS 16.0, *) {
            // Delay the orientation reset slightly to ensure smooth transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                }
            }
        } else {
            // For iOS 15 and earlier
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let value = UIInterfaceOrientation.portrait.rawValue
                UIDevice.current.setValue(value, forKey: "orientation")
                UIViewController.attemptRotationToDeviceOrientation()
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = view.bounds
        layoutControls()
    }
    
    private func setupControls() {
        // Controls container
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsContainer)
        
        // Top controls
        topControlsContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(topControlsContainer)
        
        // Close button
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        closeButton.layer.cornerRadius = 22
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        topControlsContainer.addSubview(closeButton)
        
        // Bottom controls
        bottomControlsContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomControlsContainer.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        controlsContainer.addSubview(bottomControlsContainer)
        
        // Time labels
        currentTimeLabel.textColor = .white
        currentTimeLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        currentTimeLabel.text = "0:00"
        currentTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomControlsContainer.addSubview(currentTimeLabel)
        
        durationLabel.textColor = .white
        durationLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        durationLabel.text = "0:00"
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomControlsContainer.addSubview(durationLabel)
        
        // Play/Pause button
        playPauseButton.setImage(UIImage(systemName: isPlaying ? "pause.fill" : "play.fill"), for: .normal)
        playPauseButton.tintColor = .white
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        bottomControlsContainer.addSubview(playPauseButton)
        
        // Progress slider
        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        progressSlider.tintColor = .white
        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        progressSlider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        bottomControlsContainer.addSubview(progressSlider)
        
        // Exit fullscreen button
        exitFullscreenButton.setImage(UIImage(systemName: "arrow.down.right.and.arrow.up.left"), for: .normal)
        exitFullscreenButton.tintColor = .white
        exitFullscreenButton.translatesAutoresizingMaskIntoConstraints = false
        exitFullscreenButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        bottomControlsContainer.addSubview(exitFullscreenButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            controlsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsContainer.topAnchor.constraint(equalTo: view.topAnchor),
            controlsContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            topControlsContainer.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor),
            topControlsContainer.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor),
            topControlsContainer.topAnchor.constraint(equalTo: controlsContainer.topAnchor),
            topControlsContainer.heightAnchor.constraint(equalToConstant: 80),
            
            closeButton.leadingAnchor.constraint(equalTo: topControlsContainer.leadingAnchor, constant: 16),
            closeButton.topAnchor.constraint(equalTo: topControlsContainer.topAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            
            bottomControlsContainer.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor),
            bottomControlsContainer.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor),
            bottomControlsContainer.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor),
            bottomControlsContainer.heightAnchor.constraint(equalToConstant: 100),
            
            currentTimeLabel.leadingAnchor.constraint(equalTo: bottomControlsContainer.leadingAnchor, constant: 20),
            currentTimeLabel.topAnchor.constraint(equalTo: bottomControlsContainer.topAnchor, constant: 12),
            
            durationLabel.trailingAnchor.constraint(equalTo: bottomControlsContainer.trailingAnchor, constant: -20),
            durationLabel.topAnchor.constraint(equalTo: bottomControlsContainer.topAnchor, constant: 12),
            
            playPauseButton.leadingAnchor.constraint(equalTo: bottomControlsContainer.leadingAnchor, constant: 20),
            playPauseButton.bottomAnchor.constraint(equalTo: bottomControlsContainer.bottomAnchor, constant: -20),
            playPauseButton.widthAnchor.constraint(equalToConstant: 44),
            playPauseButton.heightAnchor.constraint(equalToConstant: 44),
            
            exitFullscreenButton.trailingAnchor.constraint(equalTo: bottomControlsContainer.trailingAnchor, constant: -20),
            exitFullscreenButton.bottomAnchor.constraint(equalTo: bottomControlsContainer.bottomAnchor, constant: -20),
            exitFullscreenButton.widthAnchor.constraint(equalToConstant: 44),
            exitFullscreenButton.heightAnchor.constraint(equalToConstant: 44),
            
            progressSlider.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 20),
            progressSlider.trailingAnchor.constraint(equalTo: exitFullscreenButton.leadingAnchor, constant: -20),
            progressSlider.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor)
        ])
    }
    
    private func layoutControls() {
        // Already handled by Auto Layout
    }
    
    private func startMonitoringPlayback() {
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            self.currentTimeLabel.text = self.formatTime(self.currentTime)

            if self.duration > 0 {
                self.progressSlider.value = Float(self.currentTime / self.duration)
            }
        }
    }

    deinit {
        // The AVPlayer is shared with the inline player, so remove exactly the
        // observer we registered here to avoid a crash when either is deallocated.
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        controlsWorkItem?.cancel()
    }
    
    @objc private func handleTap() {
        showControls.toggle()
        
        UIView.animate(withDuration: 0.3) {
            self.controlsContainer.alpha = self.showControls ? 1 : 0
        }
        
        controlsWorkItem?.cancel()
        
        if showControls {
            scheduleControlsAutoHide()
        }
    }
    
    private func scheduleControlsAutoHide() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.showControls = false
            UIView.animate(withDuration: 0.3) {
                self.controlsContainer.alpha = 0
            }
        }
        controlsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }
    
    @objc private func closeTapped() {
        onDismiss?()
    }
    
    @objc private func playPauseTapped() {
        isPlaying.toggle()
        onPlayingChanged?(isPlaying)
        
        if isPlaying {
            player.play()
            playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        } else {
            player.pause()
            playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        }
    }
    
    @objc private func sliderChanged() {
        let seekTime = Double(progressSlider.value) * duration
        player.seek(to: CMTime(seconds: seekTime, preferredTimescale: 600))
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    // Pretend a subset of the credited people already have Nexus accounts, so
    // those names render orange/clickable while the rest stay grey.
    let _ = UserDefaults.standard.set(
        ["Ethan Ramirez", "Ava Thompson", "Priya Patel"],
        forKey: "createdUserProfiles"
    )
    return FilmDetailView(
        film: Submission(
            id: UUID(),
            type: .film,
            title: "Sample Film",
            details: "A great film",
            logline: "A washed-up magician gets one last shot at the spotlight.",
            ageRating: "PG-13",
            genres: ["Drama", "Comedy"],
            orderedCast: [
                OrderedEntry(role: "Jack Sullivan", name: "Ethan Ramirez"),
                OrderedEntry(role: "Maria Flores", name: "Sofia Nguyen"),
                OrderedEntry(role: "The Ringmaster", name: "Marcus Bell")
            ],
            orderedCrew: [
                OrderedEntry(role: "Director", name: "Ava Thompson"),
                OrderedEntry(role: "Writer", name: "Ava Thompson"),
                OrderedEntry(role: "Cinematographer", name: "Liam O'Brien"),
                OrderedEntry(role: "Editor", name: "Priya Patel")
            ],
            studio: "Longhorn Film Collective"
        ),
        liked: .constant(false)
    )
}
