//
//  OrganizationCard.swift
//  Longhorn Artists Connect
//
//  Everything behind a single organization: the `Organization` model and its
//  hardcoded section/theme catalog, the CloudKit-backed `OrganizationStore`, the
//  `OrganizationCard` tile, and the org page itself (`OrganizationPageView`) with
//  its content rows and weekly-shorts season views.
//  Extracted from DiscoverView.swift.
//

import SwiftUI
import CloudKit
import Combine

// MARK: - Organization Model

/// A student organization (Studios like Collective/Incubator are a subset). Stored in
/// CloudKit; the *content* of each section is wired in a later phase. Its `id` is a
/// stable slug ("collective", "incubator", "dka", "the-new-project") that keys the
/// hardcoded section layout below.
struct Organization: Identifiable, Hashable {
    let id: String        // stable slug / CloudKit record name key
    var name: String
    var description: String
    var profileImageData: Data?
    var order: Int

    /// The fixed set of sections this org shows.
    var sections: [OrgSection] { OrgSection.sections(for: id) }

    /// Bundled profile-picture asset for this org (keyed by slug). Used when the org has
    /// no CloudKit profile image set.
    var profileAssetName: String? {
        switch id {
        case "longhorn-artists-connect": return "PP Longhorn Artists Connect"
        case "collective":               return "PP Collective"
        case "dka":                      return "PP DKA"
        case "incubator":                return "PP Incubator"
        case "the-new-project":          return "PP The New Project"
        case "black-lens":               return "PP Black Lens"
        case "longhorn-late-night":      return "PP Longhorn Late Night"
        case "texas-supports-live-music": return "PP Texas Supports Live Music"
        case "paradise-music-group":     return "PP Paradise Music Group"
        case "utalent-records":          return "PP UTalent Records"
        case "texas-entertainment-association": return "PP Texas Entertainment Association"
        case "spark-magazine":           return "PP Spark"
        case "longhorn-music-business-club": return "PP Longhorn Music Business Club"
        case "next-week-now":            return "PP Next Week Now"
        default:                         return nil
        }
    }

    /// The description to show. Uses the CloudKit value when set, otherwise a canonical
    /// default per org (so descriptions appear even before/without a backend value).
    var displayDescription: String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        switch id {
        case "longhorn-artists-connect": return "Fostering collaboration between creatives at UT Austin."
        case "collective":               return "A creative studio."
        case "incubator":                return "A select group of students creating five original pilots."
        case "dka":                      return "Delta Kappa Alpha — national professional cinematic society."
        case "the-new-project":          return "Multimedia creative collective/agency — redefining creative spaces at UT Austin."
        case "black-lens":               return "What we create changes the world."
        case "longhorn-late-night":      return "UT Austin’s Best and Only Sketch Comedy Variety Show"
        case "texas-supports-live-music": return "Bringing students together through live music and support for local artists."
        case "paradise-music-group":     return "Welcome to Paradise ATX."
        case "utalent-records":          return "the only student-run record label at the university of texas at austin!"
        case "texas-entertainment-association": return "A preprofessional org for students interested in the business side of entertainment."
        case "spark-magazine":           return "It takes a SPARK. ✧"
        case "longhorn-music-business-club": return "Home to the next generation of industry leaders, learning from the live music capital of the world"
        case "next-week-now":            return "When you know what comes next, everything feels like a joke! | Live every Thursday at 11 P.M."
        default:                         return ""
        }
    }
}

/// A section shown on an org's page. Which sections each org shows is hardcoded (see
/// `sections(for:)`); their content is populated later.
enum OrgSection: String, Identifiable, Hashable {
    case weeklyShortSeasons
    case shortFilms
    case magazines
    case pilots
    case photography
    case graphicDesign
    case music
    case events

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weeklyShortSeasons: return "Weekly Shorts"
        case .shortFilms:         return "Short Films"
        case .magazines:          return "Magazines"
        case .pilots:             return "Pilots"
        case .photography:        return "Photography"
        case .graphicDesign:      return "Graphic Design"
        case .music:              return "Music"
        case .events:             return "Events"
        }
    }

    var icon: String {
        switch self {
        case .weeklyShortSeasons: return "calendar"
        case .shortFilms:         return "film"
        case .magazines:          return "book"
        case .pilots:             return "tv"
        case .photography:        return "camera"
        case .graphicDesign:      return "paintbrush.pointed"
        case .music:              return "music.note"
        case .events:             return "calendar.badge.clock"
        }
    }

    /// The hardcoded section layout per org, keyed by slug.
    static func sections(for orgID: String) -> [OrgSection] {
        switch orgID {
        case "collective":      return [.weeklyShortSeasons, .shortFilms, .magazines]
        case "incubator":       return [.pilots]
        case "dka":             return [.shortFilms]
        case "the-new-project": return [.shortFilms, .photography, .graphicDesign, .music]
        case "next-week-now":   return [.events]
        default:                return []
        }
    }
}

