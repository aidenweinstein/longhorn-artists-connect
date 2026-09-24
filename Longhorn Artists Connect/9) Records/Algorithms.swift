//
//  Algorithms.swift
//  Longhorn Artists Connect
//
//  Content-recommendation algorithms for the Home and Discover feeds.
//
//  v1 ranking (both feeds): order by like count (most-liked first). Posts with the same
//  like count are placed in a random order. Once the viewer opens a post it's marked
//  "seen"; on the next reload every seen post sinks below the unseen ones (the seen group
//  is itself ordered most-to-least liked). Newly-opened posts only move on the *next*
//  reload — the current ordering uses a snapshot taken when the feed loaded — so a post
//  doesn't jump away under the user's finger right after they tap it.
//
//  After a few pull-to-refreshes the Home feed drops the ranking entirely and serves
//  posts in a completely random order (see `refreshesBeforeFullRandom` / `shuffle`), so
//  repeatedly refreshing keeps surfacing different posts instead of the same top set.
//

import Foundation
import Combine

// MARK: - Seeded RNG

/// A deterministic random number generator (SplitMix64). Seeding it once per feed load
/// keeps the random tie-breaking order stable across SwiftUI body re-evaluations, while a
/// fresh seed on the next reload re-randomizes equal-like-count posts.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Seen Content Tracker

/// Records which posts the viewer has opened, persisted on-device so the "seen" state
/// survives relaunches. The feed reads a *snapshot* of this at load time for ordering;
/// `markSeen` records opens that take effect on the next reload.
@MainActor
final class SeenContentTracker: ObservableObject {
    static let shared = SeenContentTracker()

    @Published private(set) var seenIDs: Set<UUID> = []

    private let defaultsKey = "seenContentIDs"

    private init() { load() }

    /// Marks a post as seen (idempotent) and persists. Takes effect on the next reload.
    func markSeen(_ id: UUID) {
        guard !seenIDs.contains(id) else { return }
        seenIDs.insert(id)
        save()
    }

    func isSeen(_ id: UUID) -> Bool { seenIDs.contains(id) }

    /// A copy of the current seen set — capture this when the feed loads so ordering is
    /// stable until the next reload.
    func snapshot() -> Set<UUID> { seenIDs }

    /// Clears all seen history (e.g. on sign-out).
    func reset() {
        seenIDs = []
        save()
    }

    private func load() {
        let stored = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        seenIDs = Set(stored.compactMap(UUID.init(uuidString:)))
    }

    private func save() {
        UserDefaults.standard.set(seenIDs.map(\.uuidString), forKey: defaultsKey)
    }
}

// MARK: - Content Recommender

enum ContentRecommender {

    /// Ranks feed items for recommendation.
    ///
    /// - Unseen posts come first, then seen posts (using `seenIDs`, which the caller
    ///   should snapshot at load time).
    /// - Within each group, higher like counts rank above lower ones.
    /// - Posts with the same like count are randomized using `seed` — stable for a given
    ///   seed, re-randomized when the caller supplies a new seed on reload.
    ///
    /// Generic over the item type so both `Submission` feeds (and any future model) can
    /// use it; the caller supplies how to read the id and like count.
    static func rank<Item>(
        _ items: [Item],
        id: (Item) -> UUID,
        likeCount: (Item) -> Int,
        seenIDs: Set<UUID>,
        seed: UInt64
    ) -> [Item] {
        // Shuffle first so equal-like-count items have a random baseline order, then use
        // the shuffled position as a total tiebreak. A plain `sorted` isn't guaranteed
        // stable, so folding the shuffle index into the comparator is what preserves the
        // random tie order deterministically.
        var rng = SeededGenerator(seed: seed)
        let shuffled = items.shuffled(using: &rng).enumerated()

        return shuffled.sorted { a, b in
            let seenA = seenIDs.contains(id(a.element))
            let seenB = seenIDs.contains(id(b.element))
            if seenA != seenB { return !seenA }          // unseen before seen

            let likesA = likeCount(a.element)
            let likesB = likeCount(b.element)
            if likesA != likesB { return likesA > likesB } // more likes first

            return a.offset < b.offset                     // random, stable tiebreak
        }
        .map(\.element)
    }

    /// How many refreshes a feed serves the ranked order before switching to a completely
    /// random order. Once the viewer has refreshed this many times, every further refresh
    /// reshuffles the whole feed with no like-count or seen-state weighting.
    static let refreshesBeforeFullRandom = 3

    /// A completely random ordering — no like counts, no seen-state sinking. Stable for a
    /// given `seed` so SwiftUI body re-evaluations don't reshuffle under the user; pass a
    /// fresh seed on each reload to re-randomize.
    static func shuffle<Item>(_ items: [Item], seed: UInt64) -> [Item] {
        var rng = SeededGenerator(seed: seed)
        return items.shuffled(using: &rng)
    }

    /// A fresh seed for a feed reload. Callers hold this in view state and regenerate it
    /// each time the page reloads so tie order re-randomizes.
    static func freshSeed() -> UInt64 { UInt64.random(in: .min ... .max) }
}
