//
//  CloudKitManager.swift
//  Longhorn Artists Connect
//
//  CloudKit manager supporting separate record types
//

import CloudKit
import SwiftUI
import Combine

/// CloudKit manager that handles Film, Music, Reel, Project, Event as separate record types
@MainActor
class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()
    
    private let container = CKContainer.default()
    
    // Use private database for user-specific data, or public for shared data
    private var database: CKDatabase {
        // Change this to .privateCloudDatabase if data should be private per user
        container.publicCloudDatabase
    }
    
    @Published var isAvailable = false
    @Published var userRecordID: CKRecord.ID?
    
    private init() {
        Task {
            await checkAvailability()
        }
    }
    
    /// Check if CloudKit is available and user is signed in
    func checkAvailability() async {
        do {
            let status = try await container.accountStatus()
            isAvailable = (status == .available)
            
            if isAvailable {
                userRecordID = try await container.userRecordID()
                // Cache the account's record name so ModeratorAccess can gate moderator
                // mode on the (unspoofable) iCloud identity from any context.
                if let recordName = userRecordID?.recordName {
                    UserDefaults.standard.set(recordName, forKey: ModeratorAccess.currentUserRecordNameKey)
                }
                print("✅ CloudKit ready. User ID: \(userRecordID?.recordName ?? "unknown")")
            }
        } catch {
            print("❌ CloudKit availability check failed: \(error)")
            isAvailable = false
        }
    }
    
    // MARK: - Generic Save/Delete
    
    /// Save a record to CloudKit.
    ///
    /// Uses a long-lived `CKModifyRecordsOperation` tuned for large asset uploads
    /// (extended timeouts, background-friendly) rather than the convenience
    /// `database.save`, which can time out on big video files over slow networks.
    /// A `.allKeys` save policy overwrites any existing record with the same ID, so
    /// edits and re-uploads work without a separate fetch-and-merge conflict step.
    /// Transient failures are retried automatically, and a field the deployed schema
    /// doesn't know about is dropped and the save retried (see `saveWithRetry`).
    func save(record: CKRecord) async throws {
        // Fields an earlier save already proved the deployed schema won't accept are
        // stripped before the first attempt. Otherwise every post from a build that's
        // ahead of the schema burns a full asset upload on a save that's certain to be
        // rejected before the drop-and-retry below can get it through.
        let knownBadFields = SchemaRejectionMemory.knownRejectedFields(for: record.recordType)
            .filter { record[$0] != nil }
        for field in knownBadFields {
            record[field] = nil
        }
        if !knownBadFields.isEmpty {
            print("""
            ⚠️ Pre-stripping \(knownBadFields.sorted().joined(separator: ", ")) from \
            \(record.recordType) — the deployed schema rejected them on an earlier save
            """)
        }
        try await saveWithRetry(record: record, attemptsRemaining: 3, droppedFields: knownBadFields)
    }

    private func saveWithRetry(
        record: CKRecord,
        attemptsRemaining: Int,
        droppedFields: Set<String> = [],
        triedCoreFieldsOnly: Bool = false
    ) async throws {
        do {
            try await performModify(record: record)
            if !droppedFields.isEmpty {
                print("""
                ⚠️ Saved \(record.recordType) WITHOUT \(droppedFields.sorted().joined(separator: ", ")) — \
                field(s) not in the deployed CloudKit schema. Add them in CloudKit Dashboard \
                and deploy to Production, or this data won't sync.
                """)
            }
            print("✅ Saved record: \(record.recordType) - \(record.recordID.recordName)")
        } catch let error as CKError {
            // A field the app writes but the deployed schema doesn't define fails the
            // ENTIRE atomic save, so the post never reaches CloudKit: it stays in
            // `pendingUploadIDs`, flashes into the feed at launch before that set
            // loads, then vanishes. This has already happened three times (photography
            // credits, photography equipment, music `lyrics`) because the Development
            // environment auto-creates fields on save while Production only ever gets
            // what was explicitly deployed — so the gap is invisible in Debug builds.
            //
            // Rather than lose the whole upload over one bad field, drop the field
            // CloudKit named and retry. The post uploads with everything else intact;
            // the warning above says what was skipped.
            // Transient failures are handled BEFORE any field dropping, so a rate-limit
            // or network error whose message happens to quote a field name can't cost
            // the post a field it didn't need to lose.
            if attemptsRemaining > 1, let retryAfter = Self.retryDelay(for: error) {
                print("⏳ Transient CloudKit error (\(error.code.rawValue)); retrying in \(retryAfter)s…")
                try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                try await saveWithRetry(
                    record: record,
                    attemptsRemaining: attemptsRemaining - 1,
                    droppedFields: droppedFields,
                    triedCoreFieldsOnly: triedCoreFieldsOnly
                )
                return
            }
            if droppedFields.count < Self.maxDroppedFieldsPerSave,
               let rejectedField = Self.rejectedFieldCandidates(in: error)
                   .first(where: { record[$0] != nil }) {
                print("⚠️ CloudKit rejected field '\(rejectedField)' on \(record.recordType); retrying without it")
                record[rejectedField] = nil
                // Only pre-strip this field from future saves when the message really
                // was a schema complaint; see `namesFieldSchemaRejection`.
                if Self.namesFieldSchemaRejection(error) {
                    SchemaRejectionMemory.remember(rejectedField, for: record.recordType)
                }
                try await saveWithRetry(
                    record: record,
                    attemptsRemaining: attemptsRemaining,
                    droppedFields: droppedFields.union([rejectedField]),
                    triedCoreFieldsOnly: triedCoreFieldsOnly
                )
                return
            }
            // Last resort: the server refused the record and either named no field we
            // could drop above, or kept refusing after we dropped the ones it named.
            // Rather than lose the post, shed every non-essential field at once and save
            // the core of it — a published post missing its credits beats a post that
            // never uploads.
            //
            // Attempted for ANY remaining CKError, not just the codes that read as a
            // schema rejection: by this point the transient retries are exhausted and
            // the alternative is throwing the post away, so one stripped-down attempt
            // costs nothing. Shedding is not destructive to the local data either —
            // each upload attempt builds a fresh `CKRecord` from the stored submission,
            // so a later save (once the schema catches up) writes the full record again.
            if !triedCoreFieldsOnly {
                let shedFields = Self.nonCoreKeys(of: record)
                if !shedFields.isEmpty {
                    print("""
                    ⚠️ CloudKit rejected \(record.recordType) (\(error.code.rawValue)) and the post is \
                    otherwise lost; retrying with core fields only \
                    (dropping \(shedFields.sorted().joined(separator: ", ")))
                    """)
                    for field in shedFields {
                        record[field] = nil
                    }
                    try await saveWithRetry(
                        record: record,
                        attemptsRemaining: attemptsRemaining,
                        droppedFields: droppedFields.union(shedFields),
                        triedCoreFieldsOnly: true
                    )
                    return
                }
            }
            print("❌ SAVE FAILED for record: \(record.recordID.recordName)")
            print("❌ Error: \(error)")
            if Self.isUnattributedSchemaRejection(error) {
                // Nothing further the client can do: what's left is the record type
                // itself or one of the core fields, neither of which can be dropped.
                print("""
                ❌ This looks like a schema problem the app can't work around — check that \
                the record type '\(record.recordType)' and its title/description/asset fields \
                exist in CloudKit Dashboard and have been deployed to Production.
                """)
            }
            throw error
        }
    }

    /// Ceiling on how many fields a single save will drop before giving up, so a
    /// genuinely wrong record type can't loop shedding one field at a time.
    private static let maxDroppedFieldsPerSave = 6

    /// Message fragments that mean "this one field is the problem". Covers both a field
    /// absent from the deployed schema and one whose deployed type doesn't match what
    /// the app writes — e.g. a String the schema declares as a String List, which is an
    /// easy mistake to make when adding a field by hand in CloudKit Dashboard. Both
    /// fail the whole atomic save, and for both, dropping the field is better than
    /// losing the post.
    private static let fieldRejectionPhrases = [
        "unknown field",
        "invalid field",
        "not a valid field",
        "no such field",
        "does not exist",
        "type mismatch",
        "different type",
        "invalid type",
        "cannot be used with field"
    ]

    /// Every quoted token anywhere in `error`'s messages. These are *candidate* field
    /// names — the caller picks the first that is actually a key on the record it tried
    /// to save, and that key check is what makes this safe.
    ///
    /// Deliberately NOT gated on `fieldRejectionPhrases`: CloudKit's wording for "this
    /// field isn't in the schema" varies by path and by OS version ("Unknown field 'x'",
    /// "invalid field name 'x'", "field 'x' value type mismatch", …), and gating on a
    /// fixed phrase list meant an unrecognized variant skipped the one-field drop and
    /// fell through to shedding EVERY non-core field — an event saved with no date,
    /// host, location or category. A quoted token that isn't a key on the record (a
    /// record name, a record type, a value) is filtered out by the caller, so casting a
    /// wide net here costs nothing and rescues the post with its real data intact.
    ///
    /// Position varies too — "Unknown field 'lyrics'" puts the name after the phrase,
    /// "field 'lyrics' value type mismatch" before it — so word order is ignored and
    /// every quoted token is returned in the order it appears.
    private static func rejectedFieldCandidates(in error: CKError) -> [String] {
        // Unwrap per-record errors first: the useful message lives on the inner error.
        if let perItemErrors = error.partialErrorsByItemID?.values {
            for case let itemError as CKError in perItemErrors {
                let candidates = rejectedFieldCandidates(in: itemError)
                if !candidates.isEmpty { return candidates }
            }
        }

        let message = messageText(of: error)
        var candidates: [String] = []
        // Single and double quotes: CloudKit uses both depending on the message.
        for pattern in ["'[^']+'", "\"[^\"]+\""] {
            var searchStart = message.startIndex
            while let quoted = message.range(
                of: pattern, options: .regularExpression, range: searchStart..<message.endIndex
            ) {
                candidates.append(String(message[quoted].dropFirst().dropLast()))
                searchStart = quoted.upperBound
            }
        }
        return candidates
    }

    /// Whether `error`'s message actually reads like a schema complaint about one field.
    ///
    /// Only used to decide whether to *remember* a dropped field in
    /// `SchemaRejectionMemory` (which pre-strips it from later saves for a day). The
    /// drop-and-retry itself is unconditional — better to lose one field on one save
    /// than the whole post — but pre-stripping a field on a mere guess would silently
    /// drop good data from every subsequent post, so that half stays conservative.
    private static func namesFieldSchemaRejection(_ error: CKError) -> Bool {
        if let perItemErrors = error.partialErrorsByItemID?.values {
            for case let itemError as CKError in perItemErrors where namesFieldSchemaRejection(itemError) {
                return true
            }
        }
        let message = messageText(of: error)
        return fieldRejectionPhrases.contains { message.range(of: $0, options: .caseInsensitive) != nil }
    }

    /// Everywhere CloudKit hides useful text on an error, joined into one string.
    private static func messageText(of error: CKError) -> String {
        [
            error.localizedDescription,
            error.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
            error.userInfo["ServerErrorDescription"] as? String
        ].compactMap { $0 }.joined(separator: " ")
    }

    /// True when the server refused the record outright — the codes it uses for a
    /// malformed or unsupported record body, which in this app almost always means the
    /// deployed schema and the code have drifted apart.
    ///
    /// Deliberately narrow: network, quota, auth and rate-limit failures must NOT land
    /// here, because the caller's response is to re-upload the record (assets and all)
    /// with fields stripped, which would be pure waste for a failure that isn't about
    /// the record's contents.
    private static func isUnattributedSchemaRejection(_ error: CKError) -> Bool {
        if let perItemErrors = error.partialErrorsByItemID?.values {
            for case let itemError as CKError in perItemErrors where isUnattributedSchemaRejection(itemError) {
                return true
            }
        }
        switch error.code {
        case .invalidArguments, .serverRejectedRequest:
            return true
        default:
            return false
        }
    }

    /// Fields that can be dropped to get a post published: everything except what it
    /// needs to exist, be moderated, and be readable in the feed.
    ///
    /// The core set is derived from the app's field-naming convention instead of a
    /// per-record-type table, so a brand-new record type is covered without anyone
    /// remembering to extend a list here — which is exactly the kind of upkeep that
    /// caused the schema gaps this whole path exists to survive. Core is: the shared
    /// moderation/attribution fields, anything named `…Title` or `…Description`, and
    /// the media assets (a film whose video got dropped isn't worth publishing).
    ///
    /// `schoolID` is core for a blunter reason than the rest: feeds filter on it with a
    /// `schoolID IN {…}` predicate, and CloudKit can't match a field that isn't set. A
    /// post shed down to "core" without it would upload successfully and then be
    /// invisible to every school including its author's. If the deployed schema doesn't
    /// have the field at all, CloudKit names it and the named-field drop above — which
    /// ignores this set — still gets the post published.
    private static let coreFieldNames: Set<String> = [
        "isApproved", "submittedBy", "createdDate", "userID", "schoolID"
    ]

    /// The few named fields whose loss would make a published post actively misleading
    /// rather than merely incomplete, so they're protected from the core-only shed too.
    ///
    /// Events are the case that forced this: shedding by naming convention alone left a
    /// title and a flyer, with no date, host, place or category — an event nobody can
    /// attend. Every field here is verified present in the deployed production schema
    /// (all five appear on existing production EventSubmission records), and the
    /// named-field drop above ignores these sets, so one of them can still be dropped
    /// if CloudKit specifically names it — protecting them here can't strand a post.
    /// Keep this list tiny: the
    /// convention-based `coreFieldNames` is still what covers new record types with no
    /// upkeep, and anything added here is a field the rescue path can no longer drop.
    private static let essentialFieldNames: Set<String> = [
        "eventStartTime", "eventEndTime", "eventHost", "eventLocationText", "eventCategory"
    ]

    private static func nonCoreKeys(of record: CKRecord) -> Set<String> {
        var droppable: Set<String> = []
        for key in record.allKeys() {
            guard let value = record[key] else { continue }
            if coreFieldNames.contains(key) { continue }
            if essentialFieldNames.contains(key) { continue }
            if key.hasSuffix("Title") || key.hasSuffix("Description") { continue }
            if value is CKAsset || value is [CKAsset] { continue }
            droppable.insert(key)
        }
        return droppable
    }

    /// Per-record-type memory of fields the deployed schema rejected, so only the first
    /// post on a device pays the cost of discovering a schema gap.
    ///
    /// Entries expire after a day so the app heals itself once the field is added in
    /// CloudKit Dashboard and deployed — without expiry, one rejection would stop that
    /// field syncing for the life of the install.
    private enum SchemaRejectionMemory {
        private static let defaultsKey = "cloudKitRejectedFieldsByRecordType"
        private static let lifetime: TimeInterval = 24 * 60 * 60

        /// Keyed `"MusicSubmission/lyrics"` → when it was rejected.
        private static var store: [String: Date] {
            get { UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Date] ?? [:] }
            set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
        }

        static func knownRejectedFields(for recordType: String) -> Set<String> {
            let prefix = recordType + "/"
            let cutoff = Date().addingTimeInterval(-lifetime)
            let fields = store.compactMap { entry -> String? in
                guard entry.value > cutoff, entry.key.hasPrefix(prefix) else { return nil }
                return String(entry.key.dropFirst(prefix.count))
            }
            return Set(fields)
        }

        static func remember(_ field: String, for recordType: String) {
            let cutoff = Date().addingTimeInterval(-lifetime)
            var updated = store.filter { $0.value > cutoff }   // drop expired entries while we're here
            updated["\(recordType)/\(field)"] = Date()
            store = updated
        }
    }

    /// Runs a single modify operation configured for large uploads.
    private func performModify(record: CKRecord) async throws {
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = .allKeys   // overwrite existing record with same ID
        operation.isAtomic = true

        let config = CKOperation.Configuration()
        config.qualityOfService = .utility
        config.isLongLived = true                       // survive app suspension
        config.timeoutIntervalForRequest = 300          // 5 min between packets
        config.timeoutIntervalForResource = 60 * 60 * 24 * 7  // up to 7 days for the whole transfer
        operation.configuration = config

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Report byte-level upload progress to the progress center. CloudKit
            // invokes this on a background queue, so hop to the main actor. The
            // record name is the submission's UUID; non-submission saves (e.g. user
            // profiles) are ignored by the center.
            operation.perRecordProgressBlock = { record, progress in
                let recordName = record.recordID.recordName
                Task { @MainActor in
                    UploadProgressCenter.shared.report(recordName: recordName, fraction: progress)
                }
            }
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    /// Seconds to wait before retrying a transient CloudKit error, or nil if the
    /// error isn't worth retrying.
    private static func retryDelay(for error: CKError) -> Double? {
        if let retryAfter = error.retryAfterSeconds { return retryAfter }
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy,
             .serverResponseLost:
            // `.serverResponseLost` is transient and common on large asset uploads
            // (the connection drops mid-transfer). The others are the usual network /
            // throttling hiccups. Non-transient errors (schema mismatch, asset write
            // failure, quota, etc.) return nil so we surface them instead of looping.
            return 3
        default:
            return nil
        }
    }
    
    /// Delete a record from CloudKit
    func delete(recordID: CKRecord.ID) async throws {
        _ = try await database.deleteRecord(withID: recordID)
        print("✅ Deleted record: \(recordID.recordName)")
    }

    // MARK: - Paginated Fetch

    /// Fetches EVERY record matching `query`, following CloudKit's pagination cursor
    /// until it's exhausted.
    ///
    /// `database.records(matching:)` only returns a single server-sized page and a
    /// cursor for the rest. Since these records carry video/audio/thumbnail assets,
    /// that first page can be small — so ignoring the cursor silently drops every
    /// record past it. The sync layer then misreads those missing records as
    /// server-side deletes and removes them locally, which is what makes posts
    /// appear/disappear and diverge between devices. Looping on the cursor here
    /// guarantees callers see the complete server state.
    /// - Parameter desiredKeys: when non-nil, only these fields are fetched. Feed
    ///   queries pass an allowlist that EXCLUDES the large video/audio assets so the
    ///   feed stays light and reliable — downloading every full video inline was
    ///   timing out (empty feed for new installs) and dropping thumbnails on partial
    ///   failures. The heavy media is fetched on demand when a post is opened
    ///   (`downloadMedia`). `nil` keeps the old "fetch everything" behavior.
    private func fetchAllRecords(matching query: CKQuery, desiredKeys: [CKRecord.FieldKey]? = nil) async throws -> [CKRecord] {
        var records: [CKRecord] = []

        var (matchResults, cursor) = try await database.records(matching: query, desiredKeys: desiredKeys)
        records.append(contentsOf: matchResults.compactMap { try? $0.1.get() })

        while let currentCursor = cursor {
            (matchResults, cursor) = try await database.records(continuingMatchFrom: currentCursor, desiredKeys: desiredKeys)
            records.append(contentsOf: matchResults.compactMap { try? $0.1.get() })
        }

        return records
    }

    // MARK: - Feed desiredKeys (light fetch, no heavy media)

    /// Field allowlists for the feed queries. Each lists everything the corresponding
    /// `fromCloudKitRecord` parser reads EXCEPT the large media assets — including the
    /// image asset (thumbnail/cover/poster/flyer). The feed downloads only lightweight
    /// metadata; images are fetched once by `hydrateThumbnails` and cached to disk, so
    /// routine syncs no longer re-download them (the main source of wasted bandwidth).
    /// Keep in sync with the parsers in MediaModels.swift.
    private enum FeedKeys {
        static let film: [CKRecord.FieldKey] = [
            "filmTitle", "filmDescription", "isApproved", "submittedBy", "createdDate",
            "lastEditedDate", "filmLogline", "filmAgeRating", "filmExplicit", "filmStudio",
            "filmGenres", "filmCast", "filmCastIDs", "filmCrew", "filmCrewIDs",
            // Small numeric field (not the heavy video asset) written whenever a video was
            // uploaded. Fetching it lets the feed tell a video-less film from one whose
            // video simply hasn't downloaded yet, so the "Coming Soon" placeholder only
            // shows when there is genuinely no video attached to the post.
            "filmVideoDuration"
        ]
        static let music: [CKRecord.FieldKey] = [
            "musicTitle", "musicDescription", "isApproved", "submittedBy", "createdDate",
            "lastEditedDate", "musicArtist", "musicCategory", "musicExplicit", "musicGenres", "musicSpotifyLink",
            "musicAppleMusicLink", "amazonMusicLink", "youtubeMusicLink", "soundcloudLink",
            "lyrics", "musicRecording", "musicRecordingIDs", "musicProduction", "musicProductionIDs",
            "musicAudioExt",
            // Track length — the audio counterpart to "filmVideoDuration" / "reelVideoDuration"
            // above, and just as necessary. Without it the feed's `Music.audioDuration` is
            // always nil, so the duration badge falls back to reading the local audio file
            // and never appears on a device that hasn't downloaded the track — exactly what
            // persisting the duration was meant to avoid.
            "musicAudioDuration"
        ]
        static let reel: [CKRecord.FieldKey] = [
            "reelTitle", "reelDescription", "isApproved", "submittedBy", "createdDate",
            "lastEditedDate", "reelType", "orderedCrew", "orderedCrewIDs",
            // The headline artist and the Featured Work lists. `desiredKeys` is an
            // allowlist, so leaving these out made the feed parse them as nil — they
            // showed on the device that posted, then disappeared on the next sync,
            // the same way the event fields did below.
            "reelArtist", "featuredWork", "featuredWorkManual",
            // Small numeric field (not the heavy video asset) written whenever a reel
            // video was uploaded, so the feed can show the demo reel's length badge
            // without downloading the video — mirrors "filmVideoDuration" above.
            "reelVideoDuration"
        ]
        static let project: [CKRecord.FieldKey] = [
            "projectTitle", "projectDescription", "isApproved", "submittedBy", "createdDate",
            "lastEditedDate", "projectShootDatesText", "projectShootStart", "projectReleaseDateText",
            "projectExpectedReleaseDate", "projectGenres", "projectCastNeeded", "projectCrewNeeded",
            "projectCastAssembled", "projectCastAssembledIDs", "projectCrewAssembled", "projectCrewAssembledIDs",
            // The detail view's slideshow. Projects have no on-demand asset fetch (unlike
            // films' stills/BTS), so leaving this out of the allowlist would mean the
            // slides only ever existed on the device that posted them. They're downscaled
            // images, like photography's gallery, which rides along in the feed fetch too.
            "projectSlides"
        ]
        static let event: [CKRecord.FieldKey] = [
            "eventTitle", "eventDescription", "isApproved", "submittedBy", "createdDate",
            "lastEditedDate", "eventStartTime", "eventEndTime", "eventLocationText", "eventLocation", "eventHost",
            "eventCategory", "eventTicketsURL",
            // Category-specific fields. `desiredKeys` is an allowlist, so leaving these
            // out made the feed parse them as nil — the lineup / expectations / apply
            // link showed on the device that posted, then disappeared on the next sync.
            "eventLineup", "eventExpectations", "eventApplicationURL",
            // Theatre Performance's list of showings. Same reason as the three above:
            // without it in the allowlist the run would show on the posting device and
            // then vanish on the next sync.
            "eventShowtimes"
        ]
        // Photography's gallery IS its content (there's no separate on-demand fetch), so
        // the gallery asset list is included in the feed fetch. The small card thumbnail
        // is still hydrated separately (see `photographyThumbnail`).
        static let photography: [CKRecord.FieldKey] = [
            "photographyTitle", "photographyDescription", "isApproved", "submittedBy", "createdDate",
            "lastEditedDate", "photographyArtist", "photographyReleaseYear", "photographyImages",
            "photographyEquipment", "orderedCrew", "orderedCrewIDs"
        ]
        /// Like photography, a design post's images ARE its content, so the image asset
        /// list rides along with the feed fetch. `designVideo` is deliberately omitted —
        /// it's heavy and streams on demand (see `streamResolutionDetailed`).
        static let design: [CKRecord.FieldKey] = [
            "designTitle", "designDescription", "isApproved", "submittedBy", "createdDate",
            "lastEditedDate", "designCategory", "designReleaseYear", "designImages",
            "designVideoDuration", "orderedCrew", "orderedCrewIDs"
        ]
    }

    /// One-time thumbnail hydration. Because the feed queries omit image assets (see
    /// `FeedKeys`), the small cover/poster images must be fetched separately — but only
    /// once each, then reused from disk forever (or until the artwork is edited). This
    /// fetches ONLY the image field for the given records and persists it under the
    /// deterministic thumbnail file name the parsers expect. Callers pass only records
    /// whose local copy is missing or stale, so a warm cache performs no network at all.
    /// Fails soft: a missing image just shows a placeholder.
    private struct ThumbnailRef { let recordID: CKRecord.ID; let assetField: String; let fileName: String }

    private func hydrateThumbnails(_ refs: [ThumbnailRef]) async {
        guard !refs.isEmpty else { return }
        let byID = Dictionary(uniqueKeysWithValues: refs.map { ($0.recordID, $0) })
        let fields = Array(Set(refs.map { $0.assetField }))
        do {
            let results = try await database.records(for: Array(byID.keys), desiredKeys: fields)
            for (recordID, result) in results {
                guard let ref = byID[recordID], case .success(let record) = result else { continue }
                _ = FileManager.default.persistCloudKitAsset(
                    record.getAsset(ref.assetField),
                    fileName: ref.fileName,
                    subdirectory: "thumbnails"
                )
            }
        } catch {
            print("⚠️ Thumbnail hydration failed: \(error.localizedDescription)")
        }
    }

    /// Downloads any missing/stale thumbnails for the given feed items (once), then
    /// re-resolves each item's `thumbnailFileName` from the on-disk cache. `assetField`
    /// is the CloudKit image field and `fileName` builds the deterministic cache name
    /// (both must match the corresponding `fromCloudKitRecord` parser).
    private func withHydratedThumbnails<T: MediaItem>(
        _ items: [T],
        assetField: String,
        fileName: (UUID) -> String
    ) async -> [T] {
        let refs = items.compactMap { item -> ThumbnailRef? in
            let name = fileName(item.id)
            let stale = FileManager.default.cachedThumbnailNeedsRefresh(
                fileName: name, subdirectory: "thumbnails", lastEdited: item.lastEditedDate
            )
            guard stale else { return nil }
            return ThumbnailRef(recordID: CKRecord.ID(recordName: item.id.uuidString),
                                assetField: assetField, fileName: name)
        }
        await hydrateThumbnails(refs)

        // The models were parsed from a fetch that lacked the image, so re-resolve the
        // (now cached) file name for any that were missing one.
        var result = items
        for i in result.indices where result[i].thumbnailFileName == nil {
            result[i].thumbnailFileName = FileManager.default.persistCloudKitAsset(
                nil, fileName: fileName(result[i].id), subdirectory: "thumbnails"
            )
        }
        return result
    }

    /// Downloads (and persists) the full video/audio file for a single submission on
    /// demand — used when a post is opened, since the feed queries skip heavy assets.
    /// Returns the local file URL, or nil if unavailable. Reuses an already-downloaded
    /// copy without re-fetching.
    func downloadMedia(submissionID: UUID, type: MediaType) async -> URL? {
        let fileName: String
        let assetField: String
        switch type {
        case .film:  assetField = "filmVideo";  fileName = "\(submissionID.uuidString)_video.mov"
        case .reel:  assetField = "reelVideo";  fileName = "\(submissionID.uuidString)_video.mov"
        case .music: assetField = "musicAudio"; fileName = "\(submissionID.uuidString)_audio.m4a"
        case .design: assetField = "designVideo"; fileName = "\(submissionID.uuidString)_video.mov"
        case .project, .event: return nil   // no heavy media
        case .photography: return nil        // gallery is fetched with the feed
        }

        // Already on disk from a previous open (or a still-present upload copy)? Reuse it,
        // no network. `mediaFileURL` checks the media cache first, then Documents (legacy).
        // Audio can be saved under any extension (mp3/wav/…), so match by prefix.
        if type == .music,
           let cached = FileManager.default.existingAudioFileName(forSubmissionID: submissionID.uuidString),
           let url = FileManager.default.mediaFileURL(named: cached) {
            return url
        }
        if let existing = FileManager.default.mediaFileURL(named: fileName) { return existing }

        do {
            let recordID = CKRecord.ID(recordName: submissionID.uuidString)
            let record = try await database.record(for: recordID)
            guard let mediaDir = FileManager.default.mediaCacheDirectory else { return nil }

            // Audio needs a correct extension so AVPlayer can decode it; use the
            // recorded upload extension when present, otherwise sniff the bytes.
            if type == .music {
                guard let persisted = FileManager.default.persistAudioAsset(
                    record.getAsset(assetField),
                    submissionID: submissionID.uuidString,
                    preferredExtension: record.getString("musicAudioExt")
                ) else { return nil }
                let url = mediaDir.appendingPathComponent(persisted)
                finalizeDownloadedMedia(at: url)
                return url
            }

            guard let persisted = FileManager.default.persistCloudKitAsset(
                record[assetField] as? CKAsset,
                fileName: fileName,
                baseDirectory: mediaDir
            ) else {
                return nil
            }
            let url = mediaDir.appendingPathComponent(persisted)
            finalizeDownloadedMedia(at: url)
            return url
        } catch {
            print("❌ On-demand media download failed for \(submissionID): \(error)")
            return nil
        }
    }

    /// The byte size of a submission's primary uploaded media (film/reel video or music
    /// audio), for the moderator dashboard. Prefers an already-downloaded local copy so
    /// no network is used; otherwise reads the asset's `size` from CloudKit Web Services
    /// **without downloading the file**. Returns nil when there's no heavy media or the
    /// size can't be determined (e.g. web services not configured and nothing cached).
    func contentByteSize(submissionID: UUID, type: MediaType) async -> Int64? {
        // Local cached copy → exact on-disk size, free.
        if let local = localMediaByteSize(submissionID: submissionID, type: type) {
            return local
        }

        let field: String
        switch type {
        case .film:  field = "filmVideo"
        case .reel:  field = "reelVideo"
        case .music: field = "musicAudio"
        case .design: field = "designVideo"
        case .project, .event, .photography: return nil   // no single heavy media asset
        }
        return await CloudKitWebServices.assetSize(recordName: submissionID.uuidString, field: field)
    }

    /// Size of a submission's media file if it's already cached on disk, else nil.
    private func localMediaByteSize(submissionID: UUID, type: MediaType) -> Int64? {
        let fileName: String?
        switch type {
        case .film, .reel, .design:
            fileName = "\(submissionID.uuidString)_video.mov"
        case .music:
            // Audio can be saved under any extension, so match by prefix.
            fileName = FileManager.default.existingAudioFileName(forSubmissionID: submissionID.uuidString)
        case .project, .event, .photography:
            fileName = nil
        }
        guard let fileName,
              let url = FileManager.default.mediaFileURL(named: fileName),
              let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        else { return nil }
        return size.int64Value
    }

    /// Returns a range-streamable HTTPS URL for a submission's video/audio so the player
    /// can start before the whole file downloads. Uses the CloudKit Web Services
    /// `downloadURL` (a CDN link that supports HTTP range requests) instead of the native
    /// CKAsset, which is only usable after a full download. Returns nil when streaming
    /// isn't configured/available — callers then fall back to `downloadMedia`.
    func streamingURL(submissionID: UUID, type: MediaType) async -> URL? {
        if case .streaming(let url) = await streamResolution(submissionID: submissionID, type: type) {
            return url
        }
        return nil
    }

    /// Like `streamingURL`, but returns the detailed `StreamResolution` so callers can
    /// show an accurate status — "File Non-Existent", "Error Streaming", etc. — instead of
    /// collapsing every failure into a single nil / "Coming Soon".
    func streamResolution(submissionID: UUID, type: MediaType) async -> StreamResolution {
        await streamResolutionDetailed(submissionID: submissionID, type: type).0
    }

    /// Like `streamResolution`, but also returns a compact diagnostic of what the server
    /// handed this device (environment, HTTP status, field keys, downloadURL presence),
    /// so the UI can surface it for on-device debugging.
    func streamResolutionDetailed(submissionID: UUID, type: MediaType) async -> (StreamResolution, String) {
        let field: String
        switch type {
        case .film:  field = "filmVideo"
        case .reel:  field = "reelVideo"
        case .music: field = "musicAudio"
        case .design: field = "designVideo"
        case .project, .event, .photography: return (.assetMissing, "unsupported type")
        }
        return await CloudKitWebServices.streamResolutionDetailed(
            recordName: submissionID.uuidString, field: field
        )
    }

    /// Fetches a film's still/BTS photo galleries on demand. These are omitted from the
    /// feed (see `FeedKeys.film`) and fetched only when a film's detail view opens. The
    /// trailer is NOT fetched here — being video, it streams via `trailerStreamingURL`
    /// and is never downloaded. (Photos render from local files via `UIImage(contentsOfFile:)`,
    /// so they're cached like the app's other small artwork.) Already-cached photos are
    /// reused without network. Returns local file URLs for whatever resolved.
    func downloadFilmExtras(submissionID: UUID) async -> (bts: [URL], stills: [URL]) {
        guard let mediaDir = FileManager.default.mediaCacheDirectory else { return ([], []) }
        let idString = submissionID.uuidString

        do {
            let recordID = CKRecord.ID(recordName: idString)
            let results = try await database.records(
                for: [recordID],
                desiredKeys: ["filmBTS", "filmStills"]
            )
            guard case .success(let record)? = results[recordID] else {
                return ([], [])
            }

            func persist(_ assets: [CKAsset]?, kind: String) -> [URL] {
                guard let assets else { return [] }
                return assets.enumerated().compactMap { index, asset in
                    guard let name = FileManager.default.persistCloudKitAsset(
                        asset, fileName: "\(idString)_\(kind)_\(index).jpg", baseDirectory: mediaDir
                    ) else { return nil }
                    return mediaDir.appendingPathComponent(name)
                }
            }

            let bts = persist(record["filmBTS"] as? [CKAsset], kind: "bts")
            let stills = persist(record["filmStills"] as? [CKAsset], kind: "still")
            return (bts, stills)
        } catch {
            print("❌ On-demand film-extras fetch failed for \(submissionID): \(error)")
            return ([], [])
        }
    }

    /// Range-streamable URL for a film's trailer (a separate video from the feature film),
    /// so the trailer plays without ever being downloaded to the device. Returns nil when
    /// unavailable / web services not configured — the trailer section is then hidden.
    func trailerStreamingURL(submissionID: UUID) async -> URL? {
        await CloudKitWebServices.assetDownloadURL(
            recordName: submissionID.uuidString, field: "filmTrailer"
        )
    }

    /// Post-download bookkeeping: cap total cache size so opening many posts can't grow
    /// the media cache without bound. (The cache lives in Caches, so it's already
    /// excluded from backups and purgeable by the OS.)
    private func finalizeDownloadedMedia(at url: URL) {
        FileManager.default.trimMediaCache()
    }

    // MARK: - Post Likes

    /// Errors specific to the like flow.
    enum LikeError: Error { case notSignedIn }

    /// The current iCloud user's record name, used to attribute a like. Falls back to the
    /// value cached at launch so likes still work before `checkAvailability()` finishes.
    private var currentUserID: String? {
        userRecordID?.recordName ?? UserDefaults.standard.string(forKey: ModeratorAccess.currentUserRecordNameKey)
    }

    /// Deterministic record ID for one user's like on one post. Keying the record by
    /// "like_<postID>_<userID>" makes liking idempotent — a like is a single save, an
    /// unlike a single delete, and a user can never double-like the same post.
    private func likeRecordID(postID: UUID, userID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "like_\(postID.uuidString)_\(userID)")
    }

    /// Creates or removes the current user's like on a post. Because each user only ever
    /// writes their own record (never a shared counter), concurrent likes from different
    /// devices can't clobber each other.
    func setLike(_ liked: Bool, postID: UUID) async throws {
        guard let userID = currentUserID else { throw LikeError.notSignedIn }
        let recordID = likeRecordID(postID: postID, userID: userID)
        if liked {
            let record = CKRecord(recordType: "PostLike", recordID: recordID)
            record["postID"] = postID.uuidString as CKRecordValue
            record["userID"] = userID as CKRecordValue
            record["createdDate"] = Date() as CKRecordValue
            try await save(record: record)
        } else {
            do {
                try await delete(recordID: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                // The like was already gone server-side — treat unliking as a success.
            }
        }
    }

    /// The number of users who like a post. Counts matching `PostLike` records without
    /// fetching any of their fields (empty `desiredKeys`) so the query stays cheap.
    /// Requires the `postID` field to be marked Queryable in the CloudKit schema.
    func fetchLikeCount(postID: UUID) async throws -> Int {
        let predicate = NSPredicate(format: "postID == %@", postID.uuidString)
        let query = CKQuery(recordType: "PostLike", predicate: predicate)
        return try await fetchAllRecords(matching: query, desiredKeys: []).count
    }

    /// The raw iCloud user record names of everyone who liked a post, so the post's
    /// owner can see who liked it. Only the `userID` field is fetched to keep the query
    /// cheap. Requires the `postID` field to be marked Queryable in the CloudKit schema.
    func fetchLikers(postID: UUID) async throws -> [String] {
        let predicate = NSPredicate(format: "postID == %@", postID.uuidString)
        let query = CKQuery(recordType: "PostLike", predicate: predicate)
        let records = try await fetchAllRecords(matching: query, desiredKeys: ["userID"])
        return records.compactMap { $0["userID"] as? String }
    }

    /// The set of post IDs the current user has liked, so their likes can be restored on
    /// a fresh install / new device. Returns nil when the user isn't identified yet.
    /// Requires the `userID` field to be marked Queryable in the CloudKit schema.
    func fetchMyLikedPostIDs() async throws -> Set<UUID>? {
        guard let userID = currentUserID else { return nil }
        let predicate = NSPredicate(format: "userID == %@", userID)
        let query = CKQuery(recordType: "PostLike", predicate: predicate)
        let records = try await fetchAllRecords(matching: query, desiredKeys: ["postID"])
        return Set(records.compactMap { ($0["postID"] as? String).flatMap(UUID.init) })
    }

    // MARK: - Record Ownership

    /// The account ID to stamp on a post being saved: the signed-in user normally, or
    /// `nil` when writing a post somebody else created (a moderator editing another
    /// user's submission).
    ///
    /// `nil` leaves the `userID` key off the record entirely, and the blind `.allKeys`
    /// save overwrites only the keys a record carries — so the owner's `userID` stays
    /// as it is on the server and the edit doesn't reassign their post.
    private func ownerRecordID(preservingOwner: Bool) -> CKRecord.ID? {
        preservingOwner ? nil : userRecordID
    }

    /// Stamps the school a post belongs to, so every school's feed can filter to
    /// its own work (see `SchoolScope`).
    ///
    /// Skipped when preserving the original owner — a moderator editing another
    /// user's submission — because the alternative is an edit silently moving
    /// that post into the moderator's school.
    private func stampSchool(on record: CKRecord, preservingOwner: Bool) {
        guard !preservingOwner else { return }
        SchoolScope.stamp(on: record)
    }

    // MARK: - Film Operations

    func saveFilm(_ film: Film, preservingOwner: Bool = false) async throws {
        print("🔵 Saving Film: \(film.title)")
        let record = try await film.toCloudKitRecord(userRecordID: ownerRecordID(preservingOwner: preservingOwner))
        stampSchool(on: record, preservingOwner: preservingOwner)
        try await save(record: record)
    }
    
    func fetchAllFilms() async throws -> [Film] {
        let query = CKQuery(recordType: "FilmSubmission", predicate: SchoolScope.predicate())
        // Use CloudKit's built-in timestamp field (with three underscores)
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]

        let films = try await fetchAllRecords(matching: query, desiredKeys: FeedKeys.film).compactMap(Film.fromCloudKitRecord)
        let hydrated = await withHydratedThumbnails(films, assetField: "filmThumbnail", fileName: { "\($0.uuidString)_thumb.jpg" })

        print("✅ Fetched \(hydrated.count) films")
        return hydrated
    }

    func fetchApprovedFilms() async throws -> [Film] {
        let predicate = SchoolScope.predicate(and: NSPredicate(format: "isApproved == 1"))
        let query = CKQuery(recordType: "FilmSubmission", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]

        let films = try await fetchAllRecords(matching: query, desiredKeys: FeedKeys.film).compactMap(Film.fromCloudKitRecord)
        let hydrated = await withHydratedThumbnails(films, assetField: "filmThumbnail", fileName: { "\($0.uuidString)_thumb.jpg" })

        print("✅ Fetched \(hydrated.count) approved films")
        return hydrated
    }
    
    func deleteFilm(_ film: Film) async throws {
        let recordID = CKRecord.ID(recordName: film.id.uuidString)
        try await delete(recordID: recordID)
    }
    
    // MARK: - Music Operations
    
    func saveMusic(_ music: Music, preservingOwner: Bool = false) async throws {
        print("🔵 Saving Music: \(music.title)")
        let record = try await music.toCloudKitRecord(userRecordID: ownerRecordID(preservingOwner: preservingOwner))
        stampSchool(on: record, preservingOwner: preservingOwner)
        try await save(record: record)
    }
    
    func fetchAllMusic() async throws -> [Music] {
        let query = CKQuery(recordType: "MusicSubmission", predicate: SchoolScope.predicate())
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]

        let musicItems = try await fetchAllRecords(matching: query, desiredKeys: FeedKeys.music).compactMap(Music.fromCloudKitRecord)
        let hydrated = await withHydratedThumbnails(musicItems, assetField: "musicCover", fileName: { "\($0.uuidString)_cover.jpg" })

        print("✅ Fetched \(hydrated.count) music items")
        return hydrated
    }

    func fetchApprovedMusic() async throws -> [Music] {
        let predicate = SchoolScope.predicate(and: NSPredicate(format: "isApproved == 1"))
        let query = CKQuery(recordType: "MusicSubmission", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]

        let musicItems = try await fetchAllRecords(matching: query, desiredKeys: FeedKeys.music).compactMap(Music.fromCloudKitRecord)
        let hydrated = await withHydratedThumbnails(musicItems, assetField: "musicCover", fileName: { "\($0.uuidString)_cover.jpg" })

        print("✅ Fetched \(hydrated.count) approved music items")
        return hydrated
    }
    
    func deleteMusic(_ music: Music) async throws {
        let recordID = CKRecord.ID(recordName: music.id.uuidString)
        try await delete(recordID: recordID)
    }
    
    // MARK: - Reel Operations
    
    func saveReel(_ reel: Reel, preservingOwner: Bool = false) async throws {
        print("🔵 Saving Reel: \(reel.title)")
        let record = try await reel.toCloudKitRecord(userRecordID: ownerRecordID(preservingOwner: preservingOwner))
        stampSchool(on: record, preservingOwner: preservingOwner)
        try await save(record: record)
    }
    
    func fetchAllReels() async throws -> [Reel] {
        let query = CKQuery(recordType: "ReelSubmission", predicate: SchoolScope.predicate())
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]

        let reels = try await fetchAllRecords(matching: query, desiredKeys: FeedKeys.reel).compactMap(Reel.fromCloudKitRecord)
        let hydrated = await withHydratedThumbnails(reels, assetField: "reelThumbnail", fileName: { "\($0.uuidString)_thumb.jpg" })

        print("✅ Fetched \(hydrated.count) reels")
        return hydrated
    }

    func fetchApprovedReels() async throws -> [Reel] {
        let predicate = SchoolScope.predicate(and: NSPredicate(format: "isApproved == 1"))
        let query = CKQuery(recordType: "ReelSubmission", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]

        let reels = try await fetchAllRecords(matching: query, desiredKeys: FeedKeys.reel).compactMap(Reel.fromCloudKitRecord)
        let hydrated = await withHydratedThumbnails(reels, assetField: "reelThumbnail", fileName: { "\($0.uuidString)_thumb.jpg" })

        print("✅ Fetched \(hydrated.count) approved reels")
        return hydrated
    }
    
    func deleteReel(_ reel: Reel) async throws {
        let recordID = CKRecord.ID(recordName: reel.id.uuidString)
        try await delete(recordID: recordID)
    }
    
    // MARK: - Project Operations
    
    func saveProject(_ project: Project, preservingOwner: Bool = false) async throws {
        print("🔵 Saving Project: \(project.title)")
        let record = try await project.toCloudKitRecord(userRecordID: ownerRecordID(preservingOwner: preservingOwner))
        stampSchool(on: record, preservingOwner: preservingOwner)
        try await save(record: record)
    }
    
    func fetchAllProjects() async throws -> [Project] {
        let query = CKQuery(recordType: "ProjectSubmission", predicate: SchoolScope.predicate())
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let projects = try await fetchAllRecords(matching: query, desiredKeys: FeedKeys.project).compactMap(Project.fromCloudKitRecord)
        let hydrated = await withHydratedThumbnails(projects, assetField: "projectPoster", fileName: { "\($0.uuidString)_poster.jpg" })

        print("✅ Fetched \(hydrated.count) projects")
        return hydrated
    }
    
    func fetchApprovedProjects() async throws -> [Project] {
        let predicate = SchoolScope.predicate(and: NSPredicate(format: "isApproved == 1"))
        let query = CKQuery(recordType: "ProjectSubmission", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let projects = try await fetchAllRecords(matching: query, desiredKeys: FeedKeys.project).compactMap(Project.fromCloudKitRecord)
        let hydrated = await withHydratedThumbnails(projects, assetField: "projectPoster", fileName: { "\($0.uuidString)_poster.jpg" })

        print("✅ Fetched \(hydrated.count) approved projects")
        return hydrated
    }
    
    func deleteProject(_ project: Project) async throws {
        let recordID = CKRecord.ID(recordName: project.id.uuidString)
        try await delete(recordID: recordID)
    }
    
    // MARK: - Event Operations
    
    func saveEvent(_ event: Event, preservingOwner: Bool = false) async throws {
        print("🔵 Saving Event: \(event.title)")
        let record = try await event.toCloudKitRecord(userRecordID: ownerRecordID(preservingOwner: preservingOwner))
        stampSchool(on: record, preservingOwner: preservingOwner)
        try await save(record: record)
    }
    
    func fetchAllEvents() async throws -> [Event] {
        let query = CKQuery(recordType: "EventSubmission", predicate: SchoolScope.predicate())
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let events = try await fetchAllRecords(matching: query, desiredKeys: FeedKeys.event).compactMap(Event.fromCloudKitRecord)
        let hydrated = await withHydratedThumbnails(events, assetField: "eventFlyer", fileName: { "\($0.uuidString)_flyer.jpg" })

        print("✅ Fetched \(hydrated.count) events")
        return hydrated
    }
    
    func fetchApprovedEvents() async throws -> [Event] {
        let predicate = SchoolScope.predicate(and: NSPredicate(format: "isApproved == 1"))
        let query = CKQuery(recordType: "EventSubmission", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let events = try await fetchAllRecords(matching: query, desiredKeys: FeedKeys.event).compactMap(Event.fromCloudKitRecord)
        let hydrated = await withHydratedThumbnails(events, assetField: "eventFlyer", fileName: { "\($0.uuidString)_flyer.jpg" })

        print("✅ Fetched \(hydrated.count) approved events")
        return hydrated
    }
    
    func deleteEvent(_ event: Event) async throws {
        let recordID = CKRecord.ID(recordName: event.id.uuidString)
        try await delete(recordID: recordID)
    }
    
    // MARK: - Photography Operations

    func savePhotography(_ photography: Photography, preservingOwner: Bool = false) async throws {
        print("🔵 Saving Photography: \(photography.title)")
        let record = try await photography.toCloudKitRecord(userRecordID: ownerRecordID(preservingOwner: preservingOwner))
        stampSchool(on: record, preservingOwner: preservingOwner)
        try await save(record: record)
    }

    func fetchAllPhotography() async throws -> [Photography] {
        let query = CKQuery(recordType: "PhotographySubmission", predicate: SchoolScope.predicate())
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]

        let photos = try await fetchAllRecords(matching: query, desiredKeys: FeedKeys.photography).compactMap(Photography.fromCloudKitRecord)
        let hydrated = await withHydratedThumbnails(photos, assetField: "photographyThumbnail", fileName: { "\($0.uuidString)_thumb.jpg" })

        print("✅ Fetched \(hydrated.count) photography posts")
        return hydrated
    }

    func fetchApprovedPhotography() async throws -> [Photography] {
        let predicate = SchoolScope.predicate(and: NSPredicate(format: "isApproved == 1"))
        let query = CKQuery(recordType: "PhotographySubmission", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]

        let photos = try await fetchAllRecords(matching: query, desiredKeys: FeedKeys.photography).compactMap(Photography.fromCloudKitRecord)
        let hydrated = await withHydratedThumbnails(photos, assetField: "photographyThumbnail", fileName: { "\($0.uuidString)_thumb.jpg" })

        print("✅ Fetched \(hydrated.count) approved photography posts")
        return hydrated
    }

    func deletePhotography(_ photography: Photography) async throws {
        let recordID = CKRecord.ID(recordName: photography.id.uuidString)
        try await delete(recordID: recordID)
    }

    // MARK: - Design Operations

    func saveDesign(_ design: Design, preservingOwner: Bool = false) async throws {
        print("🔵 Saving Design: \(design.title)")
        let record = try await design.toCloudKitRecord(userRecordID: ownerRecordID(preservingOwner: preservingOwner))
        stampSchool(on: record, preservingOwner: preservingOwner)
        try await save(record: record)
    }

    func fetchAllDesign() async throws -> [Design] {
        let query = CKQuery(recordType: "DesignSubmission", predicate: SchoolScope.predicate())
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]

        let designs = try await fetchAllRecords(matching: query, desiredKeys: FeedKeys.design).compactMap(Design.fromCloudKitRecord)
        let hydrated = await withHydratedThumbnails(designs, assetField: "designThumbnail", fileName: { "\($0.uuidString)_thumb.jpg" })

        print("✅ Fetched \(hydrated.count) design posts")
        return hydrated
    }

    func fetchApprovedDesign() async throws -> [Design] {
        let predicate = SchoolScope.predicate(and: NSPredicate(format: "isApproved == 1"))
        let query = CKQuery(recordType: "DesignSubmission", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]

        let designs = try await fetchAllRecords(matching: query, desiredKeys: FeedKeys.design).compactMap(Design.fromCloudKitRecord)
        let hydrated = await withHydratedThumbnails(designs, assetField: "designThumbnail", fileName: { "\($0.uuidString)_thumb.jpg" })

        print("✅ Fetched \(hydrated.count) approved design posts")
        return hydrated
    }

    func deleteDesign(_ design: Design) async throws {
        let recordID = CKRecord.ID(recordName: design.id.uuidString)
        try await delete(recordID: recordID)
    }

    // MARK: - Fetch All Approved (Combined)

    /// Fetch all approved items across all types
    /// Returns them as a tuple that you can process individually
    ///
    /// Each type is fetched independently (see `FeedFetch.tolerating`): one type
    /// failing yields no posts of that type rather than an empty feed.
    func fetchAllApprovedItems() async -> (films: [Film], music: [Music], reels: [Reel], projects: [Project], events: [Event], photography: [Photography], design: [Design]) {
        async let films = FeedFetch.tolerating("Film") { try await fetchApprovedFilms() }
        async let music = FeedFetch.tolerating("Music") { try await fetchApprovedMusic() }
        async let reels = FeedFetch.tolerating("Reel") { try await fetchApprovedReels() }
        async let projects = FeedFetch.tolerating("Project") { try await fetchApprovedProjects() }
        async let events = FeedFetch.tolerating("Event") { try await fetchApprovedEvents() }
        async let photography = FeedFetch.tolerating("Photography") { try await fetchApprovedPhotography() }
        async let design = FeedFetch.tolerating("Design") { try await fetchApprovedDesign() }

        return await (films, music, reels, projects, events, photography, design)
    }
    
    // MARK: - Generic Record Operations (Protocol Conformance)
    
    /// Fetch records of a specific type with optional sorting
    func fetchRecords(ofType recordType: String, sortBy sortKey: String?) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        if let sortKey = sortKey {
            query.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: false)]
        }
        
        let records = try await fetchAllRecords(matching: query)

        print("✅ Fetched \(records.count) records of type: \(recordType)")
        return records
    }
    
    /// Fetch records matching a predicate with optional sorting
    func fetchRecords(ofType recordType: String, matching predicate: NSPredicate, sortBy sortKey: String?) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: predicate)
        if let sortKey = sortKey {
            query.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: false)]
        }
        
        let records = try await fetchAllRecords(matching: query)

        print("✅ Fetched \(records.count) records of type: \(recordType) with predicate")
        return records
    }
    
    /// Fetch a single record by ID
    func fetchRecord(withID recordID: CKRecord.ID) async throws -> CKRecord {
        let record = try await database.record(for: recordID)
        print("✅ Fetched record: \(recordID.recordName)")
        return record
    }

    /// Checks whether a record with this ID currently exists in CloudKit.
    ///
    /// Used as a safety net during sync reconciliation: `syncedRecordIDs` is a local
    /// heuristic that can drift, so before re-uploading a post the app thinks is
    /// missing we verify against the server directly. The result distinguishes three
    /// cases so callers never resurrect a deleted post *or* silently drop a genuine
    /// offline-created one:
    ///   - `true`  → the record is on the server (our fetch just missed it).
    ///   - `false` → confirmed absent (`.unknownItem`): deleted or never uploaded.
    ///   - `nil`   → couldn't determine (network/other error); caller should wait.
    func recordExists(id: UUID) async -> Bool? {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        do {
            _ = try await database.record(for: recordID)
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return false
        } catch {
            print("⚠️ recordExists check inconclusive for \(id): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Submission Operations (Legacy Support)
    
    /// Save a submission (for backwards compatibility)
    func saveSubmission(_ submission: Submission) async throws {
        print("🔵 Saving legacy Submission: \(submission.title)")
        let record = try submission.toCloudKitRecord(userRecordID: userRecordID)
        try await save(record: record)
    }
    
    /// Fetch all approved submissions (legacy)
    func fetchAllApprovedSubmissions() async throws -> [Submission] {
        let predicate = NSPredicate(format: "isApproved == 1")
        let query = CKQuery(recordType: "Submission", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let submissions = try await fetchAllRecords(matching: query).compactMap(Submission.fromCloudKitRecord)

        print("✅ Fetched \(submissions.count) approved submissions")
        return submissions
    }
    
    /// Fetch all submissions (legacy)
    func fetchAllSubmissions() async throws -> [Submission] {
        let query = CKQuery(recordType: "Submission", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
        
        let submissions = try await fetchAllRecords(matching: query).compactMap(Submission.fromCloudKitRecord)

        print("✅ Fetched \(submissions.count) total submissions")
        return submissions
    }
    
    /// Update submission approval status (legacy)
    func updateSubmissionApproval(submissionId: String, isApproved: Bool) async throws {
        let recordID = CKRecord.ID(recordName: submissionId)
        let record = try await fetchRecord(withID: recordID)
        record["isApproved"] = isApproved ? 1 : 0
        try await save(record: record)
        print("✅ Updated approval status for: \(submissionId)")
    }
    
    /// Delete a submission (legacy)
    func deleteSubmission(_ submission: Submission) async throws {
        let recordID = CKRecord.ID(recordName: submission.id.uuidString)
        try await delete(recordID: recordID)
    }

    // MARK: - Moderation Actions (cross-device removals)

    /// Deterministic record name so re-moderating a post overwrites the single action
    /// record for it instead of piling up duplicates.
    private func moderationRecordID(for postID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "moderation_\(postID.uuidString)")
    }

    /// Records a moderator's decision (remove or restore) for a post so it reaches
    /// every device — not just the moderator's.
    ///
    /// A removal can't rely on writing the post record itself: under the public
    /// database's default security roles only the account that CREATED a post may modify
    /// or delete it, so a moderator's write to another user's post fails and the post
    /// repopulates on other devices. The moderator DOES own these `ModerationAction`
    /// records, so this write always succeeds, and every device honors it on the next
    /// sync. (Moderator *edits* do write the post record directly — see
    /// `SubmissionStore_3_2.update` — which needs the submission record types to grant
    /// authenticated users Write in the schema's security roles.)
    func saveModerationAction(postID: UUID, isRemoved: Bool) async throws {
        let record = CKRecord(recordType: "ModerationAction", recordID: moderationRecordID(for: postID))
        record["postID"] = postID.uuidString as CKRecordValue
        record["isRemoved"] = (isRemoved ? 1 : 0) as CKRecordValue
        record["modifiedAt"] = Date() as CKRecordValue
        try await save(record: record)
    }

    /// Fetches every moderation decision. There is exactly one record per moderated
    /// post (deterministic record name), so the latest decision is authoritative.
    /// Callers apply these to their local hidden set so removed posts stay out of the
    /// feeds — and restored posts come back — on all devices.
    func fetchModerationActions() async throws -> [ModerationAction] {
        let query = CKQuery(recordType: "ModerationAction", predicate: NSPredicate(value: true))
        let records = try await fetchAllRecords(matching: query)
        return records.compactMap { record in
            guard let idString = record["postID"] as? String,
                  let postID = UUID(uuidString: idString) else { return nil }
            let isRemoved = ((record["isRemoved"] as? Int) ?? 0) == 1
            let modifiedAt = (record["modifiedAt"] as? Date) ?? record.creationDate ?? .distantPast
            return ModerationAction(postID: postID, isRemoved: isRemoved, modifiedAt: modifiedAt)
        }
    }

    // MARK: - Subscriptions

    /// Subscribe to all media types for real-time updates
    func setupAutomaticSync() async {
        do {
            try await subscribeToRecordType("FilmSubmission", subscriptionID: "film-changes")
            try await subscribeToRecordType("MusicSubmission", subscriptionID: "music-changes")
            try await subscribeToRecordType("ReelSubmission", subscriptionID: "reel-changes")
            try await subscribeToRecordType("ProjectSubmission", subscriptionID: "project-changes")
            try await subscribeToRecordType("EventSubmission", subscriptionID: "event-changes")
            print("✅ Automatic sync enabled for all media types")
        } catch {
            print("❌ Failed to setup automatic sync: \(error)")
        }
    }
    
    func subscribeToRecordType(_ recordType: String, subscriptionID: String) async throws {
        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )

        // Silent background wake only: pull the new/updated/deleted post into the local
        // store without showing a banner. Feed changes shouldn't notify every user — only
        // messages produce visible notifications. Saving unconditionally (rather than
        // bailing out when the subscription already exists) also lets this replace any
        // older subscription that still carried the "New … available" alert body.
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        _ = try await database.save(subscription)
        print("✅ Subscribed to \(recordType) changes (silent)")
    }
}

// MARK: - Feed Fetch Tolerance

/// Runs one record type's feed fetch so that its failure costs only that type.
///
/// The seven post types are fetched in parallel and were then bound with a single
/// `try await (…)` tuple, which meant one type's failure threw away every other
/// type's posts and left the app with no posts at all. That is not a hypothetical:
/// a record type or field missing from the deployed container is the recurring bug
/// in this project, and `DesignSubmission` is unqueryable in both environments
/// right now ("Type is not marked indexable"), which emptied the entire feed.
///
/// A gap in one type should cost that type's posts and nothing else, matching how
/// the upload path already sheds unknown fields rather than failing the post.
@MainActor
enum FeedFetch {

    /// The fetch's results, or an empty array if it failed.
    static func tolerating<T>(_ label: String, _ fetch: () async throws -> [T]) async -> [T] {
        do {
            return try await fetch()
        } catch {
            print("⚠️ \(label) fetch failed — showing the rest of the feed without it: \(error.localizedDescription)")
            return []
        }
    }
}

// MARK: - Moderation Action Model

/// A moderator's decision about a post, replicated through the public database so it
/// applies on every device. See `CloudKitManager.saveModerationAction`.
struct ModerationAction {
    let postID: UUID
    /// `true` = removed/hidden from all feeds; `false` = restored.
    let isRemoved: Bool
    let modifiedAt: Date
}
