//
//  SidebarShell.swift
//  Longhorn Artists Connect
//
//  The Mac (Catalyst) and iPad layout, modeled on the website (web/app/(app)/layout.tsx,
//  web/components/Sidebar.tsx): an icon sidebar on the left that widens over the page,
//  holding your school, the main pages, College Artists Connect and your account. Each
//  page keeps its own colored header, which plays the part of the website's top bar;
//  the sidebar's cap takes the same color so it runs across the whole window.
//
//  Mac vs iPad:
//    - The Mac lists every other school and opens their feeds (Aiden's call,
//      2026-11-20). The iPad, like the iPhone, stays your-school-only, so its sidebar
//      has no "Other Schools" section. Flip `listsOtherSchools` to change that.
//    - The bar opens while the pointer hovers over it (Mac, or an iPad with a
//      trackpad). On iPad it also opens from the menu button in its cap, and closes
//      when a page is picked or the content beside it is tapped.
//    - An iPad window narrower than the regular width class (Slide Over, a third of
//      the screen in Split View) doesn't use this shell at all: ContentView falls back
//      to the iPhone tab bar there.
//

import SwiftUI

// MARK: - Sidebar Items

/// One main page in the sidebar. `id` is the same tab identifier ContentView uses.
struct SidebarPage: Identifiable {
    let id: String
    let label: String
    let icon: String
}

/// A school in the sidebar, mirroring `SCHOOLS` in web/lib/schools.ts.
struct SidebarSchool: Identifiable, Hashable {
    /// Registry slug, the same value posts carry in `schoolID`.
    let slug: String
    let name: String
    let mascot: String

    var id: String { slug }
    var logo: String { "SchoolLogo-\(slug)" }
    var theme: SchoolTheme { SchoolTheme.forSchool(SchoolRegistry.name(forSlug: slug)) }

    /// Every school on the website, in its order (ties in the sidebar keep this order).
    static let all: [SidebarSchool] = [
        SidebarSchool(slug: "ut-austin", name: "UT Austin", mascot: "Longhorns"),
        SidebarSchool(slug: "berkeley", name: "UC Berkeley", mascot: "Bears"),
        SidebarSchool(slug: "usc", name: "USC", mascot: "Trojans"),
        SidebarSchool(slug: "umich", name: "UMich", mascot: "Wolverines"),
        SidebarSchool(slug: "tamu", name: "Texas A&M", mascot: "Aggies"),
        SidebarSchool(slug: "calpoly-slo", name: "Cal Poly SLO", mascot: "Mustangs"),
        SidebarSchool(slug: "ohio-state", name: "Ohio State", mascot: "Buckeyes"),
        SidebarSchool(slug: "uva", name: "UVA", mascot: "Cavaliers"),
        SidebarSchool(slug: "ucsb", name: "UC Santa Barbara", mascot: "Gauchos"),
        SidebarSchool(slug: "bu", name: "Boston University", mascot: "Terriers"),
        SidebarSchool(slug: "northwestern", name: "Northwestern", mascot: "Wildcats")
    ]
}

// MARK: - Shell

/// The whole window: sidebar on the left, the selected page (or, on the Mac, another
/// school's feed) filling the rest.
struct SidebarShell<Page: View>: View {
    let pages: [SidebarPage]
    @Binding var selection: String
    @ViewBuilder let page: (String) -> Page

    /// Whether the sidebar lists the other schools and opens their feeds. The Mac does,
    /// as the website; the iPad keeps the app's your-school-only scope.
    #if targetEnvironment(macCatalyst)
    static var listsOtherSchools: Bool { true }
    #else
    static var listsOtherSchools: Bool { false }
    #endif

    /// The other school being viewed, or `nil` while a main page is showing.
    @State private var openSchool: SidebarSchool?
    /// Pages opened so far. They stay alive once opened, so switching back keeps
    /// their scroll position and state, as the iPhone tab bar does.
    @State private var opened: Set<String> = []
    /// True while the bar was opened by a tap (iPad) rather than by hovering.
    @State private var pinnedOpen = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarRail(
                pages: pages,
                selectedPage: openSchool == nil ? selection : nil,
                openSchool: openSchool,
                pinnedOpen: $pinnedOpen,
                onSelectPage: { tab in
                    openSchool = nil
                    selection = tab
                },
                onSelectSchool: { school in
                    if Self.listsOtherSchools {
                        openSchool = school
                    } else {
                        // Your own school's page is Home here.
                        openSchool = nil
                        selection = "home"
                    }
                }
            )
            .zIndex(1)

            ZStack {
                ForEach(pages) { item in
                    if opened.contains(item.id) || item.id == selection {
                        let isShown = openSchool == nil && item.id == selection
                        page(item.id)
                            .opacity(isShown ? 1 : 0)
                            .allowsHitTesting(isShown)
                            .accessibilityHidden(!isShown)
                    }
                }
                if let openSchool {
                    SidebarSchoolFeedView(school: openSchool)
                        .id(openSchool.slug)
                }
                // While the bar is held open by a tap, a tap anywhere on the page
                // closes it instead of reaching the page.
                if pinnedOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { pinnedOpen = false }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { opened.insert(selection) }
        .onChange(of: selection) { _, tab in opened.insert(tab) }
    }
}

