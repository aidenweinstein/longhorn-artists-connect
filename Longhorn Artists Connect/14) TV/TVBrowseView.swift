//
//  TVBrowseView.swift
//  Longhorn Artists Connect
//

import SwiftUI

/// Top tabs: Search, "All", then one per school that has videos.
struct TVBrowseView: View {
    let catalog: TVCatalog
    let viewer: TVViewer

    @State private var selectedTab = Self.allTab
    @State private var playing: TVVideo?

    private static let searchTab = "search"
    private static let allTab = "all"

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: Self.searchTab, role: .search) {
                TVSearchView(catalog: catalog, play: { playing = $0 })
            }
            Tab(value: Self.allTab) {
                shelves(for: nil)
            } label: {
                Text("All")
            }
            ForEach(catalog.schools, id: \.slug) { school in
                Tab(value: school.slug) {
                    shelves(for: school.slug)
                } label: {
                    Text(school.name)
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

/// Films in a grid that grows to fit them all, then a Performances shelf.
struct TVShelvesView: View {
    let videos: [TVVideo]
    let thumbnails: [UUID: UIImage]
    let showsSchool: Bool
    let play: (TVVideo) -> Void

    /// Three cards across at 1080p, with room to lift on focus.
    static let gridColumns = [GridItem(.adaptive(minimum: 440, maximum: 560), spacing: 48, alignment: .top)]

    var body: some View {
        let films = videos.filter { $0.kind == .film }
        let performances = videos.filter { $0.kind == .reel }

        if films.isEmpty && performances.isEmpty {
            ContentUnavailableView("No Videos Yet", systemImage: "film.stack")
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 60) {
                    if !films.isEmpty {
                        VStack(alignment: .leading, spacing: 24) {
                            Text(TVVideo.Kind.film.shelfTitle)
                                .font(.title3.bold())
                            LazyVGrid(columns: Self.gridColumns, alignment: .leading, spacing: 48) {
                                ForEach(films) { video in
                                    card(for: video)
                                }
                            }
                            .padding(.vertical, 30)
                        }
                    }
                    if !performances.isEmpty {
                        VStack(alignment: .leading, spacing: 24) {
                            Text(TVVideo.Kind.reel.shelfTitle)
                                .font(.title3.bold())
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 48) {
                                    ForEach(performances) { video in
                                        card(for: video)
                                            .frame(width: 480)
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
            .scrollClipDisabled()
        }
    }

    private func card(for video: TVVideo) -> some View {
        TVVideoCard(
            video: video,
            thumbnail: thumbnails[video.id],
            showsSchool: showsSchool,
            play: { play(video) }
        )
    }
}

/// Search by title, creator or school, with results in the same grid as Films.
struct TVSearchView: View {
    let catalog: TVCatalog
    let play: (TVVideo) -> Void

    @State private var query = ""

    private var results: [TVVideo] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        return catalog.videos.filter { video in
            video.title.localizedCaseInsensitiveContains(needle)
                || video.creator.localizedCaseInsensitiveContains(needle)
                || video.schoolName.localizedCaseInsensitiveContains(needle)
                || SchoolRegistry.name(forSlug: video.schoolID).localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        Group {
            if query.isEmpty {
                ContentUnavailableView("Search Nexus", systemImage: "magnifyingglass", description: Text("Find a film or performance by title, who made it, or school."))
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: TVShelvesView.gridColumns, alignment: .leading, spacing: 48) {
                        ForEach(results) { video in
                            TVVideoCard(
                                video: video,
                                thumbnail: catalog.thumbnails[video.id],
                                showsSchool: true,
                                play: { play(video) }
                            )
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 40)
                }
                .scrollClipDisabled()
            }
        }
        .searchable(text: $query, prompt: "Titles, people, schools")
    }
}

/// A 16:9 thumbnail that lifts on focus, with the title and credit under it.
/// Fills whatever width its grid cell or shelf gives it.
struct TVVideoCard: View {
    let video: TVVideo
    let thumbnail: UIImage?
    let showsSchool: Bool
    let play: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: play) {
                artwork
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let thumbnail {
            Color.clear.overlay {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            }
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
        TVVideo(kind: .film, title: "Night Shift", creator: "Dana Whitfield", schoolID: "umich", duration: 912),
        TVVideo(kind: .reel, title: "Cinematography Reel 2026", creator: "Alex Kim", schoolID: "umich", duration: 95),
        TVVideo(kind: .reel, title: "Acting Reel", creator: "Riley Chen", schoolID: "ut-austin", duration: 120),
        TVVideo(kind: .reel, title: "Editing Reel", creator: "Taylor Brooks", schoolID: "berkeley", duration: 84)
    ]
}

#Preview("Browse") {
    TVBrowseView(
        catalog: TVCatalog(previewVideos: TVVideo.previewVideos),
        viewer: TVViewer(userRecordName: "preview", name: "Preview Viewer")
    )
}
