//
//  TagsView.swift
//  Longhorn Artists Connect
//
//  Onboarding's "Choose Your Tags" step for students: the user picks the roles that
//  describe them, then moves on to choose a base profile (see ProfileStylePage).
//  Extracted from OnboardingView.swift.
//

import SwiftUI

struct TagsView: View {
    @ObservedObject var profileModel: UserProfileModel

    /// The onboarding page index, owned by `OnboardingView`. Next goes to the
    /// base-profile page (7).
    @Binding var currentPage: Int

    // MARK: - Validation

    private var isTagsValid: Bool {
        !profileModel.userTypes.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Choose Your Tags")
                                .font(.title)
                                .fontWeight(.bold)

                            Image(systemName: "tag.fill")
                                .font(.title)
                                .foregroundStyle(Color.brandOrange)
                        }

                        Text("Describe yourself. Select at least one tag.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)

                    // User type options grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(UserType.allCases) { type in
                            UserTypeButton(
                                type: type,
                                isSelected: profileModel.userTypes.contains(type),
                                onTap: {
                                    toggleUserType(type)
                                }
                            )
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24)
            }

            // Bottom button — on to the base profile choice.
            Button {
                withAnimation {
                    currentPage = 7
                }
            } label: {
                Text("Next")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isTagsValid ? Color.brandOrange : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!isTagsValid)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Helper Methods

    private func toggleUserType(_ type: UserType) {
        // Enthusiast is mutually exclusive with other roles
        if type == .enthusiast {
            if profileModel.userTypes.contains(.enthusiast) {
                profileModel.userTypes.remove(.enthusiast)
            } else {
                profileModel.userTypes = [.enthusiast]
            }
        } else {
            // Remove enthusiast if selecting another role
            if profileModel.userTypes.contains(.enthusiast) {
                profileModel.userTypes.removeAll()
            }

            if profileModel.userTypes.contains(type) {
                profileModel.userTypes.remove(type)
            } else if profileModel.userTypes.count < 5 {
                profileModel.userTypes.insert(type)
            }
        }
    }
}

// MARK: - User Type Button

struct UserTypeButton: View {
    let type: UserType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(type.rawValue)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.brandOrange : Color(uiColor: .systemGroupedBackground))
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Tags") {
    @Previewable @State var currentPage = 2
    NavigationStack {
        TagsView(profileModel: UserProfileModel(), currentPage: $currentPage)
    }
}

#Preview("User Type Button") {
    VStack {
        UserTypeButton(type: .actor, isSelected: false, onTap: {})
        UserTypeButton(type: .director, isSelected: true, onTap: {})
    }
    .padding()
}