// MARK: - Sidebar

/// The website's sidebar: 68 points wide, growing to 224 over the page while open, and
/// closing the moment something is picked until the pointer leaves and comes back.
private struct SidebarRail: View {
    let pages: [SidebarPage]
    let selectedPage: String?
    let openSchool: SidebarSchool?
    @Binding var pinnedOpen: Bool
    let onSelectPage: (String) -> Void
    let onSelectSchool: (SidebarSchool) -> Void

    @ObservedObject private var store = SubmissionStore_3_2.shared
    @AppStorage("userSchool") private var userSchool = ""
    @AppStorage("isGuestUser") private var isGuestUser = false
    @AppStorage("userFirstName") private var userFirstName = ""
    @AppStorage("userLastName") private var userLastName = ""
    @AppStorage(SchoolScope.moderatorSchoolKey) private var moderatorSchool = ""

    @State private var hovering = false
    @State private var picked = false
    private var isOpen: Bool { pinnedOpen || (hovering && !picked) }

    static let closedWidth: CGFloat = 68
    static let openWidth: CGFloat = 224
    /// Matches the pages' own header bar, so the color runs across the window's top.
    static let capHeight: CGFloat = 50

    /// The iPad has no pointer to hover with, so its cap holds a button that opens the bar.
    #if targetEnvironment(macCatalyst)
    private let showsMenuButton = false
    #else
    private let showsMenuButton = true
    #endif

    private var brand: Color {
        let _ = moderatorSchool
        return AppTheme.theme(school: userSchool, isGuest: isGuestUser).bubble
    }

    /// Your own school, or `nil` for accounts without one (guests, industry pros).
    private var mySchool: SidebarSchool? {
        let _ = (userSchool, isGuestUser, moderatorSchool)
        guard !SchoolScope.isUnscopedAccount else { return nil }
        let slug = SchoolScope.postingSchoolID
        return SidebarSchool.all.first { $0.slug == slug }
    }

    /// Every school but yours, most posts first; ties keep the website's order.
    private var otherSchools: [SidebarSchool] {
        var counts: [String: Int] = [:]
        for post in store.approvedSubmissions where post.type != .event && post.type != .project {
            counts[SchoolRegistry.slug(post.schoolID), default: 0] += 1
        }
        let others = SidebarSchool.all.filter { $0.slug != mySchool?.slug }
        return others.enumerated()
            .sorted { a, b in
                let (ca, cb) = (counts[a.element.slug] ?? 0, counts[b.element.slug] ?? 0)
                return ca != cb ? ca > cb : a.offset < b.offset
            }
            .map(\.element)
    }

    /// Something was picked: the bar closes and stays closed until the pointer comes back.
    private func didPick() {
        picked = true
        pinnedOpen = false
    }

