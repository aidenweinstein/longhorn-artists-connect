import SwiftUI
import AVKit
// MARK: - Main Home View
struct HomeView_1: View {
    @ObservedObject var store: SubmissionStore_3_2 = .shared

    // MARK: - CloudKit Debugger
    @State private var showCloudKitDebugger = false

    // MARK: - Category Filter
    enum Category: String, CaseIterable, Identifiable {
        case all   = "All"
        case film  = "Film"
        case music = "Music"
        case people = "Reel"
        case design = "Design"
        case photography = "Photography"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all:         return "square.grid.2x2"
            case .film:        return "film"
            case .music:       return "music.note"
            case .design:      return "paintpalette.fill"
            case .people:      return "theatermasks.fill"
            case .photography: return "camera.fill"
            }
        }

        /// Per-icon size multiplier so visually heavier glyphs can be dialed down.
        var iconScale: CGFloat {
            switch self {
            case .design, .people, .photography: return 1.0   // 10% smaller
            default:                              return 1.2
            }
        }
    }

    // MARK: - Feed Mode
    /// Re-tapping the selected category's icon toggles it between the normal feed and
    /// "connections only" — just posts by or crediting people you're connected with.
    /// The highlight bubble behind the icon reflects the mode. (`fire` and `saved` are
    /// the retired trending / saved modes; nothing switches into them any more.)
    enum FeedMode: Hashable {
        case normal
        case fire
        case saved
        case connections

        var next: FeedMode {
            switch self {
            case .normal:      return .connections
            case .connections: return .normal
            case .fire:        return .saved
            case .saved:       return .normal
            }
        }
    }

    // MARK: - State
    @State private var selection: Category = .all
    /// Per-category feed mode. A missing entry means `.normal`.
    @State private var categoryModes: [Category: FeedMode] = [:]
    @State private var isSearching = false
    @State private var searchText = ""
    @FocusState private var isTextFieldFocused: Bool

    // Recommendation-feed state (see Algorithms.swift). `feedSeed` fixes the random order
    // of equal-like-count posts for this load; `seenSnapshot` is the set of already-opened
    // posts as of this load, so opening a post only sinks it to the bottom on the next
    // reload. Both are refreshed by `reloadFeedOrdering()` on appear and pull-to-refresh.
    @State private var feedSeed: UInt64 = 0
    @State private var seenSnapshot: Set<UUID> = []

    // Set after the first `onAppear`. The view stays alive inside the TabView, so
    // `onAppear` fires again every time the user switches back to Home; without this
    // guard each tab switch would re-roll the ordering and reshuffle the feed.
    @State private var hasLoadedFeed = false

    // The `feedTaskID` whose trending like counts were last fetched. `.task(id:)`
    // re-runs on every re-appear too, so this lets the fetch skip when the category and
    // mode haven't actually changed since the last run.
    @State private var lastLikeFetchID: String?

    // Pull-to-refresh count for this visit. Once it reaches
    // `ContentRecommender.refreshesBeforeFullRandom` the normal feed stops ranking and
    // serves posts in a completely random order, re-rolled on every further refresh.
    @State private var refreshCount = 0

    // Like counts captured at the last feed reload. The feed's like-based ordering reads
    // from this snapshot, not the live counts, so liking a post doesn't reshuffle the feed
    // (or eject you from an open post) until the next reload. Refreshed by
    // `reloadFeedOrdering()` on appear / pull-to-refresh, and after the trending fetch.
    @State private var likeSnapshot: [UUID: Int] = [:]

    // While a pull-to-refresh is in flight the feed keeps showing exactly what was on
    // screen when the pull started. The fresh ordering (and anything the sync brought
    // in) is swapped in only when the refresh ends and the spinner goes away — like
    // Instagram — instead of the feed re-sorting under the spinner while it can't scroll.
    @State private var refreshFreeze: RefreshFreeze?

    private struct RefreshFreeze {
        let selection: Category
        let mode: FeedMode
        let posts: [Submission]
    }

    // Directory profiles, so a name search can surface people (shown above posts).
    @ObservedObject private var userManager = UserProfileManager.shared
    @State private var selectedSearchUser: DirectoryUser?

    // Private connections, for the "connections only" feed mode.
    @ObservedObject private var connections = ConnectionsManager.shared

    // Student orgs, so a name search can surface them too (shown between people and posts).
    @ObservedObject private var orgStore: OrganizationStore = .shared
    @State private var selectedSearchOrg: Organization?

    // MARK: - Toolbar Format Per Screen Size
    /// Tunable toolbar item sizes and positions for the Home page.
    /// - `toolbarScale`: one knob to resize the toolbar bar + buttons at once
    ///   while keeping the current proportions. 1.0 = current size; e.g. 1.25
    ///   = 25% larger. (The Nexus logo is intentionally excluded.)
    /// - `pillOffsetX/Y`: nudges the entire draggable pill (outer capsule,
    ///   category buttons, highlight, and search button) from its default spot,
    ///   without affecting any other layout. Positive x moves it right,
    ///   negative x moves it left. Positive y moves it down, negative y up.
    /// - `logoHeight`: height of the Nexus logo image.
    private struct ToolbarFormat {
        var toolbarScale: CGFloat
        var pillOffsetX: CGFloat
        var pillOffsetY: CGFloat
        var logoHeight: CGFloat
        // iPad-only knobs (default to no-ops so iPhone layout is unaffected):
        /// Extra horizontal/vertical nudge applied to the logo.
        var logoOffsetX: CGFloat = 1
        var logoOffsetY: CGFloat = 0
        /// Fixed length (width) of the pill capsule. `nil` sizes it to its content.
        var pillLength: CGFloat? = nil
        /// How far down the orange toolbar bar extends. `nil` uses `60 * toolbarScale`.
        var barHeight: CGFloat? = nil

        /// Returns a copy with every size (logo, bar/row via `toolbarScale`, pill length)
        /// multiplied by `k`. Positions/offsets are left unchanged.
        func scaled(by k: CGFloat) -> ToolbarFormat {
            guard k != 1 else { return self }
            var f = self
            f.toolbarScale *= k
            f.logoHeight *= k
            if let b = f.barHeight { f.barHeight = b * k }
            if let p = f.pillLength { f.pillLength = p * k }
            return f
        }
    }

    /// Universal toolbar resizer: one knob that scales every toolbar element (logo, bar,
    /// pills, fonts) across ALL screen sizes at once, keeping the per-device proportions
    /// tuned below. 1.0 = current size; 1.2 = 20% larger; 0.85 = 15% smaller. Positions
    /// and offsets are untouched.
    private var toolbarSizeMultiplier: CGFloat { 1.0 }

    // MARK: - Per-Element Toolbar Tuning (affects every screen size at once)
    // Nexus asset (the wordmark logo).
    private var nexusSize: CGFloat { 1.6 }      // size multiplier
    private var nexusOffsetX: CGFloat { -3.6 }     // + = right
    private var nexusOffsetY: CGFloat { -2 }     // + = down
    // Toggle bar (the category pill / search bar).
    private var toggleSize: CGFloat { 0.9 }
    private var toggleOffsetX: CGFloat { 10 }
    private var toggleOffsetY: CGFloat { -2.8 }
    private var togglePadding: CGFloat { 0 }    // space reserved around it

    /// The per-device format, universally scaled by `toolbarSizeMultiplier`, with the
    /// Nexus asset additionally scaled by `nexusSize`.
    private var toolbarFormat: ToolbarFormat {
        var f = baseToolbarFormat.scaled(by: toolbarSizeMultiplier)
        f.logoHeight *= nexusSize
        return f
    }

    /// Adjust the values in each case to tune the toolbar for that screen size.
    private var baseToolbarFormat: ToolbarFormat {
        switch ScreenSizeFormat.current {
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return ToolbarFormat(toolbarScale: 1.0, pillOffsetX: -9, pillOffsetY: -2, logoHeight: 26, barHeight: 50)
        case .size402x874: // iPhone 16 Pro, 17
            return ToolbarFormat(toolbarScale: 1.02, pillOffsetX: -9, pillOffsetY: -2, logoHeight: 27, barHeight: 50)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return ToolbarFormat(toolbarScale: 1.09, pillOffsetX: -10, pillOffsetY: -2, logoHeight: 29, barHeight: 52)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return ToolbarFormat(toolbarScale: 1.12, pillOffsetX: -10, pillOffsetY: -2, logoHeight: 29, barHeight: 53)
        // iPad: the orange bar spans the screen, but its contents stay iPhone-sized and
        // centered (see `ScreenSizeFormat.toolbarContentMaxWidth`), so these match the phone.
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return ToolbarFormat(toolbarScale: 1.02, pillOffsetX: -9, pillOffsetY: -2, logoHeight: 27, barHeight: 50)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return ToolbarFormat(toolbarScale: 1.02, pillOffsetX: -9, pillOffsetY: -2, logoHeight: 27, barHeight: 50)
        }
    }

    private var toolbarScale: CGFloat { toolbarFormat.toolbarScale }
    private var pillOffsetX: CGFloat { toolbarFormat.pillOffsetX }
    private var pillOffsetY: CGFloat { toolbarFormat.pillOffsetY }

    // MARK: - Feed Format Per Screen Size
    /// Tunable sizing for the main feed.
    /// - `postSpacing`: vertical gap between feed posts.
    /// - `feedHorizontalPadding`: insets the whole feed from the screen edges.
    ///   0 = full-bleed cards; larger values make the cards narrower. Because
    ///   the post cards are width-driven, this is the main size knob for them.
    /// - `columnSpacing`: horizontal gap between feed columns on iPad. The iPhone feed
    ///   is a single column, so it has no effect there.
    private struct FeedFormat {
        var postSpacing: CGFloat
        var feedHorizontalPadding: CGFloat
        var columnSpacing: CGFloat = 0
    }

    /// Adjust the values in each case to tune the feed for that screen size.
    private var feedFormat: FeedFormat {
        switch ScreenSizeFormat.current {
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return FeedFormat(postSpacing: 0, feedHorizontalPadding: 0)
        case .size402x874: // iPhone 16 Pro, 17
            return FeedFormat(postSpacing: 0, feedHorizontalPadding: 0)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return FeedFormat(postSpacing: 0, feedHorizontalPadding: 0)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return FeedFormat(postSpacing: 0, feedHorizontalPadding: 0)
        // iPad shows two columns of posts in portrait and three in landscape (see
        // `FeedColumns`); the cards themselves stay iPhone-sized.
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return FeedFormat(postSpacing: 0, feedHorizontalPadding: 0, columnSpacing: 0)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return FeedFormat(postSpacing: 0, feedHorizontalPadding: 0, columnSpacing: 0)
        }
    }

    // MARK: - Draggable pill layout
    /// Width of each category button's hit area.
    private var pillButtonWidth: CGFloat { 32 * toolbarScale }
    /// Height of each category button's hit area.
    private var pillButtonHeight: CGFloat { 28 * toolbarScale }
    /// Visual height of the filter pill: its content (button height + 5pt padding
    /// top/bottom) after the `toggleSize` shrink. The search bar is pinned to this so
    /// both states of the pill are exactly the same height.
    private var pillVisualHeight: CGFloat { (pillButtonHeight + 10 * toolbarScale) * toggleSize }
    /// Live x-position of the pill's center (in the "pillTrack" space) while
    /// the user is dragging. `nil` when not dragging (pill follows `selection`).
    @State private var pillDragX: CGFloat? = nil

    private let startInSearchMode: Bool

    init(startInSearchMode: Bool = false) {
        self.startInSearchMode = startInSearchMode
        
    }

