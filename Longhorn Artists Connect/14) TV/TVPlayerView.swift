//
//  TVPlayerView.swift
//  Longhorn Artists Connect
//

import AVKit
import SwiftUI

/// Full-screen playback in the system player. Menu on the Siri Remote closes it.
struct TVPlayerView: View {
    let video: TVVideo
    let viewer: TVViewer

    @State private var player: AVPlayer?
    @State private var isUnavailable = false
    @State private var timeObserver: Any?
    @State private var engagement = PlaybackEngagementTracker()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if isUnavailable {
                ContentUnavailableView(
                    "Video Unavailable",
                    systemImage: "film",
                    description: Text("“\(video.title)” can't be played right now.")
                )
            } else {
                ProgressView()
            }
        }
        .task { await start() }
        .onDisappear(perform: stop)
    }

    private func start() async {
        TVWatchRecorder.shared.record(.open, for: video, by: viewer)

        guard let url = await video.streamURL() else {
            isUnavailable = true
            return
        }

        let item = AVPlayerItem(url: url)
        item.externalMetadata = metadata
        let player = AVPlayer(playerItem: item)

        // Counts only time that actually played (see `PlaybackEngagementTracker`), so
        // scrubbing to the end isn't a full watch.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { time in
            MainActor.assumeIsolated {
                let duration = player.currentItem?.duration.seconds ?? video.duration ?? 0
                let crossed = engagement.update(time: time.seconds, duration: duration)
                crossed.forEach { TVWatchRecorder.shared.record($0, for: video, by: viewer) }
            }
        }

        self.player = player
        player.play()
    }

    private func stop() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.pause()
    }

    /// Title and credit for the player's info panel.
    private var metadata: [AVMetadataItem] {
        var items = [metadataItem(.commonIdentifierTitle, video.title)]
        let credit = [video.creator, video.schoolName].filter { !$0.isEmpty }.joined(separator: " · ")
        if !credit.isEmpty { items.append(metadataItem(.iTunesMetadataTrackSubTitle, credit)) }
        if !video.summary.isEmpty { items.append(metadataItem(.commonIdentifierDescription, video.summary)) }
        return items
    }

    private func metadataItem(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }
}
