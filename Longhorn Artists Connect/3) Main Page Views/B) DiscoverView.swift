//
//  DiscoverView.swift
//  Longhorn Artists Connect
//
//  Created by Aiden Weinstein on 2/12/26.
//
//  This file contains the Discover tab UI, which displays upcoming projects and events.
//  Projects show cast/crew calls for open positions.
//  Events show upcoming community events with dates and ticket links.
//
//  Note: ProjectCard and EventCard components are in their respective files.

import SwiftUI

// MARK: - Main Discover View

struct DiscoverView: View {
    enum DiscoverCategory: String, CaseIterable, Identifiable {
        case projects = "Projects"
        case events = "Events"
        var id: String { rawValue }
    }
    
    @State private var selection: DiscoverCategory = .projects

    // MARK: - Toolbar Format Per Screen Size
    /// Tunable toolbar item sizes and positions for the Discover page.
    /// - `pillOffsetX/Y`: nudges the entire category selector (outer capsule,
    ///   buttons, and sliding highlight) from its default spot, without
    ///   affecting any other layout. Positive x moves it right, negative x
    ///   left. Positive y moves it down, negative y up.
    /// - `buttonWidth/Height`: hit area of each category button. The sliding
    ///   highlight capsule sizes itself from these.
    /// - `buttonFontSize`: text size inside the category buttons.
    /// - `logoHeight`: height of the Discover logo image.
    private struct ToolbarFormat {
        var pillOffsetX: CGFloat
        var pillOffsetY: CGFloat
        var buttonWidth: CGFloat
        var buttonHeight: CGFloat
        var buttonFontSize: CGFloat
        var logoHeight: CGFloat
        // iPad-only knobs (default to no-ops so iPhone layout is unaffected):
        /// Extra horizontal/vertical nudge applied to the logo.
        var logoOffsetX: CGFloat = 0
        var logoOffsetY: CGFloat = 0
        /// Fixed length (width) of the pill capsule. `nil` sizes it to its content.
        var pillLength: CGFloat? = nil
        /// How far down the orange toolbar bar extends.
        var barHeight: CGFloat = 60
    }

    /// Adjust the values in each case to tune the toolbar for that screen size.
    private var toolbarFormat: ToolbarFormat {
        switch ScreenSizeFormat.current {
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return ToolbarFormat(pillOffsetX: -14, pillOffsetY: -2, buttonWidth: 63, buttonHeight: 28, buttonFontSize: 14, logoHeight: 46)
        case .size402x874: // iPhone 16 Pro, 17
            return ToolbarFormat(pillOffsetX: -14, pillOffsetY: -2, buttonWidth: 64, buttonHeight: 29, buttonFontSize: 14, logoHeight: 47)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return ToolbarFormat(pillOffsetX: -15, pillOffsetY: -2, buttonWidth: 69, buttonHeight: 31, buttonFontSize: 15, logoHeight: 50)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return ToolbarFormat(pillOffsetX: -16, pillOffsetY: -2, buttonWidth: 71, buttonHeight: 31, buttonFontSize: 16, logoHeight: 52)
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return ToolbarFormat(pillOffsetX: -18, pillOffsetY: -2, buttonWidth: 90, buttonHeight: 38, buttonFontSize: 18, logoHeight: 66, logoOffsetX: 0, logoOffsetY: 0, pillLength: nil, barHeight: 80)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return ToolbarFormat(pillOffsetX: -20, pillOffsetY: -2, buttonWidth: 104, buttonHeight: 42, buttonFontSize: 20, logoHeight: 76, logoOffsetX: 0, logoOffsetY: 0, pillLength: nil, barHeight: 90)
        }
    }

    private var pillOffsetX: CGFloat { toolbarFormat.pillOffsetX }
    private var pillOffsetY: CGFloat { toolbarFormat.pillOffsetY }

    // MARK: - Feed Format Per Screen Size
    /// Tunable sizing for the main feed (project and event cards).
    /// - `rowSpacing`: vertical gap between cards.
    /// - `cardHorizontalPadding`: insets each card (and separator) from the
    ///   screen edges; larger values make the cards narrower.
    /// - `feedVerticalPadding`: padding above and below the whole list.
    private struct FeedFormat {
        var rowSpacing: CGFloat
        var cardHorizontalPadding: CGFloat
        var feedVerticalPadding: CGFloat
    }

    /// Adjust the values in each case to tune the feed for that screen size.
    private var feedFormat: FeedFormat {
        switch ScreenSizeFormat.current {
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return FeedFormat(rowSpacing: 0, cardHorizontalPadding: 30, feedVerticalPadding: 5)
        case .size402x874: // iPhone 16 Pro, 17
            return FeedFormat(rowSpacing: 0, cardHorizontalPadding: 30, feedVerticalPadding: 5)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return FeedFormat(rowSpacing: 0, cardHorizontalPadding: 20, feedVerticalPadding: 18)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return FeedFormat(rowSpacing: 0, cardHorizontalPadding: 30, feedVerticalPadding: 5)
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return FeedFormat(rowSpacing: 0, cardHorizontalPadding: 120, feedVerticalPadding: 16)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return FeedFormat(rowSpacing: 0, cardHorizontalPadding: 200, feedVerticalPadding: 16)
        }
    }
    
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    
    @State private var selectedProjectSubmission: Submission?
    @State private var selectedEvent: Submission?
    