// BODY
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                // Live upload banner: shows while a just-posted film/music/reel is
                // still uploading to CloudKit, then disappears once it lands.
                HomeUploadBanner()
                // Moderators only: fields the deployed CloudKit schema is missing.
                SchemaGapBanner()
                // Live shows (e.g. Longhorn Late Night) — see LiveStreams.swift.
                LiveStreamBanner()
                // The feed takes the rest of the page. Its width decides how many
                // columns of posts it shows: one on iPhone, two or three on iPad.
                GeometryReader { geo in
                    feedContent(width: geo.size.width)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if startInSearchMode { isSearching = true }
                // Only roll the feed ordering on the first appearance. Switching tabs
                // and coming back keeps whatever order was already on screen; a fresh
                // order is pull-to-refresh's job.
                guard !hasLoadedFeed else { return }
                hasLoadedFeed = true
                reloadFeedOrdering()
            }
            .task { await userManager.fetchAllUsers() }
            .sheet(isPresented: $showCloudKitDebugger) {
                CloudKitDebuggerView()
            }
            .sheet(item: $selectedSearchUser) { user in
                NavigationStack {
                    UserPortfolioView(user: UserProfile(directoryUser: user), portfolioOrder: user.portfolioOrder)
                }
            }
            // Org pages present from the bottom (no back button), matching the Organizations list.
            .sheet(item: $selectedSearchOrg) { org in
                NavigationStack { OrganizationPageView(organization: org) }
                    .presentationDragIndicator(.hidden)
            }
        }
    }

