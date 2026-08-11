//
//  OnboardingView.swift
//  Longhorn Artists Connect
//
//  Created by Aiden Weinstein on 12/25/25.
//
//  Refactored to use UserProfileModel for centralized user data management

import SwiftUI
import PhotosUI

// MARK: - Helper Extension for Keyboard Dismissal

extension View {
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

struct OnboardingView: View {
    // MARK: - Profile Model (Single Source of Truth)
    @StateObject private var profileModel = UserProfileModel()

    // MARK: - UI State
    @State private var currentPage: Int = 0
    @State private var fullName: String = "" // Temporary for input, splits into first/last
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedSchool: String?

    // Selection sheets
    @State private var showMajorSelection = false
    @State private var showMinorSelection = false
    @State private var showCertificateSelection = false
    @State private var showYearPicker = false
    @State private var showExistingUserSheet = false
    @State private var existingUserProjects: [Submission] = []

    // Error handling
    @State private var showingError = false
    @State private var errorMessage = ""

    // Profile picture crop (zoom & position), shared with EditProfileView via
    // these AppStorage keys so the chosen crop persists into the profile.
    @AppStorage("profileImageOffsetX") private var profileImageOffsetX: Double = 0
    @AppStorage("profileImageOffsetY") private var profileImageOffsetY: Double = 0
    @AppStorage("profileImageScale") private var profileImageScale: Double = 1.0
    @State private var showImageAdjustment = false

    // MARK: - Dependencies
    @ObservedObject var store: SubmissionStore_3_2 = .shared

    // MARK: - Constants
    private let availableYears = ["2026", "2027", "2028", "2029", "2030"]

    // MARK: - Validation
    var isAccountDetailsValid: Bool {
        let nameValid = !fullName.trimmingCharacters(in: .whitespaces).isEmpty
        let majorValid = !profileModel.major.isEmpty
        let yearValid = !profileModel.graduationYear.isEmpty
        let photoValid = profileModel.profileImage != nil
        return nameValid && majorValid && yearValid && photoValid
    }

    var isTagsValid: Bool {
        !profileModel.userTypes.isEmpty
    }

