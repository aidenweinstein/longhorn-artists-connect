//
//  FilmDetailView.swift
//  Longhorn Artists Connect
//
//  Detail view specifically for Film submissions
//

import SwiftUI
import AVKit
import Combine
import MediaPlayer

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
    // (removed showFullScreenPoster: the on-demand player no longer falls back to a
    // tappable poster, which used to zoom into the thumbnail with no way back.)
    @State private var contentLoaded = false
    /// Shown only once loading has run for over 1.5s (first-launch content download).
    @State private var showSlowLoadingMessage = false
    /// The video's native width/height ratio, used to size the inline preview so a
    /// non-16:9 film (e.g. 4:3) is shown fully instead of cropped or letterboxed.
    /// `nil` until the natural size loads (falls back to 16:9).
    @State private var videoAspectRatio: CGFloat?
    /// The resolved local video file. The feed no longer downloads video assets, so
    /// this is filled either from a previously-cached file or by an on-demand fetch.
    @State private var resolvedVideoURL: URL?
    @State private var isLoadingVideo = false
    /// Bumped after an edit replaces the video so the inline player is torn down and
    /// recreated. A replaced video is written to the SAME file path, so the AVPlayer
    /// won't reload it on its own — changing this `.id` forces a fresh player.
    @State private var videoReloadToken = 0
    /// True once `resolveVideo()` has finished and found no playable video — i.e. the
    /// film was submitted without one. Distinguishes "still downloading" from "there is
    /// nothing to play", so we can show a "Coming Soon" placeholder instead of a
    /// tappable poster that would zoom into the thumbnail with no way back.
    @State private var noVideoAvailable = false

    // MARK: - Film Extras (trailer, BTS photos, stills)
    /// Resolved on-demand (the feed omits these heavy assets). Nil until `loadExtras` runs.
    @State private var trailerURL: URL?
    @State private var btsImageURLs: [URL] = []
    @State private var stillImageURLs: [URL] = []
    /// The image the full-screen viewer is showing, if any.
    @State private var fullScreenImageURLs: [URL] = []
    @State private var fullScreenStartIndex = 0
    @State private var showImageViewer = false

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
        let canUseModerator = isModeratorMode && ModeratorAccess.isModerator

        return isUserCreator || canUseModerator
    }

    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(film.title.hashValue)
        return colors[hash % colors.count]
    }

    /// Hardcoded escape hatch for one specific film. "Group Study" softlocks the detail
    /// sheet — its content is tall enough that the swipe-to-dismiss / drag indicator gets
    /// eaten as scroll overscroll, leaving no way out (scrolling just moves the content).
    /// This film is the only place it shows up, so we special-case it and force an
    /// always-visible close button rather than change the shared dismissal behavior.
    private var needsForcedCloseButton: Bool {
        film.title.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Group Study") == .orderedSame
    }

    /// Shown in place of the video for festival-bound films: the post is public,
    /// but the film itself stays under wraps until its festival release.
    private var festivalBoundPlaceholder: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(
                    colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            VStack(spacing: 10) {
                Image(systemName: "film.stack")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Festival Bound - Coming Soon")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0/9.0, contentMode: .fit)
        .clipped()
    }

    /// Shown when a film has no video attached at all. The post is still valid (it can
    /// list cast, crew, and credits), but there's nothing to play — so the player area
    /// shows a simple "Coming Soon" rather than a tappable poster that would zoom into
    /// the thumbnail and softlock the view.
    private var comingSoonPlaceholder: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(
                    colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            VStack(spacing: 10) {
                Image(systemName: "film.stack")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Coming Soon")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0/9.0, contentMode: .fit)
        .clipped()
    }

    /// Resolves the playable video: uses a local copy if present, otherwise downloads
    /// it on demand (the feed omits heavy video assets to stay fast/reliable). The file
    /// is verified to actually contain a video track — a file that exists but has no
    /// playable video (empty/placeholder) is treated as "no video" so we show the
    /// non-tappable "Coming Soon" rather than a broken player that can softlock in
    /// fullscreen. If no video is found, `noVideoAvailable` drives the placeholder.
    private func resolveVideo() async {
        if let local = film.videoURL {
            if await Self.hasVideoTrack(local) {
                resolvedVideoURL = local
            } else {
                noVideoAvailable = true
            }
            return
        }
        guard resolvedVideoURL == nil, !isLoadingVideo else { return }
        isLoadingVideo = true
        // Stream only: play from a range-supporting CDN URL so playback starts without
        // ever writing the file to the device. If no streaming URL is available (e.g.
        // web services not configured / lookup failed), show the placeholder rather than
        // falling back to a full local download.
        if let streamURL = await CloudKitManager.shared.streamingURL(submissionID: film.id, type: .film) {
            resolvedVideoURL = streamURL
        } else {
            noVideoAvailable = true
        }
        isLoadingVideo = false
    }

    /// Downloads (or reuses) the film's extras — trailer, BTS photos, stills — on demand,
    /// since the feed skips these heavy assets. Runs once when the detail view appears.
    private func loadExtras() async {
        // Trailer streams (video, never downloaded); photo galleries fetch in parallel.
        async let trailer = CloudKitManager.shared.trailerStreamingURL(submissionID: film.id)
        async let extras = CloudKitManager.shared.downloadFilmExtras(submissionID: film.id)
        let (resolvedTrailer, resolvedExtras) = await (trailer, extras)
        await MainActor.run {
            trailerURL = resolvedTrailer
            btsImageURLs = resolvedExtras.bts
            stillImageURLs = resolvedExtras.stills
        }
    }

    /// Whether a file actually has a playable video track (not just a file that exists).
    static func hasVideoTrack(_ url: URL) async -> Bool {
        let tracks = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        return (tracks?.isEmpty == false)
    }

    /// Loads the video's natural aspect ratio (accounting for its orientation
    /// transform) so the inline preview can size itself to the real dimensions.
    private func loadVideoAspectRatio(_ url: URL) async {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else { return }
        let resolved = naturalSize.applying(transform)
        let width = abs(resolved.width)
        let height = abs(resolved.height)
        guard width > 0, height > 0 else { return }
        let ratio = width / height
        await MainActor.run { videoAspectRatio = ratio }
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

                    if showSlowLoadingMessage {
                        Text("When first downloading Nexus, content may take a few minutes to load. But, from there on after, it will be quick!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    // Only surface the first-launch hint if loading is still going after 1.5s.
                    // SwiftUI cancels this task when content loads and the view is removed.
                    try? await Task.sleep(for: .seconds(1.5))
                    showSlowLoadingMessage = true
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Video Player Section
                        VStack(alignment: .leading, spacing: 0) {
                            if film.festivalBound {
                                // Festival-bound films are public but withhold their
                                // video until release — show a placeholder instead.
                                festivalBoundPlaceholder
                            } else if let videoURL = resolvedVideoURL {
                                CustomVideoPlayerView(
                                    submission: film,
                                    videoURL: videoURL,
                                    thumbnailData: film.thumbnailData,
                                    tintColor: tintColor
                                )
                                // Recreate the player after an edit replaces the video.
                                .id(videoReloadToken)
                                // Size the preview to the video's real aspect ratio so a
                                // 4:3 (or other non-16:9) film fills it exactly with no
                                // black bars.
                                .aspectRatio(videoAspectRatio ?? (16.0/9.0), contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .task { await loadVideoAspectRatio(videoURL) }
                            } else if noVideoAvailable {
                                // Resolution finished and there's no video — the film was
                                // submitted without one. Show a non-tappable "Coming Soon"
                                // placeholder (tapping the old poster zoomed into the
                                // thumbnail with no way back, softlocking the view).
                                comingSoonPlaceholder
                            } else {
                                // No local video yet. The feed skips heavy video assets,
                                // so download it on demand here: show a spinner while it
                                // loads. When it resolves this branch is replaced by the
                                // player above, or the "Coming Soon" placeholder if none.
                                ZStack {
                                    Rectangle()
                                        .fill(LinearGradient(
                                            colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                        .frame(maxWidth: .infinity)
                                        .aspectRatio(16.0/9.0, contentMode: .fit)
                                    ProgressView()
                                        .tint(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .task { await resolveVideo() }
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
                                                    // Keep genres on a single line; shrink to fit rather than wrap.
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.7)
                                            }
                                        }

                                        // Release year, shown just under the genres line.
                                        if !film.releaseYear.isEmpty {
                                            Text(film.releaseYear)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    // Action buttons — packed tight to leave the title more room.
                                    HStack(spacing: 2) {
                                        Button {
                                            store.toggleLike(for: film)
                                        } label: {
                                            // Like counts are private: only credited collaborators
                                            // see them on their own portfolio page.
                                            Image(systemName: store.isLiked(film) ? "heart.fill" : "heart")
                                                .font(.system(size: 20))
                                                .foregroundStyle(store.isLiked(film) ? .red : .primary)
                                                .frame(minWidth: 30, minHeight: 32)
                                        }

                                        Button {
                                            showCollectionPicker = true
                                        } label: {
                                            Image(systemName: store.isInAnyCollection(film) ? "bookmark.fill" : "bookmark")
                                                .font(.system(size: 20))
                                                .foregroundStyle(iconColor)
                                                .frame(width: 30, height: 32)
                                        }

                                        Button {
                                            showSendMessage = true
                                        } label: {
                                            Image(systemName: "paperplane")
                                                .font(.system(size: 20))
                                                .foregroundStyle(iconColor)
                                                .frame(width: 30, height: 32)
                                        }

                                        Button {
                                            showReportSheet = true
                                        } label: {
                                            Image(systemName: "flag")
                                                .font(.system(size: 20))
                                                .foregroundStyle(iconColor)
                                                .frame(width: 30, height: 32)
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

                                    ForEach(film.orderedCast) { entry in
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

                            // Trailer (a separate video from the feature film above).
                            if let trailerURL {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Trailer")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    TrailerPlayerView(url: trailerURL)
                                        .aspectRatio(16.0/9.0, contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }

                            // Stills gallery.
                            if !stillImageURLs.isEmpty {
                                filmImageSection(title: "Stills", urls: stillImageURLs)
                            }

                            // Behind-the-scenes photos gallery.
                            if !btsImageURLs.isEmpty {
                                filmImageSection(title: "BTS Photos", urls: btsImageURLs)
                            }

                            // Moderator info
                            if UserDefaults.standard.bool(forKey: "isModeratorMode"), ModeratorAccess.isModerator {
                                Text("Submitted by \(film.submittedBy)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                                    .padding(.top, 16)
                            }

                            // Edit and Delete buttons
                            if canEditOrDelete {
                                OwnerActionButtons(
                                    onEdit: { showEditSheet = true },
                                    onDelete: { showDeleteConfirmation = true }
                                )
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

            // Hardcoded fix for the "Group Study" softlock (see needsForcedCloseButton):
            // a pinned close button so the sheet can always be dismissed, since swiping
            // over its tall content just scrolls instead of closing.
            if needsForcedCloseButton {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(11)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .padding(.top, 16)
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        // Show the grabber so tall, scrollable detail pages (long cast/crew) can always
        // be dismissed — pulling the indicator drives the sheet directly, whereas a plain
        // swipe over a scrollable page gets eaten as scroll overscroll and snaps back.
        .presentationDragIndicator(.visible)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    isLoading = false
                    contentLoaded = true
                }
            }
        }
        .task { await loadExtras() }
        .fullScreenCover(isPresented: $showImageViewer) {
            FullScreenImageViewer(imageURLs: fullScreenImageURLs, startIndex: fullScreenStartIndex)
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
                // Re-point at the (possibly replaced) local video and force the player to
                // reload it — the new file often lives at the same path, so the AVPlayer
                // wouldn't otherwise pick up the change.
                resolvedVideoURL = updatedSubmission.videoURL
                videoAspectRatio = nil
                videoReloadToken += 1
            }
        }
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerView(post: film)
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

    /// A titled horizontal gallery of images loaded from local file URLs. Tapping an image
    /// opens the paged full-screen viewer at that index.
    @ViewBuilder
    private func filmImageSection(title: String, urls: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        if let image = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 160, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onTapGesture {
                                    fullScreenImageURLs = urls
                                    fullScreenStartIndex = index
                                    showImageViewer = true
                                }
                        }
                    }
                }
            }
        }
    }

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

// MARK: - Owner Action Buttons

/// Compact Edit/Delete controls shown to a post's owner (and moderators) at the
/// bottom-left of a detail card. Small, horizontally stacked chips that keep their
/// colored tint + glow. Shared by every detail card (film, music, reel, event, project).
struct OwnerActionButtons: View {
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            chip(title: "Edit", systemImage: "pencil", tint: .orange, action: onEdit)
            chip(title: "Delete", systemImage: "trash", tint: .red, action: onDelete)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func chip(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12), in: Capsule())
            .shadow(color: tint.opacity(0.45), radius: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Trailer Player

/// A simple inline player for a film's trailer, using the system `VideoPlayer` controls.
/// Kept separate from the feature film's `CustomVideoPlayerView` so the two don't share a
/// player or a saved playback position (both would otherwise key off the same film ID).
struct TrailerPlayerView: View {
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .onDisappear { player.pause() }
    }
}

// MARK: - Full Screen Image Viewer

/// A paged, swipeable full-screen viewer for a set of local image files (BTS / stills).
struct FullScreenImageViewer: View {
    let imageURLs: [URL]
    let startIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int

    init(imageURLs: [URL], startIndex: Int) {
        self.imageURLs = imageURLs
        self.startIndex = startIndex
        _selection = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                    if let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .tag(index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: imageURLs.count > 1 ? .automatic : .never))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .padding()
        }
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

    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 1

    private var timeObserver: Any?

    init(url: URL, submissionID: UUID) {
        self.player = AVPlayer(url: url)
        self.submissionID = submissionID

        // Drives the scrubber. The observer fires on the main queue, so updating the
        // published state directly here is safe.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.currentTime = time.seconds
        }

        Task { @MainActor in await self.restoreAndPlay() }
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
        player.play()
        isPlaying = true
    }

    func togglePlay() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
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
        player.pause()
        removeObserver()
    }

    private func removeObserver() {
        if let token = timeObserver {
            player.removeTimeObserver(token)
            timeObserver = nil
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
        _model = StateObject(wrappedValue: VideoPlayerModel(url: videoURL, submissionID: submission.id))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VideoPlayer(player: model.player)
                .disabled(true)                     // hide native controls; we draw our own
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
            PlayerLayerView(player: model.player)

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
            studio: "Longhorn Film Collective",
            releaseYear: "2024"
        ),
        liked: .constant(false)
    )
}
