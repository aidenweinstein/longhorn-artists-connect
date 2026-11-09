//
//  SchoolArtwork.swift
//  Longhorn Artists Connect
//
//  Draws the burnt-orange + white brand assets in the current school's colors,
//  and switches the home screen icon to match. The colors themselves come from
//  SchoolColors.swift.
//

import SwiftUI
import UIKit

// MARK: - School Asset Image

/// A two-tone brand asset (tab logos, Share icons, the Nexus wordmark) drawn in
/// the current user's school colors. Drop-in for `Image("Name").resizable()`.
///
/// Observes the school through `@AppStorage`, so it redraws as soon as the user
/// picks or changes their school.
struct SchoolAssetImage: View {
    let name: String

    @AppStorage("userSchool") private var userSchool = ""
    @AppStorage("isGuestUser") private var isGuestUser = false
    // Read in `body` so a moderator's school pick redraws the asset.
    @AppStorage(SchoolScope.moderatorSchoolKey) private var moderatorSchool = ""

    init(_ name: String) {
        self.name = name
    }

    var body: some View {
        let _ = moderatorSchool
        let theme = AppTheme.theme(school: userSchool, isGuest: isGuestUser)
        if let recolored = SchoolArtwork.image(named: name, theme: theme) {
            Image(uiImage: recolored)
                .resizable()
        } else {
            Image(name)
                .resizable()
        }
    }
}

// MARK: - Recoloring

enum SchoolArtwork {

    /// Recolored assets, keyed by asset name + theme colors. Each asset is only
    /// recolored once per school per launch.
    private static let cache = NSCache<NSString, UIImage>()

    /// Longest edge, in pixels, that in-app assets are recolored at. The source
    /// files are up to ~2,300px wide but never drawn larger than a toolbar or a
    /// Share tile, so shrinking first keeps recoloring cheap without visible loss.
    private static let inAppMaxPixelDimension = 1024

    /// The asset `name` in `theme`'s colors, or `nil` when the stock artwork
    /// should be shown as-is (UT/default theme, missing asset, or an asset that
    /// isn't two-tone).
    static func image(named name: String, theme: SchoolTheme) -> UIImage? {
        guard !theme.usesStockArtwork else { return nil }

        let key = "\(name)|\(cacheKey(for: theme.bubble))|\(cacheKey(for: theme.text))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let source = UIImage(named: name),
              let recolored = recolor(source,
                                      orangeTo: theme.bubble,
                                      whiteTo: theme.text,
                                      maxPixelDimension: inAppMaxPixelDimension)
        else { return nil }

        cache.setObject(recolored, forKey: key)
        return recolored
    }

    /// Swaps an orange-and-white image's colors: orange → `bubble`, white → `text`.
    ///
    /// Every pixel is either the orange, the white, or (along anti-aliased edges
    /// and in JPEG noise) a blend of the two. The blue channel tells them apart —
    /// white is ~255, burnt-orange is near 0 — so each pixel's blue value gives
    /// how far it sits between the two, and the output is the same blend of the
    /// new colors. That keeps edges smooth instead of stair-stepped.
    ///
    /// The orange's exact blue is measured per image (the 1st percentile), since
    /// the assets use slightly different oranges. Transparency is preserved, and
    /// all-white assets on a transparent background just have their white
    /// swapped for `text`.
    ///
    /// Returns `nil` if the image has no white in it.
    static func recolor(_ source: UIImage,
                        orangeTo bubble: Color,
                        whiteTo text: Color,
                        maxPixelDimension: Int? = nil) -> UIImage? {
        guard let cgImage = source.cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        // Target size, shrunk to fit `maxPixelDimension` if needed.
        var width = cgImage.width
        var height = cgImage.height
        if let maxPixelDimension, max(width, height) > maxPixelDimension {
            let scale = Double(maxPixelDimension) / Double(max(width, height))
            width = max(1, Int((Double(width) * scale).rounded()))
            height = max(1, Int((Double(height) * scale).rounded()))
        }

        let bytesPerRow = width * 4
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo),
              let data = context.data
        else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let pixels = UnsafeMutableBufferPointer(start: data.assumingMemoryBound(to: UInt8.self),
                                                count: bytesPerRow * height)

