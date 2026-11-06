//
//  MediaCropView.swift
//  Longhorn Artists Connect
//
//  The shared upload-row controls (Photos/Files pickers, swapped for Crop + Trash once
//  something is picked) and the full-screen crop editor used for photos and videos.
//

import SwiftUI
import AVFoundation
import CoreImage

// MARK: - Upload Picker Buttons

/// The trailing buttons on a submission upload row. With nothing picked it shows the
/// Photos and/or Files pickers; once something is picked they're replaced by a trash
/// button (clears the selection, bringing the pickers back) and — for photos and
/// videos — a crop button to its left.
struct UploadPickerButtons: View {
    /// Whether the row currently holds a selection.
    let hasSelection: Bool
    /// Opens the Photos picker. `nil` hides the button (e.g. audio, which is Files-only).
    var onPhotos: (() -> Void)? = nil
    /// Opens the Files picker. `nil` hides the button.
    var onFiles: (() -> Void)? = nil
    /// Opens the crop editor. `nil` hides the button (non-visual media, or media that
    /// isn't on disk to crop).
    var onCrop: (() -> Void)? = nil
    /// Clears the current selection.
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if hasSelection {
                if let onCrop {
                    Button(action: onCrop) {
                        Label("Crop", systemImage: "crop")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }

                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                if let onPhotos {
                    Button(action: onPhotos) {
                        Label("Photos", systemImage: "photo.stack")
                            .labelStyle(.iconOnly)
                            .symbolRenderingMode(.multicolor)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }

                if let onFiles {
                    Button(action: onFiles) {
                        Label("Files", systemImage: "folder")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }
            }
        }
    }
}

// MARK: - Crop Request

/// What to crop and where to hand the result. Presented with `.mediaCropper(_:)`.
struct MediaCropRequest: Identifiable {
    enum Source {
        case image(UIImage)
        /// A video, cropped on its first frame. `preview` (if any) is shown right away;
        /// `load` produces the video file — immediately for a picked video, or after a
        /// download for an already-posted one that isn't on disk.
        case video(preview: UIImage?, load: () async -> URL?)
        /// A video cropped at playback rather than re-encoded: the editor only needs the
        /// first frame to frame the box, and hands back the rect. `load` yields any URL
        /// the first frame can be read from — a local file or the streaming link — so a
        /// posted video never has to be downloaded. `initial` is the current crop.
        case playbackCrop(preview: UIImage?, load: () async -> URL?, initial: CGRect?)
    }

    let id = UUID()
    let source: Source
    fileprivate let onImageCropped: (UIImage) -> Void
    fileprivate let onVideoCropped: (URL) -> Void
    fileprivate let onPlaybackCrop: (VideoCrop?) -> Void

    private init(source: Source,
                 onImageCropped: @escaping (UIImage) -> Void = { _ in },
                 onVideoCropped: @escaping (URL) -> Void = { _ in },
                 onPlaybackCrop: @escaping (VideoCrop?) -> Void = { _ in }) {
        self.source = source
        self.onImageCropped = onImageCropped
        self.onVideoCropped = onVideoCropped
        self.onPlaybackCrop = onPlaybackCrop
    }

    /// Crop a still image; `onCropped` receives the cropped image.
    static func image(_ image: UIImage, onCropped: @escaping (UIImage) -> Void) -> MediaCropRequest {
        MediaCropRequest(source: .image(image), onImageCropped: onCropped)
    }

    /// Frame a playback crop for a video. `onCropped` receives the chosen crop, or `nil`
    /// when the whole frame is kept.
    static func playbackCrop(preview: UIImage?,
                             load: @escaping () async -> URL?,
                             current: VideoCrop?,
                             onCropped: @escaping (VideoCrop?) -> Void) -> MediaCropRequest {
        MediaCropRequest(source: .playbackCrop(preview: preview, load: load, initial: current?.rect),
                         onPlaybackCrop: onCropped)
    }

    /// Crop a video; `onCropped` receives the URL of a newly-exported cropped copy.
    static func video(_ url: URL, onCropped: @escaping (URL) -> Void) -> MediaCropRequest {
        video(preview: nil, load: { url }, onCropped: onCropped)
    }

