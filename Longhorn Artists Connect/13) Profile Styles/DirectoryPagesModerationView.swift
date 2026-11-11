//
//  DirectoryPagesModerationView.swift
//  Longhorn Artists Connect
//
//  The "Directory" section on the Moderate page. Each row opens one of the Network
//  directory's group pages (Actors / Filmmakers / Musicians) in moderator form:
//  who's listed there, swipe to remove, and a "+" to add anyone from the user
//  list. Every change writes `directoryGroups` on the person's `UserProfile`
//  record through `UserProfileManager.setDirectoryGroups`, the same path the
//  long-press toggles in Moderate › Users use.
//

import SwiftUI
import UIKit

// MARK: - Moderate Page Section

/// Three rows — Actors, Filmmakers, Musicians — each with how many people are
/// listed on that page. Sits in the Moderate page's list under Schools.
struct ModeratorDirectorySection: View {
    @ObservedObject private var people = UserProfileManager.shared

    var body: some View {
        Section {
            ForEach(CreativeGroup.allCases) { group in
                NavigationLink {
                    DirectoryPageMembersView(group: group)
                } label: {
                    HStack {
                        Label(group.plural, systemImage: group.symbol)
                        Spacer()
                        Text("\(count(for: group))")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Enthusiasts aren't in the directory; this is the only place they're listed.
            NavigationLink {
                EnthusiastListView()
            } label: {
                HStack {
                    Label("Enthusiasts", systemImage: "popcorn")
                    Spacer()
                    Text("\(people.enthusiasts.count)")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Directory")
        } footer: {
            Text("Choose who appears on the Actors, Filmmakers and Musicians pages in Network. Everyone is listed on Everyone regardless of these picks.")
        }
    }

    private func count(for group: CreativeGroup) -> Int {
        people.allUsers.filter { $0.directoryGroups.contains(group.rawValue) }.count
    }
}

// MARK: - Enthusiasts

/// Moderator-only list of enthusiast accounts, which are hidden from the
/// directory and from everyone else.
struct EnthusiastListView: View {
    @ObservedObject private var people = UserProfileManager.shared

    private var sorted: [DirectoryUser] {
        people.enthusiasts.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    var body: some View {
        List {
            if sorted.isEmpty {
                Text("No enthusiasts yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sorted) { user in
                    Text(user.displayName)
                }
            }
        }
        .navigationTitle("Enthusiasts")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await people.fetchAllUsers(forceRefresh: true)
        }
    }
}

// MARK: - Members of One Page

/// Everyone a moderator has put on one directory page. Swipe left to take them
/// off; the "+" button opens the picker to add more.
struct DirectoryPageMembersView: View {
    let group: CreativeGroup

    @ObservedObject private var people = UserProfileManager.shared
    @State private var showPicker = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    /// IDs of people whose change is still being written, so the row shows a spinner.
    @State private var pendingIDs: Set<String> = []

    private var members: [DirectoryUser] {
        people.allUsers
            .filter { $0.directoryGroups.contains(group.rawValue) }
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    var body: some View {
        List {
            if members.isEmpty {
                Section {
                    Text(isRefreshing ? "Loading users…" : "Nobody is on the \(group.plural) page yet.")
                        .foregroundStyle(.secondary)
                    Button {
                        showPicker = true
                    } label: {
                        Label("Add People", systemImage: "person.badge.plus")
                    }
                }
            } else {
                Section {
                    ForEach(members) { user in
                        DirectoryModerationPersonRow(user: user, isPending: pendingIDs.contains(user.id))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    remove(user)
                                } label: {
                                    Label("Remove", systemImage: "person.badge.minus")
                                }
                            }
                    }
                } footer: {
                    Text("\(members.count) \(members.count == 1 ? "person" : "people") on the \(group.plural) page. Swipe left to remove someone.")
                }
            }
        }
        .navigationTitle(group.plural)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showPicker = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            DirectoryPagePeoplePicker(group: group)
        }
        .alert("Couldn't Update", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func refresh() async {
        isRefreshing = true
        await people.fetchAllUsers(forceRefresh: true)
        isRefreshing = false
    }

    private func remove(_ user: DirectoryUser) {
        var groups = Set(user.directoryGroups)
        groups.remove(group.rawValue)
        pendingIDs.insert(user.id)
        Task {
            let message = await people.setDirectoryGroups(user, groups: groups)
            pendingIDs.remove(user.id)
            if let message { errorMessage = message }
        }
    }
}

// MARK: - Add People Picker

/// Searchable list of everyone not yet on the page. People whose own tags match
/// the group (e.g. tagged Actor for the Actors page) are suggested first, but
/// anyone can be added. Tapping a person adds them straight away.
struct DirectoryPagePeoplePicker: View {
    let group: CreativeGroup

    @ObservedObject private var people = UserProfileManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var pendingIDs: Set<String> = []

    /// Everyone not already on this page, filtered by the search field.
    private var candidates: [DirectoryUser] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return people.allUsers
            .filter { !$0.directoryGroups.contains(group.rawValue) }
            .filter { user in
                guard !query.isEmpty else { return true }
                return user.displayName.lowercased().contains(query)
                    || user.rolesString.lowercased().contains(query)
                    || user.major.lowercased().contains(query)
            }
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    /// Candidates whose role tags fall in this group.
    private var suggested: [DirectoryUser] {
        candidates.filter { CreativeGroup.groups(forTagNames: $0.userTypes).contains(group) }
    }

    private var others: [DirectoryUser] {
        candidates.filter { !CreativeGroup.groups(forTagNames: $0.userTypes).contains(group) }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    Text(searchText.isEmpty ? "Everyone is already on this page." : "No one matches “\(searchText)”.")
                        .foregroundStyle(.secondary)
                } else {
                    if !suggested.isEmpty {
                        Section {
                            ForEach(suggested) { user in
                                addRow(user)
                            }
                        } header: {
                            Text("Tagged \(group.tagList)")
                        }
                    }
                    if !others.isEmpty {
                        Section {
                            ForEach(others) { user in
                                addRow(user)
                            }
                        } header: {
                            Text(suggested.isEmpty ? "Everyone" : "Everyone else")
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search by name or role")
            .navigationTitle("Add to \(group.plural)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn't Update", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDragIndicator(.hidden)
    }

    private func addRow(_ user: DirectoryUser) -> some View {
        Button {
            add(user)
        } label: {
            HStack {
                DirectoryModerationPersonRow(user: user, isPending: pendingIDs.contains(user.id))
                Spacer(minLength: 8)
                if !pendingIDs.contains(user.id) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.brandOrange)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(pendingIDs.contains(user.id))
    }

    private func add(_ user: DirectoryUser) {
        var groups = Set(user.directoryGroups)
        groups.insert(group.rawValue)
        pendingIDs.insert(user.id)
        Task {
            let message = await people.setDirectoryGroups(user, groups: groups)
            pendingIDs.remove(user.id)
            if let message { errorMessage = message }
        }
    }
}

// MARK: - Row

/// Photo (or initials), name, roles, and which other pages the person is on.
struct DirectoryModerationPersonRow: View {
    let user: DirectoryUser
    var isPending = false

    private var otherPages: [CreativeGroup] {
        CreativeGroup.ordered(Set(user.directoryGroups.compactMap(CreativeGroup.init(rawValue:))))
    }

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.displayName)
                        .font(.headline)
                    if !user.isUTStudent {
                        Text("Guest")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.brandOrange.opacity(0.2))
                            .foregroundStyle(Color.brandOrange)
                            .clipShape(Capsule())
                    }
                }
                if !user.rolesString.isEmpty {
                    Text(user.rolesString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !otherPages.isEmpty {
                    Text("On: " + otherPages.map(\.plural).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            if isPending {
                Spacer()
                ProgressView()
            }
        }
        .padding(.vertical, 2)
    }

    private var avatar: some View {
        Group {
            if let data = user.profileImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color.brandOrange.opacity(0.15))
                    .overlay {
                        Text(user.initials)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.brandOrange)
                    }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }
}
