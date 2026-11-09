import SwiftUI

// MARK: - Appearance Manager
//
// Configures all global UIKit appearances for the app.
// Called once from ContentView.init() — do not call anywhere else.
//
// To change any app-wide color or font, update NexusColors.swift
// or the values below. Nothing else needs to change.

struct AppearanceManager {

    static func configure() {
        configureNavigationBar()
        configureTabBar()
        configureScrollViews()
    }

    // MARK: - Navigation Bar
    //
    // Sets the default nav bar appearance for all screens EXCEPT HomeView,
    // which overrides this with its own orange appearance via .toolbarBackground.

    private static func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()

        // Larger title font
        appearance.largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 35, weight: .bold),
            .foregroundColor: UIColor.adaptiveText
        ]

        // Inline (scrolled) title font
        appearance.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 25, weight: .semibold),
            .foregroundColor: UIColor.adaptiveText
        ]

        // Adaptive background (dark gray in dark mode, system white in light)
        appearance.backgroundColor = .adaptiveBackground

        // Button colors
        appearance.buttonAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.adaptiveText
        ]
        appearance.doneButtonAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.adaptiveText
        ]

        UINavigationBar.appearance().standardAppearance   = appearance
        UINavigationBar.appearance().compactAppearance    = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance

        // Tint controls back arrows and bar button icons
        UINavigationBar.appearance().tintColor = .adaptiveTint
    }

    // MARK: - Tab Bar

    private static func configureTabBar() {

        // One appearance for both states. UIKit swaps between `standardAppearance` and
        // `scrollEdgeAppearance` as content scrolls and while full-screen covers dismiss,
        // so any difference between them shows up as the bar flickering. The background
        // and icon colors adapt to light/dark mode instead: dark gray (Instagram-style)
        // with white icons in dark mode, system white with black icons in light mode.
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor               = .adaptiveBackground
        appearance.stackedLayoutAppearance       = tabBarItemAppearance()
        appearance.inlineLayoutAppearance        = tabBarItemAppearance()
        appearance.compactInlineLayoutAppearance = tabBarItemAppearance()

        UITabBar.appearance().standardAppearance    = appearance
        UITabBar.appearance().scrollEdgeAppearance  = appearance
        UITabBar.appearance().tintColor             = .brandOrange
        UITabBar.appearance().unselectedItemTintColor = unselectedTabColor
    }

    /// Unselected tab icon color: white in dark mode, black in light mode, resolved from
    /// the current traits so it can never disagree with the active appearance.
    private static let unselectedTabColor = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? .white : .black
    }

    /// Builds a UITabBarItemAppearance with brand orange for selected,
    /// white (dark) or black (light) for unselected.
    private static func tabBarItemAppearance() -> UITabBarItemAppearance {
        let item = UITabBarItemAppearance()
        let unselected = unselectedTabColor

        item.selected.iconColor = .brandOrange
        item.selected.titleTextAttributes = [.foregroundColor: UIColor.brandOrange]
        item.normal.iconColor = unselected
        item.normal.titleTextAttributes = [.foregroundColor: unselected]

        return item
    }

    // MARK: - Scroll & Table Views

    private static func configureScrollViews() {
        UITableView.appearance().backgroundColor  = .adaptiveBackground
        UIScrollView.appearance().backgroundColor = .adaptiveBackground
    }
}
