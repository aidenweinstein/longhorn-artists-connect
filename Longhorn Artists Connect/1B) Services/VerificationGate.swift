//
//  VerificationGate.swift
//  Longhorn Artists Connect
//
//  Wraps a feature that requires a verified school email.
//
//  This is a *courtesy* gate, not a security control: CloudKit's public
//  database has no way to express "only verified users may write", so anyone
//  determined enough can write around the app. The nightly sweep in
//  verification-service/src/sweep.ts is what actually enforces the rule. This
//  exists so honest users get an explanation instead of a silent failure.
//

import SwiftUI

struct VerificationGate<Content: View>: View {
    /// Verb used in the explanation copy, e.g. "post your work".
    let action: String
    /// Skips the gate entirely. Set for account types that have no school
    /// email and therefore could never pass it — industry professionals would
    /// otherwise be locked out of messaging permanently.
    var bypass: Bool = false
    @ViewBuilder var content: () -> Content

    private var verification: StudentVerificationManager { .shared }
    @State private var showVerification = false

    var body: some View {
        Group {
            if bypass || !StudentVerificationManager.isConfigured || verification.status.isVerified {
                // No service configured in this build — don't wall anything off.
                content()
            } else {
                switch verification.status {
                case .unknown:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .unverified:
                    prompt
                case .verified:
                    content()
                }
            }
        }
        .task {
            await verification.refreshStatus()
        }
        .sheet(isPresented: $showVerification) {
            NavigationStack {
                SchoolEmailVerificationView {
                    showVerification = false
                }
            }
        }
    }

    private var prompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 52))
                .foregroundStyle(Color.brandOrange)

            Text("Verify your school email")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Confirm a school email address to \(action). It takes about a minute.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showVerification = true
            } label: {
                Text("Verify Now")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.brandOrange)
                    .cornerRadius(12)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
