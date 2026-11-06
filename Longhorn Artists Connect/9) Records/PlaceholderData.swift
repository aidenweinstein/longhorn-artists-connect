//
//  PlaceholderData.swift
//  Longhorn Artists Connect
//
//  Identifies the legacy placeholder posts so they can be filtered out and purged.
//  The sample posts themselves have been removed from the app.
//

import Foundation

extension Submission {

    // MARK: - Placeholder Identification

    /// The fixed record IDs used by the placeholder posts that shipped in an early
    /// build. They were accidentally uploaded to the public CloudKit database, so
    /// the app permanently filters them out (and can purge them) by these IDs.
    static let placeholderIDs: Set<UUID> = Set((1...5).compactMap {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))
    })

    /// Whether this submission is one of the legacy placeholder posts.
    var isPlaceholder: Bool { Submission.placeholderIDs.contains(id) }
}
