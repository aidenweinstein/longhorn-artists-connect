//
//  ReelDetailView.swift
//  Longhorn Artists Connect
//
//  Detail view specifically for Reel (Talent) submissions
//

import SwiftUI
import AVKit

struct ReelDetailView: View {
    /// The reel as originally passed in. Display reads go through `reel` (below), which
    /// resolves the current version from the store so an edit is reflected immediately.
    private let passedReel: Submission
    @Binding var liked: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: SubmissionStore_3_2 = .shared

    /// The live version of this reel from the store (falling back to the passed-in copy),
    /// so edits to the description/type/thumbnail appear without reopening the detail.
    private var reel: Submission {
        store.approvedSubmissions.first { $0.id == passedReel.id }
            ?? store.submissions.first { $0.id == passedReel.id }
            ?? passedReel
    }

    init(reel: Submission, liked: Binding<Bool>) {
        self.passedReel = reel
        self._liked = liked
        // Open the player at the video's known shape (from a previous load, the feed
        // preloader, or the poster's dimensions) so it doesn't snap from 16:9 later.
        self._videoAspectRatio = State(initialValue: VideoAspectCache.shared.displayAspect(for: reel))
    }

    @State private var selectedPortfolioName: CreditedPerson?
    @State private var showSendMessage = false
    @State private var showDeleteConfirmation = false
    @State private var showReportSheet = false
    @State private var showEditSheet = false
    @State private var showCollectionPicker = false
    
    // Icon color that adapts to light/dark mode
    private var iconColor: Color {
        colorScheme == .dark ? .white : .black
    }
    @State private var isLoading = true
    @State private var contentLoaded = false
    /// Shown only once loading has run for over 1.5s (first-launch content download).
    @State private var showSlowLoadingMessage = false
    /// The resolved local video file. The feed no longer downloads video assets, so
    /// this is filled from a cached copy or an on-demand fetch when the reel opens.
    @State private var resolvedVideoURL: URL?
    @State private var isLoadingVideo = false
    /// Set once `resolveVideo()` finishes without a playable video, describing *why* — so
    /// the placeholder can state the exact production state ("Coming Soon", "File
    /// Non-Existent", "Error Streaming", …). Nil while the video is still resolving
    /// (spinner) or once a playable URL is found.
    @State private var streamStatus: VideoStreamStatus?
    /// Compact diagnostic of the last stream-resolution attempt, shown under the
    /// placeholder for on-device debugging.
    @State private var streamDebug: String?
    /// Bumped after an edit replaces the video so the inline player is recreated (the new
    /// file is written to the same path, so the AVPlayer won't reload it on its own).
    @State private var videoReloadToken = 0
    /// The video's native width/height ratio (after any playback crop), used to size the
    /// inline player to the submission's real shape — a vertical or 4:3 reel isn't forced
    /// into 16:9. `nil` until the natural size loads (falls back to 16:9).
    @State private var videoAspectRatio: CGFloat?
    /// A featured-work post the user tapped, presented in its own detail sheet.
    @State private var selectedFeaturedWork: Submission?
    @State private var featuredLiked = false
    /// Local files for a showcase's stills — the uploader's copies, or fetched on demand
    /// (the feed skips them).
    @State private var stillImageURLs: [URL] = []
    @State private var fullScreenStartIndex = 0
    @State private var showImageViewer = false
    
