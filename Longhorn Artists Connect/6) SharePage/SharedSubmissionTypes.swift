//
//  SharedSubmissionTypes.swift
//  Longhorn Artists Connect
//
//  Shared types used across multiple submission views
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Manual Featured Work

/// A "Featured Work" entry typed in by hand — a project title plus its director —
/// rather than linked to an existing post on the app. Persisted as a compact JSON
/// string so these entries can live in a single CloudKit string-array field alongside
/// the linked-post IDs, without needing parallel arrays.
// A pure value type used from both UI (main actor) and the CloudKit layer, so the whole
// type is `nonisolated` (including its synthesized Codable conformance) to stay usable
// everywhere under the project's main-actor-by-default isolation.
nonisolated struct ManualFeaturedWork: Codable, Hashable, Identifiable {
    var title: String
    var director: String

    /// Stable identity for `ForEach`, derived from the content (entries with identical
    /// title + director are treated as the same row).
    var id: String { "\(title)\u{001F}\(director)" }

    init(title: String, director: String) {
        self.title = title
        self.director = director
    }

    /// The JSON string stored on the submission/CloudKit record.
    var encoded: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else { return "" }
        return string
    }

    /// Rebuilds an entry from its stored JSON string, or nil if it can't be decoded.
    init?(encoded: String) {
        guard let data = encoded.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ManualFeaturedWork.self, from: data) else {
            return nil
        }
        self = decoded
    }
}

// MARK: - Edited Media Persistence

/// Copies a newly-picked media file (video/audio/script) into the app's Documents
/// directory under `fileName`, replacing any existing file with that name. Handles
/// security-scoped URLs from the Files app (otherwise the copy silently fails and the
/// post uploads with no asset). Returns the stored file name to save on the submission,
/// or `nil` if the copy failed. Used by the edit views so replacing an asset works the
/// same way the creation form stores it.
@MainActor
func persistEditedMediaFile(from sourceURL: URL, as fileName: String) -> String? {
    // Heavy media lives in the bounded, backup-excluded media cache (not Documents).
    guard let mediaDir = FileManager.default.mediaCacheDirectory else { return nil }
    let destination = mediaDir.appendingPathComponent(fileName)
    let didAccess = sourceURL.startAccessingSecurityScopedResource()
    defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }
    do {
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return fileName
    } catch {
        print("❌ Failed to persist edited media file: \(error.localizedDescription)")
        return nil
    }
}

/// Writes film "extra" images (BTS photos / stills) to the media cache as JPEGs under the
/// deterministic names the CloudKit upload + on-demand download expect
/// (`<id>_<kind>_<n>.jpg`, e.g. `<id>_bts_0.jpg`). Stale files from a previous, longer set
/// are removed so an edit that deletes images doesn't leave orphans behind. Returns the
/// stored file names to save on the submission.
@MainActor
func persistFilmExtraImages(_ images: [UIImage], submissionID: UUID, kind: String) -> [String] {
    guard let mediaDir = FileManager.default.mediaCacheDirectory else { return [] }
    let prefix = "\(submissionID.uuidString)_\(kind)_"

    // Clear any previously-written files for this kind (indices may have shifted).
    if let existing = try? FileManager.default.contentsOfDirectory(atPath: mediaDir.path) {
        for name in existing where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: mediaDir.appendingPathComponent(name))
        }
    }

    var names: [String] = []
    for (index, image) in images.enumerated() {
        guard let data = image.jpegData(compressionQuality: 0.85) else { continue }
        let fileName = "\(prefix)\(index).jpg"
        do {
            try data.write(to: mediaDir.appendingPathComponent(fileName))
            names.append(fileName)
        } catch {
            print("❌ Failed to persist film extra image \(fileName): \(error.localizedDescription)")
        }
    }
    return names
}

/// Copies an EP/Album's extra audio tracks (everything after track 1, which is stored as
/// the submission's `audioFileName`) into the media cache under the deterministic names
/// the CloudKit upload and on-demand download expect — `<id>_track<n>.<ext>`, numbered
/// from 1. Stale files from a previous, longer tracklist are removed first so an edit that
/// deletes a track doesn't leave orphans behind.
///
/// A track that's already stored under its final name is left in place: on an edit the
/// picked URL is usually the cached copy itself, and copying a file onto itself fails.
/// Returns the stored file names, in running order.
@MainActor
func persistMusicTracks(_ urls: [URL], submissionID: UUID) -> [String] {
    guard let mediaDir = FileManager.default.mediaCacheDirectory else { return [] }
    let prefix = "\(submissionID.uuidString)_track"

    let finalNames = urls.enumerated().map { index, url -> String in
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        return "\(prefix)\(index + 1).\(ext)"
    }

    // Clear previously-written tracks that this save won't rewrite (indices may have
    // shifted, and the list may have got shorter).
    if let existing = try? FileManager.default.contentsOfDirectory(atPath: mediaDir.path) {
        for name in existing where name.hasPrefix(prefix) && !finalNames.contains(name) {
            try? FileManager.default.removeItem(at: mediaDir.appendingPathComponent(name))
        }
    }

    var names: [String] = []
    for (url, fileName) in zip(urls, finalNames) {
        let destination = mediaDir.appendingPathComponent(fileName)
        if url.standardizedFileURL == destination.standardizedFileURL {
            names.append(fileName)
            continue
        }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            names.append(fileName)
        } catch {
            print("❌ Failed to persist music track \(fileName): \(error.localizedDescription)")
        }
    }
    return names
}

