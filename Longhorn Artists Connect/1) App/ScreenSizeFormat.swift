//
//  ScreenSizeFormat.swift
//  Longhorn Artists Connect
//
//  The four supported iPhone screen formats. Each main page keeps a
//  "Toolbar Format Per Screen Size" section that switches on
//  `ScreenSizeFormat.current` to tune its toolbar item sizes and positions
//  for the device it is running on.
//

import UIKit

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
}