// MARK: - Hardcoded org projects

/// A hardcoded "project" listed under an org section (a Collective short film or magazine,
/// an Incubator pilot, …). Like the Weekly Shorts catalog, each is matched to a real posted
/// submission by title, so it's tappable once the post exists and shown disabled until then.
struct OrgProject: Identifiable, Hashable {
    let title: String
    var id: String { title }
}

/// The hardcoded project lists shown under specific org sections. A section with a
/// non-empty catalog here bypasses the CloudKit-linked content path entirely (there's
/// nothing for a moderator to add in-app), mirroring Collective's Weekly Shorts.
enum OrgProjectCatalog {

    /// The projects shown under a given org + section, in display order.
    static func projects(orgSlug: String, section: OrgSection) -> [OrgProject] {
        let titles: [String]
        switch (orgSlug, section) {
        case ("collective", .shortFilms): titles = ["Pandorox", "Coyote", "Delinquents"]
        case ("collective", .magazines):  titles = ["collective magazine vol. 1",
                                                     "collective magazine vol. 2",
                                                     "collective magazine vol. 3"]
        case ("incubator", .pilots):      titles = ["Wine to Water", "Student Film", "The Queen",
                                                     "This Call May Be Recorded", "Pulse"]
        default:                          titles = []
        }
        return titles.map(OrgProject.init)
    }

    /// Whether this org + section is driven by the hardcoded catalog above.
    static func isCatalogued(orgSlug: String, section: OrgSection) -> Bool {
        !projects(orgSlug: orgSlug, section: section).isEmpty
    }
}

// MARK: - Organization Theme

/// Per-org page colors (background + primary text/icon color).
struct OrgTheme {
    let background: Color
    let text: Color

    static func theme(for orgID: String) -> OrgTheme {
        switch orgID {
        case "longhorn-artists-connect":
            return OrgTheme(background: Color(red: 191/255, green: 87/255, blue: 0/255), text: .white)
        case "black-lens":
            return OrgTheme(background: .black, text: .white)
        case "longhorn-late-night":
            return OrgTheme(background: Color(red: 66/255, green: 85/255, blue: 140/255), text: .white)
        case "texas-supports-live-music":
            return OrgTheme(background: Color(red: 16/255, green: 16/255, blue: 16/255),
                            text: Color(red: 236/255, green: 235/255, blue: 235/255))
        case "paradise-music-group":
            return OrgTheme(background: Color(red: 103/255, green: 174/255, blue: 77/255),
                            text: Color(red: 219/255, green: 183/255, blue: 86/255))
        case "texas-entertainment-association":
            return OrgTheme(background: .black, text: .white)
        case "spark-magazine":
            return OrgTheme(background: .white, text: .black)
        case "longhorn-music-business-club":
            return OrgTheme(background: Color(red: 241/255, green: 232/255, blue: 215/255),
                            text: Color(red: 37/255, green: 31/255, blue: 22/255))
        case "utalent-records":
            return OrgTheme(background: Color(red: 234/255, green: 234/255, blue: 236/255),
                            text: Color(red: 191/255, green: 87/255, blue: 0/255))
        case "collective":
            return OrgTheme(background: Color(red: 42/255, green: 42/255, blue: 227/255), text: .white)
        case "incubator":
            return OrgTheme(background: Color(red: 84/255, green: 95/255, blue: 197/255),
                            text: Color(red: 243/255, green: 254/255, blue: 97/255))
        case "the-new-project":
            return OrgTheme(background: Color(red: 157/255, green: 52/255, blue: 43/255), text: .white)
        case "dka":
            return OrgTheme(background: Color(red: 10/255, green: 35/255, blue: 101/255),
                            text: Color(red: 244/255, green: 203/255, blue: 73/255))
        case "next-week-now":
            return OrgTheme(background: .purple, text: .black)
        default:
            return OrgTheme(background: Color.brandOrange, text: .white)
        }
    }
}

extension Organization {
    var theme: OrgTheme { OrgTheme.theme(for: id) }
}

// MARK: - Organization Content (CloudKit)

/// The special season name for shorts that haven't been assigned to a season yet.
/// Shown as a "Miscellaneous" folder, and hidden entirely when it has no shorts.
let orgMiscellaneousSeason = "Miscellaneous"

