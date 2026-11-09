//
//  VerifiedBadge.swift
//  Longhorn Artists Connect
//
//  The checkmark shown beside a verified student's name, drawn in their
//  school's colors, plus the lookup that decides who gets one.
//
//  Verification is recorded in the server-owned `Verification` CloudKit record
//  (`Verification_<userRecordName>`), which every signed-in user can read but
//  only the verification service can write. Showing the badge for someone else
//  therefore means fetching their record — `VerificationBadgeStore` batches
//  those fetches and caches the answers for the session.
//

import SwiftUI
import CloudKit
import Observation

// MARK: - Badge

/// A filled seal in the school's bubble color with the checkmark in its text
/// color — the same pairing as a credited person's name chip. Inherits its
/// size from the surrounding `.font`.
struct VerifiedBadge: View {
    let theme: SchoolTheme

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(theme.text, theme.bubble)
            .accessibilityLabel("Verified student")
    }
}

extension SchoolTheme {
    /// The theme for a verified school, keyed on the registry slug the
    /// `Verification` record carries (stable) before the display name (which
    /// the service may spell differently from `SchoolColors`). Unknown schools
    /// fall back to the app's own accent.
    @MainActor
    static func forVerifiedSchool(id: String?, name: String) -> SchoolTheme {
        if let id, let registered = SchoolScope.registeredSchools.first(where: { $0.slug == id }) {
            return forSchool(registered.name)
        }
        return forSchool(name)
    }
}

// MARK: - Current user

/// The badge beside the signed-in user's own name. Reads the status
/// `StudentVerificationManager` already keeps, so nothing is fetched here.
struct CurrentUserVerifiedBadge: View {
    private var verification: StudentVerificationManager { .shared }

    var body: some View {
        ZStack {
            if case .verified(let schoolName) = verification.status {
                VerifiedBadge(theme: .forVerifiedSchool(id: verification.verifiedSchoolID, name: schoolName))
            }
        }
        .task {
            // A device that has never opened a gated screen still has the
            // launch-time `.unknown`; settle it once so the badge can appear.
            if verification.status == .unknown {
                await verification.refreshStatus()
            }
        }
    }
}

// MARK: - Other users

/// The badge beside another member's name. `userID` is their `DirectoryUser.id`
/// (`UserProfile_<userRecordName>`) or the raw user record name; `nil` — a
/// credited name with no Nexus account — shows nothing.
struct UserVerifiedBadge: View {
    let userID: String?

    private var store: VerificationBadgeStore { .shared }

    var body: some View {
        ZStack {
            if let userID, let school = store.verifiedSchool(for: userID) {
                VerifiedBadge(theme: .forVerifiedSchool(id: school.id, name: school.name))
            }
        }
        .task(id: userID) {
            if let userID { await store.load(userID) }
        }
    }
}

/// Reads other users' `Verification` records and remembers the answers.
///
/// Rows ask for one user at a time as they appear, so requests are coalesced:
/// the first ask in a burst starts a short timer, and everything asked for
/// before it fires goes out as one `records(for:)` call. Answers — including
/// "no record" — are kept for `ttl`, so a newly verified person shows their
/// badge within a few minutes without a relaunch.
@MainActor
@Observable
final class VerificationBadgeStore {

    static let shared = VerificationBadgeStore()

    /// What a `Verification` record says about the school. `id` is the
    /// registry slug; older records may only carry the display name.
    struct VerifiedSchool: Equatable {
        let id: String?
        let name: String
    }

    private struct Entry {
        let school: VerifiedSchool?
        let fetchedAt: Date
    }

    /// Keyed by raw user record name. `school == nil` means "not verified".
    private var entries: [String: Entry] = [:]

    @ObservationIgnored private var pending: Set<String> = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?

    private let ttl: TimeInterval = 15 * 60
    /// How long to collect asks before sending a batch.
    private let coalesceDelay: Duration = .milliseconds(150)
    /// Well under CloudKit's per-operation fetch limit.
    private let batchSize = 100

    private init() {}

    // MARK: Reading

    /// The verified school for a user, or `nil` when they aren't verified or
    /// haven't been looked up yet. Call `load(_:)` to look them up.
    func verifiedSchool(for userID: String) -> VerifiedSchool? {
        entries[Self.userRecordName(from: userID)]?.school
    }

    // MARK: Loading

    /// Queues a lookup for a user unless a fresh answer is already cached.
    func load(_ userID: String) async {
        let key = Self.userRecordName(from: userID)
        if let entry = entries[key], Date().timeIntervalSince(entry.fetchedAt) < ttl {
            return
        }
        pending.insert(key)
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: self?.coalesceDelay ?? .zero)
            guard let self else { return }
            let batch = self.pending
            self.pending.removeAll()
            self.flushTask = nil
            await self.fetch(Array(batch))
        }
    }

    private func fetch(_ userRecordNames: [String]) async {
        guard !userRecordNames.isEmpty else { return }
        let database = CKContainer.default().publicCloudDatabase

        for start in stride(from: 0, to: userRecordNames.count, by: batchSize) {
            let chunk = Array(userRecordNames[start..<min(start + batchSize, userRecordNames.count)])
            let ids = chunk.map { CKRecord.ID(recordName: "Verification_\($0)") }

            let results: [CKRecord.ID: Result<CKRecord, Error>]
            do {
                results = try await database.records(for: ids, desiredKeys: ["schoolID", "schoolName"])
            } catch {
                // Whole-call failure (offline, no account): leave these unknown
                // so the next appearance retries, rather than caching "unverified".
                continue
            }

            let now = Date()
            for (index, id) in ids.enumerated() {
                let key = chunk[index]
                switch results[id] {
                case .success(let record)?:
                    let schoolID = (record["schoolID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    let schoolName = (record["schoolName"] as? String) ?? ""
                    entries[key] = Entry(school: VerifiedSchool(id: schoolID, name: schoolName), fetchedAt: now)
                case .failure(let error)?:
                    // A missing record is the normal "not verified" answer.
                    // Anything else is transient; don't remember it.
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        entries[key] = Entry(school: nil, fetchedAt: now)
                    }
                case nil:
                    break
                }
            }
        }
    }

    // MARK: Helpers

    /// Strips the `UserProfile_` prefix so a directory record name and a raw
    /// user record name resolve to the same `Verification` record.
    private static func userRecordName(from userID: String) -> String {
        let prefix = "UserProfile_"
        return userID.hasPrefix(prefix) ? String(userID.dropFirst(prefix.count)) : userID
    }
}
