//
//  HomePostCard.swift
//  Longhorn Artists Connect
//
//  Card view for posts in the home feed
//

import SwiftUI
import AVKit
import ImageIO

struct HomePostCard: View {
    let post: Submission
    let showTypeIcon: Bool
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @State private var showOptions = false
    @State private var showProjectDetail = false
    @State private var showSendMessage = false
    @State private var showCollectionPicker = false
    @State private var videoDuration: Double?
    /// Set true only once a stream lookup confirms a film genuinely has no video attached,
    /// so the "Coming Soon" badge never shows merely because a legacy film's length was
    /// never synced to the feed.
    @State private var filmConfirmedNoVideo = false
    @State private var thumbnailImage: UIImage? // Cache the image
    /// The thumbnail's width ÷ height read from the image header (no decode) the moment
    /// the card is built, so the media frame is the right height on its very first
    /// frame. Without this every card opened at 16:9 and snapped to its real shape once
    /// the async decode landed — invisible for films (their posters are 16:9) but a
    /// visible jump for event flyers and project covers, which shoved the whole feed
    /// below them as they scrolled in.
    @State private var headerAspect: CGFloat?
    /// True when the thumbnail's bottom-left corner (where the Collective logo sits) is
    /// close to white, so the white logo would be hard to see and the black one is used.
    @State private var collectiveCornerIsLight = false
    /// Inline preview: a film/reel's video plays (with sound, looping) in place of the
    /// thumbnail — or a music post's track plays behind its album art — after the
    /// card has been the one nearest the middle of the feed for 1 s (see
    /// `FeedAutoplayCoordinator`) or, on pointer devices, after the pointer rests on
    /// it for 1.5 s.
    @State private var preview = HoverPreviewController()
    /// True while enough of the thumbnail is on screen for the card to be eligible
    /// to autoplay. Used to resume a system-paused preview when the app returns to
    /// the foreground.
    @State private var isMostlyVisible = false
    @Environment(\.scenePhase) private var scenePhase
    /// The width to lay the thumbnail out at until the card's real width has been
    /// measured. The single-column iPhone feed is full-bleed, so the screen width is
    /// already exact; the multi-column iPad feed passes its column width instead so the
    /// first frame of each card is the right height too.
    var estimatedWidth: CGFloat = UIScreen.main.bounds.width
    /// The card's width as reported by the GeometryReader below, once it has landed.
    @State private var measuredWidth: CGFloat?
    /// The card's width. The thumbnail height is derived purely from this and the
    /// media's aspect ratio, so nothing about the proposed *height* (e.g. the search
    /// keyboard shrinking the feed) can make the card narrower than the normal feed.
    private var cardWidth: CGFloat { measuredWidth ?? estimatedWidth }
    @Environment(\.colorScheme) private var colorScheme

    /// Gallery carousel (photography / design posts with more than one image): the
    /// images after the first, decoded off the main actor and downsampled to the card's
    /// width. The first page is the post's thumbnail, which already *is* the first image.
    @State private var galleryImages: [UIImage] = []
    /// Which carousel page is showing; 0 is the thumbnail.
    @State private var galleryIndex = 0

    init(post: Submission, showTypeIcon: Bool, estimatedWidth: CGFloat = UIScreen.main.bounds.width) {
        self.post = post
        self.showTypeIcon = showTypeIcon
        self.estimatedWidth = estimatedWidth
        // Header-only read (a few microseconds, no pixel decode) so the first layout
        // pass already knows the media's shape. See `headerAspect`.
        _headerAspect = State(initialValue: VideoAspectCache.thumbnailAspect(post.thumbnailData))
    }

    /// The thumbnail's natural aspect ratio (width ÷ height): the decoded image's if it
    /// has landed, else the shape read from the image header, else 16:9 for the
    /// gradient placeholder when there's no thumbnail at all.
    private var thumbnailAspect: CGFloat {
        if let img = thumbnailImage, img.size.width > 0, img.size.height > 0 {
            return img.size.width / img.size.height
        }
        if let headerAspect, headerAspect > 0 {
            return headerAspect
        }
        return 16.0 / 9.0
    }

