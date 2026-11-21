//
//  NexusTVApp.swift
//  Longhorn Artists Connect
//
//  The Apple TV app: watch-only. Films and reels from every school, with no
//  posting, messaging or profiles. Only files in this folder (plus a few shared
//  data files) build for tvOS; everything else is filtered to iOS in the target.
//

import SwiftUI

@main
struct NexusTVApp: App {
    @State private var account = TVAccount()
    @State private var catalog = TVCatalog()

    var body: some Scene {
        WindowGroup {
            TVRootView(account: account, catalog: catalog)
                .task { await account.check() }
                .task { await account.watchForAccountChanges() }
        }
    }
}

/// Sign-in gate in front of the browse screen.
struct TVRootView: View {
    let account: TVAccount
    let catalog: TVCatalog

    var body: some View {
        switch account.state {
        case .checking:
            ProgressView()
        case .signedIn(let viewer):
            TVBrowseView(catalog: catalog, viewer: viewer)
        case .signedOut, .noProfile, .failed:
            TVSignInView(account: account)
        }
    }
}
