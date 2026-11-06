//
//  ProfileStylePage.swift
//  Longhorn Artists Connect
//
//  Onboarding's last step for artists: pick the base profile — Filmmaker, Actor or
//  Musician. Required; the account isn't created until one is chosen.
//
//  The choice decides what Nexus recommends, what the Now page in Discover shows,
//  and how the profile looks to everyone else (see ProfileStyle.swift). It can be
//  changed later from the Portfolio or Now page.
//

import SwiftUI

struct ProfileStylePage: View {
    @ObservedObject var profileModel: UserProfileModel

    /// Saves the profile and finishes onboarding.
    let onComplete: () -> Void

    /// The style under the finger. Starts on the one the role tags suggest, so most
    /// people only have to confirm.
    @State private var selected: ProfileStyle?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Choose Your Base Profile")
                                .font(.title)
                                .fontWeight(.bold)

                            Image(systemName: "person.crop.rectangle.stack")
                                .font(.title)
                                .foregroundStyle(Color.brandOrange)
                        }

                        Text("This shapes what Nexus recommends to you, what the Now page shows, and how your profile looks to everyone else. You can change it later.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)

                    VStack(spacing: 12) {
                        ForEach(ProfileStyle.allCases) { style in
                            styleCard(style)
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24)
            }

            // Bottom button
            Button {
                guard let selected else { return }
                profileModel.profileStyle = selected
                onComplete()
            } label: {
                Text("Explore the Nexus!")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selected == nil ? Color.gray : Color.brandOrange)
                    .cornerRadius(12)
            }
            .disabled(selected == nil)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .onAppear {
            if selected == nil {
                selected = profileModel.profileStyle ?? ProfileStyle.suggested(for: profileModel.userTypes)
            }
        }
    }

    /// One selectable style: icon, name, one-line pitch, and a "Suggested" chip on the
    /// one the role tags point to.
    private func styleCard(_ style: ProfileStyle) -> some View {
        let isSelected = selected == style
        let isSuggested = ProfileStyle.suggested(for: profileModel.userTypes) == style
        return Button {
            selected = style
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: style.symbol)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundStyle(isSelected ? Color.white : Color.brandOrange)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(style.rawValue)
                            .font(.headline)
                        if isSuggested {
                            Text("Suggested")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    (isSelected ? Color.white : Color.brandOrange).opacity(0.18),
                                    in: Capsule()
                                )
                        }
                    }
                    Text(style.pitch)
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                        .opacity(isSelected ? 0.9 : 0.7)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .padding(.top, 2)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.brandOrange : Color(uiColor: .systemGroupedBackground))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Profile Style") {
    NavigationStack {
        ProfileStylePage(profileModel: UserProfileModel(), onComplete: {})
    }
}
