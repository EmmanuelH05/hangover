import Foundation
import Testing
@testable import OpenIslandApp

/// The card's lines with two or more apps on (T13, B7), without any view.
@MainActor @Suite struct NookTodoSectionsTests {
    private typealias Sections = NookTodoCardSections
    private typealias Entry = NookTodoCardSections.Entry

    private func item(_ id: String, _ title: String) -> NookTodoItem {
        NookTodoItem(id: id, title: title, dueDate: nil, isCompleted: false, listName: "")
    }

    private func ready(_ kind: NookTodoSourceKind, _ titles: [String]) -> Entry {
        Entry(kind: kind, connection: .ready, items: titles.map { item("\(kind.rawValue):\($0)", $0) })
    }

    /// The frames' six tasks (T4): two in Reminders, two in Asana, one in
    /// monday, one in TickTick.
    private var sample: [Entry] {
        [
            ready(.reminders, ["Finish problem set 3", "Renew parking permit"]),
            ready(.asana, ["Write the sprint notes", "Email the TA"]),
            ready(.monday, ["Review the pull request"]),
            ready(.tickTick, ["Book flights"]),
        ]
    }

    private func shape(_ sections: Sections) -> [String] {
        sections.lines.map {
            switch $0 {
            case .header(let kind): "header \(kind.rawValue)"
            case .row(_, let item): "row \(item.title)"
            case .unavailable(let kind, _): "unavailable \(kind.rawValue)"
            case .more(let count): "more \(count)"
            }
        }
    }

    @Test func everythingFitsAtLargeWhenTheBudgetIsBigEnough() {
        let sections = Sections(entries: Array(sample.prefix(2)), budget: 8, size: .large)
        #expect(sections.lines.count == 6)
        #expect(sections.hidden == 0)
        #expect(sections.openCount == 4)
        #expect(!shape(sections).contains { $0.hasPrefix("more") })
    }

    @Test func headersTakeLinesFromTheBudgetAtMedium() {
        let sections = Sections(entries: sample, budget: NookTodoCard.maxRows(for: .medium), size: .medium)
        #expect(shape(sections) == ["header reminders", "row Finish problem set 3", "row Renew parking permit", "more 4"])
        #expect(sections.hidden == 4)
        #expect(sections.openCount == 6)
    }

