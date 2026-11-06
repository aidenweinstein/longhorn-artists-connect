//
//  CreateProfileView.swift
//  Longhorn Artists Connect
//
//  The "Create Your Account" step of onboarding, in two variants:
//    - `CreateProfileView`   — UT students: name, photo, major, graduation year.
//    - `IndustryDetailsView` — industry professionals: name, photo, industry,
//                              company, company role (no academics, and they
//                              skip the tags step entirely).
//  Both share `OnboardingProfilePicturePicker` for the profile photo.
//  Extracted from OnboardingView.swift.
//

import SwiftUI
import PhotosUI

// MARK: - Create Profile (UT Students)

struct CreateProfileView: View {
    @ObservedObject var profileModel: UserProfileModel

    /// Raw "First Last" input, owned by `OnboardingView` because
    /// `completeOnboarding()` splits it into first/last name on save.
    @Binding var fullName: String

    /// The onboarding page index, owned by `OnboardingView`.
    @Binding var currentPage: Int

    /// Set when the typed name already has credited projects, which drives
    /// `OnboardingView`'s "Is this you?" sheet.
    @Binding var existingUserMatch: ExistingUserMatch?

    /// Opens the crop/zoom adjuster, presented by `OnboardingView`.
    @Binding var showImageAdjustment: Bool

    @Environment(\.colorScheme) private var colorScheme

    // Selection sheets
    @State private var showMajorSelection = false
    @State private var showMinorSelection = false
    @State private var showCertificateSelection = false

    // MARK: - Dependencies
    @ObservedObject private var store: SubmissionStore_3_2 = .shared

    // MARK: - Constants
    private let availableYears = ["2026", "2027", "2028", "2029", "2030"]

    // MARK: - Validation

    private var isAccountDetailsValid: Bool {
        let nameValid = !fullName.trimmingCharacters(in: .whitespaces).isEmpty
        let majorValid = !profileModel.major.isEmpty
        let yearValid = !profileModel.graduationYear.isEmpty
        let photoValid = profileModel.profileImage != nil
        return nameValid && majorValid && yearValid && photoValid
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create Your Account")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Automatically saves with Apple ID")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                // Profile Picture Section
                OnboardingProfilePicturePicker(
                    profileModel: profileModel,
                    showImageAdjustment: $showImageAdjustment
                )

