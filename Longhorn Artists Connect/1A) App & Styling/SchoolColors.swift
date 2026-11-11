//
//  SchoolColors.swift
//  Longhorn Artists Connect
//
//  Which school gets which colors. The single place to add or change a school's
//  palette — the app accent, credit chips, recolored brand assets and the home
//  screen icon all read from here.
//

import SwiftUI

// MARK: - School Themes

/// A school's two brand colors.
///
/// Every brand asset (tab logos, Share icons, the Nexus wordmark) is drawn in
/// exactly two colors — UT burnt-orange and white — so a school's theme is a
/// straight swap: `bubble` replaces the orange and `text` replaces the white
/// (see `SchoolArtwork`). The same pair colors a credited person's name chip.
struct SchoolTheme {
    /// Replaces burnt-orange. Also the app-wide accent and the name-chip bubble.
    let bubble: Color
    /// Replaces white. Also the name-chip text.
    let text: Color
    /// The alternate home-screen icon in Assets.xcassets (an `.appiconset`), or
    /// `nil` to keep the default `AppIcon`. The system can't recolor an icon at
    /// runtime, so each school's icon is a pre-rendered asset.
    var appIconName: String? = nil
    /// The capsule behind the icons in each main page's top bar (`Color.pillActive`).
    /// The icons themselves always stay white. Defaults to a lighter tint of UT
    /// burnt-orange — same hue as the header, just brighter, the way every other
    /// school's pill is a lighter tint of its own primary.
    var toolbarPill: Color = Color(hex: "E97D25")
    /// The bubble behind the selected icon in a top bar (`Color.pillBackground`).
    /// Defaults to a deeper shade of UT burnt-orange — same hue as the header, just
    /// darker, so it still reads as orange (not brown) against the lighter pill.
    var toolbarHighlight: Color = Color(hex: "A24A00")

    /// Fallback for a recognized Nexus member whose school isn't one of the themed
    /// ones (or is unset) — uses the app's own (UT) brand accent.
    static let nexusDefault = SchoolTheme(bubble: .utBurntOrange, text: .white)

    /// True when this theme is the artwork's own colors, so assets can be shown
    /// as-is instead of being recolored.
    var usesStockArtwork: Bool {
        bubble == .utBurntOrange && text == .white
    }

    /// Every school's theme, listed once with each accepted spelling of its name.
    private static let registry: [(names: [String], theme: SchoolTheme)] = [
        // Burnt Orange + white, with a lighter orange pill and deeper orange highlight
        // (the same light/dark pairing every other school uses).
        (["The University of Texas at Austin", "UT", "UT Austin"],
         SchoolTheme(bubble: .utBurntOrange, text: .white,
                     toolbarPill: Color(hex: "E97D25"),
                     toolbarHighlight: Color(hex: "A24A00"))),
        // Berkeley Blue + California Gold. The top-bar pill is a lighter blue
        // that stands out on the Berkeley Blue header, with a deeper blue
        // highlight — the same light/dark pairing UT's oranges use.
        (["University of California, Berkeley", "UC Berkeley", "Berkeley", "Cal"],
         SchoolTheme(bubble: Color(hex: "002676"), text: Color(hex: "FDB515"),
                     appIconName: "AppIcon-Berkeley",
                     toolbarPill: Color(hex: "3B6FC4"),
                     toolbarHighlight: Color(hex: "1E4B94"))),
        // Michigan Blue + Maize, with a lighter navy pill and deeper navy highlight.
        (["University of Michigan", "Michigan", "UMich"],
         SchoolTheme(bubble: Color(hex: "00274C"), text: Color(hex: "FFCB05"),
                     appIconName: "AppIcon-Michigan",
                     toolbarPill: Color(hex: "2F5A8C"),
                     toolbarHighlight: Color(hex: "173F6E"))),
        // Poly Green + Mustang Gold, with a lighter green pill and deeper green highlight.
        (["Cal Poly SLO", "Cal Poly", "Cal Poly San Luis Obispo"],
         SchoolTheme(bubble: Color(hex: "154734"), text: Color(hex: "BD8B13"),
                     appIconName: "AppIcon-CalPolySLO",
                     toolbarPill: Color(hex: "3C7A5A"),
                     toolbarHighlight: Color(hex: "245C40"))),
        // Cardinal + Gold, with a lighter cardinal pill and deeper cardinal highlight.
        (["USC", "University of Southern California"],
         SchoolTheme(bubble: Color(hex: "990000"), text: Color(hex: "FFC72C"),
                     appIconName: "AppIcon-USC",
                     toolbarPill: Color(hex: "C4302B"),
                     toolbarHighlight: Color(hex: "8E1A16"))),
        // NYU Violet + white, with a lighter violet pill and deeper violet highlight.
        (["NYU", "New York University"],
         SchoolTheme(bubble: Color(hex: "57068C"), text: .white,
                     appIconName: "AppIcon-NYU",
                     toolbarPill: Color(hex: "8440B8"),
                     toolbarHighlight: Color(hex: "3F0466"))),
        // DePaul Blue + white, with a lighter blue pill and deeper blue highlight.
        (["DePaul", "DePaul University"],
         SchoolTheme(bubble: Color(hex: "005EB8"), text: .white,
                     appIconName: "AppIcon-DePaul",
                     toolbarPill: Color(hex: "3D8BDB"),
                     toolbarHighlight: Color(hex: "00468A"))),
        // Boston University Scarlet + white, with a lighter scarlet pill and deeper
        // scarlet highlight. No alternate home-screen icon yet, so it keeps `AppIcon`.
        (["BU", "Boston University"],
         SchoolTheme(bubble: Color(hex: "CC0000"), text: .white,
                     toolbarPill: Color(hex: "E54444"),
                     toolbarHighlight: Color(hex: "990000"))),
        // Aggie Maroon + white, with a lighter maroon pill and deeper maroon
        // highlight. No alternate home-screen icon yet, so it keeps `AppIcon`.
        (["Texas A&M", "Texas A&M University", "TAMU"],
         SchoolTheme(bubble: Color(hex: "500000"), text: .white,
                     toolbarPill: Color(hex: "8C2B2B"),
                     toolbarHighlight: Color(hex: "3A0000")))
    ]

