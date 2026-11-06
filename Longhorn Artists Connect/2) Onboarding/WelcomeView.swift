//
//  WelcomeView.swift
//  Longhorn Artists Connect
//
//  Onboarding page 1: the "Welcome to Nexus" screen where the user declares which
//  kind of account they're creating — student, industry professional, or guest
//  (the "Guest" button in the upper right). The "?" in the upper left explains
//  LAC and Nexus.
//  Each choice sets the matching flags on `profileModel` and routes onward
//  (students go to `SchoolSelectionView` first).
//  Extracted from OnboardingView.swift.
//

import SwiftUI

struct WelcomeView: View {
    @ObservedObject var profileModel: UserProfileModel

    /// The onboarding page index, owned by `OnboardingView`.
    @Binding var currentPage: Int

    /// Saves the profile and finishes onboarding. Used by the Guest path, which
    /// skips account details entirely.
    let onComplete: () -> Void

    /// Drives the "?" sheet describing LAC and Nexus.
    @State private var showAbout = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: UIScreen.main.bounds.height * 0.15) // 2/3 of the way down is ~15% from top

            // Welcome header
            VStack(spacing: 8) {
                Text("Welcome to")
                    .font(.title)
                    .foregroundStyle(.secondary)

                SchoolAssetImage("NexusOrange")
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
                    // Students pick their school on the next page (page 5), which
                    // then continues down the student path.
                    withAnimation {
                        currentPage = 5
                    }
                } label: {
                    Text("I am a Student")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandOrange)
                        .cornerRadius(12)
                }

                Button {
                    // Industry professionals are restricted accounts (no sharing) with a
                    // real profile. Route to a dedicated details page (page 3) that
                    // collects Industry / Company / Company Role instead of academics.
                    profileModel.isIndustryProfessional = true
                    profileModel.isUTStudent = false
                    profileModel.isGuest = false
                    profileModel.accountKind = nil
                    withAnimation {
                        currentPage = 3
                    }
                } label: {
                    Text("I'm an Industry Professional")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        // Mid-strength orange: between the solid UT button and the light
                        // Guest tint.
                        .background(Color.brandOrange.opacity(0.55))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .toolbar {
            // What LAC and Nexus are.
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showAbout = true
                } label: {
                    Image(systemName: "questionmark")
                        .foregroundStyle(Color.brandOrange)
                }
                .accessibilityLabel("About LAC and Nexus")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Guests skip account details entirely — no name or photo — and go
                    // straight into the app.
                    profileModel.isUTStudent = false
                    profileModel.isGuest = true
                    profileModel.accountKind = nil
                    onComplete()
                } label: {
                    Text("Guest")
                        .font(.headline)
                        .foregroundStyle(Color.brandOrange)
                }
            }
        }
        .sheet(isPresented: $showAbout) {
            AboutNexusView()
        }
    }
}

// MARK: - About LAC & Nexus

/// The copy for the Welcome page's "?" sheet. Fill these in — they're empty
/// on purpose so no placeholder wording ships.
enum AboutNexusText {
    static let lac = ""
    static let nexus = ""
}

/// Opened from the "?" on the Welcome page: what Longhorn Artists Connect and
/// Nexus are.
struct AboutNexusView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section(title: "Longhorn Artists Connect", body: AboutNexusText.lac)
                    section(title: "Nexus", body: AboutNexusText.nexus)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            if !body.isEmpty {
                Text(body)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    @Previewable @State var currentPage = 0
    NavigationStack {
        WelcomeView(
            profileModel: UserProfileModel(),
            currentPage: $currentPage,
            onComplete: {}
        )
    }
}
