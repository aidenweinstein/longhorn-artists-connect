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
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all:    return "square.grid.2x2"
            case .film:   return "film"
            case .music:  return "music.note"
            case .people: return "star.fill"
            }
        }
    }

    // MARK: - State
    @State private var selection: Category = .all
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var navigatingToStudio: StudioType? = nil
    @FocusState private var isTextFieldFocused: Bool

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
    }

    /// Adjust the values in each case to tune the toolbar for that screen size.
    private var toolbarFormat: ToolbarFormat {
        switch ScreenSizeFormat.current {
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return ToolbarFormat(toolbarScale: 1.0, pillOffsetX: -9, pillOffsetY: -2, logoHeight: 50)
        case .size402x874: // iPhone 16 Pro, 17
            return ToolbarFormat(toolbarScale: 1.02, pillOffsetX: -9, pillOffsetY: -2, logoHeight: 51)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return ToolbarFormat(toolbarScale: 1.09, pillOffsetX: -10, pillOffsetY: -2, logoHeight: 55)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return ToolbarFormat(toolbarScale: 1.12, pillOffsetX: -10, pillOffsetY: -2, logoHeight: 56)
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return ToolbarFormat(toolbarScale: 1.35, pillOffsetX: -12, pillOffsetY: -7, logoHeight: 68, logoOffsetX: 0, logoOffsetY: -10, pillLength: nil, barHeight: 80)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return ToolbarFormat(toolbarScale: 1.55, pillOffsetX: -14, pillOffsetY: -7, logoHeight: 78, logoOffsetX: 0, logoOffsetY: -10, pillLength: nil, barHeight: 90)
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
            return FeedFormat(postSpacing: 0, feedHorizontalPadding: 10)
        case .size402x874: // iPhone 16 Pro, 17
            return FeedFormat(postSpacing: 0, feedHorizontalPadding: 10)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return FeedFormat(postSpacing: 0, feedHorizontalPadding: 10)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return FeedFormat(postSpacing: 0, feedHorizontalPadding: 10)
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
            }
            .task { await userManager.fetchAllUsers() }
            .sheet(isPresented: $showCloudKitDebugger) {
                CloudKitDebuggerView()
            }
            .sheet(item: $selectedSearchUser) { user in
                NavigationStack {
                    UserPortfolioView(user: UserProfile(directoryUser: user))
                }
            }
            .navigationDestination(item: $navigatingToStudio) { studioType in
                StudioPageView(studioType: studioType)
            }
        }
    }

// ORANGE HEADER
    private var topBar: some View {
        ZStack {
            Color.brandOrange
                .ignoresSafeArea(edges: .top)
                .transition(.identity)
                .animation(nil, value: isSearching)
                .frame(height: toolbarFormat.barHeight ?? 60 * toolbarScale)
            toolbarContent
                .frame(height: 44 * toolbarScale)
                .padding(.horizontal, 12 * toolbarScale)
                .padding(.vertical, 6 * toolbarScale)
        }
        .frame(maxWidth: .infinity)
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
            .refreshable { await refreshSubmissions() }
        }
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

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
        HStack(spacing: 8) {
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
                // Match the surrounding toolbar color instead of white/black.
                .foregroundStyle(Color.brandOrange)
                .tint(Color.brandOrange)
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
        .padding(.vertical, 8 * toolbarScale)
        .frame(maxWidth: .infinity)
    }

// NEXUS LOGO
    private var nexusLogo: some View {
        Image("Nexus")
            .resizable()
            .scaledToFill()
            .frame(height: toolbarFormat.logoHeight)
            .offset(x: 5, y: -1)
            .offset(x: toolbarFormat.logoOffsetX, y: toolbarFormat.logoOffsetY)
            .onTapGesture(count: 5) {
                showCloudKitDebugger = true
            }
            .transition(.opacity.combined(with: .scale))
    }

// TOOLBAR
    private var filterPill: some View {
        HStack(spacing: 0) {
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
                    .font(.system(size: 16 * toolbarScale, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: pillButtonWidth, height: pillButtonHeight)
                    .contentShape(Rectangle())
            }
        }
        // The highlight pill lives behind the icons so it never hides them.
        .background(alignment: .leading) {
            Capsule()
                .fill(Color.pillBackground)
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

    /// Filtered and sorted posts for the currently selected category.
    private var postsForSelection: [Submission] {
        // Searching always spans every category, regardless of the selected pill.
        // Events and projects only appear in Discover, not the home feed.
        if !searchText.isEmpty {
            let allHomePosts = store.approvedSubmissions.filter { $0.type != .event && $0.type != .project }
            return searchPosts(in: allHomePosts, query: searchText)
        }

        var posts: [Submission]

        switch selection {
        case .all:
            posts = store.approvedSubmissions.filter { $0.type != .event && $0.type != .project }
        case .film:
            posts = store.approvedSubmissions.filter { $0.type == .film }
        case .music:
            posts = store.approvedSubmissions.filter { $0.type == .music }
        case .people:
            return [] // TODO: Implement people/directory view
        }

        return posts.sorted { $0.createdDate > $1.createdDate }
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
        switch selection {
        case .all:    return "No posts."
        case .film:   return "No films."
        case .music:  return "No music."
        case .people: return "No reels."
        }
    }

    /// Syncs with CloudKit, then waits 0.5s so the spinner doesn't flash too fast.
    private func refreshSubmissions() async {
        await store.syncWithCloudKit()
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}

// MARK: - Previews

#Preview {
    HomeView_1()
}

#if DEBUG

#Preview("With Mock Data") {
    HomeView_1()
        .onAppear { MockCloudKitManager.shared.resetMockData() }
}

#Preview("Empty State") {
    HomeView_1()
        .onAppear { MockCloudKitManager.shared.clearMockData() }
}

#Preview("Many Submissions") {
    HomeView_1()
        .onAppear {
            let mock = MockCloudKitManager.shared
            mock.resetMockData()
            for i in 1...20 {
                var s = Submission(
                    id: UUID(),
                    type: MediaType.allCases.randomElement()!,
                    title: "Test Post \(i)",
                    details: "Test submission \(i)"
                )
                s.isApproved = true
                s.submittedBy = "Test User \(i)"
                s.createdDate = Date().addingTimeInterval(-Double(i) * 3600)
                mock.addMockSubmission(s)
            }
        }
}

#Preview("Dark Mode") {
    HomeView_1()
        .preferredColorScheme(.dark)
        .onAppear { MockCloudKitManager.shared.resetMockData() }
}

#Preview("Search Mode") {
    HomeView_1(startInSearchMode: true)
        .onAppear { MockCloudKitManager.shared.resetMockData() }
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
