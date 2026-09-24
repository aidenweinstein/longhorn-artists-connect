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

        // Light mode tab bar
        let lightAppearance = UITabBarAppearance()
        lightAppearance.configureWithDefaultBackground()
        lightAppearance.stackedLayoutAppearance    = tabBarItemAppearance(dark: false)
        lightAppearance.inlineLayoutAppearance     = tabBarItemAppearance(dark: false)
        lightAppearance.compactInlineLayoutAppearance = tabBarItemAppearance(dark: false)

        // Dark mode tab bar — dark gray background (Instagram-style)
        let darkAppearance = UITabBarAppearance()
        darkAppearance.configureWithOpaqueBackground()
        darkAppearance.backgroundColor            = .darkBackground
        darkAppearance.stackedLayoutAppearance    = tabBarItemAppearance(dark: true)
        darkAppearance.inlineLayoutAppearance     = tabBarItemAppearance(dark: true)
        darkAppearance.compactInlineLayoutAppearance = tabBarItemAppearance(dark: true)

        UITabBar.appearance().standardAppearance    = lightAppearance
        UITabBar.appearance().scrollEdgeAppearance  = darkAppearance
        UITabBar.appearance().tintColor             = .brandOrange
        UITabBar.appearance().unselectedItemTintColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .white : .black
        }
    }

    /// Builds a UITabBarItemAppearance with brand orange for selected,
    /// white (dark) or black (light) for unselected.
    private static func tabBarItemAppearance(dark: Bool) -> UITabBarItemAppearance {
        let item = UITabBarItemAppearance()
        let unselected: UIColor = dark ? .white : .black

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
