//
//  AnimationManager-10)Animations.swift
//  Longhorn Artists Connect
//
//  Central animation and transition management
//  All customizable animation properties marked with ⚙️
//

import SwiftUI

// MARK: - Animation Manager

@MainActor
class AnimationManager {
    static let shared = AnimationManager()
    
    private init() {}
    
    // MARK: - Duration Constants
    
    /// ⚙️ Page transition duration (seconds)
    static let pageTransitionDuration: Double = 0.3
    
    /// ⚙️ Quick animation duration (seconds)
    static let quickDuration: Double = 0.15
    
    /// ⚙️ Standard animation duration (seconds)
    static let standardDuration: Double = 0.25
    
    /// ⚙️ Slow animation duration (seconds)
    static let slowDuration: Double = 0.4
    
    // MARK: - Launch Screen Settings
    
    /// ⚙️ Launch screen display duration before transition (seconds)
    static let launchScreenDisplayDuration: Double = 1.0
    
    /// ⚙️ Launch screen transition animation
    static var launchTransition: Animation {
        .easeInOut(duration: 0.7)  // Consistent fade speed for all elements
    }
    
    /// ⚙️ Launch content initial scale (for zoom-in effect)
    static let launchContentScale: CGFloat = 0.95
    
    // MARK: - Scale Constants
    
    /// ⚙️ Button press scale (1.0 = normal size)
    static let buttonPressScale: CGFloat = 0.95
    
    /// ⚙️ Button release scale
    static let buttonReleaseScale: CGFloat = 1.0
    
    /// ⚙️ Pop-in scale (from)
    static let popInFromScale: CGFloat = 0.8
    
    /// ⚙️ Pop-in scale (to)
    static let popInToScale: CGFloat = 1.0
    
    // MARK: - Spring Parameters
    
    /// ⚙️ Spring response (lower = faster)
    static let springResponse: Double = 0.3
    
    /// ⚙️ Spring damping (0-1, lower = more bounce)
    static let springDamping: Double = 0.7
    
    /// ⚙️ Bouncy spring response
    static let bouncySpringResponse: Double = 0.4
    
    /// ⚙️ Bouncy spring damping
    static let bouncySpringDamping: Double = 0.5
    
    // MARK: - Opacity Constants
    
    /// ⚙️ Fade in from opacity
    static let fadeInFrom: Double = 0.0
    
    /// ⚙️ Fade in to opacity
    static let fadeInTo: Double = 1.0
    
    /// ⚙️ Fade out from opacity
    static let fadeOutFrom: Double = 1.0
    
    /// ⚙️ Fade out to opacity
    static let fadeOutTo: Double = 0.0
    
    // MARK: - Standard Animations
    