    /// Local files of every image in the post's gallery, in order. Only photography and
    /// design posts carry a gallery; everything else is a single thumbnail.
    private var galleryURLs: [URL] {
        switch post.type {
        case .photography: return post.photoImageURLs
        case .design: return post.designImageURLs
        default: return []
        }
    }

    /// Whether this card shows a swipeable carousel rather than a single thumbnail.
    private var hasGallery: Bool { galleryURLs.count > 1 }

    /// Total pages in the carousel: the thumbnail plus every decoded gallery image.
    private var galleryPageCount: Int { galleryImages.count + 1 }

    /// The shared aspect ratio for every page after the first. It is the ratio of the
    /// *tallest* gallery image when fitted to the card width (the one that renders
    /// largest), so each remaining image fits inside the same frame uncropped and the
    /// card's height doesn't jump between swipes. Falls back to the thumbnail's ratio
    /// until the gallery has decoded.
    private var galleryRestAspect: CGFloat {
        let ratios = galleryImages.compactMap { img -> CGFloat? in
            guard img.size.width > 0, img.size.height > 0 else { return nil }
            return img.size.width / img.size.height
        }
        return ratios.min() ?? thumbnailAspect
    }

    /// The aspect ratio the media frame is laid out at right now: the thumbnail's own
    /// ratio on the first page, the shared gallery ratio on every other page.
    private var currentMediaAspect: CGFloat {
        galleryIndex == 0 ? thumbnailAspect : galleryRestAspect
    }

    /// Re-decodes the gallery whenever the set of files behind it changes.
    private var galleryTaskKey: String {
        galleryURLs.dropFirst().map(\.lastPathComponent).joined(separator: "|")
    }
    
