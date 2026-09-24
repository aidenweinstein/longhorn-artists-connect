# CloudKit Messaging System Setup Guide

## Overview

The messaging system for Longhorn Artists Connect uses CloudKit to provide secure, privacy-focused messaging between users. Messages are stored in each user's private CloudKit database, ensuring that only the participants in a conversation can access their messages.

## Architecture

### Key Components

1. **MessageRecordHandling.swift** - Core messaging logic with CloudKit integration
2. **InMessageView.swift** - UI for displaying and sending messages
3. **CloudKit Private Database** - Stores messages and conversations
4. **Push Notifications** - Real-time message delivery
5. **Local Persistence** - Offline message access

### Data Models

- **Message**: Individual messages with content, attachments, and metadata
- **Conversation**: Represents a chat between two users
- **MessageStore**: Singleton that manages all messaging operations

## CloudKit Setup

### 1. Enable CloudKit in Your Project

1. Open your project in Xcode
2. Select your app target
3. Go to "Signing & Capabilities"
4. Click "+ Capability"
5. Add "iCloud"
6. Check "CloudKit"
7. Ensure "CloudKit Containers" shows your container (usually `iCloud.your.bundle.identifier`)

### 2. Configure CloudKit Dashboard

1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard)
2. Select your container
3. Go to "Schema" → "Record Types"
4. Create the following record types:

#### Message Record Type
- **Record Type Name**: `Message`
- **Fields**:
  - `conversationID` (String, Indexed)
  - `content` (String)
  - `timestamp` (Date/Time, Indexed, Sortable)
  - `senderUserID` (String, Indexed)
  - `recipientUserID` (String, Indexed)
  - `isRead` (Int64) - 0 for false, 1 for true
  - `attachmentType` (String) - Optional
  - `attachment` (Asset) - Optional
  - `attachmentFileName` (String) - Optional

#### Conversation Record Type
- **Record Type Name**: `Conversation`
- **Fields**:
  - `participant1UserID` (String, Indexed)
  - `participant2UserID` (String, Indexed)
  - `lastMessageTimestamp` (Date/Time, Sortable)
  - `lastMessagePreview` (String)
  - `unreadCount` (Int64)

### 3. Set Up Indexes

For optimal performance, create the following indexes:

**Message Indexes:**
- `conversationID` (Queryable)
- `recipientUserID` (Queryable)
- `timestamp` (Sortable)

**Conversation Indexes:**
- `participant1UserID` (Queryable)
- `participant2UserID` (Queryable)
- `lastMessageTimestamp` (Sortable)

### 4. Configure Security Roles

1. In CloudKit Dashboard, go to "Security Roles"
2. For **Message** record type:
   - Creator: "Authenticated"
   - Reader: Creator Only
   - Writer: Creator Only
3. For **Conversation** record type:
   - Creator: "Authenticated"
   - Reader: Creator Only
   - Writer: Creator Only

> **Note**: This ensures only the message sender/receiver can access their messages. In the future, you can implement server-side logic to grant read access to both participants.

## Push Notifications Setup

### 1. Enable Push Notifications

1. In Xcode, go to "Signing & Capabilities"
2. Click "+ Capability"
3. Add "Push Notifications"
4. Add "Background Modes"
5. Check "Remote notifications"

### 2. Request Notification Permissions

Add this to your `AppDelegate` or main app file:

```swift
import UserNotifications
import CloudKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
        
        return true
    }
    
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Handle CloudKit notification
        Task {
            await MessageStore.shared.handleRemoteNotification(userInfo)
            completionHandler(.newData)
        }
    }
}
```

### 3. Update Your Main App File

```swift
@main
struct LonghornArtistsConnectApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## Usage

### Sending Messages

```swift
// Send a text message
let message = try await MessageStore.shared.sendMessage(
    to: recipientUserID,
    content: "Hello, world!",
    conversationID: conversationID
)

// Send a message with an attachment
let message = try await MessageStore.shared.sendMessage(
    to: recipientUserID,
    content: "Check out this photo!",
    conversationID: conversationID,
    attachmentURL: photoURL,
    attachmentType: .image
)
```

### Fetching Messages

```swift
// Fetch messages for a conversation
let messages = try await MessageStore.shared.fetchMessages(for: conversationID)

// Fetch all conversations
try await MessageStore.shared.fetchConversations()
```

### Marking Messages as Read

```swift
// Mark a single message as read
try await MessageStore.shared.markMessageAsRead(messageID)

