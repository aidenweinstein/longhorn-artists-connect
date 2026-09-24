//
//  SchoolScope.swift
//  Longhorn Artists Connect
//
//  Which school's work a post belongs to, and which schools the current user sees.
//

import Foundation
import CloudKit

/// The one place that decides what `schoolID` goes on a post and what the feed
/// is allowed to show.
///
/// Every `*Submission` record carries a `schoolID` holding a stable registry
/// slug — "ut-austin", "berkeley" — the same IDs the verification service's D1
/// `schools` table uses. Sharing that vocabulary is what lets the server check a
/// post's school against its creator's `Verification` record. Display names are
/// deliberately not the key: they get reworded, slugs don't.
///
/// This is not a security control. A client writes its own submission records,
/// so it can put any `schoolID` on them; only the nightly sweep can catch a
/// mismatch. This exists so honest clients scope correctly.
@MainActor
enum SchoolScope {

    /// Field name on all seven `*Submission` record types.
    ///
    /// ⚠️ Must exist and be QUERYABLE in BOTH CloudKit environments before a
    /// build that filters on it ships, and every existing record must already
    /// be stamped. See the deployment order in verification-service/README.md
    /// ("Backfilling schoolID") — shipping the filter first hides every post.
    static let fieldKey = "schoolID"

    /// The school every post created before the multi-school split belongs to,
    /// and the fallback for a student account with no verification on file
    /// (grandfathered users). Must match the backfill's `BACKFILL_DEFAULT_SCHOOL`.
    static let legacyDefault = "ut-austin"

    // MARK: - Rollout gates

    /// Whether saves stamp `schoolID` onto a post. Flip to `true` only once the
    /// field exists on all seven `*Submission` types in BOTH environments
    /// (deployment step 1).
    ///
    /// Until then a stamp writes a field the deployed schema doesn't have, which
    /// production rejects outright — the record only publishes at all because the
    /// rescue path in `CloudKitManager` retries after dropping the field CloudKit
    /// named. A wasted round-trip on every upload, so don't stamp before the
    /// schema is there.
    static let isStampingEnabled = false

    /// Whether feeds filter to `visibleSchoolIDs`. Flip to `true` only once the
    /// field exists in both environments *and* the backfill has stamped every
    /// existing record (deployment steps 1 and 2).
    ///
    /// This is deliberately separate from `isStampingEnabled`, because the safe
    /// order requires stamping to be live for a while before filtering is: the
    /// backfill only covers records that already exist, so new posts made between
    /// the backfill and this flip must arrive already stamped.
    ///
    /// ⚠️ Enabling this too early hides every post in the app. Both failure modes
    /// were observed in this container on 2026-09-23: where the field was missing,
    /// the query itself failed with `BAD_REQUEST "Did not find field: 'schoolID'"`,
    /// and where it existed but records were unstamped, CloudKit silently returned
    /// only the stamped ones — it cannot match a field that isn't set. Verify with
    /// a `schoolID IN {…}` query against both environments before flipping.
    static let isFilteringEnabled = false

    // MARK: - The current user

    /// True for account types that have no school at all: guests and industry
    /// professionals. Neither can post, and scoping them to a school they don't
    /// have would leave them with an empty app, so they see every school.
    static var isUnscopedAccount: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: "isGuestUser") || defaults.bool(forKey: "isIndustryProfessional")
    }

    /// The school to stamp on posts this user creates.
    ///
    /// Prefers the `Verification` record's `schoolID`, which the client cannot
    /// write. Falls back to the school picked during onboarding — a hint only,
    /// since an unverified account can't get past the Share gate anyway — and
    /// finally to `legacyDefault` for accounts that predate all of this.
    static var postingSchoolID: String {
        if let verified = StudentVerificationManager.shared.verifiedSchoolID {
            return verified
        }
        let picked = UserDefaults.standard.string(forKey: "userSchool") ?? ""
        return slugsByDisplayName[picked] ?? legacyDefault
    }

    /// The schools whose work this user sees, or `nil` for "every school".
    static var visibleSchoolIDs: [String]? {
        isUnscopedAccount ? nil : [postingSchoolID]
    }

    // MARK: - Queries

    /// The school clause on its own, or `nil` when the user sees every school —
    /// which includes every user while `isFilteringEnabled` is off.
    private static var schoolPredicate: NSPredicate? {
        guard isFilteringEnabled, let ids = visibleSchoolIDs else { return nil }
        // `IN` is one of the few aggregate operators CKQuery supports, and it's
        // what stands in for `OR` (which CloudKit does not support) once a
        // second visible school is ever added.
        return NSPredicate(format: "%K IN %@", fieldKey, ids)
    }

    /// The predicate for a feed query: the caller's own conditions ANDed with
    /// the school filter. Pass `nil` when the query has no other conditions.
    ///
    /// Returns `TRUEPREDICATE` rather than an `AND` of one clause when there's
    /// nothing to filter on, because CloudKit rejects compound predicates built
    /// around `TRUEPREDICATE`.
    static func predicate(and base: NSPredicate? = nil) -> NSPredicate {
        switch (base, schoolPredicate) {
        case (let base?, let school?):
            return NSCompoundPredicate(andPredicateWithSubpredicates: [base, school])
        case (let base?, nil):
            return base
        case (nil, let school?):
            return school
        case (nil, nil):
            return NSPredicate(value: true)
        }
    }

    /// Stamps the school a post belongs to onto its record. A no-op until
    /// `isStampingEnabled` says the deployed schema has the field.
    static func stamp(on record: CKRecord) {
        guard isStampingEnabled else { return }
        record[fieldKey] = postingSchoolID as CKRecordValue
    }

    // MARK: - Display-name bridge

    /// Registry slugs for the schools onboarding can pick. Used only as a
    /// pre-verification hint — the authoritative mapping is the verification
    /// service's D1 `schools` table, and the picker itself should eventually
    /// read from there instead of `UserProfileModel.otherSchools`.
    private static let slugsByDisplayName: [String: String] = [
        UserProfileModel.utSchoolName: legacyDefault,
        "University of Michigan": "umich",
        "Cal Poly SLO": "calpoly-slo",
        "USC": "usc",
        "NYU": "nyu",
        "DePaul": "depaul",
        "University of California, Berkeley": "berkeley"
    ]
}
