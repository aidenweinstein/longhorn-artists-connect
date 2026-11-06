//
//  CloudKitWebServices.swift
//  Longhorn Artists Connect
//
//  Fetches range-streamable HTTPS URLs for CloudKit assets via the CloudKit Web
//  Services REST API. The native CloudKit framework only exposes a CKAsset's file
//  *after* the entire file has downloaded, which is why large videos take a long
//  time to start. The web-services `downloadURL` is a CDN URL that supports HTTP
//  range requests, so AVPlayer can stream a video and begin playing before the
//  whole file arrives.
//

import Foundation

/// The detailed outcome of resolving a streamable asset URL. Unlike a bare `URL?`, this
/// tells apart *why* streaming isn't happening — so the UI can show an accurate status
/// ("File Non-Existent", "Error Streaming", …) instead of a blanket "Coming Soon".
enum StreamResolution {
    /// Got a range-streamable CDN URL — play it.
    case streaming(URL)
    /// No CloudKit Web Services API token is configured for this build's environment.
    case notConfigured
    /// A network / HTTP failure contacting CloudKit. `code` is the HTTP status, or a
    /// negative sentinel for a transport-level failure (couldn't reach the server).
    case lookupError(Int)
    /// The record doesn't exist in this environment (e.g. a prod build looking up a
    /// dev-only record, or a deleted post).
    case recordNotFound
    /// The record exists but carries no file in that asset field (nothing was uploaded).
    case assetMissing
    /// The asset is present but CloudKit returned no `downloadURL` for it.
    case noDownloadURL
}

/// Resolves streamable download URLs for public-database CloudKit assets.
///
/// Requires a **public-database API token** created in the CloudKit Dashboard
/// (your container → Tokens & Keys → API Tokens). Paste it into `apiToken` below.
/// Until a real token is set, `isConfigured` is false and callers fall back to the
/// existing full-download path, so the app keeps working unchanged.
enum CloudKitWebServices {

    /// API tokens are **per-environment** — a token created in Development is NOT valid in
    /// Production, and vice versa (CloudKit docs: "create an API token for each container in
    /// each environment"). The tokens are kept OUT of source control: they live in a
    /// bundled, git-ignored `Secrets.plist` (see `Secrets.example.plist` for the format and
    /// how to create the tokens). A missing file yields empty tokens → `isConfigured` is
    /// false and callers fall back gracefully.
    static let apiTokenDevelopment = secret(forKey: "CloudKitAPITokenDevelopment")
    static let apiTokenProduction = secret(forKey: "CloudKitAPITokenProduction")

    /// Reads a secret value, preferring the build-time injected Info.plist entry (from
    /// `Secrets.xcconfig` → Info.plist, baked into every build config), and falling back
    /// to a bundled `Secrets.plist` for backward compatibility. Returns "" if neither is
    /// present.
    private static func secret(forKey key: String) -> String {
        // 1) Build-time injected value (Secrets.xcconfig → Info.plist). Guard against an
        // unresolved `$(...)` placeholder, which is what appears when the xcconfig/build
        // setting is missing at build time.
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           !value.isEmpty, !value.hasPrefix("$(") {
            return value
        }
        // 2) Legacy fallback: a bundled Secrets.plist.
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let dict = NSDictionary(contentsOf: url),
            let value = dict[key] as? String
        else { return "" }
        return value
    }

    /// The API token for the resolved `environment`. Derived from `environment` (not from
    /// `#if DEBUG`) so the token and the environment string can never desync — an
    /// env/token mismatch is what CloudKit rejects with an auth error.
    static var apiToken: String {
        environment == "production" ? apiTokenProduction : apiTokenDevelopment
    }

    /// Must match the app's iCloud container identifier (see the entitlements file).
    static let containerID = "iCloud.LAA.Longhorn-Artists-Connect"

    /// Which CloudKit environment the **web-services (streaming) layer** talks to.
    ///
    /// Always the same environment as the native `CKContainer` (which follows the build's
    /// provisioning: run from Xcode → development; TestFlight/App Store → production), so
    /// a post is streamed from the environment it was uploaded to and fetched from. The
    /// two environments are kept fully separate — a Debug build never sees production
    /// posts, and a release build never sees development ones.
    static var environment: String {
        CloudKitEnvironmentDetector.isDevelopment ? "development" : "production"
    }

    /// Whether a usable API token has been configured for the current environment. When
    /// false, callers should fall back to downloading the full asset.
    static var isConfigured: Bool {
        !apiToken.isEmpty && !apiToken.hasPrefix("REPLACE_WITH_")
    }

