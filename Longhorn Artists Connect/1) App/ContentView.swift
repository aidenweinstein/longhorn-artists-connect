import SwiftUI

// MARK: - Content View
//
// Root view of the app. Responsible for:
//   1. Calling AppearanceManager to set up global UIKit styling
//   2. Reading user preferences from AppStorage
//   3. Defining the tab bar structure

struct ContentView: View {

    // MARK: - User Preferences
    @AppStorage("isModeratorMode")  private var isModeratorMode:  Bool   = false
    @AppStorage("userFirstName")    private var userFirstName:    String = ""
    @AppStorage("userLastName")     private var userLastName:     String = ""
    @AppStorage("appearanceMode")   private var appearanceMode:   String = "automatic"

    // Tracks foreground/background transitions so we can resync when the app becomes
    // active. Silent CloudKit pushes on the public database are best-effort and get
    // throttled by APNs, so without this the feed would only refresh on cold launch
    // or a manual pull-to-refresh — leaving devices out of sync after backgrounding.
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Computed Properties

    private var currentUserName: String {
        "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
    }

    private var isAidenWeinstein: Bool {
        currentUserName == "Aiden Weinstein"
    }

    private var shouldShowModeratorMode: Bool {
        isModeratorMode && isAidenWeinstein
    }

    /// Maps the stored string preference to a SwiftUI ColorScheme.
    /// nil means follow the system setting (automatic).
    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light":  return .light
        case "dark":   return .dark
        default:       return nil
        }
    }

    // MARK: - Init
    // Only job here is to configure global UIKit appearance — nothing else.

    init() {
        AppearanceManager.configure()
    }

    // MARK: - Body

    var body: some View {
        TabView {
            HomeView_1()
                .id("home")
                .tabItem { Image(systemName: "house") }

            DiscoverView()
                .id("discover")
                .tabItem { Image(systemName: "binoculars") }

            if shouldShowModeratorMode {
                ModerateView_3_1()
                    .id("moderate")
                    .tabItem { Image(systemName: "checkmark.shield") }
            } else {
                ShareView_3()
                    .id("share")
                    .tabItem { Image(systemName: "plus") }
            }

            NetworkView()
                .id("network")
                .tabItem { Image(systemName: "paperplane") }

            Portfolio_5()
                .id("portfolio")
                .tabItem { Image(systemName: "person.crop.circle") }
        }
        .transaction { $0.animation = nil }             // Disable tab switch animation
        .preferredColorScheme(preferredColorScheme)     // Apply user's appearance preference
        .background(
            Color.darkBackground
                .ignoresSafeArea()
        )
        .onChange(of: scenePhase) { _, newPhase in
            // Resync whenever the app returns to the foreground, so posts created or
            // deleted on other devices show up even if the push notification never
            // arrived.
            if newPhase == .active {
                Task { await SubmissionStore_3_2.shared.syncWithCloudKit() }
            }
        }
    }
}

#Preview {
    ContentView()
}
