import SwiftUI
import CloudKit
import Combine

/// Coordinates the Discover tab's "scroll to top" affordance. Selecting or re-tapping the
/// Discover tab bar button (see `ContentView`) requests a scroll; the events feed responds
/// by returning to the "Past Events" separator (just before past events) rather than the
/// very top, so past events stay off-screen above.
@MainActor
final class DiscoverTabCoordinator: ObservableObject {
    static let shared = DiscoverTabCoordinator()
    private init() {}

    /// Bumped each time the Discover tab is selected, including re-taps while it's already
    /// the selected tab.
    @Published var scrollToTopToken = 0

    /// Whether the pending request should animate. Re-taps animate, since the reader is
    /// already looking at the feed; arriving on the tab jumps instead, so the feed simply
    /// appears already parked on the upcoming events.
    private(set) var animatesNextScroll = true

    func requestScrollToTop(animated: Bool = true) {
        animatesNextScroll = animated
        scrollToTopToken += 1
    }
}

// MARK: - Main Discover View
struct DiscoverView: View {
    /// The two scrolling Discover feeds, in toolbar order, labeled by name in the toggle
    /// pill. The event calendar isn't one of these — it's a separate toolbar button that
    /// takes over the page (see `showCalendar`).
    enum DiscoverCategory: String, CaseIterable, Identifiable {
        case events = "Events"
        case projects = "Projects"

        var id: String { rawValue }

        /// The symbol shown in the toggle pill in place of the feed's name.
        var symbolName: String {
            switch self {
            case .events:   return "party.popper.fill"
            case .projects: return "list.bullet.clipboard.fill"
            }
        }
    }

    @State private var selection: DiscoverCategory = .events

    /// Presents the event calendar as its own page, from the standalone calendar button
    /// beside the toggle.
    @State private var showCalendar = false

    // MARK: - Toolbar Format Per Screen Size
    private struct ToolbarFormat {
        var pillOffsetX: CGFloat
        var pillOffsetY: CGFloat
        var buttonWidth: CGFloat
        var buttonHeight: CGFloat
        var buttonFontSize: CGFloat
        var logoHeight: CGFloat
        var logoOffsetX: CGFloat = 0
        var logoOffsetY: CGFloat = 0
        var pillLength: CGFloat? = nil
        var barHeight: CGFloat = 60

        func scaled(by k: CGFloat) -> ToolbarFormat {
            guard k != 1 else { return self }
            var f = self
            f.buttonWidth *= k
            f.buttonHeight *= k
            f.buttonFontSize *= k
            f.logoHeight *= k
            f.barHeight *= k
            if let p = f.pillLength { f.pillLength = p * k }
            return f
        }
    }

    private var toolbarSizeMultiplier: CGFloat { 1.0 }

    // MARK: - Per-Element Toolbar Tuning

    private var discoverSize: CGFloat { 1.15 }
    private var discoverOffsetX: CGFloat { -19 }    // + = right
    private var discoverOffsetY: CGFloat { -2 }    // + = down

    private var toggleSize: CGFloat { 1.15 }
    private var toggleOffsetX: CGFloat { 4 }
    private var toggleOffsetY: CGFloat { -2 }
    private var togglePadding: CGFloat { 0 }    // space reserved around it

    /// The toggle's halves run narrower than the shared toolbar button metrics (which the
    /// calendar and Organizations icons also use) so the pill reads as one compact
    /// switch. Height is left alone — it still matches the Home pill. `toggleSymbolScale`
    /// sizes the two symbols against that same shared font size.
    private var toggleWidthScale: CGFloat { 0.62 }
    private var toggleSymbolScale: CGFloat { 1.0 }
    private var toggleInset: CGFloat { 4 }    // horizontal inset inside the pill

    private var toggleButtonWidth: CGFloat { toolbarFormat.buttonWidth * toggleWidthScale }
    private var toggleSymbolSize: CGFloat { toolbarFormat.buttonFontSize * toggleSymbolScale }

    private var calendarSize: CGFloat { 1.3 }
    private var calendarOffsetX: CGFloat { 14 }
    private var calendarOffsetY: CGFloat { -2 }
    private var calendarPadding: CGFloat { 0 }

    private var orgSize: CGFloat { 1.3 }
    private var orgOffsetX: CGFloat { 17 }
    private var orgOffsetY: CGFloat { -2 }
    private var orgPadding: CGFloat { 0 }

    private var toolbarFormat: ToolbarFormat {
        baseToolbarFormat.scaled(by: toolbarSizeMultiplier)
    }

