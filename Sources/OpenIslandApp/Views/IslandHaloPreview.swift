import SwiftUI

extension View {
    /// The status glow behind a pill in Settings and in the welcome tour.
    ///
    /// In a window it is the same Core Animation layer the island uses
    /// (`islandHalo`), which the system animates without waking the app. A
    /// SwiftUI copy that breathed with `phaseAnimator` redrew the whole
    /// Settings window on every frame for as long as it was on screen.
    ///
    /// A picture drawn offscreen shows no layers, and gets a still SwiftUI
    /// copy of the glow (`nookDrawsStill`).
    ///
    /// The blur reaches past the view's bounds, so the host needs room around it.
    func islandHaloPreview(_ state: IslandHaloState, cornerRadius: CGFloat) -> some View {
        modifier(IslandHaloPreviewModifier(state: state, cornerRadius: cornerRadius))
    }
}

private struct IslandHaloPreviewModifier: ViewModifier {
    let state: IslandHaloState
    let cornerRadius: CGFloat
    @Environment(\.nookDrawsStill) private var drawsStill

    @ViewBuilder
    func body(content: Content) -> some View {
        if drawsStill {
            content.background(
                IslandHaloStillGlow(state: state, cornerRadius: cornerRadius)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            )
        } else {
            content.islandHalo(state, cornerRadius: cornerRadius)
        }
    }
}

/// The glow as one still frame: a blurred rounded rect at the opacity the
/// state rests at. A flash is drawn at its peak.
struct IslandHaloStillGlow: View {
    let state: IslandHaloState
    let cornerRadius: CGFloat

    /// Same inset as the Core Animation halo.
    private static let pillInset = IslandHaloLayerView.pillInset

    /// The one opacity a still picture shows for a state.
    static func opacity(for state: IslandHaloState) -> Double {
        if case let .flash(_, peak, _) = state.motion { return peak }
        return state.restOpacity
    }

    var body: some View {
        if state.isVisible {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(state.color.color)
                .padding(Self.pillInset)
                .blur(radius: state.radius)
                .offset(y: state.drop)
                .opacity(Self.opacity(for: state))
        }
    }
}
