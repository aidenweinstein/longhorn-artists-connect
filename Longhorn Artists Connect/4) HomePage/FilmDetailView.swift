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
    /// The post as it was when the detail opened. Read it through `film` instead, which
    /// resolves the store's current copy — so an edit shows immediately, and a second
    /// edit starts from the first one's result instead of silently reverting it.
    private let passedFilm: Submission
    @Binding var liked: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    /// Backs the studio credit's link to the org's page (see `studioPageTap`).
    @ObservedObject private var orgStore: OrganizationStore = .shared

    @State private var selectedPortfolioName: CreditedPerson?
    @State private var showSendMessage = false
    @State private var showDeleteConfirmation = false
    @State private var showReportSheet = false
    @State private var showEditSheet = false
    @State private var showCollectionPicker = false
    /// The organization page opened from the studio credit, if any.
    @State private var studioPage: Organization?
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
    /// Set once `resolveVideo()` finishes without a playable video, describing *why* —
    /// so the placeholder can state the exact production state ("Coming Soon", "File
    /// Non-Existent", "Error Streaming", …) instead of a blanket message. Nil while the
    /// video is still resolving (spinner) or once a playable URL is found.
    @State private var streamStatus: VideoStreamStatus?
    /// Compact diagnostic of the last stream-resolution attempt, shown under the
    /// placeholder for on-device debugging.
    @State private var streamDebug: String?

    // MARK: - Film Extras (trailer, BTS photos, stills)
    /// Resolved on-demand (the feed omits these heavy assets). Nil until `loadExtras` runs.
    @State private var trailerURL: URL?
    @State private var btsImageURLs: [URL] = []
    @State private var stillImageURLs: [URL] = []
    /// The image the full-screen viewer is showing, if any.
    @State private var fullScreenImageURLs: [URL] = []
    @State private var fullScreenStartIndex = 0
    @State private var showImageViewer = false

    init(film: Submission, liked: Binding<Bool>) {
        self.passedFilm = film
        self._liked = liked
        // Open the player at the video's known shape (from a previous load, the feed
        // preloader, or the poster's dimensions) so it doesn't snap from 16:9 later.
        self._videoAspectRatio = State(initialValue: VideoAspectCache.shared.displayAspect(for: film))
    }

    /// The live version of this film from the store (see `passedFilm`).
    private var film: Submission {
        store.currentCopy(of: passedFilm)
    }

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

    /// Opens the org page (the same one the Discover → Organizations list shows) for
    /// this film's studio credit, or `nil` when no organization goes by that name — an
    /// unrecognized credit stays plain text.
    private var studioPageTap: (() -> Void)? {
        let name = film.studio.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              let org = orgStore.organizations.first(where: {
                  $0.name.caseInsensitiveCompare(name) == .orderedSame
              })
        else { return nil }
        return { studioPage = org }
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

    /// Whether this film is expected to have a video at all. A film uploaded with a video
    /// always has its length synced to the feed (`videoDuration`), so a stored duration
    /// means "there should be a file" — letting us tell a genuine "Coming Soon" (never had
    /// a video) apart from a "File Non-Existent" (had one, but it's missing in CloudKit).
    private var expectsVideo: Bool {
        (film.videoDuration ?? 0) > 0
    }

    /// Resolves the playable video: uses a local copy if present, otherwise streams it on
    /// demand from CloudKit (the feed omits heavy video assets to stay fast/reliable). A
    /// local file is verified to actually contain a video track — a file that exists but
    /// has no playable video (empty/placeholder) is reported as `.unreadable` rather than
    /// driving a broken player that can softlock in fullscreen. On any non-playable
    /// outcome, `streamStatus` is set to the exact reason so the placeholder can state it.
    private func resolveVideo() async {
        if let local = film.videoURL {
            if await Self.hasVideoTrack(local) {
                resolvedVideoURL = local
                print("🎬 [FilmCard] PLAYING LOCAL FILE (not streaming): \(local.scheme ?? "?") \(local.lastPathComponent)")
            } else {
                streamStatus = .unreadable
            }
            return
        }
        guard resolvedVideoURL == nil, !isLoadingVideo else { return }
        // Fast path: the home feed already resolved and warmed this stream (hover
        // preview / preload), so skip the CloudKit lookup and start on it directly.
        if let warmed = FeedVideoPreloader.shared.readyStreamURL(for: film.id) {
            resolvedVideoURL = warmed
            return
        }
        isLoadingVideo = true
        // Stream only: play from a range-supporting CDN URL so playback starts without
        // ever writing the file to the device. Map each resolution outcome to a precise
        // status so the placeholder reports what's actually happening in production.
        let (resolution, debug) = await CloudKitManager.shared.streamResolutionDetailed(submissionID: film.id, type: .film)
        streamDebug = debug
        switch resolution {
        case .streaming(let streamURL):
            resolvedVideoURL = streamURL
            print("🎬 [FilmCard] STREAMING via CDN (no download): scheme=\(streamURL.scheme ?? "?") host=\(streamURL.host ?? "?")")
        case .assetMissing:
            // Record exists but carries no file. If the film never had a video, it's
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
        // The cache applies the playback crop and remembers the natural shape so the
        // next open starts at the right aspect ratio without waiting on the track.
        guard let ratio = await VideoAspectCache.shared.learn(film, from: AVURLAsset(url: url)) else { return }
        videoAspectRatio = ratio
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
                ScrollView(showsIndicators: false) {
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
                            } else if let streamStatus {
                                // Resolution finished without a playable video. The
                                // placeholder states exactly why — "Coming Soon" (never had
                                // a video), "File Non-Existent", "Error Streaming", etc. —
                                // and is non-tappable (the old poster zoomed into the
                                // thumbnail with no way back, softlocking the view).
                                VideoUnavailableView(status: streamStatus, tintColor: tintColor, detail: streamDebug, thumbnailData: film.thumbnailData)
                            } else {
                                // No local video yet. The feed skips heavy video assets, so
                                // stream it on demand here: show a labeled spinner while it
                                // pulls from CloudKit. When it resolves this branch is
                                // replaced by the player above, or the diagnostic
                                // placeholder if it couldn't be streamed.
                                VideoStreamingLoadingView(tintColor: tintColor, aspectRatio: videoAspectRatio ?? (16.0/9.0))
                                    .task { await resolveVideo() }
                            }

                            // Title and action buttons, then the logline, then the
                            // age rating / genres with the studio credit. Stacked as
                            // full-width rows so the logline can sit directly under
                            // the title without pushing the right-hand column around.
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top, spacing: 12) {
                                    // Up to three lines, shrinking rather than truncating so every
                                    // word of the title is always visible (the feed card is the
                                    // only place a title gets an ellipsis).
                                    Text(film.title)
                                        .font(.system(size: 28, weight: .bold))
                                        .minimumScaleFactor(0.5)
                                        .lineLimit(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                        // Fill the leftover width so the buttons sit
                                        // flush with the card's right edge.
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    // Action buttons, backed by a hidden one-line title
                                    // template so they're centered on the title's first
                                    // line. The template measures a *single* line on
                                    // purpose: a title that wraps to two lines grows
                                    // downward without dragging the buttons along.
                                    ZStack(alignment: .trailing) {
                                        Text(verbatim: " ")
                                            .font(.system(size: 28, weight: .bold))
                                            .lineLimit(1)
                                            .hidden()

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

                                // Logline, directly under the title.
                                if !film.logline.isEmpty {
                                    Text(film.logline)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                // Age rating and genres, with the studio/year credit
                                // (e.g. "Collective • 2025") flush right and centered
                                // on the row. The release year rides with the credit,
                                // so it's left out of the genre row itself.
                                HStack(alignment: .center, spacing: 12) {
                                    GenreReleaseYearRow(releaseYear: "") {
                                        if !film.ageRating.isEmpty {
                                            Text(film.ageRating)
                                                .font(.subheadline)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(.secondary.opacity(0.2))
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                        }

                                        GenreText(genres: film.genres.joined(separator: " • "))
                                    }

                                    // Skipped when there's nothing to credit. Tapping
                                    // the studio opens its page.
                                    if StudioYearCredit.hasCredit(studio: film.studio, releaseYear: film.releaseYear) {
                                        StudioYearCredit(
                                            studio: film.studio,
                                            releaseYear: film.releaseYear,
                                            onStudioTap: studioPageTap
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                        }

                        // Film Information
                        VStack(alignment: .leading, spacing: 12) {
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

                            // (No Studio section: the studio is credited next to the
                            // release year under the action buttons, where it's tappable.)

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
        // Hide the grey grabber so it doesn't cover the top of the content. The sheet can
        // still be dismissed with a pull-down swipe, and tall/scrollable detail pages get a
        // pinned close button (see needsForcedCloseButton above).
        .presentationDragIndicator(.hidden)
        .onAppear {
            PostAnalytics.shared.record(.open, for: film)
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
                .onAppear { PostAnalytics.shared.record(.profileVisit, for: film) }
        }
        .sheet(isPresented: $showSendMessage) {
            SendPostMessageView(post: film)
                .onAppear { PostAnalytics.shared.record(.message, for: film) }
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
                streamStatus = nil
                // Re-derive the shape (a crop change applies instantly; a replaced
                // video corrects itself once its track loads).
                videoAspectRatio = VideoAspectCache.shared.displayAspect(for: updatedSubmission)
                videoReloadToken += 1
            }
        }
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerView(post: film)
        }
        // The studio credit under the action buttons opens that org's page, presented
        // over this detail sheet exactly as it is from the Organizations list: no nav
        // bar, closed with a pull-down swipe.
        .sheet(item: $studioPage) { org in
            NavigationStack { OrganizationPageView(organization: org) }
                .presentationDragIndicator(.hidden)
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
        let player = AVPlayer(url: url)
        StreamPlaybackBuffer.tuneForVideo(player)
        _player = State(initialValue: player)
    }

    var body: some View {
        ScreenshotProtectedView {
            VideoPlayer(player: player)
        }
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
        .presentationDragIndicator(.hidden)
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
