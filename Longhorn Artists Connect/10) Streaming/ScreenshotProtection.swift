import SwiftUI
import UIKit

/// Wraps arbitrary SwiftUI content in the same private "secure text" layer that iOS
/// uses for password fields. Content rendered inside that layer is captured as solid
/// black in screenshots, screen recordings, and AirPlay / screen mirroring — while it
/// displays and plays back completely normally on the device itself.
///
/// This is the technique consumer apps use to block screen capture short of full
/// FairPlay DRM (the only officially supported, un-capturable path). It relies on an
/// undocumented UIKit implementation detail: `UITextField`'s secure-entry canvas is the
/// view whose backing layer the render server omits from any screen capture. Because
/// the detail is undocumented, this wrapper degrades gracefully — if Apple ever changes
/// that view hierarchy, the content simply renders normally (unprotected) rather than
/// breaking or crashing.
///
/// Only the video pixels are wrapped; surrounding controls stay in the normal layer so
/// they remain visible in any capture (and so their gestures behave as usual).
struct ScreenshotProtectedView<Content: View>: UIViewRepresentable {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(hostingController: UIHostingController(rootView: content))
    }

    func makeUIView(context: Context) -> UIView {
        let host = context.coordinator.hostingController
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        // Don't let the hosting controller inset the content for safe areas — otherwise
        // the wrapped video (e.g. the rotated fullscreen player) gets shrunk inside its
        // frame and `.resizeAspect` letterboxes it.
        host.safeAreaRegions = []

        let container = UIView()
        container.backgroundColor = .clear

        // The secure canvas: a secure-entry `UITextField`'s first subview is the view
        // whose layer the render server excludes from screen capture. We retain the
        // field (so the secure flag stays live), re-parent that canvas as our container,
        // and drop the field's own (empty) text machinery from it.
        let field = UITextField()
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        context.coordinator.field = field

        let secureCanvas = field.subviews.first
        let host_parent: UIView = secureCanvas ?? container   // fall back to unprotected

        if let secureCanvas {
            secureCanvas.subviews.forEach { $0.removeFromSuperview() }
            secureCanvas.isUserInteractionEnabled = true
            secureCanvas.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(secureCanvas)
            NSLayoutConstraint.activate([
                secureCanvas.topAnchor.constraint(equalTo: container.topAnchor),
                secureCanvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                secureCanvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                secureCanvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }

        host_parent.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: host_parent.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: host_parent.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: host_parent.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: host_parent.trailingAnchor),
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.hostingController.rootView = content

        // Register the hosting controller in the VC hierarchy once its container is in a
        // window, so hosted content (e.g. native player controls) gets a correct
        // lifecycle and layout.
        let host = context.coordinator.hostingController
        if host.parent == nil, let parentVC = uiView.scp_parentViewController {
            parentVC.addChild(host)
            host.didMove(toParent: parentVC)
        }
    }

    final class Coordinator {
        let hostingController: UIHostingController<Content>
        /// Retained so the secure canvas keeps its capture-exclusion flag alive.
        var field: UITextField?

        init(hostingController: UIHostingController<Content>) {
            self.hostingController = hostingController
        }
    }
}

extension View {
    /// Renders this view inside iOS's secure-entry layer so it is captured as black in
    /// screenshots, screen recordings, and mirroring. See `ScreenshotProtectedView`.
    func screenshotProtected() -> some View {
        ScreenshotProtectedView { self }
    }
}

fileprivate extension UIView {
    /// Walks the responder chain to the nearest owning view controller, if any.
    var scp_parentViewController: UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let vc = current as? UIViewController { return vc }
            responder = current.next
        }
        return nil
    }
}
