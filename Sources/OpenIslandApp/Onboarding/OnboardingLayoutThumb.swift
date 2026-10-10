import SwiftUI

/// A layout's widget page in miniature, as the layout card of the tour shows
/// it: a tile a widget, each at its real size relative to the others, with
/// the widget's icon and, where it fits, its name. The tiles come from the
/// same grid math as the island's page: a large widget is as much wider
/// and taller here as it is there.
struct OnboardingLayoutThumb: View {
    let placements: [NookWidgetPlacement]
    let calendarStyle: NookCalendarStyle
    /// The name a tile carries, in the language in use.
    let name: (NookWidgetKind) -> String
    var size = OnboardingLayoutThumb.defaultSize

    static let defaultSize = CGSize(width: 96, height: 76)

    /// One drawn tile.
    struct Tile: Equatable, Identifiable {
        let kind: NookWidgetKind
        let frame: CGRect
        let showsName: Bool

        var id: NookWidgetKind { kind }
    }

    /// The width the island's page is laid out at before it is made smaller.
    private static let naturalWidth: CGFloat = 400
    /// A tile shorter than this carries its icon alone.
    private static let minNameHeight: CGFloat = 12
    private static let inset: CGFloat = 0.6
    private static let nameFont: CGFloat = 6.5
    private static let letterWidth: CGFloat = 3.7

    /// The tiles in `size`. The page is made as wide as the box, and as tall
    /// as the box allows: a page taller than the box is squeezed in height
    /// only, which keeps every tile's size relative to the others.
    static func tiles(
        _ placements: [NookWidgetPlacement],
        calendarStyle: NookCalendarStyle,
        size: CGSize,
        name: (NookWidgetKind) -> String
    ) -> [Tile] {
        let cellHeight: (NookWidgetPlacement) -> CGFloat = {
            NookPanelView.cardHeight($0, calendarStyle: calendarStyle)
        }
        let frames = NookWidgetGridMath.slotFrames(placements, width: naturalWidth, cellHeight: cellHeight)
        let pageHeight = NookWidgetLayout.contentHeight(placements, height: cellHeight)
        guard pageHeight > 0 else { return [] }
        let across = size.width / naturalWidth
        let down = min(across, size.height / pageHeight)
        return placements.compactMap { placement in
            guard let natural = frames[placement.kind] else { return nil }
            let frame = CGRect(
                x: natural.minX * across,
                y: natural.minY * down,
                width: natural.width * across,
                height: natural.height * down
            ).insetBy(dx: inset, dy: inset)
            let fits = frame.height >= minNameHeight
                && CGFloat(name(placement.kind).count) * letterWidth + frame.height * 0.5 + 8 <= frame.width
            return Tile(kind: placement.kind, frame: frame, showsName: fits)
        }
    }

    var body: some View {
        let tiles = Self.tiles(placements, calendarStyle: calendarStyle, size: size, name: name)
        ZStack(alignment: .topLeading) {
            ForEach(tiles) { tile in
                self.tile(tile)
                    .frame(width: tile.frame.width, height: tile.frame.height)
                    .offset(x: tile.frame.minX, y: tile.frame.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// A tile is a quiet gray with the widget's icon in white. No color a
    /// widget: the pictures of two layouts differ by where the tiles sit
    /// and how large they are.
    private func tile(_ tile: Tile) -> some View {
        let icon = min(max(tile.frame.height * 0.5, 5.5), 9)
        return RoundedRectangle(cornerRadius: min(3.5, tile.frame.height / 3), style: .continuous)
            .fill(Color.white.opacity(0.12))
            .overlay(
                HStack(spacing: 2.5) {
                    Image(systemName: tile.kind.systemImage)
                        .font(.system(size: icon, weight: .bold))
                    if tile.showsName {
                        Text(name(tile.kind))
                            .font(.system(size: Self.nameFont, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(Color.white.opacity(0.78))
            )
    }
}
