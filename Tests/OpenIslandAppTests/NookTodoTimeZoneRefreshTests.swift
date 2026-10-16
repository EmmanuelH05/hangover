import Foundation
import Testing
@testable import OpenIslandApp

/// A new time zone has the source in use read its list again (D3 of the third
/// review fixes). Due days are kept as midnight in the zone they were read in,
/// which makes the list in memory read a day off in the new zone until it is
/// read again. Every source is a fake, and the system's notice is posted on a
/// center of the test's own.
@MainActor
@Suite struct NookTodoTimeZoneRefreshTests {
    private static let inbox = [TickTickFixtures.task(id: "a", title: "Write essay", due: "2026-10-10T17:00:00+0000")]

    private let center = NotificationCenter()

    private func hub(tickTick: NookTickTickTodoService, notion: NookNotionTodoService? = nil) -> NookTodoHub {
        let defaults = MemoryDefaults()
        let reminder = NookTodoDueReminder(defaults: defaults, notifications: center)
        return NookTodoHub(
            defaults: defaults, notion: notion, tickTick: tickTick, dueReminder: reminder, notifications: center
        )
    }

    private func model(_ hub: NookTodoHub) -> NookModel {
        NookModel(
            reminders: NookRemindersService(defaults: MemoryDefaults(), sample: []),
            todo: hub, defaults: MemoryDefaults(), looksForImportedGIF: false, asksMacOSForAccess: false
        )
    }

    @Test func aNewTimeZoneHasTheTickTickListReadAgain() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        let hub = hub(tickTick: harness.service)
        let nook = model(hub)
        hub.start(nook: nook)
        hub.selectedKind = .tickTick
        await harness.service.setupTask?.value
        await harness.settle()
        let before = harness.routes.filter { $0 == "GET /open/v1/project/inbox/data" }.count

        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await harness.service.refreshTask?.value
        await harness.settle()

        let after = harness.routes.filter { $0 == "GET /open/v1/project/inbox/data" }.count
        #expect(after == before + 1, "the list was read again once")
        withExtendedLifetime(nook) {}
    }

    @Test func theReadingIsNotHeldBackByTheSpacingBetweenRefreshes() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        let hub = hub(tickTick: harness.service)
        let nook = model(hub)
        hub.start(nook: nook)
        hub.selectedKind = .tickTick
        await harness.service.setupTask?.value
        await harness.settle()
        // The island opened a moment ago: an automatic refresh now would be skipped.
        harness.service.refresh()
        await harness.settle()
        let before = harness.routes.count

        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await harness.service.refreshTask?.value
        await harness.settle()

        #expect(harness.routes.count == before + 1)
        withExtendedLifetime(nook) {}
    }

    @Test func aSourceThatIsNotInUseIsLeftAlone() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        let hub = hub(tickTick: harness.service)
        let nook = model(hub)
        hub.start(nook: nook)
        // Reminders is the source in use.

        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await harness.service.refreshTask?.value
        await harness.settle()

        #expect(harness.transport.requests.isEmpty)
        withExtendedLifetime(nook) {}
    }

    @Test func aClockOrDayChangeDoesNotHaveTheSourceReadAgain() async {
        let harness = TickTickHarness()
        harness.serve(inbox: Self.inbox)
        let hub = hub(tickTick: harness.service)
        let nook = model(hub)
        hub.start(nook: nook)
        hub.selectedKind = .tickTick
        await harness.service.setupTask?.value
        await harness.settle()
        let before = harness.routes.count

        center.post(name: .NSSystemClockDidChange, object: nil)
        center.post(name: .NSCalendarDayChanged, object: nil)
        await harness.service.refreshTask?.value
        await harness.settle()

        #expect(harness.routes.count == before, "only a new zone changes what a stored day means")
        withExtendedLifetime(nook) {}
    }
}
