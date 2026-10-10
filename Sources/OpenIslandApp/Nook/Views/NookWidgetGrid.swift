import SwiftUI

/// Pure geometry for the Nook grid: where each slot sits, which slot the
/// pointer is over, and how a lifted tile follows the pointer. All points
/// are in the grid's own coordinates unless a function says otherwise.
enum NookWidgetGridMath {
    /// Frame of every widget for a grid `width` points wide, laid out by
    /// `NookWidgetLayout.rows`: two small tiles take one column each, a lone
    /// small tile sits left at one column, wide tiles span the grid.
    static func slotFrames(
        _ placements: [NookWidgetPlacement],
        width: CGFloat,
        smallRowHeight: CGFloat = NookWidgetLayout.smallHeight,
        cellHeight: (NookWidgetPlacement) -> CGFloat
    ) -> [NookWidgetKind: CGRect] {
        let column = NookWidgetLayout.columnWidth(totalWidth: width)
        var frames: [NookWidgetKind: CGRect] = [:]
        var y: CGFloat = 0
        for row in NookWidgetLayout.rows(placements) {
            let height = NookWidgetLayout.rowHeight(row, smallRowHeight: smallRowHeight, height: cellHeight)
            if row.isSmallRow {
                for (index, placement) in row.placements.enumerated() {
                    let x = CGFloat(index) * (column + NookWidgetLayout.columnSpacing)
                    frames[placement.kind] = CGRect(x: x, y: y, width: column, height: height)
                }
            } else {
                frames[row.placements[0].kind] = CGRect(x: 0, y: y, width: width, height: height)
            }
            y += height + NookWidgetLayout.rowSpacing
        }
        return frames
    }

    /// Index in `order` of the tile under `point`, skipping `dragging` so a
    /// tile hovering over its own slot hits nothing. Nil over a gap, over
    /// empty space or when `point` is only over the dragged tile.
    static func targetIndex(
        at point: CGPoint,
        frames: [NookWidgetKind: CGRect],
        order: [NookWidgetKind],
        dragging: NookWidgetKind
    ) -> Int? {
        for (index, kind) in order.enumerated() where kind != dragging {
            if frames[kind]?.contains(point) == true { return index }
        }
        return nil
    }

    /// What one pointer move does to a drag in progress.
    struct ReorderStep: Equatable {
        /// Index to move the dragged tile to, nil to leave the order alone.
        var moveTo: Int?
        /// The tile the dragged one just swapped with. It is ignored until
        /// the pointer leaves it, which stops a tall tile that lands under
        /// the pointer after a swap from pulling the dragged tile back.
        var ignoring: NookWidgetKind?
    }

    static func reorderStep(hit: Int?, order: [NookWidgetKind], ignoring: NookWidgetKind?) -> ReorderStep {
        guard let hit, order.indices.contains(hit) else {
            return ReorderStep(moveTo: nil, ignoring: nil)
        }
        let target = order[hit]
        if target == ignoring {
            return ReorderStep(moveTo: nil, ignoring: ignoring)
        }
        return ReorderStep(moveTo: hit, ignoring: target)
    }

    /// Offset that keeps a lifted tile under the pointer. `originAtStart` is
    /// the tile's slot origin when the drag began, `slotOrigin` where its
    /// slot is now (it changes when the order does), both in one space.
    static func liftedOffset(originAtStart: CGPoint, translation: CGSize, slotOrigin: CGPoint) -> CGSize {
        CGSize(
            width: originAtStart.x + translation.width - slotOrigin.x,
            height: originAtStart.y + translation.height - slotOrigin.y
        )
    }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    /// The space the grid and the shelf under it share, so a chip dragged
    /// out of the shelf can be hit-tested against the grid's tile frames.
    /// The parent applies `.coordinateSpace(.nookWidgetEditing)` to a
    /// container that holds both, with the grid at its origin or anywhere
    /// inside it.
    static var nookWidgetEditing: NamedCoordinateSpace { .named("NookWidgetEditing") }
}