    /// ⚙️ Standard spring animation
    static var spring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }
    
    /// ⚙️ Bouncy spring animation
    static var bouncySpring: Animation {
        .spring(response: bouncySpringResponse, dampingFraction: bouncySpringDamping)
    }
    
    /// ⚙️ Smooth ease-in-out animation
    static var smooth: Animation {
        .easeInOut(duration: standardDuration)
    }
    
    /// ⚙️ Quick ease-in-out animation
    static var quick: Animation {
        .easeInOut(duration: quickDuration)
    }
    
    /// ⚙️ Slow ease-in-out animation
    static var slow: Animation {
        .easeInOut(duration: slowDuration)
    }
    
    /// ⚙️ Linear animation
    static var linear: Animation {
        .linear(duration: standardDuration)
    }
    
    // MARK: - Page Transitions
    
    /// Get transition for page navigation
    /// - Parameters:
    ///   - from: Current page index
    ///   - to: Target page index
    /// - Returns: Appropriate transition based on direction
    static func pageTransition(from: Int, to: Int) -> AnyTransition {
        let direction: Edge = to > from ? .trailing : .leading
        return AnyTransition.asymmetric(
            insertion: .move(edge: direction),
            removal: .move(edge: direction == .trailing ? .leading : .trailing)
        )
    }
    
    /// Standard slide transition
    /// - Parameter edge: Edge to slide from
    /// - Returns: Slide transition
    static func slideTransition(from edge: Edge) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: edge),
            removal: .move(edge: edge)
        )
    }
    
    /// Scale and fade transition
    static var scaleAndFade: AnyTransition {
        .scale(scale: popInFromScale).combined(with: .opacity)
    }
    
    /// Fade only transition
    static var fade: AnyTransition {
        .opacity
    }
    
    // MARK: - Sheet Presentations
    
    /// ⚙️ Sheet transition duration
    static let sheetTransitionDuration: Double = 0.35
    
    /// ⚙️ Sheet animation
    static var sheetAnimation: Animation {
        .easeInOut(duration: sheetTransitionDuration)
    }
    
    // MARK: - Loading Animations
    
    /// ⚙️ Loading indicator scale
    static let loadingIndicatorScale: CGFloat = 1.5
    
    /// ⚙️ Shimmer animation duration
    static let shimmerDuration: Double = 1.5
    
    /// ⚙️ Pulse animation duration
    static let pulseDuration: Double = 1.0
    
    /// ⚙️ Pulse scale range
    static let pulseScaleRange: ClosedRange<CGFloat> = 0.95...1.05
    
    // MARK: - List Animations
    
    /// ⚙️ List item insertion animation
    static var listInsertion: Animation {
        .spring(response: 0.4, dampingFraction: 0.8)
    }
    
    /// ⚙️ List item removal animation
    static var listRemoval: Animation {
        .easeOut(duration: 0.2)
    }
    
    // MARK: - Button Animations
    
    /// ⚙️ Button tap scale animation
    static var buttonTap: Animation {
        .spring(response: 0.2, dampingFraction: 0.6)
    }
    
    /// ⚙️ Button bounce animation
    static var buttonBounce: Animation {
        .spring(response: 0.3, dampingFraction: 0.5)
    }
}

// MARK: - View Extensions

extension View {
    /// Add animated button press effect
    /// - Parameter isPressed: Binding to pressed state
    /// - Returns: View with press animation
    func animatedButtonPress(isPressed: Binding<Bool>) -> some View {
        self.scaleEffect(isPressed.wrappedValue ? AnimationManager.buttonPressScale : AnimationManager.buttonReleaseScale)
            .animation(AnimationManager.buttonTap, value: isPressed.wrappedValue)
    }
    
    /// Add page transition animation
    /// - Parameters:
    ///   - isPresented: Whether view is presented
    ///   - edge: Edge to transition from
    /// - Returns: View with transition
    func pageTransition(isPresented: Bool, from edge: Edge = .trailing) -> some View {
        self.transition(AnimationManager.slideTransition(from: edge))
            .animation(AnimationManager.smooth, value: isPresented)
    }
    
    /// Add scale-in animation
    /// - Parameter isPresented: Whether view is presented
    /// - Returns: View with scale animation
    func scaleIn(isPresented: Bool) -> some View {
        self.scaleEffect(isPresented ? 1.0 : AnimationManager.popInFromScale)
            .opacity(isPresented ? 1.0 : 0.0)
            .animation(AnimationManager.spring, value: isPresented)
    }
    
    /// Add fade animation
    /// - Parameter isPresented: Whether view is presented
    /// - Returns: View with fade animation
    func fadeIn(isPresented: Bool) -> some View {
        self.opacity(isPresented ? 1.0 : 0.0)
            .animation(AnimationManager.smooth, value: isPresented)
    }
    
    /// Add shimmer loading effect
    /// - Parameter isLoading: Whether loading state is active
    /// - Returns: View with shimmer effect
    func shimmer(isLoading: Bool) -> some View {
        self.modifier(ShimmerModifier(isLoading: isLoading))
    }
    
    /// Add pulse animation
    /// - Parameter isPulsing: Whether pulse is active
    /// - Returns: View with pulse animation
    func pulse(isPulsing: Bool) -> some View {
        self.modifier(PulseModifier(isPulsing: isPulsing))
    }
}

