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
    ///
    /// Enabled 2026-09-25: `schoolID` confirmed queryable on all seven types in
    /// both environments.
    static let isStampingEnabled = true

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
    ///
    /// Enthusiasts are guest accounts too. Those created before 2026-11 picked
    /// a school and see only that school's work; newer ones have no school and
    /// see everything.
    static var isUnscopedAccount: Bool {
        let defaults = UserDefaults.standard
        let hasSchool = !(defaults.string(forKey: "userSchool") ?? "").isEmpty
        let isSchoolessGuest = defaults.bool(forKey: "isGuestUser")
            && (AccountKind.current != .enthusiast || !hasSchool)
        return isSchoolessGuest || defaults.bool(forKey: "isIndustryProfessional")
    }

    /// The school to stamp on posts this user creates.
    ///
    /// Prefers the `Verification` record's `schoolID`, which the client cannot
    /// write. Falls back to the school picked during onboarding — a hint only,
    /// since an unverified account can't get past the Share gate anyway — and
    /// finally to `legacyDefault` for accounts that predate all of this.
    ///
    /// A moderator who has picked a school in Moderate → Schools posts to that
    /// school instead.
    static var postingSchoolID: String {
        if let moderatorSchool {
            return slugsByDisplayName[moderatorSchool] ?? legacyDefault
        }
        if let verified = StudentVerificationManager.shared.verifiedSchoolID {
            return verified
        }
        let picked = UserDefaults.standard.string(forKey: "userSchool") ?? ""
        return slugsByDisplayName[picked] ?? legacyDefault
    }

    /// The schools whose work this user sees, or `nil` for "every school".
    /// A moderator sees whichever school they picked in Moderate → Schools.
    static var visibleSchoolIDs: [String]? {
        if moderatorSchool != nil { return [postingSchoolID] }
        return isUnscopedAccount ? nil : [postingSchoolID]
    }

    // MARK: - Moderator school override

    /// UserDefaults key for the school (display name) a moderator is viewing and
    /// posting as. Empty means "my own school".
    static let moderatorSchoolKey = "moderatorSchool"

    /// The school a moderator picked in Moderate → Schools, or `nil` when none is
    /// picked or this account isn't the moderator.
    ///
    /// Deliberately tied to the moderator *account*, not the moderator-mode
    /// switch: moderator mode swaps the Share tab out for Moderate, so the pick
    /// has to survive switching the mode off in order to post to that school.
    static var moderatorSchool: String? {
        guard ModeratorAccess.isModerator else { return nil }
        let school = UserDefaults.standard.string(forKey: moderatorSchoolKey) ?? ""
        return slugsByDisplayName[school] == nil ? nil : school
    }

    // MARK: - On-device filter

    /// Whether a post stamped with `schoolID` belongs in this user's feeds.
    ///
    /// This is the client-side half of scoping, and unlike the query filter it is
    /// always on: it only hides posts already fetched, so it can't make CloudKit
    /// drop records the way an early `isFilteringEnabled` does. It also covers the
    /// on-disk cache, which the sync reconciler deliberately keeps even when a
    /// fetch doesn't return a post — so switching schools clears the old school's
    /// posts from the feeds immediately.
    ///
    /// An unstamped post counts as `legacyDefault`, which is correct for every
    /// post in the container today. Until `isStampingEnabled` is on, though, a new
    /// post from another school also arrives unstamped and shows as UT Austin.
    static func isVisible(schoolID: String?) -> Bool {
        isVisible(schoolID: schoolID, in: visibleSchoolIDs)
    }

    /// Same as `isVisible(schoolID:)`, against an already-read `visibleSchoolIDs`.
    ///
    /// Use this when filtering a whole list: `visibleSchoolIDs` costs several
    /// UserDefaults reads, and paying that per post on every feed render froze
    /// the Discover tab for minutes in 1.40. Read it once, then filter.
    static func isVisible(schoolID: String?, in visibleIDs: [String]?) -> Bool {
        guard let visibleIDs else { return true }
        let school = schoolID.flatMap { $0.isEmpty ? nil : $0 } ?? legacyDefault
        return visibleIDs.contains(school)
    }

    /// Whether a person whose profile lists `schoolName` (a display name, as
    /// `UserProfile.school` stores it) belongs in this user's directory.
    ///
    /// An empty name is a profile saved before the school picker existed, which
    /// is UT Austin — the same fallback `UserProfileModel` uses. A name with no
    /// registered slug never matches, so it only shows to unscoped accounts.
    static func isVisible(schoolName: String) -> Bool {
        isVisible(schoolName: schoolName, in: visibleSchoolIDs)
    }

    /// Same as `isVisible(schoolName:)`, against an already-read `visibleSchoolIDs`.
    static func isVisible(schoolName: String, in visibleIDs: [String]?) -> Bool {
        let name = schoolName.trimmingCharacters(in: .whitespaces)
        return isVisible(schoolID: name.isEmpty ? nil : (slugsByDisplayName[name] ?? name), in: visibleIDs)
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
    ///
    /// Ordered, so it can also drive pickers (Moderate → Schools).
    static let registeredSchools: [(name: String, slug: String)] = [
        (UserProfileModel.utSchoolName, legacyDefault),
        (UserProfileModel.berkeleySchoolName, "berkeley"),
        ("University of Michigan", "umich"),
        ("USC", "usc"),
        ("Cal Poly SLO", "calpoly-slo"),
        ("NYU", "nyu"),
        ("DePaul", "depaul"),
        ("BU", "bu"),
        ("Texas A&M", "tamu")
    ]

    private static let slugsByDisplayName: [String: String] =
        Dictionary(uniqueKeysWithValues: registeredSchools.map { ($0.name, $0.slug) })
}
