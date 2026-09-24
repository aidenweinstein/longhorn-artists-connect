//
//  HomePostCard.swift
//  Longhorn Artists Connect
//
//  Card view for posts in the home feed
//

import SwiftUI
import AVKit

struct HomePostCard: View {
    let post: Submission
    let showTypeIcon: Bool
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @State private var showOptions = false
    @State private var showProjectDetail = false
    @State private var showSendMessage = false
    @State private var showReportSheet = false
    @State private var showCollectionPicker = false
    @State private var videoDuration: Double?
    /// Set true only once a stream lookup confirms a film genuinely has no video attached,
    /// so the "Coming Soon" badge never shows merely because a legacy film's length was
    /// never synced to the feed.
    @State private var filmConfirmedNoVideo = false
    @State private var thumbnailImage: UIImage? // Cache the image
    /// True when the thumbnail's bottom-left corner (where the Collective logo sits) is
    /// close to white, so the white logo would be hard to see and the black one is used.
    @State private var collectiveCornerIsLight = false
    /// The card's measured width. The thumbnail height is derived purely from this and
    /// the media's aspect ratio, so nothing about the proposed *height* (e.g. the search
    /// keyboard shrinking the feed) can make the card narrower than the normal feed.
    /// Seeded with the full screen width — the feed is full-bleed, so this is already
    /// exact before the measurement lands and the first layout has the right height.
    @State private var cardWidth: CGFloat = UIScreen.main.bounds.width
    @Environment(\.colorScheme) private var colorScheme

    /// The thumbnail's natural aspect ratio (width ÷ height); falls back to 16:9 before
    /// the image loads or for the gradient placeholder.
    private var thumbnailAspect: CGFloat {
        if let img = thumbnailImage, img.size.width > 0, img.size.height > 0 {
            return img.size.width / img.size.height
        }
        return 16.0 / 9.0
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
            return "star.fill"
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
                    .frame(height: cardWidth / thumbnailAspect)
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
                        durationBadge(formatDuration(duration))
                    } else if post.type == .film, !post.festivalBound, filmConfirmedNoVideo {
                        durationBadge("Coming Soon")
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
                    if width > 0 { cardWidth = width }
                }
            }
            .buttonStyle(.plain)
            // Decode the thumbnail whenever its data becomes available or changes —
            // not just once on first appear. A CloudKit refresh can momentarily hand
            // back a post without its thumbnail asset (or a recycled cell can be built
            // before the data has synced), which previously left the card stuck on the
            // gradient placeholder. Keying on the data re-decodes as soon as it arrives,
            // and we keep the last good image if the data briefly drops, so thumbnails
            // never flicker away.
            .task(id: post.thumbnailData) {
                guard let thumbnailData = post.thumbnailData else { return }
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

            // Title and actions below the media
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Button {
                        showProjectDetail = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                if showTypeIcon {
                                    Image(systemName: typeIcon)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Text(post.title)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                            
                            // Show credit based on post type
                            if post.type == .film {
                                // For film, find director from crew
                                if let director = post.orderedCrew.first(where: { $0.role.lowercased().contains("director") }) {
                                    Text("Directed by \(director.name)")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else if !post.submittedBy.isEmpty {
                                    // Fallback to submitter if no director found
                                    Text("Directed by \(post.submittedBy)")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            } else if post.type == .music {
                                // For music, show artist if available
                                if !post.artist.isEmpty {
                                    Text("By \(post.artist)")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            } else if post.type == .photography {
                                // For photography, credit the photographer (falling back
                                // to the submitter).
                                if !post.artist.isEmpty {
                                    Text("By \(post.artist)")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else if !post.submittedBy.isEmpty {
                                    Text("By \(post.submittedBy)")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            } else if post.type == .reel {
                                // For reel, credit the artist (falling back to the submitter).
                                if !post.artist.isEmpty {
                                    Text("By \(post.artist)")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else if !post.submittedBy.isEmpty {
                                    Text("By \(post.submittedBy)")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Buttons on top; the studio credit sits directly beneath them so it
                    // lands on the same row as the "Directed by" credit on the left (both
                    // columns are top-aligned, so their second rows line up).
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
                            Button {
                                showSendMessage = true
                            } label: {
                                Image(systemName: "paperplane")
                                    .font(.system(size: 21))
                                    .foregroundStyle(iconColor)
                            }
                            Button {
                                showReportSheet = true
                            } label: {
                                Image(systemName: "flag")
                                    .font(.system(size: 21))
                                    .foregroundStyle(iconColor)
                            }
                        }
                        // Pin the button row to the title's line height so it sits near the
                        // top edge and the studio credit below lines up with the "Directed
                        // by" credit on the left.
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
        }
        .sheet(isPresented: $showReportSheet) {
            ReportContentView(post: post)
        }
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerView(post: post)
        }
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
}

/// Reports a feed card's measured width so the thumbnail height can be derived from it.
private struct CardWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