/// The widgets of one display laid out in the two column grid. Generic over
/// the tile so the Personalization editor can draw it with placeholder
/// tiles. Outside edit mode it is the static page; in edit mode each tile
/// is outlined, takes drags to reorder, and carries remove, size and
/// resize-grip controls.
///
/// Tiles sit in one flat `ZStack` at computed offsets, not in nested rows,
/// so a tile keeps its identity (and its card state) when it changes row.
/// The parent must apply `.coordinateSpace(.nookWidgetEditing)` above the
/// grid. Reordering uses plain `DragGesture`s because the island is a
/// non-activating panel and AppKit drag sessions do not work there.
struct NookWidgetGrid<Tile: View>: View {
    var placements: [NookWidgetPlacement]
    var isEditing: Bool
    var cellHeight: (NookWidgetPlacement) -> CGFloat
    /// Height of a row of small tiles. The island uses the shared
    /// `NookWidgetLayout.smallHeight`; the settings preview passes less.
    var smallRowHeight: CGFloat
    var allowsContextMenu: Bool
    var entersEditingOnLongPress: Bool
    /// Tile that shows the insertion highlight while a chip is dragged over it.
    var highlightedKind: NookWidgetKind?
    /// Tile the welcome tour names: it gets a still ring, in or out of edit
    /// mode. Nil draws no ring.
    var outlinedKind: NookWidgetKind?
    /// Tile frames in `.nookWidgetEditing` space, sent whenever they change.
    var onFramesChange: (([NookWidgetKind: CGRect]) -> Void)?
    var onMove: (NookWidgetKind, Int) -> Void
    var onResize: (NookWidgetKind, NookWidgetSize) -> Void
    var onRemove: (NookWidgetKind) -> Void
    var onBeginEditing: () -> Void
    var tile: (NookWidgetPlacement) -> Tile

    static var reflowAnimation: Animation { Motion.reflow }
    private static var liftAnimation: Animation { Motion.lift }
    private static var longPressDuration: Double { 0.4 }
    private static var liftScale: CGFloat { 1.03 }
    private static var editingContentOpacity: Double { 0.55 }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: LiftedDrag?
    @State private var raisedKind: NookWidgetKind?
    @State private var gridOrigin: CGPoint = .zero

    /// A reorder drag in progress.
    private struct LiftedDrag: Equatable {
        var kind: NookWidgetKind
        /// The tile's slot origin when the drag began, in shared space.
        var originAtStart: CGPoint
        var translation: CGSize
        var ignoring: NookWidgetKind?
    }

    init(
        placements: [NookWidgetPlacement],
        isEditing: Bool,
        cellHeight: @escaping (NookWidgetPlacement) -> CGFloat,
        smallRowHeight: CGFloat = NookWidgetLayout.smallHeight,
        allowsContextMenu: Bool = true,
        entersEditingOnLongPress: Bool = true,
        highlightedKind: NookWidgetKind? = nil,
        outlinedKind: NookWidgetKind? = nil,
        onFramesChange: (([NookWidgetKind: CGRect]) -> Void)? = nil,
        onMove: @escaping (NookWidgetKind, Int) -> Void,
        onResize: @escaping (NookWidgetKind, NookWidgetSize) -> Void,
        onRemove: @escaping (NookWidgetKind) -> Void,
        onBeginEditing: @escaping () -> Void,
        @ViewBuilder tile: @escaping (NookWidgetPlacement) -> Tile
    ) {
        self.placements = placements
        self.isEditing = isEditing
        self.cellHeight = cellHeight
        self.smallRowHeight = smallRowHeight
        self.allowsContextMenu = allowsContextMenu
        self.entersEditingOnLongPress = entersEditingOnLongPress
        self.highlightedKind = highlightedKind
        self.outlinedKind = outlinedKind
        self.onFramesChange = onFramesChange
        self.onMove = onMove
        self.onResize = onResize
        self.onRemove = onRemove
        self.onBeginEditing = onBeginEditing
        self.tile = tile
    }

    var body: some View {
        let order = placements.map(\.kind)
        GeometryReader { proxy in
            let frames = NookWidgetGridMath.slotFrames(
                placements,
                width: proxy.size.width,
                smallRowHeight: smallRowHeight,
                cellHeight: cellHeight
            )
            ZStack(alignment: .topLeading) {
                ForEach(placements) { placement in
                    cell(placement, frames: frames, order: order)
                }
            }
            // One animation for every change to the layout: a move, a
            // resize, a tile coming or going. Keyed on the placements, not
            // only the order, so resizes animate too.
            .motionAnimation(Self.reflowAnimation, value: placements)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .onChange(of: sharedFrames(frames), initial: true) { _, new in
                onFramesChange?(new)
            }
        }
        .frame(height: NookWidgetLayout.contentHeight(placements, smallRowHeight: smallRowHeight, height: cellHeight))
        .onGeometryChange(for: CGPoint.self) { proxy in
            proxy.frame(in: .nookWidgetEditing).origin
        } action: { origin in
            gridOrigin = origin
        }
        // Leaving edit mode mid-drag removes the gesture without onEnded.
        .onChange(of: isEditing) { _, editing in
            guard !editing else { return }
            drag = nil
            raisedKind = nil
        }
    }

    private func sharedFrames(_ frames: [NookWidgetKind: CGRect]) -> [NookWidgetKind: CGRect] {
        frames.mapValues { $0.offsetBy(dx: gridOrigin.x, dy: gridOrigin.y) }
    }

    // MARK: Tile