    private var baseToolbarFormat: ToolbarFormat {
        switch ScreenSizeFormat.current {
        // `buttonHeight` set so the pill's total height (buttonHeight + 10 padding) matches
        // the Home toggle pill (38 · toolbarScale · 0.9) on each device.
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return ToolbarFormat(pillOffsetX: -14, pillOffsetY: -2, buttonWidth: 54, buttonHeight: 24, buttonFontSize: 13, logoHeight: 50, barHeight: 50)
        case .size402x874: // iPhone 16 Pro, 17
            return ToolbarFormat(pillOffsetX: -14, pillOffsetY: -2, buttonWidth: 55, buttonHeight: 25, buttonFontSize: 13, logoHeight: 51, barHeight: 50)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return ToolbarFormat(pillOffsetX: -15, pillOffsetY: -2, buttonWidth: 59, buttonHeight: 27, buttonFontSize: 14, logoHeight: 55, barHeight: 52)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return ToolbarFormat(pillOffsetX: -16, pillOffsetY: -2, buttonWidth: 61, buttonHeight: 28, buttonFontSize: 14, logoHeight: 56, barHeight: 53)
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return ToolbarFormat(pillOffsetX: -18, pillOffsetY: -2, buttonWidth: 78, buttonHeight: 36, buttonFontSize: 17, logoHeight: 68, logoOffsetX: 0, logoOffsetY: 0, pillLength: nil, barHeight: 66)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return ToolbarFormat(pillOffsetX: -20, pillOffsetY: -2, buttonWidth: 90, buttonHeight: 43, buttonFontSize: 19, logoHeight: 78, logoOffsetX: 0, logoOffsetY: 0, pillLength: nil, barHeight: 72)
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
            return FeedFormat(rowSpacing: 0, cardHorizontalPadding: 48, feedVerticalPadding: 5)
        case .size402x874: // iPhone 16 Pro, 17
            return FeedFormat(rowSpacing: 0, cardHorizontalPadding: 48, feedVerticalPadding: 5)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return FeedFormat(rowSpacing: 0, cardHorizontalPadding: 40, feedVerticalPadding: 18)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return FeedFormat(rowSpacing: 0, cardHorizontalPadding: 48, feedVerticalPadding: 5)
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return FeedFormat(rowSpacing: 0, cardHorizontalPadding: 120, feedVerticalPadding: 16)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return FeedFormat(rowSpacing: 0, cardHorizontalPadding: 200, feedVerticalPadding: 16)
        }
    }
    
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    /// Drives the "return to top" behavior when the Discover tab is re-tapped.
    @ObservedObject private var tabCoordinator = DiscoverTabCoordinator.shared

    @State private var selectedProjectSubmission: Submission?
    @State private var selectedEvent: Submission?
    @State private var showOrganizations = false

    /// Where the events feed is scrolled. Starts out on the upcoming-events section so
    /// the feed's very first layout lands there with the past events already off-screen
    /// above, then tracks the reader as they scroll.
    @State private var eventsScrollPosition = ScrollPosition(
        id: DiscoverView.upcomingSectionID,
        anchor: .top
    )

    // Recommendation-feed state (see Algorithms.swift): random-tie seed + snapshot of
    // seen posts for this load, refreshed by `reloadFeedOrdering()`.
    @State private var feedSeed: UInt64 = 0
    @State private var seenSnapshot: Set<UUID> = []
    
    // Define colors as static constants to prevent color changes on tab switch
    private static let darkBrownColor = Color(red: 80/255, green: 50/255, blue: 30/255).opacity(1.0)  // Darker for unselected
    private static let mediumBrownColor = Color(red: 140/255, green: 90/255, blue: 55/255).opacity(1.0)  // Brighter for selected
    
    // Computed property for projects from submissions
    // Uses visibleApprovedSubmissions so a post still uploading to CloudKit doesn't
    // appear here until its upload has fully confirmed. Ordered by the recommendation
    // algorithm: most-liked first, ties randomized, seen posts sunk to the bottom.
    var projects: [Submission] {
        rankedFeed(store.visibleApprovedSubmissions.filter { $0.type == .project })
    }

    // Computed property for events from submissions.
    // Deliberately NOT run through `rankedFeed`: the recommendation algorithm randomizes
    // ties and sinks seen posts, re-rolling on every refresh. A feed of dates has to read
    // chronologically, so event order is never randomized — see `upcomingEvents` and
    // `pastEvents` for the date sorts applied to each half.
    var events: [Submission] {
        store.visibleApprovedSubmissions.filter { $0.type == .event }
    }

