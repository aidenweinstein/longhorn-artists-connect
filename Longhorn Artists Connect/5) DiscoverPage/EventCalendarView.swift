//
//  EventCalendarView.swift
//  Longhorn Artists Connect
//
//  A full page of every dated event laid out as a month calendar, opened from the
//  calendar button in the Discover toolbar. The days are ruled into a grid, and each day
//  box holds the poster of the event running that day; days with several events show them
//  layered like a pile of paper. Posters keep their own aspect ratio rather than being
//  cropped. An event hosted by a known organization is ringed in that org's color
//  (see `OrgTheme`). The toolbar filter narrows the month to any of the event categories
//  a post can be filed under (see `EventCategoryKind`).
//

import SwiftUI

// MARK: - Event Calendar Page

struct EventCalendarView: View {
    /// Every event to place on the calendar. Undated events are skipped (there's no day
    /// to put them on); the Discover list feed still shows them.
    let events: [Submission]

    /// Any date inside the month currently on screen.
    @State private var anchor = Date()
    /// The day whose events are listed under the grid.
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    /// The event whose detail sheet is open, presented from this page.
    @State private var selectedEvent: Submission?
    /// Categories the calendar is narrowed to, picked from the filter menu. Empty means
    /// no filter is on and every category shows.
    @State private var categoryFilter: Set<EventCategoryKind> = []
    /// Whether the founding story is open — see `foundingDay`.
    @State private var showFoundingStory = false

    /// Known organizations, so an event's host can be matched to the org whose color
    /// surrounds its poster.
    @ObservedObject private var orgStore = OrganizationStore.shared

    private var calendar: Calendar { Calendar.current }

    // MARK: - Layout

    /// Inset of the grid from the page edges.
    private static let horizontalPadding: CGFloat = 8
    /// Gap between day boxes, both directions. Zero so neighboring boxes share an edge
    /// and their hairline borders line up into one continuous grid.
    private static let cellSpacing: CGFloat = 0
    /// Thickness of the lines ruling the grid. Each box strokes its own border centered
    /// on its bounds, so two neighbors' halves stack into a single line of this width.
    private static let gridLineWidth: CGFloat = 0.5
    /// Height reserved for the day number above each day's poster.
    private static let dayNumberHeight: CGFloat = 20
    /// Extra room at the bottom of a box for the tilted sheets peeking out of a pile.
    private static let pileSlack: CGFloat = 12
    /// How many posters a pile shows before it stops adding sheets.
    private static let pileDepth = 3
    /// The day the five founders first got into a group chat together. Holding it down
    /// opens the founding story (see `FoundingStoryView`); every other day ignores the
    /// hold.
    private static let foundingDay = DateComponents(year: 2025, month: 9, day: 10)
    /// How long that day has to be held before the story opens — long enough that it
    /// can't be reached by accident while scrubbing the grid.
    private static let foundingHoldDuration: Double = 3
    /// Tilt of each sheet in a pile, front to back — the front poster sits square and
    /// the ones behind fan out so the stack reads as paper.
    private static let pileTilts: [Double] = [0, 6.5, -6]
    /// How far each sheet behind the front one is nudged down and right.
    private static let pileOffsets: [CGFloat] = [0, 3, 6]

    /// Day-box and poster sizes derived from the page width, so posters fill each box on
    /// every screen size rather than being pinned to one phone's dimensions.
    private struct Metrics {
        let flyerWidth: CGFloat
        let cellHeight: CGFloat

        init(containerWidth: CGFloat) {
            let gutters = EventCalendarView.cellSpacing * 6
            let usable = max(containerWidth - EventCalendarView.horizontalPadding * 2 - gutters, 0)
            let columnWidth = usable / 7
            // The poster fills its box, less a margin the tilted sheets of a pile can
            // fan into without spilling over a neighboring day.
            flyerWidth = max(columnWidth - 10, 12)
            cellHeight = EventCalendarView.dayNumberHeight
                + 3
                + flyerWidth * 1.5
                + EventCalendarView.pileSlack
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.cellSpacing), count: 7)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let metrics = Metrics(containerWidth: proxy.size.width)
                // Built once per layout pass and handed down, not recomputed per cell.
                let index = eventsByDay

