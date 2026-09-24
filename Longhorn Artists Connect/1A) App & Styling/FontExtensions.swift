//
//  FontExtensions.swift
//  Created on December 29, 2025.
//

import SwiftUI

// MARK: - Color Extension

extension Color {
    /// UT Austin Burnt Orange - Official brand color (RGB: 191, 87, 0 / Hex: #BF5700)
    static let utBrandOrange = Color(red: 191/255, green: 87/255, blue: 0/255)
    
    /// Initialize a Color from a hex string
    /// - Parameter hex: Hex string (with or without #)
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Font Extension

extension Font {
    /// Creates a Pragmatica font with the specified size and weight
    /// - Parameters:
    ///   - size: The point size of the font
    ///   - weight: The weight of the font (maps to Pragmatica variants)
    /// - Returns: A custom Font using Pragmatica
    static func pragmatica(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let fontName: String
        switch weight {
        case .black:
            fontName = "Pragmatica-Black"
        case .bold:
            fontName = "Pragmatica-Bold"
        case .heavy:
            fontName = "Pragmatica-Heavy"
        case .semibold:
            fontName = "Pragmatica-Semibold"
        case .medium:
            fontName = "Pragmatica-Medium"
        case .light:
            fontName = "Pragmatica-Light"
        case .thin:
            fontName = "Pragmatica-Thin"
        case .ultraLight:
            fontName = "Pragmatica-Ultralight"
        default: // .regular
            fontName = "Pragmatica-Regular"
        }
        return .custom(fontName, size: size)
    }
    
    // MARK: - Convenience Font Styles
    
    /// Large logo font style
    static var logoFont: Font {
        .pragmatica(34, weight: .bold)
    }
    
    /// Title font for main headings
    static var titlePragmatica: Font {
        .pragmatica(28, weight: .bold)
    }
    
    /// Headline font for section headers
    static var headlinePragmatica: Font {
        .pragmatica(20, weight: .semibold)
    }
    
    /// Subheadline font
    static var subheadlinePragmatica: Font {
        .pragmatica(16, weight: .regular)
    }
    
    /// Body text font
    static var bodyPragmatica: Font {
        .pragmatica(17, weight: .regular)
    }
    
    /// Caption font for small text
    static var captionPragmatica: Font {
        .pragmatica(12, weight: .regular)
    }
}

// MARK: - Debug Helper

#if DEBUG
extension Font {
    /// Prints all available font families and their font names to the console
    /// Useful for finding the exact font names installed in your app
    static func printAvailableFonts() {
        print("=== Available Fonts ===")
        for family in UIFont.familyNames.sorted() {
            let names = UIFont.fontNames(forFamilyName: family)
            print("Family: \(family)")
            for name in names {
                print("  - \(name)")
            }
        }
        print("======================")
    }
}
#endif