    /// Looks up a single public record and returns the range-streamable download URL
    /// for one asset field, or nil if unavailable / not configured. The URL is a
    /// short-lived signed CDN link, so it is fetched fresh per playback rather than
    /// cached.
    static func assetDownloadURL(recordName: String, field: String) async -> URL? {
        let (lookup, _) = await assetFieldLookup(recordName: recordName, field: field)
        guard
            case .value(let value, let storedExtension) = lookup,
            let urlString = value["downloadURL"] as? String
        else { return nil }

        let (url, _) = await Self.streamURL(template: urlString, field: field, storedExtension: storedExtension)
        return url
    }

    /// Builds the final streaming URL from a `downloadURL` template.
    ///
    /// The `${f}` token in the template is the filename the CDN serves the asset as, and
    /// the CDN derives the response `Content-Type` from that filename's extension.
    /// Substituting an empty string (as we used to) yields an extensionless URL served as
    /// `application/octet-stream`, which AVFoundation can't identify — so streamed media
    /// never played and only already-downloaded local files worked.
    ///
    /// Getting the *right* extension matters just as much, because AVFoundation trusts the
    /// server's MIME over the actual bytes: every production music upload is an MP3, and
    /// serving one under a hardcoded `media.m4a` name made the CDN claim `audio/mp4`, so
    /// the player tried to parse MP3 data as MP4 and failed with "Cannot Open" (-11828).
    /// Returns the URL plus a diagnostic fragment naming the filename that was used.
    private static func streamURL(
        template: String,
        field: String,
        storedExtension: String?
    ) async -> (URL?, String) {
        func url(named ext: String) -> URL? {
            URL(string: template.replacingOccurrences(of: "${f}", with: "media.\(ext)"))
        }

        var chosen = normalizedExtension(storedExtension) ?? defaultExtension(for: field)
        var source = storedExtension == nil ? "default" : "record"

        // The recorded extension can't be relied on — most music records carry none, and
        // some carry one that disagrees with the file — so confirm the container from the
        // asset's own leading bytes. One 16-byte ranged request, once per playback.
        if sniffsContainer(field), let probe = url(named: chosen),
           let sniffed = await containerExtension(atStartOf: probe, isAudio: true) {
            chosen = sniffed
            source = "sniffed"
        }
        return (url(named: chosen), "as=media.\(chosen)(\(source))")
    }

    /// Extension to assume for an asset field when nothing better is known. Videos are
    /// QuickTime `.mov` (how the app exports and uploads them); audio is `.m4a`.
    private static func defaultExtension(for field: String) -> String {
        switch field {
        case "filmVideo", "reelVideo", "filmTrailer": return "mov"
        case "musicAudio", "musicTracks":             return "m4a"
        default:                                      return "bin"
        }
    }

    /// Whether the container for this field should be confirmed from the file's bytes.
    /// Only audio does: video uploads are always the app's own `.mov` exports, and the
    /// video path already streams correctly, so it's left untouched.
    private static func sniffsContainer(_ field: String) -> Bool {
        field == "musicAudio" || field == "musicTracks"
    }

    /// Identifies a media container from the first bytes of the streamed file. Nil when
    /// the probe fails or the signature isn't recognized — the caller then keeps whatever
    /// extension it already had.
    private static func containerExtension(atStartOf url: URL, isAudio: Bool) async -> String? {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-15", forHTTPHeaderField: "Range")
        request.timeoutInterval = 10
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            http.statusCode == 200 || http.statusCode == 206,
            data.count >= 12
        else { return nil }
        return containerExtension(forHeaderBytes: [UInt8](data), isAudio: isAudio)
    }

    /// Maps a 12+ byte file header to a container extension.
    static func containerExtension(forHeaderBytes bytes: [UInt8], isAudio: Bool) -> String? {
        guard bytes.count >= 12 else { return nil }
        func ascii(_ range: Range<Int>) -> String {
            String(bytes: bytes[range], encoding: .ascii) ?? ""
        }
        // An ID3 tag, or a raw MPEG audio frame sync (11 set bits), means MP3.
        if ascii(0..<3) == "ID3" { return "mp3" }
        if bytes[0] == 0xFF, bytes[1] & 0xE0 == 0xE0 { return "mp3" }
        if ascii(4..<8) == "ftyp" {
            let brand = ascii(8..<12)
            if brand.hasPrefix("qt") { return "mov" }
            if brand.hasPrefix("M4A") || brand.hasPrefix("M4B") { return "m4a" }
            // Any other MP4-family brand: audio-only files are correctly typed as
            // `audio/mp4` via `.m4a`, while video keeps `.mp4`.
            return isAudio ? "m4a" : "mp4"
        }
        if ascii(0..<4) == "RIFF" { return "wav" }
        if ascii(0..<4) == "FORM" { return "aiff" }
        if ascii(0..<4) == "fLaC" { return "flac" }
        if ascii(0..<4) == "caff" { return "caf" }
        return nil
    }

