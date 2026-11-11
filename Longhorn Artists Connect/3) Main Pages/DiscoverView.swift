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
    /// Discover's pages, in toolbar order, labeled by name in the toggle pill: the two
    /// scrolling feeds. The event calendar isn't one of these — it's a floating
    /// button over the feeds that takes over the page (see `showCalendar`).
    enum DiscoverCategory: String, CaseIterable, Identifiable {
        case projects = "Projects"
        case events = "Events"

        var id: String { rawValue }
    }

    /// Discover opens on Projects, the first page in the toggle.
    @State private var selection: DiscoverCategory = .projects

    /// Presents the event calendar as its own page, from the floating calendar button
    /// in the bottom-right corner of either feed.
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
        /// On-screen height of the toggle pill and the Organizations circle, after their
        /// `scaleEffect`s. The app-wide toolbar pill height (see
        /// `ScreenSizeFormat.toolbarPillHeight`) so every page's toolbar lines up.
        var pillHeight: CGFloat = ScreenSizeFormat.toolbarPillHeight

        func scaled(by k: CGFloat) -> ToolbarFormat {
            guard k != 1 else { return self }
            var f = self
            f.buttonWidth *= k
            f.buttonHeight *= k
            f.buttonFontSize *= k
            f.logoHeight *= k
            f.barHeight *= k
            f.pillHeight *= k
            if let p = f.pillLength { f.pillLength = p * k }
            return f
        }
    }

    private var toolbarSizeMultiplier: CGFloat { 1.0 }

    // MARK: - Per-Element Toolbar Tuning

    private var discoverSize: CGFloat { 1.1 }   // 1.15 · 0.9
    private var discoverOffsetX: CGFloat { -14 }    // + = right
    private var discoverOffsetY: CGFloat { -2 }    // + = down

    private var toggleSize: CGFloat { 1.15 }
    private var toggleOffsetX: CGFloat { 1 }
    private var toggleOffsetY: CGFloat { -1 }     // vertically centers the pill on the wordmark
    private var togglePadding: CGFloat { 0 }    // space reserved around it

    /// The toggle's halves use the shared toolbar button metrics at full width so the
    /// "Projects" / "Events" labels fit. Height matches the Home pill. `toggleLabelScale`
    /// sizes the label text against that same shared font size.
    /// Slightly under 1 so the pages (Projects | Events) leave the wordmark room.
    private var toggleWidthScale: CGFloat { 0.92 }
    private var toggleLabelScale: CGFloat { 0.9 }
    /// Gap between the Projects and Events halves. Negative pulls the two labels
    /// closer together by overlapping their (wider-than-the-text) hit areas.
    private var toggleSpacing: CGFloat { -4 }
    /// Sizes the selection highlight capsule (width and height) within each half.
    private var highlightScale: CGFloat { 0.97 }
    private var toggleInset: CGFloat { 4 }    // horizontal inset inside the pill

    private var toggleButtonWidth: CGFloat { toolbarFormat.buttonWidth * toggleWidthScale }
    private var toggleLabelSize: CGFloat { toolbarFormat.buttonFontSize * toggleLabelScale }

    private var orgSize: CGFloat { 1.3 }
    /// Scales the building icon inside the Organizations circle (the circle itself is unchanged).
    private var orgIconScale: CGFloat { 0.9 }
    private var orgOffsetX: CGFloat { 9 }
    private var orgOffsetY: CGFloat { -1 }     // vertically centers the circle on the wordmark
    private var orgPadding: CGFloat { 0 }

    private var toolbarFormat: ToolbarFormat {
        baseToolbarFormat.scaled(by: toolbarSizeMultiplier)
    }

    private var baseToolbarFormat: ToolbarFormat {
        switch ScreenSizeFormat.current {
        // The pill height comes from `ScreenSizeFormat.toolbarPillHeight`, shared by
        // every page, so the Discover toolbar buttons match Home's exactly.
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return ToolbarFormat(pillOffsetX: -14, pillOffsetY: -2, buttonWidth: 54, buttonHeight: 24, buttonFontSize: 13, logoHeight: 50, barHeight: 50)
        case .size402x874: // iPhone 16 Pro, 17
            return ToolbarFormat(pillOffsetX: -14, pillOffsetY: -2, buttonWidth: 55, buttonHeight: 25, buttonFontSize: 13, logoHeight: 51, barHeight: 50)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return ToolbarFormat(pillOffsetX: -15, pillOffsetY: -2, buttonWidth: 59, buttonHeight: 27, buttonFontSize: 14, logoHeight: 55, barHeight: 52)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return ToolbarFormat(pillOffsetX: -16, pillOffsetY: -2, buttonWidth: 61, buttonHeight: 28, buttonFontSize: 14, logoHeight: 56, barHeight: 53)
        // iPad: the orange bar spans the screen, but its contents stay iPhone-sized and
        // centered (see `ScreenSizeFormat.toolbarContentMaxWidth`), so these match the phone.
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return ToolbarFormat(pillOffsetX: -14, pillOffsetY: -2, buttonWidth: 55, buttonHeight: 25, buttonFontSize: 13, logoHeight: 51, barHeight: 50)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return ToolbarFormat(pillOffsetX: -14, pillOffsetY: -2, buttonWidth: 55, buttonHeight: 25, buttonFontSize: 13, logoHeight: 51, barHeight: 50)
        }
    }

    private var pillOffsetX: CGFloat { toolbarFormat.pillOffsetX }
    private var pillOffsetY: CGFloat { toolbarFormat.pillOffsetY }

    // MARK: - Feed Format Per Screen Size
    /// Tunable sizing for the main feed (project and event cards).
    /// - `rowSpacing`: vertical gap between cards.
    /// - `feedVerticalPadding`: padding above and below the whole list.
    /// (Cards' horizontal inset is `eventCardHorizontalPadding`, shared by both kinds.)
    private struct FeedFormat {
        var rowSpacing: CGFloat
        var feedVerticalPadding: CGFloat
    }

    /// Adjust the values in each case to tune the feed for that screen size.
    private var feedFormat: FeedFormat {
        switch ScreenSizeFormat.current {
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return FeedFormat(rowSpacing: 0, feedVerticalPadding: 5)
        case .size402x874: // iPhone 16 Pro, 17
            return FeedFormat(rowSpacing: 0, feedVerticalPadding: 5)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return FeedFormat(rowSpacing: 0, feedVerticalPadding: 18)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return FeedFormat(rowSpacing: 0, feedVerticalPadding: 5)
        // iPad shows two columns of cards in portrait and three in landscape (see
        // `FeedColumns`); each column is about an iPhone wide, so the phone insets apply.
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return FeedFormat(rowSpacing: 0, feedVerticalPadding: 5)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return FeedFormat(rowSpacing: 0, feedVerticalPadding: 5)
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

    /// Where the projects feed is scrolled. Same arrangement as `eventsScrollPosition`:
    /// opens on the upcoming-projects section with the completed projects off-screen above.
    @State private var projectsScrollPosition = ScrollPosition(
        id: DiscoverView.upcomingProjectsSectionID,
        anchor: .top
    )

    /// Scroll bookkeeping for intercepting the system's tab-reselection scroll-to-top.
    /// A plain (non-observable) reference so per-frame offset updates never invalidate
    /// the view — writing them to `@State` re-rendered Discover on every scroll frame and
    /// hung the feed during its first layout.
    @State private var tabReturnTracker = TabReturnTracker()

    // Recommendation-feed state (see Algorithms.swift): random-tie seed + snapshot of
    // seen posts for this load, refreshed by `reloadFeedOrdering()`.
    @State private var feedSeed: UInt64 = 0
    @State private var seenSnapshot: Set<UUID> = []
    
    // Define colors as static constants to prevent color changes on tab switch
    private static let darkBrownColor = Color(red: 80/255, green: 50/255, blue: 30/255).opacity(1.0)  // Darker for unselected
    private static let mediumBrownColor = Color(red: 140/255, green: 90/255, blue: 55/255).opacity(1.0)  // Brighter for selected
    
    // Computed property for projects from submissions
    // Uses visibleApprovedSubmissions so a post still uploading to CloudKit doesn't
    // appear here until its upload has fully confirmed. Deliberately NOT run through
    // `rankedFeed` (see `events`): projects are ordered by their first shoot date,
    // earliest first — see `upcomingProjects` and `completedProjects` for the two
    // halves of the feed.
    var projects: [Submission] {
        store.visibleApprovedSubmissions.filter { $0.type == .project }
    }

    /// A project with its shoot schedule parsed once, so splitting and sorting the feed
    /// doesn't re-parse the schedule text on every comparison.
    private struct ScheduledProject {
        let project: Submission
        /// First shoot day; `.distantFuture` for TBD/unparseable dates so they sort last.
        let firstDate: Date
        let isCompleted: Bool

        init(_ project: Submission, now: Date, startOfToday: Date) {
            self.project = project
            switch project.shootSchedule {
            case .days(let days)?:
                firstDate = days.first?.start ?? .distantFuture
                // Completed once the last shoot day (its wrap time, if stored) is behind us.
                isCompleted = days.last.map { ($0.end ?? $0.start) < now } ?? false
            case .range(let start, let end)?:
                firstDate = start
                // A legacy range carries dates only (no wrap time), so the shoot counts as
                // over once its last day is before today.
                isCompleted = (end ?? start) < startOfToday
            case nil:
                // Projects whose shoot dates are TBD (or otherwise unparseable) are never
                // treated as completed.
                firstDate = .distantFuture
                isCompleted = false
            }
        }
    }

    /// Every project with its schedule parsed exactly once per evaluation.
    private var scheduledProjects: [ScheduledProject] {
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        return projects.map { ScheduledProject($0, now: now, startOfToday: startOfToday) }
    }

    /// Projects still to shoot (and undated ones), soonest first, with every project
    /// whose shoot dates are TBD after all the dated ones.
    var upcomingProjects: [Submission] {
        scheduledProjects.filter { !$0.isCompleted }
            .sorted(by: shootDateOrder)
            .map(\.project)
    }

    /// Projects whose shoots have wrapped, oldest first so the most-recently-completed
    /// one sits just above the "Completed Projects" separator.
    var completedProjects: [Submission] {
        scheduledProjects.filter { $0.isCompleted }
            .sorted(by: shootDateOrder)
            .map(\.project)
    }

    /// Orders two projects by first shoot date, earliest first. Projects with no
    /// parseable date (e.g. "TBD") sort after every dated project. Ties fall back to
    /// title so the order stays fixed across refreshes instead of depending on the
    /// store's arrival order.
    private func shootDateOrder(_ lhs: ScheduledProject, _ rhs: ScheduledProject) -> Bool {
        guard lhs.firstDate == rhs.firstDate else { return lhs.firstDate < rhs.firstDate }
        return lhs.project.title.localizedCaseInsensitiveCompare(rhs.project.title) == .orderedAscending
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
                Group {
                    switch selection {
                    case .projects: projectsView
                    case .events:   eventsView
                    }
                }
                // The calendar floats over whichever feed is showing, in the same spot
                // as Network's compose button.
                .overlay(alignment: .bottomTrailing) {
                    calendarButton
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
                SchoolAssetImage("Discover")
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
                orgsButton
                    .fixedSize()
                    .layoutPriority(1)
            }
        // Match Home's row height so the logo can render at the same height (Home
        // caps its row at 44·scale but lets the fixed-height logo overflow the bar).
        .frame(height: toolbarFormat.logoHeight)
        .padding(.horizontal, 10)
        // iPad: keep the wordmark and buttons iPhone-sized and centered while the orange
        // bar behind them still runs edge to edge. `nil` (no limit) on iPhone.
        .frame(maxWidth: ScreenSizeFormat.toolbarContentMaxWidth)
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
        HStack(spacing: -15) {
            categoryButtons
        }
        .padding(.horizontal, toggleInset)
        // Pin the pre-scale height so that, after `scaleEffect(toggleSize)`, the pill
        // renders at exactly the Home toggle bar's height.
        .frame(width: toolbarFormat.pillLength, height: toolbarFormat.pillHeight / toggleSize)
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

    /// Diameter of the circular Organizations pill's icon frame. The circle itself adds
    /// 2pt of padding on each side and is then scaled by `orgSize`, so this is chosen to
    /// make the rendered circle exactly the Home toggle bar's height.
    private var orgPillDiameter: CGFloat { toolbarFormat.pillHeight / orgSize - 4 }

    // MARK: - Floating Calendar Button

    /// Tunable sizing for the floating calendar button, per screen size. Mirrors the
    /// Network tab's compose button so the two sit identically in the corner.
    /// - `diameter`: size of the circle.
    /// - `iconSize`: size of the calendar symbol inside it.
    /// - `edgePadding`: distance from the trailing and bottom edges of the feed.
    private struct CalendarButtonFormat {
        var diameter: CGFloat
        var iconSize: CGFloat
        var edgePadding: CGFloat
    }

    private var calendarButtonFormat: CalendarButtonFormat {
        switch ScreenSizeFormat.current {
        case .size393x852:
            return CalendarButtonFormat(diameter: 60, iconSize: 24, edgePadding: 20)
        case .size402x874:
            return CalendarButtonFormat(diameter: 61, iconSize: 24, edgePadding: 20)
        case .size430x932:
            return CalendarButtonFormat(diameter: 64, iconSize: 26, edgePadding: 22)
        case .size440x956:
            return CalendarButtonFormat(diameter: 65, iconSize: 26, edgePadding: 22)
        // iPad keeps the iPhone size for this button.
        case .iPad11:
            return CalendarButtonFormat(diameter: 61, iconSize: 24, edgePadding: 20)
        case .iPad13:
            return CalendarButtonFormat(diameter: 61, iconSize: 24, edgePadding: 20)
        }
    }

    /// Large brand-orange Liquid Glass circle floating over the feed, like Network's
    /// compose button. Opens the event calendar as its own page. Kept out of the
    /// Projects/Events toggle because it isn't a third feed — it's a separate page so the
    /// toggle keeps showing whichever feed you left behind.
    private var calendarButton: some View {
        Button {
            showCalendar = true
        } label: {
            Image(systemName: "calendar")
                .font(.system(size: calendarButtonFormat.iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: calendarButtonFormat.diameter, height: calendarButtonFormat.diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(BrandGlassCircle())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .accessibilityLabel("Event calendar")
        .padding(.trailing, calendarButtonFormat.edgePadding)
        .padding(.bottom, calendarButtonFormat.edgePadding)
    }

    /// Brand-orange tinted Liquid Glass circle on iOS 26+, solid orange circle otherwise.
    private struct BrandGlassCircle: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.tint(Color.brandOrange).interactive(), in: .circle)
            } else {
                content.background(Circle().fill(Color.brandOrange))
            }
        }
    }

    /// Circular pill (same brown as the toggle) with a building icon, opening the
    /// Organizations page. Shares the toggle's offset so the two travel together.
    private var orgsButton: some View {
        Button {
            showOrganizations = true
        } label: {
            Image(systemName: "building.2.fill")
                .font(.system(size: toolbarFormat.buttonFontSize * orgIconScale, weight: .semibold))
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
        HStack(spacing: toggleSpacing) {
            ForEach(DiscoverCategory.allCases) { category in
                Button {
                    // Reset before the swap so the incoming feed's first layout lands on
                    // its separator (see `resetFeedPosition`).
                    resetFeedPosition(for: category)
                    selection = category
                } label: {
                    // The feed's name, sized against the shared toolbar font so the
                    // pill stays level with the Organizations button beside it.
                    Text(category.rawValue)
                        .font(.system(size: toggleLabelSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: toggleButtonWidth, height: toolbarFormat.buttonHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        // HIGHLIGHTED CAPSULE
        .background(alignment: .leading) {
            Capsule()
                .fill(Color.pillBackground)
                .frame(width: highlightWidth, height: highlightHeight)
                .offset(x: highlightOffsetX)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selection)
        }
    }

    /// Size of the capsule selection indicator — each half's full width and the button
    /// height plus a small overhang, both reduced by `highlightScale`.
    private var highlightWidth: CGFloat { toggleButtonWidth * highlightScale }
    private var highlightHeight: CGFloat { (toolbarFormat.buttonHeight + 5) * highlightScale }

    /// Leading offset of the selection indicator for the current selection. Each half
    /// starts `toggleButtonWidth + toggleSpacing` after the previous one; the (narrower)
    /// highlight is then centered within that half.
    private var highlightOffsetX: CGFloat {
        let index = CGFloat(DiscoverCategory.allCases.firstIndex(of: selection) ?? 0)
        return index * (toggleButtonWidth + toggleSpacing) + (toggleButtonWidth - highlightWidth) / 2
    }
    
    // MARK: - Project Thumbnail/Detail View
    
    private var projectsView: some View {
        // Computed once per render rather than once per row (see `eventsView`).
        let completedProjects = self.completedProjects
        let upcomingProjects = self.upcomingProjects

        return Group {
            if completedProjects.isEmpty && upcomingProjects.isEmpty {
                List {
                    Text("No upcoming projects.")
                        .foregroundStyle(.secondary)
                }
                .listStyle(.plain)
            } else {
                // The feed's width decides how many columns of cards it shows: one on
                // iPhone, two or three on iPad (see `FeedColumns`). One scroll view
                // holds every column, so they all scroll together.
                GeometryReader { geo in
                    let columns = FeedColumns.count(forWidth: geo.size.width)
                    ScrollView {
                        LazyVStack(spacing: feedFormat.rowSpacing) {
                            // Completed projects sit above the separator; the feed opens
                            // scrolled just below them (see `projectsScrollPosition`), so
                            // they start out of view — the same shape as past events.
                            projectGrid(completedProjects, columns: columns)

                            // Separator + upcoming projects, held to at least a full
                            // screen tall so the separator can always be pinned to the
                            // top edge (see `eventsView`).
                            VStack(spacing: feedFormat.rowSpacing) {
                                if !completedProjects.isEmpty {
                                    feedSeparator("Completed Projects")
                                }

                                projectGrid(upcomingProjects, columns: columns)

                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: completedProjects.isEmpty ? nil : geo.size.height,
                                   alignment: .top)
                            .id(Self.upcomingProjectsSectionID)
                        }
                        .scrollTargetLayout()
                        .padding(.vertical, feedFormat.feedVerticalPadding)
                        // Without this, re-tapping the Discover tab runs the system's own
                        // scroll-to-top, which races (and beats) our scroll to the
                        // separator and leaves the completed projects showing.
                        .background(ScrollsToTopDisabler())
                    }
                    .scrollPosition($projectsScrollPosition, anchor: .top)
                    .refreshable {
                        await refreshContent()
                    }
                    // Completed projects arriving after the first layout push the
                    // upcoming section down; re-assert the opening position unless the
                    // reader has already scrolled.
                    .onChange(of: completedProjects.count) { _, _ in
                        guard !projectsScrollPosition.isPositionedByUser else { return }
                        scrollToUpcomingProjects()
                    }
                    // Switching the toggle back to Projects rebuilds this feed; always
                    // reopen on the upcoming projects.
                    .onAppear {
                        scrollToUpcomingProjects()
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y
                    } action: { _, newY in
                        tabReturnTracker.offsetY = newY
                        interceptSystemScrollToTop(currentY: newY, scrollToUpcoming: scrollToUpcomingProjects)
                    }
                    .onScrollPhaseChange { _, newPhase in
                        if newPhase == .interacting {
                            tabReturnTracker.pending = nil
                        }
                    }
                    .onChange(of: tabCoordinator.scrollToTopToken) { _, _ in
                        let animated = tabCoordinator.animatesNextScroll
                        if animated {
                            tabReturnTracker.pending = (tabReturnTracker.offsetY, Date().addingTimeInterval(0.8))
                        }
                        DispatchQueue.main.async {
                            if animated {
                                withAnimation { scrollToUpcomingProjects() }
                            } else {
                                scrollToUpcomingProjects()
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedProjectSubmission) { project in
            UpcomingProjectDetailView(submission: project)
        }
    }

    /// Scroll anchor id for the upcoming-projects section, which the projects feed opens on.
    private static let upcomingProjectsSectionID = "upcomingProjectsSection"

    /// Puts the projects feed back at its opening spot: the top of the upcoming projects,
    /// with every completed project (and the separator above it) scrolled off-screen.
    private func scrollToUpcomingProjects() {
        projectsScrollPosition.scrollTo(id: Self.upcomingProjectsSectionID, anchor: .top)
    }

    /// Returns `category`'s feed to its opening position before the toggle swaps it in.
    /// The two `ScrollPosition`s live on this view, not on the feeds, so they outlive a
    /// feed that's toggled away — and a rebuilt feed would otherwise restore wherever
    /// the reader last left it, up among the completed projects / past events. Replacing
    /// the position with a fresh id-anchored one makes the incoming feed's first layout
    /// land on its separator, exactly as it does on the very first appearance.
    private func resetFeedPosition(for category: DiscoverCategory) {
        switch category {
        case .projects:
            projectsScrollPosition = ScrollPosition(id: Self.upcomingProjectsSectionID, anchor: .top)
        case .events:
            eventsScrollPosition = ScrollPosition(id: Self.upcomingSectionID, anchor: .top)
        }
    }

    /// The cards for `projects`, `columns` across, each followed by a separator line
    /// unless it sits on the grid's bottom row (mirrors `eventGrid`).
    private func projectGrid(_ projects: [Submission], columns: Int) -> some View {
        let lastRowStart = FeedColumns.lastRowStart(itemCount: projects.count, columns: columns)
        return LazyVGrid(columns: FeedColumns.gridItems(count: columns), spacing: feedFormat.rowSpacing) {
            ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                VStack(spacing: feedFormat.rowSpacing) {
                    Button {
                        SeenContentTracker.shared.markSeen(project.id)
                        selectedProjectSubmission = project
                    } label: {
                        ProjectCard(project: project)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, eventCardHorizontalPadding)

                    if index < lastRowStart {
                        Divider()
                            .padding(.horizontal, eventCardHorizontalPadding)
                    }
                }
            }
        }
    }
    
    // MARK: - Event Thumbnail/Detail View
    
    private var eventsView: some View {
        // Computed once per render. Each of these filters and sorts the whole store, and
        // reading them inside the ForEach rows (e.g. `pastEvents.count` per divider)
        // multiplied that by the number of rows — the 1.40 Discover freeze.
        let pastEvents = self.pastEvents
        let upcomingEvents = self.upcomingEvents

        return Group {
            if pastEvents.isEmpty && upcomingEvents.isEmpty {
                List {
                    Text("No upcoming events.")
                        .foregroundStyle(.secondary)
                }
                .listStyle(.plain)
            } else {
                GeometryReader { geo in
                    // One column on iPhone, two or three on iPad (see `FeedColumns`).
                    let columns = FeedColumns.count(forWidth: geo.size.width)
                    ScrollView {
                        LazyVStack(spacing: feedFormat.rowSpacing) {
                            // Past events sit above the separator; the feed opens scrolled
                            // just below them (see `eventsScrollPosition`), so they start
                            // out of view.
                            eventGrid(pastEvents, columns: columns)

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

                                eventGrid(upcomingEvents, columns: columns)

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
                        // See the projects feed: keeps the system's tab-reselect
                        // scroll-to-top from fighting our scroll to the separator.
                        .background(ScrollsToTopDisabler())
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
                    // The opening position is resolved against the lazy grid's
                    // *estimated* row heights. As the past-event rows above the
                    // separator are actually measured, the content grows and the
                    // upcoming section drifts down out of position — most visibly
                    // when toggling back to Events with the store already full. Re-pin
                    // each time the content resizes, until the reader scrolls and
                    // takes over.
                    .onScrollGeometryChange(for: CGSize.self) { geometry in
                        geometry.contentSize
                    } action: { _, _ in
                        guard !eventsScrollPosition.isPositionedByUser else { return }
                        scrollToUpcomingEvents()
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y
                    } action: { _, newY in
                        tabReturnTracker.offsetY = newY
                        if tabReturnTracker.pending != nil {
                            print("[DiscoverScroll] y=\(newY) t=\(Date().timeIntervalSince1970)")
                        }
                        interceptSystemScrollToTop(currentY: newY, scrollToUpcoming: scrollToUpcomingEvents)
                    }
                    // A reader who grabs the feed takes over; stop watching for the
                    // system scroll so their own upward drag is never overridden.
                    .onScrollPhaseChange { _, newPhase in
                        if newPhase == .interacting {
                            tabReturnTracker.pending = nil
                        }
                    }
                    .onChange(of: tabCoordinator.scrollToTopToken) { _, _ in
                        let animated = tabCoordinator.animatesNextScroll
                        print("[DiscoverScroll] tab tap animated=\(animated) y=\(tabReturnTracker.offsetY) t=\(Date().timeIntervalSince1970)")
                        if animated {
                            tabReturnTracker.pending = (tabReturnTracker.offsetY, Date().addingTimeInterval(0.8))
                        }
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

    /// Catches the system's tab-reselection scroll-to-top the moment it starts moving the
    /// feed upward and replaces it with `scrollToUpcoming` (the upcoming events or
    /// upcoming projects, whichever feed is showing). Starting from (almost) where the
    /// reader was, that scroll stays put if they're already there and only moves down if
    /// they were up among the past events / completed projects.
    private func interceptSystemScrollToTop(currentY: CGFloat, scrollToUpcoming: () -> Void) {
        guard let pending = tabReturnTracker.pending else { return }
        guard Date() < pending.until else {
            tabReturnTracker.pending = nil
            return
        }
        guard currentY < pending.startY - 1 else { return }
        print("[DiscoverScroll] intercept from \(pending.startY) at \(currentY)")
        tabReturnTracker.pending = nil
        withAnimation { scrollToUpcoming() }
    }

    /// Mutable scroll bookkeeping kept outside SwiftUI's dependency tracking (see
    /// `tabReturnTracker`).
    private final class TabReturnTracker {
        /// The events feed's current vertical content offset.
        var offsetY: CGFloat = 0
        /// Set by a Discover tab tap: the offset at tap time and how long to watch for
        /// the system's scroll-to-top.
        var pending: (startY: CGFloat, until: Date)?
    }

    /// Event and project cards run nearly edge-to-edge: their internal date box + poster
    /// + details cluster already fills the width, so the poster sits close to the left
    /// edge rather than being pushed inward by a large inset.
    private var eventCardHorizontalPadding: CGFloat { 16 }

    /// The cards for `events`, `columns` across, each followed by a separator line unless
    /// it sits on the grid's bottom row. With one column this is the familiar single
    /// stack of cards with a line between each pair.
    private func eventGrid(_ events: [Submission], columns: Int) -> some View {
        let lastRowStart = FeedColumns.lastRowStart(itemCount: events.count, columns: columns)
        return LazyVGrid(columns: FeedColumns.gridItems(count: columns), spacing: feedFormat.rowSpacing) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                VStack(spacing: feedFormat.rowSpacing) {
                    eventButton(event)

                    if index < lastRowStart {
                        Divider()
                            .padding(.horizontal, eventCardHorizontalPadding)
                    }
                }
            }
        }
    }

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
        feedSeparator("Past Events")
    }

    /// A thin inline separator with `title` between an up-chevron on each side, marking
    /// the boundary between what's already happened (above) and what's upcoming (below).
    private func feedSeparator(_ title: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                Text(title)
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

// MARK: - Scroll-To-Top Disabler

/// Turns off `scrollsToTop` on the `UIScrollView` behind the SwiftUI `ScrollView` this
/// sits inside. Place it in the scroll content (e.g. as a `.background` of the content
/// stack) so the enclosing scroll view is up its superview chain.
///
/// Re-tapping the selected tab makes the system scroll the tab's scroll view to the
/// very top, through the same path as a status-bar tap. The Discover feeds don't want
/// the top — they return to the "Past Events" / "Completed Projects" separator instead
/// (see `DiscoverTabCoordinator`) — and when both scrolls run at once the system's wins,
/// leaving the past half of the feed showing. With `scrollsToTop` off, only ours runs.
private struct ScrollsToTopDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // The view isn't in the hierarchy yet during `makeUIView`; by the next turn of
        // the run loop its superview chain reaches the scroll view.
        DispatchQueue.main.async {
            var current = uiView.superview
            while let view = current {
                if let scrollView = view as? UIScrollView {
                    scrollView.scrollsToTop = false
                    return
                }
                current = view.superview
            }
        }
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

#Preview("Discover iPad 11\" portrait", traits: .fixedLayout(width: 834, height: 1194)) {
    let _ = (ScreenSizeFormat.previewOverride = .iPad11)
    DiscoverView()
}

#Preview("Discover iPad 11\" landscape", traits: .fixedLayout(width: 1194, height: 834)) {
    let _ = (ScreenSizeFormat.previewOverride = .iPad11)
    DiscoverView()
}

// TEMP-VERIFY-START
#Preview("TEMP Discover iPad portrait", traits: .fixedLayout(width: 834, height: 1194)) {
    let _ = (ScreenSizeFormat.previewOverride = .iPad11)
    let _ = (SubmissionStore_3_2.shared.approvedSubmissions = EventCategoryKind.allCases.map { Submission.sampleEvent($0) } + ProjectType.allCases.map { Submission.sampleProject($0) })
    DiscoverView()
}

#Preview("TEMP Discover iPad landscape", traits: .fixedLayout(width: 1194, height: 834)) {
    let _ = (ScreenSizeFormat.previewOverride = .iPad11)
    let _ = (SubmissionStore_3_2.shared.approvedSubmissions = EventCategoryKind.allCases.map { Submission.sampleEvent($0) } + ProjectType.allCases.map { Submission.sampleProject($0) })
    DiscoverView()
}
// TEMP-VERIFY-END

#endif
