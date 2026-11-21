//
//  TVSignInView.swift
//  Longhorn Artists Connect
//

import CoreImage.CIFilterBuiltins
import Observation
import SwiftUI

/// Shown until the TV is signed in: a QR code (and the code it carries) to approve
/// on an iPhone, or the email on the account.
struct TVSignInView: View {
    let account: TVAccount

    @State private var pairing = TVPairing()
    @State private var isUsingEmail = false

    var body: some View {
        VStack(spacing: 50) {
            Text("Sign In to Nexus")
                .font(.title2.bold())

            if case .failed(let reason) = account.state {
                Text(reason)
                    .foregroundStyle(.red)
            }

            HStack(alignment: .center, spacing: 90) {
                TVQRCode(text: pairing.approveURL)
                    .frame(width: 420, height: 420)

                VStack(alignment: .leading, spacing: 28) {
                    Text("Scan with your iPhone camera to sign in with the Nexus app.")
                        .font(.headline)
                    Text("Or go to **nexusbylac.com/tv** and enter")
                        .foregroundStyle(.secondary)
                    Text(pairing.displayCode)
                        .font(.system(size: 76, weight: .bold, design: .monospaced))
                        .redacted(reason: pairing.code == nil ? .placeholder : [])
                    if let message = pairing.message {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                    Button("Sign In with Email") {
                        isUsingEmail = true
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)
            }
        }
        .padding(80)
        .task {
            await pairing.run { token, viewer in account.signedIn(token: token, viewer: viewer) }
        }
        .fullScreenCover(isPresented: $isUsingEmail) {
            TVEmailSignInView { token, viewer in
                isUsingEmail = false
                account.signedIn(token: token, viewer: viewer)
            }
        }
    }
}

// MARK: - Pairing

/// Starts a pairing, polls until an iPhone or the website approves it, and starts
/// a fresh one whenever a code expires.
@Observable
final class TVPairing {
    private(set) var code: String?
    private(set) var approveURL = "https://nexusbylac.com/tv"
    private(set) var message: String?

    /// "ABCD-EFGH", or a placeholder of the same shape while loading.
    var displayCode: String {
        guard let code, code.count == 8 else { return "XXXX-XXXX" }
        return "\(code.prefix(4))-\(code.suffix(4))"
    }

    private struct Started: Decodable {
        let pairingID: String
        let code: String
        let approveURL: String
    }

    private struct Poll: Decodable {
        let status: String
        let token: String?
        let viewer: TVViewer?
    }

    /// Runs until signed in or the view goes away (task cancellation).
    func run(onSignIn: (String, TVViewer) -> Void) async {
        while !Task.isCancelled {
            do {
                let started: Started = try await TVService.post("v1/tv/pair/start")
                code = started.code
                approveURL = started.approveURL
                message = nil

                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(3))
                    let poll: Poll = try await TVService.post("v1/tv/pair/poll", ["pairingID": started.pairingID])
                    if poll.status == "approved", let token = poll.token, let viewer = poll.viewer {
                        onSignIn(token, viewer)
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch let failure as TVService.Failure where failure.status == 410 {
                // Expired: loop round for a new code.
                continue
            } catch {
                code = nil
                message = (error as? TVService.Failure)?.message ?? "Couldn't reach Nexus. Retrying…"
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }
}

/// A QR code for `text`, drawn with hard pixel edges.
struct TVQRCode: View {
    let text: String

    var body: some View {
        if let image = Self.image(for: text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(24)
                .background(.white, in: .rect(cornerRadius: 24))
        } else {
            RoundedRectangle(cornerRadius: 24).fill(.quaternary)
        }
    }

    private static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard
            let output = filter.outputImage,
            let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Email

/// The email on the account, then the 6-digit code sent to it.
struct TVEmailSignInView: View {
    let onSignIn: (String, TVViewer) -> Void

    @State private var email = ""
    @State private var code = ""
    @State private var pendingID: String?
    @State private var isWorking = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    private struct Requested: Decodable {
        let pendingID: String
    }

    private struct Confirmed: Decodable {
        let token: String
        let viewer: TVViewer
    }

    var body: some View {
        VStack(spacing: 40) {
            Text(pendingID == nil ? "Sign In with Email" : "Enter Your Code")
                .font(.title2.bold())

            Text(pendingID == nil
                 ? "Use the email on your Nexus account. We'll send it a code."
                 : "We sent a 6-digit code to \(email).")
                .foregroundStyle(.secondary)

            Group {
                if pendingID == nil {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                } else {
                    TextField("6-digit code", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                }
            }
            .frame(width: 800)

            if let message {
                Text(message)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 40) {
                Button("Cancel") { dismiss() }
                Button(pendingID == nil ? "Send Code" : "Sign In") {
                    Task { await submit() }
                }
                .disabled(isWorking || (pendingID == nil ? email.isEmpty : code.count != 6))
            }
        }
        .padding(80)
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        do {
            if let pendingID {
                let confirmed: Confirmed = try await TVService.post(
                    "v1/tv/email/confirm", ["pendingID": pendingID, "code": code]
                )
                onSignIn(confirmed.token, confirmed.viewer)
            } else {
                let requested: Requested = try await TVService.post("v1/tv/email/request", ["email": email])
                pendingID = requested.pendingID
                message = nil
            }
        } catch {
            message = (error as? TVService.Failure)?.message ?? "Couldn't reach Nexus. Try again."
        }
    }
}

#Preview("Sign In") {
    TVSignInView(account: TVAccount(state: .signedOut))
}

#Preview("Email") {
    TVEmailSignInView { _, _ in }
}