    /// Guest accounts only require a name and a photo.
    var isGuestDetailsValid: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty && profileModel.profileImage != nil
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Content
                Group {
                    if currentPage == 0 {
                        page1WelcomeView
                    } else if currentPage == 1 {
                        page2AccountDetailsView
                    } else if currentPage == 2 {
                        page4UserTypesView
                    } else if currentPage == 3 {
                        guestAccountView
                    }
                }
                .animation(.easeInOut, value: currentPage)
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showYearPicker) {
                yearPickerSheet
            }
            .sheet(isPresented: $showImageAdjustment) {
                if let data = profileModel.profileImage?.jpegData(compressionQuality: 0.9) {
                    ImageAdjustmentView(
                        imageData: data,
                        offsetX: $profileImageOffsetX,
                        offsetY: $profileImageOffsetY,
                        scale: $profileImageScale
                    )
                }
            }
            .sheet(isPresented: $showExistingUserSheet) {
                ExistingUserConfirmationView(
                    fullName: fullName,
                    projects: existingUserProjects,
                    onConfirm: {
                        withAnimation {
                            currentPage += 1
                        }
                    },
                    onCancel: {
                        showExistingUserSheet = false
                    }
                )
            }
        }
    }
    
    
    // MARK: - Page 1: Welcome Screen with Create Account / Log In
    
    private var page1WelcomeView: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: UIScreen.main.bounds.height * 0.15) // 2/3 of the way down is ~15% from top
            
            // Welcome header
            VStack(spacing: 8) {
                Text("Welcome to")
                    .font(.title)
                    .foregroundStyle(.secondary)
                
                Image("NexusOrange")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 72)
                
                Text("from Longhorn Artists Connect")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 16) {
                Button {
                    profileModel.isUTStudent = true
                    withAnimation {
                        currentPage = 1
                    }
                } label: {
                    Text("I am a UT Student")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandOrange)
                        .cornerRadius(12)
                }

                Button {
                    profileModel.isUTStudent = false
                    withAnimation {
                        currentPage = 3
                    }
                } label: {
                    Text("I am a Guest User")
                        .font(.headline)
                        .foregroundStyle(Color.brandOrange)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandOrange.opacity(0.12))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Page 2: Account Details (Create Account only)
    
    private var page2AccountDetailsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create Your Account")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Automatically linked with Apple ID.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)
                
                // Profile Picture Section
                profilePictureSection()

                // Form fields
                VStack(spacing: 0) {
                    // Name field *
                    HStack(alignment: .center) {
                        Text("Name *")
                            .font(.body)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        TextField("", text: $fullName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.primary)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    
                    Divider()
                        .padding(.leading, 16)
                    
                    // Major selection *
                    Button {
                        showMajorSelection = true
                    } label: {
                        HStack(alignment: .center) {
                            Text("Major *")
                                .font(.body)
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            Text(profileModel.major.isEmpty ? "Select" : profileModel.major)
                                .foregroundStyle(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                        .padding(.leading, 16)
                    
                    // Minor selection
                    Button {
                        showMinorSelection = true
                    } label: {
                        HStack(alignment: .center) {
                            Text("Minor")
                                .font(.body)
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            Text(profileModel.minor.isEmpty ? "Select" : profileModel.minor)
                                .foregroundStyle(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                        .padding(.leading, 16)
                    
                    // Certificate selection
                    Button {
                        showCertificateSelection = true
                    } label: {
                        HStack(alignment: .center) {
                            Text("Certificate")
                                .font(.body)
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            Text(profileModel.certificate.isEmpty ? "Select" : profileModel.certificate)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                        .padding(.leading, 16)
                    
                    // Graduation Year *
                    Menu {
                        ForEach(availableYears, id: \.self) { year in
                            Button {
                                profileModel.graduationYear = year
                            } label: {
                                HStack {
                                    Text(year)
                                    if profileModel.graduationYear == year {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(alignment: .center) {
                            Text("Class of *")
                                .font(.body)
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Text(profileModel.graduationYear.isEmpty ? "Select" : profileModel.graduationYear)
                                    .foregroundStyle(.secondary)
                                
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                
                Spacer(minLength: 20)
                
                // Next button
                Button {
                    // Check if name already exists
                    let fullNameTrimmed = fullName.trimmingCharacters(in: .whitespaces)
                    let existingProjects = findProjectsForName(fullNameTrimmed)

                    if !existingProjects.isEmpty {
                        // Show "Is this you?" sheet
                        existingUserProjects = existingProjects
                        showExistingUserSheet = true
                    } else {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                } label: {
                    Text("Next")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isAccountDetailsValid ? Color.brandOrange : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!isAccountDetailsValid)
            }
            .padding(.horizontal, 24)
        }
        .sheet(isPresented: $showMajorSelection) {
            NavigationStack {
                MajorSelectionView(selectedMajor: $profileModel.major)
            }
        }
        .sheet(isPresented: $showMinorSelection) {
            NavigationStack {
                MinorSelectionView(selectedMinor: $profileModel.minor)
            }
        }
        .sheet(isPresented: $showCertificateSelection) {
            NavigationStack {
                CertificateSelectionView(selectedCertificate: $profileModel.certificate)
            }
        }
    }
    
    // MARK: - Guest Account (name + picture only, then straight to the app)

    private var guestAccountView: some View {
        VStack(spacing: 0) {
            ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create Guest Account")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Automatically liked with Apple ID.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                // Profile Picture Section
                profilePictureSection()

                // Name field
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        Text("Name *")
                            .font(.body)
                            .foregroundStyle(.primary)

                        Spacer()

                        TextField("", text: $fullName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.primary)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
            }

            // Straight into the app — no tags step for guests. Pinned to the bottom.
            Button {
                completeOnboarding()
            } label: {
                Text("Explore the Nexus!")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isGuestDetailsValid ? Color.brandOrange : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!isGuestDetailsValid)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Page 3: User Types Selection (Final Step)
    
    private var page4UserTypesView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Choose Your Tags")
                                .font(.title)
                                .fontWeight(.bold)

                            Image(systemName: "tag.fill")
                                .font(.title)
                                .foregroundStyle(Color.brandOrange)
                        }

                        Text("Describe yourself. Select at least one tag.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)
                    
                    // User type options grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(UserType.allCases) { type in
                            UserTypeButton(
                                type: type,
                                isSelected: profileModel.userTypes.contains(type),
                                onTap: {
                                    toggleUserType(type)
                                }
                            )
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24)
            }
            
            // Bottom button
            Button {
                completeOnboarding()
            } label: {
                Text("Explore the Nexus!")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isTagsValid ? Color.brandOrange : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!isTagsValid)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Helper Views

    /// Profile-photo picker shared by the UT-student and Guest onboarding pages.
    /// Applies the saved zoom/position crop to the preview and lets the user
    /// re-open the adjuster, matching EditProfileView.
    private func profilePictureSection() -> some View {
        let hasImage = profileModel.profileImage != nil
        return VStack(spacing: 16) {
            if let profileImage = profileModel.profileImage {
                GeometryReader { _ in
                    Image(uiImage: profileImage)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(profileImageScale)
                        // Offsets are saved in the adjuster's 300pt preview space,
                        // so scale them to this 120pt frame to match exactly.
                        .offset(x: CGFloat(profileImageOffsetX) * 120 / ImageAdjustmentView.previewSize,
                                y: CGFloat(profileImageOffsetY) * 120 / ImageAdjustmentView.previewSize)
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                }
                .frame(width: 120, height: 120)
                .overlay(
                    Circle()
                        .stroke(Color.brandOrange, lineWidth: 3)
                )
                .onTapGesture { showImageAdjustment = true }
            } else {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 120, height: 120)

                    Image(systemName: "person.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Text(hasImage ? "Change Photo" : "Choose Photo *")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.brandOrange)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                if hasImage {
                    Button {
                        showImageAdjustment = true
                    } label: {
                        Text("Adjust Photo")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.brandOrange.opacity(0.15))
                            .foregroundStyle(Color.brandOrange)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task { @MainActor in
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    profileModel.profileImage = uiImage
                    // Reset the crop for the new photo, then open the adjuster
                    // so the user can zoom/position — same as EditProfileView.
                    profileImageOffsetX = 0
                    profileImageOffsetY = 0
                    profileImageScale = 1.0
                    showImageAdjustment = true
                }
            }
        }
    }

    private var yearPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(availableYears, id: \.self) { year in
                    Button {
                        profileModel.graduationYear = year
                        showYearPicker = false
                    } label: {
                        HStack {
                            Text(year)
                                .foregroundStyle(.primary)
                            Spacer()
                            if profileModel.graduationYear == year {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.brandOrange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Graduation Year")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showYearPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Helper Methods

    private func toggleUserType(_ type: UserType) {
        // Enthusiast is mutually exclusive with other roles
        if type == .enthusiast {
            if profileModel.userTypes.contains(.enthusiast) {
                profileModel.userTypes.remove(.enthusiast)
            } else {
                profileModel.userTypes = [.enthusiast]
            }
        } else {
            // Remove enthusiast if selecting another role
            if profileModel.userTypes.contains(.enthusiast) {
                profileModel.userTypes.removeAll()
            }
            
            if profileModel.userTypes.contains(type) {
                profileModel.userTypes.remove(type)
            } else if profileModel.userTypes.count < 5 {
                profileModel.userTypes.insert(type)
            }
        }
    }
    
    private func findProjectsForName(_ name: String) -> [Submission] {
        var projects: [Submission] = []
        
        // Search through all submissions (approved and pending)
        let allSubmissions = store.approvedSubmissions + store.submissions
        
        for submission in allSubmissions {
            // Check if name appears in submittedBy
            if submission.submittedBy == name {
                projects.append(submission)
                continue
            }
            
            // Check cast
            for entry in submission.orderedCast where entry.name == name {
                if !projects.contains(where: { $0.id == submission.id }) {
                    projects.append(submission)
                }
                break
            }
            
            // Check crew
            for entry in submission.orderedCrew where entry.name == name {
                if !projects.contains(where: { $0.id == submission.id }) {
                    projects.append(submission)
                }
                break
            }
        }
        
        return projects
    }
    
    private func completeOnboarding() {
        let components = fullName.split(separator: " ", maxSplits: 1).map(String.init)
        let firstName = components.first ?? ""
        let lastName = components.count > 1 ? components[1] : ""

        profileModel.firstName = firstName
        profileModel.lastName = lastName

        // Bake the pan/zoom crop into the image so the framing is saved with the
        // photo and travels to CloudKit / the directory / other users. Reset the
        // crop to identity afterwards so displays don't apply it a second time.
        if let original = profileModel.profileImage,
           profileImageScale != 1.0 || profileImageOffsetX != 0 || profileImageOffsetY != 0 {
            profileModel.profileImage = ProfileImageCropper.bakedImage(
                from: original,
                scale: CGFloat(profileImageScale),
                offsetX: CGFloat(profileImageOffsetX),
                offsetY: CGFloat(profileImageOffsetY)
            )
            profileImageScale = 1.0
            profileImageOffsetX = 0
            profileImageOffsetY = 0
        }

        profileModel.save()

        print("✅ Onboarding completed for: \(profileModel.fullName)")
    }
}

// MARK: - Helper Views

struct ShareTypeInfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .padding(5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.brandOrange)
                )
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct UserTypeButton: View {
    let type: UserType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(type.rawValue)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.brandOrange : Color(uiColor: .systemGroupedBackground))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - App Section Info Row

struct AppSectionInfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.brandOrange)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.brandOrange.opacity(0.15))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Existing User Confirmation View

struct ExistingUserConfirmationView: View {
    let fullName: String
    let projects: [Submission]
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    private var projectsFoundMessage: AttributedString {
        let projectCount = projects.count
        let projectWord = projectCount == 1 ? "project" : "projects"
        var message = AttributedString("We found \(projectCount) \(projectWord) credited to ")
        var boldName = AttributedString(fullName)
        boldName.font = .body.bold()
        message.append(boldName)
        return message
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    projectsSection
                    actionButtonsSection
                    disclaimerText
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onCancel()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
            
            Text("Is this you?")
                .font(.title)
                .fontWeight(.bold)
            
            Text(projectsFoundMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 40)
    }
    
    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Projects")
                .font(.headline)
                .padding(.horizontal)
            
            ForEach(projects) { project in
                ProjectRow(project: project)
            }
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button {
                onConfirm()
                dismiss()
            } label: {
                Text("Yes, this is me")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
            
            Button {
                onCancel()
                dismiss()
            } label: {
                Text("No, that's not me")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal)
        .padding(.top, 24)
    }
    
    private var disclaimerText: some View {
        Text("If this is not you, please choose a different name or add a middle initial to distinguish yourself.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            .padding(.bottom, 40)
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func ProjectRow(project: Submission) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                let iconName = project.type == .film ? "film" : "music.note"
                Image(systemName: iconName)
                    .foregroundStyle(Color.accentColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title)
                        .font(.headline)
                    
                    if let role = getRoleInProject(project) {
                        Text(role)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
            )
        }
        .padding(.horizontal)
    }
    
    private func getRoleInProject(_ project: Submission) -> String? {
        // Check if they submitted it
        if project.submittedBy == fullName {
            return project.type == .film ? "Director" : "Artist"
        }
        
        // Check cast
        for entry in project.orderedCast where entry.name == fullName {
            return entry.role
        }
        
        // Check crew
        var crewRoles: [String] = []
        for entry in project.orderedCrew where entry.name == fullName {
            crewRoles.append(entry.role)
        }
        
        if !crewRoles.isEmpty {
            return crewRoles.joined(separator: ", ")
        }
        
        return nil
    }
}

#Preview {
    OnboardingView()
}