    /// Crop a video whose file may still need fetching. The editor opens on `preview`
    /// straight away and swaps in the video's real first frame once `load` finishes.
    static func video(preview: UIImage?,
                      load: @escaping () async -> URL?,
                      onCropped: @escaping (URL) -> Void) -> MediaCropRequest {
        MediaCropRequest(source: .video(preview: preview, load: load), onVideoCropped: onCropped)
    }
}

extension View {
    /// Presents the crop editor full-screen whenever `request` is set.
    func mediaCropper(_ request: Binding<MediaCropRequest?>) -> some View {
        fullScreenCover(item: request) { request in
            MediaCropView(request: request)
        }
    }
}

// MARK: - Crop Aspect

/// Aspect-ratio presets offered under the crop editor.
private enum CropAspect: String, CaseIterable, Identifiable {
    case free = "Free"
    case widescreen = "16:9"
    case fourThree = "4:3"
    case threeTwo = "3:2"
    case square = "1:1"

    var id: String { rawValue }

    /// Width ÷ height in pixels, or `nil` for a free-form crop.
    func ratio(for mediaSize: CGSize) -> CGFloat? {
        switch self {
        case .free:       return nil
        case .widescreen: return 16.0 / 9.0
        case .fourThree:  return 4.0 / 3.0
        case .threeTwo:   return 3.0 / 2.0
        case .square:     return 1
        }
    }
}

// MARK: - Crop View

/// Full-screen crop editor. Shows the image (or a video's first frame) with a movable,
/// resizable crop box. The box is tracked in normalized 0…1 coordinates of the upright
/// media, so the same rect crops either the full-resolution image or every video frame.
struct MediaCropView: View {
    let request: MediaCropRequest

    @Environment(\.dismiss) private var dismiss

    /// What's shown under the crop box: the image itself, or the video's first frame.
    @State private var preview: UIImage?
    /// The crop box, normalized to the media (0…1 on both axes, origin top-left).
    @State private var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var aspect: CropAspect = .free
    /// The crop box when the current drag began, so drags apply relative to it.
    @State private var dragStartRect: CGRect?
    @State private var isExporting = false
    @State private var errorMessage: String?
    /// The video file once loaded, and the in-flight load (so Done can wait on it).
    @State private var videoFileURL: URL?
    @State private var videoLoad: Task<URL?, Never>?
    @State private var videoLoadFinished = false

    /// Smallest the crop box may get, as a fraction of each side.
    private let minimumSide: CGFloat = 0.1
    private let handleSize: CGFloat = 28

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let preview {
                    GeometryReader { proxy in
                        cropCanvas(image: preview, in: proxy.size)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    aspectPicker(mediaSize: preview.size)

                    if isWaitingForVideo {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                            Text("Loading full video…")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                } else {
                    Spacer()
                    ProgressView("Loading first frame…")
                        .tint(.white)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                }
            }
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isExporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isExporting {
                        ProgressView()
                    } else {
                        Button("Done") { applyCrop() }
                            .fontWeight(.semibold)
                            .disabled(preview == nil)
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset") {
                        aspect = .free
                        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                    }
                    .disabled(isExporting)
                }
            }
            .alert("Couldn't Crop", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .task { await loadPreview() }
    }

    /// True while a video's file is still being fetched behind the first-frame preview.
    private var isWaitingForVideo: Bool {
        // Only the export crop needs the whole file; a playback crop just needs the frame.
        if case .video = request.source { return !videoLoadFinished }
        return false
    }

    // MARK: Canvas

