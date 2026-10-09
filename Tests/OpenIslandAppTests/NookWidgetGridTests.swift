import CoreGraphics
import Foundation
import Testing
@testable import OpenIslandApp

@Suite struct NookWidgetGridTests {
    private static let width: CGFloat = 450
    private static var column: CGFloat { NookWidgetLayout.columnWidth(totalWidth: width) }

    private static func place(_ kind: NookWidgetKind, _ size: NookWidgetSize) -> NookWidgetPlacement {
        NookWidgetPlacement(kind: kind, size: size)
    }

    /// Wide tiles are 100 tall, large ones 200.
    private static func height(_ placement: NookWidgetPlacement) -> CGFloat {
        placement.size == .large ? 200 : 100
    }

    private static func frames(_ placements: [NookWidgetPlacement]) -> [NookWidgetKind: CGRect] {
        NookWidgetGridMath.slotFrames(placements, width: width, cellHeight: height)
    }

    // MARK: Slot frames

    @Test func twoSmallTilesShareARowAtOneColumnEach() {
        let frames = Self.frames([Self.place(.timer, .small), Self.place(.tray, .small), Self.place(.todo, .medium)])
        let small = NookWidgetLayout.smallHeight
        let gap = NookWidgetLayout.columnSpacing

        #expect(frames[.timer] == CGRect(x: 0, y: 0, width: Self.column, height: small))
        #expect(frames[.tray] == CGRect(x: Self.column + gap, y: 0, width: Self.column, height: small))
        #expect(frames[.todo] == CGRect(x: 0, y: small + NookWidgetLayout.rowSpacing, width: Self.width, height: 100))
    }

    @Test func aLoneSmallTileIsLeftAlignedAtOneColumn() {
        let frames = Self.frames([Self.place(.timer, .small), Self.place(.calendar, .large)])

        #expect(frames[.timer] == CGRect(x: 0, y: 0, width: Self.column, height: NookWidgetLayout.smallHeight))
        #expect(frames[.calendar]?.minY == NookWidgetLayout.smallHeight + NookWidgetLayout.rowSpacing)
        #expect(frames[.calendar]?.height == 200)
    }

    @Test func framesFillTheContentHeightExactly() {
        let placements = [
            Self.place(.media, .large), Self.place(.timer, .small), Self.place(.tray, .small),
            Self.place(.notes, .small), Self.place(.todo, .medium),
        ]
        let frames = Self.frames(placements)
        let bottom = frames.values.map(\.maxY).max()

        #expect(frames.count == placements.count)
        #expect(bottom == NookWidgetLayout.contentHeight(placements, height: Self.height))
    }

    @Test func noPlacementsMeansNoFrames() {
        #expect(Self.frames([]).isEmpty)
    }

    // MARK: Hit testing

    private static let order: [NookWidgetKind] = [.timer, .tray, .todo]
    private static var sample: [NookWidgetKind: CGRect] {
        frames([place(.timer, .small), place(.tray, .small), place(.todo, .medium)])
    }