/// Installs a window-level tap recognizer that dismisses the keyboard on any tap,
/// without stealing taps from buttons or text fields (`cancelsTouchesInView = false`,
/// recognizes simultaneously). Because it ends editing on every tap, tapping a
/// navigation button also resigns the active field — so the keyboard doesn't linger
/// or reappear when returning from a pushed sub-page.
private struct DismissKeyboardOnTap: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let tap = UITapGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = context.coordinator
            window.addGestureRecognizer(tap)
            context.coordinator.tap = tap
            context.coordinator.window = window
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        if let tap = coordinator.tap {
            coordinator.window?.removeGestureRecognizer(tap)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var tap: UITapGestureRecognizer?
        weak var window: UIWindow?

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            // When the tap lands on (or inside) another text field, don't resign:
            // let the responder move straight to the new field so the keyboard stays
            // up. Resigning here would dismiss the keyboard and immediately re-present
            // it as the new field focuses, causing a visible flicker when switching
            // between fields.
            if let window,
               let hit = window.hitTest(recognizer.location(in: window), with: nil),
               hit.isInsideTextInput {
                return
            }
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

private extension UIView {
    /// True when this view is a text-entry control or lives inside one. Used to keep
    /// a tap on another field from dismissing the keyboard mid-switch.
    var isInsideTextInput: Bool {
        var view: UIView? = self
        while let current = view {
            if current is UITextField || current is UITextView { return true }
            view = current.superview
        }
        return false
    }
}

extension View {
    /// Dismisses the keyboard when the user taps anywhere (outside a text field),
    /// and when tapping controls that push a new page. Unlike an `.onTapGesture`
    /// approach, this doesn't swallow taps on buttons/fields. See `DismissKeyboardOnTap`.
    func endEditingOnTap() -> some View {
        background(DismissKeyboardOnTap())
    }
}

// MARK: - Credit Name Field

/// A text field for crediting a person that suggests matching registered users as
/// you type. Tapping a suggestion fills their exact profile name so the credit
/// links to the real person (no misspellings / faulty credits).
struct CreditNameField: View {
    let placeholder: String
    @Binding var text: String
    /// Optional binding that stores the picked person's profile record ID, so the
    /// credit links to the exact person. Defaults to a no-op for fields that don't
    /// track an ID (e.g. crew name fields).
    var profileID: Binding<String?> = .constant(nil)

    @ObservedObject private var userManager = UserProfileManager.shared
    @FocusState private var isFocused: Bool

    /// Up to 4 directory users whose name contains the typed text — unless the
    /// credit is already linked to a profile (then it's considered confirmed).
    private var suggestions: [DirectoryUser] {
        if profileID.wrappedValue != nil { return [] }
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard query.count >= 2 else { return [] }
        if userManager.allUsers.contains(where: { $0.fullName.lowercased() == query }) { return [] }
        return Array(
            userManager.allUsers
                .filter { $0.fullName.lowercased().contains(query) }
                .sorted { $0.fullName.lowercased() < $1.fullName.lowercased() }
                .prefix(4)
        )
    }

    /// Whether this credit is linked to a real profile (picked, or exact name match).
    private var isConfirmed: Bool {
        if profileID.wrappedValue != nil { return true }
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        return !query.isEmpty && userManager.allUsers.contains { $0.fullName.lowercased() == query }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(placeholder, text: $text, axis: .vertical)
                    .focused($isFocused)
                if isConfirmed {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.brandOrange)
                        .font(.caption)
                }
            }
            // If the user edits the text away from the linked profile's name, drop
            // the stale link so the ✓ and stored ID stay accurate.
            .onChange(of: text) { _, newValue in
                if let id = profileID.wrappedValue,
                   let linked = userManager.allUsers.first(where: { $0.id == id }),
                   linked.fullName.lowercased() != newValue.trimmingCharacters(in: .whitespaces).lowercased() {
                    profileID.wrappedValue = nil
                }
            }

            if isFocused && !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { user in
                        Button {
                            text = user.fullName
                            profileID.wrappedValue = user.id
                            isFocused = false
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .foregroundStyle(Color.brandOrange)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(user.fullName)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    if !user.rolesString.isEmpty {
                                        Text(user.rolesString)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if user.id != suggestions.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemBackground))
                )
            }
        }
    }
}

// MARK: - Upload Row Thumbnail

/// A compact media preview for submission "upload" rows. Shows `image` scaled to fit
/// (so its original aspect ratio is preserved) inside a fixed box, so it can never
/// overflow the row or push the surrounding controls out of place. Falls back to a
/// system icon when there's no image yet.
struct UploadRowThumbnail: View {
    let image: UIImage?
    let placeholderSystemName: String
    /// Largest the preview may get in either dimension.
    var maxSize: CGFloat = 44

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: maxSize, maxHeight: maxSize)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: placeholderSystemName)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Submission List Row (portfolio style)

/// A portfolio-style list row for a submission: a thumbnail alongside the title and
/// media type, on an adaptive rounded card with a subtle border — the same look as the
/// portfolio feed. Reused by the Featured Work picker and a reel's Featured Work list.
/// `trailing` adds an optional accessory (e.g. a selection checkmark).
struct SubmissionListRow<Trailing: View>: View {
    let submission: Submission
    @ViewBuilder var trailing: () -> Trailing

