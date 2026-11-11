//
//  DirectoryPeopleGrid.swift
//  Longhorn Artists Connect
//
//  The Network directory's four tabs — Everyone, Actors, Filmmakers, Musicians.
//  Everyone is the plain directory list. The three group tabs are the website-style
//  people pages: a large-photo grid, two cards across on iPhone, three on wider
//  screens. Who appears on a group page is chosen by moderators
//  (`DirectoryUser.directoryGroups`, set from Moderate › Users or by long-pressing a
//  person in the directory in Moderator Mode) — not by the person's own tags.
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

    /// Whether a directory user belongs on this tab: everyone is on Everyone; the
    /// group pages list only the people a moderator has put there.
    func includes(_ user: DirectoryUser) -> Bool {
        guard let group else { return true }
        return user.directoryGroups.contains(group.rawValue)
    }
}

// MARK: - Moderator Controls

/// Moderator-only toggles for which directory pages list a person. Dropped into a
/// context menu on the person's row or card (Moderate › Users, and the directory in
/// Moderator Mode). Each change is written straight to their `UserProfile` record.
struct DirectoryGroupToggles: View {
    let user: DirectoryUser
    /// Called with a user-facing message when CloudKit refuses the change.
    var onError: (String) -> Void = { _ in }

    @ObservedObject private var people = UserProfileManager.shared

    /// The live entry, so the checkmarks update as soon as a change lands.
    private var current: Set<String> {
        Set(people.findUser(byID: user.id)?.directoryGroups ?? user.directoryGroups)
    }

    var body: some View {
        Section("Directory pages") {
            ForEach(CreativeGroup.allCases) { group in
                Toggle(isOn: Binding(
                    get: { current.contains(group.rawValue) },
                    set: { isOn in
                        var groups = current
                        if isOn { groups.insert(group.rawValue) } else { groups.remove(group.rawValue) }
                        Task {
                            if let message = await people.setDirectoryGroups(user, groups: groups) {
                                onError(message)
                            }
                        }
                    }
                )) {
                    Label(group.plural, systemImage: group.symbol)
                }
            }
        }
    }
}

// MARK: - Grid

/// Large photo cards, two or three across depending on width.
struct DirectoryPeopleGrid: View {
    let users: [DirectoryUser]
    let tab: DirectoryTab
    /// Moderator Mode: long-pressing a card offers the directory-page toggles.
    var moderatorControls = false
    var onModerationError: (String) -> Void = { _ in }
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
                .contextMenu {
                    if moderatorControls {
                        DirectoryGroupToggles(user: user, onError: onModerationError)
                    }
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
            // Age range · gender · height · hair · eyes, whichever they've filled in.
            if let actor = details?.actor, !actor.cardFacts.isEmpty {
                return actor.cardFacts.joined(separator: " · ")
            }
        case .musicians:
            if let musician = details?.musician {
                let line = [musician.artistName, musician.genres, musician.instruments]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
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
                    // Three lines: an actor's age · gender · height · hair · eyes needs the room.
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