    @Test func aPointInsideATileHitsItsIndex() {
        let tray = Self.sample[.tray]!
        let todo = Self.sample[.todo]!

        #expect(NookWidgetGridMath.targetIndex(
            at: CGPoint(x: tray.midX, y: tray.midY), frames: Self.sample, order: Self.order, dragging: .timer) == 1)
        #expect(NookWidgetGridMath.targetIndex(
            at: CGPoint(x: todo.midX, y: todo.midY), frames: Self.sample, order: Self.order, dragging: .timer) == 2)
    }

    @Test func aPointBetweenTilesHitsNothing() {
        let timer = Self.sample[.timer]!
        let todo = Self.sample[.todo]!
        let columnGap = CGPoint(x: timer.maxX + NookWidgetLayout.columnSpacing / 2, y: timer.midY)
        let rowGap = CGPoint(x: todo.midX, y: todo.minY - NookWidgetLayout.rowSpacing / 2)

        #expect(NookWidgetGridMath.targetIndex(at: columnGap, frames: Self.sample, order: Self.order, dragging: .todo) == nil)
        #expect(NookWidgetGridMath.targetIndex(at: rowGap, frames: Self.sample, order: Self.order, dragging: .timer) == nil)
    }

    @Test func hoveringOverItsOwnSlotHitsNothing() {
        let timer = Self.sample[.timer]!

        #expect(NookWidgetGridMath.targetIndex(
            at: CGPoint(x: timer.midX, y: timer.midY), frames: Self.sample, order: Self.order, dragging: .timer) == nil)
    }

    @Test func emptyFramesOrOrderHitNothing() {
        let point = CGPoint(x: 10, y: 10)

        #expect(NookWidgetGridMath.targetIndex(at: point, frames: [:], order: Self.order, dragging: .timer) == nil)
        #expect(NookWidgetGridMath.targetIndex(at: point, frames: Self.sample, order: [], dragging: .timer) == nil)
    }

    @Test func spaceBesideALoneSmallTileHitsNothing() {
        let frames = Self.frames([Self.place(.timer, .small), Self.place(.todo, .medium)])
        let beside = CGPoint(x: Self.width - 5, y: 5)

        #expect(NookWidgetGridMath.targetIndex(at: beside, frames: frames, order: [.timer, .todo], dragging: .todo) == nil)
    }

    @Test func aChipNotOnThePageHitsAnyTileUnderIt() {
        let timer = Self.sample[.timer]!

        #expect(NookWidgetGridMath.targetIndex(
            at: CGPoint(x: timer.midX, y: timer.midY), frames: Self.sample, order: Self.order, dragging: .mirror) == 0)
    }

    @Test func tileEdgesAreInclusiveAtTheTopLeftAndExclusiveAtTheBottomRight() {
        let tray = Self.sample[.tray]!

        #expect(NookWidgetGridMath.targetIndex(
            at: CGPoint(x: tray.minX, y: tray.minY), frames: Self.sample, order: Self.order, dragging: .timer) == 1)
        #expect(NookWidgetGridMath.targetIndex(
            at: CGPoint(x: tray.maxX, y: tray.maxY), frames: Self.sample, order: Self.order, dragging: .timer) == nil)
    }

    // MARK: Reorder steps

    @Test func enteringATileMovesToItAndRemembersIt() {
        let step = NookWidgetGridMath.reorderStep(hit: 2, order: Self.order, ignoring: nil)

        #expect(step == .init(moveTo: 2, ignoring: .todo))
    }

    @Test func aTileJustSwappedWithIsIgnoredUntilThePointerLeavesIt() {
        let stay = NookWidgetGridMath.reorderStep(hit: 2, order: Self.order, ignoring: .todo)
        let leave = NookWidgetGridMath.reorderStep(hit: nil, order: Self.order, ignoring: .todo)
        let other = NookWidgetGridMath.reorderStep(hit: 1, order: Self.order, ignoring: .todo)

        #expect(stay == .init(moveTo: nil, ignoring: .todo))
        #expect(leave == .init(moveTo: nil, ignoring: nil))
        #expect(other == .init(moveTo: 1, ignoring: .tray))
    }

    @Test func aHitOutsideTheOrderIsTreatedAsNoHit() {
        #expect(NookWidgetGridMath.reorderStep(hit: 9, order: Self.order, ignoring: .todo) == .init(moveTo: nil, ignoring: nil))
    }

    /// A medium tile dragged down onto a tall large one: after the swap the
    /// large tile sits at the top and still covers the pointer. Without the
    /// ignore rule the next move would swap straight back.
    @Test func aTallTileUnderThePointerAfterASwapDoesNotPullTheDraggedTileBack() {
        var order: [NookWidgetKind] = [.todo, .calendar]
        func placements() -> [NookWidgetPlacement] {
            order.map { Self.place($0, $0 == .calendar ? .large : .medium) }
        }
        let pointer = CGPoint(x: 100, y: 130)
        var ignoring: NookWidgetKind?
        var moves = 0

        for _ in 0..<5 {
            let hit = NookWidgetGridMath.targetIndex(
                at: pointer, frames: Self.frames(placements()), order: order, dragging: .todo)
            let step = NookWidgetGridMath.reorderStep(hit: hit, order: order, ignoring: ignoring)
            ignoring = step.ignoring
            if let index = step.moveTo {
                order = NookWidgetLayout.moving(.todo, to: index, in: order)
                moves += 1
            }
        }

        #expect(moves == 1)
        #expect(order == [.calendar, .todo])
    }

    // MARK: Following the pointer

    @Test func aLiftedTileStaysUnderThePointerWhenItsSlotMoves() {
        let start = CGPoint(x: 0, y: 130)
        let translation = CGSize(width: 40, height: 90)
        let before = NookWidgetGridMath.liftedOffset(originAtStart: start, translation: translation, slotOrigin: start)
        let newSlot = CGPoint(x: 0, y: 340)
        let after = NookWidgetGridMath.liftedOffset(originAtStart: start, translation: translation, slotOrigin: newSlot)

        #expect(before == translation)
        // Slot plus offset lands on the same spot before and after the move.
        #expect(start.y + before.height == newSlot.y + after.height)
        #expect(start.x + before.width == newSlot.x + after.width)
    }

    // MARK: Window height

    @Test func editingExtraHeightIsTheShelfAndTheGapAboveIt() {
        #expect(NookPanelView.editingExtraHeight == NookWidgetLayout.rowSpacing + NookWidgetShelf.height)
    }

    @Test func editingAddsTheShelfAndThePaddingUnderItWhenThereAreWidgets() {
        let placements = [Self.place(.timer, .small), Self.place(.tray, .small), Self.place(.todo, .large)]
        let resting = NookPanelView.preferredHeight(for: placements, calendarStyle: .strip, isEditing: false)
        let editing = NookPanelView.preferredHeight(for: placements, calendarStyle: .strip, isEditing: true)

        #expect(editing - resting == NookPanelView.editingExtraHeight + NookPanelView.verticalPadding)
    }

    /// Top to bottom, the way the view stacks it: the scroll area (grid plus
    /// its padding), the gap, the shelf, then the padding under the shelf.
    @Test func editingHeightWithWidgetsIsEveryPieceTheViewStacks() {
        let placements = [Self.place(.timer, .small), Self.place(.tray, .small), Self.place(.todo, .large)]
        let style = NookCalendarStyle.strip
        let grid = NookWidgetLayout.contentHeight(placements) { NookPanelView.cardHeight($0, calendarStyle: style) }
        let scrollArea = NookPanelView.verticalPadding * 2 + grid
        let expected = scrollArea
            + NookWidgetLayout.rowSpacing
            + NookWidgetShelf.height
            + NookPanelView.verticalPadding

        #expect(NookPanelView.preferredHeight(for: placements, calendarStyle: style, isEditing: true) == expected)
    }

    @Test func anEmptyPageEditsAsJustTheShelfAndRestsAsTheEmptyState() {
        let resting = NookPanelView.preferredHeight(for: [], calendarStyle: .strip, isEditing: false)
        let editing = NookPanelView.preferredHeight(for: [], calendarStyle: .strip, isEditing: true)

        #expect(resting == NookPanelView.verticalPadding * 2 + NookPanelView.emptyHeight)
        #expect(editing == NookPanelView.verticalPadding * 2 + NookPanelView.editingExtraHeight)
    }
}