    /// Sanitizes a stored extension for use in a URL path component: strips a leading dot
    /// and whitespace, lowercases, and rejects anything that isn't plainly alphanumeric
    /// (a stray value must not be able to inject path or query characters).
    private static func normalizedExtension(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard !trimmed.isEmpty, trimmed.count <= 5,
              trimmed.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return trimmed
    }

    /// The record's companion string field holding an asset's real container extension,
    /// if the schema has one for that asset field. Requested alongside the asset so the
    /// `${f}` filename can carry the true container (see `streamFileName`).
    private static func extensionField(for field: String) -> String? {
        switch field {
        case "musicAudio": return "musicAudioExt"
        default:           return nil
        }
    }

    /// The byte size of an asset field on a public record, read from the record
    /// metadata **without downloading the file** (the asset value dictionary carries a
    /// `size`). Returns nil when unavailable / not configured. Lets the moderator
    /// dashboard show an uploaded file's size without paying to fetch the whole asset.
    static func assetSize(recordName: String, field: String) async -> Int64? {
        guard let size = await assetValue(recordName: recordName, field: field)?["size"] as? NSNumber
        else { return nil }
        return size.int64Value
    }

    /// Resolves a range-streamable download URL for one asset field, returning a detailed
    /// `StreamResolution` so callers (and the UI) can tell apart the failure modes —
    /// not-configured / network error / record-gone / no-file-uploaded / no-download-URL —
    /// rather than collapsing every one into a single nil.
    static func streamResolution(recordName: String, field: String) async -> StreamResolution {
        await streamResolutionDetailed(recordName: recordName, field: field).0
    }

    /// Like `streamResolution`, but also returns a compact human-readable diagnostic of
    /// exactly what the server handed *this device* (environment, HTTP status, which field
    /// keys came back, whether a `downloadURL` was present). Surfaced on-screen so a
    /// device-only failure can be inspected without a console — e.g. why a production
    /// TestFlight build reports "File Non-Existent" while the same lookup works elsewhere.
    static func streamResolutionDetailed(recordName: String, field: String) async -> (StreamResolution, String) {
        let (lookup, debug) = await assetFieldLookup(recordName: recordName, field: field)
        switch lookup {
        case .notConfigured:         return (.notConfigured, debug)
        case .lookupError(let code): return (.lookupError(code), debug)
        case .recordNotFound:        return (.recordNotFound, debug)
        case .assetMissing:          return (.assetMissing, debug)
        case .value(let value, let storedExtension):
            guard let urlString = value["downloadURL"] as? String else {
                return (.noDownloadURL, debug + " valueKeys=\(Array(value.keys).sorted())")
            }
            let (url, detail) = await Self.streamURL(
                template: urlString, field: field, storedExtension: storedExtension
            )
            guard let url else { return (.noDownloadURL, debug + " badURL") }
            return (.streaming(url), debug + " " + detail)
        }
    }

    /// Range-streamable URLs for every file in an asset-list field, in list order — used
    /// for an EP/Album's extra tracks (`musicTracks`, with container extensions in the
    /// parallel `extensionListField`). The feed never fetches that list, so this is the
    /// only way a viewer's device learns the tracks exist. Returns an empty array when
    /// streaming isn't configured, the lookup fails, or the record has no list (singles,
    /// performances, and every record from before the field existed).
    static func streamURLs(recordName: String, listField: String, extensionListField: String?) async -> [URL] {
        guard isConfigured, let endpoint = URL(string:
            "https://api.apple-cloudkit.com/database/1/\(containerID)/\(environment)/public/records/lookup?ckAPIToken=\(apiToken)"
        ) else { return [] }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "records": [["recordName": recordName]],
            "desiredKeys": [listField] + (extensionListField.map { [$0] } ?? [])
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let record = (json["records"] as? [[String: Any]])?.first,
            let fields = record["fields"] as? [String: Any],
            // An ASSET_LIST arrives as `{"value": [assetValue, …], "type": "ASSET_LIST"}`.
            let assets = (fields[listField] as? [String: Any])?["value"] as? [[String: Any]]
        else { return [] }

        let exts = extensionListField
            .flatMap { (fields[$0] as? [String: Any])?["value"] as? [String] } ?? []

        var urls: [URL] = []
        for (index, asset) in assets.enumerated() {
            guard let template = asset["downloadURL"] as? String else { continue }
            let (url, _) = await Self.streamURL(
                template: template,
                field: listField,
                storedExtension: index < exts.count ? exts[index] : nil
            )
            if let url { urls.append(url) }
        }
        return urls
    }