/// Links an existing post (submission) into an org's section. For the Weekly Short
/// Seasons section, `season` names the season ("" ⇒ Miscellaneous).
struct OrgContentLink: Identifiable, Hashable {
    let id: String          // CloudKit record name
    let orgSlug: String
    let section: String     // OrgSection.rawValue
    let submissionID: UUID
    var season: String      // only used by .weeklyShortSeasons; "" = Miscellaneous
    var order: Int
}

/// Loads/stores the links that tag posts into org sections.
@MainActor
final class OrgContentStore: ObservableObject {
    static let shared = OrgContentStore()

    @Published var links: [OrgContentLink] = []

    private let database = CKContainer.default().publicCloudDatabase
    private static let recordType = "OrgContentLink"

    private init() { Task { await load() } }

    func load() async {
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        do {
            let results = try await database.records(matching: query)
            links = results.matchResults
                .compactMap { try? $0.1.get() }
                .compactMap(Self.link(from:))
        } catch {
            // Record type may not exist until the first link is created — that's fine.
            print("ℹ️ OrgContentLink fetch failed (\(error.localizedDescription)).")
        }
    }

    /// Links for one org + section, in insertion order.
    func links(orgSlug: String, section: OrgSection) -> [OrgContentLink] {
        links.filter { $0.orgSlug == orgSlug && $0.section == section.rawValue }
            .sorted { $0.order < $1.order }
    }

    /// Distinct seasons for an org's Weekly Short Seasons, newest-named last. A
    /// "Miscellaneous" entry is appended only when unassigned shorts exist.
    func seasons(orgSlug: String) -> [String] {
        let seasonLinks = links(orgSlug: orgSlug, section: .weeklyShortSeasons)
        var named = Array(Set(seasonLinks.map(\.season).filter { !$0.isEmpty })).sorted()
        if seasonLinks.contains(where: { $0.season.isEmpty }) {
            named.append(orgMiscellaneousSeason)
        }
        return named
    }

    /// The shorts in one season ("Miscellaneous" maps to the empty-season links).
    func shorts(orgSlug: String, season: String) -> [OrgContentLink] {
        let target = (season == orgMiscellaneousSeason) ? "" : season
        return links(orgSlug: orgSlug, section: .weeklyShortSeasons)
            .filter { $0.season == target }
    }

    /// Resolves a link's submission from the shared store, if it's loaded.
    func submission(for link: OrgContentLink) -> Submission? {
        let all = SubmissionStore_3_2.shared.approvedSubmissions + SubmissionStore_3_2.shared.submissions
        return all.first { $0.id == link.submissionID }
    }

    func add(orgSlug: String, section: OrgSection, submissionID: UUID, season: String = "") async {
        let recordID = CKRecord.ID(recordName: "OrgLink_\(UUID().uuidString)")
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["orgSlug"] = orgSlug as CKRecordValue
        record["section"] = section.rawValue as CKRecordValue
        record["submissionID"] = submissionID.uuidString as CKRecordValue
        record["season"] = season as CKRecordValue
        record["order"] = links.count as CKRecordValue
        do {
            let saved = try await database.save(record)
            if let link = Self.link(from: saved) { links.append(link) }
        } catch {
            print("❌ Failed to add org content link: \(error.localizedDescription)")
        }
    }

    func remove(_ link: OrgContentLink) async {
        do {
            try await database.deleteRecord(withID: CKRecord.ID(recordName: link.id))
            links.removeAll { $0.id == link.id }
        } catch {
            print("❌ Failed to remove org content link: \(error.localizedDescription)")
        }
    }

    private static func link(from record: CKRecord) -> OrgContentLink? {
        guard let orgSlug = record["orgSlug"] as? String,
              let section = record["section"] as? String,
              let submissionIDString = record["submissionID"] as? String,
              let submissionID = UUID(uuidString: submissionIDString) else { return nil }
        return OrgContentLink(
            id: record.recordID.recordName,
            orgSlug: orgSlug,
            section: section,
            submissionID: submissionID,
            season: record["season"] as? String ?? "",
            order: (record["order"] as? Int) ?? 0
        )
    }
}

// MARK: - Organization Store (CloudKit)

/// Loads organizations from CloudKit and seeds the known four on first run. Seeding
/// creates the `Organization` record type automatically in the Development environment;
/// deploy the schema to Production from the CloudKit Dashboard before release.
@MainActor
final class OrganizationStore: ObservableObject {
    static let shared = OrganizationStore()

    @Published var organizations: [Organization] = []
    @Published var isLoading = true

    private let database = CKContainer.default().publicCloudDatabase
    private static let recordType = "Organization"

