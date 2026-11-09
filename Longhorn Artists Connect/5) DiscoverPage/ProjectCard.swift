//
//  ProjectCard.swift
//  Longhorn Artists Connect
//
//  Created by Aiden Weinstein on 2/12/26.
//
//  This file contains UI components for displaying projects in the Discover feed
//  and the detail view for upcoming projects that need cast/crew.

import SwiftUI
import AVKit
import CloudKit
import QuickLook

// Lightweight identifiable wrapper so a tapped credit name can drive a sheet
struct CreditedPerson: Identifiable {
    let id = UUID()
    let name: String
}

/// A credited person's name, shared across the detail cards. Registered Nexus
/// members get school-colored text (UT orange, Michigan blue, USC red, NYU purple,
/// Cal Poly green — keyed to their school) and tap through to their portfolio;
/// everyone else is shown as plain grey, non-interactive text.
struct CreditNameView: View {
    let name: String
    @Binding var selection: CreditedPerson?
    @ObservedObject private var profileManager = UserProfileManager.shared

    var body: some View {
        if let theme = chipTheme {
            Button {
                selection = CreditedPerson(name: name)
            } label: {
                Text(name)
                    // Same size as non-member names (`.body`) so all credits match.
                    .font(.body)
                    // School color as plain text — no bubble. `bubble` is each school's
                    // primary color (the requested per-school text color).
                    .foregroundStyle(theme.bubble)
                    .multilineTextAlignment(.trailing)
            }
            .buttonStyle(.plain)
        } else {
            Text(name)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    /// The bubble theme for this credited person, or `nil` if they aren't a Nexus
    /// member (unrecognized names stay plain grey). A directory member is themed by
    /// their school; a locally-created profile with no school gets the brand default.
    private var chipTheme: SchoolTheme? {
        if let user = profileManager.allUsers.first(where: { $0.fullName == name }) {
            return SchoolTheme.forSchool(user.school)
        }
        let createdProfiles = UserDefaults.standard.stringArray(forKey: "createdUserProfiles") ?? []
        if createdProfiles.contains(name) { return .nexusDefault }
        return nil
    }
}

// MARK: - Project Card Component (for Discover Feed)

struct ProjectCard: View {
    let project: Submission
    /// For the org profile picture atop the shoot-date box (Org Projects).
    @ObservedObject private var orgStore = OrganizationStore.shared

    /// The organization this project credits as its studio, if the stored studio names
    /// one in the directory (case-insensitive, like the film detail's studio lookup).
    private var studioOrganization: Organization? {
        let name = project.studio.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return orgStore.organizations.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The course code ("RTF 304D") when the studio is a production class.
    private var classCode: String? {
        ProductionClassCatalog.code(for: project.studio)
    }

    /// The poster's bounding box (2:3), the same slot the event card gives its flyer.
    /// The poster is fitted inside it at its own aspect ratio. Together with the
    /// shoot-date box, the left cluster fills roughly half the card width.
    private let posterWidth: CGFloat = 110
    private let posterHeight: CGFloat = 165

    private var needsCast: Bool { !project.castNeeded.isEmpty }
    private var needsCrew: Bool { !project.crewNeeded.isEmpty }

    /// Capsule label based on which roles are still open.
    private var teamStatusText: String {
        switch (needsCast, needsCrew) {
        case (true, true):   return "Cast & Crew Needed"
        case (true, false):  return "Cast Needed"
        case (false, true):  return "Crew Needed"
        case (false, false): return "Cast & Crew Assembled"
        }
    }

    /// Orange while roles are open, grey once everything is assembled.
    private var teamStatusColor: Color {
        (needsCast || needsCrew) ? Color.brandOrange : Color.secondary
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Boxed shoot dates to the left of the poster, centered vertically against
                // it — the same treatment the event card gives its date. Pinned to the
                // poster's height so a tall info column can't drag the box downward.
                if let shootSchedule {
                    shootDateBox(shootSchedule)
                        .frame(minHeight: posterHeight, alignment: .center)
                }

                // Poster at its original aspect ratio (fit within the slot rather than
                // cropped to fill it). Square corners, matching the event card.
                if let thumbnailData = project.thumbnailData,
                   let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: posterWidth, maxHeight: posterHeight)
                        .frame(width: posterWidth, alignment: .top)
                } else {
                    ZStack {
                        Color.secondary.opacity(0.1)
                        Image(systemName: "photo")
                            .imageScale(.large)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: posterWidth, height: posterHeight)
                }
                
                // Project info on right
                VStack(alignment: .leading, spacing: 4) {
                    // Project title heading
                    Text(project.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    projectInfo
                }
                .frame(maxWidth: .infinity, maxHeight: posterHeight, alignment: .top)
            }
            .padding(.vertical, 16)
        }
    }
    
    private var projectType: ProjectType? { ProjectType(rawValue: project.projectType) }

    // MARK: - Shoot Date Box (left of the card)

    /// Only a Cast & Crew Call (or a legacy project with no type) shows shoot dates;
    /// scripts and in-development/post posts describe themselves differently.
    private var showsShootDates: Bool {
        switch projectType {
        case .script, .inDevelopment, .inPostProduction: return false
        default: return true
        }
    }

    /// The shoot schedule parsed from the stored text, or `nil` when there is none or it
    /// doesn't parse (in which case the info column falls back to showing the raw text).
    private var shootSchedule: ShootSchedule.Parsed? {
        showsShootDates ? project.shootSchedule : nil
    }

    /// One month of a multi-day shoot, for the box: "JUN" over "15, 16, 20".
    private struct MonthGroup: Identifiable {
        let id: String
        let month: String
        var days: String
    }

