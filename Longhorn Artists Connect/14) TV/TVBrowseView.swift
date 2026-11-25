//
//  TVBrowseView.swift
//  Longhorn Artists Connect
//

import SwiftUI

/// Top tabs: "All", then one per school that has videos.
struct TVBrowseView: View {
    let catalog: TVCatalog
    let viewer: TVViewer

    @State private var selectedTab = Self.allTab
    @State private var playing: TVVideo?

    private static let allTab = "all"

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("All", value: Self.allTab) {
                shelves(for: nil)
            }
            ForEach(catalog.schools, id: \.slug) { school in
                Tab(school.name, value: school.slug) {
                    shelves(for: school.slug)
                }
            }
        }
        .task { await catalog.load() }
        .fullScreenCover(item: $playing) { video in
            TVPlayerView(video: video, viewer: viewer)
        }
    }

    @ViewBuilder
    private func shelves(for school: String?) -> some View {
        switch catalog.phase {
        case .loading:
            ProgressView()
        case .failed(let reason):
            ContentUnavailableView("Couldn't Load Videos", systemImage: "wifi.exclamationmark", description: Text(reason))
        case .loaded:
            TVShelvesView(
                videos: catalog.videos(inSchool: school),
                thumbnails: catalog.thumbnails,
                showsSchool: school == nil,
                play: { playing = $0 }
            )
        }
    }
}

/// A Films shelf and a Reels shelf.
struct TVShelvesView: View {
    let videos: [TVVideo]
    let thumbnails: [UUID: UIImage]
    let showsSchool: Bool
    let play: (TVVideo) -> Void

    var body: some View {
        let shelves = TVVideo.Kind.allCases
            .map { kind in (kind, videos.filter { $0.kind == kind }) }
            .filter { !$0.1.isEmpty }

        if shelves.isEmpty {
            ContentUnavailableView("No Videos Yet", systemImage: "film.stack")
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 60) {
                    ForEach(shelves, id: \.0) { kind, videos in
                        VStack(alignment: .leading, spacing: 24) {
                            Text(kind.shelfTitle)
                                .font(.title3.bold())
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 48) {
                                    ForEach(videos) { video in
                                        TVVideoCard(
                                            video: video,
                                            thumbnail: thumbnails[video.id],
                                            showsSchool: showsSchool,
                                            play: { play(video) }
                                        )
                                    }
                                }
                                .padding(.vertical, 30)
                            }
                            .scrollClipDisabled()
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
            }
        }
    }
}

/// A 16:9 thumbnail that lifts on focus, with the title and credit under it.
struct TVVideoCard: View {
    let video: TVVideo
    let thumbnail: UIImage?
    let showsSchool: Bool
    let play: () -> Void

    private static let width: CGFloat = 480

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: play) {
                artwork
                    .frame(width: Self.width, height: Self.width * 9 / 16)
                    .overlay(alignment: .bottomTrailing) {
                        if let duration = video.duration, duration > 0 {
                            Text(Duration.seconds(duration).formatted(.time(pattern: duration >= 3600 ? .hourMinuteSecond : .minuteSecond)))
                                .font(.caption2.monospacedDigit().bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.7), in: .capsule)
                                .foregroundStyle(.white)
                                .padding(12)
                        }
                    }
            }
            .buttonStyle(.card)

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(credit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: Self.width, alignment: .leading)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: video.kind == .film ? "film" : "play.rectangle")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var credit: String {
        [video.creator, showsSchool ? video.schoolName : nil]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }
}

// MARK: - Previews

extension TVVideo {
    static let previewVideos: [TVVideo] = [
        TVVideo(kind: .film, title: "Golden Hour", creator: "Maya Torres", schoolID: "ut-austin", duration: 742),
        TVVideo(kind: .film, title: "The Last Bus Home", creator: "Jordan Lee", schoolID: "berkeley", duration: 1265),
        TVVideo(kind: .film, title: "Static", creator: "Priya Shah", schoolID: "usc", duration: 3720),
        TVVideo(kind: .film, title: "Paper Cranes", creator: "Sam Okafor", schoolID: "ut-austin", duration: 488),
        TVVideo(kind: .reel, title: "Cinematography Reel 2026", creator: "Alex Kim", schoolID: "umich", duration: 95),
        TVVideo(kind: .reel, title: "Acting Reel", creator: "Riley Chen", schoolID: "ut-austin", duration: 120),
        TVVideo(kind: .reel, title: "Editing Reel", creator: "Taylor Brooks", schoolID: "berkeley", duration: 84)
    ]
}

#Preview("Browse") {
    TVBrowseView(
        catalog: TVCatalog(previewVideos: TVVideo.previewVideos),
        viewer: TVViewer(userID: "preview", name: "Preview Viewer")
    )
}
