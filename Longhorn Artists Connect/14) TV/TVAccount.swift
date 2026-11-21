//
//  TVAccount.swift
//  Longhorn Artists Connect
//
//  Who is watching. The TV signs in to a Nexus account by QR code (approved in
//  the iPhone app or on the website) or by the email on the account, and gets a
//  session token from the verification service. Requiring an account keeps
//  anonymous devices from adding watch time; verification and account type
//  don't change anything on TV.
//

import Observation

/// The signed-in Nexus member.
struct TVViewer: Equatable, Decodable {
    /// The account's user record name, as `NewPostView` records it.
    let userRecordName: String
    /// "First Last", for skipping the viewer's own posts.
    let name: String
}

@Observable
final class TVAccount {

    enum State: Equatable {
        case checking
        case signedOut
        case signedIn(TVViewer)
        /// Couldn't reach the service to check a saved sign-in.
        case failed(String)
    }

    private(set) var state: State

    init(state: State = .checking) {
        self.state = state
    }

    private struct Me: Decodable {
        let viewer: TVViewer
    }

    /// Checks the saved token, if any, is still signed in.
    func check() async {
        guard let token = TVSessionStore.token else {
            state = .signedOut
            return
        }
        if case .signedIn = state {} else { state = .checking }
        do {
            let me: Me = try await TVService.post("v1/tv/me", ["token": token])
            state = .signedIn(me.viewer)
        } catch let failure as TVService.Failure where failure.status == 401 {
            TVSessionStore.clear()
            state = .signedOut
        } catch {
            state = .failed("Couldn't reach Nexus. Check your internet connection.")
        }
    }

    func signedIn(token: String, viewer: TVViewer) {
        TVSessionStore.save(token)
        state = .signedIn(viewer)
    }

    func signOut() async {
        if let token = TVSessionStore.token {
            let _: SignedOut? = try? await TVService.post("v1/tv/signout", ["token": token])
        }
        TVSessionStore.clear()
        state = .signedOut
    }

    private struct SignedOut: Decodable {
        let signedOut: Bool
    }
}
