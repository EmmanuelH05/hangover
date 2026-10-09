import SwiftUI

extension View {
    /// The pure SwiftUI twin of `islandHalo`, for Settings (`ImageRenderer`
    /// cannot draw AppKit views). The glow is a blurred rounded rect behind
    /// the view, driven by `phaseAnimator` and `keyframeAnimator`.
    ///
    /// The blur reaches past the view's bounds, so the host needs room around it.
    func islandHaloPreview(_ state: IslandHaloState, cornerRadius: CGFloat) -> some View {
        modifier(IslandHaloPreviewModifier(state: state, cornerRadius: cornerRadius))
    }
}

private struct IslandHaloPreviewModifier: ViewModifier {
    let state: IslandHaloState
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.background(
            IslandHaloPreviewGlow(state: state, cornerRadius: cornerRadius, reduceMotion: reduceMotion)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }
}

private struct IslandHaloPreviewGlow: View {
    let state: IslandHaloState
    let cornerRadius: CGFloat
    let reduceMotion: Bool

    /// Same inset as the Core Animation halo.
    private static let pillInset = IslandHaloLayerView.pillInset

    var body: some View {
        ZStack {
            if state.isVisible {
                glow
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: Motion.Halo.fade), value: state.isVisible)
    }

    private var glow: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(state.color.color)
            .padding(Self.pillInset)
            .blur(radius: state.radius)
            .offset(y: state.drop)
            .modifier(IslandHaloOpacityDriver(motion: state.motion, restOpacity: state.restOpacity, reduceMotion: reduceMotion))
            .animation(.easeInOut(duration: Motion.Halo.colorCrossfade), value: state.color)
            .animation(.easeInOut(duration: Motion.Halo.fade), value: state.radius)
            .animation(.easeInOut(duration: Motion.Halo.fade), value: state.drop)
    }
}

/// Moves the glow's opacity the way the layer halo does. Each motion is its
/// own branch, so switching motion starts the new one fresh.
private struct IslandHaloOpacityDriver: ViewModifier {
    let motion: IslandHaloMotion
    let restOpacity: Double
    let reduceMotion: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        switch motion {
        case .none, .steady:
            content.opacity(restOpacity)
        case let .breathing(period, low, high):
            if reduceMotion {
                content.opacity(restOpacity)
            } else {
                content.phaseAnimator([low, high]) { view, opacity in
                    view.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: period / 2)
                }
            }
        case let .drift(period):
            if reduceMotion {
                content.opacity(restOpacity)
            } else {
                content.phaseAnimator([restOpacity * 0.75, min(1, restOpacity * 1.15)]) { view, opacity in
                    view.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: period)
                }
            }
        case let .flash(token, peak, duration):
            content.modifier(
                IslandHaloFlash(token: token, peak: peak, rest: restOpacity, duration: duration, reduceMotion: reduceMotion)
            )
        }
    }
}

/// One rise, settle and fall per token. It also plays when it first appears,
/// which `keyframeAnimator` alone does not do. With Reduce Motion it is one
/// fade instead: start at the peak and ease out to rest.
private struct IslandHaloFlash: ViewModifier {
    let token: UInt64
    let peak: Double
    let rest: Double
    let duration: TimeInterval
    let reduceMotion: Bool

    @State private var trigger: UInt64?

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: rest, trigger: trigger) { view, opacity in
                view.opacity(opacity)
            } keyframes: { _ in
                KeyframeTrack {
                    if reduceMotion {
                        MoveKeyframe(peak)
                        // A start velocity of twice the average slope, ending
                        // flat, eases the fade out.
                        CubicKeyframe(
                            rest,
                            duration: duration,
                            startVelocity: duration > 0 ? 2 * (rest - peak) / duration : 0,
                            endVelocity: 0
                        )
                    } else {
                        CubicKeyframe(peak, duration: duration * 0.18)
                        CubicKeyframe(peak * 0.55, duration: duration * 0.32)
                        CubicKeyframe(rest, duration: duration * 0.5)
                    }
                }
            }
            .onAppear { trigger = token }
            .onChange(of: token) { _, newToken in trigger = newToken }
    }
}
