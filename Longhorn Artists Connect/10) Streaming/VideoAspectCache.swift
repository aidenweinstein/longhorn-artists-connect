//
//  VideoAspectCache.swift
//  Longhorn Artists Connect
//
//  Remembers the shape of every video the app has seen so a detail view can open
//  its inline player at the video's real aspect ratio on the very first frame,
//  instead of starting at 16:9 and snapping once the track's natural size loads.
//
//  Sources, in order of trust:
//    1. A natural size read from the video track itself — recorded by the feed
//       preloader (which already pulls the container metadata) and by every
//       detail view / player surface that loads it. Persisted across launches.
//    2. The post's thumbnail. At upload the poster is the video's first frame,
//       cropped the same way as the playback crop, so its pixel shape matches
//       what the player will show. Read from the image header without decoding.
//

import SwiftUI
import AVFoundation
import ImageIO

final class VideoAspectCache {
    static let shared = VideoAspectCache()

    private static let defaultsKey = "videoNaturalAspects"

    /// Upright, uncropped width ÷ height per submission ID.
    private var aspects: [String: CGFloat]

    private init() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Double] ?? [:]
        aspects = stored.mapValues { CGFloat($0) }
    }

    // MARK: Lookup

    /// The video's upright, uncropped width ÷ height, if it has been seen before.
    func naturalAspect(for id: UUID) -> CGFloat? {
        aspects[id.uuidString]
    }

    /// The shape the inline player should open at for `post`: the known natural
    /// aspect with the post's playback crop applied, else the thumbnail's shape.
    /// `nil` only when neither is available (callers fall back to 16:9).
    func displayAspect(for post: Submission) -> CGFloat? {
        if let natural = naturalAspect(for: post.id) {
            return Self.applyingCrop(post.videoCrop, to: natural)
        }
        return Self.thumbnailAspect(post.thumbnailData)
    }

    // MARK: Recording

    /// Remembers `aspect` as the natural shape of `id`'s video.
    func store(_ aspect: CGFloat, for id: UUID) {
        guard aspect.isFinite, aspect > 0 else { return }
        if let existing = aspects[id.uuidString], abs(existing - aspect) < 0.001 { return }
        aspects[id.uuidString] = aspect
        UserDefaults.standard.set(aspects.mapValues { Double($0) }, forKey: Self.defaultsKey)
    }

    /// Reads the natural aspect from `asset`, records it for `post`, and returns the
    /// display aspect (crop applied). `nil` if the track can't be read.
    func learn(_ post: Submission, from asset: AVAsset) async -> CGFloat? {
        guard let natural = await Self.naturalAspect(of: asset) else { return nil }
        store(natural, for: post.id)
        return Self.applyingCrop(post.videoCrop, to: natural)
    }

    // MARK: Helpers

    /// The display shape of a video with `natural` aspect once the post's playback
    /// crop (if any) is applied.
    static func applyingCrop(_ encodedCrop: String?, to natural: CGFloat) -> CGFloat {
        guard let crop = VideoCrop(encodedCrop) else { return natural }
        return natural * crop.rect.width / crop.rect.height
    }

    /// The asset's first video track's upright width ÷ height.
    static func naturalAspect(of asset: AVAsset) async -> CGFloat? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        return await naturalAspect(of: track)
    }

    /// The track's upright width ÷ height (its orientation transform applied).
    static func naturalAspect(of track: AVAssetTrack) async -> CGFloat? {
        guard let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
        let upright = size.applying(transform)
        let width = abs(upright.width)
        let height = abs(upright.height)
        guard width > 0, height > 0 else { return nil }
        return width / height
    }

    /// The thumbnail's pixel width ÷ height, read from the image header (no decode).
    /// Honors an EXIF orientation that turns the image on its side.
    static func thumbnailAspect(_ data: Data?) -> CGFloat? {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        // EXIF orientations 5–8 are rotated 90°, swapping the displayed width and height.
        let isSideways = (5...8).contains(orientation)
        return CGFloat(isSideways ? height / width : width / height)
    }
}