    /// Width of the leading thumbnail; height follows the media's aspect ratio.
    private let thumbnailWidth: CGFloat = 110

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(submission.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(submission.type.rawValue.capitalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(UIColor.separator), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = submission.thumbnailData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: thumbnailWidth)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: thumbnailWidth, height: thumbnailWidth * 0.6)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    Image(systemName: SubmissionListRow.iconName(for: submission.type))
                        .foregroundStyle(.secondary)
                )
        }
    }

    static func iconName(for type: MediaType) -> String {
        switch type {
        case .film:    return "film"
        case .music:   return "music.note"
        case .reel:    return "video"
        case .project: return "hammer"
        case .event:   return "calendar"
        case .photography: return "camera"
        case .design:  return "paintpalette.fill"
        }
    }
}

/// A read-only Featured Work row for a hand-typed entry (project + director) that isn't
/// a post on the app. Styled to match `SubmissionListRow` so linked and manual entries
/// sit together in the same list.
struct ManualFeaturedWorkRow: View {
    let entry: ManualFeaturedWork

    private let thumbnailWidth: CGFloat = 110

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: thumbnailWidth, height: thumbnailWidth * 0.6)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    Image(systemName: "hammer")
                        .foregroundStyle(.secondary)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(entry.director.isEmpty ? "Project" : "Directed by \(entry.director)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(UIColor.separator), lineWidth: 1)
        )
    }
}

// MARK: - Genre / Release Year Row

/// The line under a post's title that carries its genres on the left and its release
/// year pinned to the right edge. Shared by the film, music, reel, and photography
/// detail views so the year always reads in the same place.
///
/// `content` is the whole left-hand side — a `GenreText` plus whatever else that type
/// shows on the line (a film's age-rating badge, a track's "Explicit" tag), in the order
/// that type wants them. The row claims the full width of the column it sits in, so the
/// year lands against the column's trailing edge (just inside the action buttons).
///
/// A post credited to a studio shows its year in the `StudioYearCredit` under the action
/// buttons instead, so it isn't repeated here.
struct GenreReleaseYearRow<Content: View>: View {
    /// The release year, shown flush right. Empty hides it.
    let releaseYear: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            content()

            Spacer(minLength: 8)

            if !releaseYear.isEmpty {
                Text(releaseYear)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    // Never let the year shrink or wrap to make room for the genres.
                    .fixedSize()
            }
        }
        // Fill the info column's width so the trailing year sits on its right edge.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension GenreReleaseYearRow where Content == GenreText {
    /// A row holding nothing but the genres and the year.
    init(genres: String, releaseYear: String) {
        self.init(releaseYear: releaseYear) { GenreText(genres: genres) }
    }
}

// MARK: - Studio / Year Credit

/// The studio and release year credited directly under a post's action buttons, flush
/// with the card's right edge — e.g. "Incubator • 2025". The studio has no section of
/// its own on the detail page; this is the only place it appears.
///
/// Sized to match the cast/crew credits below, and tappable (in the brand color, like a
/// credited name) when the studio has a page to open.
struct StudioYearCredit: View {
    /// The crediting studio. Empty — or the default "Independent", which reads as "no
    /// studio" — shows the year alone.
    let studio: String
    /// The release year. Empty shows the studio alone.
    let releaseYear: String
    /// Opens the studio's page. `nil` leaves the studio as plain text, for studios that
    /// don't have a page.
    var onStudioTap: (() -> Void)? = nil

