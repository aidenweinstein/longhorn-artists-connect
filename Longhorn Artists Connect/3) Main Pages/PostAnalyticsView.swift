//
//  PostAnalyticsView.swift
//  Longhorn Artists Connect
//
//  Moderator-only engagement numbers per post, read from `NewPostView` records
//  (see PostAnalytics.swift). Artists never see any of this.
//

import SwiftUI

struct PostAnalyticsView: View {
    @ObservedObject private var store: SubmissionStore_3_2 = .shared
    @Environment(\.dismiss) private var dismiss

    @State private var range: DateRange = .week
    @State private var rows: [PostRow] = []
    @State private var totals: [PostEngagementKind: Int] = [:]
    @State private var uniquePeople = 0
    @State private var isLoading = false
    @State private var errorMessage: String?

    enum DateRange: String, CaseIterable, Identifiable {
        case week = "7 Days"
        case month = "30 Days"
        case all = "All Time"

        var id: String { rawValue }

        var startDate: Date {
            switch self {
            case .week:  return Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
            case .month: return Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
            // Well before any record, without handing CloudKit a year-0001 date.
            case .all:   return Date(timeIntervalSince1970: 0)
            }
        }
    }

    /// One post's counts. Each count is people-days: one person opening the same post
    /// on three different days counts 3 opens, but only 1 person.
    struct PostRow: Identifiable {
        let id: UUID
        let post: Submission?
        let counts: [PostEngagementKind: Int]
        let people: Int
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Range", selection: $range) {
                        ForEach(DateRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    HStack {
                        Label("People", systemImage: "person.2")
                        Spacer()
                        Text("\(uniquePeople)").fontWeight(.semibold)
                    }
                    ForEach(PostEngagementKind.allCases, id: \.self) { kind in
                        HStack {
                            Label(kind.label, systemImage: kind.icon)
                            Spacer()
                            Text("\(totals[kind] ?? 0)").fontWeight(.semibold)
                        }
                    }
                } header: {
                    Text("Totals")
                } footer: {
                    Text("Each person counts once per post, per action, per day. Posts' own creators and moderator-mode browsing aren't counted.")
                }

                Section("Posts") {
                    if rows.isEmpty && !isLoading {
                        Text(errorMessage ?? "No activity in this range yet.")
                            .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                    }
                    ForEach(rows) { row in
                        postRow(row)
                    }
                }
            }
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if isLoading && rows.isEmpty {
                    ProgressView("Loading analytics…")
                }
            }
            .task(id: range) { await load() }
            .refreshable { await load() }
        }
        .presentationDragIndicator(.hidden)
    }

    private func postRow(_ row: PostRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(row.post?.title ?? "Removed post")
                    .font(.headline)
                    .lineLimit(1)
                if let type = row.post?.type {
                    Text(type.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                Spacer()
                Label("\(row.people)", systemImage: "person.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let author = row.post?.submittedBy, !author.isEmpty {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                ForEach(PostEngagementKind.allCases, id: \.self) { kind in
                    Label("\(row.counts[kind] ?? 0)", systemImage: kind.icon)
                        .font(.caption)
                        .foregroundStyle((row.counts[kind] ?? 0) > 0 ? Color.primary : Color.secondary)
                }
            }
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let views = try await CloudKitManager.shared.fetchPostViews(since: range.startDate)
            let postsByID = Dictionary(store.submissions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            var counts: [UUID: [PostEngagementKind: Int]] = [:]
            var people: [UUID: Set<String>] = [:]
            var newTotals: [PostEngagementKind: Int] = [:]
            for view in views {
                guard let kind = PostEngagementKind(rawValue: view.kind) else { continue }
                counts[view.postID, default: [:]][kind, default: 0] += 1
                people[view.postID, default: []].insert(view.userID)
                newTotals[kind, default: 0] += 1
            }

            rows = counts
                .map { id, kindCounts in
                    PostRow(id: id, post: postsByID[id], counts: kindCounts, people: people[id]?.count ?? 0)
                }
                .sorted {
                    ($0.counts[.open] ?? 0, $0.people) > ($1.counts[.open] ?? 0, $1.people)
                }
            totals = newTotals
            uniquePeople = Set(views.map(\.userID)).count
            errorMessage = nil
        } catch {
            rows = []
            totals = [:]
            uniquePeople = 0
            errorMessage = "Couldn't load analytics: \(error.localizedDescription)"
        }
    }
}
