//
//  TVCatalog.swift
//  Longhorn Artists Connect
//
//  The Apple TV app's videos: every approved film and reel, from every school,
//  minus the ones a moderator removed. Read straight from the public database
//  rather than through `SubmissionStore`, which the TV app doesn't include.
//

import CloudKit
import Observation
import UIKit

/// A film or reel the Apple TV app can play.
struct TVVideo: Identifiable, Hashable {

    enum Kind: String, CaseIterable {
        case film
        case reel

        var recordType: String {
            switch self {
            case .film: return CloudKitRecordTypes.film
            case .reel: return CloudKitRecordTypes.reel
            }
        }

        /// Shelf title on the browse screen.
        var shelfTitle: String {
            switch self {
            case .film: return "Films"
            case .reel: return "Reels"
            }
        }

        // Field names, matching `Film` / `Reel` in MediaModels.swift.
        var titleField: String { "\(rawValue)Title" }
        var descriptionField: String { "\(rawValue)Description" }
        var durationField: String { "\(rawValue)VideoDuration" }
        var thumbnailField: String { "\(rawValue)Thumbnail" }
        /// The video asset, streamed through `CloudKitWebServices`.
        var videoField: String { "\(rawValue)Video" }
        /// A big website upload's Cloudflare R2 link, used instead of the asset.
        var externalVideoField: String { "\(rawValue)VideoURL" }

        /// Everything the catalog reads, minus the thumbnail and video assets.
        var feedKeys: [CKRecord.FieldKey] {
            [titleField, descriptionField, durationField, externalVideoField,
             "submittedBy", "createdDate", SchoolScopeField.key]
        }
    }

    let id: UUID
    let kind: Kind
    let title: String
    let creator: String
    let summary: String
    /// Registry slug; an unstamped post is already read as `SchoolRegistry.legacyDefault`.
    let schoolID: String
    let createdDate: Date
    let duration: Double?
    let externalVideoURL: URL?

    var schoolName: String { SchoolRegistry.shortName(forSlug: schoolID) }

    init?(record: CKRecord, kind: Kind) {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        self.id = id
        self.kind = kind
        title = (record[kind.titleField] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"
        creator = record["submittedBy"] as? String ?? ""
        summary = record[kind.descriptionField] as? String ?? ""
        schoolID = SchoolRegistry.slug(record[SchoolScopeField.key] as? String)
        createdDate = record["createdDate"] as? Date ?? record.creationDate ?? .distantPast
        duration = (record[kind.durationField] as? NSNumber)?.doubleValue
        externalVideoURL = (record[kind.externalVideoField] as? String)
            .flatMap(URL.init(string:))
            .flatMap { $0.scheme == "https" ? $0 : nil }
    }

    init(id: UUID = UUID(), kind: Kind, title: String, creator: String, summary: String = "",
         schoolID: String, createdDate: Date = .now, duration: Double? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.creator = creator
        self.summary = summary
        self.schoolID = schoolID
        self.createdDate = createdDate
        self.duration = duration
        externalVideoURL = nil
    }

    /// A range-streamable URL for the video, or nil when there isn't one.
    func streamURL() async -> URL? {
        if let externalVideoURL { return externalVideoURL }
        return await CloudKitWebServices.assetDownloadURL(recordName: id.uuidString, field: kind.videoField)
    }
}

/// `SchoolScope.fieldKey`, which the TV app can't reach.
private enum SchoolScopeField {
    static let key = "schoolID"
}

@Observable
final class TVCatalog {

    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var videos: [TVVideo] = []
    private(set) var thumbnails: [UUID: UIImage] = [:]
    private(set) var phase: Phase = .loading

    @ObservationIgnored private let database = CKContainer.default().publicCloudDatabase

    init() {}

    /// A catalog that's already loaded, for previews.
    init(previewVideos: [TVVideo]) {
        videos = previewVideos
        phase = .loaded
    }