    /// Whether this studio/year pair has anything to credit. Callers that reserve space
    /// around the credit — e.g. padding its row out to line up with a genre row — check
    /// this first so they don't leave a gap where the credit renders nothing.
    static func hasCredit(studio: String, releaseYear: String) -> Bool {
        creditedStudio(in: studio) != nil
            || !releaseYear.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The studio name worth crediting, or `nil` when there's nothing distinct to show.
    private static func creditedStudio(in studio: String) -> String? {
        let name = studio.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != "Independent" else { return nil }
        return name
    }

    private var creditedStudio: String? {
        Self.creditedStudio(in: studio)
    }

    private var year: String {
        releaseYear.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        if creditedStudio != nil || !year.isEmpty {
            HStack(spacing: 4) {
                if let creditedStudio {
                    if let onStudioTap {
                        Button(action: onStudioTap) {
                            studioText(creditedStudio)
                                .foregroundStyle(Color.brandOrange)
                        }
                        .buttonStyle(.plain)
                    } else {
                        studioText(creditedStudio)
                            .foregroundStyle(.secondary)
                    }

                    if !year.isEmpty {
                        Text("•")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }

                if !year.isEmpty {
                    Text(year)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
        }
    }

    /// The studio name itself. A long name (e.g. "Beyond Frame Productions") shrinks
    /// rather than wrapping or crowding the title beside it.
    private func studioText(_ name: String) -> some View {
        Text(name)
            .font(.body)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// The genre/category text as it appears on a post's `GenreReleaseYearRow`, e.g.
/// "Drama • Thriller". Renders nothing when there are no genres.
struct GenreText: View {
    let genres: String

    var body: some View {
        if !genres.isEmpty {
            Text(genres)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                // Keep genres on a single line; shrink to fit rather than wrap.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Release Year Picker

/// A menu row that lets the user pick a release year (next year down through the last
/// 60, newest first). Matches the inline pickers used by the film/music forms; shared
/// so every submission view can offer the same "Release Year" field.
struct ReleaseYearPicker: View {
    @Binding var releaseYear: String

    private var releaseYears: [String] {
        // Next year down through nine years back (e.g. 2027…2017), newest first.
        let current = Calendar.current.component(.year, from: Date())
        return (0...10).map { String(current + 1 - $0) }
    }

    var body: some View {
        Menu {
            ForEach(releaseYears, id: \.self) { year in
                Button {
                    releaseYear = year
                } label: {
                    HStack {
                        Text(year)
                        if releaseYear == year { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack {
                Text("Release Year")
                    .foregroundStyle(.primary)
                Spacer()
                Text(releaseYear.isEmpty ? "Select" : releaseYear)
                    .lineLimit(1)
                    .foregroundStyle(Color.brandOrange)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Age Rating

enum AgeRating: String, CaseIterable, Identifiable, Codable {
    case general = "G"
    case pg = "PG"
    case pg13 = "PG-13"
    case r = "R"
    
    var id: String { rawValue }
}

// MARK: - Film Category

/// How a film was produced. Drives which "studio" field the form shows: an org's studio
/// list, a production class, or nothing (independent). The chosen studio/class is stored
/// in `Submission.studio`, so the category is derived back from that value when re-opening
/// a draft or editing an existing film.
enum FilmCategory: String, CaseIterable, Identifiable {
    case org = "Org Project"
    case classProject = "Class Project"
    case independent = "Independent Project"

    var id: String { rawValue }
}

// MARK: - Production Classes

/// One of the production classes a film can be submitted under. `fullName` (course code
/// plus class name) is what gets stored in `Submission.studio` and shown on the form and
/// the post detail; `code` is shown on its own in the home feed credit, where the full
/// name is too long.
struct ProductionClass: Identifiable, Hashable {
    /// The course number, e.g. "RTF 304D".
    let code: String
    /// The class name without its course number, e.g. "Intro to Production".
    let name: String
    /// Earlier names this class has been stored under, so films posted before a rename
    /// still resolve to it.
    let legacyNames: [String]

    /// e.g. "RTF 304D Intro to Production" — the canonical stored value.
    var fullName: String { "\(code) \(name)" }
    var id: String { fullName }
}

/// The hardcoded catalog of production classes, plus the matching used to recognize a
/// stored `Submission.studio` value as a class rather than an org's studio.
enum ProductionClassCatalog {

    /// Every selectable class, in the order the submission form lists them.
    static let all: [ProductionClass] = [
        ProductionClass(code: "RTF 304D", name: "Intro to Production",
                        legacyNames: ["Intro to Production", "304D Intro to Production", "304D"]),
        ProductionClass(code: "RTF 366K", name: "Narrative Production",
                        legacyNames: ["Narrative Production"]),
        ProductionClass(code: "RTF 343",  name: "Advanced Narrative Production",
                        legacyNames: ["Advanced Narrative Production"]),
        ProductionClass(code: "RTF 367D", name: "Directing Workshop",
                        legacyNames: ["Director's Workshop", "Directors Workshop"])
    ]

    /// The class names offered in the form's "Class" menu.
    static var names: [String] { all.map(\.fullName) }

    /// The class a stored `studio` value refers to, if any. Matches the canonical
    /// "code + name", the bare code, the bare name, and any legacy name — so both
    /// newly-posted and pre-rename films resolve.
    static func match(_ studio: String) -> ProductionClass? {
        let key = normalize(studio)
        guard !key.isEmpty else { return nil }
        return all.first { candidate in
            var keys = [candidate.fullName, candidate.code, candidate.name]
            keys.append(contentsOf: candidate.legacyNames)
            return keys.contains { normalize($0) == key }
        }
    }

    /// The course code to credit a stored `studio` value with, or `nil` when the value
    /// isn't a production class at all.
    static func code(for studio: String) -> String? { match(studio)?.code }

    /// Lowercases, straightens curly apostrophes and collapses whitespace so matching
    /// tolerates the capitalization and punctuation drift in already-stored values.
    private static func normalize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

// MARK: - Cast & Crew Types

struct CastEntry: Codable, Equatable, Identifiable {
    let id: UUID
    var performer: String
    var role: String
    /// CloudKit record name of the performer's profile, when picked from the
    /// directory. `nil` for free-typed names.
    var profileID: String?

    init(id: UUID = UUID(), performer: String = "", role: String = "", profileID: String? = nil) {
        self.id = id
        self.performer = performer
        self.role = role
        self.profileID = profileID
    }
}

/// Photography equipment used for a shoot. Each field is a freeform, optional
/// description. Stored on `Submission`/`Photography` and round-tripped through CloudKit
/// as a single JSON string (`photographyEquipment`).
struct EquipmentInfo: Codable, Equatable {
    /// Camera body (e.g., "Canon EOS R5").
    var camera: String = ""
    /// Lens(es) used (e.g., "RF 24-70mm f/2.8").
    var lens: String = ""
    /// Lighting setup (e.g., "Godox AD200, natural light").
    var lighting: String = ""
    /// Filters used (e.g., "Polarizer, ND1000").
    var filters: String = ""
    /// Support gear (e.g., "Tripod, gimbal, monopod").
    var support: String = ""
    /// Anything else worth crediting (drones, editing software, etc.).
    var accessories: String = ""

    /// True when nothing has been filled in.
    var isEmpty: Bool {
        [camera, lens, lighting, filters, support, accessories]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Labeled, non-empty entries in display order — used for read-only summaries.
    var labeledEntries: [(label: String, value: String)] {
        let pairs: [(String, String)] = [
            ("Camera", camera),
            ("Lens", lens),
            ("Lighting", lighting),
            ("Filters", filters),
            ("Support", support),
            ("Other", accessories)
        ]
        return pairs
            .filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { (label: $0.0, value: $0.1) }
    }

    /// JSON string for CloudKit round-tripping. Empty string when nothing is set.
    var jsonString: String {
        guard !isEmpty,
              let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else { return "" }
        return string
    }

    init(camera: String = "", lens: String = "", lighting: String = "",
         filters: String = "", support: String = "", accessories: String = "") {
        self.camera = camera
        self.lens = lens
        self.lighting = lighting
        self.filters = filters
        self.support = support
        self.accessories = accessories
    }

    /// Rebuilds from the JSON produced by `jsonString`; empty/invalid input yields a
    /// blank `EquipmentInfo`.
    init(jsonString: String) {
        if let data = jsonString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(EquipmentInfo.self, from: data) {
            self = decoded
        } else {
            self = EquipmentInfo()
        }
    }
}

struct CastInfo: Codable, Equatable {
    var primaries: [CastEntry] = []
    var secondaries: [CastEntry] = []
    var extras: [CastEntry] = []
    
    // Legacy fields for backward compatibility
    var legacyPrimarys: String = ""
    var legacySecondarys: String = ""
    var legacyExtras: String = ""
    
    // New detailed cast entries (for backward compatibility)
    var detailedCast: [CastEntry] = []
    
    var summary: String {
        var lines: [String] = []
        
        // New categorized cast
        if !primaries.isEmpty {
            lines.append(contentsOf: primaries
                .filter { !$0.performer.isEmpty && !$0.role.isEmpty }
                .map { "Primary - \($0.role): \($0.performer)" })
        }
        
        if !secondaries.isEmpty {
            lines.append(contentsOf: secondaries
                .filter { !$0.performer.isEmpty && !$0.role.isEmpty }
                .map { "Secondary - \($0.role): \($0.performer)" })
        }
        
        if !extras.isEmpty {
            lines.append(contentsOf: extras
                .filter { !$0.performer.isEmpty && !$0.role.isEmpty }
                .map { "Extra - \($0.role): \($0.performer)" })
        }
        
        // Legacy fields for backward compatibility
        let pairs: [(String, String)] = [
            ("Primaries", legacyPrimarys),
            ("Secondaries", legacySecondarys),
            ("Extras", legacyExtras)
        ]
        lines.append(contentsOf: pairs
            .filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "\($0.0): \($0.1)" })
        
        // Detailed cast for backward compatibility
        if !detailedCast.isEmpty {
            lines.append(contentsOf: detailedCast
                .filter { !$0.performer.isEmpty && !$0.role.isEmpty }
                .map { "\($0.role): \($0.performer)" })
        }
        
        return lines.joined(separator: "\n")
    }
}

/// One credited crew person: a name plus, when picked from the directory, the linked
/// profile ID so the credit points at the exact person.
struct CrewMember: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var profileID: String?

    init(id: UUID = UUID(), name: String = "", profileID: String? = nil) {
        self.id = id
        self.name = name
        self.profileID = profileID
    }
}

/// A crew role (e.g. "Producer") and everyone credited under it. Holding an array of
/// members lets a single role credit multiple people (two producers, etc.), and the
/// editable `role` lets users add custom crew types beyond the standard list.
struct CrewRoleGroup: Codable, Equatable, Identifiable {
    let id: UUID
    var role: String
    var members: [CrewMember]

    init(id: UUID = UUID(), role: String = "", members: [CrewMember] = [CrewMember()]) {
        self.id = id
        self.role = role
        self.members = members
    }
}

struct CrewInfo: Codable, Equatable {
    var groups: [CrewRoleGroup]

    /// The standard film-crew roles, pre-listed so the common credits are one tap away.
    static let defaultRoles: [String] = [
        "Director", "Producer", "Writer", "Editor",
        "Director of Photography", "1st Assistant Camera", "2nd Assistant Camera",
        "Gaffer", "Key Grip", "Grip", "BBE",
        "Composer", "On-Set Mixer", "Boom Operator", "SFX Designer", "Sound Mixer",
        "Production Designer", "Wardrobe", "Hair and Makeup", "Set Dresser",
        "Stunt Coordinator", "Colorist", "Production Assistant"
    ]

    /// A fresh crew sheet, seeded with the standard roles (each with one empty name
    /// field). Users can add more people to any role, or add custom roles.
    init() {
        groups = Self.defaultRoles.map { CrewRoleGroup(role: $0) }
    }

    var summary: String {
        toOrderedEntries().map { "\($0.role): \($0.name)" }.joined(separator: "\n")
    }
}

// MARK: - Cast/Crew ↔ OrderedEntry Conversion

extension CastInfo {
    /// Flattens cast (primaries, then secondaries, then extras) into ordered
    /// entries, dropping rows missing a name or role. Mirrors how the submission
    /// form builds a post's cast, so editing produces identical data.
    func toOrderedEntries() -> [OrderedEntry] {
        (primaries + secondaries + extras).compactMap { entry in
            guard !entry.performer.isEmpty && !entry.role.isEmpty else { return nil }
            return OrderedEntry(role: entry.role, name: entry.performer, profileID: entry.profileID)
        }
    }

    /// Rebuilds cast from stored ordered entries. The original primary/secondary/
    /// extra grouping isn't persisted, so everything is restored under "Primary".
    init(orderedEntries entries: [OrderedEntry]) {
        self.init()
        primaries = entries.map { CastEntry(performer: $0.name, role: $0.role, profileID: $0.profileID) }
    }
}

extension CrewInfo {
    /// Flattens filled crew into ordered entries — one per credited person, in the
    /// order shown. Rows missing a role or a name are dropped.
    func toOrderedEntries() -> [OrderedEntry] {
        var entries: [OrderedEntry] = []
        for group in groups {
            let role = group.role.trimmingCharacters(in: .whitespaces)
            guard !role.isEmpty else { continue }
            for member in group.members {
                let name = member.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                entries.append(OrderedEntry(role: role, name: name, profileID: member.profileID))
            }
        }
        return entries
    }

    /// Rebuilds crew from stored ordered entries, one editable row per credit (role +
    /// name), matching the flat Credits-style form layout.
    init(orderedEntries entries: [OrderedEntry]) {
        groups = entries.map {
            CrewRoleGroup(role: $0.role, members: [CrewMember(name: $0.name, profileID: $0.profileID)])
        }
    }
}

// MARK: - Reel Types

struct ReelExperience: Codable, Equatable, Identifiable {
    let id: UUID
    var project: String
    var month: Int
    var year: Int
    
    init(id: UUID = UUID(), project: String = "", month: Int = 1, year: Int = Calendar.current.component(.year, from: Date())) {
        self.id = id
        self.project = project
        self.month = month
        self.year = year
    }
    
    var dateString: String {
        let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(monthNames[month - 1]) \(year)"
    }
}

struct ReelSkill: Codable, Equatable, Identifiable {
    let id: UUID
    var skill: String
    var month: Int
    var year: Int
    
    init(id: UUID = UUID(), skill: String = "", month: Int = 1, year: Int = Calendar.current.component(.year, from: Date())) {
        self.id = id
        self.skill = skill
        self.month = month
        self.year = year
    }
    
    var dateString: String {
        let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(monthNames[month - 1]) \(year)"
    }
}

// MARK: - Form Views

struct CastFormView: View {
    @Binding var cast: CastInfo

    var body: some View {
        List {
            Section("Primary Cast") {
                ForEach($cast.primaries) { $entry in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Role", text: $entry.role, axis: .vertical)
                        CreditNameField(placeholder: "Performer", text: $entry.performer, profileID: $entry.profileID)
                    }
                }
                .onDelete { indexSet in
                    cast.primaries.remove(atOffsets: indexSet)
                }
                
                Button("Add Primary") {
                    cast.primaries.append(CastEntry())
                }
            }
            
            Section("Secondary Cast") {
                ForEach($cast.secondaries) { $entry in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Role", text: $entry.role, axis: .vertical)
                        CreditNameField(placeholder: "Performer", text: $entry.performer, profileID: $entry.profileID)
                    }
                }
                .onDelete { indexSet in
                    cast.secondaries.remove(atOffsets: indexSet)
                }
                
                Button("Add Secondary") {
                    cast.secondaries.append(CastEntry())
                }
            }
            
            Section("Extras") {
                ForEach($cast.extras) { $entry in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Role", text: $entry.role, axis: .vertical)
                        CreditNameField(placeholder: "Performer", text: $entry.performer, profileID: $entry.profileID)
                    }
                }
                .onDelete { indexSet in
                    cast.extras.remove(atOffsets: indexSet)
                }
                
                Button("Add Extra") {
                    cast.extras.append(CastEntry())
                }
            }
        }
        .navigationTitle("Cast")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CrewFormView: View {
    @Binding var crew: CrewInfo
    /// Labels default to the film "Crew" wording; other media (e.g. photography)
    /// can reuse this form with their own "Credits" wording.
    var navigationTitle: String = "Crew"
    var sectionTitle: String = "Crew"
    var addButtonTitle: String = "Add Crew Credit"

    var body: some View {
        List {
            Section(sectionTitle) {
                ForEach($crew.groups) { $group in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Role (e.g., Director, Editor)", text: $group.role, axis: .vertical)
                        CreditNameField(
                            placeholder: "Name",
                            text: Binding(
                                get: { group.members.first?.name ?? "" },
                                set: { newValue in
                                    if group.members.isEmpty {
                                        $group.wrappedValue.members = [CrewMember(name: newValue)]
                                    } else {
                                        $group.wrappedValue.members[0].name = newValue
                                    }
                                }
                            ),
                            profileID: Binding(
                                get: { group.members.first?.profileID },
                                set: { newID in
                                    if !group.members.isEmpty {
                                        $group.wrappedValue.members[0].profileID = newID
                                    }
                                }
                            )
                        )
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    crew.groups.remove(atOffsets: indexSet)
                }

                Button {
                    crew.groups.append(CrewRoleGroup(role: ""))
                } label: {
                    Label(addButtonTitle, systemImage: "plus.circle.fill")
                        .foregroundStyle(Color.brandOrange)
                }
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Music Credits Form Views

struct MusicCreditsFormView: View {
    @Binding var recordingCredits: [OrderedEntry]
    @Binding var productionCredits: [OrderedEntry]

    // Default role fields shown ready to fill out when no credits exist yet.
    private let defaultRecordingRoles = ["Vocalist", "Lead Guitar", "Rhythm Guitar", "Bass Guitar", "Drums"]
    private let defaultProductionRoles = ["Producer", "Mixer", "Engineer"]

    var body: some View {
        // No inner NavigationStack: this form is pushed via `navigationDestination`
        // onto the submission form's stack. Nesting a second stack here caused the
        // whole editor to pop when tagging a credited user mutated the bound entry.
        List {
            Section("Recording") {
                ForEach($recordingCredits) { $entry in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Role (e.g., Lead Vocals, Guitar)", text: $entry.role, axis: .vertical)
                        CreditNameField(placeholder: "Name", text: $entry.name, profileID: $entry.profileID)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    recordingCredits.remove(atOffsets: indexSet)
                }

                Button {
                    recordingCredits.append(OrderedEntry())
                } label: {
                    Label("Add Recording Credit", systemImage: "plus.circle.fill")
                        .foregroundStyle(Color.brandOrange)
                }
            }

            Section("Production") {
                ForEach($productionCredits) { $entry in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Role (e.g., Producer, Mix Engineer)", text: $entry.role, axis: .vertical)
                        CreditNameField(placeholder: "Name", text: $entry.name, profileID: $entry.profileID)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    productionCredits.remove(atOffsets: indexSet)
                }

                Button {
                    productionCredits.append(OrderedEntry())
                } label: {
                    Label("Add Production Credit", systemImage: "plus.circle.fill")
                        .foregroundStyle(Color.brandOrange)
                }
            }
        }
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Seed the standard role fields the first time the form is opened.
            if recordingCredits.isEmpty {
                recordingCredits = defaultRecordingRoles.map { OrderedEntry(role: $0) }
            }
            if productionCredits.isEmpty {
                productionCredits = defaultProductionRoles.map { OrderedEntry(role: $0) }
            }
        }
    }
}

// MARK: - Project Team Form Views

/// A cast-needed entry stores the role and an optional description in a single string
/// (kept as `[String]` for CloudKit) using a `": "` separator — e.g. "Lead Actor: villain,
/// mid-20s". These helpers split/join that encoding so the form can edit the two parts
/// separately and the card can show them role-left / description-right.
enum CastRoleFormat {
    private static let separator = ": "

    static func split(_ raw: String) -> (role: String, description: String) {
        if let range = raw.range(of: separator) {
            return (String(raw[..<range.lowerBound]), String(raw[range.upperBound...]))
        }
        return (raw, "")
    }

    static func join(role: String, description: String) -> String {
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return desc.isEmpty ? role : "\(role)\(separator)\(desc)"
    }
}

/// Cast roles still open for a project. Styled like the Film cast page (a List
/// section with an Add button); each row has a role field and an optional
/// description field (e.g. character notes), shown on the card beside the role.
struct ProjectCastNeededFormView: View {
    @Binding var castNeeded: [String]

    /// Role name for the entry at `index`, backed by the encoded `"Role: Description"` string.
    private func roleBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { CastRoleFormat.split(castNeeded[index]).role },
            set: { castNeeded[index] = CastRoleFormat.join(role: $0, description: CastRoleFormat.split(castNeeded[index]).description) }
        )
    }

    /// Optional description for the entry at `index`.
    private func descriptionBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { CastRoleFormat.split(castNeeded[index]).description },
            set: { castNeeded[index] = CastRoleFormat.join(role: CastRoleFormat.split(castNeeded[index]).role, description: $0) }
        )
    }

    var body: some View {
        List {
            Section("Roles Needed") {
                ForEach(castNeeded.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Role (e.g., Lead Actor)", text: roleBinding(index), axis: .vertical)
                        TextField("Description (optional)", text: descriptionBinding(index), axis: .vertical)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    castNeeded.remove(atOffsets: indexSet)
                }

                Button("Add Available Role") {
                    castNeeded.append("")
                }
            }
        }
        .navigationTitle("Cast Needed")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Crew roles still open for a project — mirrors the Cast Needed page.
struct ProjectCrewNeededFormView: View {
    @Binding var crewNeeded: [String]

    var body: some View {
        List {
            Section("Roles Needed") {
                ForEach(crewNeeded.indices, id: \.self) { index in
                    TextField("Role (e.g., Sound Mixer)", text: $crewNeeded[index], axis: .vertical)
                }
                .onDelete { indexSet in
                    crewNeeded.remove(atOffsets: indexSet)
                }

                Button("Add Available Role") {
                    crewNeeded.append("")
                }
            }
        }
        .navigationTitle("Crew Needed")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct VideoPickerView: View {
    let completion: (Result<URL, Error>) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VideoPickerHelper(completion: { result in
            completion(result)
            dismiss()
        })
    }
}

struct DocumentPickerView: View {
    let allowedTypes: [UTType]
    let completion: (Result<URL, Error>) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        DocumentPicker(
            contentTypes: allowedTypes,
            onSelect: { url in
                completion(.success(url))
                dismiss()
            },
            onCancel: {
                completion(.failure(NSError(domain: "DocumentPicker", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cancelled"])))
                dismiss()
            }
        )
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onSelect: (URL) -> Void
    let onCancel: () -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        // Route the "loading" indicator to the field that's actually being filled:
        // image picks drive the image spinner (album cover / thumbnail / poster /
        // flyer rows), everything else drives the video/file download ring. This keeps
        // the indicator scoped to the right row instead of the whole upload section.
        let isImagePick = !contentTypes.isEmpty && contentTypes.allSatisfy { $0.conforms(to: .image) }
        return Coordinator(onSelect: onSelect, onCancel: onCancel, isImagePick: isImagePick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL) -> Void
        let onCancel: () -> Void
        /// Whether the picked content is an image, so the correct field-scoped loading
        /// indicator is shown while the file is materialized.
        let isImagePick: Bool

        init(onSelect: @escaping (URL) -> Void, onCancel: @escaping () -> Void, isImagePick: Bool = false) {
            self.onSelect = onSelect
            self.onCancel = onCancel
            self.isImagePick = isImagePick
        }

        /// Begin/end the field-appropriate loading indicator around the file copy.
        private func beginLoadingIndicator() {
            DispatchQueue.main.async {
                if self.isImagePick { MediaDownloadCenter.shared.beginImageLoad() }
                else { MediaDownloadCenter.shared.begin() }
            }
        }
        private func endLoadingIndicator() {
            if isImagePick { MediaDownloadCenter.shared.finishImageLoad() }
            else { MediaDownloadCenter.shared.finish() }
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancel()
                return
            }

            // The picked URL is security-scoped and, for a Files / iCloud-Drive item that
            // hasn't been downloaded to the device ("deep in Files"), can point at a
            // placeholder rather than the real bytes. Copy it into our own temp sandbox
            // through an NSFileCoordinator using `.forUploading`, which triggers the
            // iCloud download and waits for it to finish. Without this, the downstream
            // copy grabs a 0-byte placeholder and the post uploads with no usable media —
            // or the upload fails and the post silently never appears anywhere.
            let didAccess = url.startAccessingSecurityScopedResource()
            let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)

            // Show the field-scoped loading indicator while the (possibly large,
            // possibly iCloud-hosted) file transfers; the picker sheet has dismissed.
            beginLoadingIndicator()

            DispatchQueue.global(qos: .userInitiated).async {
                var coordinatorError: NSError?
                var materialized = false
                NSFileCoordinator().coordinate(readingItemAt: url, options: [.forUploading], error: &coordinatorError) { readURL in
                    do {
                        try? FileManager.default.removeItem(at: tempURL)
                        try FileManager.default.copyItem(at: readURL, to: tempURL)
                        materialized = FileManager.default.fileExistsAndIsAccessible(at: tempURL)
                    } catch {
                        print("❌ DocumentPicker: failed to copy picked file: \(error.localizedDescription)")
                    }
                }
                if let coordinatorError {
                    print("❌ DocumentPicker: file coordination failed: \(coordinatorError.localizedDescription)")
                }
                if didAccess { url.stopAccessingSecurityScopedResource() }

                DispatchQueue.main.async {
                    self.endLoadingIndicator()
                    if materialized {
                        self.onSelect(tempURL)
                    } else {
                        // Couldn't get the real bytes — treat as a cancel so we never
                        // create a post backed by missing/placeholder media.
                        self.onCancel()
                    }
                }
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

// MARK: - Multi-Image Document Picker

/// Files-app picker that allows selecting MULTIPLE images at once, materializing each
/// (including iCloud-Drive placeholders) before handing back the loaded `UIImage`s. Used by
/// the film BTS-photos / stills rows, which accept any number of images and no videos.
struct MultiImageDocumentPicker: UIViewControllerRepresentable {
    let onSelect: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image])
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onCancel: onCancel)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onSelect: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !urls.isEmpty else {
                onCancel()
                return
            }
            DispatchQueue.main.async { MediaDownloadCenter.shared.beginImageLoad() }
            DispatchQueue.global(qos: .userInitiated).async {
                var images: [UIImage] = []
                for url in urls {
                    let didAccess = url.startAccessingSecurityScopedResource()
                    var coordinatorError: NSError?
                    // Coordinate the read so an iCloud-Drive placeholder is downloaded to
                    // real bytes before we decode it (see the single-file DocumentPicker).
                    NSFileCoordinator().coordinate(readingItemAt: url, options: [.forUploading], error: &coordinatorError) { readURL in
                        if let data = try? Data(contentsOf: readURL), let image = UIImage(data: data) {
                            images.append(image)
                        }
                    }
                    if didAccess { url.stopAccessingSecurityScopedResource() }
                }
                DispatchQueue.main.async {
                    MediaDownloadCenter.shared.finishImageLoad()
                    if images.isEmpty { self.onCancel() } else { self.onSelect(images) }
                }
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

// MARK: - Photo Picker for Thumbnail

struct PhotoPickerForThumbnail: View {
    @Binding var selectedImage: UIImage?
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ImagePickerController(selectedImage: $selectedImage, onDismiss: {
            dismiss()
            onDismiss()
        })
    }
}

struct ImagePickerController: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(selectedImage: $selectedImage, onDismiss: onDismiss)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        @Binding var selectedImage: UIImage?
        let onDismiss: () -> Void
        
        init(selectedImage: Binding<UIImage?>, onDismiss: @escaping () -> Void) {
            _selectedImage = selectedImage
            self.onDismiss = onDismiss
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                selectedImage = image
            }
            onDismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onDismiss()
        }
    }
}

// MARK: - Video State Views

struct VideoErrorStateView: View {
    @Binding var videoLoadError: Bool
    @Binding var showVideoPicker: Bool
    @Binding var showDocumentPicker: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text("Failed to load video")
                    .foregroundStyle(.red)
            }
            
            HStack(spacing: 12) {
                Button("Retry from Photos") {
                    videoLoadError = false
                    showVideoPicker = true
                }
                .font(.caption)
                
                Button("Retry from Files") {
                    videoLoadError = false
                    showDocumentPicker = true
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - Credit Name Field Preview

#if DEBUG
#endif
