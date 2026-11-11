//
//  StudentVerificationManager.swift
//  Longhorn Artists Connect
//
//  Client for the student verification service (see verification-service/).
//
//  The authoritative "this user is verified" signal is the `Verification`
//  CloudKit record, which only the service's server-to-server key may write.
//  Nothing in this file can mark a user verified — it can only ask the service
//  to do so, and read back the result. That separation is the whole point: a
//  flag on `UserProfile` would be writable by its owner and therefore worthless.
//

import Foundation
import CloudKit
import Observation

/// Error payload the service returns alongside a non-2xx status.
private struct ServiceErrorPayload: Decodable {
    let message: String
}

@MainActor
@Observable
final class StudentVerificationManager {

    static let shared = StudentVerificationManager()

    // MARK: - Types

    enum Status: Equatable {
        case unknown
        case unverified
        case verified(schoolName: String)

        var isVerified: Bool {
            if case .verified = self { return true }
            return false
        }
    }

    struct School: Identifiable, Decodable, Hashable {
        let id: String
        let name: String
        let shortName: String?
        let state: String?
    }

    /// What an address is being verified for.
    enum Purpose: String {
        /// A school address — the domain must be in the service's registry.
        case school
        /// Enthusiast sign-up: any address the user controls.
        case enthusiast
    }

    /// Handle for a code that's been emailed but not yet confirmed.
    struct PendingVerification {
        let id: String
        let expiresAt: Date
        let schoolName: String
        let email: String
    }

