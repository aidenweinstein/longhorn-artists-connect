//
//  OnboardingView.swift
//  Longhorn Artists Connect
//
//  Created by Aiden Weinstein on 12/25/25.
//
//  Refactored to use UserProfileModel for centralized user data management
//
//  This is the onboarding coordinator: it owns the shared profile model and the
//  step history, presents the app-level sheets, and saves the finished profile.
//
//  Welcome
//    ├─ Create Account → school → role
//    │     ├─ student   → verify student email   → details → tags
//    │     ├─ professor → verify faculty email   → details
//    │     └─ alumni    → name + phone           → details
//    ├─ Sign In → school → verify school email → restore this Apple ID's profile
//    │     (no profile yet → offered Create Account)
//    └─ Enthusiast (upper right) → verify any email → name
//
//  The individual pages live in their own files: WelcomeView, SchoolSelectionView,
//  SchoolRolePage, SchoolEmailVerificationView, ContactDetailsView,
//  CreateProfileView and TagsView.
//

import SwiftUI
import PhotosUI

// MARK: - Existing User Match

/// Payload for the "Is this you?" sheet. Built by `CreateProfileView` when the
/// typed name already has credited projects, and presented by `OnboardingView`.
struct ExistingUserMatch: Identifiable {
    let id = UUID()
    let name: String
    let projects: [Submission]
}

// MARK: - Onboarding Coordinator

struct OnboardingView: View {
    /// One page of onboarding.
    enum Step: Hashable {
        case welcome
        case school
        case role
        case verifySchoolEmail
        case alumniContact
        case details
        case tags
        case signInVerify
        case enthusiastVerify
        case enthusiastName
    }

    /// Which Welcome button started the school-picking path.
    enum Flow {
        case createAccount
        case signIn
    }

    // MARK: - Profile Model (Single Source of Truth)
    @StateObject private var profileModel = UserProfileModel()

    // MARK: - UI State
    /// Pages visited, so Back can retrace them. The last one is showing.
    @State private var steps: [Step] = [.welcome]
    @State private var flow: Flow = .createAccount
    @State private var school: OnboardingSchool?
    @State private var role: SchoolRole = .student
    @State private var fullName: String = "" // Temporary for input, splits into first/last
    /// Set once a school email is verified on Sign-In, so Create Account
    /// (offered when no profile exists) doesn't ask again.
    @State private var hasVerifiedSchoolEmail = false

    /// The matched existing user + their projects, driving the "Is this you?" sheet.
    /// Using `.sheet(item:)` (rather than a separate bool + array) guarantees the sheet
    /// is built with this exact payload, instead of a stale/empty snapshot.
    @State private var existingUserMatch: ExistingUserMatch?

    // Sign-In
    @State private var isRestoring = false
    @State private var showNoAccountFound = false

    // Profile picture crop (zoom & position), shared with EditProfileView via
    // these AppStorage keys so the chosen crop persists into the profile.
    @AppStorage("profileImageOffsetX") private var profileImageOffsetX: Double = 0
    @AppStorage("profileImageOffsetY") private var profileImageOffsetY: Double = 0
    @AppStorage("profileImageScale") private var profileImageScale: Double = 1.0
    @State private var showImageAdjustment = false

    private var step: Step { steps.last ?? .welcome }

