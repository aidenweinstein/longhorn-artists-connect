//
//  NotificationService.swift
//  NotificationService
//
//  Restyles incoming message pushes as iOS communication notifications: the
//  sender's profile picture becomes the big icon with the Nexus app icon small in
//  its corner, the way Messages and other chat apps look. (The system always draws
//  the avatar as a circle.) No photo → the system draws a monogram of the name.
//
//  CloudKit sends the Message subscription's push with `mutable-content` set (see
//  `MessageStore.setupMessageSubscription` in the app), which routes it through here
//  before it's shown. The payload already carries `senderUserID`, `senderName` and
//  `messagePreview`; the photo comes from the sender's `UserProfile` record in the
//  shared CloudKit container and is cached on disk so later messages are instant.
//
//  Anything that isn't a message push (or that fails along the way) is delivered
//  untouched, so a banner always appears. The app keeps its own copy of the restyle
//  logic in `CommunicationNotifications.swift` for its local banners.
//

import CloudKit
import Intents
import UIKit
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {

    /// Hands the content to the system exactly once, whichever of the two paths
    /// (finished or out of time) gets there first.
    private final class Delivery: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: ((UNNotificationContent) -> Void)?
        let fallback: UNNotificationContent

        init(handler: @escaping (UNNotificationContent) -> Void, fallback: UNNotificationContent) {
            self.handler = handler
            self.fallback = fallback
        }

        func deliver(_ content: UNNotificationContent) {
            lock.lock()
            let handler = self.handler
            self.handler = nil
            lock.unlock()
            handler?(content)
        }
    }

    private var delivery: Delivery?
    private var work: Task<Void, Never>?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        let delivery = Delivery(handler: contentHandler, fallback: request.content)
        self.delivery = delivery

        // Only CloudKit message pushes carry a sender. Anything else passes straight through.
        guard let mutable = request.content.mutableCopy() as? UNMutableNotificationContent,
              let query = CKQueryNotification(fromRemoteNotificationDictionary: request.content.userInfo),
              let rawSenderID = query.recordFields?["senderUserID"] as? String,
              !rawSenderID.isEmpty else {
            delivery.deliver(request.content)
            return
        }

        let senderID = Self.canonicalUserID(rawSenderID)
        let senderName = (query.recordFields?["senderName"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? mutable.title

        work = Task {
            let imageData = await SenderPhotoStore.imageData(for: senderID)
            let styled = await CommunicationStyle.apply(to: mutable,
                                                        senderID: senderID,
                                                        senderName: senderName,
                                                        senderImageData: imageData)
            delivery.deliver(styled)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Out of time: show the plain banner rather than nothing.
        work?.cancel()
        if let delivery { delivery.deliver(delivery.fallback) }
    }

    /// Message records store the raw CloudKit user record name, but be tolerant of
    /// the directory's `UserProfile_<id>` form so both resolve to the same person.
    static func canonicalUserID(_ id: String) -> String {
        let prefix = "UserProfile_"
        return id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id
    }
}

// MARK: - Communication styling

/// Mirror of the app's `CommunicationNotifications` — extensions can't share app code.
enum CommunicationStyle {

    /// Longest side of the avatar handed to the system; it's drawn at ~40pt.
    static let avatarMaxSide: CGFloat = 256

    static func apply(to content: UNMutableNotificationContent,
                      senderID: String,
                      senderName: String,
                      senderImageData: Data?) async -> UNNotificationContent {
        let sender = INPerson(personHandle: INPersonHandle(value: senderID, type: .unknown),
                              nameComponents: nil,
                              displayName: senderName,
                              image: senderImageData.map { INImage(imageData: $0) },
                              contactIdentifier: nil,
                              customIdentifier: senderID)
        // Incoming, so the current user is implicitly the recipient; no recipients and
        // no group name gives the one-to-one look with the sender's avatar. Chats are
        // strictly one-to-one in Nexus, so the sender identifies the thread.
        let intent = INSendMessageIntent(recipients: nil,
                                         outgoingMessageType: .outgoingMessageText,
                                         content: content.body,
                                         speakableGroupName: nil,
                                         conversationIdentifier: "dm-\(senderID)",
                                         serviceName: nil,
                                         sender: sender,
                                         attachments: nil)

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        try? await interaction.donate()

        do {
            return try content.updating(from: intent)
        } catch {
            return content
        }
    }
}

// MARK: - Sender photo

/// Fetches a sender's profile photo from their `UserProfile` record and keeps a
/// downscaled copy in this extension's own caches directory.
enum SenderPhotoStore {

    private static let containerID = "iCloud.LAA.Longhorn-Artists-Connect"
    /// How long a cached photo is trusted before a fresh fetch is tried.
    private static let maxCacheAge: TimeInterval = 24 * 60 * 60

    /// The sender's photo as JPEG data, or nil if they have none / nothing could be
    /// fetched. A fresh-enough cached copy wins; a stale one is the fallback when the
    /// network fetch fails.
    static func imageData(for senderID: String) async -> Data? {
        let cacheURL = cacheURL(for: senderID)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < maxCacheAge,
           let data = try? Data(contentsOf: cacheURL) {
            return data.isEmpty ? nil : data
        }

        switch await fetchPhoto(for: senderID) {
        case .success(let data):
            // An empty file remembers "no photo" so we don't refetch every message.
            try? (data ?? Data()).write(to: cacheURL, options: .atomic)
            return data
        case .failure:
            guard let stale = try? Data(contentsOf: cacheURL), !stale.isEmpty else { return nil }
            return stale
        }
    }

    /// `.success(nil)` means the profile exists but has no photo.
    private static func fetchPhoto(for senderID: String) async -> Result<Data?, Error> {
        let database = CKContainer(identifier: containerID).publicCloudDatabase
        let recordID = CKRecord.ID(recordName: "UserProfile_\(senderID)")
        do {
            let results = try await database.records(for: [recordID], desiredKeys: ["profileImage"])
            guard let result = results[recordID] else { return .success(nil) }
            let record = try result.get()
            guard let asset = record["profileImage"] as? CKAsset,
                  let fileURL = asset.fileURL,
                  let raw = try? Data(contentsOf: fileURL) else { return .success(nil) }
            return .success(downscaled(raw))
        } catch {
            return .failure(error)
        }
    }

    /// Profile photos are uploaded at full size; shrink to what a banner needs.
    private static func downscaled(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > CommunicationStyle.avatarMaxSide else { return data }
        let scale = CommunicationStyle.avatarMaxSide / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return image.preparingThumbnail(of: target)?.jpegData(compressionQuality: 0.85) ?? data
    }

    private static func cacheURL(for senderID: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = caches.appendingPathComponent("SenderPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Record names are plain ASCII, but keep the file name safe regardless.
        let safe = senderID.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(safe).jpg")
    }
}
