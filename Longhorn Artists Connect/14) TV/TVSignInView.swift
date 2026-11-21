//
//  TVSignInView.swift
//  Longhorn Artists Connect
//

import SwiftUI

/// Shown until this Apple TV's iCloud account matches a Nexus account.
struct TVSignInView: View {
    let account: TVAccount

    var body: some View {
        VStack(spacing: 40) {
            Image(systemName: icon)
                .font(.system(size: 120))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title2.bold())

            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1100)

            Button("Check Again") {
                Task { await account.check() }
            }
        }
        .padding(80)
    }

    private var icon: String {
        switch account.state {
        case .failed: return "exclamationmark.icloud"
        default:      return "person.crop.circle.badge.questionmark"
        }
    }

    private var title: String {
        switch account.state {
        case .noProfile: return "No Nexus Account Found"
        case .failed:    return "Couldn't Reach Nexus"
        default:         return "Sign In to Watch"
        }
    }

    private var message: String {
        switch account.state {
        case .noProfile:
            return "This Apple TV's Apple Account doesn't have a Nexus account yet. Create one in the Nexus app on your iPhone, then check again."
        case .failed(let reason):
            return reason
        default:
            return "Sign in to this Apple TV with the same Apple Account you use for Nexus on your iPhone. Go to Settings → Users and Accounts → iCloud."
        }
    }
}

#Preview("Signed Out") {
    TVSignInView(account: TVAccount(state: .signedOut))
}

#Preview("No Profile") {
    TVSignInView(account: TVAccount(state: .noProfile))
}