    /// `days` grouped under their month, in order. Each month's day numbers are joined
    /// with commas so the line wraps naturally inside the narrow box.
    private func monthGroups(_ days: [Date]) -> [MonthGroup] {
        let calendar = Calendar.current
        var groups: [MonthGroup] = []
        for day in days {
            let key = "\(calendar.component(.year, from: day))-\(calendar.component(.month, from: day))"
            let dayNumber = String(calendar.component(.day, from: day))
            if let index = groups.firstIndex(where: { $0.id == key }) {
                groups[index].days += ", " + dayNumber
            } else {
                groups.append(MonthGroup(id: key, month: day.formatted(.dateTime.month(.abbreviated)), days: dayNumber))
            }
        }
        return groups
    }

    /// A boxed shoot-date summary shown to the left of the poster, topped by a camera
    /// icon — the same shape as the event card's date box. A single shoot day reads
    ///
    ///     🎥
    ///     Mon
    ///     Jun
    ///     15
    ///     7:00am
    ///
    /// and a multi-day shoot lists every day under its month ("JUN" / "15, 16, 20" /
    /// "JUL" / "2"). The box grows with the schedule rather than dropping days.
    private func shootDateBox(_ schedule: ShootSchedule.Parsed) -> some View {
        VStack(spacing: 8) {
            shootDateBoxBadge

            VStack(spacing: 2) {
                switch schedule {
                case .days(let days) where days.count > 1:
                    let groups = monthGroups(days.map(\.start))
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        Text(group.month)
                            .font(.subheadline.weight(.semibold))
                            .textCase(.uppercase)
                            .padding(.top, index == 0 ? 0 : 6)
                        Text(group.days)
                            .font(.body.weight(.bold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .days(let days):
                    if let day = days.first {
                        singleDayStack(day.start, footer: Self.timeOrYear(day))
                    }
                case .range(let start, let end):
                    singleDayStack(start, footer: Self.rangeFooter(start: start, end: end))
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

    /// What sits atop the shoot-date box: the org's profile picture for an Org Project,
    /// the course code ("RTF 304D") for a Class Project, and the camera icon otherwise.
    @ViewBuilder
    private var shootDateBoxBadge: some View {
        if let org = studioOrganization {
            OrgAvatar(imageData: org.profileImageData, diameter: 30,
                      tint: .secondary, assetName: org.profileAssetName)
        } else if let classCode {
            Text(classCode)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandOrange)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 62)
        } else {
            Image(systemName: "video.fill")
                .font(.title3)
                .foregroundStyle(Color.brandOrange)
        }
    }

    /// Weekday / month / big day number for one date, plus an optional small footer.
    @ViewBuilder
    private func singleDayStack(_ date: Date, footer: String?) -> some View {
        Text(date, format: .dateTime.weekday(.abbreviated))
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)

        Text(date, format: .dateTime.month(.abbreviated))
            .font(.subheadline.weight(.semibold))
            .textCase(.uppercase)

        Text(date, format: .dateTime.day())
            .font(.system(size: 34, weight: .bold))

        if let footer {
            Text(footer)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Under a single shoot day: its hours ("7:00am - 5:00pm"), or the year when the
    /// shoot isn't in the current year.
    private static func timeOrYear(_ day: ShootSchedule.Day) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: day.start)
        if year != calendar.component(.year, from: Date()) { return String(year) }
        return ShootSchedule.timeRangeText(day)
    }

    /// Under a legacy range's first day: "to Jul 20" for a multi-day range, the year
    /// when the range is outside the current year, or nothing.
    private static func rangeFooter(start: Date, end: Date?) -> String? {
        let calendar = Calendar.current
        if let end, !calendar.isDate(start, inSameDayAs: end) {
            return "to " + end.formatted(.dateTime.month(.abbreviated).day())
        }
        let year = calendar.component(.year, from: start)
        if year != calendar.component(.year, from: Date()) { return String(year) }
        return nil
    }

    /// The right-side description, which varies by project type.
    @ViewBuilder private var projectInfo: some View {
        switch projectType {
        case .script:
            if !scriptMeta.isEmpty {
                Text(scriptMeta)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        case .inDevelopment, .inPostProduction:
            if !project.writers.isEmpty {
                Text("Written by \(project.writers)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(inDevTeam)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        default:
            // Cast & Crew Call (and legacy projects): logline, shoot dates, role capsule.
            if !project.logline.isEmpty {
                Text(project.logline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
            }
            Spacer(minLength: 0)
            // Shoot dates normally live in the box to the left of the poster; only fall
            // back to the inline text when they were written in a form we can't parse.
            if shootSchedule == nil, !project.shootDates.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "video.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(removeYear(from: project.shootDates))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            // Always one line: the capsule shrinks the text rather than wrapping it.
            Text(teamStatusText)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(teamStatusColor)
                .clipShape(Capsule())
        }
    }

    /// "N pages · Genre · Writer" for a Script project (each part shown only if present).
    private var scriptMeta: String {
        var parts: [String] = []
        if project.scriptPageCount > 0 {
            parts.append("\(project.scriptPageCount) page\(project.scriptPageCount == 1 ? "" : "s")")
        }
        if let genre = project.genres.first, !genre.isEmpty { parts.append(genre) }
        if !project.writers.isEmpty { parts.append(project.writers) }
        return parts.joined(separator: " · ")
    }

    /// "X cast · Y crew" for an In-Development or In-Post-Production project.
    private var inDevTeam: String {
        "\(project.orderedCast.count) cast · \(project.orderedCrew.count) crew"
    }

    // Helper function to remove year from dates
    private func removeYear(from dateString: String) -> String {
        var result = dateString
        let yearPattern = try? NSRegularExpression(pattern: "\\b\\d{4}\\b", options: [])
        if let pattern = yearPattern {
            let range = NSRange(dateString.startIndex..., in: dateString)
            result = pattern.stringByReplacingMatches(in: dateString, range: range, withTemplate: "")
        }
        // Clean up extra spaces, commas, and dashes
        result = result.replacingOccurrences(of: "  ", with: " ")
        result = result.replacingOccurrences(of: ", ,", with: "")
        result = result.replacingOccurrences(of: ",,", with: "")
        result = result.replacingOccurrences(of: ", -", with: " -")
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: ", -"))
        return result
    }
}

// MARK: - Project Detail View (Full Screen Sheet)

struct UpcomingProjectDetailView: View {
    /// The post as it was when this screen opened. Read `submission` instead — Discover
    /// presents this view with `.sheet(item:)`, which hands over a snapshot that never
    /// updates, so an edit made from here would otherwise leave stale values on screen.
    private let presentedSubmission: Submission
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SubmissionStore_3_2 = .shared

    init(submission: Submission) {
        self.presentedSubmission = submission
    }

    /// The store's live copy of the post, so a save from the edit sheet shows right away.
    private var submission: Submission {
        store.currentCopy(of: presentedSubmission)
    }

    /// The open role the user tapped Apply/Audition on; drives the application sheet.
    @State private var roleApplication: RoleApplication?
    @Environment(\.openURL) private var openURL
    @State private var showEditSheet = false
    @State private var isLoading = true
    @State private var contentLoaded = false
    /// Shown only once loading has run for over 1.5s (first-launch content download).
    @State private var showSlowLoadingMessage = false
    @State private var showFullScreenPoster = false
    @State private var showScriptReader = false
    @State private var selectedPerson: CreditedPerson?
    /// The images at the top of the page: the post's slides in order, with the poster
    /// last. A project with no slides has just the poster here, exactly as before.
    /// Decoded once in `loadCarousel` rather than on every body pass.
    @State private var carouselImages: [UIImage] = []
    @State private var carouselIndex = 0


    // Check if current user is the project creator or a moderator
    private var canEditOrDelete: Bool {
        // Check if user is the creator
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        let isUserCreator = !currentUser.isEmpty && currentUser == submission.submittedBy
        
        // Check if user is the moderator (gated on the CloudKit user record ID).
        let isModeratorMode = UserDefaults.standard.bool(forKey: "isModeratorMode")
        let canUseModerator = isModeratorMode && ModeratorAccess.isModerator

        return isUserCreator || canUseModerator
    }

    /// True for accounts created via the "I'm an Industry Professional" flow (the same
    /// flag `ContentView` uses to hide the Share tab).
    @AppStorage("isIndustryProfessional") private var isIndustryProfessional: Bool = false

    /// Whether this user may join the production. Open cast/crew roles and the
    /// project's contacts are for students joining a student production: industry
    /// professionals can see that a role is open, but get no Apply/Audition button and
    /// don't see the students' personal emails and phone numbers. They can still reach
    /// the team through in-app messaging.
    private var canApplyToRoles: Bool {
        !isIndustryProfessional
    }
    
    // Generate a consistent color for each project based on title
    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(submission.title.hashValue)
        return colors[hash % colors.count]
    }
    
    var body: some View {
        // The page lives in its own NavigationStack (every caller presents it as a
        // sheet) so the Apply / Audition form can push in from the right like the
        // cast/crew screens in the submission views. The stack's bar stays hidden
        // here so the page itself looks exactly as before.
        NavigationStack {
            ZStack {
                if isLoading && !contentLoaded {
                    loadingView
                } else {
                    mainContentView
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $roleApplication) { application in
                AuditionApplicationView(
                    project: submission,
                    roleName: application.role,
                    applicationType: application.type
                )
                // Keeps the back arrow the adaptive black/white color rather than the
                // app's orange accent, matching the other pushed screens.
                .tint(.primary)
            }
        }
        .presentationDragIndicator(.hidden)
        .onAppear {
            PostAnalytics.shared.record(.open, for: submission)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    isLoading = false
                    contentLoaded = true
                }
            }
        }
        .task { loadCarousel() }
        .sheet(isPresented: $showEditSheet) {
            ProjectEditView(submission: submission) { updatedSubmission in
                store.update(updatedSubmission)
                loadCarousel()
            }
        }
        .fullScreenCover(isPresented: $showFullScreenPoster) {
            // Open whichever image the slideshow is currently showing, not always the
            // poster.
            UpcomingProjectFullScreenPosterView(
                submission: submission,
                tintColor: tintColor,
                image: carouselImages.indices.contains(carouselIndex) ? carouselImages[carouselIndex] : nil
            )
        }
        .sheet(isPresented: $showScriptReader) {
            if let scriptURL = submission.scriptURL {
                ScriptReaderView(scriptURL: scriptURL, projectTitle: submission.title)
            }
        }
        .sheet(item: $selectedPerson) { person in
            PersonProfileView(name: person.name)
                .onAppear { PostAnalytics.shared.record(.profileVisit, for: submission) }
        }
    }
    
    // MARK: - Subviews
    
    private var loadingView: some View {
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
    }
    
    private var mainContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                posterAndInfoSection
                detailsSection
                crewSection
                castSection
                contactSection
                editDeleteButtons
            }
        }
    }

