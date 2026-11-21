//
//  TVService.swift
//  Longhorn Artists Connect
//
//  The verification service's Apple TV routes (verification-service/src/tv.ts),
//  and the Keychain item holding this TV's session token.
//

import Foundation
import Security

enum TVService {

    /// The same service the iPhone app verifies through. Read from the bundled
    /// Secrets.plist, like `StudentVerificationManager.baseURL`.
    static var baseURL: URL? {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let dict = NSDictionary(contentsOf: url),
            let value = dict["VerificationServiceBaseURL"] as? String,
            !value.isEmpty, !value.hasPrefix("REPLACE_WITH_")
        else { return nil }
        return URL(string: value)
    }

    /// A refusal from the service, with its message for the screen.
    struct Failure: Error {
        let status: Int
        let code: String
        let message: String
    }

    private struct ErrorBody: Decodable {
        let error: String?
        let message: String?
    }

    static func post<Response: Decodable>(_ path: String, _ body: [String: String] = [:]) async throws -> Response {
        guard let baseURL else {
            throw Failure(status: 0, code: "not_configured", message: "Sign-in isn't set up in this build.")
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let error = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw Failure(
                status: status,
                code: error?.error ?? "",
                message: error?.message ?? "Something went wrong. Try again."
            )
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

/// This TV's session token, in the Keychain so it survives relaunches.
enum TVSessionStore {
    private static let service = "LAA.Longhorn-Artists-Connect.tv-session"

    static var token: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        clear()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(token.utf8)
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
