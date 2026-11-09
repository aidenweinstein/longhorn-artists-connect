//
//  EventReminderScheduler.swift
//  Longhorn Artists Connect
//

import Foundation
import UserNotifications

/// Schedules on-device reminders for every upcoming event in the feed: three days, one
/// day and one hour before it starts. An event on Friday at 1 PM reminds on Tuesday at
/// 1 PM, Thursday at 1 PM and Friday at 12 PM.
///
/// These are local notifications, so every user gets them without any server work —
/// the device already has the events feed. The full set is rebuilt whenever the feed
/// changes (new, edited or removed events) and on each foreground, so reminders never
/// point at a stale time or a deleted post.
enum EventReminderScheduler {

    /// How far ahead of the start each reminder fires, plus the phrase used in its body.
    private enum Lead: String, CaseIterable {
        case threeDays, oneDay, oneHour

        var phrase: String {
            switch self {
            case .threeDays: return "in 3 days"
            case .oneDay:    return "tomorrow"
            case .oneHour:   return "in 1 hour"
            }
        }

        /// Uses calendar arithmetic for the day offsets so the reminder keeps the same
        /// wall-clock time across a daylight-saving change (Tuesday 1 PM, not 12 PM).
        func fireDate(before start: Date, calendar: Calendar) -> Date? {
            switch self {
            case .threeDays: return calendar.date(byAdding: .day, value: -3, to: start)
            case .oneDay:    return calendar.date(byAdding: .day, value: -1, to: start)
            case .oneHour:   return calendar.date(byAdding: .hour, value: -1, to: start)
            }
        }
    }

    /// Every reminder's identifier starts with this, so a reschedule can clear exactly
    /// the reminders it owns without touching any other pending notification.
    private static let identifierPrefix = "event-reminder-"

    /// iOS keeps at most 64 pending local notifications per app and silently drops the
    /// rest, so only the soonest reminders are scheduled (with a little headroom). Later
    /// ones get picked up by a future reschedule as the earlier ones fire.
    private static let maxPendingReminders = 60

    /// A cheap fingerprint of everything the reminders depend on. Views reschedule when
    /// it changes instead of on every feed refresh.
    static func signature(for submissions: [Submission]) -> String {
        submissions
            .filter { $0.type == .event }
            .compactMap { event -> String? in
                guard let start = nextStart(of: event) else { return nil }
                return "\(event.id)|\(start.timeIntervalSince1970)|\(event.title)|\(event.eventLocation ?? "")"
            }
            .sorted()
            .joined(separator: ",")
    }

    /// Replaces all pending event reminders with a fresh set built from `submissions`.
    static func reschedule(for submissions: [Submission]) async {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        // Event reminders are for everyone, guests included (who are otherwise never
        // asked, since they can't message). iOS only ever shows this prompt once.
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }

        let now = Date()
        let calendar = Calendar.current

        // Build every future reminder, then keep only the soonest ones (see the cap).
        var reminders: [(fireDate: Date, request: UNNotificationRequest)] = []
        for event in submissions where event.type == .event {
            guard let start = nextStart(of: event) else { continue }
            for lead in Lead.allCases {
                guard let fireDate = lead.fireDate(before: start, calendar: calendar),
                      fireDate > now else { continue }
                reminders.append((fireDate, request(for: event, start: start, lead: lead, fireDate: fireDate, calendar: calendar)))
            }
        }
        reminders.sort { $0.fireDate < $1.fireDate }
        let scheduled = reminders.prefix(maxPendingReminders)

        // Clear the previous set first so deleted or rescheduled events stop reminding.
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        for reminder in scheduled {
            do {
                try await center.add(reminder.request)
            } catch {
                print("⚠️ Failed to schedule event reminder: \(error.localizedDescription)")
            }
        }
        print("🔔 Scheduled \(scheduled.count) event reminder(s) (\(reminders.count) upcoming)")
    }

    /// The start the reminders count down to: the next showing that hasn't begun yet
    /// (multi-showing events like a play's run), otherwise the event's own start.
    /// Nil for undated events and events that have already started.
    private static func nextStart(of event: Submission, now: Date = Date()) -> Date? {
        let starts = (event.eventShowings ?? []).map(\.start) + [event.eventStartDate].compactMap { $0 }
        return starts.filter { $0 > now }.min()
    }

    private static func request(for event: Submission, start: Date, lead: Lead, fireDate: Date, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = event.title.isEmpty ? "Upcoming Event" : event.title

        let time = start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        var body = "Starts \(lead.phrase) — \(time)"
        if let location = event.eventLocation?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            body += " at \(location)"
        }
        content.body = body
        content.sound = .default
        content.userInfo = ["eventReminderID": event.id.uuidString]

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(
            identifier: "\(identifierPrefix)\(event.id.uuidString)-\(lead.rawValue)",
            content: content,
            trigger: trigger
        )
    }
}
