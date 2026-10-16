import Foundation
import Testing
@testable import OpenIslandApp

/// The date popover is a window of its own. A click in it must not read as a
/// click outside the island, which would close the island and lose the task
/// typed in it (D7 of the review fixes).
@MainActor
@Suite struct NookTodoDatePickerTests {
    private func hub() -> NookTodoHub {
        NookTodoHub(defaults: MemoryDefaults())
    }

    /// The click the panel controller builds, with the hub's flag where it puts it.
    private func clickAction(with hub: NookTodoHub) -> IslandClickAction {
        IslandPointerRules.clickAction(
            IslandClickContext(
                status: .opened,
                reason: .click,
                isInClosedSurface: false,
                isInExpandedArea: false,
                isOnNotch: false,
                blocksDismiss: false,
                hasOpenPicker: hub.isPickingDate
            )
        )
    }

    @Test func theDatePickerStartsDown() {
        #expect(!hub().isPickingDate)
    }

    @Test func aClickOutsideWhileTheDatePopoverIsUpLeavesTheIslandOpen() {
        let hub = hub()
        hub.isPickingDate = true

        #expect(clickAction(with: hub) == .none)
    }

    @Test func withTheDatePopoverDownAClickOutsideStillCloses() {
        let hub = hub()
        hub.isPickingDate = true
        hub.isPickingDate = false

        #expect(clickAction(with: hub) == .dismiss)
    }

    /// The click, the swipe and the pointer leaving all read this one flag,
    /// which keeps a swipe or a drift from closing the island under the
    /// popover the click rule already spares.
    @Test func theNookCountsTheDatePopoverAsAnOpenPicker() {
        let nook = NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
        #expect(!nook.hasOpenPicker)

        nook.todo.isPickingDate = true
        #expect(nook.hasOpenPicker)

        nook.todo.isPickingDate = false
        #expect(!nook.hasOpenPicker)
    }
}