    /// Schools that have at least one video, most videos first — the same order
    /// as the website's school list.
    var schools: [(slug: String, name: String)] {
        let counts = Dictionary(grouping: videos, by: \.schoolID).mapValues(\.count)
        return counts.keys
            .sorted { (counts[$0]!, SchoolRegistry.shortName(forSlug: $1)) > (counts[$1]!, SchoolRegistry.shortName(forSlug: $0)) }
            .map { ($0, SchoolRegistry.shortName(forSlug: $0)) }
    }

    /// Every video, or one school's.
    func videos(inSchool slug: String?) -> [TVVideo] {
        guard let slug else { return videos }
        return videos.filter { $0.schoolID == slug }
    }

    func load() async {
        if videos.isEmpty { phase = .loading }

        async let films = fetch(.film)
        async let reels = fetch(.reel)
        async let removed = removedPostIDs()
        let (filmResult, reelResult, removedIDs) = await (films, reels, removed)

        // Each type is tolerated on its own, so a problem with one doesn't empty the app.
        let fetched = [filmResult, reelResult].compactMap { try? $0.get() }
        guard !fetched.isEmpty else {
            if case .failure(let error) = filmResult, videos.isEmpty {
                phase = .failed(error.localizedDescription)
            }
            return
        }

        videos = fetched.joined()
            .filter { !removedIDs.contains($0.id) }
            .sorted { $0.createdDate > $1.createdDate }
        phase = .loaded

        await loadThumbnails()
    }

    // MARK: - Fetching

    /// Approved posts of one kind. Approval is what puts a post in the iPhone feeds.
    private func fetch(_ kind: TVVideo.Kind) async -> Result<[TVVideo], Error> {
        let query = CKQuery(recordType: kind.recordType, predicate: NSPredicate(format: "isApproved == 1"))
        do {
            let records = try await allRecords(matching: query, desiredKeys: kind.feedKeys)
            return .success(records.compactMap { TVVideo(record: $0, kind: kind) })
        } catch {
            print("📺 Couldn't fetch \(kind.recordType): \(error.localizedDescription)")
            return .failure(error)
        }
    }

    /// Posts a moderator removed. One `ModerationAction` per moderated post; the
    /// latest decision is the record itself (see `CloudKitManager.saveModerationAction`).
    private func removedPostIDs() async -> Set<UUID> {
        let query = CKQuery(recordType: CloudKitRecordTypes.moderationAction, predicate: NSPredicate(value: true))
        guard let records = try? await allRecords(matching: query, desiredKeys: ["postID", "isRemoved"]) else {
            return []
        }
        return Set(records.compactMap { record in
            guard ((record["isRemoved"] as? Int) ?? 0) == 1 else { return nil }
            return (record["postID"] as? String).flatMap(UUID.init(uuidString:))
        })
    }

    private func allRecords(matching query: CKQuery, desiredKeys: [CKRecord.FieldKey]) async throws -> [CKRecord] {
        var (results, cursor) = try await database.records(matching: query, desiredKeys: desiredKeys)
        var records = results.compactMap { try? $0.1.get() }
        while let next = cursor {
            (results, cursor) = try await database.records(continuingMatchFrom: next, desiredKeys: desiredKeys)
            records += results.compactMap { try? $0.1.get() }
        }
        return records
    }

    /// Thumbnails, in batches, after the shelves are already showing.
    private func loadThumbnails() async {
        for kind in TVVideo.Kind.allCases {
            let ids = videos.filter { $0.kind == kind && thumbnails[$0.id] == nil }
                .map { CKRecord.ID(recordName: $0.id.uuidString) }
            for start in stride(from: 0, to: ids.count, by: 50) {
                let batch = Array(ids[start..<min(start + 50, ids.count)])
                guard let results = try? await database.records(for: batch, desiredKeys: [kind.thumbnailField]) else {
                    continue
                }
                for (recordID, result) in results {
                    guard
                        let id = UUID(uuidString: recordID.recordName),
                        let asset = (try? result.get())?[kind.thumbnailField] as? CKAsset,
                        let url = asset.fileURL,
                        let image = UIImage(contentsOfFile: url.path)
                    else { continue }
                    thumbnails[id] = image
                }
            }
        }
    }
}
