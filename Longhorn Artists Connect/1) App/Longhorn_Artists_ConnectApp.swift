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

// Global flag to allow landscape only for fullscreen video
@MainActor
class OrientationManager: ObservableObject {
    static let shared = OrientationManager()
    @Published var allowLandscape = false
    
    private init() {}
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return OrientationManager.shared.allowLandscape ? .allButUpsideDown : .portrait
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Register for remote notifications (CloudKit sync)
        application.registerForRemoteNotifications()

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
        if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            print("🔔 Received CloudKit notification: \(notification.notificationType.rawValue)")
            
            Task { @MainActor in
                await SubmissionStore_3_2.shared.handleCloudKitNotification()
                completionHandler(.newData)
            }
        } else {
            completionHandler(.noData)
        }
    }
}

@main
struct AppView: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
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
        }
    }
}

struct FullAppView: View {
    var body: some View {
        ContentView()
    }
}

struct AppView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

#Preview {
    ContentView()
}

