//
//  CommunicationNotifications.swift
//  Longhorn Artists Connect
//
//  Turns a plain banner into an iOS communication notification: the person's
//  profile picture becomes the big icon with the Nexus app icon tucked in its corner,
//  the way Messages and other chat apps look. (The system always draws this avatar
//  as a circle; there is no square option.) No photo → the system draws a monogram
//  of the name instead.
//
//  Used for the local "a connection posted" banner (`ConnectionsManager`). Incoming
//  message pushes get the same treatment in the NotificationService extension, which
//  carries its own copy of this logic because extensions can't share app code.
//
//  Needs the Communication Notifications entitlement on the app target and
//  `INSendMessageIntent` under `NSUserActivityTypes` in Info.plist — both set.
//

import Foundation
import Intents
import UIKit
import UserNotifications

enum CommunicationNotifications {

    /// Longest side of the avatar handed to the system. It's drawn at ~40pt, so this
    /// keeps the intent small without visible loss.
    private static let avatarMaxSide: CGFloat = 256

    /// Returns `content` restyled as a message from `senderName`. Falls back to the
    /// untouched content if the system rejects the intent, so a banner always shows.
    static func styled(_ content: UNMutableNotificationContent,
                       senderID: String,
                       senderName: String,
                       senderImageData: Data?,
                       conversationID: String) async -> UNNotificationContent {
        let sender = INPerson(personHandle: INPersonHandle(value: senderID, type: .unknown),
                              nameComponents: nil,
                              displayName: senderName,
                              image: avatar(from: senderImageData),
                              contactIdentifier: nil,
                              customIdentifier: senderID)
        // Incoming, so the current user is implicitly the recipient — no `recipients`
        // and no group name means a one-to-one look with the sender's avatar.
        let intent = INSendMessageIntent(recipients: nil,
                                         outgoingMessageType: .outgoingMessageText,
                                         content: content.body,
                                         speakableGroupName: nil,
                                         conversationIdentifier: conversationID,
                                         serviceName: nil,
                                         sender: sender,
                                         attachments: nil)

        // Donating lets Focus and Siri treat this as a message from a person. A failed
        // donation isn't fatal — the restyle below still works.
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        try? await interaction.donate()

        do {
            return try content.updating(from: intent)
        } catch {
            print("⚠️ Couldn't style communication notification: \(error.localizedDescription)")
            return content
        }
    }

    /// The stored profile JPEG, downscaled for the intent. Nil when there's no photo.
    static func avatar(from data: Data?) -> INImage? {
        guard let data, let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > avatarMaxSide else { return INImage(imageData: data) }
        let scale = avatarMaxSide / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        guard let small = image.preparingThumbnail(of: target),
              let jpeg = small.jpegData(compressionQuality: 0.85) else {
            return INImage(imageData: data)
        }
        return INImage(imageData: jpeg)
    }
}
