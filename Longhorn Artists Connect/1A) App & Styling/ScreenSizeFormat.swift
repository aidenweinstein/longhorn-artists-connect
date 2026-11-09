//
//  ScreenSizeFormat.swift
//  Longhorn Artists Connect
//
//  Universal, single-source-of-truth screen bucketing and scaling for every
//  supported iPhone and iPad size.
//
//  This file holds two cooperating pieces:
//    - `ScreenSizeFormat` buckets the running device into one of six screen formats.
//      Each main page keeps a "Toolbar Format Per Screen Size" section that switches
//      on `ScreenSizeFormat.current` to tune its toolbar item sizes and positions.
//    - `ScreenScale` assigns ONE scale factor to each of those buckets. Values
//      authored against the reference 393-wide iPhone are multiplied by that factor
//      to produce the size used on the current device.
//
//  Every device-dependent dimension in the app (font sizes, frames, padding,
//  spacing, icon sizes, etc.) should flow through here. That way, tuning how the
//  UI scales across screen sizes only ever means editing THIS file.
//
//  Usage:
//      Text("Hi").font(.scaled(size: 17, weight: .semibold))
//      Image(...).frame(width: ScreenScale.scaled(60), height: ScreenScale.scaled(60))
//      .padding(20.scaledToScreen)
//

import SwiftUI
import UIKit

// MARK: - Screen Size Format

enum ScreenSizeFormat {
    /// 393 × 852 pts — iPhone 14 Pro, 15, 15 Pro, 16
    case size393x852
    /// 402 × 874 pts — iPhone 16 Pro, 17
    case size402x874
    /// 430 × 932 pts — iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
    case size430x932
    /// 440 × 956 pts — iPhone 16 Pro Max, 17 Pro Max
    case size440x956
    /// ~834 × 1194 pts — iPad Pro 11", iPad Air 11"
    case iPad11
    /// ~1024 × 1366 pts — iPad Pro 13", iPad Air 13"
    case iPad13

    /// The format for the current device. iPads are bucketed by their shorter
    /// (portrait-width) side so orientation doesn't change the result; iPhones
    /// are bucketed by width so nearby sizes fall into the closest format.
    static var current: ScreenSizeFormat {
        #if DEBUG
        if let previewOverride { return previewOverride }
        #endif
        let bounds = UIScreen.main.bounds

        if UIDevice.current.userInterfaceIdiom == .pad {
            // Shorter side ≈ 834 on 11" iPads, ≈ 1024 on 13" iPads.
            let shortSide = min(bounds.width, bounds.height)
            return shortSide < 950 ? .iPad11 : .iPad13
        }

        let width = bounds.width
        switch width {
        case ..<398:  return .size393x852
        case ..<416:  return .size402x874
        case ..<435:  return .size430x932
        default:      return .size440x956
        }
    }

    #if DEBUG
    /// Set by the size-specific previews so a fixed-layout preview uses the
    /// format matching its dimensions instead of the canvas device's screen.
    static var previewOverride: ScreenSizeFormat?
    #endif

    /// True for the two iPad formats.
    var isPad: Bool {
        self == .iPad11 || self == .iPad13
    }

    // MARK: iPad header layout

    /// On iPad the orange header bar itself runs edge to edge, but the things inside it
    /// (wordmark, pills, buttons) keep their iPhone size and sit centered in a column
    /// this wide — about one iPhone across. `nil` on iPhone, where the contents simply
    /// fill the bar as before. Apply with `.frame(maxWidth:)` on each page's header row.
    static var toolbarContentMaxWidth: CGFloat? {
        current.isPad ? 430 : nil
    }

    // MARK: Toolbar pill height

    /// The on-screen height of every pill/button in the orange toolbar, shared by all
    /// five main pages so they line up when switching tabs. Home is the reference: its
    /// filter pill fills a 44·toolbarScale row and is then shrunk by its 0.9 toggleSize,
    /// so the rendered height is 39.6·toolbarScale per device. Pages that apply their
    /// own `scaleEffect` divide this by that scale before framing the button.
    var toolbarPillHeight: CGFloat {
        switch self {
        case .size393x852: return 39.6   // Home toolbarScale 1.0
        case .size402x874: return 40.4   // Home toolbarScale 1.02
        case .size430x932: return 43.2   // Home toolbarScale 1.09
        case .size440x956: return 44.4   // Home toolbarScale 1.12
        case .iPad11:      return 40.4   // iPhone-sized toolbar contents (1.02)
        case .iPad13:      return 40.4
        }
    }

