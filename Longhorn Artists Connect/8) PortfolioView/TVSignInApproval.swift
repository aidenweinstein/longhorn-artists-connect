//
//  TVSignInApproval.swift
//  Longhorn Artists Connect
//
//  Signs an Apple TV in as this account. The TV shows a code and a QR code for
//  nexusbylac.com/tv?code=…, which opens here as a universal link (or type the
//  code in More → Sign In to Apple TV). The verification service proves the
//  account the same way school verification does: it hands out a nonce, this
//  device writes it to its own UserProfile, and the service reads it back.
//  See verification-service/src/tv.ts.
//

import CloudKit
import Observation
import SwiftUI

@MainActor
@Observable
final class TVSignInApproval {

    enum Phase: Equatable {
        case idle
        case working
        case approved
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    /// The code in a nexusbylac.com/tv link, or nil for any other URL.
    static func code(from url: URL) -> String? {
        guard
            url.host()?.hasSuffix("nexusbylac.com") == true,
            url.path() == "/tv",
            let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value,
            !code.isEmpty
        else { return nil }
        return code
    }

    func approve(code: String) async {
        phase = .working
        do {
            guard let baseURL = StudentVerificationManager.baseURL else {
                throw ApprovalError("Apple TV sign-in isn't available in this build.")
            }
            let userRecordName = try await CKContainer.default().userRecordID().recordName
            let request = Request(code: code, userRecordName: userRecordName)

            let claim: Claim = try await post(baseURL.appendingPathComponent("v1/tv/pair/claim"), body: request)
            try await StudentVerificationManager.shared.writeNonce(claim.nonce, userRecordName: userRecordName)
            let _: Approved = try await post(baseURL.appendingPathComponent("v1/tv/pair/approve"), body: request)
            phase = .approved
        } catch let error as ApprovalError {
            phase = .failed(error.message)
        } catch {
            phase = .failed("Couldn't sign in the Apple TV. Check your connection and try again.")
        }
    }

    // MARK: - Networking

    private struct Request: Encodable {
        let code: String
        let userRecordName: String
    }

    private struct Claim: Decodable {
        let nonce: String
    }

    private struct Approved: Decodable {
        let approved: Bool
    }

    private struct ServiceError: Decodable {
        let message: String
    }

    private struct ApprovalError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    private func post<Body: Encodable, Response: Decodable>(_ url: URL, body: Body) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(ServiceError.self, from: data))?.message
            throw ApprovalError(message ?? "Couldn't sign in the Apple TV. Try again.")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

/// "Sign in to Apple TV?" — opened from the TV's QR code, or from More.
struct TVSignInApprovalView: View {
    @State private var code: String
    @State private var approval = TVSignInApproval()
    @Environment(\.dismiss) private var dismiss

    init(code: String = "") {
        _code = State(initialValue: code)
    }

    var body: some View {
        NavigationStack {
            Form {
                if approval.phase == .approved {
                    Section {
                        Label("Your Apple TV is signed in.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Section {
                        TextField("ABCD-EFGH", text: $code)
                            .font(.system(.title3, design: .monospaced))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Code on your TV")
                    } footer: {
                        Text("Your Apple TV will watch as your Nexus account. Only approve a TV you're using.")
                    }

                    if case .failed(let message) = approval.phase {
                        Section {
                            Text(message)
                                .foregroundStyle(.red)
                        }
                    }

                    Section {
                        Button {
                            Task { await approval.approve(code: code) }
                        } label: {
                            HStack {
                                Text("Sign In Apple TV")
                                if approval.phase == .working {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(code.filter { $0.isLetter || $0.isNumber }.count != 8 || approval.phase == .working)
                    }
                }
            }
            .navigationTitle("Sign In to Apple TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    TVSignInApprovalView(code: "ABCD-EFGH")
}
