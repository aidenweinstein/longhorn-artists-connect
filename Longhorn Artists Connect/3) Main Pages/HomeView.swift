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
    /// Each category cycles through three modes when its icon is re-tapped:
    /// normal (chronological strip) → fire (trending) → saved (your saved + liked) → normal.
    /// The highlight bubble behind the icon reflects the mode.
    enum FeedMode: Hashable {
        case normal
        case fire
        case saved

        var next: FeedMode {
            switch self {
            case .normal: return .fire
            case .fire:   return .saved
            case .saved:  return .normal
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

    // Pull-to-refresh count for this visit. Once it reaches
    // `ContentRecommender.refreshesBeforeFullRandom` the normal feed stops ranking and
    // serves posts in a completely random order, re-rolled on every further refresh.
    @State private var refreshCount = 0

    // Like counts captured at the last feed reload. The feed's like-based ordering reads
    // from this snapshot, not the live counts, so liking a post doesn't reshuffle the feed
    // (or eject you from an open post) until the next reload. Refreshed by
    // `reloadFeedOrdering()` on appear / pull-to-refresh, and after the trending fetch.
    @State private var likeSnapshot: [UUID: Int] = [:]

    // Directory profiles, so a name search can surface people (shown above posts).
    @ObservedObject private var userManager = UserProfileManager.shared
    @State private var selectedSearchUser: DirectoryUser?

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
        var logoOffsetX: CGFloat = 0
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
    private var nexusOffsetX: CGFloat { -7 }     // + = right
    private var nexusOffsetY: CGFloat { -2 }     // + = down
    // Toggle bar (the category pill / search bar).
    private var toggleSize: CGFloat { 0.95 }
    private var toggleOffsetX: CGFloat { 13 }
    private var toggleOffsetY: CGFloat { -3 }
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
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return ToolbarFormat(toolbarScale: 1.35, pillOffsetX: -12, pillOffsetY: -7, logoHeight: 35, logoOffsetX: 0, logoOffsetY: -10, pillLength: nil, barHeight: 66)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return ToolbarFormat(toolbarScale: 1.55, pillOffsetX: -14, pillOffsetY: -7, logoHeight: 41, logoOffsetX: 0, logoOffsetY: -10, pillLength: nil, barHeight: 72)
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
    private struct FeedFormat {
        var postSpacing: CGFloat
        var feedHorizontalPadding: CGFloat
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
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return FeedFormat(postSpacing: 0, feedHorizontalPadding: 0)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return FeedFormat(postSpacing: 0, feedHorizontalPadding: 0)
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
                feedContent
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if startInSearchMode { isSearching = true }
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
        }
    }

// ORANGE HEADER
    private var topBar: some View {
        toolbarContent
            .frame(height: 44 * toolbarScale)
            .padding(.horizontal, 12 * toolbarScale)
            .padding(.vertical, 6 * toolbarScale)
            // Fixed header height (uniform across all five pages) with the orange bleeding
            // up behind the status bar / Dynamic Island. Content taller than the bar just
            // centers within it.
            .frame(maxWidth: .infinity, minHeight: toolbarFormat.barHeight ?? 56 * toolbarScale, maxHeight: toolbarFormat.barHeight ?? 56 * toolbarScale)
            .background(Color.brandOrange, ignoresSafeAreaEdges: .top)
            .animation(nil, value: isSearching)
    }

// SCROLLABLE FEED
    @ViewBuilder
    private var feedContent: some View {
        if isSearching && searchText.isEmpty {
            searchPlaceholder
        } else if isSearching {
            // Search results: matching profiles first, then matching posts.
            let profiles = matchingProfiles
            let posts = postsForSelection
            if profiles.isEmpty && posts.isEmpty {
                List {
                    Text(emptyStateMessage)
                        .foregroundStyle(.secondary)
                }
                .listStyle(.plain)
                .refreshable { await refreshSubmissions() }
            } else {
                ScrollView {
                    LazyVStack(spacing: feedFormat.postSpacing) {
                        ForEach(profiles) { user in
                            searchProfileRow(user)
                        }
                        ForEach(posts) { post in
                            HomePostCard(post: post, showTypeIcon: selection == .all)
                        }
                    }
                    .padding(.horizontal, feedFormat.feedHorizontalPadding)
                }
                .scrollIndicators(.hidden)
                // Keep the feed at full height while the search keyboard is up, so it
                // doesn't shrink — the cards render the same size as the normal feed.
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .refreshable { await refreshSubmissions() }
            }
        } else if postsForSelection.isEmpty {
            List {
                Text(emptyStateMessage)
                    .foregroundStyle(.secondary)
            }
            .listStyle(.plain)
            .refreshable { await refreshSubmissions() }
        } else {
            ScrollView {
                LazyVStack(spacing: feedFormat.postSpacing) {
                    ForEach(postsForSelection) { post in
                        HomePostCard(post: post, showTypeIcon: selection == .all)
                    }
                }
                .padding(.horizontal, feedFormat.feedHorizontalPadding)
            }
            .scrollIndicators(.hidden)
            // Trending mode needs authoritative like counts; fetch them for the posts
            // in view whenever the category or its mode changes.
            .task(id: feedTaskID) { await refreshVisibleLikeCountsIfNeeded() }
            .refreshable { await refreshSubmissions() }
        }
    }

    /// Re-runs the trending like-count fetch when the selected category or its mode changes.
    private var feedTaskID: String { "\(selection.rawValue)|\(currentMode)" }

    /// When the current feed is on fire, pull each visible post's like count from
    /// CloudKit so the trending sort reflects real cross-user engagement.
    private func refreshVisibleLikeCountsIfNeeded() async {
        guard currentMode == .fire else { return }
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
                    Text(user.fullName)
                        .font(.headline)
                        .foregroundStyle(.primary)
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
        Image("Nexus")
            .resizable()
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
                    // Tapping selects the category. Re-tapping the current one is a no-op
                    // (the trending / saved feed modes were removed).
                    selection = Category.allCases[index]
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
            Text("Search for a specific artist, project, genre, etc...")
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
                return ContentRecommender.shuffle(posts, seed: feedSeed)
            }
            // Default feed: recommendation ranking — most-liked first, ties randomized,
            // already-seen posts sunk to the bottom (see Algorithms.swift).
            return ContentRecommender.rank(
                posts,
                id: { $0.id },
                likeCount: orderingLikeCount,
                seenIDs: seenSnapshot,
                seed: feedSeed
            )
        case .fire:
            // Trending: likes decayed by age, so newer popular posts beat old ones.
            return posts.sorted { trendingScore($0) > trendingScore($1) }
        case .saved:
            // Everything you've saved (any collection) plus everything you've liked.
            return posts.filter { isSaved($0) }.sorted { $0.createdDate > $1.createdDate }
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
        switch selection {
        case .all:         return "No posts."
        case .film:        return "No films."
        case .music:       return "No music."
        case .design:      return "No designs."
        case .people:      return "No reels."
        case .photography: return "No photography."
        }
    }

    /// Syncs with CloudKit, then waits 0.5s so the spinner doesn't flash too fast.
    private func refreshSubmissions() async {
        refreshCount += 1
        reloadFeedOrdering()
        await store.syncWithCloudKit()
        try? await Task.sleep(nanoseconds: 500_000_000)
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

#endif