    /// Whether email verification steps are shown. Development builds (and
    /// builds with no service configured) skip them, as before.
    private var isVerificationEnabled: Bool {
        StudentVerificationManager.isUIAvailable && StudentVerificationManager.isRequired
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                page
                    .animation(.easeInOut, value: step)
            }
            // Tapping anywhere outside a text field drops the keyboard. The account
            // pages are fixed (scrollDisabled), so without this the keyboard can sit
            // over the Next / Create Account button with no way to reach it.
            .endEditingOnTap()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if steps.count > 1 && !isRestoring {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation { _ = steps.popLast() }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Back")
                    }
                }
            }
            .overlay {
                if isRestoring {
                    ProgressView("Signing in…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("No account found", isPresented: $showNoAccountFound) {
                Button("Create Account") {
                    flow = .createAccount
                    withAnimation { steps = [.welcome, .school, .role] }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("There's no Nexus account on this Apple ID yet. You can create one now.")
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
            .sheet(item: $existingUserMatch) { match in
                ExistingUserConfirmationView(
                    fullName: match.name,
                    projects: match.projects,
                    onConfirm: advanceFromDetails,
                    onCancel: {
                        existingUserMatch = nil
                    }
                )
            }
        }
        // Onboarding is presented outside ContentView, so it needs its own copy of the
        // app-wide "no scrollbars" preference (see ContentView).
        .scrollIndicators(.hidden)
    }

    // MARK: - Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome:
            WelcomeView(
                onCreateAccount: {
                    flow = .createAccount
                    go(to: .school)
                },
                onSignIn: {
                    flow = .signIn
                    go(to: .school)
                },
                onEnthusiast: {
                    configureEnthusiast()
                    go(to: isVerificationEnabled ? .enthusiastVerify : .enthusiastName)
                }
            )

        case .school:
            SchoolSelectionView { picked in
                school = picked
                profileModel.school = picked.name
                switch flow {
                case .createAccount:
                    go(to: .role)
                case .signIn:
                    if isVerificationEnabled {
                        go(to: .signInVerify)
                    } else {
                        restoreProfile()
                    }
                }
            }

        case .role:
            if let school {
                SchoolRolePage(school: school) { picked in
                    role = picked
                    configureMember(role: picked)
                    switch picked {
                    case .student, .professor:
                        go(to: isVerificationEnabled && !hasVerifiedSchoolEmail ? .verifySchoolEmail : .details)
                    case .alumni:
                        go(to: .alumniContact)
                    }
                }
            }

        case .verifySchoolEmail:
            // Required to move on: no skip button.
            SchoolEmailVerificationView(
                onFinished: { go(to: .details) },
                dismissTitle: nil,
                school: school?.name,
                allowedDomains: school?.domain(for: role).map { [$0] },
                subtitle: role == .professor
                    ? "Enter your faculty email address. We'll send a six-digit code to confirm it's yours."
                    : "Enter your student email address. We'll send a six-digit code to confirm it's yours."
            )

        case .alumniContact:
            ContactDetailsView(
                title: "Welcome Back",
                subtitle: "Alumni don't need a school email. Tell us who you are.",
                fullName: $fullName,
                phoneNumber: $profileModel.phoneNumber,
                buttonTitle: "Next",
                onContinue: { go(to: .details) }
            )

        case .details:
            CreateProfileView(
                profileModel: profileModel,
                fullName: $fullName,
                role: role,
                onNext: advanceFromDetails,
                existingUserMatch: $existingUserMatch,
                showImageAdjustment: $showImageAdjustment
            )

        case .tags:
            TagsView(
                profileModel: profileModel,
                onComplete: completeOnboarding
            )

        case .signInVerify:
            // Either verifying or "I'm an alumni" leads to the restore: the
            // account itself is keyed by Apple ID, and alumni have no school email.
            SchoolEmailVerificationView(
                onFinished: {
                    hasVerifiedSchoolEmail = StudentVerificationManager.shared.status.isVerified
                    restoreProfile()
                },
                dismissTitle: "I'm an alumni",
                school: school?.name,
                allowedDomains: school?.allDomains,
                title: "Sign In",
                subtitle: "Verify your school email to sign in to your Nexus account."
            )

        case .enthusiastVerify:
            SchoolEmailVerificationView(
                onFinished: { go(to: .enthusiastName) },
                dismissTitle: nil,
                allowedDomains: [],
                purpose: .enthusiast,
                title: "Verify Your Email",
                subtitle: "Enter any email address. We'll send a six-digit code to confirm it's yours."
            )

        case .enthusiastName:
            ContactDetailsView(
                title: "What's your name?",
                subtitle: "Enthusiasts can watch and listen to work on Nexus. Your account isn't listed in the directory.",
                fullName: $fullName,
                buttonTitle: "Finish",
                onContinue: completeOnboarding
            )
        }
    }

    // MARK: - Navigation

    private func go(to next: Step) {
        withAnimation { steps.append(next) }
    }

    /// Students go on to pick tags; professors and alumni are done.
    private func advanceFromDetails() {
        if role == .student {
            go(to: .tags)
        } else {
            completeOnboarding()
        }
    }

    // MARK: - Account Types

    /// Student, professor or alumni: a full member of the picked school.
    private func configureMember(role: SchoolRole) {
        profileModel.schoolRole = role
        profileModel.isUTStudent = true
        profileModel.isGuest = false
        profileModel.isIndustryProfessional = false
        profileModel.accountKind = .artist
        if role != .alumni {
            profileModel.phoneNumber = ""
        }
    }

    /// The Guest-style experience (no posting, messaging, projects or events),
    /// with no school and no directory listing.
    private func configureEnthusiast() {
        profileModel.schoolRole = nil
        profileModel.isUTStudent = false
        profileModel.isGuest = true
        profileModel.isIndustryProfessional = false
        profileModel.accountKind = .enthusiast
        profileModel.school = ""
        profileModel.phoneNumber = ""
    }

    // MARK: - Sign In

    /// Loads the profile saved to this Apple ID. Success flips
    /// `hasCompletedOnboarding`, which swaps the app in (see LaunchScreenView).
    private func restoreProfile() {
        isRestoring = true
        Task {
            await CloudKitManager.shared.checkAvailability()
            let restored = CloudKitManager.shared.isAvailable
                ? await UserProfileModel().loadFromCloudKit()
                : false
            isRestoring = false
            if !restored {
                showNoAccountFound = true
            }
        }
    }

    // MARK: - Helper Methods

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
        VStack(spacing: 0) {
            // Scrollable content: starts at the top and scrolls when it overflows
            // the (fixed-height) medium detent.
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    projectsSection
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }

            // Pinned below the scroll view so the confirmation buttons stay visible
            // no matter how many projects are listed.
            actionButtonsSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(.systemBackground))
    }

    // MARK: - View Components

    private var headerSection: some View {
        VStack(spacing: 12) {
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Projects")
                .font(.headline)

            ForEach(projects) { project in
                Text(project.title)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button {
                onConfirm()
                dismiss()
            } label: {
                Text("Yes, this is me")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.brandOrange)
                    .cornerRadius(12)
            }

            Button {
                onCancel()
                dismiss()
            } label: {
                Text("No, that's not me")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray4))
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }
}

#Preview("Onboarding") {
    OnboardingView()
}

#Preview("Existing User Confirmation") {
    ExistingUserConfirmationView(
        fullName: "Jane Doe",
        projects: ["Sample Film", "Sample Track", "Sample Reel"].map {
            Submission(id: UUID(), type: .film, title: $0, details: "", isApproved: true, submittedBy: "Jane Doe")
        },
        onConfirm: {},
        onCancel: {}
    )
}
