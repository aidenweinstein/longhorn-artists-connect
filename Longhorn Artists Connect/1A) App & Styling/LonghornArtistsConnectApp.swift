//
//  Longhorn_Artists_ConnectApp.swift
//  Longhorn Artists Connect
//
//  Created by Aiden Weinstein on 11/26/25.
//

import SwiftUI
import CloudKit
import Combine
import AVFoundation
import UserNotifications

// The app is portrait-only. Fullscreen video no longer rotates the device — it
// rotates the *content* 90° to fill the screen (see `RotatingFullScreenPlayer` in
// FilmCard.swift), so the interface never leaves portrait and there's no orientation
// state to manage here anymore.

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        // Always portrait. Fullscreen video fills the screen by rotating its content,
        // not the interface, so landscape is never needed.
        return .portrait
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Register for remote notifications (CloudKit sync)
        application.registerForRemoteNotifications()

        // Become the notification delegate so message banners can be presented while
        // the app is open (and muted threads suppressed). Permission itself is requested
        // contextually via `PushAuthorization.request()`.
        UNUserNotificationCenter.current().delegate = self

        // Start the connections manager now so its request/accept push subscriptions
        // exist from launch, not just once a profile or the Directory is opened.
        _ = ConnectionsManager.shared

        // Use the .playback category so audio/video sound plays even when the
        // device's ringer/silent switch is set to silent.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ Failed to configure audio session for playback: \(error.localizedDescription)")
        }

        return true
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Handle CloudKit notification
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            completionHandler(.noData)
            return
        }
        print("🔔 Received CloudKit notification: \(notification.notificationType.rawValue)")

        // Route by which subscription fired. Messaging pushes (new message / updated
        // conversation) must reach MessageStore so a chat shows up for the recipient
        // live — including a shared post that starts a brand-new thread. Everything
        // else is a media-feed change handled by the submission store. Previously every
        // push went only to the submission store, so messages never synced from a push.
        let subscriptionID = (notification as? CKQueryNotification)?.subscriptionID
        Task { @MainActor in
            switch subscriptionID {
            case "MessageSubscription", "ConversationSubscription":
                await MessageStore.shared.handleRemoteNotification(userInfo)
            case let id? where ConnectionsManager.subscriptionIDs.contains(id):
                // Someone sent or accepted a connection request: reload the edge sets so
                // their profile button and the Directory sections update.
                await ConnectionsManager.shared.refresh()
            default:
                await SubmissionStore_3_2.shared.handleCloudKitNotification()
            }
            completionHandler(.newData)
        }
    }
}

// MARK: - Push Notification Authorization

/// Requests notification permission the first time the user reaches a surface where
/// message notifications matter (e.g. opening Messages). Kept out of cold launch so the
/// system prompt appears in context. Safe to call repeatedly — iOS only prompts once.
enum PushAuthorization {
    static func request() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { print("⚠️ Notification auth error: \(error.localizedDescription)") }
            if granted {
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            }
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Foreground banners: shown unless the sender's thread is muted.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        if let ck = CKQueryNotification(fromRemoteNotificationDictionary: userInfo),
           let senderID = ck.recordFields?["senderUserID"] as? String,
           ConversationPreferencesManager.shared.isMuted(senderID) {
            completionHandler([])   // muted: no banner/sound while app is open
            return
        }
        completionHandler([.banner, .sound, .badge])
    }

    /// Tapping a notification syncs the thread so the message is present when the user
    /// opens Messages.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        // Go-live notifications (LiveStreams.swift) open the show's stream.
        if let link = userInfo[LiveStreamNotifications.streamURLKey] as? String,
           let url = URL(string: link) {
            Task { @MainActor in
                await UIApplication.shared.open(url)
                completionHandler()
            }
            return
        }
        // Connection request / acceptance banners: refresh the edge sets so the
        // Directory's Requests section is current when the user lands there.
        if let ck = CKQueryNotification(fromRemoteNotificationDictionary: userInfo),
           let id = ck.subscriptionID,
           ConnectionsManager.subscriptionIDs.contains(id) {
            Task { @MainActor in
                await ConnectionsManager.shared.refresh()
                completionHandler()
            }
            return
        }
        Task { @MainActor in
            await MessageStore.shared.handleRemoteNotification(userInfo)
            completionHandler()
        }
    }
}

