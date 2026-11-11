//
//  SchoolSelectionView.swift
//  Longhorn Artists Connect
//
//  Onboarding page shown after Create Account or Sign In: the user picks their
//  school from `OnboardingSchool.all`. `OnboardingView` decides what's next.
//

import SwiftUI

struct SchoolSelectionView: View {
    let onSelect: (OnboardingSchool) -> Void

    var body: some View {
        // The buttons are centered in the full page; the header is overlaid at
        // the top so it doesn't push them off-center.
        VStack(spacing: 16) {
            ForEach(OnboardingSchool.all) { school in
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
    private func schoolButton(_ school: OnboardingSchool) -> some View {
        let theme = SchoolTheme.forSchool(school.name)
        return Button {
            onSelect(school)
        } label: {
            Text(school.shortName)
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
    NavigationStack {
        SchoolSelectionView(onSelect: { _ in })
    }
}