    var body: some View {
        Color.clear
            .frame(width: Self.closedWidth)
            .overlay(alignment: .leading) {
                bar
                    .frame(width: isOpen ? Self.openWidth : Self.closedWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.darkBackground.ignoresSafeArea())
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
                    }
                    .shadow(color: .black.opacity(isOpen ? 0.25 : 0), radius: 12, x: 4)
                    .clipped()
                    .animation(.easeOut(duration: 0.2), value: isOpen)
                    .onHover { inside in
                        hovering = inside
                        if !inside { picked = false }
                    }
            }
    }

    private var bar: some View {
        VStack(alignment: .leading, spacing: 0) {
            cap

            // Your school and the main pages, always in view.
            VStack(alignment: .leading, spacing: 4) {
                if let mySchool {
                    schoolRow(mySchool, selected: openSchool == mySchool)
                }
                ForEach(pages) { item in
                    pageRow(item)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)

            if SidebarShell<EmptyView>.listsOtherSchools {
                Divider().padding(.top, 12)

                // The other schools: the only part that scrolls.
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mySchool == nil ? "Schools" : "Other Schools")
                            .font(.system(size: 11, weight: .semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 2)
                            .opacity(isOpen ? 1 : 0)
                        ForEach(otherSchools) { school in
                            schoolRow(school, selected: openSchool == school)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            } else {
                Spacer(minLength: 12)
            }

            // College Artists Connect and your account, always in view.
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Link(destination: URL(string: "https://collegeartistsconnect.org")!) {
                    row(selected: false) {
                        logo("CollegeArtistsConnect", size: 26)
                    } label: {
                        Text("College Artists Connect")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .simultaneousGesture(TapGesture().onEnded { didPick() })
                if !isGuestUser {
                    accountRow
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    /// The school-colored strip across the top, level with the pages' header bars. On
    /// iPad it also bleeds up behind the status bar, as those bars do, and holds the
    /// button that opens the sidebar.
    private var cap: some View {
        HStack {
            if showsMenuButton {
                Button {
                    pinnedOpen.toggle()
                    if pinnedOpen { picked = false }
                } label: {
                    Image(systemName: pinnedOpen ? "sidebar.left" : "line.3.horizontal")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.theme(school: userSchool, isGuest: isGuestUser).text)
                        .frame(width: Self.closedWidth - 16, height: Self.capHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pinnedOpen ? "Close sidebar" : "Open sidebar")
                .padding(.leading, 8)
            }
            Spacer(minLength: 0)
        }
        .frame(height: Self.capHeight)
        .frame(maxWidth: .infinity)
        .background(brand, ignoresSafeAreaEdges: .top)
    }

    // MARK: Rows

    private func pageRow(_ item: SidebarPage) -> some View {
        let selected = selectedPage == item.id
        return Button {
            didPick()
            onSelectPage(item.id)
        } label: {
            row(selected: selected) {
                Image(systemName: item.icon)
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 30, height: 30)
            } label: {
                Text(item.label)
                    .font(.system(size: 16, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
    }

    private func schoolRow(_ school: SidebarSchool, selected: Bool) -> some View {
        Button {
            didPick()
            onSelectSchool(school)
        } label: {
            row(selected: selected, tint: school.theme.bubble) {
                logo(school.logo, size: 30)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(school.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text(school.mascot)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(school.name)
    }

    /// "Signed in as" with your initials; opens Portfolio.
    private var accountRow: some View {
        let name = [userFirstName, userLastName].filter { !$0.isEmpty }.joined(separator: " ")
        let initials = [userFirstName, userLastName].compactMap(\.first).map(String.init).joined()
        return Button {
            didPick()
            onSelectPage("portfolio")
        } label: {
            row(selected: false) {
                Circle()
                    .fill(brand)
                    .frame(width: 26, height: 26)
                    .overlay {
                        Text(initials.isEmpty ? "?" : initials)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Signed in as")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(name.isEmpty ? "Your account" : name)
                        .font(.system(size: 13, weight: .medium))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your account")
    }

    /// A sidebar row: the icon stays put at the closed width, and the label fades in
    /// beside it while the bar is open. The selected row gets a tinted background and
    /// the indicator on its left edge, as on the website.
    private func row<Icon: View, Label: View>(
        selected: Bool,
        tint: Color? = nil,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder label: () -> Label
    ) -> some View {
        let color = tint ?? brand
        return HStack(spacing: 14) {
            icon()
                .frame(width: 32, height: 32)
            label()
                .lineLimit(1)
                .fixedSize()
                .opacity(isOpen ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .foregroundStyle(selected ? color : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selected ? color.opacity(0.15) : .clear)
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3)
                .fill(color)
                .frame(width: 4, height: 28)
                .offset(x: -8)
                .opacity(selected ? 1 : 0)
        }
        .contentShape(Rectangle())
        .frame(width: Self.openWidth - 16, alignment: .leading)
    }

    private func logo(_ name: String, size: CGFloat) -> some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - Another School's Feed

/// A school's Home feed in its own colors, like the website's /school/<slug>: its
/// posts (everything but events and projects), newest first. Mac only in practice,
/// since only the Mac sidebar lists other schools.
private struct SidebarSchoolFeedView: View {
    let school: SidebarSchool
    @ObservedObject private var store = SubmissionStore_3_2.shared

    private var posts: [Submission] {
        store.approvedSubmissions
            .filter {
                $0.type != .event && $0.type != .project
                    && SchoolRegistry.slug($0.schoolID) == school.slug
            }
            .sorted { $0.createdDate > $1.createdDate }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                GeometryReader { geo in
                    let columns = FeedColumns.count(forWidth: geo.size.width)
                    let columnWidth = FeedColumns.columnWidth(totalWidth: geo.size.width, count: columns)
                    if posts.isEmpty {
                        Text("No posts from \(school.name) yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: FeedColumns.gridItems(count: columns), spacing: 0) {
                                ForEach(posts) { post in
                                    HomePostCard(post: post, showTypeIcon: true, estimatedWidth: columnWidth)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .refreshable { await store.syncWithCloudKit() }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        // The page takes the school's colors, as the website's top bar does.
        .tint(school.theme.bubble)
    }

    /// The website's top bar on a school page: the Nexus wordmark in the school's
    /// two colors, with the school's logo and name.
    private var header: some View {
        HStack(spacing: 12) {
            wordmark
                .frame(height: 27)
            Spacer()
            Text(school.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(school.theme.text)
            Image(school.logo)
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(Circle())
        }
        .padding(.horizontal, 16)
        .frame(height: SidebarRail.capHeight)
        .frame(maxWidth: .infinity)
        .background(school.theme.bubble, ignoresSafeAreaEdges: .top)
    }

    @ViewBuilder
    private var wordmark: some View {
        if let recolored = SchoolArtwork.image(named: "Nexus", theme: school.theme) {
            Image(uiImage: recolored).resizable().scaledToFit()
        } else {
            Image("Nexus").resizable().scaledToFit()
        }
    }
}
