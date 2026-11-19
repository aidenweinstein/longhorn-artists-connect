import SwiftUI
import UIKit

// MARK: - Tab Swipe Gesture
//
// A horizontal swipe anywhere on a tab's content that moves to the neighbouring tab,
// the way you'd swipe between pages. Implemented as a UIKit pan recognizer (bridged via
// `UIGestureRecognizerRepresentable`) rather than a SwiftUI `DragGesture` so it can
// defer to every other pan in the hierarchy: vertical feeds keep scrolling, horizontal
// carousels and swipe actions keep swiping, the navigation back-swipe keeps working,
// and only a sideways swipe nobody else claims switches tabs.

struct TabSwipeGesture: UIGestureRecognizerRepresentable {

    enum Direction {
        /// Finger moved right-to-left: go to the next tab.
        case forward
        /// Finger moved left-to-right: go to the previous tab.
        case backward
    }

    /// Called once per completed swipe with the direction the user is paging.
    let onSwipe: (Direction) -> Void

    /// Minimum sideways travel for a slow drag to count as a page swipe.
    private static let travelThreshold: CGFloat = 60
    /// A quick flick counts even if it didn't travel far.
    private static let flickVelocity: CGFloat = 500
    private static let flickMinimumTravel: CGFloat = 20

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard recognizer.state == .ended, let view = recognizer.view else { return }
        let travel = recognizer.translation(in: view).x
        let velocity = recognizer.velocity(in: view).x

        let dragged = abs(travel) >= Self.travelThreshold
        let flicked = abs(velocity) >= Self.flickVelocity && abs(travel) >= Self.flickMinimumTravel
        guard dragged || flicked else { return }

        // Ignore a drag that reversed course: trust where the finger ended up.
        onSwipe(travel < 0 ? .forward : .backward)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        /// Width of the leading-edge strip reserved for the navigation back-swipe.
        private let backSwipeEdge: CGFloat = 24

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return false }

            // Only clearly sideways movement pages; anything diagonal or vertical is
            // left alone so feeds scroll untouched.
            let translation = pan.translation(in: view)
            guard abs(translation.x) > abs(translation.y) * 1.5 else { return false }

            // Swipes that start at the leading edge belong to the navigation stack's
            // interactive pop, even when it ends up with nothing to pop.
            let startX = pan.location(in: view).x - translation.x
            return startX > backSwipeEdge
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Yield to every other pan under the finger: scroll views (which fail on a
            // sideways drag they can't scroll), horizontal carousels, List swipe actions
            // and the navigation back-swipe. We only page when none of them want it.
            otherGestureRecognizer is UIPanGestureRecognizer
        }
    }
}
