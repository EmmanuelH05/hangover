import CoreGraphics
import SwiftUI

/// One choice in the photo booth's Settings as plain values, which keeps
/// what the tiles list apart from how they are drawn.
struct NookPhotoBoothChoice: Identifiable, Equatable, Sendable {
    let id: String
    /// What the tile is called, in the app's language.
    let name: String
    let isChosen: Bool

    static func layout(_ kind: NookPhotoStripLayout.Kind, chosen: NookPhotoStripLayout.Kind, name: String) -> NookPhotoBoothChoice {
        NookPhotoBoothChoice(id: kind.id, name: name, isChosen: kind == chosen)
    }

    static func theme(_ theme: NookPhotoStripTheme, chosen: String, name: String) -> NookPhotoBoothChoice {
        NookPhotoBoothChoice(id: theme.id, name: name, isChosen: theme.id == chosen)
    }
}

/// A button that shows a small picture of the strip a choice makes, with the
/// choice's name under it. The card around it is the one the rest of
/// Settings uses, which gives it hover, press and the selection ring.
struct NookPhotoBoothTile: View {
    let choice: NookPhotoBoothChoice
    /// The layout the picture is of. Its shape is held open while the
    /// picture is still being drawn, which keeps the tile from jumping.
    let pictureKind: NookPhotoStripLayout.Kind
    let picture: CGImage?
    /// Lines the name may take. A tile reserves them all, which keeps the
    /// tiles of a grid the same height.
    let nameLines: Int
    let ringNamespace: Namespace.ID
    let ringGroup: String
    let select: () -> Void

    /// The card's padding on both sides, from `PersonalizationCard`.
    static let cardPadding: CGFloat = 24
    /// Narrowest a tile gets, wide enough for a two-word name.
    static let minimumWidth: CGFloat = 96
    /// Height of the box the picture sits in: the tallest a preview is.
    static let pictureHeight = NookPhotoBoothPreviewDrawing.longestSide / NookPhotoBoothPreviewDrawing.pixelsPerPoint

    /// Narrowest a tile of this layout's pictures gets: its picture fits
    /// with the card around it.
    static func minimumWidth(showing kind: NookPhotoStripLayout.Kind) -> CGFloat {
        max(minimumWidth, NookPhotoBoothPreviewDrawing.pointSize(of: kind).width + cardPadding)
    }

    var body: some View {
        PersonalizationCard(
            title: choice.name,
            selected: choice.isChosen,
            style: .panel,
            ringNamespace: ringNamespace,
            ringGroup: ringGroup,
            action: select
        ) {
            VStack(spacing: 8) {
                pictureBox
                    .frame(height: Self.pictureHeight)
                Text(choice.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(nameLines, reservesSpace: true)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var pictureBox: some View {
        let size = NookPhotoBoothPreviewDrawing.pointSize(of: pictureKind)
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        return ZStack {
            shape.fill(Color.white.opacity(0.06))
            if let picture {
                Image(decorative: picture, scale: NookPhotoBoothPreviewDrawing.pixelsPerPoint)
                    .resizable()
                    .interpolation(.high)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.35), radius: 3, y: 1)
        .motionAnimation(Motion.contentSwap, value: picture != nil)
    }
}

/// Lays tiles out in rows that wrap. All the tiles are one width: as many
/// columns as fit at `minimumWidth`, shared out across the row.
struct NookPhotoBoothTileFlow: Layout {
    var minimumWidth: CGFloat
    var spacing: CGFloat = 8

    /// As many columns as fit, then as few as keep the same number of rows,
    /// which spreads the tiles evenly instead of leaving one alone on the
    /// last row. A width that is not a finite number has no edge to wrap at,
    /// and the tiles take one row.
    func columns(fitting width: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 1 }
        guard width.isFinite else { return count }
        let fits = min(max(1, Int(((width + spacing) / (minimumWidth + spacing)).rounded(.down))), count)
        let rows = (count + fits - 1) / fits
        return (count + rows - 1) / rows
    }

    /// The width to lay out in: the one proposed, or the width of a single
    /// row when none is proposed or it is unbounded, as a stack or a bare
    /// hosting view may propose.
    func layoutWidth(_ proposed: CGFloat?, count: Int) -> CGFloat {
        if let proposed, proposed.isFinite { return max(0, proposed) }
        return minimumWidth * CGFloat(count) + spacing * CGFloat(max(0, count - 1))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = layoutWidth(proposal.width, count: subviews.count)
        let rows = rowHeights(subviews, width: width)
        return CGSize(width: width, height: rows.reduce(0, +) + spacing * CGFloat(rows.count - 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let width = layoutWidth(bounds.width, count: subviews.count)
        let columns = columns(fitting: width, count: subviews.count)
        let tileWidth = self.tileWidth(in: width, columns: columns)
        let heights = rowHeights(subviews, width: width)
        var y = bounds.minY
        for (row, height) in heights.enumerated() {
            for column in 0..<columns {
                let index = row * columns + column
                guard index < subviews.count else { break }
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + CGFloat(column) * (tileWidth + spacing), y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: tileWidth, height: height)
                )
            }
            y += height + spacing
        }
    }

    private func tileWidth(in width: CGFloat, columns: Int) -> CGFloat {
        (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    /// The height of each row: its tallest tile at the shared width.
    private func rowHeights(_ subviews: Subviews, width: CGFloat) -> [CGFloat] {
        let columns = columns(fitting: width, count: subviews.count)
        let tileWidth = tileWidth(in: width, columns: columns)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: tileWidth, height: nil)).height }
        return stride(from: 0, to: heights.count, by: columns).map { start in
            heights[start..<min(start + columns, heights.count)].max() ?? 0
        }
    }
}
