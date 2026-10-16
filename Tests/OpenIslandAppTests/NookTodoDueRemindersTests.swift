import EventKit
import Foundation
import Testing
@testable import OpenIslandApp

/// A task source that records what it is asked to add and touches nothing.
@MainActor
final class NookTodoDueFakeSource: NookTodoSource {
    var items: [NookTodoItem] = []
    var displayName = "Fake"
    var connection: NookTodoConnection = .ready
    var errorMessage: String?
    var notesSaveFailed = false
    var isShowingCachedItems = false
    var canAdd = true
    var canComplete = true
    var canEditNotes = true
    var notesUnavailableReason: String?
    var canSetDue = true
    var dueUnavailableReason: String?
    var addPlaceholder = "Add"
    var autoRefreshInterval: Duration?
    private(set) var added: [Added] = []

    struct Added: Equatable {
        let title: String
        let due: DateComponents?
    }

    func refresh() {}
    func refreshOnTimer() {}
    func complete(_ id: String) {}
    func setNotes(_ notes: String, for id: String) {}

    func add(_ title: String, due: DateComponents?) {
        added.append(Added(title: title, due: due))
    }
}

/// What Return does with the add field, and how Reminders keeps a day (D69).
@MainActor
@Suite struct NookTodoDueRemindersTests {
    private typealias F = NookTodoDueFixtures

    // MARK: Return on the add field

    @Test func aPickedDayGoesWithTheTask() async {
        let source = NookTodoDueFakeSource()

        let added = await NookTodoAdding.submit(draft: "HW3", due: F.day(2026, 10, 16), to: source)

        #expect(added)
        #expect(source.added == [.init(title: "HW3", due: F.day(2026, 10, 16))])
    }

    @Test func noPickedDayAddsATaskWithNoDate() async {
        let source = NookTodoDueFakeSource()

        let added = await NookTodoAdding.submit(draft: "HW3", due: nil, to: source)

        #expect(added)
        #expect(source.added == [.init(title: "HW3", due: nil)])
    }

    @Test func aSourceThatCannotKeepADayIsNotGivenOne() async {
        let source = NookTodoDueFakeSource()
        source.canSetDue = false

        let added = await NookTodoAdding.submit(draft: "HW3", due: F.day(2026, 10, 16), to: source)

        #expect(added)
        #expect(source.added == [.init(title: "HW3", due: nil)])
    }

    @Test func onlyTheDayIsSentNeverATime() async {
        let source = NookTodoDueFakeSource()
        let withTime = DateComponents(year: 2026, month: 10, day: 16, hour: 15, minute: 30)

        _ = await NookTodoAdding.submit(draft: "HW3", due: withTime, to: source)

        #expect(source.added.first?.due == F.day(2026, 10, 16))
    }

    @Test func somethingThatIsNotADayIsLeftOut() async {
        let source = NookTodoDueFakeSource()

        _ = await NookTodoAdding.submit(draft: "HW3", due: F.day(2026, 2, 30), to: source)

        #expect(source.added == [.init(title: "HW3", due: nil)])
    }

    @Test(arguments: ["", "   ", " \n "])
    func aBlankTitleAddsNothing(draft: String) async {
        let source = NookTodoDueFakeSource()

        let added = await NookTodoAdding.submit(draft: draft, due: F.day(2026, 10, 16), to: source)

        #expect(!added)
        #expect(source.added.isEmpty)
    }

    @Test func aSourceThatCannotAddTakesNothing() async {
        let source = NookTodoDueFakeSource()
        source.canAdd = false

        let added = await NookTodoAdding.submit(draft: "HW3", due: F.day(2026, 10, 16), to: source)

        #expect(!added)
        #expect(source.added.isEmpty)
    }

    @Test func theProtocolsPlainAddMeansNoDate() async {
        let source = NookTodoDueFakeSource()

        source.add("Call home")

        #expect(source.added == [.init(title: "Call home", due: nil)])
    }

    // MARK: Reminders

    @Test func theSampleListKeepsTheDayOnTheNewRow() {
        let service = NookRemindersService(defaults: MemoryDefaults(), sample: [])

        service.add("  Call home  ", due: F.day(2026, 10, 16))
        service.add("Buy milk", due: nil)
        service.add("Bad day", due: F.day(2026, 2, 30))

        let dates = service.items.map(\.dueDate)
        #expect(service.items.map(\.title) == ["Call home", "Buy milk", "Bad day"])
        #expect(dates[0] == NookTodoDay.date(from: F.day(2026, 10, 16), calendar: .current))
        #expect(dates[1] == nil)
        #expect(dates[2] == nil)
    }

    @Test func aNewRowShowsItsDateRightAwayOnTheDay() {
        let service = NookRemindersService(defaults: MemoryDefaults(), sample: [])
        let today = NookTodoDay.components(of: Date(), calendar: .current)

        service.add("Call home", due: today)

        let due = service.items.last?.dueDate
        #expect(due.map { Calendar.current.isDateInToday($0) } == true)
    }

    @Test func remindersIsGivenYearMonthAndDayOnTheGregorianCalendar() {
        let withTime = DateComponents(year: 2026, month: 10, day: 16, hour: 9, minute: 5)

        let due = NookRemindersService.dueComponents(for: withTime)

        #expect(due?.year == 2026 && due?.month == 10 && due?.day == 16)
        #expect(due?.hour == nil && due?.minute == nil && due?.second == nil)
        #expect(due?.timeZone == nil)
        #expect(due?.calendar?.identifier == .gregorian)
        #expect(NookRemindersService.dueComponents(for: nil) == nil)
        #expect(NookRemindersService.dueComponents(for: F.day(2026, 13, 1)) == nil)
    }

    @Test func remindersCanSetADateWhenItCanAdd() {
        let sample = NookRemindersService(defaults: MemoryDefaults(), sample: [])
        let fake = FakeEventKitPermission(status: .denied)
        let locked = NookRemindersService(access: fake.access, defaults: MemoryDefaults())

        #expect(sample.canAdd && sample.canSetDue)
        #expect(sample.dueUnavailableReason == nil)
        #expect(!locked.canAdd && !locked.canSetDue)
        #expect(locked.dueUnavailableReason == LanguageManager.shared.t("nook.todo.due.unavailable"))
    }
}