// Mark entire conversation as read
try await MessageStore.shared.markConversationAsRead(conversationID)
```

### Using InMessageView

```swift
NavigationLink {
    InMessageView(
        conversationID: conversation.id,
        otherUserID: otherUser.id,
        otherUserName: otherUser.name,
        otherUserRole: otherUser.role
    )
} label: {
    Text("Message \(otherUser.name)")
}
```

## Privacy & Security

### Current Implementation

- Messages are stored in each user's **private CloudKit database**
- Only the authenticated user can read/write their own messages
- CloudKit handles encryption at rest and in transit
- Local persistence is stored in the app's sandboxed Documents directory

### Future Enhancements

To improve privacy and enable true peer-to-peer messaging:

1. **Shared Database**: Move conversations to a shared zone where both participants have access
2. **End-to-End Encryption**: Implement custom encryption before storing in CloudKit
3. **Message Deletion**: Add support for deleting messages from CloudKit (currently only local)
4. **Message Expiration**: Auto-delete messages after a certain period

### Implementing Shared Conversations

To allow both participants to see messages, you'll need to:

1. Create a **Custom Zone** in CloudKit
2. Use **CKShare** to share the conversation zone with the other participant
3. Grant appropriate permissions to both users

Example:

```swift
func shareConversation(_ conversation: Conversation, with userID: String) async throws {
    let zone = CKRecordZone(zoneName: "Conversation-\(conversation.id.uuidString)")
    let zoneID = zone.zoneID
    
    // Create zone
    _ = try await privateDatabase.save(zone)
    
    // Create share
    let share = CKShare(rootRecord: conversationRecord)
    share[CKShare.SystemFieldKey.title] = "Conversation with \(userID)"
    
    // Lookup participant
    let lookupInfo = CKUserIdentity.LookupInfo(userRecordID: CKRecord.ID(recordName: userID))
    let participants = try await container.shareParticipants(for: [lookupInfo])
    
    if let participant = participants.first {
        participant.permission = .readWrite
        share.addParticipant(participant)
    }
    
    // Save share
    _ = try await privateDatabase.save(share)
}
```

## Testing

### Development Environment

1. Use the **Development** CloudKit environment for testing
2. Sign in with a test Apple ID on your device/simulator
3. Ensure iCloud is enabled in Settings

### Testing Checklist

- [ ] Send text message
- [ ] Send image attachment
- [ ] Send video attachment
- [ ] Send document attachment
- [ ] Receive push notification
- [ ] Mark message as read
- [ ] View message history
- [ ] Handle network errors
- [ ] Offline message caching
- [ ] Background sync

## Troubleshooting

### Messages Not Sending

1. Check iCloud account is signed in
2. Verify CloudKit dashboard schema matches code
3. Check network connectivity
4. Review Xcode console for errors

### Push Notifications Not Working

1. Ensure physical device (notifications don't work reliably on simulator)
2. Check notification permissions in Settings
3. Verify "Push Notifications" capability is enabled
4. Ensure CloudKit subscriptions are created (check logs)

### Schema Mismatches

If you get schema errors:
1. Delete test data in CloudKit Dashboard
2. Reset Development environment schema
3. Redeploy schema changes

## Performance Considerations

### Message Pagination

For conversations with many messages, implement pagination:

```swift
func fetchMessages(
    for conversationID: UUID, 
    limit: Int = 50,
    cursor: CKQueryOperation.Cursor? = nil
) async throws -> ([Message], CKQueryOperation.Cursor?)
```

### Attachment Optimization

- Compress images before uploading
- Set maximum file size limits
- Use thumbnail previews for images/videos
- Store large files in iCloud Drive, reference in messages

### Background Sync

- Implement silent push notifications for background updates
- Use `URLSession` background tasks for large uploads
- Cache messages locally for offline access

## Deployment

### Before Production

1. **Switch to Production Environment** in CloudKit Dashboard
2. **Deploy Schema** from Development to Production
3. **Test** thoroughly with TestFlight
4. **Monitor** CloudKit usage and quotas
5. **Implement Analytics** to track message delivery success

### CloudKit Quotas

Free tier limits:
- Storage: 10 GB
- Data Transfer: 200 MB/day
- Requests: 40 requests/second

Monitor your usage in CloudKit Dashboard and plan for scaling.

## Additional Resources

- [CloudKit Documentation](https://developer.apple.com/documentation/cloudkit)
- [CloudKit Best Practices](https://developer.apple.com/videos/play/wwdc2021/10086/)
- [Push Notifications Guide](https://developer.apple.com/documentation/usernotifications)

## Support

For questions or issues with the messaging system, contact the development team or file an issue in the project repository.