    /// The orgs seeded on first run. Order here is their display order.
    private static let seeds: [(slug: String, name: String)] = [
        ("longhorn-artists-connect", "Longhorn Artists Connect"),
        ("collective", "Collective"),
        ("incubator", "Incubator"),
        ("texas-supports-live-music", "Texas Supports Live Music"),
        ("dka", "DKA"),
        ("the-new-project", "The New Project"),
        ("black-lens", "Black Lens"),
        ("paradise-music-group", "Paradise Music Group"),
        ("longhorn-late-night", "Longhorn Late Night"),
        ("utalent-records", "UTalent Records"),
        ("texas-entertainment-association", "Texas Entertainment Association"),
        ("spark-magazine", "Spark Magazine"),
        ("longhorn-music-business-club", "Longhorn Music Business Club"),
        ("next-week-now", "Next Week Now")
    ]

    private init() {
        Task { await load() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        // The seeds list is the source of truth for display order, keyed by slug.
        let seedOrder = Dictionary(uniqueKeysWithValues:
            Self.seeds.enumerated().map { ($0.element.slug, $0.offset) })

        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        do {
            // No sort descriptor (avoids needing a sortable index); we order client-side.
            let results = try await database.records(matching: query)
            var orgs = results.matchResults
                .compactMap { try? $0.1.get() }
                .compactMap(Self.organization(from:))

            // Apply the canonical display order from the seeds list.
            for i in orgs.indices {
                if let order = seedOrder[orgs[i].id] { orgs[i].order = order }
            }

            // Keep stored names in sync with the seed list so a rename (e.g. "Collective
            // Studios" → "Collective") takes effect for orgs already created in CloudKit.
            // A write only happens while a stale name exists; once updated it's a no-op.
            let seedNames = Dictionary(uniqueKeysWithValues: Self.seeds.map { ($0.slug, $0.name) })
            for i in orgs.indices {
                if let seedName = seedNames[orgs[i].id], orgs[i].name != seedName {
                    orgs[i].name = seedName
                    await rename(slug: orgs[i].id, to: seedName)
                }
            }

            // Create any seed orgs missing from CloudKit (first run, or seeds added
            // after the original orgs were already created).
            let existing = Set(orgs.map(\.id))
            let missing = Self.seeds.enumerated().filter { !existing.contains($0.element.slug) }
            orgs.append(contentsOf: await create(missing))

            organizations = Self.backfillingSeeds(orgs)
        } catch {
            // Most commonly the record type doesn't exist yet (first launch) — seed it.
            print("ℹ️ Organization fetch failed (\(error.localizedDescription)); seeding.")
            let created = await create(Array(Self.seeds.enumerated()))
            organizations = Self.backfillingSeeds(created)
        }
    }

    /// Creates the given seed orgs in CloudKit. Uses deterministic record IDs (keyed by
    /// slug) so a re-run can't create duplicates. `offset` is the seed's canonical order.
    private func create(_ seeds: [(offset: Int, element: (slug: String, name: String))]) async -> [Organization] {
        var created: [Organization] = []
        for seed in seeds {
            let recordID = CKRecord.ID(recordName: "Organization_\(seed.element.slug)")
            let record = CKRecord(recordType: Self.recordType, recordID: recordID)
            record["slug"] = seed.element.slug as CKRecordValue
            record["name"] = seed.element.name as CKRecordValue
            record["orgDescription"] = "" as CKRecordValue
            record["order"] = seed.offset as CKRecordValue
            if let saved = try? await database.save(record),
               let org = Self.organization(from: saved) {
                created.append(org)
            }
        }
        return created
    }

    /// Updates the stored `name` of an already-created org record (fire-and-forget), so a
    /// seed rename is reflected for users who created the record under its old name.
    private func rename(slug: String, to name: String) async {
        let recordID = CKRecord.ID(recordName: "Organization_\(slug)")
        guard let record = try? await database.record(for: recordID) else { return }
        record["name"] = name as CKRecordValue
        _ = try? await database.save(record)
    }

    /// The given orgs plus an in-memory stand-in for every seed missing from them, in
    /// canonical order. Creating a seed record fails whenever that record already exists
    /// in CloudKit, so a create pass never returns the full list — without this backfill
    /// a failed fetch would leave only the newly added seed on screen.
    private static func backfillingSeeds(_ orgs: [Organization]) -> [Organization] {
        var result = orgs
        let present = Set(result.map(\.id))
        for (index, seed) in seeds.enumerated() where !present.contains(seed.slug) {
            result.append(Organization(id: seed.slug, name: seed.name, description: "",
                                       profileImageData: nil, order: index))
        }
        return result.sorted { $0.order < $1.order }
    }

    /// Builds an `Organization` from a CloudKit record, loading its profile image asset.
    private static func organization(from record: CKRecord) -> Organization? {
        guard let slug = record["slug"] as? String,
              let name = record["name"] as? String else { return nil }
        var imageData: Data?
        if let asset = record["profileImage"] as? CKAsset, let url = asset.fileURL {
            imageData = try? Data(contentsOf: url)
        }
        return Organization(
            id: slug,
            name: name,
            description: record["orgDescription"] as? String ?? "",
            profileImageData: imageData,
            order: (record["order"] as? Int) ?? 0
        )
    }
}


/// A single organization tile. Sized by its container so all tiles split the page height
/// evenly. Shows the org's profile picture when set, otherwise a placeholder icon.
struct OrganizationCard: View {
    let organization: Organization