    /// `registry` flattened to a lookup table, built once. `forSchool` sits behind
    /// `Color.brandOrange`, which hundreds of view bodies read on every render, so it
    /// must not parse hex colors or walk a string switch each time.
    private static let themesByName: [String: SchoolTheme] = {
        var table: [String: SchoolTheme] = [:]
        for entry in registry {
            for name in entry.names { table[name] = entry.theme }
        }
        return table
    }()

    /// The theme for a school name. Unknown/empty falls back to `nexusDefault`.
    static func forSchool(_ school: String) -> SchoolTheme {
        themesByName[school.trimmingCharacters(in: .whitespaces)] ?? .nexusDefault
    }

    /// The brand accent for a school (the bubble color), used to theme the whole app.
    static func brandColor(for school: String) -> Color {
        forSchool(school).bubble
    }
}

// MARK: - App Theme

/// Resolves the app-wide theme from the current user's school. Guest users
/// (and users with no school set) always get UT burnt-orange.
enum AppTheme {
    /// Forces a school's theme regardless of the signed-in user. For Xcode
    /// previews only — set it with `usePreviewSchool(_:)`.
    private(set) static var previewSchool: String? {
        didSet { invalidateCache() }
    }

    /// Renders a preview as if the user attends `school` (a display name, e.g.
    /// "University of California, Berkeley"). Returns nothing so it can sit in a
    /// `#Preview` body as `let _ = AppTheme.usePreviewSchool(...)`.
    static func usePreviewSchool(_ school: String) {
        previewSchool = school
    }

    // MARK: Cache

    /// `current` resolved once and reused until something it depends on changes.
    ///
    /// Resolving the theme costs half a dozen UserDefaults reads (school, guest flag,
    /// account kind, the moderator's name and school pick). `Color.brandOrange` and
    /// the toolbar pill colors go through it, and together they're read hundreds of
    /// times per render pass across the app, so paying that on every read made every
    /// screen slower. All of those inputs live in UserDefaults, so the cache is
    /// cleared whenever the app's defaults change (and when a preview overrides the
    /// school); the next read re-resolves.
    ///
    /// The defaults notification is delivered synchronously on whichever thread wrote
    /// the value, so the cache is guarded by a lock and cleared off the main actor.
    nonisolated private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedCurrent: SchoolTheme?
    private static let defaultsObserver: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification, object: nil, queue: nil
    ) { _ in
        invalidateCache()
    }

    nonisolated private static func invalidateCache() {
        cacheLock.lock()
        cachedCurrent = nil
        cacheLock.unlock()
    }

    /// The current user's school, as saved during onboarding.
    static var currentSchool: String {
        previewSchool ?? UserDefaults.standard.string(forKey: "userSchool") ?? ""
    }

    /// Whether this account was created via the Guest flow.
    static var isGuest: Bool {
        previewSchool == nil && UserDefaults.standard.bool(forKey: "isGuestUser")
    }

    /// The theme for the given account state. Views that observe `userSchool` /
    /// `isGuestUser` (and `moderatorSchool`) through `@AppStorage` pass their
    /// values here so they redraw when the school changes.
    ///
    /// A moderator's pick in Moderate → Schools wins over their own school, so
    /// the app looks the way it does for that school's students.
    static func theme(school: String, isGuest: Bool) -> SchoolTheme {
        if let previewSchool { return SchoolTheme.forSchool(previewSchool) }
        if let moderatorSchool = SchoolScope.moderatorSchool {
            return SchoolTheme.forSchool(moderatorSchool)
        }
        // Enthusiasts are guest accounts that belong to a school, so they get
        // its colors.
        let usesNexusDefault = isGuest && AccountKind.current != .enthusiast
        return usesNexusDefault ? .nexusDefault : SchoolTheme.forSchool(school)
    }

    /// The current user's theme. Cached — see `cachedCurrent`.
    static var current: SchoolTheme {
        // Touching the observer registers it on first use; it lives for the process.
        _ = defaultsObserver
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cachedCurrent { return cachedCurrent }
        let resolved = theme(school: currentSchool, isGuest: isGuest)
        cachedCurrent = resolved
        return resolved
    }

    /// The themed brand color for the whole app. Guests stay orange.
    static var brandColor: Color {
        current.bubble
    }
}
