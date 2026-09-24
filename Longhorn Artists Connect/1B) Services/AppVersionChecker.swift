//
//  AppVersionChecker.swift
//  Longhorn Artists Connect
//
//  Checks the App Store for a newer release and, when one exists, surfaces a
//  "new version available" popup that sends the user to the store to update.
//

import SwiftUI
import Combine

/// Compares the running app's version against the version currently live on the
/// App Store. When the store has a newer build, `updateAvailable` flips true so
/// the UI can present the update popup, and `appStoreURL` points at the listing.
@MainActor
final class AppVersionChecker: ObservableObject {

    static let shared = AppVersionChecker()

    /// True once a newer version has been found on the App Store.
    @Published var updateAvailable = false

    /// The App Store listing to open when the user taps "Update".
    private(set) var appStoreURL: URL?

    private init() {}

    /// Response shape from Apple's iTunes lookup endpoint (only the fields we use).
    private struct LookupResponse: Decodable {
        struct Result: Decodable {
            let version: String
            let trackViewUrl: String
        }
        let results: [Result]
    }

    /// Queries the App Store for this app's live version and, if it's newer than
    /// the installed build, marks an update as available. Failures are silent —
    /// a missing network response should never block the user from using the app.
    func check() async {
        guard
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            let bundleID = Bundle.main.bundleIdentifier,
            let lookupURL = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)")
        else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: lookupURL)
            let lookup = try JSONDecoder().decode(LookupResponse.self, from: data)

            guard let result = lookup.results.first else { return }

            appStoreURL = URL(string: result.trackViewUrl)

            if Self.isVersion(result.version, newerThan: currentVersion) {
                updateAvailable = true
            }
        } catch {
            print("⚠️ App version check failed: \(error.localizedDescription)")
        }
    }

    /// Opens the App Store listing so the user can install the update.
    func openAppStore() {
        guard let appStoreURL else { return }
        UIApplication.shared.open(appStoreURL)
    }

    /// Numeric, component-aware version comparison (e.g. "1.10" > "1.9").
    private static func isVersion(_ candidate: String, newerThan installed: String) -> Bool {
        candidate.compare(installed, options: .numeric) == .orderedDescending
    }
}
