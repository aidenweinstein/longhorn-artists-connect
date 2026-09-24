import SwiftUI

// MARK: - Nexus Brand Colors
//
// Single source of truth for every color used in the app.
// Usage in SwiftUI:  .foregroundStyle(Color.brandOrange)
// Usage in UIKit:    UIColor.brandOrange

// MARK: - SwiftUI Colors
extension Color {

    // The literal UT burnt-orange. Fixed base value; `brandOrange` below is themed.
    static let utBurntOrange = Color(red: 191/255, green: 87/255, blue: 0/255)

    // Primary brand color — used for nav bar, selected icons, accents. Themed to the
    // current user's school (see `AppTheme`), so a Michigan user sees blue, a USC user
    // red, etc. Defaults to UT burnt-orange when no school is set.
    static var brandOrange: Color { AppTheme.brandColor }

    // Toolbar pill background (the dark brown capsule in HomeView)
    static let pillActive = Color(red: 240/255, green: 165/255, blue: 46/255)

    // Toolbar pill active/selected state (slightly darker)
    static let pillBackground = Color(red: 182/255, green: 119/255, blue: 23/255)

    // App background in dark mode
    static let darkBackground = Color(red: 18/255, green: 18/255, blue: 18/255)
}

// MARK: - School Credit Themes

/// Bubble + text colors for a credited person's name chip, keyed by their school.
/// Registered members get a colored bubble; unrecognized names stay plain grey.
struct SchoolTheme {
    let bubble: Color
    let text: Color

    /// Fallback for a recognized Nexus member whose school isn't one of the themed
    /// ones (or is unset) — uses the app's own (UT) brand accent.
    static let nexusDefault = SchoolTheme(bubble: .utBurntOrange, text: .white)

    /// The theme for a school name. Unknown/empty falls back to `nexusDefault`.
    static func forSchool(_ school: String) -> SchoolTheme {
        switch school.trimmingCharacters(in: .whitespaces) {
        case "The University of Texas at Austin", "UT", "UT Austin":
            return SchoolTheme(bubble: .utBurntOrange, text: .white)
        case "University of Michigan", "Michigan", "UMich":
            return SchoolTheme(bubble: Color(hex: "00274C"), text: Color(hex: "FFCB05"))
        case "Cal Poly SLO", "Cal Poly", "Cal Poly San Luis Obispo":
            return SchoolTheme(bubble: Color(hex: "154734"), text: Color(hex: "BD8B13"))
        case "USC", "University of Southern California":
            return SchoolTheme(bubble: Color(hex: "990000"), text: Color(hex: "FFC72C"))
        case "NYU", "New York University":
            return SchoolTheme(bubble: Color(hex: "57068C"), text: .white)
        case "DePaul", "DePaul University":
            return SchoolTheme(bubble: Color(hex: "005EB8"), text: .white)
        default:
            return .nexusDefault
        }
    }

    /// The brand accent for a school (the bubble color), used to theme the whole app.
    static func brandColor(for school: String) -> Color {
        forSchool(school).bubble
    }
}

// MARK: - App Theme

/// Resolves the app-wide brand color from the current user's school. Guest users
/// (and users with no school set) always get UT burnt-orange.
enum AppTheme {
    /// The current user's school, as saved during onboarding.
    static var currentSchool: String {
        UserDefaults.standard.string(forKey: "userSchool") ?? ""
    }

    /// Whether this account was created via the Guest flow.
    static var isGuest: Bool {
        UserDefaults.standard.bool(forKey: "isGuestUser")
    }

    /// The themed brand color for the whole app. Guests stay orange.
    static var brandColor: Color {
        isGuest ? .utBurntOrange : SchoolTheme.brandColor(for: currentSchool)
    }
}

// MARK: - UIKit Colors
// Used by AppearanceManager for UINavigationBar, UITabBar, etc.
extension UIColor {

    // Primary brand color — themed to the current user's school (see `AppTheme`).
    static var brandOrange: UIColor { UIColor(AppTheme.brandColor) }

    // App background in dark mode
    static let darkBackground = UIColor(red: 18/255, green: 18/255, blue: 18/255, alpha: 1.0)

    // Adapts automatically between light and dark mode
    static let adaptiveBackground = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? .darkBackground : .systemBackground
    }

    static let adaptiveText = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? .white : .black
    }

    static let adaptiveTint = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? .white : .brandOrange
    }
}

// MARK: - Preview
private struct NexusColorSwatch: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
}

private let nexusColorSwatches: [NexusColorSwatch] = [
    .init(name: "brandOrange",    color: .brandOrange),
    .init(name: "pillBackground", color: .pillBackground),
    .init(name: "pillActive",     color: .pillActive),
    .init(name: "darkBackground", color: .darkBackground),
]

#Preview("Nexus Colors") {
    ScrollView {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140), spacing: 16)],
            spacing: 16
        ) {
            ForEach(nexusColorSwatches) { swatch in
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(swatch.color)
                        .frame(height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        )
                    Text(swatch.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(20)
    }
    .background(Color(.systemBackground))
}
