import SwiftUI

/// What one tile shows in edit mode: an outline, a layer that takes every
/// click so the card underneath stays inert, a remove button, S/M/L size
/// buttons and a resize grip in the bottom-right corner. Dragging the
/// body runs `reorder`.
struct NookWidgetEditOverlay<Reorder: Gesture>: View {
    var placement: NookWidgetPlacement
    var isHighlighted: Bool
    var reorder: Reorder
    var onResize: (NookWidgetSize) -> Void
    var onRemove: () -> Void

    /// Size when the grip drag began; the drag snaps relative to it.
    @State private var sizeAtDragStart: NookWidgetSize?
    /// One per tile, so the current-size highlight slides between this
    /// tile's three buttons and never to another tile's.
    @Namespace private var sizeHighlight

    private static var cornerRadius: CGFloat { 16 }
    private static var controlInset: CGFloat { 4 }
    private static var hitArea: CGFloat { 22 }
    private static var gripHitArea: CGFloat { 28 }
    private static var gripVisible: CGFloat { 18 }

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                .gesture(reorder)
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                .allowsHitTesting(false)
            insertionHighlight
                .opacity(isHighlighted ? 1 : 0)
                .motionAnimation(Motion.hover, value: isHighlighted)
            removeButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Self.controlInset)
            sizeButtons
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(Self.controlInset)
            resizeGrip
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    private var insertionHighlight: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(Color.orange.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Color.orange, lineWidth: 2)
            )
            .allowsHitTesting(false)
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "minus.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Color.red.opacity(0.9))
                .font(.system(size: 16))
                .frame(width: Self.hitArea, height: Self.hitArea)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(placement.kind.title)")
    }

    private var sizeButtons: some View {
        HStack(spacing: 0) {
            ForEach(NookWidgetSize.allCases) { size in
                let isCurrent = size == placement.size
                Button {
                    onResize(size)
                } label: {
                    Text(size.shortTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isCurrent ? Color.orange : Color.white.opacity(0.6))
                        .frame(width: Self.hitArea, height: Self.hitArea)
                        .background {
                            if isCurrent {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.orange.opacity(0.2))
                                    .matchedGeometryEffect(id: "currentSize", in: sizeHighlight)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(size.title)
            }
        }
        .motionAnimation(Motion.selection, value: placement.size)
        .background(Capsule().fill(Color.black.opacity(0.4)))
    }

    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.85))
            .frame(width: Self.gripVisible, height: Self.gripVisible)
            .background(Circle().fill(Color.black.opacity(0.4)))
            .frame(width: Self.gripHitArea, height: Self.gripHitArea)
            .contentShape(Rectangle())
            .gesture(resizeGesture)
            .accessibilityLabel("Resize \(placement.kind.title)")
    }

    /// Reports each size the drag passes through, not only the last. The
    /// shared space keeps the translation steady while the tile reflows
    /// under the grip.
    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .nookWidgetEditing)
            .onChanged { value in
                let start = sizeAtDragStart ?? placement.size
                sizeAtDragStart = start
                let snapped = NookWidgetLayout.snappedSize(from: start, translation: value.translation)
                if snapped != placement.size { onResize(snapped) }
            }
            .onEnded { _ in sizeAtDragStart = nil }
    }
}

/// The row under the grid in edit mode: chips for widgets that can be
/// added, and Done. Click a chip to add it at the end, or drag it onto a
/// tile to add it at that tile's place.
struct NookWidgetShelf: View {
    var addable: [NookWidgetKind]
    /// Widgets on the page, in order.
    var order: [NookWidgetKind]
    /// Their frames in `.nookWidgetEditing` space.
    var tileFrames: [NookWidgetKind: CGRect]
    /// The tile a dragged chip is over, drawn highlighted by the grid.
    @Binding var insertionTarget: NookWidgetKind?
    var onAdd: (NookWidgetKind) -> Void
    var onAddAt: (NookWidgetKind, Int) -> Void
    /// Nil hides the Done button; the settings editor has no edit mode.
    var onDone: (() -> Void)?
    var addTitle = "Add"
    var allShownTitle = "Every widget is on the page"

    /// Height of the row; `NookPanelView.editingExtraHeight` counts it.
    static let height: CGFloat = 28

    /// Movement below this is a click, at or above it a drag.
    private static var dragThreshold: CGFloat { 4 }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragging: ChipDrag?

    private struct ChipDrag: Equatable {
        var kind: NookWidgetKind
        var translation: CGSize
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showsTitles: true)
            row(showsTitles: false)
        }
        .frame(height: Self.height)
    }

    private func row(showsTitles: Bool) -> some View {
        HStack(spacing: 6) {
            if addable.isEmpty {
                Text(allShownTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .transition(.opacity)
            } else {
                Text(addTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .transition(.opacity)
                ForEach(addable) { kind in
                    chip(kind, showsTitle: showsTitles)
                }
            }
            Spacer(minLength: 8)
            if let onDone {
                doneButton(onDone)
            }
        }
        // Chips slide over to close a gap, or make room, when the list changes.
        .motionAnimation(Motion.reflow, value: addable)
    }

    /// A chip joining the shelf grows in; one leaving shrinks away.
    private var chipTransition: AnyTransition {
        Motion.transition(.scale(scale: 0.8).combined(with: .opacity), reduceMotion: reduceMotion)
    }

    private func doneButton(_ onDone: @escaping () -> Void) -> some View {
        Button(action: onDone) {
            Text("Done")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .frame(height: 24)
                .background(Capsule().fill(Color.orange))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func chip(_ kind: NookWidgetKind, showsTitle: Bool) -> some View {
        let isDragging = dragging?.kind == kind
        return HStack(spacing: 5) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 11, weight: .medium))
            if showsTitle {
                Text(kind.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Color.white.opacity(0.85))
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .contentShape(Capsule())
        .scaleEffect(isDragging ? 1.05 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.45 : 0), radius: isDragging ? 8 : 0, y: isDragging ? 4 : 0)
        // Before the offset, so only the lift animates and the chip still
        // follows the pointer exactly.
        .motionAnimation(Motion.lift, value: isDragging)
        .offset(isDragging ? (dragging?.translation ?? .zero) : .zero)
        .zIndex(isDragging ? 1 : 0)
        .transition(chipTransition)
        .gesture(chipGesture(kind))
        .help("Add \(kind.title)")
        .accessibilityLabel("Add \(kind.title)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onAdd(kind) }
    }

    /// One gesture for both: a release without movement is a click, a
    /// release after a drag drops the chip on the tile under the pointer.
    private func chipGesture(_ kind: NookWidgetKind) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .nookWidgetEditing)
            .onChanged { value in
                guard Self.isDrag(value.translation) else { return }
                dragging = ChipDrag(kind: kind, translation: value.translation)
                insertionTarget = tileKind(under: value.location, dropping: kind)
            }
            .onEnded { value in
                let target = tileKind(under: value.location, dropping: kind)
                // Settles back (scale, shadow and offset) on the lift spring.
                withMotion(Motion.lift) {
                    dragging = nil
                    insertionTarget = nil
                }
                if !Self.isDrag(value.translation) {
                    onAdd(kind)
                } else if let target, let index = order.firstIndex(of: target) {
                    onAddAt(kind, index)
                }
            }
    }

    private func tileKind(under point: CGPoint, dropping kind: NookWidgetKind) -> NookWidgetKind? {
        NookWidgetGridMath
            .targetIndex(at: point, frames: tileFrames, order: order, dragging: kind)
            .map { order[$0] }
    }

    private static func isDrag(_ translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) >= dragThreshold
    }
}
