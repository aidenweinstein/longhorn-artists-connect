//
//  SchoolRegistry.swift
//  Longhorn Artists Connect
//
//  The schools a post can belong to, by display name and `schoolID` slug. Shared
//  by the iPhone app (through `SchoolScope`) and the Apple TV app, which has none
//  of `SchoolScope`'s account logic.
//

import Foundation

enum SchoolRegistry {

    /// The school every post created before the multi-school split belongs to,
    /// and what an unstamped post counts as. Must match the backfill's
    /// `BACKFILL_DEFAULT_SCHOOL`.
    static let legacyDefault = "ut-austin"

    /// Display name and registry slug for every school, in picker order. The
    /// display names match `SchoolTheme`'s canonical names and
    /// `UserProfileModel.utSchoolName` / `berkeleySchoolName`.
    static let schools: [(name: String, slug: String)] = [
        ("The University of Texas at Austin", legacyDefault),
        ("University of California, Berkeley", "berkeley"),
        ("University of Michigan", "umich"),
        ("USC", "usc"),
        ("Cal Poly SLO", "calpoly-slo"),
        ("NYU", "nyu"),
        ("DePaul", "depaul"),
        ("BU", "bu"),
        ("Texas A&M", "tamu"),
        ("Ohio State", "ohio-state"),
        ("UVA", "uva"),
        ("UC Santa Barbara", "ucsb"),
        ("Northwestern", "northwestern")
    ]

    /// The display name for a post's `schoolID`. An empty or missing stamp is
    /// `legacyDefault`; an unregistered slug comes back as itself.
    static func name(forSlug slug: String?) -> String {
        let slug = slug.flatMap { $0.isEmpty ? nil : $0 } ?? legacyDefault
        return schools.first { $0.slug == slug }?.name ?? slug
    }
}
