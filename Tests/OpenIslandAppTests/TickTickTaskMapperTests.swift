import Foundation
import Testing
@testable import OpenIslandApp

@Suite struct TickTickTaskMapperTests {
    private let losAngeles = TickTickFixtures.calendar("America/Los_Angeles")

    private func rows(_ tasks: [TickTickTask], limit: Int = 100) -> [TickTickRow] {
        TickTickTaskMapper.rows(from: tasks, listID: "p1", listName: "Work", limit: limit, calendar: losAngeles)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, in calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    // MARK: Order and filtering

    @Test func soonestDueComesFirstThenTickTicksOwnOrder() {
        let tasks = [
            TickTickTask(id: "later", title: "Later", dueDate: "2026-10-12T17:00:00+0000"),
            TickTickTask(id: "second", title: "No date, second", sortOrder: 5),
            TickTickTask(id: "sooner", title: "Sooner", dueDate: "2026-10-10T17:00:00+0000"),
            TickTickTask(id: "first", title: "No date, first", sortOrder: -9),
        ]

        #expect(rows(tasks).map(\.item.id) == ["sooner", "later", "first", "second"])
    }

    @Test func tasksWithTheSameDateAndOrderKeepOneOrder() {
        let tasks = [TickTickTask(id: "b", title: "B"), TickTickTask(id: "a", title: "A")]

        #expect(rows(tasks).map(\.item.id) == ["a", "b"])
        #expect(rows(tasks.reversed()).map(\.item.id) == ["a", "b"])
    }

    @Test func onlyOpenTasksAreShown() {
        let tasks = [
            TickTickTask(id: "open", title: "Open"),
            TickTickTask(id: "done", title: "Done", status: 2),
            TickTickTask(id: "dropped", title: "Abandoned", status: -1),
            TickTickTask(id: "note", title: "A note", kind: "NOTE"),
            TickTickTask(id: "list", title: "With a checklist", kind: "CHECKLIST"),
        ]

        #expect(Set(rows(tasks).map(\.item.id)) == ["open", "list"])
    }

    @Test func theLimitKeepsTheSoonest() {
        let tasks = (1...5).map { TickTickTask(id: "t\($0)", title: "Task", sortOrder: Int64($0)) }

        #expect(rows(tasks, limit: 2).map(\.item.id) == ["t1", "t2"])
        #expect(rows(tasks, limit: 0).isEmpty)
    }

    @Test func aRowCarriesItsListAndItsName() {
        let tasks = [
            TickTickTask(id: "own", projectID: "inbox42", title: "Has a list"),
            TickTickTask(id: "none", title: "Has none"),
        ]

        let mapped = rows(tasks)

        #expect(mapped.first { $0.item.id == "own" }?.projectID == "inbox42")
        // The list that was asked for stands in for a missing one.
        #expect(mapped.first { $0.item.id == "none" }?.projectID == "p1")
        #expect(mapped.allSatisfy { $0.item.listName == "Work" && !$0.item.isCompleted })
    }

    // MARK: Notes

    @Test func aChecklistTaskKeepsItsNoteInDesc() {
        let tasks = [
            TickTickTask(id: "plain", title: "Plain", content: "bring cash", desc: "ignored"),
            TickTickTask(id: "list", title: "Checklist", content: "ignored", desc: "for the trip", kind: "CHECKLIST"),
            TickTickTask(id: "bare", title: "No note"),
        ]

        let mapped = rows(tasks)
        let plain = mapped.first { $0.item.id == "plain" }
        let list = mapped.first { $0.item.id == "list" }

        #expect(plain?.item.notes == "bring cash")
        #expect(plain?.notesField == .content)
        #expect(list?.item.notes == "for the trip")
        #expect(list?.notesField == .desc)
        #expect(mapped.first { $0.item.id == "bare" }?.item.notes == nil)
    }

    // MARK: Dates

    @Test func bothDateShapesAreRead() throws {
        let parser = TickTickDateParser()
        let expected = try date(2019, 11, 13, 3, in: TickTickFixtures.calendar("GMT"))

        #expect(parser.date(from: "2019-11-13T03:00:00+0000") == expected)
        #expect(parser.date(from: "2019-11-13T03:00:00.000+0000") == expected)
        #expect(parser.date(from: "2019-11-12T19:00:00-0800") == expected)
        #expect(parser.date(from: "next tuesday") == nil)
        #expect(parser.date(from: "") == nil)
    }

    @Test func aTimedTaskIsDueAtItsMoment() throws {
        let task = TickTickTask(
            id: "a", title: "Call", dueDate: "2026-10-09T22:30:00+0000", timeZone: "America/Los_Angeles"
        )

        let due = try #require(TickTickTaskMapper.dueDate(of: task, calendar: losAngeles))

        #expect(losAngeles.dateComponents([.month, .day, .hour, .minute], from: due)
            == DateComponents(month: 10, day: 9, hour: 15, minute: 30))
    }

