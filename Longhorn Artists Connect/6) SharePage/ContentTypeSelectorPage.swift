//
//  ContentTypeSelectorPage.swift
//  Longhorn Artists Connect
//
//  The "What are you sharing?" category chooser shown at the top of the Share tab.
//  Kept in its own file so its preview compiles independently of ShareView_3's
//  much larger form/picker hierarchy.
//

import SwiftUI

// MARK: - Content Type Selector Page
struct ContentTypeSelectorPage: View {
    @Binding var selectedType: MediaType?
    @Binding var showDraftsSheet: Bool
    @Binding var showInfoSheet: Bool

    // MARK: - Toolbar Format Per Screen Size
    /// Tunable toolbar item sizes and positions for the Share page.
    /// - `draftsWidth/pillHeight/draftsFontSize`: size of the Drafts pill.
    /// - `infoWidth/infoFontSize`: size of the info button pill.
    /// - `pillOffsetX/Y`: nudges both pills from their default spot.
    /// - `logoHeight`: height of the Share logo image.
    private struct ToolbarFormat {
        var draftsWidth: CGFloat
        var draftsFontSize: CGFloat
        var infoWidth: CGFloat
        var infoFontSize: CGFloat
        var pillHeight: CGFloat
        var pillOffsetX: CGFloat
        var pillOffsetY: CGFloat
        var logoHeight: CGFloat
        // iPad-only knobs (default to no-ops so iPhone layout is unaffected):
        /// Extra horizontal/vertical nudge applied to the logo.
        var logoOffsetX: CGFloat = 0
        var logoOffsetY: CGFloat = 0
        /// Fixed length (width) of the Drafts pill. `nil` falls back to `draftsWidth`.
        var pillLength: CGFloat? = nil
        /// How far down the orange toolbar bar extends.
        var barHeight: CGFloat = 60
    }

    /// Adjust the values in each case to tune the toolbar for that screen size.
    private var toolbarFormat: ToolbarFormat {
        switch ScreenSizeFormat.current {
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return ToolbarFormat(draftsWidth: 60, draftsFontSize: 14, infoWidth: 50, infoFontSize: 18, pillHeight: 40, pillOffsetX: 0, pillOffsetY: 0, logoHeight: 55)
        case .size402x874: // iPhone 16 Pro, 17
            return ToolbarFormat(draftsWidth: 61, draftsFontSize: 14, infoWidth: 51, infoFontSize: 18, pillHeight: 41, pillOffsetX: 0, pillOffsetY: 0, logoHeight: 56)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return ToolbarFormat(draftsWidth: 66, draftsFontSize: 15, infoWidth: 55, infoFontSize: 20, pillHeight: 44, pillOffsetX: 0, pillOffsetY: 0, logoHeight: 60)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return ToolbarFormat(draftsWidth: 67, draftsFontSize: 16, infoWidth: 56, infoFontSize: 20, pillHeight: 45, pillOffsetX: 0, pillOffsetY: 0, logoHeight: 62)
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return ToolbarFormat(draftsWidth: 90, draftsFontSize: 20, infoWidth: 74, infoFontSize: 26, pillHeight: 56, pillOffsetX: 0, pillOffsetY: 0, logoHeight: 78, logoOffsetX: 0, logoOffsetY: 0, pillLength: nil, barHeight: 80)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return ToolbarFormat(draftsWidth: 104, draftsFontSize: 23, infoWidth: 84, infoFontSize: 30, pillHeight: 64, pillOffsetX: -30, pillOffsetY: -10, logoHeight: 90, logoOffsetX: 30, logoOffsetY: -10, pillLength: nil, barHeight: 90)
        }
    }

    // MARK: - Feed Format Per Screen Size
    /// Tunable sizing for the main feed (the title and content type cards).
    /// - `titleFontSize`: size of the "What are you sharing?" title.
    /// - `cardSpacing`: vertical gap between the content type cards.
    /// - `horizontalPadding`: insets the title and cards from the screen edges.
    /// - `cardIconSize`: size of the orange icon square in each card (the
    ///   image inside scales with it).
    private struct FeedFormat {
        var titleFontSize: CGFloat
        var cardSpacing: CGFloat
        var horizontalPadding: CGFloat
        var cardIconSize: CGFloat
    }

    /// Adjust the values in each case to tune the feed for that screen size.
    private var feedFormat: FeedFormat {
        switch ScreenSizeFormat.current {
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return FeedFormat(titleFontSize: 34, cardSpacing: 12, horizontalPadding: 20, cardIconSize: 60)
        case .size402x874: // iPhone 16 Pro, 17
            return FeedFormat(titleFontSize: 34, cardSpacing: 12, horizontalPadding: 20, cardIconSize: 61)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return FeedFormat(titleFontSize: 36, cardSpacing: 13, horizontalPadding: 22, cardIconSize: 65)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return FeedFormat(titleFontSize: 37, cardSpacing: 13, horizontalPadding: 22, cardIconSize: 67)
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return FeedFormat(titleFontSize: 48, cardSpacing: 18, horizontalPadding: 80, cardIconSize: 90)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return FeedFormat(titleFontSize: 56, cardSpacing: 20, horizontalPadding: 140, cardIconSize: 104)
        }
    }