// ORANGE HEADER
    private var topBar: some View {
        toolbarContent
            .frame(height: 44 * toolbarScale)
            .padding(.horizontal, 12 * toolbarScale)
            // iPad: keep the logo + pill iPhone-sized and centered while the orange bar
            // behind them still runs edge to edge. `nil` (no limit) on iPhone.
            .frame(maxWidth: ScreenSizeFormat.toolbarContentMaxWidth)
            .padding(.vertical, 6 * toolbarScale)
            // Fixed header height (uniform across all five pages) with the orange bleeding
            // up behind the status bar / Dynamic Island. Content taller than the bar just
            // centers within it.
            .frame(maxWidth: .infinity, minHeight: toolbarFormat.barHeight ?? 56 * toolbarScale, maxHeight: toolbarFormat.barHeight ?? 56 * toolbarScale)
            .background(Color.brandOrange, ignoresSafeAreaEdges: .top)
            .animation(nil, value: isSearching)
    }

// SCROLLABLE FEED
    /// The feed laid out for `width` points: one column on iPhone, two or three on
    /// iPad (see `FeedColumns`). Every column lives in the same scroll view, so they
    /// all scroll together.
    @ViewBuilder
    private func feedContent(width: CGFloat) -> some View {
        let columns = FeedColumns.count(forWidth: width)
        // Handed to each card so its first frame is already the right height, instead
        // of starting at full-screen width and snapping once it has measured itself.
        let columnWidth = FeedColumns.columnWidth(
            totalWidth: width,
            count: columns,
            spacing: feedFormat.columnSpacing,
            horizontalPadding: feedFormat.feedHorizontalPadding
        )
        if isSearching && searchText.isEmpty {
            searchPlaceholder
        } else if isSearching {
            // Search results: matching profiles first, then orgs, then matching posts.
            let profiles = matchingProfiles
            let orgs = matchingOrganizations
            let posts = postsForSelection
            if profiles.isEmpty && orgs.isEmpty && posts.isEmpty {
                List {
                    Text(emptyStateMessage)
                        .foregroundStyle(.secondary)
                }
                .listStyle(.plain)
                .refreshable { await refreshSubmissions() }
            } else {
                ScrollView {
                    feedGrid(columns: columns) {
                        ForEach(profiles) { user in
                            searchProfileRow(user)
                        }
                        ForEach(orgs) { org in
                            searchOrganizationRow(org)
                        }
                        ForEach(posts) { post in
                            HomePostCard(post: post, showTypeIcon: selection == .all, estimatedWidth: columnWidth)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                // Keep the feed at full height while the search keyboard is up, so it
                // doesn't shrink — the cards render the same size as the normal feed.
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .refreshable { await refreshSubmissions() }
            }
        } else if displayedPosts.isEmpty {
            List {
                Text(emptyStateMessage)
                    .foregroundStyle(.secondary)
            }
            .listStyle(.plain)
            .refreshable { await refreshSubmissions() }
        } else {
            ScrollView {
                feedGrid(columns: columns) {
                    ForEach(displayedPosts) { post in
                        HomePostCard(post: post, showTypeIcon: selection == .all, estimatedWidth: columnWidth)
                    }
                }
            }
            .scrollIndicators(.hidden)
            // Trending mode needs authoritative like counts; fetch them for the posts
            // in view whenever the category or its mode changes.
            .task(id: feedTaskID) { await refreshVisibleLikeCountsIfNeeded() }
            .refreshable { await refreshSubmissions() }
        }
    }

    /// The feed's layout: `columns` equal-width, top-aligned columns of cards, inset
    /// from the screen edges by the feed padding. With one column this is exactly the
    /// old single stack of full-width cards.
    private func feedGrid<Content: View>(columns: Int, @ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: FeedColumns.gridItems(count: columns, spacing: feedFormat.columnSpacing),
            spacing: feedFormat.postSpacing
        ) {
            content()
        }
        .padding(.horizontal, feedFormat.feedHorizontalPadding)
    }

    /// What the normal (non-search) feed shows: the snapshot frozen at the start of a
    /// pull-to-refresh while that refresh is still running for this category and mode,
    /// otherwise the live ordering.
    private var displayedPosts: [Submission] {
        if let freeze = refreshFreeze, freeze.selection == selection, freeze.mode == currentMode {
            return freeze.posts
        }
        return postsForSelection
    }

    /// Re-runs the trending like-count fetch when the selected category or its mode changes.
    private var feedTaskID: String { "\(selection.rawValue)|\(currentMode)" }

    /// When the current feed is on fire, pull each visible post's like count from
    /// CloudKit so the trending sort reflects real cross-user engagement.
    private func refreshVisibleLikeCountsIfNeeded() async {
        guard currentMode == .fire else { return }
        // `.task(id:)` also re-runs when the tab is re-shown. Skip the fetch (and the
        // reorder it can cause) unless the category or mode actually changed.
        guard lastLikeFetchID != feedTaskID else { return }
        lastLikeFetchID = feedTaskID
        for post in postsForSelection {
            await store.refreshLikeCount(for: post.id)
        }
        // Freeze the freshly-fetched counts so the trending order settles once and stays
        // put until the next reload, rather than reshuffling as each fetch lands or when
        // the user likes something.
        likeSnapshot = store.likeCounts
    }

    /// A tappable profile card shown at the top of search results. Opens the
    /// person's portfolio, matching the directory's behavior.
    private func searchProfileRow(_ user: DirectoryUser) -> some View {
        Button {
            selectedSearchUser = user
        } label: {
            HStack(spacing: 12) {
                if let data = user.profileImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.brandOrange.opacity(0.2))
                            .frame(width: 44, height: 44)
                        Text(user.initials)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.brandOrange)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(user.fullName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        UserVerifiedBadge(userID: user.id)
                            .font(.subheadline)
                    }
                    if !user.rolesString.isEmpty {
                        Text(user.rolesString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Show the person's class year (e.g. '28) instead of a chevron.
                if !user.graduationYear.isEmpty {
                    Text("'\(user.graduationYear.suffix(2))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    /// A tappable org card shown in search results (between profiles and posts). Uses the
    /// same card and height as the Organizations list, and opens the org's page.
    private func searchOrganizationRow(_ org: Organization) -> some View {
        Button {
            selectedSearchOrg = org
        } label: {
            OrganizationCard(organization: org)
                .frame(maxWidth: .infinity)
                .frame(height: 96)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    /// Orgs whose name matches the search query (exact → contains → similar).
    private var matchingOrganizations: [Organization] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }

        let orgs = orgStore.organizations
        let exact = orgs.filter { $0.name.lowercased() == q }
        let contains = orgs.filter { $0.name.lowercased() != q && $0.name.lowercased().contains(q) }
        let similar = orgs
            .filter { o in !exact.contains(where: { $0.id == o.id }) && !contains.contains(where: { $0.id == o.id }) }
            .filter { levenshteinDistance($0.name.lowercased(), q) <= 2 }
            .sorted { levenshteinDistance($0.name.lowercased(), q) < levenshteinDistance($1.name.lowercased(), q) }

        return exact + contains + similar
    }

    /// Directory profiles whose name matches the search query (exact → contains →
    /// similar). Guests are excluded, matching the directory.
    private var matchingProfiles: [DirectoryUser] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }

        let users = userManager.allUsers.filter { $0.isUTStudent }
        let exact = users.filter { $0.fullName.lowercased() == q }
        let contains = users.filter { $0.fullName.lowercased() != q && $0.fullName.lowercased().contains(q) }
        let similar = users
            .filter { u in !exact.contains(where: { $0.id == u.id }) && !contains.contains(where: { $0.id == u.id }) }
            .filter { levenshteinDistance($0.fullName.lowercased(), q) <= 2 }
            .sorted { levenshteinDistance($0.fullName.lowercased(), q) < levenshteinDistance($1.fullName.lowercased(), q) }

        return exact + contains + similar
    }

// STANDARD & SEARCH VIEW SWITCHER
    @ViewBuilder
    private var toolbarContent: some View {
        HStack(spacing: -10) {
            if !isSearching {
                nexusLogo
                Spacer(minLength: 8)
            }
            persistentPill
        }
    }

 // SMOOTH PILL TRANSITION
    private var persistentPill: some View {
        ZStack {
            Capsule()
                .fill(isSearching ? Color.pillActive : Color.pillActive)
            if isSearching {
                searchBar
                    .transition(.opacity)
            } else {
                filterPill
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: isSearching ? .infinity : toolbarFormat.pillLength)
        // Pin the pre-scale height so that, after `scaleEffect(toggleSize)`, the pill
        // renders at the app-wide toolbar pill height every other page matches.
        .frame(height: ScreenSizeFormat.toolbarPillHeight / toggleSize)
        // The horizontal nudge is meant for the narrow filter pill; applying it to
        // the full-width search bar pushes its left edge too far out, so skip it
        // while searching to keep both ends evenly inset.
        .offset(x: isSearching ? 0 : pillOffsetX, y: pillOffsetY)
        .padding(isSearching ? 0 : togglePadding)
        .scaleEffect(isSearching ? 1.0 : toggleSize)
        .offset(x: isSearching ? 4 : toggleOffsetX, y: isSearching ? -3 : toggleOffsetY)
    }

// IN SEARCH BAR
    private var searchBar: some View {
        HStack(spacing: 3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15 * toolbarScale, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24 * toolbarScale, height: 24 * toolbarScale, alignment: .trailing)

            TextField("Search", text: $searchText, axis: .vertical)
                .textFieldStyle(.plain)
                // Fixed size so the field renders the same regardless of the
                // device's Dynamic Type setting, matching the preview.
                .font(.system(size: 17))
                // Always white so it stays legible on the orange toolbar.
                .foregroundStyle(.white)
                .tint(.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity)
                .autocorrectionDisabled()
                .focused($isTextFieldFocused)

            Button {
                isTextFieldFocused = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isSearching = false
                    searchText = ""
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16 * toolbarScale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 14 * toolbarScale)
        .offset(y:0)
        // Pin to the filter pill's visual height so switching into search doesn't
        // make the toolbar taller than normal.
        .frame(maxWidth: .infinity, minHeight: pillVisualHeight, maxHeight: pillVisualHeight)
    }

// NEXUS LOGO
    private var nexusLogo: some View {
        SchoolAssetImage("Nexus")
            .scaledToFill()
            .frame(height: toolbarFormat.logoHeight)
            .offset(x: 5, y: -1)
            .offset(x: toolbarFormat.logoOffsetX, y: toolbarFormat.logoOffsetY)
            .offset(x: nexusOffsetX, y: nexusOffsetY)
            .onTapGesture(count: 5) {
                showCloudKitDebugger = true
            }
            .transition(.opacity.combined(with: .scale))
    }

// TOOLBAR
    private var filterPill: some View {
        HStack(spacing: -5) {
            categoryButtons
            searchOpenButton
        }
        .padding(5 * toolbarScale)
    }

// CATEGORY BUTTONS
    private var categoryButtons: some View {
        HStack(spacing: 0) {
            ForEach(Category.allCases) { category in
                Image(systemName: category.icon)
                    .font(.system(size: 16 * toolbarScale * category.iconScale, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: pillButtonWidth, height: pillButtonHeight)
                    .contentShape(Rectangle())
            }
        }
        // The highlight pill lives behind the icons so it never hides them. Its look
        // reflects the current feed mode (plain / fiery / ribbon).
        .background(alignment: .leading) {
            modeHighlight
                .frame(width: 35 * toolbarScale, height: 35 * toolbarScale)
                .offset(x: pillCenterX - 35 * toolbarScale / 2)
                .animation(
                    pillDragX == nil
                        ? .spring(response: 0.3, dampingFraction: 0.7)
                        : .interactiveSpring(response: 0.15, dampingFraction: 0.85),
                    value: pillCenterX
                )
        }
        .coordinateSpace(name: "pillTrack")
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("pillTrack"))
                .onChanged { value in
                    pillDragX = value.location.x
                }
                .onEnded { value in
                    let index = nearestCategoryIndex(forX: value.location.x)
                    let tapped = Category.allCases[index]
                    // Tapping selects the category. Re-tapping the current one toggles
                    // it between the normal feed and "connections only".
                    if tapped == selection {
                        categoryModes[tapped] = currentMode == .connections ? .normal : .connections
                    } else {
                        selection = tapped
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        pillDragX = nil
                    }
                }
        )
    }

    /// Center x-position of the highlight pill within the category button row.
    /// Follows the finger while dragging, otherwise tracks the current selection.
    private var pillCenterX: CGFloat {
        let count = Category.allCases.count
        let minX = pillButtonWidth / 2
        let maxX = pillButtonWidth * CGFloat(count) - pillButtonWidth / 2
        if let pillDragX {
            return min(max(pillDragX, minX), maxX)
        }
        let index = Category.allCases.firstIndex(of: selection) ?? 0
        return CGFloat(index) * pillButtonWidth + pillButtonWidth / 2
    }

    /// The index of the category button whose slot is closest to `x`.
    private func nearestCategoryIndex(forX x: CGFloat) -> Int {
        let count = Category.allCases.count
        let raw = Int(x / pillButtonWidth)
        return min(max(raw, 0), count - 1)
    }

    /// The feed mode of the currently selected category.
    private var currentMode: FeedMode { categoryModes[selection] ?? .normal }

    /// The highlight bubble behind the selected icon, styled per feed mode:
    /// normal = plain pill, fire = hot gradient + glow, saved = pill with a ribbon tail.
    @ViewBuilder
    private var modeHighlight: some View {
        switch currentMode {
        case .normal:
            Capsule().fill(Color.pillBackground)
        case .connections:
            // Same pill with a small "people" badge on its shoulder, so the category
            // icon stays readable and the badge says whose posts these are.
            Capsule()
                .fill(Color.pillBackground)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 7 * toolbarScale, weight: .bold))
                        .foregroundStyle(Color.brandOrange)
                        .padding(3 * toolbarScale)
                        .background(Circle().fill(.white))
                        .offset(x: 4 * toolbarScale, y: -4 * toolbarScale)
                }
        case .fire:
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.orange, Color.red],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color.orange.opacity(0.9), radius: 6)
                .shadow(color: Color.red.opacity(0.6), radius: 10)
        case .saved:
            Capsule()
                .fill(Color.pillBackground)
                // Two triangles below the bubble read as a ribbon/badge tail.
                .overlay(alignment: .bottom) {
                    RibbonTail()
                        .fill(Color.pillBackground)
                        .frame(width: 20 * toolbarScale, height: 13 * toolbarScale)
                        .offset(y: 11 * toolbarScale)
                }
        }
    }

    /// The magnifying glass button that opens search mode.
    private var searchOpenButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isSearching = true
            }
            isTextFieldFocused = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13 * toolbarScale, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32 * toolbarScale, height: 28 * toolbarScale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Blank background with prompt text shown while search is open
    /// but no query has been typed yet.
    private var searchPlaceholder: some View {
        VStack {
            Spacer()
            Text("Search for a specific artist, project, org, genre, etc...")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 60)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // =========================================================
    // MARK: - Data Helpers
    // =========================================================

    /// Which Home category a reel belongs to, based on its discipline. Reels are split
    /// across the feed tabs: acting & choreography stay in the Reel (theatre) tab,
    /// cinematography/editing/directing join Film, and composition/sound design join Music.
    private func reelHomeCategory(_ reelType: String) -> Category {
        switch reelType {
        case "Cinematography", "Editing", "Directing":
            return .film
        case "Composition", "Sound Design":
            return .music
        default: // Acting, Choreography (and any unspecified reel)
            return .people
        }
    }

    /// Filtered and sorted posts for the currently selected category.
    private var postsForSelection: [Submission] {
        // Festival-bound films appear in the feed like any other post; only their
        // video is withheld (a "Coming Soon" placeholder shows in its place).
        let publicPosts = store.visibleApprovedSubmissions

        // Searching always spans every category, regardless of the selected pill.
        // Events and projects only appear in Discover, not the home feed.
        if !searchText.isEmpty {
            let allHomePosts = publicPosts.filter { $0.type != .event && $0.type != .project }
            return searchPosts(in: allHomePosts, query: searchText)
        }

        var posts: [Submission]

        switch selection {
        case .all:
            posts = publicPosts.filter { $0.type != .event && $0.type != .project }
        case .film:
            // Films plus the film-discipline reels (cinematography / editing / directing).
            posts = publicPosts.filter {
                $0.type == .film || ($0.type == .reel && reelHomeCategory($0.reelType) == .film)
            }
        case .music:
            // Music plus the sound-discipline reels (composition / sound design).
            posts = publicPosts.filter {
                $0.type == .music || ($0.type == .reel && reelHomeCategory($0.reelType) == .music)
            }
        case .people:
            // The Reel (theatre) tab shows only performance reels (acting / choreography).
            posts = publicPosts.filter {
                $0.type == .reel && reelHomeCategory($0.reelType) == .people
            }
        case .design:
            posts = publicPosts.filter { $0.type == .design }
        case .photography:
            posts = publicPosts.filter { $0.type == .photography }
        }

        // Order by the selected category's mode.
        switch currentMode {
        case .normal:
            // After a few refreshes, drop the ranking and serve a completely random
            // order so repeated refreshing keeps surfacing different posts.
            if refreshCount >= ContentRecommender.refreshesBeforeFullRandom {
                return ContentRecommender.shuffle(posts, id: { $0.id }, seed: feedSeed)
            }
            // Default feed: recommendation ranking — most-liked first, ties randomized,
            // already-seen posts sunk to the bottom (see Algorithms.swift).
            let ranked = ContentRecommender.rank(
                posts,
                id: { $0.id },
                likeCount: orderingLikeCount,
                seenIDs: seenSnapshot,
                seed: feedSeed
            )
            // On All, lead with the kind of work the viewer's profile style is about
            // (films for filmmakers, performances for actors, music for musicians).
            if selection == .all, let style = ProfileStyle.current {
                return style.recommend(ranked)
            }
            return ranked
        case .fire:
            // Trending: likes decayed by age, so newer popular posts beat old ones.
            return posts.sorted { trendingScore($0) > trendingScore($1) }
        case .saved:
            // Everything you've saved (any collection) plus everything you've liked.
            return posts.filter { isSaved($0) }.sorted { $0.createdDate > $1.createdDate }
        case .connections:
            // Posts made by, or crediting, someone you're connected with — newest first.
            return posts.filter(isFromConnection).sorted { $0.createdDate > $1.createdDate }
        }
    }

    /// Whether a post was posted by, or credits, one of the user's connections.
    /// Matches by linked profile ID where a credit has one, else by name — the same
    /// rules the Collaborators stats use.
    private var isFromConnection: (Submission) -> Bool {
        let connected = connections.connectedUsers(in: userManager.allUsers)
        guard !connected.isEmpty else { return { _ in false } }
        let ids = Set(connected.map(\.messagingUserID))
        let names = Set(connected.map { Collaborator.nameKey(for: $0.fullName) })
        return { post in
            if names.contains(Collaborator.nameKey(for: post.submittedBy)) { return true }
            return post.creditEntries.contains { entry in
                if let id = Collaborator.normalizedProfileID(entry.profileID), ids.contains(id) { return true }
                return names.contains(Collaborator.nameKey(for: entry.name))
            }
        }
    }

    /// Trending rank: like count decayed by how long ago the post was created.
    /// `+2` avoids a divide-by-zero and softens the boost for brand-new posts.
    private func trendingScore(_ post: Submission) -> Double {
        let likes = Double(orderingLikeCount(post))
        let hours = max(0, Date().timeIntervalSince(post.createdDate) / 3600)
        return likes / pow(hours + 2, 1.5)
    }

    /// The like count used for feed *ordering*: the value captured at the last reload,
    /// falling back to the live count for posts that appeared since (so a newly arrived
    /// post still sorts sensibly on its first showing). Freezing the ordering key here is
    /// what keeps liking a post from reshuffling the feed until the next reload.
    private func orderingLikeCount(_ post: Submission) -> Int {
        likeSnapshot[post.id] ?? store.likeCount(for: post)
    }

    /// IDs of every saved post: the union of all collections' contents (including the
    /// system "Liked" collection) plus the user's liked set, so nothing is missed.
    private var savedPostIDs: Set<UUID> {
        var ids = store.likedSubmissionIds
        for collection in store.collections {
            ids.formUnion(collection.submissionIds)
        }
        return ids
    }

    private func isSaved(_ post: Submission) -> Bool {
        savedPostIDs.contains(post.id)
    }

    /// Tiered fuzzy search: exact → contains → similar (Levenshtein ≤ 2). Besides
    /// the title, "contains" also matches the creator and any credited cast/crew
    /// name, so searching a person surfaces the projects associated with them.
    private func searchPosts(in posts: [Submission], query: String) -> [Submission] {
        let q = query.lowercased()

        // Names credited on a post (creator, cast, crew, and music credits).
        func associatedNames(_ p: Submission) -> [String] {
            ([p.submittedBy] + (p.orderedCast + p.orderedCrew + p.orderedRecording + p.orderedProduction).map { $0.name })
                .map { $0.lowercased() }
        }

        let exact = posts.filter { $0.title.lowercased() == q }
        func isExact(_ p: Submission) -> Bool { exact.contains(where: { $0.id == p.id }) }

        let contains = posts.filter { p in
            guard !isExact(p) else { return false }
            if p.title.lowercased().contains(q) { return true }
            return associatedNames(p).contains { $0.contains(q) }
        }
        func isContains(_ p: Submission) -> Bool { contains.contains(where: { $0.id == p.id }) }

        let similar = posts
            .filter { !isExact($0) && !isContains($0) }
            .filter { levenshteinDistance($0.title.lowercased(), q) <= 2 }
            .sorted  { levenshteinDistance($0.title.lowercased(), q) < levenshteinDistance($1.title.lowercased(), q) }

        return exact + contains + similar
    }

    /// Minimum single-character edits to transform s1 into s2.
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        var last = [Int](0...s2.count)
        for (i, c1) in s1.enumerated() {
            var cur = [i + 1] + [Int](repeating: 0, count: s2.count)
            for (j, c2) in s2.enumerated() {
                cur[j + 1] = c1 == c2 ? last[j] : min(last[j], last[j + 1], cur[j]) + 1
            }
            last = cur
        }
        return last.last ?? 0
    }

    private var emptyStateMessage: String {
        if !searchText.isEmpty { return "No results found." }
        if currentMode == .saved { return "No saved posts yet. Like or bookmark posts to see them here." }
        if currentMode == .connections {
            return connections.connectedIDs.isEmpty
                ? "No connections yet. Connect with people from their profile to see their posts here."
                : "No posts from your connections yet. Tap the icon again to see everything."
        }
        switch selection {
        case .all:         return "No posts."
        case .film:        return "No films."
        case .music:       return "No music."
        case .design:      return "No designs."
        case .people:      return "No reels."
        case .photography: return "No photography."
        }
    }

    /// Pull-to-refresh. Freezes the feed as it currently appears, syncs with CloudKit
    /// (waiting at least 0.5s so the spinner doesn't flash), and only then — as the
    /// spinner is dismissed and the feed is scrollable again — swaps in the new ordering.
    /// Reordering up front made the posts shuffle under the spinner mid-refresh.
    private func refreshSubmissions() async {
        if searchText.isEmpty {
            refreshFreeze = RefreshFreeze(selection: selection, mode: currentMode, posts: postsForSelection)
        }
        refreshCount += 1
        await store.syncWithCloudKit()
        try? await Task.sleep(nanoseconds: 500_000_000)
        // Swap without animating, so the new feed simply appears rather than the old
        // cards visibly sliding into their new positions.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            reloadFeedOrdering()
            refreshFreeze = nil
        }
    }

    /// Re-rolls the recommendation ordering for a fresh page load: a new random seed for
    /// like-count ties, and a fresh snapshot of seen posts (so posts opened since the last
    /// load now sink to the bottom).
    private func reloadFeedOrdering() {
        feedSeed = ContentRecommender.freshSeed()
        seenSnapshot = SeenContentTracker.shared.snapshot()
        likeSnapshot = store.likeCounts
    }
}

