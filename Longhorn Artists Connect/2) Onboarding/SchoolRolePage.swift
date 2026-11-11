//
//  SchoolRolePage.swift
//  Longhorn Artists Connect
//
//  Onboarding page shown after school selection when creating an account:
//  student, professor or alumni (see `SchoolRole`).
//

import SwiftUI

struct SchoolRolePage: View {
    /// The school picked on the previous page; its colors theme the buttons.
    let school: OnboardingSchool
    let onSelect: (SchoolRole) -> Void

    var body: some View {
        // Same layout as SchoolSelectionView: buttons centered in the full page,
        // header overlaid at the top so it doesn't push them off-center.
        VStack(spacing: 16) {
            ForEach(SchoolRole.allCases) { role in
                roleButton(role)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            Text(school.shortName)
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
        }
    }

    private func roleButton(_ role: SchoolRole) -> some View {
        let theme = SchoolTheme.forSchool(school.name)
        return Button {
            onSelect(role)
        } label: {
            Text(role.choiceLabel)
                .font(.headline)
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity)
                .padding()
                .background(theme.bubble)
                .cornerRadius(12)
        }
    }
}

#Preview {
    NavigationStack {
        SchoolRolePage(school: OnboardingSchool.all[0], onSelect: { _ in })
    }
}
