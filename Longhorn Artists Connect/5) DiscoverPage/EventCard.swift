//
//  EventCard.swift
//  Longhorn Artists Connect
//
//  Created by Aiden Weinstein on 2/12/26.
//
//  This file contains UI components for displaying events in the Discover feed
//  and the detail view for events with dates, locations, and ticket links.

import SwiftUI

// MARK: - Event Card Component (for Discover Feed)

struct EventCard: View {
    let event: Submission

    /// The flyer's bounding box (2:3). The flyer itself is fitted inside it at its own
    /// aspect ratio, so the slot — not the image — is what reserves the space. Together
    /// with the date box, the left cluster fills roughly half the card width, leaving the
    /// rest for the details column.
    private let posterWidth: CGFloat = 110
    private let posterHeight: CGFloat = 165

    private var categoryKind: EventCategoryKind? { EventCategoryKind(rawValue: event.genres.first ?? "") }

    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(event.title.hashValue)
        return colors[hash % colors.count]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Boxed date/time to the left of the flyer, centered vertically against it.
                // Pin the centering region to the flyer's height (not the full row) so a
                // tall info column on the right can't drag the box below the flyer's center.
                dateBox
                    .frame(height: posterHeight, alignment: .center)

                // Flyer/poster
                ZStack {
                    if let thumbnailData = event.thumbnailData,
                       let uiImage = UIImage(data: thumbnailData) {
                        // Fit, never fill: the flyer keeps its own aspect ratio and is
                        // shown whole inside the poster slot. Filling would crop off the
                        // edges of anything that isn't 2:3, which hides flyer content.
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Rectangle()
                            .fill(LinearGradient(colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(
                                VStack(spacing: 4) {
                                    if let startDate = event.eventStartDate {
                                        Text(startDate, format: .dateTime.month(.abbreviated))
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.white.opacity(0.9))
                                        
                                        Text(startDate, format: .dateTime.day())
                                            .font(.system(size: 32, weight: .bold))
                                            .foregroundStyle(.white)
                                    } else {
                                        Image(systemName: "calendar")
                                            .font(.system(size: 40))
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                }
                            )
                    }
                }
                .frame(width: posterWidth, height: posterHeight)
                .clipped() // Remove rounded corners, just clip to frame

                // Event info on right — just the title and description (see `infoColumn`),
                // vertically centered against the flyer so the text block reads as level
                // with the poster rather than hugging its top edge.
                VStack(alignment: .leading, spacing: 6) {
                    infoColumn
                }
                .frame(maxWidth: .infinity, minHeight: posterHeight, alignment: .leading)
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Info Column

    /// The right-hand column: the title and the description, and nothing else. Date and
    /// time live in the boxed `dateBox` to the left of the flyer, and the category is
    /// conveyed by the accent icon above it. Everything else (host, lineup, location,
    /// expectations, ticket/apply links) is left to the detail view, so the card stays a
    /// clean title + description read.
    @ViewBuilder private var infoColumn: some View {
        titleText
        loglineText(lineLimit: 5)
    }

    private var titleText: some View {
        Text(event.title)
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func loglineText(lineLimit: Int) -> some View {
        if !event.logline.isEmpty {
            Text(event.logline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(lineLimit)
        }
    }

    // MARK: - Date/Time Box (left of the card)

    /// A boxed date/time summary shown to the left of the flyer, topped by an icon for
    /// the event's category, e.g.
    ///
    ///     🎤  (category icon)
    ///     Sep
    ///     10
    ///     7:30pm
    ///
    /// with the day number largest. Only the start time is shown. Recruitment Schedule
    /// (a date range with no times) omits the time line.
    @ViewBuilder private var dateBox: some View {
        if let startDate = event.eventStartDate {
            VStack(spacing: 8) {
                // Category icon above the date box — the card's at-a-glance event type.
                if let icon = categoryKind?.accentIcon {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(Color.brandOrange)
                }

                VStack(spacing: 2) {
                    Text(startDate, format: .dateTime.month(.abbreviated))
                        .font(.subheadline.weight(.semibold))
                        .textCase(.uppercase)

                    Text(startDate, format: .dateTime.day())
                        .font(.system(size: 34, weight: .bold))

                    if let startTimeText {
                        Text(startTimeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(.primary)
                .frame(width: 62)
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    /// The event's start time, e.g. "7:30pm". Recruitment Schedule (date range, no times)
    /// shows nothing here.
    private var startTimeText: String? {
        guard categoryKind?.usesDateRange != true,
              let start = event.eventStartDate else { return nil }
        return timeString(start, includeMeridiem: true)
    }

    /// A time like "7:30pm" (with meridiem) or "7:30" (without), lowercased.
    private func timeString(_ date: Date, includeMeridiem: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = includeMeridiem ? "h:mma" : "h:mm"
        return formatter.string(from: date).lowercased()
    }

}

// MARK: - Event Detail View

struct EventDetailView: View {
    let event: Submission
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    
    @State private var isLoading = true
    @State private var contentLoaded = false
    /// Shown only once loading has run for over 1.5s (first-launch content download).
    @State private var showSlowLoadingMessage = false
    @State private var showFullScreenPoster = false
    @State private var showEditSheet = false

    /// Known organizations, so a host that names one can link to that org's page.
    @ObservedObject private var orgStore = OrganizationStore.shared
    /// The org whose page is presented when the host is tapped (nil = none).
    @State private var selectedOrg: Organization?

    /// The organization the host links to, when the host names a known org.
    private var hostOrganization: Organization? {
        let host = event.eventHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return nil }
        return orgStore.organizations.first { $0.name.caseInsensitiveCompare(host) == .orderedSame }
    }

    // Check if current user is the event creator or a moderator
    private var canEditOrDelete: Bool {
        // Check if user is the creator
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        let isUserCreator = !currentUser.isEmpty && currentUser == event.submittedBy
        
        // Debug logging
        print("🔍 [Event] Edit/Delete Permission Check:")
        print("   Current User: '\(currentUser)'")
        print("   Event Submitted By: '\(event.submittedBy)'")
        print("   Is User Creator: \(isUserCreator)")
        
        // Check if user is the moderator (gated on the CloudKit user record ID).
        let isModeratorMode = UserDefaults.standard.bool(forKey: "isModeratorMode")
        let canUseModerator = isModeratorMode && ModeratorAccess.isModerator

        print("   Is Moderator Mode: \(isModeratorMode)")
        print("   Is Moderator: \(ModeratorAccess.isModerator)")
        print("   Can Edit/Delete: \(isUserCreator || canUseModerator)")

        return isUserCreator || canUseModerator
    }

    /// The event category (Concert, Info Session, …), stored in the submission's `genres`.
    private var eventCategory: String { event.genres.first ?? "" }

    private var categoryKind: EventCategoryKind? { EventCategoryKind(rawValue: eventCategory) }

    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(event.title.hashValue)
        return colors[hash % colors.count]
    }

    // MARK: - Date/Time Formatting

    /// "Mon, Oct 5" — abbreviated weekday, abbreviated month, day.
    private func longDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    /// "7:00pm" — lowercase meridiem, no space.
    private func shortTimeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date).lowercased()
    }

    /// Theatre Performance: the run's showings in order. Empty for every other category,
    /// and for a theatre post whose showings haven't synced.
    private var showings: [EventShowing] {
        guard categoryKind?.usesShowings == true else { return [] }
        return (event.eventShowings ?? []).sorted { $0.start < $1.start }
    }

    /// One showing: "Fri, Oct 10 • 7:30pm - 9:30pm".
    private func showingLine(_ showing: EventShowing) -> String {
        "\(longDateString(showing.start)) • \(shortTimeString(showing.start)) - \(shortTimeString(showing.end))"
    }

    /// The large date line shown under the title:
    /// "Monday, Oct 5 • 7:00pm - 11:00pm" for timed events, a date range for
    /// Recruitment Schedule (which has no times), or the span of the run for a
    /// multi-showing event (each showing is then listed below). `nil` when the event has
    /// no date.
    private var eventDateText: String? {
        // A run spans its first through its last performance; a one-night run reads as
        // an ordinary single date, so it falls through to the timed-event line below.
        if let first = showings.first, let last = showings.last,
           !Calendar.current.isDate(first.start, inSameDayAs: last.start) {
            return "\(longDateString(first.start)) - \(longDateString(last.start))"
        }

        guard let start = event.eventStartDate else { return nil }

        if categoryKind?.usesDateRange == true {
            if let end = event.eventEndDate {
                return "\(longDateString(start)) - \(longDateString(end))"
            }
            return longDateString(start)
        }

        var line = longDateString(start)
        if let end = event.eventEndDate,
           Calendar.current.isDate(start, inSameDayAs: end) {
            line += " • \(shortTimeString(start)) - \(shortTimeString(end))"
        } else {
            line += " • \(shortTimeString(start))"
        }
        return line
    }

    /// One Details row: a bold label on the left, its value trailing-aligned on the right.
    @ViewBuilder
    private func detailRow<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            value()
                .font(.body)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if isLoading && !contentLoaded {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    if showSlowLoadingMessage {
                        Text("When first downloading Nexus, content may take a few minutes to load. But, from there on after, it will be quick!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    // Only surface the first-launch hint if loading is still going after 1.5s.
                    // SwiftUI cancels this task when content loads and the view is removed.
                    try? await Task.sleep(for: .seconds(1.5))
                    showSlowLoadingMessage = true
                }
            } else {
                // Main content
                ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Poster alone at the top, title/info stacked below (like projects)
                    VStack(alignment: .leading, spacing: 12) {
                        // Flyer spans the full width, edge to edge (aspect ratio preserved).
                        Button {
                            showFullScreenPoster = true
                        } label: {
                            if let thumbnailData = event.thumbnailData,
                               let uiImage = UIImage(data: thumbnailData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .clipped() // Edge-to-edge, no rounded corners
                            } else {
                                ZStack {
                                    Rectangle()
                                        .fill(LinearGradient(colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))

                                    Image(systemName: "calendar")
                                        .font(.system(size: 72))
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 353)
                                .clipped() // No rounded corners
                            }
                        }
                        .buttonStyle(.plain)

                        // Title, large date/time, and location — the event's
                        // at-a-glance header, left-aligned below the poster.
                        VStack(alignment: .leading, spacing: 8) {
                            Text(event.title)
                                .font(.system(size: 28, weight: .bold))
                                .minimumScaleFactor(0.6)
                                .lineLimit(2)

                            // Large date line: "Monday, Oct 5 • 7:00pm - 11:00pm".
                            if let eventDateText {
                                Text(eventDateText)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            // Every performance in the run, listed under the date span.
                            // Only for a real run — a single showing is already spelled
                            // out, with its times, in the date line above.
                            if showings.count > 1 {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Showings")
                                        .font(.headline)
                                    ForEach(showings) { showing in
                                        Text(showingLine(showing))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.top, 4)
                            }

                            // Location — a clickable orange link to Apple Maps.
                            if let location = event.eventLocation, !location.isEmpty {
                                Button {
                                    openLocationInMaps(location: location)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "location.fill")
                                            .font(.subheadline)
                                        Text(location)
                                            .font(.body)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                    .foregroundStyle(Color.brandOrange)
                                }
                                .buttonStyle(.plain)
                            }

                            if !event.logline.isEmpty {
                                Text(event.logline)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    }
                    
                    // Details Section — label/value rows (Host, Category, lineup,
                    // Entry Requirements). Date and location live in the header above.
                    if !eventCategory.isEmpty || !event.eventHost.isEmpty
                        || (event.eventLineup?.isEmpty == false)
                        || (event.eventExpectations?.isEmpty == false) {
                        Divider()
                            .padding(.top, 12)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Details")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)

                            VStack(alignment: .leading, spacing: 10) {
                                // Host — orange and tappable when it names a known org
                                // (opens its page); plain gray text otherwise.
                                if !event.eventHost.isEmpty {
                                    detailRow("Host") {
                                        if let org = hostOrganization {
                                            Button {
                                                selectedOrg = org
                                            } label: {
                                                Text(event.eventHost)
                                                    .foregroundStyle(Color.brandOrange)
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            Text(event.eventHost)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                // Category (e.g. Artist Mixer).
                                if !eventCategory.isEmpty {
                                    detailRow("Category") {
                                        Text(eventCategory)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                // Lineup — Artists / Actors / Films for the category.
                                if let label = categoryKind?.lineupLabel,
                                   let lineup = event.eventLineup, !lineup.isEmpty {
                                    detailRow(label) {
                                        Text(lineup)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                // Entry Requirements (Recruitment Schedule expectations).
                                if let expectations = event.eventExpectations, !expectations.isEmpty {
                                    detailRow("Entry Requirements") {
                                        Text(expectations)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        // Buy Ticket button — only when a real tickets link is provided.
                        // Trim first so a whitespace-only value (e.g. an empty string
                        // round-tripped through CloudKit) doesn't surface the button.
                        if let ticketsURL = event.eventTicketsURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !ticketsURL.isEmpty,
                           let url = URL(string: ticketsURL) {
                            Link(destination: url) {
                                HStack {
                                    Image(systemName: "ticket")
                                    Text("Buy Ticket")
                                }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.brandOrange)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        } else if let applyURL = event.eventApplicationURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                                  !applyURL.isEmpty,
                                  let url = URL(string: applyURL) {
                            Link(destination: url) {
                                HStack {
                                    Image(systemName: "square.and.pencil")
                                    Text("Apply")
                                }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.brandOrange)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        
                        // Edit and Delete buttons for creator or moderator
                        if canEditOrDelete {
                            OwnerActionButtons(
                                onEdit: { showEditSheet = true },
                                onDelete: {
                                    store.delete(event)
                                    dismiss()
                                }
                            )
                        }
                    }
                    .padding()
                }
                }
            }
        }
        .presentationDragIndicator(.hidden)
        .fullScreenCover(isPresented: $showFullScreenPoster) {
            EventFullScreenPosterView(event: event, tintColor: tintColor)
        }
        .sheet(isPresented: $showEditSheet) {
            EventEditView(submission: event) { updatedSubmission in
                store.update(updatedSubmission)
            }
        }
        .sheet(item: $selectedOrg) { org in
            NavigationStack { OrganizationPageView(organization: org) }
                .presentationDragIndicator(.hidden)
        }
        .onAppear {
            // Simulate loading delay using Swift Concurrency
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation {
                    isLoading = false
                    contentLoaded = true
                }
            }
        }
    }
    
    private func openLocationInMaps(location: String) {
        // Encode the location for URL
        guard let encodedLocation = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "maps://?q=\(encodedLocation)") else {
            return
        }
        
        // Try to open in Apple Maps
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            // Fallback to web version
            if let webURL = URL(string: "https://maps.apple.com/?q=\(encodedLocation)") {
                UIApplication.shared.open(webURL)
            }
        }
    }
}

// MARK: - Event Full Screen Poster View

struct EventFullScreenPosterView: View {
    let event: Submission
    let tintColor: Color
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Poster image
            if let thumbnailData = event.thumbnailData,
               let uiImage = UIImage(data: thumbnailData) {
                // Blurred, filled copy behind the poster so the letterbox space around it
                // shows a soft version of the art rather than flat black.
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .blur(radius: 40)
                    .overlay(Color.black.opacity(0.35))
                    .clipped()

                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Rectangle()
                    .fill(LinearGradient(colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Close button in top right
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(.black.opacity(0.5))
                            )
                            .contentShape(Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Preview Samples

#if DEBUG
extension Submission {
    /// A fully-populated sample event for previewing one category's card/detail UI.
    /// Every field the category surfaces is filled so the layout can be tuned per type.
    static func sampleEvent(_ kind: EventCategoryKind) -> Submission {
        var s = Submission(
            id: UUID(),
            type: .event,
            title: sampleEventTitle(kind),
            details: "",
            isApproved: true,
            submittedBy: "Aiden Weinstein"
        )
        s.logline = "A short description of the event that gives people the gist of what to expect and why they should come."
        s.eventHost = "Longhorn Film Collective"
        s.genres = [kind.rawValue]

        let calendar = Calendar.current
        let evening = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()

        if kind.usesDateRange {
            // Recruitment: a start/end date range, expectations, application link.
            s.eventStartDate = Date()
            s.eventEndDate = calendar.date(byAdding: .day, value: 14, to: Date())
            s.eventExpectations = "Weekly 3-hour meetings, one weekend shoot per month, and active participation in the group chat."
            s.eventApplicationURL = "https://example.com/apply"
        } else if kind.usesShowings {
            // Theatre: a three-night run, with the post's dates bracketing the showings.
            s.eventShowings = (0..<3).compactMap { offset in
                guard let start = calendar.date(byAdding: .day, value: offset, to: evening),
                      let end = calendar.date(byAdding: .hour, value: 2, to: start)
                else { return nil }
                return EventShowing(start: start, end: end)
            }
            s.syncEventDatesToShowings()
            s.eventLocation = "Winship Drama Building, 300 E 23rd St, Austin, TX"
        } else {
            // Everything else: a single date with a start/end time and a location.
            s.eventStartDate = evening
            s.eventEndDate = calendar.date(byAdding: .hour, value: 2, to: evening)
            s.eventLocation = "Winship Drama Building, 300 E 23rd St, Austin, TX"
        }

        switch kind {
        case .concert:
            s.eventLineup = "The Bright Lights, Marfa, Neon Coast"
            s.eventTicketsURL = "https://example.com/tickets"
        case .actorShowcase:
            s.eventLineup = "Jordan Lee, Priya Shah, Marcus Webb, Elena Ruiz"
        case .theatrePerformance:
            s.eventLineup = "Jordan Lee, Priya Shah, Marcus Webb, Elena Ruiz"
            s.eventTicketsURL = "https://example.com/tickets"
        case .filmFestival:
            s.eventLineup = "Sundown, The Long Wait, Static, Bloom"
        case .speaker:
            s.eventLineup = "Dana Whitfield, Omar Castillo"
        default:
            break
        }
        return s
    }

    private static func sampleEventTitle(_ kind: EventCategoryKind) -> String {
        switch kind {
        case .recruitmentSchedule: return "Fall Recruitment"
        case .infoSession:         return "New Member Info Session"
        case .concert:             return "Spring Showcase Concert"
        case .actorShowcase:       return "Actor Showcase Night"
        case .theatrePerformance:  return "Our Town"
        case .filmFestival:        return "Longhorn Film Festival"
        case .artistMixer:         return "Artist Mixer"
        case .speaker:             return "Guest Speaker Talk"
        }
    }
}

// MARK: - Card Previews (one per category, all fields filled)

#Preview("Card • Recruitment") {
    EventCard(event: .sampleEvent(.recruitmentSchedule)).padding(.horizontal)
}
#Preview("Card • Info Session") {
    EventCard(event: .sampleEvent(.infoSession)).padding(.horizontal)
}
#Preview("Card • Concert") {
    EventCard(event: .sampleEvent(.concert)).padding(.horizontal)
}
#Preview("Card • Actor Showcase") {
    EventCard(event: .sampleEvent(.actorShowcase)).padding(.horizontal)
}
#Preview("Card • Theatre Performance") {
    EventCard(event: .sampleEvent(.theatrePerformance)).padding(.horizontal)
}
#Preview("Card • Film Festival") {
    EventCard(event: .sampleEvent(.filmFestival)).padding(.horizontal)
}
#Preview("Card • Artist Mixer") {
    EventCard(event: .sampleEvent(.artistMixer)).padding(.horizontal)
}
#Preview("Card • Speaker") {
    EventCard(event: .sampleEvent(.speaker)).padding(.horizontal)
}

// MARK: - Detail Previews (one per category, all fields filled)

#Preview("Detail • Recruitment") { EventDetailView(event: .sampleEvent(.recruitmentSchedule)) }
#Preview("Detail • Info Session") { EventDetailView(event: .sampleEvent(.infoSession)) }
#Preview("Detail • Concert") { EventDetailView(event: .sampleEvent(.concert)) }
#Preview("Detail • Actor Showcase") { EventDetailView(event: .sampleEvent(.actorShowcase)) }
#Preview("Detail • Theatre Performance") { EventDetailView(event: .sampleEvent(.theatrePerformance)) }
#Preview("Detail • Film Festival") { EventDetailView(event: .sampleEvent(.filmFestival)) }
#Preview("Detail • Artist Mixer") { EventDetailView(event: .sampleEvent(.artistMixer)) }
#Preview("Detail • Speaker") { EventDetailView(event: .sampleEvent(.speaker)) }
#endif
