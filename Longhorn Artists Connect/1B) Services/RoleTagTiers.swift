//
//  RoleTagTiers.swift
//  Longhorn Artists Connect
//
//  The role tag chips drawn on portfolios. Everyone picks up to five tags in
//  onboarding and each one is shown as a plain chip in the person's school colors.
//  (An earlier version ranked tags into metallic tiers by credit count; that
//  ranking has been removed, so the chips carry no numbers.)
//

import SwiftUI

// MARK: - Role Tag Chip

/// One role tag on a portfolio, drawn in the person's school colors.
struct RoleTagBubble: View {
    let tag: String
    /// The person's school theme.
    let theme: SchoolTheme

    var body: some View {
        Text(tag)
            .font(.subheadline)
            .foregroundStyle(theme.text)
            // ====== UI CONTROLS!!!!! ======
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(theme.bubble)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            // ==============================
            .accessibilityLabel(tag)
    }
}

// MARK: - Previews

#Preview("Role Tags") {
    let theme = SchoolTheme.forSchool("The University of Texas at Austin")
    return VStack(spacing: 14) {
        RoleTagBubble(tag: "Director", theme: theme)
        RoleTagBubble(tag: "Editor", theme: theme)
        RoleTagBubble(tag: "Cinematographer", theme: theme)
    }
    .padding()
}

#Preview("Berkeley") {
    let theme = SchoolTheme.forSchool("University of California, Berkeley")
    return HStack(spacing: 6) {
        RoleTagBubble(tag: "Writer", theme: theme)
        RoleTagBubble(tag: "Producer", theme: theme)
    }
    .padding()
}
