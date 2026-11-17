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

    /// Titles of the placeholder posts that keep coming back under record IDs other
    /// than the fixed ones above. Hardcoded so they never show, whatever their ID.
    /// Compared lowercased and trimmed. (A real post with one of these exact titles
    /// would be hidden too.)
    static let placeholderTitles: Set<String> = [
        "morgan taylor - acting reel 2026",
        "the midnight garden",
        "neon dreams",
    ]

    /// Whether this submission is one of the legacy placeholder posts.
    var isPlaceholder: Bool {
        if Submission.placeholderIDs.contains(id) { return true }
        let normalized = title
            .replacingOccurrences(of: "\u{2013}", with: "-")   // en dash
            .replacingOccurrences(of: "\u{2014}", with: "-")   // em dash
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return Submission.placeholderTitles.contains(normalized)
    }
}