    enum VerificationError: LocalizedError {
        case notConfigured
        case noAccount
        case service(String)
        case network

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Verification isn't configured in this build."
            case .noAccount:
                return "Sign in to iCloud to verify your school email."
            case .service(let message):
                return message
            case .network:
                return "Couldn't reach the verification service. Check your connection."
            }
        }
    }

    // MARK: - State

    private(set) var status: Status = .unknown
    private(set) var isBusy = false

    /// Registry slug of the verified school ("ut-austin", "berkeley"), or nil
    /// when this account has no `Verification` record. This — not the display
    /// name in `status` — is what posts and feed queries key on; see
    /// `SchoolScope`.
    private(set) var verifiedSchoolID: String?

    /// The address this device verified, for display in Edit Profile only.
    /// The `Verification` record stores just a hash of the email, so this is
    /// nil when verification happened on another device.
    private(set) var verifiedEmail: String?

    /// Cached so the UI isn't gated behind a network round trip at launch.
    /// Advisory only — `refreshStatus()` re-reads the authoritative record.
    private let cacheKey = "studentVerificationCachedSchool"
    private let schoolIDCacheKey = "studentVerificationCachedSchoolID"
    private let emailCacheKey = "studentVerificationCachedEmail"

    private let session = URLSession(configuration: .default)

    private init() {
        if let cached = UserDefaults.standard.string(forKey: cacheKey), !cached.isEmpty {
            status = .verified(schoolName: cached)
        }
        verifiedSchoolID = UserDefaults.standard.string(forKey: schoolIDCacheKey).flatMap {
            $0.isEmpty ? nil : $0
        }
        verifiedEmail = UserDefaults.standard.string(forKey: emailCacheKey).flatMap {
            $0.isEmpty ? nil : $0
        }
    }

    // MARK: - Configuration

    /// Base URL of the deployed Worker, e.g. "https://lac-verification.<sub>.workers.dev".
    /// Supplied the same way as the CloudKit tokens: Secrets.xcconfig → Info.plist,
    /// with a bundled Secrets.plist fallback.
    private static var baseURL: URL? {
        let key = "VerificationServiceBaseURL"

        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           !value.isEmpty, !value.hasPrefix("$(") {
            return URL(string: value)
        }
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let dict = NSDictionary(contentsOf: url),
            let value = dict[key] as? String,
            !value.isEmpty, !value.hasPrefix("REPLACE_WITH_")
        else { return nil }
        return URL(string: value)
    }

    /// Whether a service URL is present. When false, nothing can actually be
    /// verified, so release builds behave as though verification didn't exist
    /// rather than walling users out.
    static var isConfigured: Bool { baseURL != nil }

    /// Whether to show the verification UI at all.
    ///
    /// Debug builds show it even with no service URL, so the screens can be
    /// laid out and walked through before the Worker is deployed — otherwise
    /// the UI is invisible until the backend exists, which makes it impossible
    /// to test in the order you'd actually build things. Attempting to send a
    /// code in that state surfaces `VerificationError.notConfigured`.
    static var isUIAvailable: Bool {
        #if DEBUG
        return true
        #else
        return isConfigured
        #endif
    }

    /// Whether verification is enforced in this build.
    ///
    /// Development builds (the CloudKit Development environment: Xcode runs
    /// and the simulator) skip it entirely — onboarding doesn't show the step
    /// and `VerificationGate` stays open — so test accounts don't need a real
    /// school address. Verifying voluntarily from Edit Profile still works,
    /// and the moderator's test-email button still exercises the real send.
    /// Keyed on the CloudKit environment rather than `#if DEBUG` for the same
    /// reason `CloudKitEnvironmentDetector` exists: a Debug-configured archive
    /// on TestFlight must still enforce.
    static var isRequired: Bool {
        !CloudKitEnvironmentDetector.isDevelopment
    }

    // MARK: - Status

    /// Re-reads the `Verification` record from CloudKit. This is the source of
    /// truth; the service writes it and the client can only read it.
    func refreshStatus() async {
        guard let userRecordName = try? await CKContainer.default().userRecordID().recordName else {
            status = .unverified
            return
        }

        let recordID = CKRecord.ID(recordName: "Verification_\(userRecordName)")
        do {
            let record = try await CKContainer.default().publicCloudDatabase.record(for: recordID)
            let schoolName = (record["schoolName"] as? String) ?? "your school"
            status = .verified(schoolName: schoolName)
            UserDefaults.standard.set(schoolName, forKey: cacheKey)

            if let schoolID = (record["schoolID"] as? String), !schoolID.isEmpty {
                verifiedSchoolID = schoolID
                UserDefaults.standard.set(schoolID, forKey: schoolIDCacheKey)
            }
        } catch {
            // A missing record means "not verified"; any other error leaves the
            // cached value alone rather than locking a verified user out on a
            // transient failure.
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                status = .unverified
                verifiedSchoolID = nil
                verifiedEmail = nil
                UserDefaults.standard.removeObject(forKey: cacheKey)
                UserDefaults.standard.removeObject(forKey: schoolIDCacheKey)
                UserDefaults.standard.removeObject(forKey: emailCacheKey)
            }
        }
    }

    // MARK: - School registry

    func searchSchools(matching query: String) async throws -> [School] {
        guard let baseURL = Self.baseURL else { throw VerificationError.notConfigured }

        var components = URLComponents(url: baseURL.appendingPathComponent("v1/schools"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { throw VerificationError.notConfigured }

        struct Response: Decodable { let schools: [School] }
        let response: Response = try await get(url)
        return response.schools
    }

    // MARK: - Verification flow

    /// Asks the service to email a code. Also writes the returned nonce onto
    /// this user's own `UserProfile` record — only the account owner can do
    /// that, which is how the service proves the caller owns the account it
    /// claims at confirm time.
    func requestCode(email: String, purpose: Purpose = .school) async throws -> PendingVerification {
        let (pending, nonce, userRecordName) = try await sendCodeRequest(email: email, purpose: purpose)
        try await writeNonce(nonce, userRecordName: userRecordName)
        return pending
    }

    /// Moderator diagnostics: asks the service to email a real code — same
    /// endpoint, template, sender and rate limits as `requestCode` — but skips
    /// the ownership nonce, so the send is checked in isolation and a CloudKit
    /// hiccup can't be mistaken for a mail failure. Without the nonce the code
    /// can never be confirmed, so nothing about the account changes.
    func sendTestCode(email: String) async throws -> PendingVerification {
        try await sendCodeRequest(email: email).pending
    }

    /// The `/v1/verify/request` round trip shared by the real flow and the
    /// moderator's test send.
    private func sendCodeRequest(
        email: String,
        purpose: Purpose = .school
    ) async throws -> (pending: PendingVerification, nonce: String, userRecordName: String) {
        guard let baseURL = Self.baseURL else { throw VerificationError.notConfigured }
        guard let userRecordName = try? await CKContainer.default().userRecordID().recordName else {
            throw VerificationError.noAccount
        }

        isBusy = true
        defer { isBusy = false }

        struct Request: Encodable {
            let email: String
            let userRecordName: String
            let purpose: String
        }
        struct SchoolStub: Decodable { let id: String; let name: String }
        struct Response: Decodable {
            let pendingID: String
            let nonce: String
            let expiresAt: Double
            let school: SchoolStub
        }

        let response: Response = try await post(
            baseURL.appendingPathComponent("v1/verify/request"),
            body: Request(email: email, userRecordName: userRecordName, purpose: purpose.rawValue)
        )

        let pending = PendingVerification(
            id: response.pendingID,
            expiresAt: Date(timeIntervalSince1970: response.expiresAt),
            schoolName: response.school.name,
            email: email
        )
        return (pending, response.nonce, userRecordName)
    }

    /// Submits the emailed code. On success the service has written the
    /// `Verification` record, so we re-read it rather than trusting the reply.
    func confirmCode(_ code: String, for pending: PendingVerification) async throws {
        guard let baseURL = Self.baseURL else { throw VerificationError.notConfigured }

        isBusy = true
        defer { isBusy = false }

        struct Request: Encodable {
            let pendingID: String
            let code: String
        }
        struct Response: Decodable { let verified: Bool }

        let _: Response = try await post(
            baseURL.appendingPathComponent("v1/verify/confirm"),
            body: Request(pendingID: pending.id, code: code)
        )

        await refreshStatus()

        // The service only answers 2xx once it has written the record, so if
        // the read-back missed it (propagation lag, flaky network), trust the
        // reply for this session; the next refresh settles it either way.
        if !status.isVerified {
            status = .verified(schoolName: pending.schoolName)
            UserDefaults.standard.set(pending.schoolName, forKey: cacheKey)
        }
        verifiedEmail = pending.email
        UserDefaults.standard.set(pending.email, forKey: emailCacheKey)
    }

    // MARK: - Ownership proof

    /// Writes the one-time nonce to this user's own `UserProfile` record.
    ///
    /// Creates a stub record if none exists yet: during onboarding the profile
    /// isn't saved to CloudKit until the final step, and `UserProfileModel.save()`
    /// does a fetch-modify-save, so a stub here is filled in rather than clobbered.
    private func writeNonce(_ nonce: String, userRecordName: String) async throws {
        let database = CKContainer.default().publicCloudDatabase
        let recordID = CKRecord.ID(recordName: "UserProfile_\(userRecordName)")

        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: "UserProfile", recordID: recordID)
        }

        record["verificationNonce"] = nonce as CKRecordValue
        _ = try await database.save(record)
    }

    // MARK: - Networking

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await send(request)
    }

    private func post<Body: Encodable, T: Decodable>(_ url: URL, body: Body) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw VerificationError.network
        }

        guard let http = response as? HTTPURLResponse else { throw VerificationError.network }

        guard (200..<300).contains(http.statusCode) else {
            // The service returns { error, message } with user-facing copy.
            if let payload = try? JSONDecoder().decode(ServiceErrorPayload.self, from: data) {
                throw VerificationError.service(payload.message)
            }
            throw VerificationError.service("Verification failed. Try again.")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw VerificationError.service("Unexpected response from the verification service.")
        }
    }
}