    /// `toolbarPillHeight` for the current device.
    static var toolbarPillHeight: CGFloat {
        current.toolbarPillHeight
    }
}

// MARK: - Feed Columns

/// How many side-by-side columns the Home and Discover feeds show.
///
/// iPhone feeds are always one column. iPad feeds grow to two columns in portrait and
/// three in landscape, so each column stays about one iPhone wide and the cards inside
/// keep their iPhone size. The count comes from the width actually available to the
/// feed rather than the device's orientation, so a Split View or Stage Manager window
/// narrower than a full-screen iPad drops columns instead of squeezing the cards.
///
/// The whole grid lives in one scroll view, so every column scrolls together.
enum FeedColumns {
    /// A column is never narrower than this — just under the narrowest supported
    /// iPhone (393 pt), so every iPhone still lays out as a single column.
    static let minimumColumnWidth: CGFloat = 380
    /// Landscape iPads get three columns; nothing goes wider than that.
    static let maximumColumns = 3

    /// The number of columns that fit in `width` points.
    ///
    /// Full-screen results: 11" iPad → 2 portrait / 3 landscape, 13" iPad → 2 / 3,
    /// every iPhone → 1.
    static func count(forWidth width: CGFloat) -> Int {
        let fit = Int(width / minimumColumnWidth)
        return min(max(fit, 1), maximumColumns)
    }

    /// `count` equal, top-aligned columns for a `LazyVGrid`, with `spacing` points
    /// between neighbouring columns.
    static func gridItems(count: Int, spacing: CGFloat = 0) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
    }

    /// The width of one column when `count` columns share `totalWidth`, after
    /// `horizontalPadding` on each side and `spacing` between columns.
    static func columnWidth(totalWidth: CGFloat, count: Int, spacing: CGFloat = 0, horizontalPadding: CGFloat = 0) -> CGFloat {
        let usable = totalWidth - 2 * horizontalPadding - spacing * CGFloat(count - 1)
        return max(usable / CGFloat(count), 0)
    }

    /// Index of the first item on the grid's last row. Items before it have another
    /// row beneath them (so they can show a separator); items from it on are the
    /// bottom row. With one column this is simply `count - 1`.
    static func lastRowStart(itemCount: Int, columns: Int) -> Int {
        guard itemCount > 0, columns > 0 else { return 0 }
        return ((itemCount - 1) / columns) * columns
    }
}

// MARK: - Screen Scale

enum ScreenScale {

    /// The multiplier applied to every scaled value on a given screen size.
    ///
    /// The 393-wide iPhone is the reference (factor `1.0`); larger phones scale up
    /// proportionally. Edit these numbers to change how the ENTIRE app scales
    /// for each screen size — nothing else needs to change.
    static func factor(for format: ScreenSizeFormat) -> CGFloat {
        switch format {
        case .size393x852: return 0.95   // iPhone 14 Pro, 15, 15 Pro, 16 (reference)
        case .size402x874: return 1.00   // iPhone 16 Pro, 17
        case .size430x932: return 1.00   // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
        case .size440x956: return 1.00   // iPhone 16 Pro Max, 17 Pro Max
        // iPad keeps iPhone-sized elements and spends its extra width on more feed
        // columns (see `FeedColumns`) rather than on scaling everything up.
        case .iPad11:      return 1.00   // iPad Pro 11", iPad Air 11"
        case .iPad13:      return 1.00   // iPad Pro 13", iPad Air 13"
        }
    }

    /// The scale factor for the current device.
    static var factor: CGFloat {
        factor(for: .current)
    }

    /// Scales a reference (393-wide) value to the current device.
    /// Rounded to the nearest point to avoid blurry half-pixel layouts.
    static func scaled(_ value: CGFloat) -> CGFloat {
        (value * factor).rounded()
    }
}

// MARK: - Numeric Conveniences

extension CGFloat {
    /// Scales this reference (393-wide) value to the current device. See `ScreenScale`.
    var scaledToScreen: CGFloat { ScreenScale.scaled(self) }
}

extension Double {
    /// Scales this reference (393-wide) value to the current device. See `ScreenScale`.
    var scaledToScreen: CGFloat { ScreenScale.scaled(CGFloat(self)) }
}

extension Int {
    /// Scales this reference (393-wide) value to the current device. See `ScreenScale`.
    var scaledToScreen: CGFloat { ScreenScale.scaled(CGFloat(self)) }
}

// MARK: - Font Convenience

extension Font {
    /// A system font whose point size is scaled to the current screen. See `ScreenScale`.
    static func scaled(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: ScreenScale.scaled(size), weight: weight, design: design)
    }
}
