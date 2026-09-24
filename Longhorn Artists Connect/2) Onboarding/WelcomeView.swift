//
//  WelcomeView.swift
//  Longhorn Artists Connect
//
//  Onboarding page 1: the "Welcome to Nexus" screen where the user declares which
//  kind of account they're creating — UT student, industry professional, or guest.
//  Each choice sets the matching flags on `profileModel` and routes onward.
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

    var body: some View {
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
                    profileModel.isGuest = false
                    profileModel.school = UserProfileModel.utSchoolName
                    withAnimation {
                        // Verify the school email first: the user has declared
                        // they're a student but hasn't typed anything yet, so
                        // finding out they're ineligible here costs them nothing.
                        // Falls through to details when the service is absent.
                        currentPage = StudentVerificationManager.isUIAvailable ? 4 : 1
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
                    // Industry professionals are restricted accounts (no sharing) with a
                    // real profile. Route to a dedicated details page (page 3) that
                    // collects Industry / Company / Company Role instead of academics.
                    profileModel.isIndustryProfessional = true
                    profileModel.isUTStudent = false
                    profileModel.isGuest = false
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

                Button {
                    // Guests skip account details entirely — no name or photo — and go
                    // straight into the app.
                    profileModel.isUTStudent = false
                    profileModel.isGuest = true
                    onComplete()
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
}