        // Pass 1: histogram of (un-premultiplied) blue across the visible pixels,
        // to find this image's orange and white levels.
        var histogram = [Int](repeating: 0, count: 256)
        var counted = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[i + 3])
            guard alpha >= 128 else { continue }
            histogram[min(255, Int(pixels[i + 2]) * 255 / alpha)] += 1
            counted += 1
        }
        guard counted > 0 else { return nil }

        let measuredOrangeBlue = percentile(0.01, of: histogram, total: counted)
        let whiteBlue = percentile(0.99, of: histogram, total: counted)
        // An all-white asset on transparency (the Home "NEXUS" wordmark) has no
        // orange to measure, so fall back to burnt-orange's own blue level (0).
        let orangeBlue = whiteBlue - measuredOrangeBlue >= 64 ? measuredOrangeBlue : 0
        let span = Float(whiteBlue - orangeBlue)
        // No white in it at all — not one of the brand assets.
        guard span >= 64 else { return nil }

        let from = components(of: bubble)
        let to = components(of: text)

        // Pass 2: remap every pixel along the orange → white axis.
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[i + 3]
            guard alpha > 0 else { continue }
            let opacity = Float(alpha) / 255
            let blue = Float(pixels[i + 2]) / opacity
            let t = min(max((blue - Float(orangeBlue)) / span, 0), 1)
            // Write back premultiplied, to match the context's format.
            pixels[i]     = UInt8(((from.r + (to.r - from.r) * t) * opacity).rounded())
            pixels[i + 1] = UInt8(((from.g + (to.g - from.g) * t) * opacity).rounded())
            pixels[i + 2] = UInt8(((from.b + (to.b - from.b) * t) * opacity).rounded())
        }

        guard let output = context.makeImage() else { return nil }
        // Keep the same size in points even when shrunk.
        let scale = source.scale * CGFloat(width) / CGFloat(cgImage.width)
        return UIImage(cgImage: output, scale: scale, orientation: source.imageOrientation)
    }

    // MARK: Helpers

    /// The blue level at or below which `fraction` of the counted pixels fall.
    private static func percentile(_ fraction: Double, of histogram: [Int], total: Int) -> Int {
        let target = Int(Double(total) * fraction)
        var running = 0
        for (level, count) in histogram.enumerated() {
            running += count
            if running > target { return level }
        }
        return 255
    }

    /// A color's sRGB components on a 0–255 scale.
    private static func components(of color: Color) -> (r: Float, g: Float, b: Float) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamp = { (value: CGFloat) in Float(min(max(value, 0), 1)) * 255 }
        return (clamp(r), clamp(g), clamp(b))
    }

    private static func cacheKey(for color: Color) -> String {
        let c = components(of: color)
        return "\(Int(c.r)),\(Int(c.g)),\(Int(c.b))"
    }
}

// MARK: - Home Screen Icon

/// Switches the home screen icon to the current school's (`SchoolTheme.appIconName`).
///
/// iOS can't recolor an icon at runtime, so each school's icon is a pre-rendered
/// `.appiconset` in Assets.xcassets (made with `SchoolArtwork.recolor` from
/// `AppIcon`'s Nexus.png). They ship because the target sets
/// `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`.
///
/// iOS shows a brief "You have changed the icon" alert whenever this switches.
enum SchoolAppIcon {
    static func apply(_ theme: SchoolTheme) async {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != theme.appIconName else { return }
        do {
            try await app.setAlternateIconName(theme.appIconName)
        } catch {
            print("⚠️ Couldn't switch app icon to \(theme.appIconName ?? "AppIcon"): \(error.localizedDescription)")
        }
    }
}