                // Form fields
                VStack(spacing: 0) {
                    // Name field
                    HStack(alignment: .center) {
                        Text("First & Last Name")
                            .font(.body)
                            .foregroundStyle(.primary)

                        Spacer()

                        TextField("", text: $fullName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.primary)
                            // No `.textContentType(.name)`: the name-autofill content type is
                            // what makes iOS draw the grey autofill highlight behind the field,
                            // and there's no API to keep autofill while hiding that box. Dropping
                            // it lets the field sit flush on the page background in both modes.
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
                            Text("Major")
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

                    // Graduation Year
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
                            Text("Class of")
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
                // Card fill in light mode only. In dark mode the grouped-background
                // grey reads as an unwanted bubble around the fields, so drop it and let
                // the fields sit directly on the base background.
                .background(colorScheme == .dark ? Color.clear : Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Spacer(minLength: 155)

                // Next button
                Button {
                    // Check if name already exists
                    let fullNameTrimmed = fullName.trimmingCharacters(in: .whitespaces)
                    let existingProjects = findProjectsForName(fullNameTrimmed)

                    if !existingProjects.isEmpty {
                        // Show "Is this you?" sheet
                        existingUserMatch = ExistingUserMatch(name: fullNameTrimmed, projects: existingProjects)
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
        // The whole page fits on screen, so keep it fixed — don't let it scroll or
        // bounce when the keyboard pushes up for the name field.
        .scrollDisabled(true)
        // Push from the right (like the cast/crew screens in the submission views)
        // instead of sliding up as a sheet. `.tint(.primary)` keeps the back arrow the
        // adaptive black/white color rather than the app's orange accent.
        .navigationDestination(isPresented: $showMajorSelection) {
            MajorSelectionView(selectedMajor: $profileModel.major)
                .tint(.primary)
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

    // MARK: - Helper Methods

    private func findProjectsForName(_ name: String) -> [Submission] {
        var projects: [Submission] = []

        // Search only the live feed. `store.submissions` is the deleted/hidden
        // bucket, so it's intentionally excluded — deleted projects don't count.
        // Only credited creative works count here — films, music, and reels. Events
        // and projects are excluded from the "Is this you?" match.
        let allSubmissions = store.approvedSubmissions.filter {
            $0.type == .film || $0.type == .music || $0.type == .reel
        }

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
}

// MARK: - Industry Professional Details

struct IndustryDetailsView: View {
    @ObservedObject var profileModel: UserProfileModel

    /// Raw "First Last" input, owned by `OnboardingView`.
    @Binding var fullName: String

    /// Opens the crop/zoom adjuster, presented by `OnboardingView`.
    @Binding var showImageAdjustment: Bool

    /// Saves the profile and finishes onboarding.
    let onComplete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Validation

    /// Industry-professional account details are complete when the name, all three
    /// industry fields, and a profile photo are provided.
    private var isIndustryDetailsValid: Bool {
        let nameValid = !fullName.trimmingCharacters(in: .whitespaces).isEmpty
        let industryValid = !profileModel.industry.trimmingCharacters(in: .whitespaces).isEmpty
        let companyValid = !profileModel.company.trimmingCharacters(in: .whitespaces).isEmpty
        let roleValid = !profileModel.companyRole.trimmingCharacters(in: .whitespaces).isEmpty
        let photoValid = profileModel.profileImage != nil
        return nameValid && industryValid && companyValid && roleValid && photoValid
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create Your Account")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Automatically saves with Apple ID")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                // Profile Picture Section
                OnboardingProfilePicturePicker(
                    profileModel: profileModel,
                    showImageAdjustment: $showImageAdjustment
                )

                // Form fields
                VStack(spacing: 0) {
                    industryField(title: "First & Last Name", text: $fullName)

                    Divider().padding(.leading, 16)

                    industryField(title: "Industry", text: $profileModel.industry)

                    Divider().padding(.leading, 16)

                    industryField(title: "Company", text: $profileModel.company)

                    Divider().padding(.leading, 16)

                    industryField(title: "Company Role", text: $profileModel.companyRole)
                }
                // Card fill in light mode only (matches CreateProfileView).
                .background(colorScheme == .dark ? Color.clear : Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Spacer(minLength: 60)

                // Create Account button — industry pros skip the tags step.
                Button {
                    onComplete()
                } label: {
                    Text("Create Account")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isIndustryDetailsValid ? Color.brandOrange : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!isIndustryDetailsValid)
            }
            .padding(.horizontal, 24)
        }
        // The whole page fits on screen, so keep it fixed like CreateProfileView.
        .scrollDisabled(true)
    }

    /// A single labeled text field row for the industry account-details card.
    /// Uses `axis: .vertical` so single-line fields don't get iOS's autofill fill
    /// drawn behind them.
    private func industryField(title: String, text: Binding<String>) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            TextField("", text: text, axis: .vertical)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
                .autocorrectionDisabled()
                .textContentType(nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Shared Profile Picture Picker

/// Profile-photo picker shared by the UT-student and industry onboarding pages.
/// Applies the saved zoom/position crop to the preview and lets the user
/// re-open the adjuster, matching EditProfileView.
struct OnboardingProfilePicturePicker: View {
    @ObservedObject var profileModel: UserProfileModel

    /// Opens the crop/zoom adjuster, presented by `OnboardingView`.
    @Binding var showImageAdjustment: Bool

    @State private var selectedPhotoItem: PhotosPickerItem?

    // Profile picture crop (zoom & position), shared with EditProfileView via
    // these AppStorage keys so the chosen crop persists into the profile.
    @AppStorage("profileImageOffsetX") private var profileImageOffsetX: Double = 0
    @AppStorage("profileImageOffsetY") private var profileImageOffsetY: Double = 0
    @AppStorage("profileImageScale") private var profileImageScale: Double = 1.0

    var body: some View {
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
                    Text(hasImage ? "Change Photo" : "Choose Photo")
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
}

#Preview("Create Profile (UT Student)") {
    @Previewable @State var fullName = ""
    @Previewable @State var currentPage = 1
    @Previewable @State var existingUserMatch: ExistingUserMatch?
    @Previewable @State var showImageAdjustment = false
    NavigationStack {
        CreateProfileView(
            profileModel: UserProfileModel(),
            fullName: $fullName,
            currentPage: $currentPage,
            existingUserMatch: $existingUserMatch,
            showImageAdjustment: $showImageAdjustment
        )
    }
}

#Preview("Industry Details") {
    @Previewable @State var fullName = ""
    @Previewable @State var showImageAdjustment = false
    NavigationStack {
        IndustryDetailsView(
            profileModel: UserProfileModel(),
            fullName: $fullName,
            showImageAdjustment: $showImageAdjustment,
            onComplete: {}
        )
    }
}

#Preview("Profile Picture Picker") {
    @Previewable @State var showImageAdjustment = false
    OnboardingProfilePicturePicker(
        profileModel: UserProfileModel(),
        showImageAdjustment: $showImageAdjustment
    )
    .padding()
}
