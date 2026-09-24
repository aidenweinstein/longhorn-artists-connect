//
//  OnboardingView.swift
//  Longhorn Artists Connect
//
//  Created by Aiden Weinstein on 12/25/25.
//
//  Refactored to use UserProfileModel for centralized user data management
//
//  This is the onboarding coordinator: it owns the shared profile model and the
//  page index, presents the app-level sheets, and saves the finished profile.
//  The individual pages live in their own files:
//    - page 0 → WelcomeView.swift          (WelcomeView)
//    - page 1 → CreateProfileView.swift    (CreateProfileView — UT students)
//    - page 2 → TagsView.swift             (TagsView)
//    - page 3 → CreateProfileView.swift    (IndustryDetailsView)
//    - page 4 → SchoolEmailVerificationView.swift
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
    // MARK: - Profile Model (Single Source of Truth)
    @StateObject private var profileModel = UserProfileModel()

    // MARK: - UI State
    @State private var currentPage: Int = 0
    @State private var fullName: String = "" // Temporary for input, splits into first/last

    /// The matched existing user + their projects, driving the "Is this you?" sheet.
    /// Using `.sheet(item:)` (rather than a separate bool + array) guarantees the sheet
    /// is built with this exact payload, instead of a stale/empty snapshot.
    @State private var existingUserMatch: ExistingUserMatch?

    // Error handling
    @State private var showingError = false
    @State private var errorMessage = ""

    @State private var showYearPicker = false

    // Profile picture crop (zoom & position), shared with EditProfileView via
    // these AppStorage keys so the chosen crop persists into the profile.
    @AppStorage("profileImageOffsetX") private var profileImageOffsetX: Double = 0
    @AppStorage("profileImageOffsetY") private var profileImageOffsetY: Double = 0
    @AppStorage("profileImageScale") private var profileImageScale: Double = 1.0
    @State private var showImageAdjustment = false

    // MARK: - Constants
    private let availableYears = ["2026", "2027", "2028", "2029", "2030"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Content
                Group {
                    if currentPage == 0 {
                        WelcomeView(
                            profileModel: profileModel,
                            currentPage: $currentPage,
                            onComplete: completeOnboarding
                        )
                    } else if currentPage == 1 {
                        CreateProfileView(
                            profileModel: profileModel,
                            fullName: $fullName,
                            currentPage: $currentPage,
                            existingUserMatch: $existingUserMatch,
                            showImageAdjustment: $showImageAdjustment
                        )
                    } else if currentPage == 2 {
                        TagsView(
                            profileModel: profileModel,
                            onComplete: completeOnboarding
                        )
                    } else if currentPage == 3 {
                        IndustryDetailsView(
                            profileModel: profileModel,
                            fullName: $fullName,
                            showImageAdjustment: $showImageAdjustment,
                            onComplete: completeOnboarding
                        )
                    } else if currentPage == 4 {
                        page5VerificationView
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
            .sheet(item: $existingUserMatch) { match in
                ExistingUserConfirmationView(
                    fullName: match.name,
                    projects: match.projects,
                    onConfirm: {
                        withAnimation {
                            currentPage += 1
                        }
                    },
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

    // MARK: - Page 5: School Email Verification

    /// Shown immediately after the student declares themselves a student, and
    /// before any profile details are collected — so someone without an
    /// eligible school address finds out before doing any work.
    ///
    /// Students only. Industry professionals have no school email and are
    /// already restricted from sharing; guests never reach this page.
    /// Skipping is allowed and lands on account details all the same; posting
    /// stays gated until they verify (see `VerificationGate`).
    private var page5VerificationView: some View {
        SchoolEmailVerificationView {
            withAnimation {
                currentPage = 1
            }
        }
    }

    // MARK: - Helper Views

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

#Preview {
    OnboardingView()
}
