//
//  MessagingAppDelegate.swift
//  Longhorn Artists Connect
//
//  AppDelegate configuration for CloudKit push notifications
//

import UIKit
import UserNotifications
import CloudKit

class MessagingAppDelegate: NSObject, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        
        // Request notification permissions
        requestNotificationPermissions(application: application)
        
        // Initialize message store to setup subscriptions
        Task {
            _ = MessageStore.shared
        }
        
        return true
    }
    
    // MARK: - Notification Permissions
    
    private func requestNotificationPermissions(application: UIApplication) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("⚠️ Failed to request notification permissions: \(error)")
                return
            }
            
            if granted {
                print("✅ Notification permissions granted")
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            } else {
                print("⚠️ Notification permissions denied")
            }
        }
        
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self
    }
    
    // MARK: - Remote Notifications
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("✅ Device Token: \(token)")
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("⚠️ Failed to register for remote notifications: \(error)")
    }
    
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("📨 Received remote notification")
        
        // Check if this is a CloudKit notification
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        
        if notification?.notificationType == .query {
            print("📨 CloudKit query notification received")
            
            // Handle the notification in MessageStore
            Task {
                await MessageStore.shared.handleRemoteNotification(userInfo)
                completionHandler(.newData)
            }
        } else {
            completionHandler(.noData)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension MessagingAppDelegate: UNUserNotificationCenterDelegate {
    
    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("📨 Notification received in foreground")
        
        // Show banner and play sound even when app is open
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("📨 User tapped notification")
        
        let userInfo = response.notification.request.content.userInfo
        
        // Handle CloudKit notification
        if let notification = CKQueryNotification(fromRemoteNotificationDictionary: userInfo) {
            handleNotificationTap(notification)
        }
        
        completionHandler()
    }
    
    // MARK: - Navigation Helper
    
    private func handleNotificationTap(_ notification: CKQueryNotification) {
        // Post a notification that the app can observe to navigate to the message
        guard let recordID = notification.recordID else { return }
        
        NotificationCenter.default.post(
            name: .didReceiveMessageNotification,
            object: nil,
            userInfo: ["recordID": recordID.recordName]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let didReceiveMessageNotification = Notification.Name("didReceiveMessageNotification")
}

// MARK: - Usage Example

/*
 To integrate this into your app, update your main App file:
 
 ```swift
 @main
 struct LonghornArtistsConnectApp: App {
     @UIApplicationDelegateAdaptor(MessagingAppDelegate.self) var appDelegate
     
     var body: some Scene {
         WindowGroup {
             ContentView()
         }
     }
 }
 ```
 
 To handle navigation when a notification is tapped:
 
 ```swift
 struct ContentView: View {
     @State private var selectedConversationID: UUID?
     @State private var showMessageView = false
     
     var body: some View {
         NavigationStack {
             // Your main view
         }
         .onReceive(NotificationCenter.default.publisher(for: .didReceiveMessageNotification)) { notification in
             if let recordName = notification.userInfo?["recordID"] as? String {
                 // Parse the message record and navigate to conversation
                 handleMessageNotification(recordName: recordName)
             }
         }
         .sheet(isPresented: $showMessageView) {
             if let conversationID = selectedConversationID {
                 // Show message view
                 InMessageView(
                     conversationID: conversationID,
                     otherUserID: "...",
                     otherUserName: "...",
                     otherUserRole: "..."
                 )
             }
         }
     }
     
     private func handleMessageNotification(recordName: String) {
         // Fetch the message and extract conversation ID
         Task {
             // Implementation here
         }
     }
 }
 ```
 */
