//
//  WelcomeView.swift
//  Longhorn Artists Connect
//
//  Onboarding's first page, "Welcome to Nexus": Create Account or Sign In, plus
//  "Enthusiast" in the upper right for people who just want to follow along.
//  The "?" in the upper left explains LAC and Nexus. `OnboardingView` decides
//  where each choice leads.
//

import SwiftUI

struct WelcomeView: View {
    let onCreateAccount: () -> Void
    let onSignIn: () -> Void
    let onEnthusiast: () -> Void

    /// Drives the "?" sheet describing LAC and Nexus.
    @State private var showAbout = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: UIScreen.main.bounds.height * 0.15) // 2/3 of the way down is ~15% from top

            // Welcome header
            VStack(spacing: 8) {
                Text("Welcome to")
                    .font(.title)
                    .foregroundStyle(.secondary)

                SchoolAssetImage("NexusOrange")
                    .scaledToFit()
                    .frame(height: 72)

                Text("from Longhorn Artists Connect")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 16) {
                Button(action: onCreateAccount) {
                    Text("Create Account")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandOrange)
                        .cornerRadius(12)
                }

                Button(action: onSignIn) {
                    Text("Sign In")
                        .font(.headline)
                        .foregroundStyle(Color.brandOrange)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandOrange.opacity(0.15))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .toolbar {
            // What LAC and Nexus are.
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showAbout = true
                } label: {
                    Image(systemName: "questionmark")
                        .foregroundStyle(Color.brandOrange)
                }
                .accessibilityLabel("About LAC and Nexus")
            }

            // Enthusiasts follow along without a school account: they verify
            // any email, give a name, and can't post.
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onEnthusiast) {
                    Text("Enthusiast")
                        .font(.headline)
                        .foregroundStyle(Color.brandOrange)
                }
            }
        }
        .sheet(isPresented: $showAbout) {
            AboutNexusView()
        }
    }
}

// MARK: - About LAC & Nexus

/// The copy for the Welcome page's "?" sheet. Fill these in — they're empty
/// on purpose so no placeholder wording ships.
enum AboutNexusText {
    static let lac = ""
    static let nexus = ""
}

/// Opened from the "?" on the Welcome page: what Longhorn Artists Connect and
/// Nexus are.
struct AboutNexusView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section(title: "Longhorn Artists Connect", body: AboutNexusText.lac)
                    section(title: "Nexus", body: AboutNexusText.nexus)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            if !body.isEmpty {
                Text(body)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        WelcomeView(onCreateAccount: {}, onSignIn: {}, onEnthusiast: {})
    }
}
