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
                // Poster on left
                ZStack {
                    if let thumbnailData = project.thumbnailData,
                       let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 180)
                            .clipped()
                    } else {
                        Color.secondary.opacity(0.1)
                        Image(systemName: "photo")
                            .imageScale(.large)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, height: 180)
                .clipped() // Square corners, matching the event card
                
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
                .frame(maxWidth: .infinity, maxHeight: 180, alignment: .top)
            }
            .padding(.vertical, 16)
        }
    }
    
    private var projectType: ProjectType? { ProjectType(rawValue: project.projectType) }

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
        case .inDevelopment:
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
            if !project.shootDates.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "video.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(removeYear(from: project.shootDates))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(teamStatusText)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
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

    /// "X cast · Y crew" for an In-Development project.
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

    @State private var selectedCastRole: String?
    @State private var selectedCrewRole: String?
    @State private var showAuditionSheet = false
    @State private var showApplySheet = false
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
    
    // Generate a consistent color for each project based on title
    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(submission.title.hashValue)
        return colors[hash % colors.count]
    }
    
    var body: some View {
        ZStack {
            if isLoading && !contentLoaded {
                loadingView
            } else {
                mainContentView
            }
        }
        .presentationDragIndicator(.hidden)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    isLoading = false
                    contentLoaded = true
                }
            }
        }
        .task { loadCarousel() }
        .sheet(isPresented: $showAuditionSheet) {
            if let role = selectedCastRole {
                AuditionApplicationView(
                    projectTitle: submission.title,
                    roleName: role,
                    applicationType: .audition
                )
            }
        }
        .sheet(isPresented: $showApplySheet) {
            if let role = selectedCrewRole {
                AuditionApplicationView(
                    projectTitle: submission.title,
                    roleName: role,
                    applicationType: .crewApplication
                )
            }
        }
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
                castCallSection
                crewCallSection
                castSection
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
            .tabViewStyle(.page)
            .frame(maxWidth: .infinity)
            // Size the slideshow to the current image's own aspect ratio so each shows
            // at the shape it was submitted — no letterboxing.
            .aspectRatio(currentCarouselAspectRatio, contentMode: .fit)
            .animation(.default, value: carouselIndex)
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
    
    @ViewBuilder
    private var detailsSection: some View {
        if !submission.genres.isEmpty || !submission.shootDates.isEmpty || !submission.expectedReleaseDate.isEmpty {
            Divider()
                .padding(.top, 12)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Details")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 6) {
                    if !submission.genres.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "theatermasks.fill")
                                .font(.caption)
                            Text(submission.genres.joined(separator: ", "))
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    }

                    if !submission.shootDates.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "video.fill")
                                .font(.caption)
                            Text(submission.shootDates)
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    }

                    if !submission.expectedReleaseDate.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "popcorn.fill")
                                .font(.caption)
                            Text(submission.expectedReleaseDate)
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }
    
    @ViewBuilder
    private var crewSection: some View {
        if !submission.orderedCrew.isEmpty {
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
            }
            .padding(.vertical)
        }
    }
    
    @ViewBuilder
    private var castCallSection: some View {
        if !submission.castNeeded.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cast Call")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                ForEach(submission.castNeeded, id: \.self) { entry in
                    let parsed = CastRoleFormat.split(entry)
                    HStack(alignment: .top, spacing: 12) {
                        Text(parsed.role)
                            .font(.body)

                        if !parsed.description.isEmpty {
                            Spacer(minLength: 8)
                            Text(parsed.description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
            .padding(.bottom, 8)
        }
    }
    
    @ViewBuilder
    private var crewCallSection: some View {
        if !submission.crewNeeded.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Crew Call")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                ForEach(submission.crewNeeded, id: \.self) { role in
                    HStack(alignment: .center, spacing: 12) {
                        Text(role)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
            .padding(.bottom, 8)
        }
    }
    
    @ViewBuilder
    private var castSection: some View {
        if !submission.orderedCast.isEmpty {
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
        .presentationDragIndicator(.hidden)
    }
}

struct AuditionApplicationView: View {
    let projectTitle: String
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
    }
    
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""
    @State private var showSuccessAlert = false
    
    private var displayRoleName: String {
        let components = roleName.components(separatedBy: ":")
        return components.first?.trimmingCharacters(in: .whitespaces) ?? roleName
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(projectTitle)
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
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Message")
                        .font(.headline)
                    
                    TextEditor(text: $messageText)
                        .frame(minHeight: 200)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            Group {
                                if messageText.isEmpty {
                                    Text(applicationType.messagePrompt)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 16)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                        .allowsHitTesting(false)
                                }
                            }
                        )
                }
                
                Spacer()
                
                Button {
                    submitApplication()
                } label: {
                    Text("Submit \(applicationType.title)")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(messageText.isEmpty ? Color.gray : Color.brandOrange)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
            .navigationTitle(applicationType.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Application Submitted!", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Your \(applicationType.title.lowercased()) has been sent to the project creator. Good luck!")
        }
        .presentationDragIndicator(.hidden)
    }
    
    private func submitApplication() {
        print("Submitting \(applicationType.title) for project: \(projectTitle)")
        print("Role: \(displayRoleName)")
        print("Message: \(messageText)")
        showSuccessAlert = true
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

        switch type {
        case .castCrewCall:
            // Poster + logline + shoot dates + open cast/crew + assembled team.
            s.logline = "A neo-noir thriller about a detective who uncovers a conspiracy while investigating a series of art heists in downtown Austin."
            s.genres = ["Thriller", "Mystery", "Crime"]
            s.shootDates = "June 15, 2026 - July 20, 2026"
            s.expectedReleaseDate = "Fall 2026"
            s.castNeeded = [
                "Lead Detective (Male, 30-40)",
                "Art Gallery Owner (Female, 40-50)",
                "Mysterious Informant (Any, 25-35)"
            ]
            s.crewNeeded = ["Director of Photography", "Gaffer", "Key Grip", "Sound Mixer"]
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
        case .inDevelopment:
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

    private static func sampleProjectTitle(_ type: ProjectType) -> String {
        switch type {
        case .castCrewCall:  return "Sunset Boulevard"
        case .script:        return "Letters to Nowhere"
        case .inDevelopment: return "Static on the Third Floor"
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