    // Define colors as static constants to prevent color changes on tab switch
    private static let darkBrownColor = Color(red: 80/255, green: 50/255, blue: 30/255).opacity(1.0)  // Darker for unselected
    private static let mediumBrownColor = Color(red: 140/255, green: 90/255, blue: 55/255).opacity(1.0)  // Brighter for selected
    
    // Computed property for projects from submissions
    var projects: [Submission] {
        store.approvedSubmissions.filter { $0.type == .project }
    }
    
    // Computed property for events from submissions
    var events: [Submission] {
        store.approvedSubmissions.filter { $0.type == .event }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                if selection == .projects {
                    projectsView
                } else {
                    eventsView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

// ORANGE HEADER
    private var topBar: some View {
        ZStack {
            Color.brandOrange
                .ignoresSafeArea(edges: .top)
                .frame(height: toolbarFormat.barHeight)
            HStack(spacing: 8) {
                Image("Discover")
                    .resizable()
                    .scaledToFill()
                    .frame(height: toolbarFormat.logoHeight)
                    .offset(x: 10, y: -1)
                    .offset(x: toolbarFormat.logoOffsetX, y: toolbarFormat.logoOffsetY)
                Spacer(minLength: 9)
                filterPill
            }
            .frame(height: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
    }

// TOOLBAR
    private var filterPill: some View {
        HStack(spacing: 0) {
            categoryButtons
        }
        .padding(8)
        .frame(width: toolbarFormat.pillLength)
        .background(
            Capsule()
                .fill(Color.pillActive)
        )
        .offset(x: pillOffsetX, y: pillOffsetY)
    }

// CATEGORY BUTTONS
    private var categoryButtons: some View {
        HStack(spacing: 2) {
            ForEach(DiscoverCategory.allCases) { category in
                Button {
                        selection = category
                } label: {
                    Text(category.rawValue)
                        .font(.system(size: toolbarFormat.buttonFontSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: toolbarFormat.buttonWidth, height: toolbarFormat.buttonHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        // HIGHLIGHTED CAPSULE
        .background(alignment: .leading) {
            Capsule()
                .fill(Color.pillBackground)
                .frame(width: toolbarFormat.buttonWidth + 5, height: toolbarFormat.buttonHeight + 3)
                .offset(x: highlightOffsetX)
                .offset(x:-3)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selection)
        }
    }

    /// Leading offset of the highlight capsule for the current selection.
    /// Buttons have 2pt spacing; the capsule is inset 1pt.
    private var highlightOffsetX: CGFloat {
        let index = CGFloat(DiscoverCategory.allCases.firstIndex(of: selection) ?? 0)
        return index * (toolbarFormat.buttonWidth + 2) + 1
    }
    
    // MARK: - Project Thumbnail/Detail View
    
    private var projectsView: some View {
        Group {
            if projects.isEmpty {
                List {
                    Text("No upcoming projects.")
                        .foregroundStyle(.secondary)
                }
                .listStyle(.plain)
            } else {
                ScrollView {
                    LazyVStack(spacing: feedFormat.rowSpacing) {
                        ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                            Button {
                                selectedProjectSubmission = project
                            } label: {
                                ProjectCard(project: project)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, feedFormat.cardHorizontalPadding)

                            // Add separator line between projects
                            if index < projects.count - 1 {
                                Divider()
                                    .padding(.horizontal, feedFormat.cardHorizontalPadding)
                            }
                        }
                    }
                    .padding(.vertical, feedFormat.feedVerticalPadding)
                }
                .refreshable {
                    await refreshContent()
                }
            }
        }
        .sheet(item: $selectedProjectSubmission) { project in
            UpcomingProjectDetailView(submission: project)
        }
    }
    
    // MARK: - Event Thumbnail/Detail View
    
    private var eventsView: some View {
        Group {
            if events.isEmpty {
                List {
                    Text("No upcoming events.")
                        .foregroundStyle(.secondary)
                }
                .listStyle(.plain)
            } else {
                ScrollView {
                    LazyVStack(spacing: feedFormat.rowSpacing) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            Button {
                                selectedEvent = event
                            } label: {
                                EventCard(event: event)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, feedFormat.cardHorizontalPadding)

                            // Add separator line between events
                            if index < events.count - 1 {
                                Divider()
                                    .padding(.horizontal, feedFormat.cardHorizontalPadding)
                            }
                        }
                    }
                    .padding(.vertical, feedFormat.feedVerticalPadding)
                }
                .refreshable {
                    await refreshContent()
                }
            }
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event)
        }
    }
    
    // MARK: - Refresh Function
    
    private func refreshContent() async {
        // Sync with CloudKit to get latest projects and events
        await store.syncWithCloudKit()
        
        // Small delay for better UX
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }
}

#Preview {
    DiscoverView()
}

// MARK: - Screen Size Previews

#if DEBUG

#Preview("Discover 393 × 852", traits: .fixedLayout(width: 393, height: 852)) {
    let _ = (ScreenSizeFormat.previewOverride = .size393x852)
    DiscoverView()
}

#Preview("Discover 402 × 874", traits: .fixedLayout(width: 402, height: 874)) {
    let _ = (ScreenSizeFormat.previewOverride = .size402x874)
    DiscoverView()
}

#Preview("Discover 430 × 932", traits: .fixedLayout(width: 430, height: 932)) {
    let _ = (ScreenSizeFormat.previewOverride = .size430x932)
    DiscoverView()
}

#Preview("Discover 440 × 956", traits: .fixedLayout(width: 440, height: 956)) {
    let _ = (ScreenSizeFormat.previewOverride = .size440x956)
    DiscoverView()
}

#endif