    private var posterAndInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Flyer alone at the top; its blurred backdrop bleeds to the page edges.
            posterButton
                .frame(maxWidth: .infinity, alignment: .center)

            projectInfoColumn
                .padding(.horizontal)
        }
    }

    /// The poster — or, when the post has slides, a swipeable slideshow of them with the
    /// poster shown last. (The Discover feed still previews the poster on its own.)
    @ViewBuilder
    private var posterButton: some View {
        if carouselImages.count > 1 {
            VStack(spacing: 0) {
                TabView(selection: $carouselIndex) {
                    ForEach(Array(carouselImages.enumerated()), id: \.offset) { index, image in
                        Button {
                            showFullScreenPoster = true
                        } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .tag(index)
                    }
                }
                // The page dots sit beneath the slides (below) instead of over them.
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity)
                // Size the slideshow to the current image's own aspect ratio so each shows
                // at the shape it was submitted — no letterboxing.
                .aspectRatio(currentCarouselAspectRatio, contentMode: .fit)
                .animation(.default, value: carouselIndex)

                GalleryPageDots(count: carouselImages.count, currentIndex: carouselIndex)
            }
        } else {
            Button {
                showFullScreenPoster = true
            } label: {
                if let uiImage = carouselImages.first {
                    // Poster spans the full width, edge to edge (aspect ratio preserved).
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipped() // Edge-to-edge, no rounded corners
                } else {
                    ZStack {
                        Color.secondary.opacity(0.1)
                        Image(systemName: "photo")
                            .imageScale(.large)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 235, height: 353)
                    .clipped() // No rounded corners, matching the event poster
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Aspect ratio (width / height) of the slide currently on screen.
    private var currentCarouselAspectRatio: CGFloat {
        guard carouselImages.indices.contains(carouselIndex) else { return 2.0 / 3.0 }
        let size = carouselImages[carouselIndex].size
        guard size.width > 0, size.height > 0 else { return 2.0 / 3.0 }
        return size.width / size.height
    }

    /// Decodes the slides from disk and appends the poster, so the slideshow ends on the
    /// poster. With no slides this is just the poster and the page renders as before.
    private func loadCarousel() {
        var images = submission.projectSlideURLs.compactMap { UIImage(contentsOfFile: $0.path) }
        if let poster = submission.thumbnailData.flatMap(UIImage.init) {
            images.append(poster)
        }
        carouselImages = images
        if !carouselImages.indices.contains(carouselIndex) { carouselIndex = 0 }
    }

    private var projectInfoColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(submission.title)
                .font(.system(size: 28, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(2)

            if !submission.logline.isEmpty {
                Text(submission.logline)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !submission.ageRating.isEmpty {
                Text(submission.ageRating)
                    .font(.subheadline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if submission.scriptURL != nil {
                readScriptButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readScriptButton: some View {
        Button {
            showScriptReader = true
        } label: {
            HStack {
                Image(systemName: "doc.text.fill")
                Text("Read Script")
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .padding()
            .background(Color.brandOrange)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 4)
    }
    
    /// The Details rows for the shoot: one "Mon, Jun 15 • 7:00am" line per shoot day, or
    /// the stored text as written for a legacy range / loose value.
    private var shootDateLines: [String] {
        if case .days(let days)? = submission.shootSchedule {
            return days.map { "\(ShootSchedule.dayText($0.start)) • \(ShootSchedule.timeRangeText($0))" }
        }
        return submission.shootDates.isEmpty ? [] : [submission.shootDates]
    }

    /// The Details row for the organization or class behind the project: "Class" when the
    /// stored studio is a production class, "Organization" otherwise. `nil` when there's
    /// nothing to show.
    private var studioDetail: (label: String, value: String)? {
        let studio = submission.studio.trimmingCharacters(in: .whitespaces)
        guard !studio.isEmpty, studio != "Independent" else { return nil }
        let label = ProductionClassCatalog.match(studio) != nil ? "Class" : "Organization"
        return (label, studio)
    }

    /// One Details row: the detail type on the left ("Genre", "Shoot Dates", …) and its
    /// answer trailing-aligned on the right — the same shape as the event card's rows.
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

    @ViewBuilder
    private var detailsSection: some View {
        if !submission.genres.isEmpty || !submission.shootDates.isEmpty
            || studioDetail != nil {
            Divider()
                .padding(.top, 12)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Details")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 8) {
                    if !submission.genres.isEmpty {
                        detailRow("Genre") {
                            Text(submission.genres.joined(separator: ", "))
                        }
                    }

                    // Every shoot day on its own line, with its call time. Each day stays
                    // on a single line — the text shrinks rather than wrapping.
                    if !shootDateLines.isEmpty {
                        detailRow("Shoot Dates") {
                            VStack(alignment: .trailing, spacing: 2) {
                                ForEach(Array(shootDateLines.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                            }
                        }
                    }

                    if let studioDetail {
                        detailRow(studioDetail.label) {
                            Text(studioDetail.value)
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }
    
    /// Crew: the assembled team (role left, name right), then any positions still open
    /// (role left, Apply button right, in place of a name).
    @ViewBuilder
    private var crewSection: some View {
        if !submission.orderedCrew.isEmpty || !submission.crewNeeded.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Crew")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                ForEach(consolidatedCrew(submission.orderedCrew), id: \.name) { consolidated in
                    HStack(alignment: .top) {
                        Text(consolidated.roles.joined(separator: ", "))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer()

                        Button {
                            selectedPerson = CreditedPerson(name: consolidated.name)
                        } label: {
                            Text(consolidated.name)
                                .font(.body)
                                .foregroundStyle(Color.brandOrange)
                                .multilineTextAlignment(.trailing)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }

                ForEach(submission.crewNeeded, id: \.self) { role in
                    openRoleRow(role: role, description: "", buttonTitle: "Apply") {
                        apply(to: role, as: .crewApplication)
                    }
                }
            }
            .padding(.vertical)
        }
    }

    /// An open role the user is applying to, and which kind of application it is.
    /// Hashable so it can drive `navigationDestination(item:)`.
    private struct RoleApplication: Identifiable, Hashable {
        let id = UUID()
        let role: String
        let type: AuditionApplicationView.ApplicationType
    }

    /// A still-open role in the Cast or Crew list: the role (and, for cast, its
    /// description) on the left, and an Apply/Audition button on the right where a
    /// filled role shows the person's name.
    private func openRoleRow(
        role: String,
        description: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(role)
                    .font(.body)
                    .foregroundStyle(.secondary)
                if !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if canApplyToRoles {
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.brandOrange)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                // Industry professionals see that the role is unfilled, but can't apply.
                Text("Open")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    /// Starts an application for an open role. When the poster gave a sign-up link,
    /// that's where they take applications, so open it; otherwise use the in-app form.
    private func apply(to role: String, as type: AuditionApplicationView.ApplicationType) {
        if let url = auditionURL {
            openURL(url)
        } else {
            roleApplication = RoleApplication(role: role, type: type)
        }
    }

    /// The Cast & Crew Call's sign-up link, if one was given. A bare domain
    /// ("forms.gle/abc") is opened as https. Reached through each open role's
    /// Audition/Apply button (see `apply(to:as:)`) rather than a separate button.
    private var auditionURL: URL? {
        guard let trimmed = submission.projectAuditionURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed)
    }

    /// Who to reach out to. Each line is shown as written, with any email, phone number
    /// or link inside it made tappable. Hidden from industry professionals (see
    /// `canApplyToRoles`): these are students' personal contact details.
    @ViewBuilder
    private var contactSection: some View {
        if canApplyToRoles, let contacts = submission.projectContacts, !contacts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Contact")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)

                ForEach(contacts, id: \.self) { line in
                    Text(Self.linkified(line))
                        .font(.body)
                        .tint(Color.brandOrange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                }
            }
            .padding(.bottom, 8)
        }
    }

    /// `line` with every email, phone number and URL it contains turned into a link, so a
    /// contact can be reached straight from the post: an email opens a Mail compose
    /// (mailto:, which the detector produces for bare addresses), and a phone number
    /// opens a new text in Messages (sms:) rather than placing a call.
    private static func linkified(_ line: String) -> AttributedString {
        var result = AttributedString(line)
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return result }
        let nsRange = NSRange(line.startIndex..., in: line)
        for match in detector.matches(in: line, range: nsRange) {
            let url: URL?
            if match.resultType == .phoneNumber, let number = match.phoneNumber {
                url = URL(string: "sms:" + number.filter { $0.isNumber || $0 == "+" })
            } else {
                url = match.url
            }
            guard let url,
                  let stringRange = Range(match.range, in: line),
                  let lower = AttributedString.Index(stringRange.lowerBound, within: result),
                  let upper = AttributedString.Index(stringRange.upperBound, within: result)
            else { continue }
            result[lower..<upper].link = url
        }
        return result
    }

    /// Cast: the assembled cast (role left, name right), then any roles still open
    /// (role and description left, Audition button right, in place of a name).
    @ViewBuilder
    private var castSection: some View {
        if !submission.orderedCast.isEmpty || !submission.castNeeded.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cast")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                ForEach(submission.orderedCast) { entry in
                    HStack(alignment: .center) {
                        Text(entry.role)
                            .font(.body)
                            .foregroundStyle(.secondary)
                        
                        Spacer()

                        Button {
                            selectedPerson = CreditedPerson(name: entry.name)
                        } label: {
                            Text(entry.name)
                                .font(.body)
                                .foregroundStyle(Color.brandOrange)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }

                ForEach(submission.castNeeded, id: \.self) { entry in
                    let parsed = CastRoleFormat.split(entry)
                    openRoleRow(role: parsed.role, description: parsed.description, buttonTitle: "Audition") {
                        apply(to: entry, as: .audition)
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }
    
    @ViewBuilder
    private var editDeleteButtons: some View {
        if canEditOrDelete {
            OwnerActionButtons(
                onEdit: { showEditSheet = true },
                onDelete: {
                    store.delete(submission)
                    dismiss()
                }
            )
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
    
    // Helper function to consolidate crew members with multiple roles
    private func consolidatedCrew(_ crew: [OrderedEntry]) -> [(name: String, roles: [String])] {
        var grouped: [String: [String]] = [:]
        var order: [String] = []
        
        for entry in crew {
            if grouped[entry.name] == nil {
                order.append(entry.name)
                grouped[entry.name] = []
            }
            grouped[entry.name]?.append(entry.role)
        }
        
        return order.map { name in
            (name: name, roles: grouped[name] ?? [])
        }
    }
}

// MARK: - Supporting Views

struct UpcomingProjectFullScreenPosterView: View {
    let submission: Submission
    let tintColor: Color
    /// The exact image to show — the slide the page's slideshow is on. Defaults to the
    /// post's poster when the caller has nothing more specific.
    var image: UIImage? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let uiImage = image ?? submission.thumbnailData.flatMap(UIImage.init) {
                // Blurred, filled copy of the poster behind it, so the letterbox space
                // around a non-fullscreen poster shows a soft version of the art rather
                // than flat black.
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
                            .background(Circle().fill(.black.opacity(0.5)))
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

/// The in-app Audition / Apply form for an open role on a Cast & Crew Call.
///
/// Submitting sends the application as a direct message to the project's director
/// and producer (whoever is credited in the project's crew list), so it shows up in
/// their Messages thread with the applicant. If neither is credited, it falls back to
/// the person who posted the project. Auditions can attach a video, which is sent as
/// a `.video` message attachment the recipient can play from the chat.
struct AuditionApplicationView: View {
    let project: Submission
    let roleName: String
    let applicationType: ApplicationType
    
    enum ApplicationType {
        case audition
        case crewApplication
        
        var title: String {
            switch self {
            case .audition: return "Audition"
            case .crewApplication: return "Apply"
            }
        }
        
        var messagePrompt: String {
            switch self {
            case .audition: return "Tell us about yourself and why you'd be perfect for this role..."
            case .crewApplication: return "Tell us about your experience and why you'd be great for this position..."
            }
        }

        /// Only auditions take a video (a self-tape); crew applications are text.
        var allowsVideo: Bool { self == .audition }
    }
    
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var userManager = UserProfileManager.shared
    @State private var messageText = ""
    @State private var showSuccessAlert = false
    @FocusState private var isMessageFocused: Bool

    // Audition video (self-tape)
    @State private var videoURL: URL?
    @State private var showVideoPicker = false
    @State private var isPreparingVideo = false

    // Sending
    @State private var isSending = false
    @State private var sendError: String?
    /// Display names of the people the application was delivered to, for the alert.
    @State private var sentToNames: [String] = []
    
    private var displayRoleName: String {
        let components = roleName.components(separatedBy: ":")
        return components.first?.trimmingCharacters(in: .whitespaces) ?? roleName
    }

    private var trimmedMessage: String {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedMessage.isEmpty && !isSending && !isPreparingVideo
    }

    // MARK: - Recipients

    /// A person the application goes to: their messaging ID plus a name for the alert.
    private struct Recipient: Hashable {
        let messagingID: String
        let name: String
    }

    /// Whether a crew role is the director or a producer. "Director of Photography"
    /// and similar department heads are deliberately excluded.
    private static func isDirectorOrProducer(_ role: String) -> Bool {
        let r = role.lowercased()
        if r.contains("producer") { return true }
        if r.contains("director") {
            return !r.contains("photography") && !r.contains("casting") && !r.contains("art director")
        }
        return false
    }

    /// Resolves a crew credit to a messaging ID: by linked profile when the credit
    /// was picked from the directory, otherwise by matching the name.
    private func messagingID(for entry: OrderedEntry) -> String? {
        if let profileID = entry.profileID, !profileID.isEmpty {
            return canonicalMessagingID(profileID)
        }
        return messagingID(forName: entry.name)
    }

    private func messagingID(forName name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return userManager.allUsers.first { $0.fullName.caseInsensitiveCompare(trimmed) == .orderedSame }?.messagingUserID
    }

    /// The director(s) and producer(s) credited on the project, falling back to the
    /// poster. The current user is dropped so you can't accidentally message yourself.
    private func resolveRecipients(excluding currentUserID: String?) -> [Recipient] {
        var seen = Set<String>()
        var recipients: [Recipient] = []

        func add(_ id: String?, name: String) {
            guard let id, !id.isEmpty else { return }
            let canonical = canonicalMessagingID(id)
            if let currentUserID, canonical == canonicalMessagingID(currentUserID) { return }
            guard seen.insert(canonical).inserted else { return }
            recipients.append(Recipient(messagingID: canonical, name: name))
        }

        for entry in project.orderedCrew where Self.isDirectorOrProducer(entry.role) {
            add(messagingID(for: entry), name: entry.name)
        }

        // No director/producer credited (or none in the directory): send to the poster.
        if recipients.isEmpty {
            add(messagingID(forName: project.submittedBy), name: project.submittedBy)
        }
        return recipients
    }

    /// The text that lands in the recipients' chat: a header naming the project and
    /// role, then the applicant's message.
    private var composedMessage: String {
        let kind = applicationType == .audition ? "Audition" : "Application"
        var lines = ["🎬 \(kind) for \"\(project.title)\"", "Role: \(displayRoleName)"]
        if applicationType == .audition && videoURL != nil {
            lines.append("Audition video attached.")
        }
        lines.append("")
        lines.append(trimmedMessage)
        return lines.joined(separator: "\n")
    }
    
    /// Pushed onto the project page's navigation stack (see
    /// `UpcomingProjectDetailView`), so the back arrow is the way out — there's no
    /// Cancel button and no NavigationStack of its own.
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                projectHeader

                roleDescriptionSection

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Message")
                        .font(.headline)

                    // `axis: .vertical` keeps iOS from drawing its own field box behind
                    // the text (same workaround as the other forms), so the light grey
                    // card is the only background. Starts eight lines tall and grows.
                    TextField(applicationType.messagePrompt, text: $messageText, axis: .vertical)
                        .focused($isMessageFocused)
                        .lineLimit(8...)
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if applicationType.allowsVideo {
                    videoSection
                }
            }
            .padding()
        }
        // Pulling the list down slides the keyboard away, and there's a Done
        // button on the keyboard itself, so the form is never stuck behind it.
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            submitButton
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .navigationTitle(applicationType.title)
        .navigationBarTitleDisplayMode(.inline)
        // The project page hides the stack's bar; this screen needs it for the title
        // and back button.
        .toolbar(.visible, for: .navigationBar)
        // No backing out mid-send, which would orphan the upload.
        .navigationBarBackButtonHidden(isSending)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isMessageFocused = false }
                    .fontWeight(.semibold)
            }
        }
        .interactiveDismissDisabled(isSending)
        .sheet(isPresented: $showVideoPicker) {
            VideoPickerHelper { result in
                handleVideoPick(result)
            }
            .ignoresSafeArea()
        }
        .alert("\(applicationType.title) Sent!", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) {
                dismiss()
            }
        } message: {
            Text(successMessage)
        }
        .alert("Couldn't Send", isPresented: Binding(
            get: { sendError != nil },
            set: { if !$0 { sendError = nil } }
        )) {
            Button("OK", role: .cancel) { sendError = nil }
        } message: {
            Text(sendError ?? "")
        }
        .task {
            // Make sure the directory is loaded so credits resolve to real people.
            // Throttled internally, so this is cheap if it's already been fetched.
            await userManager.fetchAllUsers()
        }
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Sections

    private var projectHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Project")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(project.title)
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Role")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Text(displayRoleName)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { isMessageFocused = false }
    }

    /// What the role involves, so the applicant knows what they're signing up for.
    /// Crew positions get the standard job description from `CrewRoleGuide`; cast
    /// roles show the character notes the poster wrote plus what every performer is
    /// expected to do.
    private var roleDescriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About the Role")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                switch applicationType {
                case .audition:
                    castRoleDescription
                case .crewApplication:
                    crewRoleDescription
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .contentShape(Rectangle())
        .onTapGesture { isMessageFocused = false }
    }

    /// The poster's own notes on the character (the part after "Role: " in the
    /// posting), then the expectations shared by every cast member.
    @ViewBuilder
    private var castRoleDescription: some View {
        let notes = CastRoleFormat.split(roleName).description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            Text(notes)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        expectationList(title: "As a cast member you're expected to", items: CrewRoleGuide.castExpectations)
    }

    /// The standard description of the crew position, or a pointer to the contacts
    /// for a custom role the guide doesn't know.
    @ViewBuilder
    private var crewRoleDescription: some View {
        if let guide = CrewRoleGuide.description(for: displayRoleName) {
            // Only spell out the full title when the posting used a short form ("BBE").
            if guide.title.caseInsensitiveCompare(displayRoleName) != .orderedSame {
                Text(guide.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(guide.summary)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            expectationList(title: "The \(guide.title) is expected to", items: guide.expectations)
        } else {
            Text("This is a custom position for this production. Ask the director or producer what it involves — their details are in the project's contacts.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A short heading and a bulleted list of duties.
    private func expectationList(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Optional self-tape for auditions.
    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audition Video")
                .font(.headline)
            Text("Optional. Attach a self-tape from your library.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let videoURL {
                HStack(spacing: 12) {
                    Image(systemName: "video.fill")
                        .font(.title2)
                        .foregroundStyle(Color.brandOrange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Video attached")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(fileSizeDescription(for: videoURL))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        try? FileManager.default.removeItem(at: videoURL)
                        self.videoURL = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .disabled(isSending)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Button {
                    isMessageFocused = false
                    showVideoPicker = true
                } label: {
                    HStack {
                        if isPreparingVideo {
                            ProgressView()
                            Text("Preparing video…")
                        } else {
                            Image(systemName: "video.badge.plus")
                            Text("Add Video")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isPreparingVideo || isSending)
            }
        }
    }

    private var submitButton: some View {
        Button {
            submitApplication()
        } label: {
            HStack(spacing: 8) {
                if isSending {
                    ProgressView().tint(.white)
                    Text(videoURL != nil ? "Uploading…" : "Sending…")
                } else {
                    Text("Submit \(applicationType.title)")
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(canSubmit ? Color.brandOrange : Color.gray)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!canSubmit)
    }

    private var successMessage: String {
        let kind = applicationType.title.lowercased()
        switch sentToNames.count {
        case 0:
            return "Your \(kind) has been sent. Good luck!"
        case 1:
            return "Your \(kind) has been sent to \(sentToNames[0]) as a message. Good luck!"
        default:
            let list = sentToNames.dropLast().joined(separator: ", ") + " and " + sentToNames.last!
            return "Your \(kind) has been sent to \(list) as a message. Good luck!"
        }
    }

    private func fileSizeDescription(for url: URL) -> String {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 else {
            return "Ready to send"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    // MARK: - Actions

    private func handleVideoPick(_ result: Result<URL, Error>) {
        switch result {
        case .success(let pickedURL):
            isPreparingVideo = true
            Task {
                // Remux to a fast-start layout (and verify the file is readable) so
                // CloudKit can upload it and the recipient can start playback early.
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("audition-\(UUID().uuidString)")
                    .appendingPathExtension("mov")
                let prepared = (try? await VideoCompressionHelper.compressVideoIfNeeded(
                    inputURL: pickedURL,
                    outputURL: outputURL
                )) ?? pickedURL
                await MainActor.run {
                    videoURL = prepared
                    isPreparingVideo = false
                }
            }
        case .failure(let error):
            // Cancelling the picker isn't an error worth surfacing.
            if case VideoPickerError.cancelled = error { return }
            sendError = error.localizedDescription
        }
    }
    
    private func submitApplication() {
        guard canSubmit else { return }
        isMessageFocused = false
        isSending = true

        let content = composedMessage
        let attachment = applicationType.allowsVideo ? videoURL : nil

        Task {
            let currentUserID = try? await CKContainer.default().userRecordID().recordName
            let recipients = resolveRecipients(excluding: currentUserID)

            guard !recipients.isEmpty else {
                await MainActor.run {
                    isSending = false
                    sendError = "We couldn't find the director or producer of this project in the directory, so the \(applicationType.title.lowercased()) couldn't be sent. Try reaching out through the project's contacts instead."
                }
                return
            }

            var delivered: [String] = []
            var firstError: Error?
            for recipient in recipients {
                do {
                    _ = try await MessageStore.shared.sendMessage(
                        to: recipient.messagingID,
                        content: content,
                        attachmentURL: attachment,
                        attachmentType: attachment == nil ? nil : .video
                    )
                    delivered.append(recipient.name)
                } catch {
                    print("❌ Failed to send \(applicationType.title) to \(recipient.name): \(error.localizedDescription)")
                    if firstError == nil { firstError = error }
                }
            }

            await MainActor.run {
                isSending = false
                if delivered.isEmpty, let firstError {
                    sendError = firstError.localizedDescription
                } else {
                    sentToNames = delivered
                    showSuccessAlert = true
                }
            }
        }
    }
}

// MARK: - Script Reader View

struct ScriptReaderView: View {
    let scriptURL: URL
    let projectTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QuickLookPreview(url: scriptURL)
                .navigationTitle(projectTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - QuickLook Preview

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        
        init(url: URL) {
            self.url = url
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return url as QLPreviewItem
        }
    }
}


// MARK: - Preview Samples

#if DEBUG
extension Submission {
    /// A fully-populated sample project for previewing one project type's card/detail UI.
    /// Only the fields that type surfaces are filled, so each layout can be tuned per type.
    static func sampleProject(_ type: ProjectType) -> Submission {
        var s = Submission(
            id: UUID(),
            type: .project,
            title: sampleProjectTitle(type),
            details: "",
            isApproved: true,
            submittedBy: "Jamie Martinez"
        )
        s.projectType = type.rawValue
        s.studio = "RTF 304D Intro to Production"

        switch type {
        case .castCrewCall:
            // Poster + logline + shoot dates + open cast/crew + assembled team.
            s.logline = "A neo-noir thriller about a detective who uncovers a conspiracy while investigating a series of art heists in downtown Austin."
            s.genres = ["Thriller", "Mystery", "Crime"]
            s.shootDates = ShootSchedule.text(from: sampleShootDays)
            s.castNeeded = [
                "Lead Detective (Male, 30-40)",
                "Art Gallery Owner (Female, 40-50)",
                "Mysterious Informant (Any, 25-35)"
            ]
            s.crewNeeded = ["Director of Photography", "Gaffer", "Key Grip", "Sound Mixer"]
            s.projectAuditionURL = "https://example.com/audition"
            s.projectContacts = ["Jamie Martinez — jamie@example.com", "Sam Rodriguez — (512) 555-0142"]
            s.orderedCrew = [
                OrderedEntry(role: "Director", name: "Jamie Martinez"),
                OrderedEntry(role: "Producer", name: "Sam Rodriguez"),
                OrderedEntry(role: "Writer", name: "Casey Anderson")
            ]
        case .script:
            // Script PDF + genre + writer (thumbnail would be the first page).
            s.logline = "When a small-town archivist finds a letter addressed to her from the future, she has one week to decide whether to send it."
            s.genres = ["Drama"]
            s.writers = "Casey Anderson"
            s.scriptPageCount = 97
        case .inDevelopment, .inPostProduction:
            // Flyer + writers + current cast & crew (no script).
            s.logline = "A coming-of-age comedy following three roommates who start a pirate radio station out of their dorm."
            s.writers = "Casey Anderson & Priya Shah"
            s.orderedCast = [
                OrderedEntry(role: "Sam", name: "Jordan Lee"),
                OrderedEntry(role: "Web", name: "Marcus Webb")
            ]
            s.orderedCrew = [
                OrderedEntry(role: "Director", name: "Jamie Martinez"),
                OrderedEntry(role: "Producer", name: "Sam Rodriguez"),
                OrderedEntry(role: "Editor", name: "Taylor Brooks")
            ]
        }
        return s
    }

    /// Four shoot days across two months, so the card's date box shows month grouping.
    /// Each runs from its call hour to its wrap hour.
    private static var sampleShootDays: [ShootDay] {
        let calendar = Calendar.current
        return [(6, 15, 7, 17), (6, 16, 7, 17), (6, 20, 18, 23), (7, 2, 9, 15)].compactMap { month, day, call, wrap in
            guard let start = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: call)),
                  let end = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: wrap))
            else { return nil }
            return ShootDay(date: start, end: end)
        }
    }

    private static func sampleProjectTitle(_ type: ProjectType) -> String {
        switch type {
        case .castCrewCall:  return "Sunset Boulevard"
        case .script:        return "Letters to Nowhere"
        case .inDevelopment, .inPostProduction: return "Static on the Third Floor"
        }
    }
}

// MARK: - Card Previews (one per project type)

#Preview("Card • Script") {
    ProjectCard(project: .sampleProject(.script)).padding(.horizontal)
}
#Preview("Card • In-Development") {
    ProjectCard(project: .sampleProject(.inDevelopment)).padding(.horizontal)
}
#Preview("Card • Cast & Crew Call") {
    ProjectCard(project: .sampleProject(.castCrewCall)).padding(.horizontal)
}

// MARK: - Detail Previews (one per project type)

#Preview("Detail • Script") { UpcomingProjectDetailView(submission: .sampleProject(.script)) }
#Preview("Detail • In-Development") { UpcomingProjectDetailView(submission: .sampleProject(.inDevelopment)) }
#Preview("Detail • Cast & Crew Call") { UpcomingProjectDetailView(submission: .sampleProject(.castCrewCall)) }
#endif