    var body: some View {
        let theme = organization.theme
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.background)
            HStack(spacing: 14) {
                OrgAvatar(imageData: organization.profileImageData, diameter: 44, tint: theme.text, assetName: organization.profileAssetName)
                VStack(alignment: .leading, spacing: 4) {
                    Text(organization.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(theme.text)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                    if !organization.displayDescription.isEmpty {
                        Text(organization.displayDescription)
                            .font(.subheadline)
                            .foregroundStyle(theme.text.opacity(0.85))
                            .lineLimit(2)   // rest truncates with "…"
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}

/// Circular org avatar — the profile photo if present, else a person.3 placeholder.
struct OrgAvatar: View {
    let imageData: Data?
    var diameter: CGFloat
    var tint: Color = .white
    /// Bundled asset-catalog image name, used when there's no CloudKit `imageData`.
    var assetName: String? = nil

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let assetName, UIImage(named: assetName) != nil {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.3.fill")
                    .font(.system(size: diameter * 0.45, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.9))
            }
        }
        .frame(width: diameter, height: diameter)
        .background(Circle().fill(tint.opacity(0.2)))
        .clipShape(Circle())
    }
}

// MARK: - Org Page Theming Helper

/// Applies an org's page colors: full-bleed background + a matching (light) nav bar.
private struct OrgThemedPage: ViewModifier {
    let theme: OrgTheme
    func body(content: Content) -> some View {
        content
            .background(theme.background.ignoresSafeArea())
            // Match the nav bar to the org's color so the header reads as part of the page
            // rather than a separate white strip. `.dark` keeps the title/back button light
            // and legible on the (dark) org backgrounds.
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
private extension View {
    func orgThemed(_ theme: OrgTheme) -> some View { modifier(OrgThemedPage(theme: theme)) }
}

/// A themed top bar for pushed org sub-pages (seasons). The org root page hides the
/// system nav bar; if a pushed page re-showed it, its safe-area inset would be applied
/// only after the push animation, making the content visibly shift down once it settled.
/// Hiding the system bar here too (no visibility toggle) and drawing our own matching bar
/// keeps the content anchored throughout the transition.
private struct OrgPushedHeader<Trailing: View>: View {
    let title: String
    let theme: OrgTheme
    @ViewBuilder var trailing: Trailing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.text)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(theme.text.opacity(0.15)))
                }
                Spacer()
                trailing
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.background)
    }
}

// MARK: - Organization Page

/// One organization's page: profile picture, name, description, and its sections shown
/// as sub-headers with their content underneath. Content is managed on the backend —
/// there's no in-app adding. Weekly Short Seasons lists seasons, each pushing to its shorts.
struct OrganizationPageView: View {
    let organization: Organization

    @ObservedObject private var content: OrgContentStore = .shared
    @ObservedObject private var submissionStore: SubmissionStore_3_2 = .shared
    @State private var selected: Submission?
    @State private var selectedEvent: Submission?
    @State private var addSection: OrgSection?

    /// Only moderators can add/remove org content in-app; everyone else sees it read-only.
    private var canModerate: Bool {
        UserDefaults.standard.bool(forKey: "isModeratorMode") && ModeratorAccess.isModerator
    }

    /// Events that credit this org as their host. Auto-derived from the submission store
    /// (matched on the host name), so crediting an org on an event surfaces it here with
    /// no manual linking. Sorted soonest-first.
    private var creditedEvents: [Submission] {
        submissionStore.visibleApprovedSubmissions
            .filter { $0.type == .event
                && $0.eventHost.caseInsensitiveCompare(organization.name) == .orderedSame }
            .sorted { ($0.eventStartDate ?? .distantFuture) < ($1.eventStartDate ?? .distantFuture) }
    }