    // Generate a consistent color for each post based on title
    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(post.title.hashValue)
        return colors[hash % colors.count]
    }
    
    // Icon color that adapts to light/dark mode
    private var iconColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    // Get the icon for the post type
    private var typeIcon: String {
        switch post.type {
        case .film:
            return "film"
        case .music:
            return "music.note"
        case .reel:
            return "theatermasks.fill"
        case .photography:
            return "camera.fill"
        case .design:
            return "paintpalette.fill"
        case .project:
            return "doc.text"
        case .event:
            return "calendar"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Media thumbnail - adapts to content aspect ratio
            Button {
                // Record the open so the recommendation algorithm sinks this post to the
                // bottom of the feed on the next reload (see Algorithms.swift).
                SeenContentTracker.shared.markSeen(post.id)
                showProjectDetail = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    // Media fills the full card width; its height is width ÷ aspect ratio,
                    // so it's identical in the normal and search feeds regardless of the
                    // height the layout proposes (the keyboard no longer shrinks it).
                    Group {
                        if post.type == .film && post.festivalBound {
                            // Festival-bound films withhold their video and poster
                            // until release — show a "Coming Soon" placeholder.
                            ZStack {
                                Rectangle()
                                    .fill(LinearGradient(colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                VStack(spacing: 8) {
                                    Image(systemName: "film.stack")
                                        .font(.system(size: 36, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.9))
                                    Text("Festival Bound - Coming Soon")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.horizontal, 24)
                            }
                        } else if hasGallery, !galleryImages.isEmpty {
                            // Photo/design gallery: swipe sideways through every image
                            // right on the feed. Until the extra images have decoded the
                            // plain thumbnail below shows, exactly as for a single image.
                            galleryPager
                        } else if let thumbnailImage {
                            // Fit, not fill: the frame below is derived from this image's
                            // own aspect ratio, so fitting renders identically to filling
                            // while guaranteeing nothing is cropped. Filling would shave
                            // the photo's edges whenever the frame's ratio is even slightly
                            // off the image's — a stale measured width for one frame, or
                            // rounding in the upload downscale.
                            Image(uiImage: thumbnailImage)
                                .resizable()
                                .scaledToFit()
                        } else {
                            // Background color/gradient fallback
                            Rectangle()
                                .fill(LinearGradient(colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    // The first page keeps the thumbnail's own ratio; swiping on, the frame
                    // settles at the shared gallery ratio and stays there (see
                    // `currentMediaAspect`), animating the one-time height change.
                    .frame(height: cardWidth / currentMediaAspect)
                    .animation(.default, value: galleryIndex)
                    // Hover preview: the video fades in over the thumbnail once enough of
                    // it is buffered to play without stuttering. It never takes touches,
                    // so tapping still opens the post. A music post has nothing to show —
                    // its track plays audibly behind the album art — so no surface.
                    .overlay {
                        if let player = preview.player, !FeedVideoPreloader.isAudioPreview(post) {
                            FeedPreviewSurface(player: player, crop: VideoCrop(post.videoCrop))
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if preview.isBuffering {
                            ProgressView()
                                .tint(.white)
                                .padding(6)
                                .background(Circle().fill(.black.opacity(0.5)))
                                .padding(8)
                                .transition(.opacity)
                        } else if preview.player != nil, FeedVideoPreloader.isAudioPreview(post) {
                            // Music autoplay: a pulsing speaker in the spinner's slot shows
                            // the sound is coming from this card.
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .symbolEffect(.variableColor.iterative, isActive: true)
                                .frame(width: 20, height: 20)
                                .padding(6)
                                .background(Circle().fill(.black.opacity(0.5)))
                                .padding(8)
                                .transition(.opacity)
                        }
                    }
                    .clipped()
                    // Studio badge in the bottom-left corner (opposite the timecode).
                    // The Collective mark is white by default and switches to black when
                    // the area behind it is close to white so it stays legible (same size
                    // either way); the Incubator mark is its org profile picture, framed
                    // in a circle exactly as it appears on the Incubator org page.
                    .overlay(alignment: .bottomLeading) {
                        if isCollectiveStudio {
                            Image(collectiveCornerIsLight ? "Collective Black" : "Collective White")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 40)
                                .padding(.leading, 8)
                                .padding(.bottom, 0)
                        } else if isIncubatorStudio {
                            OrgAvatar(imageData: nil, diameter: 24,
                                      assetName: "PP Incubator")
                                .padding(.leading, 8)
                                .padding(.bottom, 0)
                        }
                    }

                    // Duration overlay for film (video) and music (audio) posts.
                    // Withheld for festival-bound films (video isn't shown yet). A film
                    // submitted without a video shows "Coming Soon" in the timecode slot
                    // instead of a length.
                    if let duration = videoDuration, (post.type == .film || post.type == .music || post.type == .reel), !post.festivalBound {
                        // The timecode fades out while the card is autoplaying — the
                        // media is already running, so its length is just clutter — and
                        // fades back in when the preview stops.
                        durationBadge(formatDuration(duration))
                            .opacity(isPreviewPlaying ? 0 : 1)
                            .animation(.easeInOut(duration: 0.25), value: isPreviewPlaying)
                    } else if post.type == .film, !post.festivalBound, filmConfirmedNoVideo {
                        durationBadge("Coming Soon")
                    } else if hasGallery {
                        // Gallery posts: show the position in the gallery ("2/5") in the
                        // timecode slot — just the count until the extra images decode.
                        // A single image needs no badge.
                        photoCountBadge(galleryImages.isEmpty ? nil : galleryIndex + 1, of: galleryURLs.count)
                    }
                }
                .frame(maxWidth: .infinity)
                // Measure the actual card width so the height above is exact on every device.
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: CardWidthPreferenceKey.self, value: geo.size.width)
                    }
                )
                .onPreferenceChange(CardWidthPreferenceKey.self) { width in
                    if width > 0 { measuredWidth = width }
                }
                // Pointer hover (iPad trackpad/mouse, Mac): rest on the thumbnail for
                // 1.5 s to start the video; moving off stops it.
                .onHover { hovering in
                    guard canHoverPreview else { return }
                    preview.hoverChanged(hovering, post: post)
                }
                // Scroll autoplay: the previewable card nearest the middle of the feed
                // plays inline (with sound, looping) once it has held the center for
                // 1 s; as the feed scrolls and a different card becomes the centered
                // one, it takes over and this one stops. Each visible card reports
                // where its media sits on every scroll frame, and the coordinator picks.
                .onGeometryChange(for: FeedAutoplayCoordinator.Placement.self) { proxy in
                    FeedAutoplayCoordinator.Placement(mediaSize: proxy.size,
                                                      viewport: proxy.bounds(of: .scrollView))
                } action: { placement in
                    isMostlyVisible = FeedAutoplayCoordinator.isEligible(placement)
                    guard canHoverPreview else {
                        FeedAutoplayCoordinator.shared.remove(post.id)
                        return
                    }
                    FeedAutoplayCoordinator.shared.update(post, placement: placement, controller: preview)
                }
            }
            .buttonStyle(.plain)
            // Warm this post's stream once the card has settled on screen so a hover
            // preview — or opening the post — starts without the usual lookup and
            // buffering delay. Released when the card scrolls away. The short wait
            // means a fast flick through the feed doesn't fire a CloudKit lookup and
            // metadata fetch for every card that flashes past (the task is cancelled
            // when the card disappears, so a card that didn't linger never warms).
            .task(id: post.id) {
                guard canHoverPreview else { return }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                FeedVideoPreloader.shared.preload(post)
            }
            .onDisappear {
                FeedAutoplayCoordinator.shared.remove(post.id)
                preview.stop()
                FeedVideoPreloader.shared.cancelPreload(for: post.id)
            }
            // Opening the post hands playback to the detail view's own player, and
            // pauses feed autoplay so nothing plays under the sheet; when it closes,
            // the coordinator re-picks the centered card (the geometry callback won't
            // fire again on its own while the feed hasn't moved).
            .onChange(of: showProjectDetail) { _, isOpen in
                if isOpen {
                    FeedAutoplayCoordinator.shared.setSuspended(true)
                    preview.stop()
                } else {
                    FeedAutoplayCoordinator.shared.setSuspended(false)
                }
            }
            // iOS pauses the player when the app leaves the foreground; pick the
            // autoplay back up when it returns if the card is still on screen.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, isMostlyVisible { preview.resumeIfNeeded() }
            }
            // Decode the thumbnail whenever its data becomes available or changes —
            // not just once on first appear. A CloudKit refresh can momentarily hand
            // back a post without its thumbnail asset (or a recycled cell can be built
            // before the data has synced), which previously left the card stuck on the
            // gradient placeholder. Keying on the data re-decodes as soon as it arrives,
            // and we keep the last good image if the data briefly drops, so thumbnails
            // never flicker away.
            .task(id: post.thumbnailData) {
                guard let thumbnailData = post.thumbnailData else { return }
                // Thumbnail data that arrives after the card was built (a CloudKit sync
                // landing on a recycled cell): size the frame from the header right now,
                // in the same frame, rather than waiting on the decode below.
                if let aspect = VideoAspectCache.thumbnailAspect(thumbnailData) {
                    headerAspect = aspect
                }
                let decoded = await Task.detached(priority: .userInitiated) {
                    UIImage(data: thumbnailData)
                }.value
                if let decoded { thumbnailImage = decoded }
                // Pick the legible Collective logo variant for this thumbnail's corner.
                if isCollectiveStudio, let decoded {
                    let light = await Task.detached(priority: .userInitiated) {
                        HomePostCard.bottomLeftIsLight(decoded)
                    }.value
                    collectiveCornerIsLight = light
                }
            }
            // Decode the rest of a gallery post's images for the carousel, downsampled to
            // the card's width so a 2000 px upload never sits in memory at full size
            // just to show a few hundred points wide. Re-runs if the files change.
            .task(id: galleryTaskKey) {
                let urls = Array(galleryURLs.dropFirst())
                guard !urls.isEmpty else {
                    galleryImages = []
                    galleryIndex = 0
                    return
                }
                let maxPixel = Int(min(2000, cardWidth * UIScreen.main.scale))
                let decoded = await Task.detached(priority: .userInitiated) {
                    urls.compactMap { HomePostCard.downsampledImage(at: $0, maxPixel: maxPixel) }
                }.value
                guard !Task.isCancelled else { return }
                galleryImages = decoded
                if galleryIndex >= decoded.count + 1 { galleryIndex = 0 }
            }
            .task(id: post.videoDuration) {
                // Show the media length. Prefer the duration stored on the post (synced
                // via CloudKit, so it works even when the media hasn't been downloaded on
                // this device); otherwise read it from the local file — the film's video
                // or the music's audio.
                guard videoDuration == nil else { return }
                if let stored = post.videoDuration, stored > 0 {
                    videoDuration = stored
                } else if (post.type == .film || post.type == .reel), let videoURL = post.videoURL {
                    videoDuration = await getVideoDuration(from: videoURL)
                } else if post.type == .music, let audioURL = post.audioURL {
                    videoDuration = await getVideoDuration(from: audioURL)
                } else if post.type == .film || post.type == .reel {
                    // Legacy film/reel: a video lives in CloudKit but its length was never
                    // synced to the feed. Resolve the stream and read just the video's
                    // metadata (a small range request, not a full download) so the timecode
                    // still shows — and only mark a film "Coming Soon" once the lookup
                    // confirms there's genuinely no video attached.
                    await resolveDurationFromStream()
                }
            }

            // Gallery posts: page dots under the carousel, as on the project page.
            if hasGallery, !galleryImages.isEmpty {
                GalleryPageDots(count: galleryPageCount, currentIndex: galleryIndex)
                    .padding(.top, 4)
                    .padding(.bottom, -8)
            }

            // Title and actions below the media
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    // Title spans the full card width (the action buttons sit on the row
                    // below it), wrapping to at most two lines before truncating.
                    Button {
                        showProjectDetail = true
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if showTypeIcon {
                                Image(systemName: typeIcon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Text(post.title)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    // Bottom-aligned so the "Directed by" credit on the left lands on the
                    // same row as the year/studio credit under the buttons on the right.
                    HStack(alignment: .bottom) {
                        // The single credit under the title — one rule per post type
                        // (see `creditLine`), e.g. "Directed by …" or "Shot by …".
                        if let credit = creditLine {
                            creditLineView(credit)
                        }

                        Spacer()

                        // Buttons on top; the studio credit sits directly beneath them.
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 8) { // Reduced from 16 to 8
                                Button {
                                    store.toggleLike(for: post)
                                } label: {
                                    // Like counts are private: only credited collaborators see them
                                    // on their own portfolio page, never on the home feed.
                                    Image(systemName: store.isLiked(post) ? "heart.fill" : "heart")
                                        .foregroundStyle(store.isLiked(post) ? .red : .primary)
                                        .font(.system(size: 21))
                                }
                                Button {
                                    showCollectionPicker = true
                                } label: {
                                    Image(systemName: store.isInAnyCollection(post) ? "bookmark.fill" : "bookmark")
                                        .font(.system(size: 21))
                                        .foregroundStyle(iconColor)
                                }
                                // Report lives in the post detail view only; the feed keeps
                                // like + save + send so the title row has more room.
                                Button {
                                    showSendMessage = true
                                } label: {
                                    Image(systemName: "paperplane")
                                        .font(.system(size: 21))
                                        .foregroundStyle(iconColor)
                                }
                            }
                            .frame(height: 22)

                            // Release year (and studio, if any) — same style as the director
                            // credit, mirrored right. e.g. "2025 • Collective".
                            if let credit = trailingCredit {
                                Text(credit)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)

                // Divider only in the padded area
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $showProjectDetail) {
            ProjectDetailView(post: post, liked: .constant(store.isLiked(post)))
        }
        .sheet(isPresented: $showSendMessage) {
            SendPostMessageView(post: post)
                .onAppear { PostAnalytics.shared.record(.message, for: post) }
        }
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerView(post: post)
        }
    }

    // MARK: - Credit line

    /// The one credit shown under a post's title, split into its lead-in and the name so
    /// the name can be styled (and, for music, linked) on its own.
    private struct CreditLine {
        let prefix: String
        let name: String
    }

    /// The single credit for this post, by type:
    /// - film / design: "Directed by <Director>", falling back to the submitter
    /// - music: "by <Artist>"
    /// - performance (reel): "by <Performer>", falling back to the submitter
    /// - photography: "Shot by <Director of Photography>", falling back to the
    ///   photographer field, then the submitter
    /// `nil` when there's nobody to credit, or for types that don't show one.
    private var creditLine: CreditLine? {
        switch post.type {
        case .film, .design:
            return firstNonEmpty(directorName, post.submittedBy)
                .map { CreditLine(prefix: "Directed by", name: $0) }
        case .music:
            return firstNonEmpty(post.artist)
                .map { CreditLine(prefix: "by", name: $0) }
        case .reel:
            return firstNonEmpty(post.artist, post.submittedBy)
                .map { CreditLine(prefix: "by", name: $0) }
        case .photography:
            return firstNonEmpty(crewName(role: "Director of Photography"), post.artist, post.submittedBy)
                .map { CreditLine(prefix: "Shot by", name: $0) }
        case .project, .event:
            return nil
        }
    }

    /// The credited Director. An exact "Director" role wins; otherwise the first role
    /// that mentions "director" (e.g. a hand-typed "Co-Director"), excluding the
    /// Director of Photography so a DP is never credited as the director.
    private var directorName: String? {
        if let exact = crewName(role: "Director") { return exact }
        let loose = post.orderedCrew.first { entry in
            let role = entry.role.lowercased()
            return role.contains("director") && !role.contains("photography")
        }?.name
        return firstNonEmpty(loose)
    }

    /// The first crew member whose role matches `role` (case-insensitively), if named.
    private func crewName(role: String) -> String? {
        let name = post.orderedCrew.first {
            $0.role.caseInsensitiveCompare(role) == .orderedSame
        }?.name
        return firstNonEmpty(name)
    }

    /// The first candidate that isn't blank, trimmed.
    private func firstNonEmpty(_ candidates: String?...) -> String? {
        for candidate in candidates {
            if let trimmed = candidate?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    /// Renders a credit at the feed's 14 pt secondary style. Tapping the line opens the
    /// post. Names are never highlighted or linked on the feed — profile links live on
    /// the post detail pages (`CreditNameView`).
    private func creditLineView(_ credit: CreditLine) -> some View {
        Button {
            showProjectDetail = true
        } label: {
            Text("\(credit.prefix) \(credit.name)")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }
    
    /// Whether this card can play an inline preview: a film or reel with a video that
    /// isn't withheld (festival-bound) or confirmed missing, or a music post (its
    /// track autoplays audibly).
    private var canHoverPreview: Bool {
        FeedVideoPreloader.isPreviewable(post) && !filmConfirmedNoVideo
    }

    /// True while an inline preview (video or audio) is actually playing on this card.
    private var isPreviewPlaying: Bool {
        preview.player != nil
    }

    // Helper function to get video duration
    private func getVideoDuration(from url: URL) async -> Double {
        let asset = AVAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return duration.seconds
        } catch {
            print("Error getting video duration: \(error.localizedDescription)")
            return 0
        }
    }
    
    // Helper function to format duration as MM:SS
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// True for a film credited to the "Collective" studio, which gets the Collective
    /// logo overlaid on its thumbnail.
    private var isCollectiveStudio: Bool {
        post.type == .film && post.studio.trimmingCharacters(in: .whitespaces) == "Collective"
    }

    /// True for a film credited to the "Incubator" studio, which gets the Incubator egg
    /// overlaid on its thumbnail in the same corner as the Collective logo.
    private var isIncubatorStudio: Bool {
        post.type == .film && post.studio.trimmingCharacters(in: .whitespaces) == "Incubator"
    }

    /// The swipeable gallery for a photography/design post with several images. Page 0 is
    /// the thumbnail at its own aspect ratio; the rest share `galleryRestAspect` (the
    /// tallest image's), so each fits uncropped inside one stable frame. The surrounding
    /// Button still opens the post on tap — the pager's pan only claims horizontal swipes,
    /// and the feed's vertical scroll is untouched.
    private var galleryPager: some View {
        TabView(selection: $galleryIndex) {
            ForEach(0..<galleryPageCount, id: \.self) { index in
                Group {
                    if index == 0, let thumbnailImage {
                        Image(uiImage: thumbnailImage)
                            .resizable()
                            .scaledToFit()
                    } else if index > 0, galleryImages.indices.contains(index - 1) {
                        Image(uiImage: galleryImages[index - 1])
                            .resizable()
                            .scaledToFit()
                    } else {
                        Rectangle()
                            .fill(LinearGradient(colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    /// Decodes a gallery image straight to feed size — at most `maxPixel` on its longer
    /// side — via ImageIO, so the full-resolution bitmap is never materialised. Pure
    /// work; runs off the main actor.
    nonisolated static func downsampledImage(at url: URL, maxPixel: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Whether the bottom-left corner of an image (where the Collective logo sits) is
    /// close to white — averaged over that corner region. Used to swap the white logo
    /// for the black one so it stays visible. Runs off the main actor (pure work).
    nonisolated static func bottomLeftIsLight(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return false }
        // Bottom-left ~30% × ~30% region (CGImage origin is top-left).
        let regionW = max(1, Int(Double(w) * 0.30))
        let regionH = max(1, Int(Double(h) * 0.30))
        let rect = CGRect(x: 0, y: h - regionH, width: regionW, height: regionH)
        guard let cropped = cg.cropping(to: rect) else { return false }

        // Average the region down to a single pixel.
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let r = Double(pixel[0]), g = Double(pixel[1]), b = Double(pixel[2])
        let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
        return luminance > 0.7
    }

    /// The studio to credit under the action row, or nil when there's nothing distinct
    /// to show. Only a specific studio is surfaced — an empty value or the default
    /// "Independent" reads as "no studio" and is omitted. A class project is credited by
    /// its course code alone (e.g. "RTF 304D"), since the full class name is too long for the
    /// feed; the post detail still shows the whole name.
    private var distinctStudioName: String? {
        let name = post.studio.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != "Independent" else { return nil }
        return ProductionClassCatalog.code(for: name) ?? name
    }

    /// True for one of Collective's magazines, matched by title against the hardcoded
    /// catalog. They're identified as Collective's rather than by a release year.
    private var isCollectiveMagazine: Bool {
        let key = CollectiveStudios.normalize(post.title)
        return OrgProjectCatalog.projects(orgSlug: "collective", section: .magazines)
            .contains { CollectiveStudios.normalize($0.title) == key }
    }

    /// The trailing credit shown under the action buttons: the release year, then the
    /// studio if there's a distinct one — e.g. "2025 • Collective", or just "2025", or
    /// just the studio. For a Collective Weekly Short the season/episode code is prefixed
    /// to the left, e.g. "S1E1 • 2025 • Collective". `nil` when there's nothing to show.
    private var trailingCredit: String? {
        // Collective's magazines read just "Collective" — no year.
        if isCollectiveMagazine { return "Collective" }

        let year = post.releaseYear.trimmingCharacters(in: .whitespaces)
        let base: String?
        switch (year.isEmpty, distinctStudioName) {
        case (false, .some(let studio)): base = "\(year) • \(studio)"
        case (false, .none):             base = year
        case (true, .some(let studio)):  base = studio
        case (true, .none):              base = nil
        }

        if let code = CollectiveStudios.episodeCode(forTitle: post.title) {
            return base.map { "\(code) • \($0)" } ?? code
        }
        return base
    }

    /// Resolves a legacy film/reel's video length when it wasn't synced to the feed. Asks
    /// the streaming layer for the asset's CDN URL and reads only the video's metadata (a
    /// small range request, not a full download) so the timecode badge can show. If the
    /// lookup reports no asset at all, the film is genuinely awaiting its video, so
    /// `filmConfirmedNoVideo` drives the "Coming Soon" badge. Transient/errored lookups
    /// leave the badge off rather than mislabel the post.
    private func resolveDurationFromStream() async {
        let (resolution, _) = await CloudKitManager.shared.streamResolutionDetailed(
            submissionID: post.id, type: post.type
        )
        switch resolution {
        case .streaming(let url):
            let seconds = await getVideoDuration(from: url)
            if seconds > 0 { videoDuration = seconds }
        case .assetMissing:
            filmConfirmedNoVideo = true
        default:
            break
        }
    }

    /// The rounded black pill in the thumbnail's corner — holds either the media length
    /// or, for a video-less film, "Coming Soon".
    private func durationBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(.black.opacity(0.7))
            )
            .padding(8)
            // Nudge in from the trailing edge so the pill doesn't kiss the card border.
            .padding(.trailing, 4)
    }

    /// Gallery-post counterpart of `durationBadge`: the same pill in the same corner,
    /// holding a stack icon and the position in the gallery ("2/5"), or just the count
    /// when no position is known yet.
    private func photoCountBadge(_ position: Int?, of count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "square.on.square")
                .font(.caption2)
            Text(position.map { "\($0)/\(count)" } ?? "\(count)")
                .font(.caption)
                .monospacedDigit()
        }
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(.black.opacity(0.7))
        )
        .padding(8)
        .padding(.trailing, 4)
    }
}

/// Reports a feed card's measured width so the thumbnail height can be derived from it.
private struct CardWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