@main
struct AppView: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Observed so the home screen icon follows the user's school (see `SchoolAppIcon`).
    @AppStorage("userSchool") private var userSchool = ""
    @AppStorage("isGuestUser") private var isGuestUser = false
    @AppStorage(SchoolScope.moderatorSchoolKey) private var moderatorSchool = ""

    init() {
        // Moderator mode is a per-session privilege: it always starts OFF and stays
        // locked until the password is entered in More → Moderation this run. Clearing
        // the persisted flag here guarantees a relaunch re-locks it.
        UserDefaults.standard.set(false, forKey: "isModeratorMode")

        // Enable beta mode for TestFlight builds
        // This ensures beta testers' data is preserved when migrating to production
        #if DEBUG
        // Uncomment for testing beta mode in development
        // SubmissionStore_3_2.enableBetaMode()
        #elseif TESTFLIGHT
        // Automatically enable for TestFlight builds
        SubmissionStore_3_2.enableBetaMode()
        #endif
        
        // Initialize CloudKit check (non-capturing)
        Task {
            await Self.checkCloudKitStatus()
        }

        // Reclaim disk at launch. Media used to be persisted into Documents with no cap,
        // so it could balloon to tens of GB. It now lives in a backup-excluded, purgeable
        // media cache: purge any heavy media older builds left in Documents, drop the
        // abandoned full-size scratch copies in tmp, then cap the cache to its budget.
        // Trimmed/purged posts just re-download on demand. Off the main thread since it
        // does disk I/O.
        //
        // The before/after report is logged so a device that's still large can be
        // diagnosed from the console: it says which area holds the bytes, and whether a
        // purge is actually reclaiming them or they're being re-downloaded.
        Task.detached(priority: .utility) {
            print("📦 Storage before reclaim:\n\(FileManager.default.storageReport())")
            FileManager.default.reclaimDiskSpace()
            print("📦 Storage after reclaim:\n\(FileManager.default.storageReport())")
        }
    }
    
    private static func checkCloudKitStatus() async {
        do {
            let status = try await CKContainer.default().accountStatus()
            switch status {
            case .available:
                print("✅ CloudKit available and ready")
            case .noAccount:
                print("⚠️ No iCloud account signed in")
            case .restricted:
                print("⚠️ iCloud restricted")
            case .couldNotDetermine:
                print("⚠️ Could not determine iCloud status")
            case .temporarilyUnavailable:
                print("⚠️ iCloud temporarily unavailable")
            @unknown default:
                print("⚠️ Unknown iCloud status")
            }
        } catch {
            print("❌ CloudKit error: \(error.localizedDescription)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            LaunchScreenView()
                // Runs at launch and again whenever the school, guest status or a
                // moderator's school pick changes; a no-op when the icon already matches.
                .task(id: "\(userSchool)|\(isGuestUser)|\(moderatorSchool)") {
                    await SchoolAppIcon.apply(AppTheme.theme(school: userSchool, isGuest: isGuestUser))
                }
        }
    }
}

#Preview {
    ContentView()
}

#Preview("UC Berkeley Colors") {
    let _ = AppTheme.usePreviewSchool("University of California, Berkeley")
    ContentView()
}

#Preview("Michigan Colors") {
    let _ = AppTheme.usePreviewSchool("University of Michigan")
    ContentView()
}

#Preview("USC Colors") {
    let _ = AppTheme.usePreviewSchool("USC")
    ContentView()
}

#Preview("Cal Poly SLO Colors") {
    let _ = AppTheme.usePreviewSchool("Cal Poly SLO")
    ContentView()
}