                ScrollView {
                    VStack(spacing: 12) {
                        monthHeader
                        weekdayHeader

                        LazyVGrid(columns: columns, spacing: Self.cellSpacing) {
                            ForEach(displayedDays, id: \.timeIntervalSince1970) { day in
                                dayCell(day, dayEvents: index[day] ?? [], metrics: metrics)
                            }
                        }
                        .padding(.horizontal, Self.horizontalPadding)

                        selectedDayList(index[selectedDay] ?? [])
                    }
                    .padding(.vertical, 10)
                }
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") {
                        let today = calendar.startOfDay(for: Date())
                        anchor = today
                        selectedDay = today
                    }
                    .foregroundStyle(Color.brandOrange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    categoryFilterMenu
                }
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailView(event: event)
            }
        }
        // Hung on the stack rather than beside the event sheet: two `.sheet` modifiers
        // on the same view don't both work.
        .sheet(isPresented: $showFoundingStory) {
            FoundingStoryView()
        }
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Header

    /// "September 2026" with a step arrow on each side.
    private var monthHeader: some View {
        HStack {
            Button { stepMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(Color.brandOrange)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            Spacer()

            Text(anchor.formatted(.dateTime.month(.wide).year()))
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            Button { stepMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(Color.brandOrange)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, 16)
    }

    /// The single-letter weekday row above the grid, honoring the locale's first weekday.
    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
    }

    // MARK: - Category Filter

    /// Narrows the calendar to one or more of the event categories a post can be filed
    /// under. Nothing checked means everything shows; the icon fills in while a filter
    /// is on so it's clear the month isn't showing all of its events.
    private var categoryFilterMenu: some View {
        Menu {
            ForEach(EventCategoryKind.allCases, id: \.self) { kind in
                Toggle(isOn: filterBinding(for: kind)) {
                    Label(kind.rawValue, systemImage: kind.accentIcon)
                }
            }

            if !categoryFilter.isEmpty {
                Section {
                    Button("Show All Events", systemImage: "arrow.counterclockwise") {
                        categoryFilter.removeAll()
                    }
                }
            }
        } label: {
            Image(systemName: categoryFilter.isEmpty
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
                .font(.headline)
                .foregroundStyle(Color.brandOrange)
        }
        // Keeps the categories in their declared order rather than letting the menu
        // reorder them by proximity to the button.
        .menuOrder(.fixed)
        .accessibilityLabel("Filter by event type")
    }

    private func filterBinding(for kind: EventCategoryKind) -> Binding<Bool> {
        Binding(
            get: { categoryFilter.contains(kind) },
            set: { isOn in
                if isOn {
                    categoryFilter.insert(kind)
                } else {
                    categoryFilter.remove(kind)
                }
            }
        )
    }

    /// The events the calendar is currently showing. An event whose category isn't one
    /// of the known kinds drops out while a filter is on, since it can't match a
    /// checked type.
    private var filteredEvents: [Submission] {
        guard !categoryFilter.isEmpty else { return events }
        return events.filter { event in
            guard let kind = EventCategoryKind(rawValue: event.genres.first ?? "") else {
                return false
            }
            return categoryFilter.contains(kind)
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        guard first > 0, first < symbols.count else { return symbols }
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Moves the calendar a month forward or back, snapping the listed day into the new
    /// month so the list under the grid always matches what's on screen.
    private func stepMonth(by amount: Int) {
        guard let moved = calendar.date(byAdding: .month, value: amount, to: anchor) else { return }
        anchor = moved
        if !calendar.isDate(selectedDay, equalTo: moved, toGranularity: .month) {
            selectedDay = calendar.startOfDay(for: moved)
        }
    }

    // MARK: - Day Index

    /// Events keyed by every day they run on, so a multi-day event (a recruitment
    /// schedule, a festival) appears on each of its days rather than only its start.
    /// Spans are capped at 60 days so a mistyped end date can't balloon the index.
    private var eventsByDay: [Date: [Submission]] {
        var map: [Date: [Submission]] = [:]
        for event in filteredEvents {
            // A multi-showing run (Theatre Performance) lands on exactly the days it
            // plays: the span between its first and last performance can include dark
            // nights, which the start…end walk below would wrongly fill in.
            let showingDays = Set((event.eventShowings ?? []).map { calendar.startOfDay(for: $0.start) })
            if !showingDays.isEmpty {
                for day in showingDays {
                    map[day, default: []].append(event)
                }
                continue
            }

            guard let start = event.eventStartDate else { continue }
            let firstDay = calendar.startOfDay(for: start)
            let lastDay = calendar.startOfDay(for: event.eventEndDate ?? start)
            var day = firstDay
            var placed = 0
            while day <= lastDay, placed < 60 {
                map[day, default: []].append(event)
                placed += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        // Earliest start first within a day, so the pile's top sheet is the day's first
        // event and the list below reads in running order.
        for (day, dayEvents) in map {
            map[day] = dayEvents.sorted {
                ($0.eventStartDate ?? .distantPast) < ($1.eventStartDate ?? .distantPast)
            }
        }
        return map
    }

    /// The anchor month, padded out to whole weeks so the grid is rectangular.
    private var displayedDays: [Date] {
        guard let month = calendar.dateInterval(of: .month, for: anchor),
              let gridStart = calendar.dateInterval(of: .weekOfMonth, for: month.start)?.start
        else { return [] }

        var days: [Date] = []
        var day = gridStart
        // Whole weeks, from the first row through the row holding the month's last day.
        while day < month.end || days.count % 7 != 0 {
            days.append(day)
            guard days.count < 42, let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    // MARK: - Day Box

    /// One day box: its number, then the poster(s) of the events running that day.
    private func dayCell(_ day: Date, dayEvents: [Submission], metrics: Metrics) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        // The grid pads with days from the neighboring months; dim those.
        let isOutsideMonth = !calendar.isDate(day, equalTo: anchor, toGranularity: .month)

        return Button {
            selectedDay = calendar.startOfDay(for: day)
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .foregroundStyle(dayNumberColor(isToday: isToday, isOutsideMonth: isOutsideMonth))
                    .frame(width: Self.dayNumberHeight, height: Self.dayNumberHeight)
                    .background {
                        if isToday { Circle().fill(Color.brandOrange) }
                    }

                flyerPile(dayEvents, width: metrics.flyerWidth)

                // The only hint that this box does anything.
                if isFoundingDay(day) {
                    Image(systemName: "questionmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.brandOrange)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.cellHeight, alignment: .top)
            .padding(.top, 4)
            .background(isSelected ? Color.brandOrange.opacity(0.12) : .clear)
            // The lines ruling the calendar. Every box draws all four of its edges, so
            // the shared edges of neighboring boxes add up to one grid over the month.
            .overlay {
                Rectangle()
                    .stroke(Color(UIColor.separator), lineWidth: Self.gridLineWidth)
            }
            // Selection sits just inside the ruling so it reads as a filled-in day
            // rather than a thicker grid line.
            .overlay {
                if isSelected {
                    Rectangle()
                        .strokeBorder(Color.brandOrange, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Simultaneous because the box is a Button: a plain `.onLongPressGesture` on a
        // view wrapping a Button never fires — the button claims the touch. Hung on
        // every box rather than only the founding day so the cells stay identical to
        // SwiftUI; the hold is a no-op on any other date.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: Self.foundingHoldDuration)
                .onEnded { _ in
                    guard isFoundingDay(day) else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showFoundingStory = true
                }
        )
        .accessibilityLabel(dayAccessibilityLabel(day, count: dayEvents.count))
    }

    /// Whether this box is September 10, 2025 — the day that opens the founding story.
    private func isFoundingDay(_ day: Date) -> Bool {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return parts.year == Self.foundingDay.year
            && parts.month == Self.foundingDay.month
            && parts.day == Self.foundingDay.day
    }

    /// The day's poster(s). A single event shows its poster on its own; several are
    /// layered like a pile of paper — each sheet behind the last, nudged down and right
    /// and tilted slightly — so a busy day reads as a stack at a glance.
    @ViewBuilder
    private func flyerPile(_ dayEvents: [Submission], width: CGFloat) -> some View {
        if !dayEvents.isEmpty {
            let shown = Array(dayEvents.prefix(Self.pileDepth).enumerated())
            ZStack {
                // Drawn back to front so the day's first event ends up on top.
                ForEach(shown.reversed(), id: \.element.id) { depth, event in
                    flyerChip(event, width: width, ringWidth: 1.5)
                        // A drop shadow per sheet is what sells the stack as physical
                        // paper rather than flat overlapping rectangles.
                        .shadow(color: .black.opacity(0.22), radius: 1.5, x: 0.5, y: 1)
                        .rotationEffect(.degrees(Self.pileTilts[depth]))
                        .offset(x: Self.pileOffsets[depth], y: Self.pileOffsets[depth])
                }
            }
        }
    }

    /// White on today's filled circle, faded for a neighboring month's padding days,
    /// otherwise the normal text color.
    private func dayNumberColor(isToday: Bool, isOutsideMonth: Bool) -> Color {
        if isToday { return .white }
        return isOutsideMonth ? Color.secondary.opacity(0.5) : .primary
    }

    private func dayAccessibilityLabel(_ day: Date, count: Int) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        switch count {
        case 0:  return date
        case 1:  return "\(date), 1 event"
        default: return "\(date), \(count) events"
        }
    }

    // MARK: - Selected Day List

    /// The tappable list of the selected day's events, under the grid. This is how a
    /// pile gets unstacked — every event on that day is listed out in running order.
    @ViewBuilder
    private func selectedDayList(_ dayEvents: [Submission]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text(selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.headline)
                .padding(.horizontal, 16)

            if dayEvents.isEmpty {
                // Says so when the day is only empty because of the filter, rather than
                // claiming the day has nothing on it.
                Text(categoryFilter.isEmpty
                     ? "No events on this day."
                     : "No events of these types on this day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                ForEach(dayEvents) { event in
                    Button {
                        SeenContentTracker.shared.markSeen(event.id)
                        selectedEvent = event
                    } label: {
                        eventRow(event)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A poster + title/time/host row for one of the selected day's events.
    private func eventRow(_ event: Submission) -> some View {
        HStack(alignment: .top, spacing: 12) {
            flyerChip(event, width: 58, ringWidth: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let timeText = timeText(for: event) {
                    Text(timeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // The host, tinted in the org's color when it names a known org — the
                // same color ringing the poster.
                if !event.eventHost.isEmpty {
                    Text(event.eventHost)
                        .font(.caption)
                        .foregroundStyle(hostOrgColor(for: event) ?? .secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }

    /// "7:30pm" for a timed event; nil for a date-range category that carries no time.
    ///
    /// For a run of showings this is the time of the performance on the day being listed,
    /// not the run's opening night.
    private func timeText(for event: Submission) -> String? {
        let showingStart = (event.eventShowings ?? [])
            .first { calendar.isDate($0.start, inSameDayAs: selectedDay) }?
            .start
        guard let start = showingStart ?? event.eventStartDate else { return nil }
        let kind = EventCategoryKind(rawValue: event.genres.first ?? "")
        guard kind?.usesDateRange != true else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: start).lowercased()
    }

    // MARK: - Poster + Org Color

    /// An event's poster, whole and at its own aspect ratio, surrounded by its host
    /// organization's color. Events without a known org host get no ring.
    private func flyerChip(_ event: Submission, width: CGFloat, ringWidth: CGFloat) -> some View {
        let ringColor = hostOrgColor(for: event)
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let poster = event.thumbnailData.flatMap { UIImage(data: $0) }
        let size = Self.flyerSize(for: poster, width: width)

        return Group {
            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.22))
                    .overlay(
                        Image(systemName: "calendar")
                            .font(.system(size: width * 0.4))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay {
            if let ringColor {
                shape.stroke(ringColor, lineWidth: ringWidth)
            }
        }
        // A hairline outside the ring so an org color matching the page background
        // (Spark's white, Black Lens' black) still reads as a border. It also separates
        // the sheets of a pile from each other.
        .overlay {
            shape
                .inset(by: -(ringColor == nil ? 0 : ringWidth) / 2)
                .stroke(Color(UIColor.separator), lineWidth: 0.5)
        }
        // The poster keeps its own shape, but every chip takes up the same slot, so day
        // boxes stay a uniform height and the sheets of a pile hang from the same line.
        .frame(width: width, height: width * 1.5, alignment: .top)
    }

    /// The on-screen size of a poster: its own aspect ratio scaled to fit the
    /// `width` × `width * 1.5` slot, so the whole flyer shows instead of being cropped
    /// to portrait. A poster that's missing or unreadable fills the slot.
    private static func flyerSize(for poster: UIImage?, width: CGFloat) -> CGSize {
        let maxHeight = width * 1.5
        guard let poster, poster.size.width > 0, poster.size.height > 0 else {
            return CGSize(width: width, height: maxHeight)
        }
        let aspect = poster.size.width / poster.size.height
        let height = width / aspect
        guard height > maxHeight else { return CGSize(width: width, height: height) }
        // Taller than the slot (a long banner): pin the height and narrow the width.
        return CGSize(width: maxHeight * aspect, height: maxHeight)
    }

    /// The color of the organization hosting this event, or nil when the host doesn't
    /// name a known org (so no ring is drawn). Matches `EventDetailView`'s host lookup.
    private func hostOrgColor(for event: Submission) -> Color? {
        let host = event.eventHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return nil }
        guard let org = orgStore.organizations.first(where: {
            $0.name.caseInsensitiveCompare(host) == .orderedSame
        }) else { return nil }
        return org.theme.background
    }
}

// MARK: - Founding Story

/// The page behind a three-second hold on September 10, 2025: the group chat where the
/// five founders introduced themselves, and what came of it.
private struct FoundingStoryView: View {
    private static let story = """
    Longhorn Artists Connect was founded by five UT students: Elliott Saiontz, Aiden \
    Weinstein, Quinn Graves, Clayton Laney, and Tim Robertson. All sophomores at the \
    time, they saw a problem with the creative departments on campus: they were all \
    disconnected. Actors and directors and musicians and writers... they never met one \
    another. The young five decided to change that, and here we are now.
    """

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image("Founding Conversation")
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(UIColor.separator), lineWidth: 0.5)
                        }
                        .accessibilityLabel("The group chat where the five founders first introduced themselves.")

                    Text(Self.story)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Secret Page 2/5")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Previews

#if DEBUG

private extension Submission {
    /// A dated sample event for the calendar previews: `dayOffset` days from today,
    /// hosted by `host` (match an org name to exercise the org-color ring), with a
    /// solid-color stand-in poster at `flyerSize`'s proportions.
    static func sampleCalendarEvent(
        title: String,
        host: String,
        dayOffset: Int,
        hour: Int = 19,
        flyer: UIColor,
        flyerSize: CGSize = CGSize(width: 80, height: 120),
        category: EventCategoryKind = .concert,
        spanDays: Int = 0
    ) -> Submission {
        var s = Submission(
            id: UUID(),
            type: .event,
            title: title,
            details: "",
            isApproved: true,
            submittedBy: "Aiden Weinstein"
        )
        s.eventHost = host
        s.genres = [category.rawValue]
        s.logline = "A sample event used to lay out the calendar."

        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        s.eventStartDate = calendar.date(bySettingHour: hour, minute: 30, second: 0, of: day)
        if spanDays > 0 {
            s.eventEndDate = calendar.date(byAdding: .day, value: spanDays, to: day)
        }

        // A flat color block stands in for the poster so the pile and org ring are easy
        // to read.
        let renderer = UIGraphicsImageRenderer(size: flyerSize)
        let image = renderer.image { context in
            flyer.setFill()
            context.fill(CGRect(origin: .zero, size: flyerSize))
        }
        s.thumbnailData = image.jpegData(compressionQuality: 0.8)
        return s
    }

    /// A spread of events across the current month: single-event days, days with a pile
    /// of two and of four, a multi-day span, a host that isn't a known org, posters
    /// shaped as portrait, square, landscape, and a tall banner, and a mix of categories
    /// for the filter menu to sort through.
    static var sampleCalendarEvents: [Submission] {
        [
            .sampleCalendarEvent(title: "Spring Showcase", host: "Collective",
                                 dayOffset: 0, flyer: .systemTeal,
                                 category: .actorShowcase),
            .sampleCalendarEvent(title: "Pilot Screening", host: "Incubator",
                                 dayOffset: 0, hour: 21, flyer: .systemPink,
                                 flyerSize: CGSize(width: 100, height: 100),
                                 category: .filmFestival),
            .sampleCalendarEvent(title: "Open Mic", host: "Paradise Music Group",
                                 dayOffset: 3, flyer: .systemIndigo,
                                 category: .concert),
            .sampleCalendarEvent(title: "Photo Walk", host: "Spark Magazine",
                                 dayOffset: 3, hour: 11, flyer: .white,
                                 flyerSize: CGSize(width: 160, height: 90),
                                 category: .infoSession),
            .sampleCalendarEvent(title: "Crew Call", host: "DKA",
                                 dayOffset: 3, hour: 14, flyer: .systemOrange,
                                 category: .infoSession),
            .sampleCalendarEvent(title: "Table Read", host: "Black Lens",
                                 dayOffset: 3, hour: 16, flyer: .darkGray,
                                 category: .speaker),
            .sampleCalendarEvent(title: "Short Film Night", host: "DKA",
                                 dayOffset: 6, flyer: .systemOrange,
                                 flyerSize: CGSize(width: 60, height: 200),
                                 category: .filmFestival),
            .sampleCalendarEvent(title: "Indie Mixer", host: "Some Unlisted Host",
                                 dayOffset: 8, flyer: .systemGreen,
                                 category: .artistMixer),
            .sampleCalendarEvent(title: "Fall Recruitment", host: "Black Lens",
                                 dayOffset: -2, flyer: .brown,
                                 category: .recruitmentSchedule, spanDays: 5),
            .sampleCalendarEvent(title: "Late Night Taping", host: "Longhorn Late Night",
                                 dayOffset: 12, hour: 23, flyer: .systemBlue,
                                 category: .concert)
        ]
    }
}

#Preview("Calendar • No Events") {
    EventCalendarView(events: [])
}

#endif
