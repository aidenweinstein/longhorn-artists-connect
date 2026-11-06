import SwiftUI
import UserNotifications

// MARK: - Live Show
/// A recurring weekly live show. While it's on air, `LiveStreamBanner` shows a
/// "<name> is Live!" strip at the top of the Home feed with a Stream button.
struct LiveShow: Identifiable {
    let id: String
    /// Display name used in the banner ("<name> is Live!").
    let name: String
    /// Optional venue appended to the banner text ("… is Live! @ <location>").
    var location: String? = nil
    /// Asset-catalog image shown at the left of the banner. `nil` falls back to a
    /// generic "live" symbol.
    var iconAsset: String? = nil
    /// Where the Stream button sends the user.
    let streamURL: URL
    /// Day of the week it airs, using `Calendar` numbering (1 = Sunday … 7 = Saturday).
    let weekday: Int
    /// Start time, in `timeZone`.
    let startHour: Int
    let startMinute: Int
    /// How long the banner stays up after the start time.
    let duration: TimeInterval
    /// The show's local time zone. "America/Chicago" follows CST/CDT automatically.
    var timeZone: TimeZone = TimeZone(identifier: "America/Chicago") ?? .current

    /// Banner text, e.g. "Longhorn Late Night is Live! @ HSM Studio".
    var bannerText: String {
        if let location, !location.isEmpty {
            // Non-breaking space keeps "@" on the same line as the venue if it wraps.
            return "\(name) is Live! @\u{00A0}\(location)"
        }
        return "\(name) is Live!"
    }

    /// True if `date` falls inside this week's (or last week's) airing window.
    /// Checking the most recent start before `date` handles shows that run past
    /// midnight into the next day.
    func isLive(at date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.weekday = weekday
        components.hour = startHour
        components.minute = startMinute
        guard let lastStart = calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTime,
            direction: .backward
        ) else { return false }
        return date < lastStart.addingTimeInterval(duration)
    }
}

// MARK: - Schedule
/// Every live show the app knows about. Add new shows here.
enum LiveStreams {
    static let shows: [LiveShow] = [
        // Wednesdays, 11:00 PM Central.
        LiveShow(
            id: "longhorn-late-night",
            name: "Longhorn Late Night",
            location: "HSM Studio",
            iconAsset: "PP Longhorn Late Night",
            streamURL: URL(string: "https://www.watchtstv.com/live")!,
            weekday: 4,
            startHour: 23,
            startMinute: 0,
            duration: 60 * 60
        ),
        // Thursdays, 11:00 PM Central.
        LiveShow(
            id: "next-week-now",
            name: "Next Week Now",
            location: "HSM",
            iconAsset: "PP Next Week Now",
            streamURL: URL(string: "https://www.watchtstv.com/live")!,
            weekday: 5,
            startHour: 23,
            startMinute: 0,
            duration: 60 * 60
        )
    ]

    /// Shows on air at `date`.
    static func liveShows(at date: Date) -> [LiveShow] {
        shows.filter { $0.isLive(at: date) }
    }
}

// MARK: - Go-Live Notifications
/// Schedules a repeating local notification for every show in `LiveStreams.shows`,
/// firing at the show's start each week. Local notifications need no server — each
/// device knows the schedule — and a repeating trigger keeps firing every week even
/// if the app isn't opened.
enum LiveStreamNotifications {
    /// Every go-live notification's identifier starts with this, so a reschedule can
    /// clear exactly the ones it owns without touching other pending notifications.
    private static let identifierPrefix = "live-stream-"

    /// `userInfo` key holding the stream link; the app delegate opens it on tap.
    static let streamURLKey = "liveStreamURL"

    /// Replaces all pending go-live notifications with a fresh set built from `LiveStreams.shows`.
    static func schedule() async {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        // For everyone, guests included. iOS only ever shows this prompt once.
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }

        // Clear the previous set first so removed or retimed shows stop notifying.
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        for show in LiveStreams.shows {
            do {
                try await center.add(request(for: show))
            } catch {
                print("⚠️ Failed to schedule live stream notification: \(error.localizedDescription)")
            }
        }
    }

    private static func request(for show: LiveShow) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = show.bannerText
        content.body = "Tap to stream now."
        content.sound = .default
        content.userInfo = [streamURLKey: show.streamURL.absoluteString]

        // Weekday + time in the show's own time zone, so it fires at 11 PM Central
        // wherever the user is, and follows CST/CDT.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = show.timeZone
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = show.timeZone
        components.weekday = show.weekday
        components.hour = show.startHour
        components.minute = show.startMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        return UNNotificationRequest(
            identifier: "\(identifierPrefix)\(show.id)",
            content: content,
            trigger: trigger
        )
    }
}

// MARK: - Preview Clock Override
extension EnvironmentValues {
    /// When set, the banner uses this time instead of the real clock. Used by
    /// previews to show the banner while a show is on air.
    @Entry var liveStreamsDateOverride: Date? = nil
}

// MARK: - Home Banner
/// Sits at the top of the Home feed (under the header) and lists any shows that
/// are live right now. Re-checks the schedule every 30 seconds so it appears and
/// disappears on its own.
struct LiveStreamBanner: View {
    @Environment(\.liveStreamsDateOverride) private var dateOverride
    @Environment(\.openURL) private var openURL

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let live = LiveStreams.liveShows(at: dateOverride ?? context.date)
            Group {
                if !live.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(live) { show in
                            row(for: show)
                        }
                    }
                    .background(Color(uiColor: .secondarySystemBackground))
                    .overlay(alignment: .bottom) {
                        Divider()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: live.map(\.id))
        }
    }

    /// The show's artwork as a small circle, or a pulsing "live" symbol if it has none.
    @ViewBuilder
    private func icon(for show: LiveShow) -> some View {
        if let asset = show.iconAsset {
            Image(asset)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
                .frame(width: 24)
        }
    }

    private func row(for show: LiveShow) -> some View {
        HStack(spacing: 12) {
            icon(for: show)
            Text(show.bannerText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Button {
                openURL(show.streamURL)
            } label: {
                Text("Stream")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.brandOrange, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stream \(show.name)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Previews
/// A Wednesday at 11:15 PM Central, so the previews show the banner as live.
private var previewLiveDate: Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
    let components = DateComponents(year: 2026, month: 9, day: 30, hour: 23, minute: 15)
    return calendar.date(from: components) ?? .now
}

#Preview("On the Home Feed") {
    HomeView_1()
        .environment(\.liveStreamsDateOverride, previewLiveDate)
}

#Preview("Banner Only") {
    VStack(spacing: 0) {
        LiveStreamBanner()
        Spacer()
    }
    .environment(\.liveStreamsDateOverride, previewLiveDate)
}
