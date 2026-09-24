import SwiftUI

struct LaunchScreenView: View {
    @State private var isActive = false
    @State private var launchScreenOpacity: Double = 1.0  // ⚙️ #1: Initial launch screen opacity (1.0 = fully visible)
    // Content stays fully opaque and is *revealed* as the orange overlay fades out.
    // (Fading the content in via opacity left the system floating tab-bar capsule —
    // which lives in a separate layer that ignores ancestor opacity — invisible until
    // the fade fully finished, so it popped in late.)
    @State private var contentOpacity: Double = 1.0       // ⚙️ #2: Content opacity (kept at 1 so everything reveals together)
    // The zoom lives on the launch overlay (scales up as it fades) instead of on the
    // main content — scaling the content pulls its edge-to-edge top bar / tab bar
    // inward and exposes black at the top and bottom of the screen mid-transition.
    @State private var launchScreenScale: CGFloat = 1.0   // ⚙️ #3: Launch overlay scale (animates outward)
    @State private var didBeginFade = false       // Guards the fade so it only runs once
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    @ObservedObject private var store = SubmissionStore_3_2.shared  // NEW: Observe store
    
    var body: some View {
        ZStack {
            // Main content with fade-in and scale
            if isActive {
                if hasCompletedOnboarding {
                    ContentView()
                        .tint(Color.brandOrange)  // ⚙️ #4: Main content tint color
                        .opacity(contentOpacity)  // ⚙️ #5: Content opacity (animated)
                } else {
                    OnboardingView()
                        .tint(Color.brandOrange)  // ⚙️ #7: Onboarding tint color
                        .opacity(contentOpacity)  // ⚙️ #8: Onboarding opacity (animated)
                }
            }
            
            // Launch screen overlay - everything in one ZStack to fade together
            ZStack {
                Color.brandOrange  // ⚙️ #10: Launch screen background color
                    .ignoresSafeArea()
                
                VStack {
                    Spacer()  // ⚙️ #11: Top spacing (pushes icon down)
                    
                    // Graph icon centered
                    Image("Graph Icon")  // Using Graph Icon asset
                        .resizable()
                        .scaledToFit()
                        .frame(width: 250, height: 250)  // ⚙️ #12: Icon width, ⚙️ #13: Icon height
                        .padding(.top, 20)  // ⚙️ #14: Icon top padding (vertical adjustment)
                    
                    Spacer()  // ⚙️ #15: Middle spacing #1 (pushes icon up)
                    Spacer()  // ⚙️ #16: Middle spacing #2 (extra push - creates vertical center offset)
                }
                
                // "from" and "Longhorn Artists Connect" at the bottom
                VStack {
                    Spacer()  // ⚙️ #17: Push text to bottom
                    
                    VStack(spacing: 4) {  // ⚙️ #18: Spacing between "from" and "Longhorn Artists Connect"
                        Text("from")
                            .font(.system(size: 16, weight: .regular))  // ⚙️ #19: "from" text size
                            .foregroundStyle(.white.opacity(0.9))  // ⚙️ #20: "from" text opacity
                        
                        Text("Longhorn Artists Connect")
                            .font(.system(size: 20, weight: .semibold))  // ⚙️ #21: Brand text size
                            .foregroundStyle(.white.opacity(0.9))  // ⚙️ #22: Brand text opacity
                    }
                    .padding(.bottom, 60)  // ⚙️ #23: Bottom text padding from screen edge
                }
            }
            .compositingGroup()  // Fade the overlay as a single layer so the icon and orange disappear in lockstep
            .scaleEffect(launchScreenScale)  // ⚙️ Zoom the overlay outward as it fades
            .opacity(launchScreenOpacity)  // ⚙️ #24: Launch screen overlay opacity (animated to 0)
            .ignoresSafeArea()  // Cover the full screen so the zoom never reveals edges
            .allowsHitTesting(launchScreenOpacity > 0)
        }
        .onAppear {
            // Activate content immediately but keep it invisible
            isActive = true

            // Note: the launch CloudKit sync is driven by SubmissionStore's own init
            // (load local cache → sync → subscribe), which observing `store` above kicks
            // off. Firing a second sync here raced that cache load and doubled the
            // launch-time network work, so it's intentionally not done here.

            if hasCompletedOnboarding {
                // Fast path: this device already knows the user's profile locally.
                DispatchQueue.main.asyncAfter(deadline: .now() + AnimationManager.launchScreenDisplayDuration) {
                    beginFade()
                }
            } else {
                // No local profile — but this may be a returning user on a fresh
                // install / new device. Their account is tied to their iCloud ID, so
                // check CloudKit for an existing UserProfile before showing onboarding.
                Task {
                    await restoreProfileFromCloudKitIfNeeded()
                    await MainActor.run { beginFade() }
                }
                // Safety net so a slow/offline CloudKit never holds the launch screen.
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                    beginFade()
                }
            }
        }
    }

    /// Runs the launch → content crossfade exactly once.
    private func beginFade() {
        guard !didBeginFade else { return }
        didBeginFade = true
        withAnimation(AnimationManager.launchTransition) {
            launchScreenOpacity = 0.0   // fade OUT the launch overlay, revealing the content beneath
            launchScreenScale = 1.08     // overlay zooms out slightly as it fades
        }
    }

    /// Pulls the signed-in user's profile from CloudKit (keyed by their iCloud
    /// record ID). If one exists, `loadFromCloudKit()` populates local storage and
    /// flips `hasCompletedOnboarding`, so a returning user skips onboarding and sees
    /// their existing profile instead of being forced to make a new account.
    private func restoreProfileFromCloudKitIfNeeded() async {
        // Resolve the CloudKit account first so the user's record ID is available.
        await CloudKitManager.shared.checkAvailability()
        guard CloudKitManager.shared.isAvailable else { return }

        await UserProfileModel().loadFromCloudKit()
    }
}

#Preview {
    LaunchScreenView()
}