// MARK: - Shimmer Modifier

struct ShimmerModifier: ViewModifier {
    let isLoading: Bool
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    if isLoading {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.clear,
                                Color.white.opacity(0.3), // ⚙️ Shimmer highlight opacity
                                Color.clear
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 2) // ⚙️ Shimmer width multiplier
                        .offset(x: phase * geometry.size.width - geometry.size.width)
                        .onAppear {
                            withAnimation(
                                .linear(duration: AnimationManager.shimmerDuration)
                                .repeatForever(autoreverses: false)
                            ) {
                                phase = 1
                            }
                        }
                    }
                }
            )
            .mask(content)
    }
}

// MARK: - Pulse Modifier

struct PulseModifier: ViewModifier {
    let isPulsing: Bool
    @State private var scale: CGFloat = 1.0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? scale : 1.0)
            .onAppear {
                if isPulsing {
                    withAnimation(
                        .easeInOut(duration: AnimationManager.pulseDuration)
                        .repeatForever(autoreverses: true)
                    ) {
                        scale = AnimationManager.pulseScaleRange.upperBound
                    }
                }
            }
    }
}

// MARK: - Button Press Modifier

struct ButtonPressModifier: ViewModifier {
    @State private var isPressed = false
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? AnimationManager.buttonPressScale : 1.0)
            .animation(AnimationManager.buttonTap, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        action()
                    }
            )
    }
}

extension View {
    /// Add button press animation with action
    /// - Parameter action: Action to perform on tap
    /// - Returns: View with press animation
    func animatedButton(action: @escaping () -> Void) -> some View {
        self.modifier(ButtonPressModifier(action: action))
    }
}

// MARK: - List Animation Helpers

extension View {
    /// Add list row animation
    /// - Parameter id: Unique identifier for the row
    /// - Returns: View with animation
    func listRowAnimation<ID: Hashable>(id: ID) -> some View {
        self.transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(AnimationManager.listInsertion, value: id)
    }
}

// MARK: - Easing Curves

extension Animation {
    /// ⚙️ Custom easing curve - ease in
    static var customEaseIn: Animation {
        .timingCurve(0.42, 0, 1, 1, duration: 0.3)
    }
    
    /// ⚙️ Custom easing curve - ease out
    static var customEaseOut: Animation {
        .timingCurve(0, 0, 0.58, 1, duration: 0.3)
    }
    
    /// ⚙️ Custom easing curve - ease in-out
    static var customEaseInOut: Animation {
        .timingCurve(0.42, 0, 0.58, 1, duration: 0.3)
    }
}

// MARK: - Haptic Feedback

extension AnimationManager {
    /// Trigger haptic feedback
    /// - Parameter style: Feedback style
    static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    /// Trigger selection haptic
    static func selectionHaptic() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
    
    /// Trigger notification haptic
    /// - Parameter type: Notification type
    static func notificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}

// MARK: - Preview Helpers

#if DEBUG
struct AnimationPreview: View {
    @State private var isPresented = false
    @State private var isPressed = false
    @State private var isLoading = false
    @State private var isPulsing = false
    
    var body: some View {
        VStack(spacing: 20) { // ⚙️ Preview spacing
            Button("Toggle Presentation") {
                withAnimation(AnimationManager.spring) {
                    isPresented.toggle()
                }
            }
            .animatedButton(action: { isPresented.toggle() })
            
            if isPresented {
                Rectangle()
                    .fill(Color.blue) // ⚙️ Preview color
                    .frame(width: 100, height: 100) // ⚙️ Preview size
                    .scaleIn(isPresented: isPresented)
            }
            
            Button("Toggle Loading") {
                isLoading.toggle()
            }
            .shimmer(isLoading: isLoading)
            
            Button("Toggle Pulse") {
                isPulsing.toggle()
            }
            .pulse(isPulsing: isPulsing)
        }
        .padding() // ⚙️ Preview padding
    }
}

#Preview {
    AnimationPreview()
}
#endif