    @Test func anAllDayTaskSetInTheSameZoneIsDueThatDay() throws {
        // Midnight on October 9 in Los Angeles.
        let task = TickTickTask(
            id: "a", title: "Rent", dueDate: "2026-10-09T07:00:00.000+0000",
            isAllDay: true, timeZone: "America/Los_Angeles"
        )

        let expected = try date(2026, 10, 9, in: losAngeles)

        #expect(TickTickTaskMapper.dueDate(of: task, calendar: losAngeles) == expected)
    }

    @Test func anAllDayTaskSetInAnotherZoneKeepsItsDay() throws {
        // Midnight on October 9 in Shanghai, which is still October 8 in
        // Los Angeles. The task is for the 9th and must say so.
        let task = TickTickTask(
            id: "a", title: "Rent", dueDate: "2026-10-08T16:00:00+0000", isAllDay: true, timeZone: "Asia/Shanghai"
        )

        let expected = try date(2026, 10, 9, in: losAngeles)

        #expect(TickTickTaskMapper.dueDate(of: task, calendar: losAngeles) == expected)
    }

    @Test func anAllDayTaskWithNoZoneIsReadInTheLocalOne() throws {
        let task = TickTickTask(id: "a", title: "Rent", dueDate: "2026-10-09T07:00:00+0000", isAllDay: true)

        let expected = try date(2026, 10, 9, in: losAngeles)

        #expect(TickTickTaskMapper.dueDate(of: task, calendar: losAngeles) == expected)
    }

    @Test func anAllDayTaskOverSeveralDaysIsDueOnItsLastDay() throws {
        // Set for October 9 to 11. TickTick sends the end as midnight on the 12th.
        let task = TickTickTask(
            id: "a", title: "Trip", startDate: "2026-10-09T07:00:00+0000", dueDate: "2026-10-12T07:00:00+0000",
            isAllDay: true, timeZone: "America/Los_Angeles"
        )
        let expected = try date(2026, 10, 11, in: losAngeles)

        #expect(TickTickTaskMapper.dueDate(of: task, calendar: losAngeles) == expected)
    }

    @Test func anAllDayTaskOfOneDayIsNotMovedBack() throws {
        let task = TickTickTask(
            id: "a", title: "Rent", startDate: "2026-10-09T07:00:00+0000", dueDate: "2026-10-09T07:00:00+0000",
            isAllDay: true, timeZone: "America/Los_Angeles"
        )
        let expected = try date(2026, 10, 9, in: losAngeles)

        #expect(TickTickTaskMapper.dueDate(of: task, calendar: losAngeles) == expected)
    }

    @Test func aTimedTaskWithAStartKeepsItsDueMoment() throws {
        let task = TickTickTask(
            id: "a", title: "Call", startDate: "2026-10-09T20:00:00+0000", dueDate: "2026-10-09T22:30:00+0000"
        )
        let due = try #require(TickTickTaskMapper.dueDate(of: task, calendar: losAngeles))

        #expect(losAngeles.component(.hour, from: due) == 15)
    }

    @Test func aTaskWithChecklistItemsKeepsItsNoteInDescWhateverItsKind() throws {
        let task = try TickTickFixtures.decodeTask(
            "{\"id\":\"a\",\"title\":\"Pack\",\"content\":\"x\",\"desc\":\"for the trip\",\"items\":[{\"id\":\"i1\",\"title\":\"Socks\"}]}"
        )
        let plain = try TickTickFixtures.decodeTask("{\"id\":\"b\",\"title\":\"Call\",\"content\":\"x\",\"items\":[]}")

        #expect(task.hasChecklistItems)
        #expect(TickTickTaskMapper.notesField(of: task) == .desc)
        #expect(plain.hasChecklistItems == false)
        #expect(TickTickTaskMapper.notesField(of: plain) == .content)
    }

    @Test func aDateThatCannotBeReadLeavesTheTaskUndated() {
        let tasks = [TickTickTask(id: "a", title: "Odd", dueDate: "sometime")]

        #expect(rows(tasks).first?.item.dueDate == nil)
        #expect(rows(tasks).count == 1)
    }

    // MARK: Offline copy

    @Test func theOfflineCopyGivesBackTheSameRows() throws {
        let mapped = rows([
            TickTickTask(id: "a", projectID: "inbox42", title: "Rent", content: "by the 5th",
                         dueDate: "2026-10-09T22:30:00+0000"),
            TickTickTask(id: "b", title: "Pack", desc: "for the trip", kind: "CHECKLIST"),
        ])
        let snapshot = TickTickTodoSnapshot(
            listID: "p1", listName: "Work", savedAt: Date(timeIntervalSince1970: 1_800_000_000), rows: mapped
        )

        let decoded = try JSONDecoder().decode(TickTickTodoSnapshot.self, from: JSONEncoder().encode(snapshot))

        #expect(decoded == snapshot)
        #expect(decoded.rows == mapped)
    }
}