    private var canEditOrDelete: Bool {
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        let isUserCreator = !currentUser.isEmpty && currentUser == reel.submittedBy
        
        let isModeratorMode = UserDefaults.standard.bool(forKey: "isModeratorMode")
        let canUseModerator = isModeratorMode && ModeratorAccess.isModerator

        return isUserCreator || canUseModerator
    }
    
    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(reel.title.hashValue)
        return colors[hash % colors.count]
    }

    /// The reel's featured-work posts, resolved from their stored IDs against the store.
    private var featuredWorks: [Submission] {
        let all = store.approvedSubmissions + store.submissions
        return reel.featuredWorkIDs.compactMap { idString in
            guard let uuid = UUID(uuidString: idString) else { return nil }
            return all.first { $0.id == uuid }
        }
    }

    /// Hand-typed featured-work entries (project + director) that aren't posts on the app.
    private var manualFeaturedWorks: [ManualFeaturedWork] {
        reel.featuredWorkManual.compactMap(ManualFeaturedWork.init(encoded:))
    }

    /// Whether this reel is expected to have a video at all. A reel uploaded with a video
    /// has its length synced to the feed (`videoDuration`), so a stored duration means
    /// "there should be a file" — letting us tell a genuine "Coming Soon" (never had a
    /// video) apart from a "File Non-Existent" (had one, but it's missing in CloudKit).
    private var expectsVideo: Bool {
        (reel.videoDuration ?? 0) > 0
    }

    /// Resolves the playable video. Uses the uploader's local copy if one is already on
    /// disk; otherwise streams from a range-supporting CDN URL (never downloaded to the
    /// device). On any non-playable outcome, `streamStatus` is set to the exact reason so
    /// the placeholder can state what's actually happening in production.
    private func resolveVideo() async {
        if let local = reel.videoURL {
            if await FilmDetailView.hasVideoTrack(local) {
                resolvedVideoURL = local
                print("🎬 [ReelCard] PLAYING LOCAL FILE (not streaming): \(local.scheme ?? "?") \(local.lastPathComponent)")
            } else {
                streamStatus = .unreadable
            }
            return
        }
        guard resolvedVideoURL == nil, !isLoadingVideo else { return }
        // Fast path: the home feed already resolved and warmed this stream (hover
        // preview / preload), so skip the CloudKit lookup and start on it directly.
        if let warmed = FeedVideoPreloader.shared.readyStreamURL(for: reel.id) {
            resolvedVideoURL = warmed
            return
        }
        isLoadingVideo = true
        // Stream only: play from a range-supporting CDN URL so playback starts without
        // ever writing the file to the device. Map each resolution outcome to a precise
        // status so the placeholder reports what's actually happening in production.
        let (resolution, debug) = await CloudKitManager.shared.streamResolutionDetailed(submissionID: reel.id, type: .reel)
        streamDebug = debug
        switch resolution {
        case .streaming(let streamURL):
            resolvedVideoURL = streamURL
            print("🎬 [ReelCard] STREAMING via CDN (no download): scheme=\(streamURL.scheme ?? "?") host=\(streamURL.host ?? "?")")
        case .assetMissing:
            // Record exists but carries no file. If the reel never had a video, it's
            // genuinely "Coming Soon"; if a video was expected, the file is missing.
            streamStatus = expectsVideo ? .fileNonExistent : .comingSoon
        case .recordNotFound:
            streamStatus = .recordNotFound
        case .noDownloadURL:
            streamStatus = .noDownloadURL
        case .lookupError(let code):
            streamStatus = .errorStreaming(code)
        case .notConfigured:
            streamStatus = .notConfigured
        }
        isLoadingVideo = false
    }

    /// Loads the video's natural aspect ratio (accounting for its orientation
    /// transform and any playback crop) so the inline player matches the submission.
    private func loadVideoAspectRatio(_ url: URL) async {
        // The cache applies the playback crop and remembers the natural shape so the
        // next open starts at the right aspect ratio without waiting on the track.
        guard let ratio = await VideoAspectCache.shared.learn(reel, from: AVURLAsset(url: url)) else { return }
        videoAspectRatio = ratio
    }

    /// Loads the reel's stills: the local copies when the uploader is viewing, otherwise
    /// whatever CloudKit holds (empty for a reel posted without any).
    private func loadStills() async {
        let local = reel.stillImageURLs
        stillImageURLs = local.isEmpty
            ? await CloudKitManager.shared.downloadReelStills(submissionID: reel.id)
            : local
    }

    // MARK: - Featured Work

    /// Presents the appropriate detail view for a tapped featured-work post.
    @ViewBuilder
    private func featuredWorkDetail(for work: Submission) -> some View {
        switch work.type {
        case .film, .music, .reel, .photography, .design:
            PostDetailRouter(post: work, liked: $featuredLiked)
        case .project:
            UpcomingProjectDetailView(submission: work)
        case .event:
            EventDetailView(event: work)
        }
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
                        // Video Player Section (Demo Reel)
                        VStack(alignment: .leading, spacing: 0) {
                            if let videoURL = resolvedVideoURL {
                                CustomVideoPlayerView(
                                    submission: reel,
                                    videoURL: videoURL,
                                    thumbnailData: reel.thumbnailData,
                                    tintColor: tintColor
                                )
                                // Recreate the player after an edit replaces the video.
                                .id(videoReloadToken)
                                // Size the player to the video's real aspect ratio
                                // rather than locking every performance to 16:9.
                                .aspectRatio(videoAspectRatio ?? (16.0/9.0), contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .task(id: videoReloadToken) { await loadVideoAspectRatio(videoURL) }
                            } else if let streamStatus {
                                // Resolution finished without a playable video. The
                                // placeholder states exactly why — "Coming Soon", "File
                                // Non-Existent", "Error Streaming", etc. — and is
                                // non-tappable (the old poster opened a full-screen
                                // thumbnail with no way back, softlocking the view).
                                VideoUnavailableView(status: streamStatus, tintColor: tintColor, detail: streamDebug, thumbnailData: reel.thumbnailData)
                            } else {
                                // Still resolving: a labeled spinner while it pulls from
                                // CloudKit (replaced by the player, or the diagnostic
                                // placeholder, once it resolves).
                                VideoStreamingLoadingView(tintColor: tintColor, aspectRatio: videoAspectRatio ?? (16.0/9.0))
                                    .task { await resolveVideo() }
                            }
                            
                            // Title and action buttons
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        // Up to three lines, shrinking rather than truncating so
                                        // every word of the title is always visible.
                                        Text(reel.title)
                                            .font(.system(size: 28, weight: .bold))
                                            .minimumScaleFactor(0.5)
                                            .lineLimit(3)
                                            .fixedSize(horizontal: false, vertical: true)

                                        // Artist name — same placement/style as the music card.
                                        if !reel.artist.isEmpty {
                                            Text(reel.artist)
                                                .font(.title3)
                                                .foregroundStyle(.secondary)
                                        }

                                        // Reel type, with the release year pinned to the
                                        // row's right edge.
                                        GenreReleaseYearRow(
                                            genres: reel.reelType,
                                            releaseYear: reel.releaseYear
                                        )
                                    }
                                    // No Spacer here: the genre/year row above is
                                    // full-width, so the info column already pushes the
                                    // buttons right — and a Spacer would split the
                                    // leftover width, pulling the year off the edge.

                                    // Action buttons — packed tight to leave the title more room.
                                    HStack(spacing: 2) {
                                        Button {
                                            store.toggleLike(for: reel)
                                        } label: {
                                            // Like counts are private: only credited collaborators
                                            // see them on their own portfolio page.
                                            Image(systemName: store.isLiked(reel) ? "heart.fill" : "heart")
                                                .font(.system(size: 20))
                                                .foregroundStyle(store.isLiked(reel) ? .red : .primary)
                                                .frame(minWidth: 30, minHeight: 32)
                                        }

                                        Button {
                                            showCollectionPicker = true
                                        } label: {
                                            Image(systemName: store.isInAnyCollection(reel) ? "bookmark.fill" : "bookmark")
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
                        
                        // Reel Information
                        VStack(alignment: .leading, spacing: 12) {
                            // Description (the reel's own "reelDescription" field, which
                            // the edit form writes to — not `logline`, which reels never set).
                            if !reel.reelDescription.isEmpty {
                                Text(reel.reelDescription)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, 12)
                            }

                            // Stills gallery (Actor/Dance Showcase only).
                            if !stillImageURLs.isEmpty {
                                Divider()
                                stillsSection
                            }

                            // Featured Work — linked posts this reel references plus any
                            // hand-typed entries, listed in the same card style as a portfolio.
                            if !featuredWorks.isEmpty || !manualFeaturedWorks.isEmpty {
                                Divider()
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Featured Work")
                                        .font(.title2)
                                        .fontWeight(.bold)

                                    VStack(spacing: 10) {
                                        ForEach(featuredWorks) { work in
                                            Button {
                                                selectedFeaturedWork = work
                                            } label: {
                                                SubmissionListRow(submission: work) { EmptyView() }
                                            }
                                            .buttonStyle(.plain)
                                        }

                                        // Hand-typed entries: not tappable (no post to open).
                                        ForEach(manualFeaturedWorks) { entry in
                                            ManualFeaturedWorkRow(entry: entry)
                                        }
                                    }
                                }
                            }

                            // Moderator info
                            if UserDefaults.standard.bool(forKey: "isModeratorMode"), ModeratorAccess.isModerator {
                                Text("Submitted by \(reel.submittedBy)")
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
        }
        // Hide the grey grabber so it doesn't cover the top of the content. The sheet can
        // still be dismissed with a pull-down swipe.
        .presentationDragIndicator(.hidden)
        .onAppear {
            PostAnalytics.shared.record(.open, for: reel)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    isLoading = false
                    contentLoaded = true
                }
            }
        }
        .sheet(item: $selectedPortfolioName) { person in
            PersonProfileView(name: person.name)
                .onAppear { PostAnalytics.shared.record(.profileVisit, for: reel) }
        }
        .sheet(isPresented: $showSendMessage) {
            SendPostMessageView(post: reel)
                .onAppear { PostAnalytics.shared.record(.message, for: reel) }
        }
        .sheet(isPresented: $showReportSheet) {
            ReportContentView(post: reel)
        }
        .sheet(isPresented: $showEditSheet) {
            ReelEditView(submission: reel) { updatedSubmission in
                store.update(updatedSubmission)
                // Re-point at the (possibly replaced) local video and force a reload —
                // the new file often lives at the same path.
                resolvedVideoURL = updatedSubmission.videoURL
                streamStatus = nil
                // Re-derive the shape (a crop change applies instantly; a replaced
                // video corrects itself once its track loads).
                videoAspectRatio = VideoAspectCache.shared.displayAspect(for: updatedSubmission)
                videoReloadToken += 1
            }
        }
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerView(post: reel)
        }
        .fullScreenCover(isPresented: $showImageViewer) {
            FullScreenImageViewer(imageURLs: stillImageURLs, startIndex: fullScreenStartIndex)
        }
        // Re-runs after an edit changes the category or the stills set.
        .task(id: "\(reel.reelType)|\(reel.stillImageFileNames)") { await loadStills() }
        .sheet(item: $selectedFeaturedWork) { work in
            featuredWorkDetail(for: work)
        }
        .alert("Delete Reel?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                store.delete(reel)
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    /// Horizontally-scrolling stills; tapping one opens the full-screen viewer.
    private var stillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stills")
                .font(.title2)
                .fontWeight(.bold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(stillImageURLs.enumerated()), id: \.offset) { index, url in
                        if let image = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 160, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onTapGesture {
                                    fullScreenStartIndex = index
                                    showImageViewer = true
                                }
                        }
                    }
                }
            }
        }
    }
}

// Note: Video player components (CustomVideoPlayerView, FullScreenVideoPlayer, etc.) 
// are shared with FilmCard.swift and defined there.

#Preview {
    // Pretend a subset of the credited people already have Nexus accounts, so
    // those names render orange/clickable while the rest stay grey.
    let _ = UserDefaults.standard.set(
        ["Ava Thompson", "Priya Patel"],
        forKey: "createdUserProfiles"
    )
    return ReelDetailView(
        reel: Submission(
            id: UUID(),
            type: .reel,
            title: "Acting Reel",
            details: "Professional actor",
            orderedCrew: [
                OrderedEntry(role: "Director", name: "Ava Thompson"),
                OrderedEntry(role: "Scene Partner", name: "Liam O'Brien"),
                OrderedEntry(role: "Editor", name: "Priya Patel")
            ],
            reelType: "Dramatic",
            reelDescription: "Selected scenes from recent stage and screen work.",
            reelExperience: "5 years of theater and independent film.",
            reelSpecificSkills: "Stage combat, dialects, improv"
        ),
        liked: .constant(false)
    )
}
