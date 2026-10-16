import Foundation
import Testing
@testable import OpenIslandApp

/// A Notion date range is overdue by its end, not by its start (D9 of the
/// review fixes). The due day stays the start.
@MainActor
@Suite struct NotionDateRangeTests {
    private typealias F = NookTodoDueFixtures
    private let calendar = F.calendar()

    // MARK: Reading a range

    private func items(_ pages: [(id: String, due: String, end: String?)]) throws -> [NookTodoItem] {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.selectSchema)
        let resolved = try NotionTodoMapper.resolve(NotionTodoMapper.detect(schema), schema: schema).get()
        let decoded = try pages.map { page in
            var json = NotionFixtures.page(id: page.id, title: page.id, due: page.due)
            if let end = page.end {
                json = json.replacingOccurrences(of: "\"end\":null", with: "\"end\":\"\(end)\"")
            }
            return try NotionFixtures.decodePage(json)
        }
        return NotionTodoMapper.items(from: decoded, resolved: resolved, listName: "To-Do")
    }

    @Test func aRangeKeepsItsStartAsTheDueDayAndItsEndBesideIt() throws {
        let item = try #require(try items([("range", "2026-10-10", "2026-10-20")]).first)

        #expect(item.dueDate == NotionTodoMapper.parseDate("2026-10-10"))
        #expect(item.endDate == NotionTodoMapper.parseDate("2026-10-20"))
        #expect(item.overdueDate == item.endDate)
    }

    @Test func aSingleDateHasNoEnd() throws {
        let item = try #require(try items([("single", "2026-10-10", nil)]).first)

        #expect(item.endDate == nil)
        #expect(item.overdueDate == item.dueDate)
    }

    @Test(arguments: ["2026-10-10", "2026-10-09"])
    func anEndThatIsNotAfterTheStartIsNotARange(end: String) throws {
        let item = try #require(try items([("odd", "2026-10-10", end)]).first)

        #expect(item.endDate == nil)
        #expect(item.dueDate == NotionTodoMapper.parseDate("2026-10-10"))
    }

    @Test func aRangeWithTimesEndsOnItsEndMoment() throws {
        let item = try #require(try items([("timed", "2026-10-10T09:00:00.000-07:00", "2026-10-12T17:00:00.000-07:00")]).first)

        #expect(item.endDate != nil)
        #expect(item.endDate.map { $0 > (item.dueDate ?? .distantFuture) } == true)
    }

    @Test func aPageWithNoDateHasNeither() throws {
        let schema = try NotionFixtures.decodeSchema(NotionFixtures.selectSchema)
        let resolved = try NotionTodoMapper.resolve(NotionTodoMapper.detect(schema), schema: schema).get()
        let page = try NotionFixtures.decodePage(NotionFixtures.page(id: "none", title: "None"))

        let item = try #require(NotionTodoMapper.items(from: [page], resolved: resolved, listName: "To-Do").first)

        #expect(item.dueDate == nil && item.endDate == nil)
    }

    // MARK: The closed notch counts a range by its end

    private func item(_ id: String, start: Int, end: Int?) -> NookTodoItem {
        NookTodoItem(
            id: id, title: "Task \(id)", dueDate: F.moment(start, in: calendar), isCompleted: false, listName: "List",
            endDate: end.map { F.moment($0, in: calendar) }
        )
    }

    private func notices(_ items: [NookTodoItem], day: Int = 15) -> [NookTodoDueNotice.Wording] {
        NookTodoDueNotice.notices(
            items: items, now: F.moment(day, 10, in: calendar), calendar: calendar, shown: NookTodoDueShown()
        ).map(\.wording)
    }

    @Test func aRangeThatStartedAndHasNotEndedIsNotOverdue() {
        #expect(notices([item("a", start: 10, end: 20)]).isEmpty)
    }

    @Test func aRangeIsOverdueOnceItsEndHasPassed() {
        #expect(notices([item("a", start: 10, end: 12)]) == [.overdue(count: 1)])
    }

    @Test func aRangeStillRunningOnItsLastDayIsNotOverdueYet() {
        #expect(notices([item("a", start: 10, end: 15)]).isEmpty)
        #expect(notices([item("a", start: 10, end: 15)], day: 16) == [.overdue(count: 1)])
    }

    @Test func aRangeThatStartsTodayIsDueToday() {
        #expect(notices([item("a", start: 15, end: 20)]) == [.oneDue(title: "Task a")])
    }

    @Test func aSingleDatePastIsStillOverdue() {
        #expect(notices([item("a", start: 10, end: nil)]) == [.overdue(count: 1)])
    }

    @Test func theCountMixesRangesAndDatesByTheirOwnDeadline() {
        let list = [
            item("range-running", start: 10, end: 20),
            item("range-ended", start: 9, end: 13),
            item("single", start: 11, end: nil),
        ]

        #expect(notices(list) == [.overdue(count: 2)])
    }

    // MARK: The offline copy keeps the end

    @Test func theOfflineCopyKeepsARangesEnd() throws {
        let original = item("a", start: 10, end: 20)
        let snapshot = NotionTodoSnapshot(
            dataSourceID: "ds", databaseTitle: "To-Do", savedAt: F.moment(15, in: calendar), items: [original]
        )

        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(NotionTodoSnapshot.self, from: data)

        #expect(restored.items.first?.endDate == original.endDate)
        #expect(restored.items.first?.dueDate == original.dueDate)
    }

    @Test func aCopySavedBeforeRangesWereReadStillLoads() throws {
        let json = """
        {"dataSourceID":"ds","databaseTitle":"To-Do","savedAt":780000000,
         "tasks":[{"id":"a","title":"Old","dueDate":780000000}]}
        """

        let restored = try JSONDecoder().decode(NotionTodoSnapshot.self, from: Data(json.utf8))

        #expect(restored.items.first?.endDate == nil)
        #expect(restored.items.first?.title == "Old")
    }
}
