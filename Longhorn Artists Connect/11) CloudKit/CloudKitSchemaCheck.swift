//
//  CloudKitSchemaCheck.swift
//  Longhorn Artists Connect
//
//  Read-only check of the *deployed* CloudKit schema, so a field the app writes but the
//  schema doesn't have is caught before a large video uploads — and listed, on device,
//  exactly as it needs to be added in CloudKit Dashboard.
//

import SwiftUI
import CloudKit
import Combine

// MARK: - Field Type

/// A CloudKit field type, as named by CloudKit Web Services.
nonisolated enum CKFieldType: String, Codable, Hashable, Sendable {
    case string = "STRING"
    case stringList = "STRING_LIST"
    case int64 = "NUMBER_INT64"
    case double = "NUMBER_DOUBLE"
    case timestamp = "TIMESTAMP"
    case asset = "ASSET"
    case assetList = "ASSET_LIST"

    /// The type as it's picked in CloudKit Dashboard's "Add Field" menu.
    var dashboardName: String {
        switch self {
        case .string:     return "String"
        case .stringList: return "String List"
        case .int64:      return "Int(64)"
        case .double:     return "Double"
        case .timestamp:  return "Date/Time"
        case .asset:      return "Asset"
        case .assetList:  return "Asset List"
        }
    }

    /// The type of a value the app is about to write, or nil for one this check doesn't model.
    init?(value: CKRecordValue) {
        switch value {
        case is CKAsset:   self = .asset
        case is [CKAsset]: self = .assetList
        case is String:    self = .string
        case is [String]:  self = .stringList
        case is Date:      self = .timestamp
        case let number as NSNumber:
            self = CFNumberIsFloatType(number) ? .double : .int64
        default:
            return nil
        }
    }

    /// Whether a deployed field of type `deployed` accepts this type. Assets and asset
    /// lists answer the probe identically, so they're treated as interchangeable.
    func isCompatible(withDeployed deployed: CKFieldType) -> Bool {
        let assets: Set<CKFieldType> = [.asset, .assetList]
        if assets.contains(self) && assets.contains(deployed) { return true }
        return self == deployed
    }
}

// MARK: - Schema Gap

/// One way the deployed schema falls short of what the app writes.
nonisolated struct SchemaGap: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// The field doesn't exist on the record type.
        case missingField
        /// The field exists with a different type than the app writes (fails the save too).
        case wrongType
        /// The whole record type doesn't exist.
        case missingRecordType
    }

    let recordType: String
    /// Empty for `missingRecordType`.
    let field: String
    let kind: Kind
    /// What the app writes.
    let expected: CKFieldType?
    /// What's deployed (`wrongType` only).
    let deployed: CKFieldType?

    var id: String { "\(recordType)/\(field)/\(kind.rawValue)" }

    /// One line of the Dashboard checklist.
    var checklistLine: String {
        switch kind {
        case .missingField:
            return "+ \(field) — \(expected?.dashboardName ?? "?")"
        case .wrongType:
            return "! \(field) — is \(deployed?.dashboardName ?? "?"), app writes \(expected?.dashboardName ?? "?")"
        case .missingRecordType:
            return "+ record type \(recordType) doesn't exist"
        }
    }
}

// MARK: - Schema Check