    /// An event is "past" once its end (or start, if it has no end) is before now.
    /// Undated events are never treated as past.
    private func isPastEvent(_ event: Submission) -> Bool {
        guard let reference = event.eventEndDate ?? event.eventStartDate else { return false }
        return reference < Date()
    }

    /// Upcoming (and undated) events, soonest first, so the feed opens on the next thing
    /// happening. Undated events fall to the bottom of the list.
    var upcomingEvents: [Submission] {
        events.filter { !isPastEvent($0) }
            .sorted { chronologicalOrder($0, $1, undatedDate: .distantFuture) }
    }

    /// Past events, oldest first so the most-recently-passed one sits just above the
    /// "Past Events" separator.
    var pastEvents: [Submission] {
        events.filter { isPastEvent($0) }
            .sorted { chronologicalOrder($0, $1, undatedDate: .distantPast) }
    }

    /// Orders two events by start date. Events sharing a date fall back to their title so
    /// the order stays fixed across refreshes instead of depending on the store's
    /// arrival order. `undatedDate` decides where an event with no date goes.
    private func chronologicalOrder(_ lhs: Submission, _ rhs: Submission, undatedDate: Date) -> Bool {
        let left = lhs.eventStartDate ?? undatedDate
        let right = rhs.eventStartDate ?? undatedDate
        guard left == right else { return left < right }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    /// Applies the shared recommendation ranking (see Algorithms.swift) to a feed slice.
    private func rankedFeed(_ items: [Submission]) -> [Submission] {
        ContentRecommender.rank(
            items,
            id: { $0.id },
            likeCount: { store.likeCount(for: $0) },
            seenIDs: seenSnapshot,
            seed: feedSeed
        )
    }

    /// Re-rolls the ordering for a fresh page load (see `HomeView.reloadFeedOrdering`).
    private func reloadFeedOrdering() {
        feedSeed = ContentRecommender.freshSeed()
        seenSnapshot = SeenContentTracker.shared.snapshot()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                switch selection {
                case .projects: projectsView
                case .events:   eventsView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { reloadFeedOrdering() }
            .sheet(item: $selectedEvent) { event in
                EventDetailView(event: event)
            }
        }
        .sheet(isPresented: $showOrganizations) {
            OrganizationsView()
        }
        // The calendar is its own page rather than a third feed — it owns its month
        // navigation and presents event details itself.
        .sheet(isPresented: $showCalendar) {
            EventCalendarView(events: events)
        }
    }

// ORANGE HEADER
    private var topBar: some View {
        HStack(spacing: 6) {
                Image("Discover")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: toolbarFormat.logoHeight, alignment: .leading)
            
                    .scaleEffect(discoverSize, anchor: .leading)
                    .offset(x: 10, y: -1)
                    .offset(x: toolbarFormat.logoOffsetX, y: toolbarFormat.logoOffsetY)
                    .offset(x: discoverOffsetX, y: discoverOffsetY)
                // Guaranteed gap so the wordmark never runs under the pill. The logo eats
                // all remaining width, so this Spacer stays at its minimum — enough to
                // clear the logo's +10 nudge and the pill's negative offset.
                Spacer(minLength: 24)
                filterPill
                    .fixedSize()
                    .layoutPriority(1)
                calendarButton
                    .fixedSize()
                    .layoutPriority(1)
                orgsButton
                    .fixedSize()
                    .layoutPriority(1)
            }
        // Match Home's row height so the logo can render at the same height (Home
        // caps its row at 44·scale but lets the fixed-height logo overflow the bar).
        .frame(height: toolbarFormat.logoHeight)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // Orange fills the bar and extends up behind the status bar / Dynamic Island.
        // `.background(_:ignoresSafeAreaEdges:)` is the reliable way to bleed a background
        // into the top safe area (a child Color + ignoresSafeArea didn't fill on non-initial
        // TabView tabs).
        .frame(maxWidth: .infinity, minHeight: toolbarFormat.barHeight, maxHeight: toolbarFormat.barHeight)
        .background(Color.brandOrange, ignoresSafeAreaEdges: .top)
    }

// TOOLBAR
    private var filterPill: some View {
        HStack(spacing: -10) {
            categoryButtons
        }
        .padding(.horizontal, toggleInset)
        .padding(.vertical, 6)
        .frame(width: toolbarFormat.pillLength)
        .background(
            Capsule()
                .fill(Color.pillActive)
        )
        .offset(x: pillOffsetX, y: pillOffsetY)
        // Universal per-element padding/size/position (all screen sizes).
        .padding(togglePadding)
        .scaleEffect(toggleSize)
        .offset(x: toggleOffsetX, y: toggleOffsetY)
        .offset(x:-3)
    }

