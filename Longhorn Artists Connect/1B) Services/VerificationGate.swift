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
                // Development build, or no service configured in this build —
                // don't wall anything off.
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

/// Periodically nudges unverified students to verify their school email.
///
/// Accounts created before verification existed never saw the onboarding step,
/// and anyone can skip it there, so this is how they find out. It's a reminder,
/// not a wall: "Not Now" snoozes it for `snoozeInterval`. Website sign-in is by
/// school email, and the service only links that email to this app account once
/// it's verified — hence the copy.
struct VerificationReminder: ViewModifier {
    /// False for guests and industry professionals, who have no school email.
    let isEligible: Bool

    private static let lastShownKey = "verificationReminderLastShown"
    private static let snoozeInterval: TimeInterval = 3 * 24 * 60 * 60

    private var verification: StudentVerificationManager { .shared }
    @State private var showReminder = false
    @State private var showVerification = false

    /// Starts the snooze window.
    static func snooze() {
        UserDefaults.standard.set(Date(), forKey: lastShownKey)
    }

    func body(content: Content) -> some View {
        content
            .task {
                guard isEligible,
                      StudentVerificationManager.isRequired,
                      StudentVerificationManager.isConfigured else { return }

                if let last = UserDefaults.standard.object(forKey: Self.lastShownKey) as? Date,
                   Date().timeIntervalSince(last) < Self.snoozeInterval {
                    return
                }

                await verification.refreshStatus()
                guard verification.status == .unverified else { return }

                Self.snooze()
                showReminder = true
            }
            .alert("Verify your school email", isPresented: $showReminder) {
                Button("Verify Now") { showVerification = true }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Verifying lets you sign in to the Nexus website and keep it in sync with your account here. You'll also need it to post your work.")
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
