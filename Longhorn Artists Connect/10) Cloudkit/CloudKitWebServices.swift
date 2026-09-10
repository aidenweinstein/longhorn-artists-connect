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

    /// Reads a string value from the bundled `Secrets.plist`, or "" if absent.
    private static func secret(forKey key: String) -> String {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let dict = NSDictionary(contentsOf: url),
            let value = dict[key] as? String
        else { return "" }
        return value
    }

    /// The API token for the current build's environment (see `environment`).
    static var apiToken: String {
        #if DEBUG
        return apiTokenDevelopment
        #else
        return apiTokenProduction
        #endif
    }

    /// Must match the app's iCloud container identifier (see the entitlements file).
    static let containerID = "iCloud.LAA.Longhorn-Artists-Connect"

    /// CloudKit keeps DEBUG builds on the development environment and release /
    /// TestFlight builds on production, mirroring the native `CKContainer`.
    static var environment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
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
        guard var urlString = await assetValue(recordName: recordName, field: field)?["downloadURL"] as? String
        else { return nil }

        // Web-services download URLs sometimes carry a literal `${f}` template
        // token; it resolves to an empty filename for a plain asset fetch.
        urlString = urlString.replacingOccurrences(of: "${f}", with: "")
        return URL(string: urlString)
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

    /// Shared record/asset lookup: returns the CloudKit Web Services `value` dictionary
    /// for one asset field (which contains `downloadURL`, `size`, checksums, …), or nil
    /// if unavailable / not configured.
    private static func assetValue(recordName: String, field: String) async -> [String: Any]? {
        guard isConfigured else { return nil }
        guard let endpoint = URL(string:
            "https://api.apple-cloudkit.com/database/1/\(containerID)/\(environment)/public/records/lookup?ckAPIToken=\(apiToken)"
        ) else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "records": [["recordName": recordName]],
            "desiredKeys": [field]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("❌ CloudKit web-services lookup failed (HTTP \(code)) for \(recordName)")
                return nil
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let records = json["records"] as? [[String: Any]],
                let fields = records.first?["fields"] as? [String: Any],
                let asset = fields[field] as? [String: Any],
                let value = asset["value"] as? [String: Any]
            else { return nil }
            return value
        } catch {
            print("❌ CloudKit web-services lookup error for \(recordName): \(error)")
            return nil
        }
    }
}