    // ORANGE HEADER
    private var topBar: some View {
        ZStack {
            Color.brandOrange
                .ignoresSafeArea(edges: .top)
                .frame(height: toolbarFormat.barHeight)
            HStack(spacing: 8) {
                Image("Share")
                    .resizable()
                    .scaledToFit()
                    .frame(height: toolbarFormat.logoHeight)
                    .offset(x: -4, y: -2)
                    .offset(x: toolbarFormat.logoOffsetX, y: toolbarFormat.logoOffsetY)
                Spacer(minLength: 8)
                filterPill
            }
            .frame(height: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // TOOLBAR PILLS (distinct buttons with space between them)
    private var filterPill: some View {
        HStack(spacing: 8) {
            // Drafts button
            Button {
                showDraftsSheet = true
            } label: {
                Text("Drafts")
                    .font(.system(size: toolbarFormat.draftsFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: toolbarFormat.pillLength ?? toolbarFormat.draftsWidth, height: toolbarFormat.pillHeight)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(Color.pillActive))

            // Info button
            Button {
                showInfoSheet = true
            } label: {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: toolbarFormat.infoFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: toolbarFormat.infoWidth, height: toolbarFormat.pillHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(Color.pillActive))
        }
        .offset(x: toolbarFormat.pillOffsetX, y: toolbarFormat.pillOffsetY)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    topBar

                // "What are you sharing?" title
                Text("What are you sharing?")
                    .font(.system(size: feedFormat.titleFontSize, weight: .bold))
                    .padding(.horizontal, feedFormat.horizontalPadding)
                    .padding(.top, 30)
                    .padding(.bottom, 20)

                // Content type cards - non-scrollable, stacked vertically
                VStack(spacing: feedFormat.cardSpacing) {
                    ContentTypeCard(
                        imageName: "Film",
                        title: "Film",
                        description: "Frame your vision",
                        color: .black,
                        iconSize: feedFormat.cardIconSize
                    ) {
                        selectedType = .film
                    }

                    ContentTypeCard(
                        imageName: "Music",
                        title: "Music",
                        description: "Sound that resonates",
                        color: .black,
                        iconSize: feedFormat.cardIconSize
                    ) {
                        selectedType = .music
                    }

                    ContentTypeCard(
                        imageName: "Reel",
                        title: "Reel",
                        description: "Show yourself off",
                        color: .black,
                        iconSize: feedFormat.cardIconSize
                    ) {
                        selectedType = .reel
                    }

                    ContentTypeCard(
                        imageName: "Project",
                        title: "Project",
                        description: "Building something bigger",
                        color: .black,
                        iconSize: feedFormat.cardIconSize
                    ) {
                        selectedType = .project
                    }

                    ContentTypeCard(
                        imageName: "Event",
                        title: "Event",
                        description: "Gather your people",
                        color: .black,
                        iconSize: feedFormat.cardIconSize
                    ) {
                        selectedType = .event
                    }
                }
                .padding(.horizontal, feedFormat.horizontalPadding)
                .padding(.bottom, 20)

                Spacer() // Push content to top
            }
            // Lock the content to the (keyboard-independent) container size so it can
            // never shift up or down when a submission sheet's keyboard appears.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Content Type Card
struct ContentTypeCard: View {
    let imageName: String
    let title: String
    let description: String
    let color: Color
    var iconSize: CGFloat = 60
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon (the inner image keeps its original proportion of the square)
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.brandOrange)
                        .frame(width: iconSize, height: iconSize)

                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize * 43.75 / 60, height: iconSize * 43.75 / 60)
                        .foregroundColor(.white)
                }

                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(description)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(ContentTypeCardButtonStyle())
        .tint(.primary) // Uses primary color (black/white based on scheme) for any tint
    }
}

/// Presses the entire card (rectangle + icon) as one cohesive unit: a subtle
/// scale-down and darken on press instead of the default per-content opacity fade.
struct ContentTypeCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("Category Selector") {
    ContentTypeSelectorPage(
        selectedType: .constant(nil),
        showDraftsSheet: .constant(false),
        showInfoSheet: .constant(false)
    )
}

// MARK: - Screen Size Previews

#if DEBUG

#Preview("Share 393 × 852", traits: .fixedLayout(width: 393, height: 852)) {
    let _ = (ScreenSizeFormat.previewOverride = .size393x852)
    ContentTypeSelectorPage(
        selectedType: .constant(nil),
        showDraftsSheet: .constant(false),
        showInfoSheet: .constant(false)
    )
}

#Preview("Share 402 × 874", traits: .fixedLayout(width: 402, height: 874)) {
    let _ = (ScreenSizeFormat.previewOverride = .size402x874)
    ContentTypeSelectorPage(
        selectedType: .constant(nil),
        showDraftsSheet: .constant(false),
        showInfoSheet: .constant(false)
    )
}

#Preview("Share 430 × 932", traits: .fixedLayout(width: 430, height: 932)) {
    let _ = (ScreenSizeFormat.previewOverride = .size430x932)
    ContentTypeSelectorPage(
        selectedType: .constant(nil),
        showDraftsSheet: .constant(false),
        showInfoSheet: .constant(false)
    )
}

#Preview("Share 440 × 956", traits: .fixedLayout(width: 440, height: 956)) {
    let _ = (ScreenSizeFormat.previewOverride = .size440x956)
    ContentTypeSelectorPage(
        selectedType: .constant(nil),
        showDraftsSheet: .constant(false),
        showInfoSheet: .constant(false)
    )
}

#endif