    /// The media fitted into `available`, with the dimmed surround, crop box, grid, and
    /// corner handles laid over it.
    private func cropCanvas(image: UIImage, in available: CGSize) -> some View {
        let fitted = fittedSize(for: image.size, in: available)
        let box = CGRect(x: cropRect.minX * fitted.width,
                         y: cropRect.minY * fitted.height,
                         width: cropRect.width * fitted.width,
                         height: cropRect.height * fitted.height)

        return ZStack(alignment: .topLeading) {
            Image(uiImage: image)
                .resizable()
                .frame(width: fitted.width, height: fitted.height)

            // Dim everything outside the crop box (even-odd fill punches the hole).
            Path { path in
                path.addRect(CGRect(origin: .zero, size: fitted))
                path.addRect(box)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            // The box itself: dragging inside it moves it.
            cropGrid
                .frame(width: box.width, height: box.height)
                .contentShape(Rectangle())
                .offset(x: box.minX, y: box.minY)
                .gesture(moveGesture(canvas: fitted))

            ForEach(Corner.allCases, id: \.self) { corner in
                cornerHandle(corner)
                    .position(corner.point(in: box))
                    .gesture(resizeGesture(corner: corner, canvas: fitted, mediaSize: image.size))
            }
        }
        .frame(width: fitted.width, height: fitted.height)
        .frame(width: available.width, height: available.height)
    }

    /// Rule-of-thirds grid inside a white border.
    private var cropGrid: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Path { path in
                for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                    path.move(to: CGPoint(x: size.width * fraction, y: 0))
                    path.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                    path.move(to: CGPoint(x: 0, y: size.height * fraction))
                    path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                }
            }
            .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
        }
        .overlay(Rectangle().stroke(Color.white, lineWidth: 1.5))
    }

    private func cornerHandle(_ corner: Corner) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 14, height: 14)
            .shadow(radius: 2)
            // A larger invisible hit area than the dot itself.
            .frame(width: handleSize, height: handleSize)
            .contentShape(Rectangle())
    }

    /// Aspect presets, shown as a row of capsules under the canvas.
    private func aspectPicker(mediaSize: CGSize) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CropAspect.allCases) { option in
                    Button {
                        aspect = option
                        if let ratio = option.ratio(for: mediaSize) {
                            cropRect = centeredRect(ratio: normalizedRatio(ratio, mediaSize: mediaSize))
                        }
                    } label: {
                        Text(option.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(aspect == option ? Color.black : Color.white)
                            .background(Capsule().fill(aspect == option ? Color.white : Color.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .disabled(isExporting)
    }

    // MARK: Gestures

    private func moveGesture(canvas: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStartRect ?? cropRect
                if dragStartRect == nil { dragStartRect = start }
                let dx = value.translation.width / canvas.width
                let dy = value.translation.height / canvas.height
                cropRect.origin = CGPoint(
                    x: min(max(start.minX + dx, 0), 1 - start.width),
                    y: min(max(start.minY + dy, 0), 1 - start.height)
                )
            }
            .onEnded { _ in dragStartRect = nil }
    }

    private func resizeGesture(corner: Corner, canvas: CGSize, mediaSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStartRect ?? cropRect
                if dragStartRect == nil { dragStartRect = start }
                let delta = CGSize(width: value.translation.width / canvas.width,
                                   height: value.translation.height / canvas.height)
                let lockedRatio = aspect.ratio(for: mediaSize).map { normalizedRatio($0, mediaSize: mediaSize) }
                cropRect = resized(start, corner: corner, by: delta, normalizedRatio: lockedRatio)
            }
            .onEnded { _ in dragStartRect = nil }
    }

    /// Moves `corner` of `start` by `delta` while the opposite corner stays pinned,
    /// keeping the box inside the media, above the minimum size, and (when locked) at
    /// `normalizedRatio` width ÷ height in normalized units.
    private func resized(_ start: CGRect, corner: Corner, by delta: CGSize, normalizedRatio: CGFloat?) -> CGRect {
        let anchor = corner.opposite.point(in: start)
        let signX: CGFloat = corner.isLeading ? -1 : 1
        let signY: CGFloat = corner.isTop ? -1 : 1
        let moving = corner.point(in: start)

        // Room available between the anchor and the media's edge in each direction.
        let maxWidth = signX > 0 ? 1 - anchor.x : anchor.x
        let maxHeight = signY > 0 ? 1 - anchor.y : anchor.y

        var width = min(max(signX * (moving.x + delta.width - anchor.x), minimumSide), maxWidth)
        var height = min(max(signY * (moving.y + delta.height - anchor.y), minimumSide), maxHeight)

        if let ratio = normalizedRatio {
            // Follow whichever side was dragged further, then shrink to fit the media.
            if width / height > ratio { height = width / ratio } else { width = height * ratio }
            if width > maxWidth { width = maxWidth; height = width / ratio }
            if height > maxHeight { height = maxHeight; width = height * ratio }
        }

        return CGRect(x: signX > 0 ? anchor.x : anchor.x - width,
                      y: signY > 0 ? anchor.y : anchor.y - height,
                      width: width,
                      height: height)
    }

    // MARK: Geometry Helpers

    /// `mediaSize` scaled to fit inside `available`, preserving its aspect ratio.
    private func fittedSize(for mediaSize: CGSize, in available: CGSize) -> CGSize {
        guard mediaSize.width > 0, mediaSize.height > 0 else { return available }
        let scale = min(available.width / mediaSize.width, available.height / mediaSize.height)
        return CGSize(width: mediaSize.width * scale, height: mediaSize.height * scale)
    }

    /// Converts a pixel aspect ratio into normalized units (where the whole media is 1×1).
    private func normalizedRatio(_ pixelRatio: CGFloat, mediaSize: CGSize) -> CGFloat {
        guard mediaSize.width > 0 else { return pixelRatio }
        return pixelRatio * mediaSize.height / mediaSize.width
    }

    /// The largest centered box with the given normalized width ÷ height.
    private func centeredRect(ratio: CGFloat) -> CGRect {
        let width = ratio >= 1 ? 1 : ratio
        let height = ratio >= 1 ? 1 / ratio : 1
        return CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }

    // MARK: Loading & Applying

    private func loadPreview() async {
        switch request.source {
        case .image(let image):
            preview = image
        case .playbackCrop(let placeholder, let load, let initial):
            if let initial { cropRect = initial }
            if let placeholder {
                preview = placeholder
            } else if let url = await load(), let frame = await Self.firstFrame(of: url) {
                preview = frame
            } else {
                errorMessage = "The video's first frame couldn't be loaded. Check your connection and try again."
            }
            videoLoadFinished = true
        case .video(let placeholder, let load):
            // Open on the supplied frame at once, then fetch the video (a download for a
            // posted video that isn't on disk) in the background.
            preview = placeholder
            let task = Task { await load() }
            videoLoad = task
            let loaded = await task.value
            videoLoadFinished = true
            guard let url = loaded else {
                if preview == nil { errorMessage = "The video couldn't be loaded." }
                return
            }
            videoFileURL = url
            // Swap in the video's true first frame so the crop box matches the video.
            if let frame = await Self.firstFrame(of: url) {
                if let old = preview, !sameAspect(old.size, frame.size) {
                    aspect = .free
                    cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                }
                preview = frame
            } else if preview == nil {
                errorMessage = "The video's frames couldn't be read."
            }
        }
    }

    /// The video's exact first frame, upright. Uses the async generator (zero time
    /// tolerance) so it works on a remote streaming URL without blocking the UI.
    private static func firstFrame(of url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        guard let (image, _) = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: image)
    }

    private func sameAspect(_ a: CGSize, _ b: CGSize) -> Bool {
        guard a.height > 0, b.height > 0 else { return false }
        return abs(a.width / a.height - b.width / b.height) < 0.01
    }

    private func applyCrop() {
        let rect = cropRect
        switch request.source {
        case .image(let image):
            request.onImageCropped(ImageCropper.crop(image, to: rect))
            dismiss()
        case .playbackCrop:
            // Nothing to render — the player applies the rect.
            request.onPlaybackCrop(VideoCrop(rect: rect))
            dismiss()
        case .video:
            isExporting = true
            Task {
                // Wait for the video if it's still downloading.
                var url = videoFileURL
                if url == nil { url = await videoLoad?.value }
                guard let url else {
                    isExporting = false
                    errorMessage = "The video isn't available to crop right now. Check your connection and try again."
                    return
                }
                do {
                    let cropped = try await VideoCropper.crop(url, to: rect)
                    request.onVideoCropped(cropped)
                    isExporting = false
                    dismiss()
                } catch {
                    isExporting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Video Crop

/// A playback crop: a normalized rect (0…1, origin top-left) of the video's upright frame
/// that the player zooms to. Stored on posts as a compact "x,y,w,h" string so it syncs as
/// a single CloudKit STRING field.
nonisolated struct VideoCrop: Equatable {
    let rect: CGRect

    /// `nil` when `rect` is (essentially) the whole frame — there's nothing to crop.
    init?(rect: CGRect) {
        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clamped.isNull, clamped.width > 0.01, clamped.height > 0.01 else { return nil }
        let isFullFrame = clamped.minX < 0.001 && clamped.minY < 0.001
            && clamped.width > 0.999 && clamped.height > 0.999
        guard !isFullFrame else { return nil }
        self.rect = clamped
    }

    /// Parses a stored crop; `nil` for an empty/invalid string.
    init?(_ encoded: String?) {
        guard let parts = encoded?.split(separator: ",").compactMap({ Double($0) }),
              parts.count == 4 else { return nil }
        self.init(rect: CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]))
    }

    var encoded: String {
        [rect.minX, rect.minY, rect.width, rect.height]
            .map { String(format: "%.4f", Double($0)) }
            .joined(separator: ",")
    }
}

// MARK: - Corner

private enum Corner: CaseIterable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var isLeading: Bool { self == .topLeading || self == .bottomLeading }
    var isTop: Bool { self == .topLeading || self == .topTrailing }

    var opposite: Corner {
        switch self {
        case .topLeading:     return .bottomTrailing
        case .topTrailing:    return .bottomLeading
        case .bottomLeading:  return .topTrailing
        case .bottomTrailing: return .topLeading
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: isLeading ? rect.minX : rect.maxX,
                y: isTop ? rect.minY : rect.maxY)
    }
}

// MARK: - Croppers

/// Crops a still image by a normalized rect of its upright (orientation-applied) size.
enum ImageCropper {
    static func crop(_ image: UIImage, to normalizedRect: CGRect) -> UIImage {
        let size = image.size
        let cropRect = CGRect(x: normalizedRect.minX * size.width,
                              y: normalizedRect.minY * size.height,
                              width: normalizedRect.width * size.width,
                              height: normalizedRect.height * size.height).integral
        guard cropRect.width > 0, cropRect.height > 0 else { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        // Drawing the UIImage (rather than slicing its CGImage) honours its orientation,
        // so the rect lines up with what the crop editor showed.
        return UIGraphicsImageRenderer(size: cropRect.size, format: format).image { _ in
            image.draw(at: CGPoint(x: -cropRect.minX, y: -cropRect.minY))
        }
    }
}

/// Crops every frame of a video by a normalized rect of its upright frame, exporting a
/// new file (audio is carried over untouched).
nonisolated enum VideoCropper {
    enum CropError: LocalizedError {
        case noVideoTrack
        case exportUnavailable

        var errorDescription: String? {
            switch self {
            case .noVideoTrack:      return "This file has no video to crop."
            case .exportUnavailable: return "This video can't be exported."
            }
        }
    }

    static func crop(_ url: URL, to normalizedRect: CGRect) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw CropError.noVideoTrack
        }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let upright = naturalSize.applying(transform)
        let frameSize = CGSize(width: abs(upright.width), height: abs(upright.height))

        // Pixel crop in top-left-origin space, rounded to even sizes (encoders need them).
        let cropWidth = max(2, floor(normalizedRect.width * frameSize.width / 2) * 2)
        let cropHeight = max(2, floor(normalizedRect.height * frameSize.height / 2) * 2)
        let cropX = (normalizedRect.minX * frameSize.width).rounded()
        let cropY = (normalizedRect.minY * frameSize.height).rounded()
        // Core Image's origin is bottom-left, so flip the y offset.
        let ciY = frameSize.height - cropY - cropHeight

        // The filter handler receives each frame already upright (preferred transform
        // applied), matching the first frame the crop editor showed.
        let composition = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let source = request.sourceImage
            let rect = CGRect(x: source.extent.minX + cropX,
                              y: source.extent.minY + ciY,
                              width: cropWidth,
                              height: cropHeight)
            let output = source
                .cropped(to: rect)
                .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            request.finish(with: output, context: nil)
        }
        composition.renderSize = CGSize(width: cropWidth, height: cropHeight)

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw CropError.exportUnavailable
        }
        export.videoComposition = composition

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        try await export.export(to: outputURL, as: .mov)
        return outputURL
    }
}
