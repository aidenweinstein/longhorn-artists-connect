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
/// members are orange and tap through to their portfolio (by assigning the
/// bound selection); everyone else is shown as plain grey, non-interactive text.
struct CreditNameView: View {
    let name: String
    @Binding var selection: CreditedPerson?
    @ObservedObject private var profileManager = UserProfileManager.shared

    var body: some View {
        if isRegisteredOnNexus(name) {
            Button {
                selection = CreditedPerson(name: name)
            } label: {
                Text(name)
                    .font(.body)
                    .foregroundStyle(Color.brandOrange)
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

    /// Whether a credited person has a Nexus account (directory user or a
    /// locally created profile), which makes their name clickable.
    private func isRegisteredOnNexus(_ name: String) -> Bool {
        let createdProfiles = UserDefaults.standard.stringArray(forKey: "createdUserProfiles") ?? []
        if createdProfiles.contains(name) { return true }
        return profileManager.allUsers.contains { $0.fullName == name }
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
                .clipShape(RoundedRectangle(cornerRadius: 8)) // Slightly rounded corners
                
                // Project info on right
                VStack(alignment: .leading, spacing: 4) {
                    // Project title heading
                    Text(project.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Logline under title - shows as much as possible without pushing content below poster
                    if !project.logline.isEmpty {
                        Text(project.logline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                    }
                    
                    Spacer(minLength: 0)
                    
                    // Shoot dates with film camera icon (without year) - centered between logline and button
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
                    
                    // Role status capsule: orange when cast/crew are still needed,
                    // grey once the team is fully assembled.
                    Text(teamStatusText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(teamStatusColor)
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity, maxHeight: 180, alignment: .top)
            }
            .padding(.vertical, 16)
        }
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
        result = result.replacingOccurrences(of: "- ", with: "-")
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: ", -"))
        return result
    }
}

// MARK: - Project Detail View (Full Screen Sheet)

struct UpcomingProjectDetailView: View {
    let submission: Submission
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    
    @State private var selectedCastRole: String?
    @State private var selectedCrewRole: String?
    @State private var showAuditionSheet = false
    @State private var showApplySheet = false
    @State private var showEditSheet = false
    @State private var isLoading = true
    @State private var contentLoaded = false
    @State private var showFullScreenPoster = false
    @State private var showScriptReader = false
    @State private var selectedPerson: CreditedPerson?
    
    // Check if current user is the project creator or a moderator
    private var canEditOrDelete: Bool {
        // Check if user is the creator
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        let isUserCreator = !currentUser.isEmpty && currentUser == submission.submittedBy
        
        // Check if user is a moderator (only Aiden Weinstein)
        let isModeratorMode = UserDefaults.standard.bool(forKey: "isModeratorMode")
        let isAidenWeinstein = currentUser == "Aiden Weinstein"
        let canUseModerator = isModeratorMode && isAidenWeinstein
        
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
        .presentationDragIndicator(.visible)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    isLoading = false
                    contentLoaded = true
                }
            }
        }
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
            }
        }
        .fullScreenCover(isPresented: $showFullScreenPoster) {
            UpcomingProjectFullScreenPosterView(submission: submission, tintColor: tintColor)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            // Flyer centered, alone at the top
            posterButton
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 10) // Nudge the flyer down

            projectInfoColumn
        }
        .padding(.horizontal)
        .padding(.top)
    }

    private var posterButton: some View {
        Button {
            showFullScreenPoster = true
        } label: {
            if let thumbnailData = submission.thumbnailData,
               let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 235)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    Color.secondary.opacity(0.1)
                    Image(systemName: "photo")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 235, height: 353)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .buttonStyle(.plain)
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
                
                ForEach(submission.castNeeded, id: \.self) { role in
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
                
                ForEach(submission.orderedCast, id: \.role) { entry in
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

            HStack(spacing: 12) {
                Button {
                    showEditSheet = true
                } label: {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                Button {
                    store.delete(submission)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .font(.headline)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
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
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let thumbnailData = submission.thumbnailData,
               let uiImage = UIImage(data: thumbnailData) {
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
    @State private var showShareSheet = false
    
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
                    
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(items: [scriptURL])
                }
        }
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

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview("Project Card") {
    ProjectCard(project: .placeholderProjectV2)
        .padding(.horizontal)
}

#Preview("Project Detail") {
    UpcomingProjectDetailView(submission: .placeholderProjectV2)
}