    @ViewBuilder
    private func cell(
        _ placement: NookWidgetPlacement,
        frames: [NookWidgetKind: CGRect],
        order: [NookWidgetKind]
    ) -> some View {
        let kind = placement.kind
        let frame = frames[kind] ?? .zero
        let isLifted = drag?.kind == kind
        let shift = liftShift(for: kind, frame: frame)
        let canLongPress = entersEditingOnLongPress && !isEditing
        withContextMenu(placement) {
            tile(placement)
                .environment(\.nookWidgetSize, placement.size)
                .frame(width: frame.width, height: frame.height)
                .allowsHitTesting(!isEditing)
                // Dimmed content lets the edit controls read on top of it.
                .opacity(isEditing ? Self.editingContentOpacity : 1)
                .overlay {
                    if isEditing {
                        NookWidgetEditOverlay(
                            placement: placement,
                            isHighlighted: highlightedKind == kind,
                            reorder: reorderGesture(for: kind, frames: frames, order: order),
                            onResize: { onResize(kind, $0) },
                            onRemove: { onRemove(kind) }
                        )
                        .transition(.opacity)
                    }
                }
                .motionAnimation(Motion.editToggle, value: isEditing)
                .overlay { if outlinedKind == kind { NookWidgetTourRing() } }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: Self.longPressDuration).onEnded { _ in onBeginEditing() },
            including: canLongPress ? .all : .subviews
        )
        .scaleEffect(isLifted ? Self.liftScale : 1)
        .shadow(color: .black.opacity(isLifted ? 0.45 : 0), radius: isLifted ? 12 : 0, y: isLifted ? 6 : 0)
        .motionAnimation(Self.liftAnimation, value: isLifted)
        .offset(x: frame.minX + shift.width, y: frame.minY + shift.height)
        .zIndex(raisedKind == kind ? 1 : 0)
        .transition(Motion.transition(Self.tileTransition, reduceMotion: reduceMotion))
    }

    /// A tile added to the page grows in from slightly smaller; one removed
    /// shrinks away. The ZStack's reflow animation drives both.
    private static var tileTransition: AnyTransition {
        .scale(scale: 0.9).combined(with: .opacity)
    }

    /// Where the lifted tile sits relative to its slot, so it stays under
    /// the pointer even after the slot moves.
    private func liftShift(for kind: NookWidgetKind, frame: CGRect) -> CGSize {
        guard let drag, drag.kind == kind else { return .zero }
        return NookWidgetGridMath.liftedOffset(
            originAtStart: drag.originAtStart,
            translation: drag.translation,
            slotOrigin: CGPoint(x: frame.minX + gridOrigin.x, y: frame.minY + gridOrigin.y)
        )
    }

    // MARK: Reorder

    private func reorderGesture(
        for kind: NookWidgetKind,
        frames: [NookWidgetKind: CGRect],
        order: [NookWidgetKind]
    ) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .nookWidgetEditing)
            .onChanged { value in
                var current = drag ?? startDrag(kind, frames: frames)
                current.translation = value.translation
                let pointer = CGPoint(x: value.location.x - gridOrigin.x, y: value.location.y - gridOrigin.y)
                let hit = NookWidgetGridMath.targetIndex(at: pointer, frames: frames, order: order, dragging: kind)
                let step = NookWidgetGridMath.reorderStep(hit: hit, order: order, ignoring: current.ignoring)
                current.ignoring = step.ignoring
                drag = current
                raisedKind = kind
                if let index = step.moveTo { onMove(kind, index) }
            }
            .onEnded { _ in
                withMotion(Self.reflowAnimation) { drag = nil }
            }
    }

    private func startDrag(_ kind: NookWidgetKind, frames: [NookWidgetKind: CGRect]) -> LiftedDrag {
        let origin = frames[kind]?.origin ?? .zero
        return LiftedDrag(
            kind: kind,
            originAtStart: CGPoint(x: origin.x + gridOrigin.x, y: origin.y + gridOrigin.y),
            translation: .zero,
            ignoring: nil
        )
    }

    // MARK: Menu

    @ViewBuilder
    private func withContextMenu<Content: View>(
        _ placement: NookWidgetPlacement,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if allowsContextMenu {
            content().contextMenu { menu(for: placement) }
        } else {
            content()
        }
    }

    @ViewBuilder
    private func menu(for placement: NookWidgetPlacement) -> some View {
        ForEach(NookWidgetSize.allCases) { size in
            Button {
                onResize(placement.kind, size)
            } label: {
                if size == placement.size {
                    Label(size.title, systemImage: "checkmark")
                } else {
                    Text(size.title)
                }
            }
        }
        Divider()
        Button("Edit Widgets") { onBeginEditing() }
        Button("Remove from This Display") { onRemove(placement.kind) }
    }
}

/// The ring the welcome tour draws round the widget it names. Plain and
/// still, and it takes no clicks.
private struct NookWidgetTourRing: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.cyan, lineWidth: 3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
