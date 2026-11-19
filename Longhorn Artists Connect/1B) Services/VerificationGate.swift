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
            if bypass
                || !StudentVerificationManager.isRequired
                || !StudentVerificationManager.isConfigured
                || verification.status.isVerified {
                // No service configured in this build (or a build pointed at
                // Development) — don't wall anything off.
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

// MARK: - Verification Reminder

/// Prompts unverified students to verify their school email every time they
/// open the app.
///
/// Accounts created before verification existed never saw the onboarding step,
/// so this is how they find out. It's a prompt, not a wall: "Not Now" dismisses
/// it until the app is next opened — a cold launch or a return from the
/// background — and it keeps coming back until they verify. The sheet pins the
/// address to the school's own domain (see `SchoolEmailVerificationView.domains`),
/// so a personal address can't be used. Website sign-in is by school email, and
/// the service only links that email to this app account once it's verified —
/// hence the copy.
struct VerificationReminder: ViewModifier {
    /// False for guests and industry professionals, who have no school email.
    let isEligible: Bool

    @Environment(\.scenePhase) private var scenePhase

    private var verification: StudentVerificationManager { .shared }
    @State private var showReminder = false
    @State private var showVerification = false

    func body(content: Content) -> some View {
        content
            // Keyed on the scene phase so it re-runs on every return to the
            // foreground, not just at launch.
            .task(id: scenePhase) {
                guard scenePhase == .active,
                      isEligible,
                      StudentVerificationManager.isRequired,
                      StudentVerificationManager.isConfigured,
                      // Switching to Mail for the code and back shouldn't stack
                      // a second prompt on top of the one already showing.
                      !showReminder, !showVerification else { return }

                await verification.refreshStatus()
                guard verification.status == .unverified else { return }

                showReminder = true
            }
            .alert("Verify your school email", isPresented: $showReminder) {
                Button("Verify Now") { showVerification = true }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Confirm the email address your school issued you to post your work and sign in to the Nexus website. It takes about a minute.")
            }
            .sheet(isPresented: $showVerification) {
                NavigationStack {
                    SchoolEmailVerificationView {
                        showVerification = false
                    }
                }
            }
    }
}

extension View {
    /// See `VerificationReminder`.
    func verificationReminder(isEligible: Bool) -> some View {
        modifier(VerificationReminder(isEligible: isEligible))
    }
}