/// Probes the deployed schema one field at a time through CloudKit Web Services.
///
/// Each probe is a query filtering the field against a deliberately wrong-typed value
/// (a LOCATION — a type the app never writes), so CloudKit always refuses it — and its
/// refusal says exactly what's deployed:
///   - `Did not find field: 'x'` → the field is missing
///   - `Invalid value, expected type STRING_LIST` → present, with that type
///   - `missing required field 'fileChecksum'` → present, an asset (or asset list)
///   - HTTP 404 `could not find record_type` → the record type itself is missing
/// Read-only and account-free (API token), so it costs nothing next to a video upload.
nonisolated enum CloudKitSchemaCheck {

    /// What the deployed schema says about one field.
    private enum ProbeResult: Sendable {
        case present(CKFieldType?)   // nil = present with a type this check doesn't model
        case missingField
        case missingRecordType
        case unknown                 // not configured / network error / unexpected reply
    }

    /// Fields already confirmed present-and-compatible this session, keyed
    /// `env/type/field`. Gaps are never cached, so a field added in Dashboard is seen
    /// on the very next check.
    private actor ConfirmedCache {
        private var confirmed: Set<String> = []
        func contains(_ key: String) -> Bool { confirmed.contains(key) }
        func insert(_ key: String) { confirmed.insert(key) }
    }
    private static let cache = ConfirmedCache()

    // MARK: Public API

    /// The gaps between what `record` is about to write and the deployed schema.
    /// Empty when everything's in place **or** the check couldn't run — an unknown
    /// never blocks or strips anything; the save's own drop-and-retry still applies.
    static func gaps(for record: CKRecord) async -> [SchemaGap] {
        var expected: [String: CKFieldType] = [:]
        for key in record.allKeys() {
            if let value = record[key], let type = CKFieldType(value: value) {
                expected[key] = type
            }
        }
        return await gaps(recordType: record.recordType, expected: expected)
    }

    /// Why a post of `type` can't be posted right now, or nil when its record type and
    /// every field it can write (see `manifest`) are deployed with the right types.
    ///
    /// The Share form's gate. Stripping gaps at upload time kept posts alive, but every
    /// schema gap still ended as a post that flashed and vanished or went up missing
    /// data, so posting is refused outright until the Dashboard catches up. That also
    /// covers a check that can't run (no API token, offline): unverified isn't ready.
    /// Applies in both environments, since fields are added in Dashboard by hand either way.
    static func postingBlocker(for type: MediaType) async -> String? {
        let recordType = recordType(for: type)
        guard CloudKitWebServices.isConfigured else {
            return "This build is missing its CloudKit API token, so it can't confirm CloudKit is ready for \(type.displayName) posts."
        }
        guard let expected = manifest[recordType] else { return nil }

        let (gaps, unverified) = await check(recordType: recordType, expected: expected)
        await MainActor.run { SchemaGapCenter.shared.update(recordType: recordType, gaps: gaps) }

        if !gaps.isEmpty {
            let lines = gaps.map { "  " + $0.checklistLine }.joined(separator: "\n")
            return """
            CloudKit (\(CloudKitWebServices.environment)) isn't set up for \(type.displayName) posts yet. \
            Add these to \(recordType) in CloudKit Dashboard, then Deploy Schema Changes:
            \(lines)
            """
        }
        if !unverified.isEmpty {
            return "Couldn't confirm CloudKit is ready for \(type.displayName) posts. Check your connection and try again."
        }
        return nil
    }

    /// The CloudKit record type each post type saves to.
    static func recordType(for type: MediaType) -> String {
        switch type {
        case .film:        return CloudKitRecordTypes.film
        case .music:       return CloudKitRecordTypes.music
        case .reel:        return CloudKitRecordTypes.reel
        case .project:     return CloudKitRecordTypes.project
        case .event:       return CloudKitRecordTypes.event
        case .photography: return CloudKitRecordTypes.photography
        case .design:      return CloudKitRecordTypes.design
        }
    }

    /// Checks every post type's full field list (see `manifest`), for the Secret page.
    static func checkAllPostTypes() async -> [String: [SchemaGap]] {
        await withTaskGroup(of: (String, [SchemaGap]).self) { group in
            for (recordType, fields) in manifest {
                group.addTask { (recordType, await gaps(recordType: recordType, expected: fields)) }
            }
            var result: [String: [SchemaGap]] = [:]
            for await (recordType, gaps) in group { result[recordType] = gaps }
            return result
        }
    }

    /// The Dashboard checklist for `gaps`, ready to copy.
    static func checklist(_ gaps: [SchemaGap], environment: String) -> String {
        guard !gaps.isEmpty else { return "✅ CloudKit \(environment): every field the app writes exists." }
        var lines = ["CloudKit Dashboard → \(environment) — add these, then Deploy Schema Changes:"]
        for recordType in Set(gaps.map(\.recordType)).sorted() {
            lines.append("")
            lines.append(recordType)
            for gap in gaps.filter({ $0.recordType == recordType }).sorted(by: { $0.field < $1.field }) {
                lines.append("  " + gap.checklistLine)
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Probing

    private static func gaps(recordType: String, expected: [String: CKFieldType]) async -> [SchemaGap] {
        await check(recordType: recordType, expected: expected).gaps
    }

    /// The gaps, plus the fields whose probe couldn't get an answer (`unverified`).
    private static func check(
        recordType: String,
        expected: [String: CKFieldType]
    ) async -> (gaps: [SchemaGap], unverified: [String]) {
        let env = CloudKitWebServices.environment
        guard CloudKitWebServices.isConfigured, !expected.isEmpty else { return ([], []) }

        let results = await withTaskGroup(of: (String, CKFieldType, ProbeResult).self) { group in
            for (field, type) in expected {
                group.addTask {
                    let key = "\(env)/\(recordType)/\(field)"
                    if await cache.contains(key) { return (field, type, .present(type)) }
                    return (field, type, await probe(recordType: recordType, field: field))
                }
            }
            var all: [(String, CKFieldType, ProbeResult)] = []
            for await result in group { all.append(result) }
            return all
        }

        var gaps: [SchemaGap] = []
        var unverified: [String] = []
        for (field, type, result) in results {
            switch result {
            case .missingRecordType:
                // One entry covers the whole type; its fields are moot until it exists.
                return ([SchemaGap(recordType: recordType, field: "", kind: .missingRecordType, expected: nil, deployed: nil)], [])
            case .missingField:
                gaps.append(SchemaGap(recordType: recordType, field: field, kind: .missingField, expected: type, deployed: nil))
            case .present(let deployed?) where !type.isCompatible(withDeployed: deployed):
                gaps.append(SchemaGap(recordType: recordType, field: field, kind: .wrongType, expected: type, deployed: deployed))
            case .present:
                await cache.insert("\(env)/\(recordType)/\(field)")
            case .unknown:
                unverified.append(field)
            }
        }
        return (gaps.sorted { $0.field < $1.field }, unverified.sorted())
    }

    private static func probe(recordType: String, field: String) async -> ProbeResult {
        guard let endpoint = URL(string:
            "https://api.apple-cloudkit.com/database/1/\(CloudKitWebServices.containerID)/\(CloudKitWebServices.environment)/public/records/query?ckAPIToken=\(CloudKitWebServices.apiToken)"
        ) else { return .unknown }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let query: [String: Any] = [
            "recordType": recordType,
            "filterBy": [[
                "fieldName": field,
                "comparator": "EQUALS",
                "fieldValue": ["value": ["latitude": 0, "longitude": 0], "type": "LOCATION"]
            ]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query, "resultsLimit": 1])

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let status = (response as? HTTPURLResponse)?.statusCode
        else { return .unknown }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let reason = json?["reason"] as? String ?? ""

        if status == 404 || reason.contains("could not find record_type") { return .missingRecordType }
        if reason.contains("Did not find field") { return .missingField }
        if reason.contains("fileChecksum") { return .present(.asset) }
        if let range = reason.range(of: "expected type ") {
            let name = reason[range.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            return .present(CKFieldType(rawValue: String(name)))
        }
        return .unknown
    }

    // MARK: Manifest

    /// Every field each post type writes, with its type — mirrors the post models'
    /// `toCloudKitRecord` (plus `SchoolScope`'s `schoolID`). Only used by the Secret
    /// page's "check everything" button; uploads check the real record instead, so a
    /// field missing from this table can't cause a bad save — it just goes unchecked
    /// here. Add new fields to this table when adding them to a model.
    static let manifest: [String: [String: CKFieldType]] = {
        let shared: [String: CKFieldType] = [
            "isApproved": .int64, "submittedBy": .string, "createdDate": .timestamp,
            "lastEditedDate": .timestamp, "userID": .string, "schoolID": .string
        ]
        let perType: [String: [String: CKFieldType]] = [
            "FilmSubmission": [
                "filmTitle": .string, "filmDescription": .string, "filmAgeRating": .string,
                "filmBTS": .assetList, "filmCast": .stringList, "filmCastIDs": .stringList,
                "filmCrew": .stringList, "filmCrewIDs": .stringList, "filmExplicit": .int64,
                "filmFestivalBound": .int64, "filmGenres": .stringList, "filmLogline": .string,
                "filmReleaseYear": .string, "filmStills": .assetList, "filmStudio": .string,
                "filmThumbnail": .asset, "filmTrailer": .asset, "filmVideo": .asset,
                "filmVideoCrop": .string, "filmVideoDuration": .double
            ],
            "MusicSubmission": [
                "musicTitle": .string, "musicDescription": .string, "musicArtist": .string,
                "musicAudio": .asset, "musicAudioDuration": .double, "musicAudioExt": .string,
                "musicCategory": .string, "musicCover": .asset, "musicExplicit": .int64,
                "musicGenres": .stringList, "musicProduction": .stringList,
                "musicProductionIDs": .stringList, "musicRecording": .stringList,
                "musicRecordingIDs": .stringList, "musicReleaseYear": .string,
                "musicTracks": .assetList, "musicTrackExts": .stringList, "musicVideo": .asset,
                "lyrics": .string, "musicSpotifyLink": .string, "musicAppleMusicLink": .string,
                "amazonMusicLink": .string, "soundcloudLink": .string, "youtubeMusicLink": .string
            ],
            "ReelSubmission": [
                "reelTitle": .string, "reelDescription": .string, "reelType": .string,
                "reelArtist": .string, "reelReleaseYear": .string, "reelVideo": .asset,
                "reelThumbnail": .asset, "reelStills": .assetList, "reelVideoCrop": .string,
                "reelVideoDuration": .double, "orderedCrew": .stringList,
                "orderedCrewIDs": .stringList, "orderedCast": .stringList,
                "orderedCastIDs": .stringList, "featuredWork": .stringList,
                "featuredWorkManual": .stringList
            ],
            "PhotographySubmission": [
                "photographyTitle": .string, "photographyDescription": .string,
                "photographyArtist": .string, "photographyGear": .stringList,
                "photographyImages": .assetList, "photographyReleaseYear": .string,
                "photographyThumbnail": .asset, "orderedCrew": .stringList,
                "orderedCrewIDs": .stringList
            ],
            "DesignSubmission": [
                "designTitle": .string, "designDescription": .string, "designCategory": .string,
                "designImages": .assetList, "designReleaseYear": .string,
                "designThumbnail": .asset, "designVideo": .asset, "designVideoCrop": .string,
                "designVideoDuration": .double, "orderedCrew": .stringList,
                "orderedCrewIDs": .stringList,
                // Design's own date fields; the shared createdDate/lastEditedDate are
                // removed below (see `Design.toCloudKitRecord`).
                "designCreatedDate": .timestamp, "designLastEditedDate": .timestamp
            ],
            "ProjectSubmission": [
                "projectTitle": .string, "projectDescription": .string,
                "projectCastAssembled": .stringList, "projectCastAssembledIDs": .stringList,
                "projectCastNeeded": .stringList, "projectCrewAssembled": .stringList,
                "projectCrewAssembledIDs": .stringList, "projectCrewNeeded": .stringList,
                "projectExpectedReleaseDate": .timestamp, "projectGenres": .stringList,
                "projectPoster": .asset, "projectReleaseDateText": .string,
                "projectShootDatesText": .string, "projectShootStart": .timestamp,
                "projectSlides": .assetList, "projectAuditionURL": .string,
                "projectContacts": .stringList, "projectStudio": .string
            ],
            "EventSubmission": [
                "eventTitle": .string, "eventDescription": .string,
                "eventApplicationURL": .string, "eventCategory": .string,
                "eventStartTime": .timestamp, "eventEndTime": .timestamp,
                "eventExpectations": .string, "eventFlyer": .asset, "eventHost": .string,
                "eventLineup": .stringList, "eventLocationText": .string,
                "eventRSVPURL": .string, "eventShowtimes": .stringList,
                "eventTicketsURL": .string, "eventWebsiteURL": .string
            ]
        ]
        var merged = perType.mapValues { $0.merging(shared) { own, _ in own } }
        // DesignSubmission's shared date fields were deployed as STRING and Design no
        // longer writes them, so they aren't required.
        merged["DesignSubmission"]?["createdDate"] = nil
        merged["DesignSubmission"]?["lastEditedDate"] = nil
        // Not a post, but a field the Artist / Enthusiast flow depends on (see
        // `AccountKind`). Listed here so the Secret page's check flags it.
        merged[CloudKitRecordTypes.userProfile] = [
            "accountKind": .string
        ]
        return merged
    }()
}

// MARK: - Schema Gap Center

/// The latest known schema gaps, per record type, for the on-device report. Fed by
/// every post upload's pre-flight check and by the Secret page's "Check Schema".
/// Persisted (per CloudKit environment) so a TestFlight build still shows what an
/// earlier upload found after a relaunch.
@MainActor
final class SchemaGapCenter: ObservableObject {
    static let shared = SchemaGapCenter()

    private let defaultsKey = "\(CloudKitEnvironmentDetector.localCachePrefix)cloudKitSchemaGaps"

    /// Latest gaps keyed by record type. A type checked clean is removed, so fixing a
    /// field in Dashboard clears it from the report on the next check.
    @Published private(set) var gapsByRecordType: [String: [SchemaGap]] = [:]

    var allGaps: [SchemaGap] {
        gapsByRecordType.keys.sorted().flatMap { gapsByRecordType[$0] ?? [] }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: [SchemaGap]].self, from: data) {
            gapsByRecordType = decoded
        }
    }

    /// Replaces what's known about `recordType` with a fresh check's result.
    func update(recordType: String, gaps: [SchemaGap]) {
        gapsByRecordType[recordType] = gaps.isEmpty ? nil : gaps
        if let data = try? JSONEncoder().encode(gapsByRecordType) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

// MARK: - On-Device Report

/// The Dashboard checklist, grouped by record type, with Copy and Re-check buttons.
struct SchemaGapReportView: View {
    @ObservedObject private var center = SchemaGapCenter.shared
    @State private var isChecking = false
    @State private var copied = false

    private var environmentName: String { CloudKitEnvironmentDetector.current }

    var body: some View {
        let gaps = center.allGaps
        Text(gaps.isEmpty
             ? "No known gaps in \(environmentName). Tap Check Schema to verify every post type."
             : "Add these in CloudKit Dashboard → \(environmentName), then Deploy Schema Changes. + = add field, ! = fix type.")
            .font(.caption)
            .foregroundStyle(.secondary)

        ForEach(Array(Set(gaps.map(\.recordType))).sorted(), id: \.self) { recordType in
            VStack(alignment: .leading, spacing: 4) {
                Text(recordType)
                    .font(.subheadline.weight(.semibold))
                ForEach(gaps.filter { $0.recordType == recordType }) { gap in
                    Text(gap.checklistLine)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(gap.kind == .wrongType ? Color.orange : Color.primary)
                }
            }
            .textSelection(.enabled)
            .padding(.vertical, 2)
        }

        if !gaps.isEmpty {
            Button(copied ? "Copied" : "Copy Checklist") {
                UIPasteboard.general.string = CloudKitSchemaCheck.checklist(gaps, environment: environmentName)
                copied = true
            }
        }

        Button {
            Task { await checkAll() }
        } label: {
            HStack {
                Text(isChecking ? "Checking…" : "Check Schema")
                if isChecking {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(isChecking)
    }

    private func checkAll() async {
        isChecking = true
        copied = false
        let results = await CloudKitSchemaCheck.checkAllPostTypes()
        for (recordType, gaps) in results {
            center.update(recordType: recordType, gaps: gaps)
        }
        print(CloudKitSchemaCheck.checklist(center.allGaps, environment: environmentName))
        isChecking = false
    }
}

/// Home-feed banner shown to moderators while the deployed schema is known to be
/// missing fields the app writes. Tapping opens the full checklist.
struct SchemaGapBanner: View {
    @ObservedObject private var center = SchemaGapCenter.shared
    @AppStorage("isModeratorMode") private var isModeratorMode: Bool = false
    @State private var showReport = false

    var body: some View {
        let count = center.allGaps.count
        if isModeratorMode && count > 0 {
            Button {
                showReport = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.icloud.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CloudKit schema is missing \(count) field\(count == 1 ? "" : "s")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Posts upload without them. Tap to see what to add.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showReport) {
                NavigationStack {
                    List { SchemaGapReportView() }
                        .navigationTitle("CloudKit Schema")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showReport = false }
                            }
                        }
                }
            }
        }
    }
}