    /// Outcome of a single asset-field lookup, before it's interpreted for streaming vs.
    /// size. Kept distinct from `StreamResolution` so the size path can reuse it too.
    private enum AssetFieldLookup {
        /// The asset value dict (downloadURL, size, checksums, …), plus the container
        /// extension recorded alongside the asset — nil when the schema has no companion
        /// extension field for it, or the record predates one.
        case value([String: Any], fileExtension: String?)
        case notConfigured
        case lookupError(Int)
        case recordNotFound
        case assetMissing
    }

    /// Shared record/asset lookup: returns the CloudKit Web Services `value` dictionary
    /// for one asset field (which contains `downloadURL`, `size`, checksums, …), or nil
    /// if unavailable / not configured.
    private static func assetValue(recordName: String, field: String) async -> [String: Any]? {
        if case .value(let value, _) = await assetFieldLookup(recordName: recordName, field: field).0 {
            return value
        }
        return nil
    }

    /// The detailed record/asset lookup underlying both `assetValue` (size path) and
    /// `streamResolution` (streaming path). Distinguishes a missing record, a missing
    /// asset field, and a network failure so the caller can report exactly what happened.
    /// The returned string is a compact diagnostic of the actual server response.
    private static func assetFieldLookup(recordName: String, field: String) async -> (AssetFieldLookup, String) {
        let prefix = "env=\(environment) field=\(field)"
        guard isConfigured else { return (.notConfigured, "\(prefix) not-configured tokenLen=\(apiToken.count)") }
        guard let endpoint = URL(string:
            "https://api.apple-cloudkit.com/database/1/\(containerID)/\(environment)/public/records/lookup?ckAPIToken=\(apiToken)"
        ) else { return (.lookupError(-1), "\(prefix) bad-endpoint") }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Fetch the companion extension field in the same lookup — the streamed URL's
        // filename has to carry the real container, or the CDN reports the wrong MIME.
        var desiredKeys = [field]
        if let extField = extensionField(for: field) { desiredKeys.append(extField) }
        let body: [String: Any] = [
            "records": [["recordName": recordName]],
            "desiredKeys": desiredKeys
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                print("❌ CloudKit web-services lookup: no HTTP response for \(recordName)")
                return (.lookupError(-1), "\(prefix) no-http-response")
            }
            guard http.statusCode == 200 else {
                print("❌ CloudKit web-services lookup failed (HTTP \(http.statusCode)) for \(recordName)")
                return (.lookupError(http.statusCode), "\(prefix) http=\(http.statusCode)")
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let records = json["records"] as? [[String: Any]],
                let record = records.first
            else {
                print("❌ CloudKit web-services lookup: malformed response for \(recordName)")
                return (.lookupError(-2), "\(prefix) http=200 malformed")
            }
            // A per-record server error (e.g. "NOT_FOUND") means the record itself isn't
            // in this environment — distinct from a record that exists without the asset.
            if let serverErrorCode = record["serverErrorCode"] as? String, !serverErrorCode.isEmpty {
                print("❌ CloudKit web-services lookup: record \(recordName) → \(serverErrorCode)")
                return (.recordNotFound, "\(prefix) http=200 \(serverErrorCode)")
            }
            let fields = record["fields"] as? [String: Any]
            let fieldKeys = fields.map { Array($0.keys).sorted() } ?? []
            guard
                let fields,
                let asset = fields[field] as? [String: Any],
                let value = asset["value"] as? [String: Any]
            else {
                let assetKeys = (fields?[field] as? [String: Any]).map { Array($0.keys).sorted() }
                let detail = "\(prefix) http=200 fieldsKeys=\(fieldKeys)" +
                    (assetKeys.map { " assetKeys=\($0)" } ?? " fieldAbsent")
                print("⚠️ CloudKit web-services lookup: asset missing → \(detail)")
                return (.assetMissing, detail)
            }
            // Web services wraps every field as `{"value": …, "type": …}`, so the
            // extension arrives as a nested string value.
            let storedExtension = extensionField(for: field)
                .flatMap { fields[$0] as? [String: Any] }
                .flatMap { $0["value"] as? String }
            return (.value(value, fileExtension: storedExtension), "\(prefix) http=200 ok ext=\(storedExtension ?? "none")")
        } catch {
            print("❌ CloudKit web-services lookup error for \(recordName): \(error)")
            return (.lookupError(-1), "\(prefix) transport-error \(error.localizedDescription)")
        }
    }
}
