import SwiftUI

/// The opened island as a small picture for a choice card: the black shape
/// hanging from the top edge of its box, drawn with the island's own shape
/// and the look's own numbers at a fraction of their size (D35). Plain
/// SwiftUI, which lets Settings, the welcome tour and a snapshot share it.
struct OpenedLookArt: View {
    let look: IslandOpenedLook
    let profile: IslandAppearanceDisplayProfile
    /// Faint bars that stand for a page's content.
    var showsContent = true

    var body: some View {
        GeometryReader { proxy in
            let metrics = IslandOpenedMetrics.resolve(look: look, profile: profile)
            let scale = OpenedLookArtLayout.scale(boxWidth: proxy.size.width, profile: profile)
            let size = OpenedLookArtLayout.shapeSize(look: look, profile: profile, in: proxy.size)
            let shape = OpenedIslandSurfaceShape(
                topProfile: profile == .notch ? .notch : .topBar,
                topCornerRadius: metrics.topRadius * scale * OpenedLookArtLayout.cornerBoost,
                bottomCornerRadius: metrics.bottomRadius * scale * OpenedLookArtLayout.cornerBoost
            )
            shape
                .fill(Color.black)
                .overlay { shape.stroke(Color.white.opacity(0.22), lineWidth: 0.75) }
                .overlay {
                    if showsContent {
                        content(inset: metrics.sideInset * scale + 3)
                    }
                }
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .accessibilityHidden(true)
    }

    /// Two rows of faint bars: a wide card over two small ones.
    private func content(inset: CGFloat) -> some View {
        VStack(spacing: 3) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .frame(height: 7)
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color.white.opacity(0.1))
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color.white.opacity(0.1))
            }
            .frame(height: 7)
        }
        .padding(.horizontal, inset)
        .padding(.bottom, 6)
        .padding(.top, 10)
    }
}

/// Sizing rules for `OpenedLookArt`. A plain enum and not part of the
/// view, which keeps them callable from tests without the main actor.
enum OpenedLookArtLayout {
    /// The widest look fills this much of the box's width.
    static let widestShare: CGFloat = 0.9
    /// The shape hangs this far down the box.
    static let heightShare: CGFloat = 0.74
    /// Corners are drawn larger than to scale. At a card's size a true
    /// radius would be a point or two, and the two choices would look alike.
    static let cornerBoost: CGFloat = 2.4

    /// Points of picture for one point of island, in a box this wide.
    static func scale(boxWidth: CGFloat, profile: IslandAppearanceDisplayProfile) -> CGFloat {
        let widest = IslandOpenedMetrics.preferredWidth(.widest, profile: profile)
        return boxWidth * widestShare / widest
    }

    /// Size of the shape for `look` in a box of this size.
    static func shapeSize(
        look: IslandOpenedLook,
        profile: IslandAppearanceDisplayProfile,
        in box: CGSize
    ) -> CGSize {
        let metrics = IslandOpenedMetrics.resolve(look: look, profile: profile)
        return CGSize(
            width: metrics.panelWidth * scale(boxWidth: box.width, profile: profile),
            height: box.height * heightShare
        )
    }
}
