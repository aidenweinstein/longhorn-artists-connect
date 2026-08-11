import SwiftUI

// MARK: - Nexus Brand Colors
//
// Single source of truth for every color used in the app.
// Usage in SwiftUI:  .foregroundStyle(Color.brandOrange)
// Usage in UIKit:    UIColor.brandOrange

// MARK: - SwiftUI Colors
extension Color {

    // Primary brand color — used for nav bar, selected icons, accents
    static let brandOrange = Color(red: 191/255, green: 87/255, blue: 0/255)

    // Toolbar pill background (the dark brown capsule in HomeView)
    static let pillActive = Color(red: 240/255, green: 165/255, blue: 46/255)

    // Toolbar pill active/selected state (slightly darker)
    static let pillBackground = Color(red: 182/255, green: 119/255, blue: 23/255)

    // App background in dark mode
    static let darkBackground = Color(red: 18/255, green: 18/255, blue: 18/255)
}

// MARK: - UIKit Colors
// Used by AppearanceManager for UINavigationBar, UITabBar, etc.
extension UIColor {

    // Primary brand color
    static let brandOrange = UIColor(red: 191/255, green: 87/255, blue: 0/255, alpha: 1.0)

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
