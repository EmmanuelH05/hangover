import AppKit
import SwiftUI

/// The app's motion vocabulary. Springs for anything that can be
/// interrupted (they keep their velocity when the target moves mid-flight),
/// curves only for fades. Every view picks a named animation from here
/// instead of writing literals, which keeps the island and Settings moving
/// with one feel.
enum Motion {
    // MARK: Island

    static let islandOpen = Animation.spring(response: 0.42, dampingFraction: 0.8)
    static let islandClose = Animation.smooth(duration: 0.3)
    static let islandPop = Animation.spring(response: 0.3, dampingFraction: 0.5)
    static let popDuration: TimeInterval = 0.3
    /// Height changes of the opened island (page switch, widget resize,
    /// a notification card measuring itself).
    static let islandResize = Animation.smooth(duration: 0.36, extraBounce: 0.04)
    /// How long the window waits after a shrink before it gives the space back,
    /// so the shape finishes animating inside the old frame.
    static let islandResizeSettle: TimeInterval = 0.5
    static let openedSurfaceUnmountDelay: TimeInterval = 0.36
    static let openedContentReveal = Animation.easeOut(duration: 0.2).delay(0.1)
    static let pageSwitch = Animation.smooth(duration: 0.34)
    static let hoverScale = Animation.spring(response: 0.38, dampingFraction: 0.8)
    /// Width and layout morphs of the closed pill. Replaces the old
    /// `timingCurve(0.4, 0, 0.2, 1, duration: 0.45)`.
    static let morph = Animation.smooth(duration: 0.45)

    // MARK: Content and controls

    static let contentSwap = Animation.snappy(duration: 0.3)
    static let selection = Animation.snappy(duration: 0.24)
    static let hover = Animation.easeOut(duration: 0.15)
    static let press = Animation.spring(response: 0.2, dampingFraction: 0.7)
    static let toggleEnable = Animation.easeInOut(duration: 0.2)
    static let reflow = Animation.spring(response: 0.3, dampingFraction: 0.85)
    static let lift = Animation.spring(response: 0.25, dampingFraction: 0.8)
    static let editToggle = Animation.smooth(duration: 0.25)
    /// The mirror's ring light fading in and out. A window fade in AppKit,
    /// which takes a duration and not an `Animation`.
    static let ringLightFade: TimeInterval = 0.25

    /// The bar of one "See it in action" step filling over the step's time.
    static func stepProgress(seconds: TimeInterval) -> Animation {
        .linear(duration: seconds)
    }

    /// What every animation becomes when Reduce Motion is on.
    static let reducedFallback = Animation.easeInOut(duration: 0.2)

    // MARK: Halo timings

    enum Halo {
        static let colorCrossfade: TimeInterval = 0.5
        static let fade: TimeInterval = 0.35
        static let flash: TimeInterval = 1.2
        /// How long a completion flash token stays live in the controller.
        static let flashHold: TimeInterval = 1.4
        static let approvalPeriod: TimeInterval = 2.0
        static let questionPeriod: TimeInterval = 2.6
        static let driftPeriod: TimeInterval = 8.0
    }

    // MARK: Transitions

    /// Content replacing content in place (slot swaps, page switch).
    static var slotSwap: AnyTransition { AnyTransition(.blurReplace) }

    // MARK: Reduce Motion

    static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedFallback : animation
    }

    static func transition(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }
}

/// `withAnimation` that follows Reduce Motion.
@MainActor
@discardableResult
func withMotion<Result>(_ animation: Animation, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.resolved(animation, reduceMotion: Motion.prefersReducedMotion), body)
}

/// Press feedback for plain buttons: a slight scale on the press spring, or
/// a dim when Reduce Motion is on.
struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration, pressedScale: pressedScale)
    }

    private struct PressableLabel: View {
        let configuration: ButtonStyleConfiguration
        let pressedScale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .scaleEffect(pressed && !reduceMotion ? pressedScale : 1)
                .opacity(pressed && reduceMotion ? 0.8 : 1)
                .animation(Motion.resolved(Motion.press, reduceMotion: reduceMotion), value: pressed)
        }
    }
}

private struct HoverHighlightModifier: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? opacity : 0))
            )
            .onHover { hovering in
                withAnimation(Motion.hover) { isHovering = hovering }
            }
    }
}

private struct MotionAnimationModifier<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(Motion.resolved(animation, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// A soft white wash behind the view while the pointer is over it.
    func hoverHighlight(cornerRadius: CGFloat, opacity: Double = 0.04) -> some View {
        modifier(HoverHighlightModifier(cornerRadius: cornerRadius, opacity: opacity))
    }

    /// `.animation(_:value:)` that follows Reduce Motion.
    func motionAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(MotionAnimationModifier(animation: animation, value: value))
    }
}
