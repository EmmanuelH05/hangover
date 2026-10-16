import Foundation
@testable import OpenIslandApp

/// Calendars, moments and rows for the due-date rules (D69). Every rule takes
/// `now` and `calendar`, so a test pins both and reads the same on every
/// machine.
enum NookTodoDueFixtures {
    static let english = Locale(identifier: "en_US")

    static func calendar(_ zone: String = "America/Los_Angeles") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    /// A moment in October 2026 unless a month is given. The 14th is a Wednesday.
    static func moment(
        _ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 10, year: Int = 2026, in calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date()
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    static func item(_ id: String, _ title: String = "Task", due: Date? = nil, done: Bool = false) -> NookTodoItem {
        NookTodoItem(id: id, title: title, dueDate: due, isCompleted: done, listName: "List")
    }
}
