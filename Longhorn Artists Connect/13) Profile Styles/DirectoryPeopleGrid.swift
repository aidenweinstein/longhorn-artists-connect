//
//  DirectoryPeopleGrid.swift
//  Longhorn Artists Connect
//
//  The Network directory's four tabs — Everyone, Actors, Filmmakers, Musicians — and
//  the large-photo grid each one shows: two cards across on iPhone, three on wider
//  screens, like the website's people pages. Membership in the three group tabs is
//  by role tag (see CreativeGroup.swift); nothing is curated by hand.
//

import SwiftUI
import UIKit

// MARK: - Tabs

enum DirectoryTab: String, CaseIterable, Identifiable {
    case everyone = "Everyone"
    case actors = "Actors"
    case filmmakers = "Filmmakers"
    case musicians = "Musicians"

    var id: String { rawValue }

    /// The tag group this tab lists, or nil for Everyone.
    var group: CreativeGroup? {
        switch self {
        case .everyone: return nil
        case .actors: return .actor
        case .filmmakers: return .filmmaker
        case .musicians: return .musician
        }
    }

    init(group: CreativeGroup) {
        switch group {
        case .actor: self = .actors
        case .filmmaker: self = .filmmakers
        case .musician: self = .musicians
        }
    }

    /// Whether a directory user belongs on this tab.
    func includes(_ user: DirectoryUser) -> Bool {
        guard let group else { return true }
        return CreativeGroup.groups(forTagNames: user.userTypes).contains(group)
    }
}

// MARK: - Grid

/// Large photo cards, two or three across depending on width.
struct DirectoryPeopleGrid: View {
    let users: [DirectoryUser]
    let tab: DirectoryTab
    let onSelect: (DirectoryUser) -> Void

    @ObservedObject private var creative = CreativeProfileStore.shared
    @State private var width: CGFloat = 0

    private var columns: Int {
        width >= 700 ? 3 : 2
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: columns),
                  spacing: 16) {
            ForEach(users) { user in
                DirectoryPersonCard(
                    user: user,
                    image: image(for: user),
                    subtitle: subtitle(for: user)
                ) {
                    onSelect(user)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// Actors tab shows the uploaded headshot when there is one; everything else uses
    /// the profile photo.
    private func image(for user: DirectoryUser) -> UIImage? {
        if tab == .actors, let headshot = creative.headshot(forUserID: user.id) {
            return headshot
        }
        return user.profileImageData.flatMap { UIImage(data: $0) }
    }

    private func subtitle(for user: DirectoryUser) -> String {
        let details = creative.profile(forUserID: user.id)?.details
        switch tab {
        case .actors:
            if let actor = details?.actor {
                let line = [actor.ageRangeText, actor.gender, actor.basedIn].filter { !$0.isEmpty }.joined(separator: " · ")
                if !line.isEmpty { return line }
            }
        case .musicians:
            if let musician = details?.musician {
                let line = [musician.artistName, musician.genres].filter { !$0.isEmpty }.joined(separator: " · ")
                if !line.isEmpty { return line }
            }
        case .filmmakers:
            // Just their film roles, so a Director / Actor reads "Director" here.
            let film = user.userTypes.filter { name in
                UserType(rawValue: name).map { CreativeGroup.filmmaker.tags.contains($0) } ?? false
            }
            if !film.isEmpty { return film.joined(separator: ", ") }
        case .everyone:
            break
        }
        if user.isIndustryProfessional {
            return [user.companyRole, user.company].filter { !$0.isEmpty }.joined(separator: " • ")
        }
        return user.rolesString
    }
}

/// One person: a tall photo with their name and a line underneath.
struct DirectoryPersonCard: View {
    let user: DirectoryUser
    let image: UIImage?
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Color.secondary.opacity(0.12)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Text(user.initials)
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(Color.brandOrange)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        // Class year chip, students only.
                        if !user.isIndustryProfessional, !user.graduationYear.isEmpty {
                            Text("'\(String(user.graduationYear.suffix(2)))")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(8)
                        }
                    }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(user.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    UserVerifiedBadge(userID: user.id)
                        .font(.caption)
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