// MARK: - Ribbon Tail

/// A swallowtail ribbon tail: a rectangle whose bottom edge is notched into two
/// downward triangles. Drawn just under the highlight bubble in "saved" mode so the
/// bubble reads as an award ribbon.
private struct RibbonTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))       // right tail point
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))        // inward notch
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))        // left tail point
        path.closeSubpath()
        return path
    }
}

// MARK: - Previews

#Preview {
    HomeView_1()
}

#if DEBUG

#Preview("Dark Mode") {
    HomeView_1()
        .preferredColorScheme(.dark)
}

#Preview("Search Mode") {
    HomeView_1(startInSearchMode: true)
}

#endif

// MARK: - Screen Size Previews

#if DEBUG

#Preview("Home 393 × 852", traits: .fixedLayout(width: 393, height: 852)) {
    let _ = (ScreenSizeFormat.previewOverride = .size393x852)
    HomeView_1()
}

#Preview("Home 402 × 874", traits: .fixedLayout(width: 402, height: 874)) {
    let _ = (ScreenSizeFormat.previewOverride = .size402x874)
    HomeView_1()
}

#Preview("Home 430 × 932", traits: .fixedLayout(width: 430, height: 932)) {
    let _ = (ScreenSizeFormat.previewOverride = .size430x932)
    HomeView_1()
}