    var body: some View {
        let theme = organization.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header: a large static profile picture with the org name to its right.
                HStack(spacing: 16) {
                    OrgAvatar(imageData: organization.profileImageData, diameter: 84,
                              tint: theme.text, assetName: organization.profileAssetName)
                    Text(organization.name)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(theme.text)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }

                // Description.
                if !organization.displayDescription.isEmpty {
                    Text(organization.displayDescription)
                        .font(.body)
                        .foregroundStyle(theme.text.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Each section as a sub-header with its content underneath.
                ForEach(organization.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(section.title)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(theme.text)
                            Spacer()
                            // Hardcoded sections (Weekly Shorts, and the project catalogs)
                            // come from in-app catalogs, so there's nothing to add here.
                            if canModerate && !isHardcodedSection(section) {
                                Button { addSection = section } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(theme.text)
                                }
                            }
                        }
                        sectionContent(section, theme: theme)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Events crediting this org, auto-derived from the feed (see
                // `creditedEvents`). Shown only when the org hosts at least one event, and
                // only when it doesn't already declare an `.events` section (which renders
                // the same list under its own header — see `sectionContent`).
                if !organization.sections.contains(.events), !creditedEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Events")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(theme.text)
                        ForEach(creditedEvents) { event in
                            eventButton(event)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        // Presented as a bottom sheet — no nav bar / back button. The themed background
        // fills to the top so the header is the same color as the rest of the page.
        .background(theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await content.load() }
        .sheet(item: $selected) { submission in
            PostDetailRouter(post: submission, liked: .constant(false))
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event)
        }
        .sheet(item: $addSection) { section in
            OrgAddContentView(
                orgSlug: organization.id,
                section: section,
                isSeasonSection: section == .weeklyShortSeasons,
                presetSeason: nil
            )
        }
        .presentationDragIndicator(.hidden)
    }

    /// The content shown under a section's sub-header.
    @ViewBuilder
    private func sectionContent(_ section: OrgSection, theme: OrgTheme) -> some View {
        if section == .weeklyShortSeasons {
            // Collective's Weekly Shorts are hardcoded (see CollectiveStudios); other orgs
            // use the CloudKit-linked seasons.
            if organization.id == "collective" {
                ForEach(CollectiveStudios.seasons, id: \.self) { season in
                    NavigationLink {
                        CollectiveSeasonView(organization: organization, season: season)
                    } label: {
                        OrgSeasonRow(season: "Season \(season)",
                                     count: CollectiveStudios.episodes(inSeason: season).count,
                                     theme: theme)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                let seasons = content.seasons(orgSlug: organization.id)
                if seasons.isEmpty {
                    emptyNote(theme: theme)
                } else {
                    ForEach(seasons, id: \.self) { season in
                        NavigationLink {
                            OrgSeasonShortsView(organization: organization, season: season)
                        } label: {
                            OrgSeasonRow(season: season,
                                         count: content.shorts(orgSlug: organization.id, season: season).count,
                                         theme: theme)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else if section == .events {
            // Events are auto-derived from the feed by host credit (see `creditedEvents`),
            // so there's nothing to link here — posting an event that credits this org
            // surfaces it automatically.
            if creditedEvents.isEmpty {
                emptyNote(theme: theme)
            } else {
                ForEach(creditedEvents) { event in
                    eventButton(event)
                }
            }
        } else if OrgProjectCatalog.isCatalogued(orgSlug: organization.id, section: section) {
            // Hardcoded projects (see OrgProjectCatalog), each matched to a real post by
            // title: tappable once posted, shown disabled ("Not posted yet") until then.
            ForEach(OrgProjectCatalog.projects(orgSlug: organization.id, section: section)) { project in
                let submission = matchedSubmission(forTitle: project.title)
                Button { selected = submission } label: {
                    OrgProjectRow(project: project, submission: submission, theme: theme)
                }
                .buttonStyle(.plain)
                .disabled(submission == nil)
            }
        } else {
            let links = content.links(orgSlug: organization.id, section: section)
            if links.isEmpty {
                emptyNote(theme: theme)
            } else {
                ForEach(links) { link in
                    if let submission = content.submission(for: link) {
                        Button { selected = submission } label: {
                            OrgContentRow(submission: submission, theme: theme)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if canModerate {
                                Button(role: .destructive) {
                                    Task { await content.remove(link) }
                                } label: { Label("Remove", systemImage: "minus.circle") }
                            }
                        }
                    }
                }
            }
        }
    }

    /// One tappable event, rendered with the same `EventCard` as the Discover events feed
    /// (marks it seen and opens its detail sheet, matching Discover).
    private func eventButton(_ event: Submission) -> some View {
        Button {
            SeenContentTracker.shared.markSeen(event.id)
            selectedEvent = event
        } label: {
            EventCard(event: event)
        }
        .buttonStyle(.plain)
    }

    private func emptyNote(theme: OrgTheme) -> some View {
        Text("Nothing here yet.")
            .font(.subheadline)
            .foregroundStyle(theme.text.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Sections whose content comes from in-app sources rather than moderator links
    /// (Collective's Weekly Shorts, any project catalog, and Events — which are derived
    /// from event posts crediting this org), so there's nothing for a moderator to add.
    private func isHardcodedSection(_ section: OrgSection) -> Bool {
        (organization.id == "collective" && section == .weeklyShortSeasons)
            || section == .events
            || OrgProjectCatalog.isCatalogued(orgSlug: organization.id, section: section)
    }

    /// The approved post whose title matches the given catalog title (normalized), if it's
    /// been posted. Matching reuses the Weekly Shorts normalization.
    private func matchedSubmission(forTitle title: String) -> Submission? {
        let key = CollectiveStudios.normalize(title)
        return submissionStore.visibleApprovedSubmissions.first {
            CollectiveStudios.normalize($0.title) == key
        }
    }
}

// MARK: - Org content row + detail

/// A themed row for a tagged post inside an org section/season.
struct OrgContentRow: View {
    let submission: Submission
    let theme: OrgTheme

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = submission.thumbnailData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "film")
                        .foregroundStyle(theme.text.opacity(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 96, height: 58)
            .background(theme.text.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(submission.title)
                    .font(.headline)
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                Text(submission.type.rawValue.capitalized)
                    .font(.subheadline)
                    .foregroundStyle(theme.text.opacity(0.75))
            }
            Spacer(minLength: 8)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.text.opacity(0.12))
        )
    }
}

/// A themed row for a hardcoded org project (see `OrgProjectCatalog`). Shows the matched
/// post's thumbnail once the project has been posted, and a muted "Not posted yet" note
/// until then — mirroring the Weekly Short episode row.
struct OrgProjectRow: View {
    let project: OrgProject
    let submission: Submission?
    let theme: OrgTheme

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = submission?.thumbnailData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "film")
                        .foregroundStyle(theme.text.opacity(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 96, height: 58)
            .background(theme.text.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(project.title)
                    .font(.headline)
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                Text(submission.map { $0.type.rawValue.capitalized } ?? "Not posted yet")
                    .font(.subheadline)
                    .foregroundStyle(theme.text.opacity(0.75))
            }
            Spacer(minLength: 8)
            if submission != nil {
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(theme.text.opacity(0.7))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.text.opacity(submission == nil ? 0.06 : 0.12))
        )
        .opacity(submission == nil ? 0.6 : 1)
    }
}

// MARK: - Weekly Short Seasons

/// A row for one season (folder) in the seasons list.
struct OrgSeasonRow: View {
    let season: String
    let count: Int
    let theme: OrgTheme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(theme.text)
                .frame(width: 30)
            Text(season)
                .font(.headline)
                .foregroundStyle(theme.text)
            Spacer()
            Text("\(count)")
                .font(.subheadline)
                .foregroundStyle(theme.text.opacity(0.7))
            Image(systemName: "chevron.right")
                .font(.subheadline)
                .foregroundStyle(theme.text.opacity(0.7))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.text.opacity(0.12))
        )
    }
}

/// The shorts within one season. Read-only for regular users; moderators can add/remove.
struct OrgSeasonShortsView: View {
    let organization: Organization
    let season: String

    @ObservedObject private var content: OrgContentStore = .shared
    @State private var selected: Submission?
    @State private var showAdd = false

    private var canModerate: Bool {
        UserDefaults.standard.bool(forKey: "isModeratorMode") && ModeratorAccess.isModerator
    }

    var body: some View {
        let theme = organization.theme
        let shorts = content.shorts(orgSlug: organization.id, season: season)

        VStack(spacing: 0) {
            OrgPushedHeader(title: season, theme: theme) {
                if canModerate {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(theme.text)
                            .frame(width: 32, height: 32)
                    }
                }
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    if shorts.isEmpty {
                        Text("Nothing here yet.")
                            .font(.subheadline)
                            .foregroundStyle(theme.text.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(shorts) { link in
                            if let submission = content.submission(for: link) {
                                Button { selected = submission } label: {
                                    OrgContentRow(submission: submission, theme: theme)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if canModerate {
                                        Button(role: .destructive) {
                                            Task { await content.remove(link) }
                                        } label: { Label("Remove", systemImage: "minus.circle") }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .orgThemed(theme)
        .toolbar(.hidden, for: .navigationBar)
        .task { await content.load() }
        .sheet(item: $selected) { submission in
            PostDetailRouter(post: submission, liked: .constant(false))
        }
        .sheet(isPresented: $showAdd) {
            // Adds directly into this season (Miscellaneous ⇒ blank/"unassigned").
            OrgAddContentView(
                orgSlug: organization.id,
                section: .weeklyShortSeasons,
                isSeasonSection: true,
                presetSeason: season == orgMiscellaneousSeason ? "" : season
            )
        }
    }
}

// MARK: - Collective Weekly Shorts (hardcoded catalog)

/// The episodes in one Collective season, from the hardcoded `CollectiveStudios` catalog.
/// Each episode is matched to a real posted submission by title; matched episodes are
/// tappable and open the post, unmatched ones are shown but disabled ("not posted yet").
struct CollectiveSeasonView: View {
    let organization: Organization
    let season: Int

    @ObservedObject private var store: SubmissionStore_3_2 = .shared
    @State private var selected: Submission?

    var body: some View {
        let theme = organization.theme
        VStack(spacing: 0) {
            OrgPushedHeader(title: "Season \(season)", theme: theme) { EmptyView() }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(CollectiveStudios.episodes(inSeason: season)) { episode in
                        let submission = matchedSubmission(for: episode)
                        Button {
                            selected = submission
                        } label: {
                            CollectiveEpisodeRow(episode: episode, submission: submission, theme: theme)
                        }
                        .buttonStyle(.plain)
                        .disabled(submission == nil)
                    }
                }
                .padding()
            }
        }
        .orgThemed(theme)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selected) { submission in
            PostDetailRouter(post: submission, liked: .constant(false))
        }
    }

    /// The approved post whose title matches this episode (normalized), if it's been posted.
    private func matchedSubmission(for episode: CollectiveEpisode) -> Submission? {
        let key = CollectiveStudios.normalize(episode.title)
        return store.visibleApprovedSubmissions.first {
            CollectiveStudios.normalize($0.title) == key
        }
    }
}

/// A row for one Weekly Short: its "SxEy" code and title, the matched post's thumbnail
/// when available, and a muted "Not posted yet" note when no matching post exists.
struct CollectiveEpisodeRow: View {
    let episode: CollectiveEpisode
    let submission: Submission?
    let theme: OrgTheme

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = submission?.thumbnailData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "film")
                        .foregroundStyle(theme.text.opacity(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 96, height: 58)
            .background(theme.text.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("\(episode.code)  \(episode.title)")
                    .font(.headline)
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                Text(submission == nil ? "Not posted yet" : "Weekly Short")
                    .font(.subheadline)
                    .foregroundStyle(theme.text.opacity(0.75))
            }
            Spacer(minLength: 8)
            if submission != nil {
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(theme.text.opacity(0.7))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.text.opacity(submission == nil ? 0.06 : 0.12))
        )
        .opacity(submission == nil ? 0.6 : 1)
    }
}

// MARK: - Add existing post to a section (moderators only)

/// A searchable list of existing approved posts. Tapping one tags it into the org's
/// section (and, for seasons, an optional typed season name — blank = Miscellaneous).
struct OrgAddContentView: View {
    let orgSlug: String
    let section: OrgSection
    /// When true this is the Weekly Short Seasons section and a season field is offered.
    let isSeasonSection: Bool
    /// A fixed season to add into (skips the season field). nil = let the user type one.
    let presetSeason: String?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store: SubmissionStore_3_2 = .shared
    @ObservedObject private var content: OrgContentStore = .shared
    @State private var searchText = ""
    @State private var seasonName = ""

    private var candidates: [Submission] {
        let all = store.visibleApprovedSubmissions.sorted { $0.createdDate > $1.createdDate }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
            $0.submittedBy.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isSeasonSection && presetSeason == nil {
                    TextField("Season (leave blank for Miscellaneous)", text: $seasonName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                        .padding(.top, 12)
                }

                List {
                    ForEach(candidates) { submission in
                        Button {
                            Task {
                                await content.add(
                                    orgSlug: orgSlug,
                                    section: section,
                                    submissionID: submission.id,
                                    season: presetSeason ?? seasonName.trimmingCharacters(in: .whitespaces)
                                )
                                dismiss()
                            }
                        } label: {
                            SubmissionListRow(submission: submission) { EmptyView() }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "Search posts")
            .navigationTitle("Add to \(section.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.hidden)
    }
}
