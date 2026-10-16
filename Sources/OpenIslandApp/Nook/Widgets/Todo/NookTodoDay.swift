import Foundation

/// A due date is a whole day, never a time (D69). These are the helpers every
/// source shares to turn a moment into a day and a day back into a moment.
///
/// A day is year, month and day in the Gregorian calendar, whatever calendar
/// the user prefers: Notion and TickTick take Gregorian years, and a Buddhist
/// calendar would send 2569. Every function takes the calendar whose clock
/// decides what day it is.
enum NookTodoDay {
    /// The day a moment falls on, on the calendar's clock.
    static func components(of date: Date, calendar: Calendar) -> DateComponents {
        let parts = gregorian(like: calendar).dateComponents([.year, .month, .day], from: date)
        return DateComponents(year: parts.year, month: parts.month, day: parts.day)
    }

    /// The year, month and day of `day` when they make a real day, and nothing
    /// else: a time of day is dropped, and February 30th or a month 13 gives nil.
    static func normalized(_ day: DateComponents?) -> DateComponents? {
        guard let day, let year = day.year, let month = day.month, let dayOfMonth = day.day else { return nil }
        let wanted = DateComponents(year: year, month: month, day: dayOfMonth)
        // Foundation rolls an impossible day over to a real one. A day that
        // does not come back the same was not real.
        // GMT has no clock changes, so no day can be skipped by one.
        var checker = Calendar(identifier: .gregorian)
        checker.timeZone = .gmt
        guard let date = checker.date(from: wanted), components(of: date, calendar: checker) == wanted else {
            return nil
        }
        return wanted
    }

    /// `2026-03-05`, the form Notion takes. Nil unless `day` is a real day.
    static func isoString(_ day: DateComponents?) -> String? {
        guard let day = normalized(day), let year = day.year, let month = day.month, let dayOfMonth = day.day else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }

    /// The start of `day` on the calendar's clock. Nil unless `day` is real.
    static func date(from day: DateComponents, calendar: Calendar) -> Date? {
        guard let day = normalized(day) else { return nil }
        let local = gregorian(like: calendar)
        return local.date(from: day).map { local.startOfDay(for: $0) }
    }

    /// The day of a moment as `2026-10-09`. Keys sort in time order.
    static func key(of date: Date, calendar: Calendar) -> String {
        isoString(components(of: date, calendar: calendar)) ?? ""
    }

    /// A Gregorian calendar on the same clock as `calendar`.
    private static func gregorian(like calendar: Calendar) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = calendar.timeZone
        return result
    }
}