    /// Diameter of the circular Organizations pill — matches the toggle pill's height.
    private var orgPillDiameter: CGFloat { toolbarFormat.buttonHeight + 4 }

    /// Standalone circular button that opens the event calendar as its own page. Kept out
    /// of the Projects/Events toggle because it isn't a third feed — it's a separate page
    /// so the toggle keeps showing whichever feed you left behind.
    private var calendarButton: some View {
        Button {
            showCalendar = true
        } label: {
            Image(systemName: "calendar")
                .font(.system(size: toolbarFormat.buttonFontSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: orgPillDiameter, height: orgPillDiameter)
                .contentShape(Circle())
                .padding(2)
        }
        .buttonStyle(.plain)
        .background(Circle().fill(Color.pillActive))
        .offset(x: pillOffsetX, y: pillOffsetY)
        // Universal per-element padding/size/position (all screen sizes).
        .padding(calendarPadding)
        .scaleEffect(calendarSize)
        .offset(x: calendarOffsetX, y: calendarOffsetY)
        .accessibilityLabel("Event calendar")
        .offset(x:-3)
    }

    /// Circular pill (same brown as the toggle) with a multi-person icon, opening the
    /// Organizations page. Shares the toggle's offset so the two travel together.
    private var orgsButton: some View {
        Button {
            showOrganizations = true
        } label: {
            Image(systemName: "person.3.fill")
                .font(.system(size: toolbarFormat.buttonFontSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: orgPillDiameter, height: orgPillDiameter)
                .contentShape(Circle())
                .padding(2)
        }
        .buttonStyle(.plain)
        .background(Circle().fill(Color.pillActive))
        .offset(x: pillOffsetX, y: pillOffsetY)
        // Universal per-element padding/size/position (all screen sizes).
        .padding(orgPadding)
        .scaleEffect(orgSize)
        .offset(x: orgOffsetX, y: orgOffsetY)
    }

// CATEGORY BUTTONS
    private var categoryButtons: some View {
        HStack(spacing: 0) {
            ForEach(DiscoverCategory.allCases) { category in
                Button {
                        selection = category
                } label: {
                    // Symbols rather than names — sized to match the calendar and
                    // Organizations icons beside the pill, not the smaller label text
                    // they replaced.
                    Image(systemName: category.symbolName)
                        .font(.system(size: toggleSymbolSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: toggleButtonWidth, height: toolbarFormat.buttonHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(category.rawValue)
            }
        }
        // HIGHLIGHTED CIRCLE
        .background(alignment: .leading) {
            Circle()
                .fill(Color.pillBackground)
                .frame(width: highlightDiameter, height: highlightDiameter)
                .offset(x: highlightOffsetX)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selection)
        }
    }

    /// Diameter of the round selection indicator — the pill's height plus the same 3pt
    /// overhang the capsule used, so it still fills the switch vertically.
    private var highlightDiameter: CGFloat { toolbarFormat.buttonHeight + 5 }

    /// Leading offset of the selection indicator for the current selection. Buttons sit
    /// flush against each other, so each half starts at `index * toggleButtonWidth`; the
    /// remainder centers the circle within that half.
    private var highlightOffsetX: CGFloat {
        let index = CGFloat(DiscoverCategory.allCases.firstIndex(of: selection) ?? 0)
        return index * toggleButtonWidth + (toggleButtonWidth - highlightDiameter) / 2
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
                                SeenContentTracker.shared.markSeen(project.id)
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
                GeometryReader { geo in
                    ScrollView {
                        LazyVStack(spacing: feedFormat.rowSpacing) {
                            // Past events sit above the separator; the feed opens scrolled
                            // just below them (see `eventsScrollPosition`), so they start
                            // out of view.
                            ForEach(Array(pastEvents.enumerated()), id: \.element.id) { index, event in
                                eventButton(event)

                                if index < pastEvents.count - 1 {
                                    Divider()
                                        .padding(.horizontal, eventCardHorizontalPadding)
                                }
                            }

                            // Separator + upcoming events, held to at least a full
                            // screen tall so the separator can always be pinned to the
                            // top edge — even with few/no upcoming events, the past
                            // events above it still scroll off-screen.
                            VStack(spacing: feedFormat.rowSpacing) {
                                // "Past Events" marker — the scroll-up affordance and the
                                // boundary between past and upcoming events.
                                if !pastEvents.isEmpty {
                                    pastEventsSeparator
                                }

                                ForEach(Array(upcomingEvents.enumerated()), id: \.element.id) { index, event in
                                    eventButton(event)

                                    if index < upcomingEvents.count - 1 {
                                        Divider()
                                            .padding(.horizontal, eventCardHorizontalPadding)
                                    }
                                }

                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: pastEvents.isEmpty ? nil : geo.size.height,
                                   alignment: .top)
                            // The feed's opening position. Tagged on the whole upcoming
                            // section (a direct child of the scroll target layout) rather
                            // than on the separator inside it, so the scroll view can find
                            // it without the lazy rows around it having been built yet.
                            .id(Self.upcomingSectionID)
                        }
                        .scrollTargetLayout()
                        .padding(.vertical, feedFormat.feedVerticalPadding)
                    }
                    // Opens on the upcoming section instead of the top of the content.
                    // `eventsScrollPosition` starts out pointing there, so the scroll view
                    // resolves it during its first layout pass — nothing flashes into view
                    // and no post-layout scroll is needed. SwiftUI also holds this position
                    // as past events stream in above it from the CloudKit sync.
                    .scrollPosition($eventsScrollPosition, anchor: .top)
                    .refreshable {
                        await refreshContent()
                    }
                    // Past events arriving after the first layout push the upcoming section
                    // down. SwiftUI normally keeps it pinned on its own, but re-assert in
                    // case the position was resolved before the sync landed. Skipped once
                    // the feed has been scrolled, so it never yanks the feed away.
                    .onChange(of: pastEvents.count) { _, _ in
                        guard !eventsScrollPosition.isPositionedByUser else { return }
                        scrollToUpcomingEvents()
                    }
                    // Switching the toggle back to Events rebuilds this feed, which would
                    // otherwise restore wherever the reader last left it — up among the
                    // past events. Always reopen on the upcoming events.
                    .onAppear {
                        scrollToUpcomingEvents()
                    }
                    .onChange(of: tabCoordinator.scrollToTopToken) { _, _ in
                        // Arriving on (or re-tapping) the Discover tab returns to the
                        // "Past Events" separator rather than the very top, so past events
                        // stay off-screen above. Deferred a runloop tick so it runs after
                        // the system's own tab-reselection scroll-to-top, letting ours win.
                        let animated = tabCoordinator.animatesNextScroll
                        DispatchQueue.main.async {
                            if animated {
                                withAnimation { scrollToUpcomingEvents() }
                            } else {
                                scrollToUpcomingEvents()
                            }
                        }
                    }
                }
            }
        }
    }

    /// Scroll anchor id for the upcoming-events section, which the events feed opens on.
    private static let upcomingSectionID = "upcomingEventsSection"

    /// Puts the feed back at its opening spot: the top of the upcoming events, with every
    /// past event (and the "Past Events" separator above it) scrolled off-screen.
    private func scrollToUpcomingEvents() {
        eventsScrollPosition.scrollTo(id: Self.upcomingSectionID, anchor: .top)
    }

    /// Event cards run nearly edge-to-edge (their internal date box + flyer + details
    /// already fill the width), so they use a much smaller inset than project cards.
    private var eventCardHorizontalPadding: CGFloat { 16 }

    /// One tappable event card in the feed (marks it seen and opens its detail sheet).
    @ViewBuilder
    private func eventButton(_ event: Submission) -> some View {
        Button {
            SeenContentTracker.shared.markSeen(event.id)
            selectedEvent = event
        } label: {
            EventCard(event: event)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, eventCardHorizontalPadding)
    }

    /// A thin inline "Past Events" separator with an up-chevron on each side of the text,
    /// signaling that everything above it has already happened.
    private var pastEventsSeparator: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                Text("Past Events")
                Image(systemName: "chevron.up")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .fixedSize()

            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.horizontal, eventCardHorizontalPadding)
        .padding(.vertical, 8)
    }
    
    // MARK: - Refresh Function
    
    private func refreshContent() async {
        reloadFeedOrdering()
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

#Preview("Discover 440 × 956") {
    let _ = (ScreenSizeFormat.previewOverride = .size440x956)
    DiscoverView()
        .previewDevice("iPhone 16 Pro Max")
}

#endif
