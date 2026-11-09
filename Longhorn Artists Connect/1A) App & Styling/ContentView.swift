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
    @AppStorage("appearanceMode")   private var appearanceMode:   String = "automatic"
    // Guests get a pared-down app: no sharing or messaging, so those tabs are hidden.
    @AppStorage("isGuestUser")      private var isGuestUser:      Bool   = false
    // True for accounts created via the "I'm an Industry Professional" onboarding flow.
    // These are restricted like guests for sharing (no Share tab) but keep the Network tab.
    @AppStorage("isIndustryProfessional") private var isIndustryProfessional: Bool = false
    // The school a moderator is viewing/posting as (Moderate → Schools). Changing it
    // rebuilds the tabs so every header, pill and asset picks up that school's theme.
    @AppStorage(SchoolScope.moderatorSchoolKey) private var moderatorSchool: String = ""

    // Tracks foreground/background transitions so we can resync when the app becomes
    // active. Silent CloudKit pushes on the public database are best-effort and get
    // throttled by APNs, so without this the feed would only refresh on cold launch
    // or a manual pull-to-refresh — leaving devices out of sync after backgrounding.
    @Environment(\.scenePhase) private var scenePhase

    // Watches the App Store for a newer release so we can prompt the user to update.
    @StateObject private var versionChecker = AppVersionChecker.shared

    // Currently selected tab (keyed by the same identifiers used for each tab's `.id`).
    // Backing store for `tabSelection`, which also detects re-taps of the Discover tab.
    @State private var selectedTab = "home"

    /// Selection binding for the tab bar. Whenever the Discover tab is selected — whether
    /// arriving from another tab or re-tapping it while already there — ask the Discover
    /// feed to return to the top (just before past events) instead of leaving it scrolled
    /// up among the past events. Re-taps animate the scroll; arriving on the tab jumps, so
    /// the feed is simply already in place.
    private var tabSelection: Binding<String> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == "discover" {
                    DiscoverTabCoordinator.shared.requestScrollToTop(animated: newValue == selectedTab)
                }
                selectedTab = newValue
            }
        )
    }

    // MARK: - Computed Properties

    private var shouldShowModeratorMode: Bool {
        // Gate on the moderator's profile name. Enabling `isModeratorMode` itself
        // requires the session password (see the Moderation section in More), so this
        // just controls whether the Moderate tab is shown once the mode is on.
        isModeratorMode && ModeratorAccess.isModerator
    }

    /// Industry professionals don't post content, so they get no Share tab. Gated purely
    /// on the dedicated "Industry Professional" account type — NOT on a user's roles.
    /// A UT student who tags themselves Manager/Agent is still a student and keeps Share;
    /// inferring "industry" from roles previously hid the tab from those students.
    private var isIndustryPro: Bool {
        isIndustryProfessional
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
        TabView(selection: tabSelection) {
            HomeView_1()
                .id("home")
                .tag("home")
                .tabItem { Image(systemName: "house") }

            DiscoverView()
                .id("discover")
                .tag("discover")
                .tabItem { Image(systemName: "binoculars") }

            // Guests can't share content or message, so hide both the Share/Moderate
            // and Network tabs entirely for them. Industry pros also get no Share tab.
            if shouldShowModeratorMode {
                ModerateView_3_1()
                    .id("moderate")
                    .tag("moderate")
                    .tabItem { Image(systemName: "checkmark.shield") }
            } else if !isGuestUser && !isIndustryPro {
                // New accounts verify a school email before posting. Accounts
                // that predate verification are exempt and keep full access;
                // they can still verify voluntarily from their profile.
                VerificationGate(
                    action: "post your work",
                    bypass: StudentVerificationManager.accountPredatesVerification
                ) {
                    ShareView_3()
                }
                .id("share")
                .tag("share")
                .tabItem { Image(systemName: "plus") }
            }

            if !isGuestUser {
                // Messaging is deliberately ungated for now.
                NetworkView()
                    .id("network")
                    .tag("network")
                    .tabItem { Image(systemName: "paperplane") }
            }

            Portfolio_5()
                .id("portfolio")
                .tag("portfolio")
                .tabItem { Image(systemName: "person.crop.circle") }
        }
        .id(moderatorSchool)                            // Re-theme everything on a moderator school switch
        .onChange(of: moderatorSchool) {
            // Refetch so the feeds show the newly picked school's posts (once
            // `SchoolScope.isFilteringEnabled` is on).
            Task { await SubmissionStore_3_2.shared.syncWithCloudKit() }
        }
        .transaction { $0.animation = nil }             // Disable tab switch animation
        // No scrollbars anywhere in the app. This is an environment value, so it reaches
        // every ScrollView / List / TextEditor in all five tabs *and* in the sheets and
        // full-screen covers they present (post detail pages, submission forms, pickers).
        // Set here rather than per-view so new screens inherit it automatically.
        .scrollIndicators(.hidden)
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
                Task {
                    await SubmissionStore_3_2.shared.syncWithCloudKit()
                    // Silent pushes are best-effort, so also look for new casting /
                    // crew calls matching the user's tags on every foreground sync.
                    await RoleCallNotifier.noticeOpenRoles(in: SubmissionStore_3_2.shared.visibleApprovedSubmissions)
                }
                // Reconcile the home-screen badge with the real unread total. CloudKit
                // only ever increments the badge on message delivery, so without this it
                // lingered on the icon even after every message had been read. Guests
                // can't message, so skip it (and avoid spinning up MessageStore for them).
                if !isGuestUser {
                    Task { MessageStore.shared.syncApplicationBadge() }
                }
                // Top the event reminders back up: iOS caps pending notifications, so
                // later events only get scheduled once earlier reminders have fired.
                Task { await EventReminderScheduler.reschedule(for: SubmissionStore_3_2.shared.visibleApprovedSubmissions) }
            } else if newPhase == .background {
                // Reclaim disk every time the app backgrounds, not just at launch. Video
                // and audio stream from the CDN and aren't downloaded for playback, so
                // this is mostly an uploader's leftovers — the media-cache copies and the
                // full-size scratch files each pick and upload leaves in tmp — which would
                // otherwise accumulate for a whole session between the rare cold starts.
                // Off the main thread since it does disk I/O.
                Task.detached(priority: .utility) {
                    FileManager.default.reclaimDiskSpace()
                }
            }
        }
        .onAppear {
            // Ask for notification permission up front so message banners work even for
            // users who never open the Messages tab (previously the only place it was
            // requested). Guests can't message and get no visible notifications, so don't
            // prompt them. iOS only ever shows the system prompt once.
            if !isGuestUser {
                PushAuthorization.request()
            }
        }
        .task {
            // Ask the App Store whether a newer build is live. If so, the popup below
            // appears and the only way forward is to tap "Update".
            await versionChecker.check()
        }
        // Event reminders live in their own tiny view so that observing the submission
        // store doesn't re-evaluate this root view (and with it all five tabs) on every
        // store change — that re-render on each sync/like/upload tick made the whole app
        // feel sluggish.
        .background { EventReminderCoordinator() }
        .task {
            // Weekly "<show> is Live!" notifications — see LiveStreams.swift.
            await LiveStreamNotifications.schedule()
        }
        .alert("A new version is available!", isPresented: $versionChecker.updateAvailable) {
            Button("Update") {
                versionChecker.openAppStore()
            }
        }
    }
}

// MARK: - Event Reminder Coordinator

/// Invisible view that keeps the on-device event reminders in step with the events
/// feed. It's the only thing at the root that observes the submission store, so a
/// store change re-evaluates just this view rather than the whole tab bar.
private struct EventReminderCoordinator: View {
    @ObservedObject private var submissionStore = SubmissionStore_3_2.shared

    var body: some View {
        Color.clear
            .task(id: EventReminderScheduler.signature(for: submissionStore.visibleApprovedSubmissions)) {
                // Every user gets reminders 3 days, 1 day and 1 hour before each event.
                // Re-runs whenever an event is added, edited or removed.
                await EventReminderScheduler.reschedule(for: submissionStore.visibleApprovedSubmissions)
            }
    }
}

#Preview {
    ContentView()
}
