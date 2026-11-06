//
//  SchoolSelectionView.swift
//  Longhorn Artists Connect
//
//  Onboarding page shown after "I am a Student": the user picks their school,
//  which sets `profileModel.school` and continues down the student path.
//

import SwiftUI

struct SchoolSelectionView: View {
    @ObservedObject var profileModel: UserProfileModel

    /// The onboarding page index, owned by `OnboardingView`.
    @Binding var currentPage: Int

    /// The only schools offered for now. Each button wears its own school's colors.
    private let schools = [
        UserProfileModel.utSchoolName,
        UserProfileModel.berkeleySchoolName
    ]

    var body: some View {
        // The buttons are centered in the full page; the header is overlaid at
        // the top so it doesn't push them off-center.
        VStack(spacing: 16) {
            ForEach(schools, id: \.self) { school in
                schoolButton(school)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            Text("Select your school")
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
        }
    }

    /// A button for one school, in that school's colors (see SchoolColors.swift).
    /// Every school takes the same student path.
    private func schoolButton(_ school: String) -> some View {
        let theme = SchoolTheme.forSchool(school)
        return Button {
            profileModel.school = school
            withAnimation {
                // Next: Artist / Enthusiast (UserTypePage), which sets
                // the account flags and continues down that kind's path.
                currentPage = 6
            }
        } label: {
            Text(school)
                .font(.headline)
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding()
                .background(theme.bubble)
                .cornerRadius(12)
        }
    }
}

#Preview {
    @Previewable @State var currentPage = 5
    NavigationStack {
        SchoolSelectionView(
            profileModel: UserProfileModel(),
            currentPage: $currentPage
        )
    }
}
