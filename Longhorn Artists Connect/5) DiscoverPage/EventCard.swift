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

extension Submission {
    /// Whether an event is over: once its last showing, its end, or (with no end) its
    /// start has passed. Shared by the event detail (which stops taking RSVPs) and the
    /// profile "See You At" row (which only lists upcoming events).
    var eventHasEnded: Bool {
        let lastShowingEnd = eventShowings?.map(\.end).max()
        guard let last = lastShowingEnd ?? eventEndDate ?? eventStartDate else { return false }
        return last < Date()
    }
}

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
    ///     Wed
    ///     Sep
    ///     10
    ///     7:30pm
    ///
    /// with the day number largest. Only the start time is shown. Events from a previous
    /// year show that year in place of the time.
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
                    Text(startDate, format: .dateTime.weekday(.abbreviated))
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

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

    /// The event's start time, e.g. "7:30pm" — or its year, e.g. "2025", when the event
    /// is from a previous year.
    private var startTimeText: String? {
        guard let start = event.eventStartDate else { return nil }
        let calendar = Calendar.current
        let startYear = calendar.component(.year, from: start)
        if startYear < calendar.component(.year, from: Date()) {
            return String(startYear)
        }
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
    /// The post as it was when the detail opened. Read it through `event` instead, which
    /// resolves the store's current copy — so an edit shows immediately, and a second
    /// edit starts from the first one's result instead of silently reverting it.
    private let passedEvent: Submission
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SubmissionStore_3_2 = .shared

    init(event: Submission) {
        self.passedEvent = event
    }

    /// The live version of this event from the store (see `passedEvent`).
    private var event: Submission {
        store.currentCopy(of: passedEvent)
    }

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

    /// Everyone going to this event (iCloud user record names, oldest RSVP first),
    /// loaded from the `EventAttendance` records when the detail opens.
    @State private var attendeeIDs: [String] = []
    /// The current user's own answer (Going / Maybe / Can't Go), nil if unanswered.
    @State private var myRSVP: EventRSVPStatus?
    /// True while an RSVP save/delete is in flight, so taps can't stack up.
    @State private var isUpdatingGoing = false
    @State private var showAttendees = false
    /// Set when an RSVP couldn't be saved; drives the alert.
    @State private var goingErrorMessage: String?
    @ObservedObject private var profiles = UserProfileManager.shared

    /// Past events keep their "who went" list but no longer take new RSVPs. An event
    /// is over once its last showing, its end, or (with no end) its start has passed.
    private var isEventOver: Bool { event.eventHasEnded }

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

    /// Height of the poster band at the top of the page — about 40% of an iPhone
    /// screen, so the title, date, description, and location all fit beneath it on
    /// the first screen regardless of the flyer's aspect ratio.
    private var posterBandHeight: CGFloat { 340.scaledToScreen }

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

    /// The event's showings in order. Empty for a single-date post, and for a post whose
    /// showings haven't synced.
    private var showings: [EventShowing] {
        (event.eventShowings ?? []).sorted { $0.start < $1.start }
    }

    /// One showing: "Fri, Oct 10 • 7:30pm - 9:30pm".
    private func showingLine(_ showing: EventShowing) -> String {
        "\(longDateString(showing.start)) • \(shortTimeString(showing.start)) - \(shortTimeString(showing.end))"
    }

    /// The large date line shown under the title:
    /// "Monday, Oct 5 • 7:00pm - 11:00pm" for timed events, or the span of the run for a
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
                        // Flyer in a fixed-height, edge-to-edge band so the title, date,
                        // and location stay on the first screen whatever shape the flyer
                        // is. The whole flyer is shown (aspect ratio preserved), centered
                        // over a blurred copy of itself that fills the gutters a portrait
                        // or landscape flyer leaves. Tap for the full-size poster.
                        Button {
                            showFullScreenPoster = true
                        } label: {
                            if let thumbnailData = event.thumbnailData,
                               let uiImage = UIImage(data: thumbnailData) {
                                Color.clear
                                    .overlay {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .blur(radius: 40)
                                    }
                                    .overlay(Color.black.opacity(0.3))
                                    .overlay {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFit()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: posterBandHeight)
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
                                .frame(height: posterBandHeight)
                                .clipped() // No rounded corners
                            }
                        }
                        .buttonStyle(.plain)

                        // Going / Maybe / Can't Go buttons and the row of who's going sit
                        // directly under the poster so RSVPing is the first thing you see.
                        if !isEventOver || !attendeeIDs.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                if !isEventOver {
                                    rsvpButtons
                                }
                                if !attendeeIDs.isEmpty {
                                    whosGoingRow
                                }
                            }
                            .padding(.horizontal)
                        }

                        // Title, large date/time, description, and location — the event's
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

                            if !event.logline.isEmpty {
                                Text(event.logline)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
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

                                // Lineup — labelled Artists / Actors / Films on posts that
                                // still carry a category, plain "Artists" otherwise.
                                if let lineup = event.eventLineup, !lineup.isEmpty {
                                    detailRow(categoryKind?.lineupLabel ?? "Artists") {
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
                        // One button per link the poster filled in, each with its own
                        // icon. Links left blank produce no button.
                        linkButton(event.eventApplicationURL, title: "Apply", icon: "square.and.pencil")
                        linkButton(event.eventTicketsURL, title: "Buy Tickets", icon: "ticket")
                        linkButton(event.eventRSVPURL, title: "RSVP", icon: "envelope.open")
                        linkButton(event.eventWebsiteURL, title: "Visit Website", icon: "globe")

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
        .sheet(isPresented: $showAttendees) {
            EventAttendeesSheet(attendeeIDs: attendeeIDs, isEventOver: isEventOver)
        }
        .task { await loadAttendees() }
        .alert(
            "Couldn't RSVP",
            isPresented: Binding(get: { goingErrorMessage != nil }, set: { if !$0 { goingErrorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(goingErrorMessage ?? "")
        }
        .onAppear {
            PostAnalytics.shared.record(.open, for: event)
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
    
    // MARK: - RSVP (Going / Maybe / Can't Go)

    /// Whether the current user answered Going.
    private var isGoing: Bool { myRSVP == .going }

    /// Three equal-width buttons. The chosen one turns solid orange; tapping it again
    /// clears the answer.
    private var rsvpButtons: some View {
        HStack(spacing: 10) {
            rsvpButton(.going, title: "Going") {
                Image(systemName: "hand.raised.fill")
            }
            rsvpButton(.maybe, title: "Maybe") {
                // SF Symbols has no thinking face, so this uses the emoji.
                Text("🤔")
            }
            rsvpButton(.notGoing, title: "Can't Go") {
                Text("😞")
            }
        }
        .disabled(isUpdatingGoing)
        .sensoryFeedback(.selection, trigger: myRSVP)
    }

    private func rsvpButton(
        _ status: EventRSVPStatus,
        title: String,
        @ViewBuilder icon: () -> some View
    ) -> some View {
        let isSelected = myRSVP == status
        return Button {
            setRSVP(status)
        } label: {
            VStack(spacing: 4) {
                icon()
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.headline)
            .foregroundStyle(isSelected ? .white : Color.brandOrange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.brandOrange : Color.brandOrange.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.brandOrange, lineWidth: isSelected ? 0 : 1.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Overlapping profile photos of the first few attendees plus a count; tap to see
    /// the full list.
    private var whosGoingRow: some View {
        Button {
            showAttendees = true
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: -10) {
                    ForEach(Array(attendeeIDs.prefix(5)), id: \.self) { id in
                        EventAttendeeAvatar(profile: profiles.findUser(byID: id), size: 32)
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    }
                }

                Text(goingSummary)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "You and 3 others are going", "Maya Chen is going", "12 went", …
    private var goingSummary: String {
        let verb = isEventOver ? "went" : (attendeeIDs.count == 1 && !isGoing ? "is going" : "are going")
        let others = attendeeIDs.filter { $0 != CloudKitManager.shared.currentAttendeeID }
        if isGoing {
            if others.isEmpty { return isEventOver ? "You went" : "You're going" }
            return "You and \(others.count) \(others.count == 1 ? "other" : "others") \(verb)"
        }
        if attendeeIDs.count == 1, let name = profiles.findUser(byID: attendeeIDs[0])?.displayName {
            return "\(name) \(verb)"
        }
        return "\(attendeeIDs.count) \(isEventOver ? "went" : "going")"
    }

    /// Loads who's going and the current user's own answer.
    private func loadAttendees() async {
        guard let rsvps = try? await CloudKitManager.shared.fetchEventRSVPs(eventID: event.id) else { return }
        attendeeIDs = rsvps.filter { $0.status == .going }.map(\.userID)
        if let me = CloudKitManager.shared.currentAttendeeID {
            myRSVP = rsvps.first { $0.userID == me }?.status
        }
    }

    /// Sets the current user's RSVP to `status`, or clears it if that was already their
    /// answer. Updates the UI immediately, then rolls back if the CloudKit write fails
    /// (e.g. not signed in to iCloud, or offline).
    private func setRSVP(_ status: EventRSVPStatus) {
        guard !isUpdatingGoing else { return }
        guard let me = CloudKitManager.shared.currentAttendeeID else {
            goingErrorMessage = "Sign in to iCloud in Settings to RSVP to events."
            return
        }
        let newRSVP: EventRSVPStatus? = myRSVP == status ? nil : status
        let previousRSVP = myRSVP
        let previousIDs = attendeeIDs

        withAnimation(.snappy) {
            myRSVP = newRSVP
            if newRSVP == .going {
                if !attendeeIDs.contains(me) { attendeeIDs.append(me) }
            } else {
                attendeeIDs.removeAll { $0 == me }
            }
        }

        isUpdatingGoing = true
        Task {
            defer { isUpdatingGoing = false }
            do {
                try await CloudKitManager.shared.setRSVP(newRSVP, eventID: event.id)
            } catch {
                print("❌ [Event] Couldn't update RSVP: \(error)")
                withAnimation(.snappy) {
                    myRSVP = previousRSVP
                    attendeeIDs = previousIDs
                }
                goingErrorMessage = "Couldn't update your RSVP. Check your connection and try again."
            }
        }
    }

    /// A full-width link button, shown only when `rawURL` holds a real link. Trims first so
    /// a whitespace-only value (e.g. an empty string round-tripped through CloudKit)
    /// doesn't surface a button, and assumes https when the poster typed a bare domain
    /// ("example.com"), which `Link` otherwise can't open.
    @ViewBuilder
    private func linkButton(_ rawURL: String?, title: String, icon: String) -> some View {
        if let trimmed = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
           let url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed) {
            Link(destination: url) {
                HStack {
                    Image(systemName: icon)
                    Text(title)
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.brandOrange)
                .clipShape(RoundedRectangle(cornerRadius: 12))
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

// MARK: - Event Attendees

/// A circular profile photo for an attendee, or a person icon when they have none
/// (or aren't in the directory).
struct EventAttendeeAvatar: View {
    let profile: DirectoryUser?
    var size: CGFloat = 44

    var body: some View {
        if let data = profile?.profileImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.utBrandOrange.opacity(0.3))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(Color.utBrandOrange)
                }
        }
    }
}

/// Everyone going to an event. Attendees in the directory link to their profile;
/// the rest are collapsed into one "Guest User" row (same approach as `WhoLikedSheet`).
struct EventAttendeesSheet: View {
    let attendeeIDs: [String]
    let isEventOver: Bool
    @ObservedObject private var profiles = UserProfileManager.shared

    private var knownAttendees: [DirectoryUser] {
        attendeeIDs.compactMap { profiles.findUser(byID: $0) }
    }

    private var guestCount: Int { attendeeIDs.count - knownAttendees.count }

    var body: some View {
        NavigationStack {
            Group {
                if attendeeIDs.isEmpty {
                    ContentUnavailableView(
                        "No One Yet",
                        systemImage: "person.2",
                        description: Text("Be the first to say you're going.")
                    )
                } else {
                    List {
                        ForEach(knownAttendees) { person in
                            NavigationLink {
                                PersonProfileView(name: person.fullName)
                            } label: {
                                HStack(spacing: 12) {
                                    EventAttendeeAvatar(profile: person)
                                    Text(person.displayName)
                                        .font(.headline)
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        if guestCount > 0 {
                            HStack(spacing: 12) {
                                EventAttendeeAvatar(profile: nil)
                                Text(guestCount > 1 ? "Guest User x\(guestCount)" : "Guest User")
                                    .font(.headline)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle(isEventOver ? "\(attendeeIDs.count) Went" : "\(attendeeIDs.count) Going")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(.systemBackground))
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
                // Drawn as an overlay on a screen-sized Color so the filled image's
                // oversize layout bounds don't inflate the ZStack and push the close
                // button off screen (which left no way to dismiss the cover).
                Color.clear
                    .overlay {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 40)
                    }
                    .overlay(Color.black.opacity(0.35))
                    .clipped()
                    .ignoresSafeArea()

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
        // Tap anywhere to close, matching ProfilePhotoZoomOverlay, so there's always a way out.
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
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
        s.eventRSVPURL = "https://example.com/rsvp"
        s.eventWebsiteURL = "https://example.com"

        let calendar = Calendar.current
        let evening = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()

        if kind.usesShowings {
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
        case .screening:
            s.eventLineup = "Sundown"
        case .speaker:
            s.eventLineup = "Dana Whitfield, Omar Castillo"
        default:
            break
        }
        return s
    }

    private static func sampleEventTitle(_ kind: EventCategoryKind) -> String {
        switch kind {
        case .infoSession:         return "New Member Info Session"
        case .concert:             return "Spring Showcase Concert"
        case .actorShowcase:       return "Actor Showcase Night"
        case .theatrePerformance:  return "Our Town"
        case .filmFestival:        return "Longhorn Film Festival"
        case .screening:           return "Sundown Premiere Screening"
        case .artistMixer:         return "Artist Mixer"
        case .speaker:             return "Guest Speaker Talk"
        }
    }
}

// MARK: - Card Previews (one per category, all fields filled)

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

#Preview("Detail • Info Session") { EventDetailView(event: .sampleEvent(.infoSession)) }
#Preview("Detail • Concert") { EventDetailView(event: .sampleEvent(.concert)) }
#Preview("Detail • Actor Showcase") { EventDetailView(event: .sampleEvent(.actorShowcase)) }
#Preview("Detail • Theatre Performance") { EventDetailView(event: .sampleEvent(.theatrePerformance)) }
#Preview("Detail • Film Festival") { EventDetailView(event: .sampleEvent(.filmFestival)) }
#Preview("Detail • Artist Mixer") { EventDetailView(event: .sampleEvent(.artistMixer)) }
#Preview("Detail • Speaker") { EventDetailView(event: .sampleEvent(.speaker)) }
#endif