#Preview("Home 440 × 956", traits: .fixedLayout(width: 440, height: 956)) {
    let _ = (ScreenSizeFormat.previewOverride = .size440x956)
    HomeView_1()
}

#Preview("Home iPad 11\" portrait", traits: .fixedLayout(width: 834, height: 1194)) {
    let _ = (ScreenSizeFormat.previewOverride = .iPad11)
    HomeView_1()
}

#Preview("Home iPad 11\" landscape", traits: .fixedLayout(width: 1194, height: 834)) {
    let _ = (ScreenSizeFormat.previewOverride = .iPad11)
    HomeView_1()
}

// TEMP-VERIFY-START
#Preview("TEMP iPad grid portrait", traits: .fixedLayout(width: 834, height: 1194)) {
    let _ = (ScreenSizeFormat.previewOverride = .iPad11)
    let _ = (SubmissionStore_3_2.shared.approvedSubmissions = ["Sample Film A", "Sample Film B", "Sample Film C"].map {
        Submission(id: UUID(), type: .film, title: $0, details: "", isApproved: true, submittedBy: "Preview")
    })
    HomeView_1()
}

#Preview("TEMP iPad grid landscape", traits: .fixedLayout(width: 1194, height: 834)) {
    let _ = (ScreenSizeFormat.previewOverride = .iPad11)
    let _ = (SubmissionStore_3_2.shared.approvedSubmissions = ["Sample Film A", "Sample Film B", "Sample Film C"].map {
        Submission(id: UUID(), type: .film, title: $0, details: "", isApproved: true, submittedBy: "Preview")
    })
    HomeView_1()
}
// TEMP-VERIFY-END

#endif