    @Test func theLargeCardCutsWithAMoreLineThatCountsRowsNotShown() {
        let sections = Sections(entries: sample, budget: NookTodoCard.maxRows(for: .large), size: .large)
        #expect(sections.lines.count <= 8)
        #expect(shape(sections).last == "more \(sections.hidden)")
        let rowsShown = sections.lines.filter { if case .row = $0 { true } else { false } }.count
        #expect(rowsShown + sections.hidden == 6)
        #expect(shape(sections).prefix(6) == [
            "header reminders", "row Finish problem set 3", "row Renew parking permit",
            "header asana", "row Write the sprint notes", "row Email the TA",
        ])
    }

    @Test func theSmallCardStopsWithoutAMoreLine() {
        let sections = Sections(entries: sample, budget: NookTodoCard.maxRows(for: .small), size: .small)
        #expect(shape(sections) == ["header reminders", "row Finish problem set 3", "row Renew parking permit"])
        #expect(sections.hidden == 4)
    }

    @Test func aHeaderLeftAloneByTheCutIsNotDrawn() {
        let entries = [ready(.reminders, ["One"]), ready(.asana, ["Two", "Three"])]
        let sections = Sections(entries: entries, budget: 3, size: .small)
        #expect(shape(sections) == ["header reminders", "row One"])
        #expect(sections.hidden == 2)
    }

    @Test func anUnavailableAppShowsItsHeaderAndOneDimLine() {
        let down = Entry(kind: .asana, connection: .unavailable(message: "Add a token"), items: [])
        let sections = Sections(entries: [ready(.reminders, ["One"]), down], budget: 8, size: .large)
        #expect(shape(sections) == ["header reminders", "row One", "header asana", "unavailable asana"])
        #expect(sections.openCount == 1)
        #expect(sections.hidden == 0)
        #expect(sections.lines.last == .unavailable(.asana, message: "Add a token"))
    }

    @Test func anUnavailableAppKeepsItsItemsOutOfTheCount() {
        let stale = Entry(
            kind: .monday, connection: .unavailable(message: "Offline"), items: [item("monday:1", "Old")]
        )
        let sections = Sections(entries: [ready(.reminders, ["One"]), stale], budget: 8, size: .large)
        #expect(sections.openCount == 1)
        #expect(!shape(sections).contains("row Old"))
    }

    @Test func aCutThatOnlyDropsAnUnavailableLineHasNoMoreLine() {
        let down = Entry(kind: .asana, connection: .unavailable(message: "Offline"), items: [])
        let sections = Sections(entries: [ready(.reminders, ["One", "Two"]), down], budget: 4, size: .medium)
        #expect(shape(sections) == ["header reminders", "row One", "row Two"])
        #expect(sections.hidden == 0)
    }

    @Test func anAppWithNothingOpenKeepsItsHeader() {
        let sections = Sections(entries: [ready(.reminders, []), ready(.asana, ["Two"])], budget: 8, size: .large)
        #expect(shape(sections) == ["header reminders", "header asana", "row Two"])
    }

    @Test func theNoticeTakesALineFromTheBudget() {
        let withNotice = NookTodoCard.rowLimit(for: .medium, hasNotice: true)
        let sections = Sections(entries: sample, budget: withNotice, size: .medium)
        #expect(sections.lines.count == 3)
        #expect(shape(sections).last == "more 5")
    }

    @Test func oneAppIsJustHeaderAndRowsAndNeverChangesTheOneAppCard() {
        // The card draws today's list, not these lines, whenever one app is
        // on (T12): the hub says so, and this type is never asked.
        let defaults = MemoryDefaults()
        let hub = NookTodoHub(defaults: defaults)
        #expect(!hub.hasManyEnabled)
        hub.setEnabled(.tickTick, true)
        #expect(hub.hasManyEnabled)
        hub.setEnabled(.tickTick, false)
        #expect(!hub.hasManyEnabled)
        let one = Sections(entries: [ready(.reminders, ["A", "B", "C"])], budget: 4, size: .medium)
        #expect(shape(one) == ["header reminders", "row A", "row B", "row C"])
        #expect(one.hidden == 0)
    }

    /// T15: the app with the earliest due task leads, overdue first, undated
    /// last, and a tie keeps the Settings order.
    @Test func sectionsComeInOrderOfUrgency() {
        func dated(_ kind: NookTodoSourceKind, _ title: String, daysFromNow: Int?) -> Entry {
            let due = daysFromNow.map { Date(timeIntervalSince1970: 1_000_000 + Double($0) * 86_400) }
            return Entry(kind: kind, connection: .ready, items: [
                NookTodoItem(id: "\(kind.rawValue):\(title)", title: title, dueDate: due, isCompleted: false, listName: ""),
            ])
        }
        let entries = [
            dated(.reminders, "Renew parking permit", daysFromNow: nil),
            dated(.tickTick, "Book flights", daysFromNow: 3),
            dated(.asana, "Write the sprint notes", daysFromNow: -1),
            dated(.monday, "Review the pull request", daysFromNow: 1),
        ]
        let ordered = Sections.byUrgency(entries).map(\.kind)
        #expect(ordered == [.asana, .monday, .tickTick, .reminders])

        // At medium the overdue task is the one that shows, not the first app in Settings.
        let medium = Sections(entries: entries, budget: 4, size: .medium)
        #expect(shape(medium) == ["header asana", "row Write the sprint notes", "more 3"])

        // Nothing dated anywhere: the Settings order holds.
        let undated = Sections.byUrgency(sample).map(\.kind)
        #expect(undated == [.reminders, .asana, .monday, .tickTick])

        // An app that is not ready never leads, whatever it holds: it
        // sorts with the undated ones, in the Settings order.
        let down = Entry(kind: .canvas, connection: .unavailable(message: "Offline"), items: [])
        #expect(Sections.byUrgency([down] + entries).map(\.kind) == [.asana, .monday, .tickTick, .canvas, .reminders])
    }

    @Test func noEntriesDrawNothing() {
        let sections = Sections(entries: [], budget: 4, size: .medium)
        #expect(sections.lines.isEmpty)
        #expect(sections.openCount == 0)
    }
}
