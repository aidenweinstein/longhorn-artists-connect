//
//  UserTypePage.swift
//  Longhorn Artists Connect
//
//  Onboarding page shown after school selection: the user says whether they're
//  an Artist or an Enthusiast (see `AccountKind` for what each gets).
//

import SwiftUI

struct UserTypePage: View {
    @ObservedObject var profileModel: UserProfileModel

    /// The onboarding page index, owned by `OnboardingView`.
    @Binding var currentPage: Int

    /// Saves the profile and finishes onboarding. Used by the Enthusiast path,
    /// which skips account details like Guest does.
    let onComplete: () -> Void

    var body: some View {
        // Same layout as SchoolSelectionView: buttons centered in the full page,
        // header overlaid at the top so it doesn't push them off-center.
        VStack(spacing: 16) {
            ForEach(AccountKind.allCases) { kind in
                kindButton(kind)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            Text("I am a...")
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
        }
    }

    /// A button for one kind, in the colors of the school picked on the
    /// previous page (see SchoolColors.swift).
    private func kindButton(_ kind: AccountKind) -> some View {
        let theme = SchoolTheme.forSchool(profileModel.school)
        return Button {
            select(kind)
        } label: {
            HStack(spacing: 10) {
                Text(kind.icon)
                Text(kind.rawValue)
            }
            .font(.headline)
            .foregroundStyle(theme.text)
            .frame(maxWidth: .infinity)
            .padding()
            .background(theme.bubble)
            .cornerRadius(12)
        }
    }

    private func select(_ kind: AccountKind) {
        profileModel.accountKind = kind
        switch kind {
        case .artist:
            // The full student path.
            profileModel.isUTStudent = true
            profileModel.isGuest = false
            withAnimation {
                // Verify the school email first: finding out they're ineligible
                // here costs them nothing. Falls through to details when the
                // service is absent, or in development builds where
                // verification isn't required.
                let showsVerification = StudentVerificationManager.isUIAvailable
                    && StudentVerificationManager.isRequired
                currentPage = showsVerification ? 4 : 1
            }
        case .enthusiast:
            // The Guest experience — no details, no sharing or messaging — but
            // kept to the school picked on the previous page (see `SchoolScope`).
            profileModel.isUTStudent = false
            profileModel.isGuest = true
            onComplete()
        }
    }
}

#Preview {
    @Previewable @State var currentPage = 6
    NavigationStack {
        UserTypePage(
            profileModel: UserProfileModel(),
            currentPage: $currentPage,
            onComplete: {}
        )
    }
}
