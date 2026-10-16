import Foundation
import Testing
@testable import OpenIslandApp

/// Notion's years are Gregorian whatever calendar the Mac prefers (D8 of the
/// review fixes). A bare date read on a Buddhist, Japanese or ROC calendar
/// would land centuries away.
@Suite struct NotionDateCalendarTests {
    private static let zone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    private static func calendar(_ identifier: Calendar.Identifier, zone: TimeZone = zone) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = zone
        return calendar
    }

    /// Midnight of the day, worked out on a Gregorian calendar in the zone.
    private static func midnight(_ year: Int, _ month: Int, _ day: Int, zone: TimeZone = zone) -> Date? {
        let gregorian = calendar(.gregorian, zone: zone)
        return gregorian.date(from: DateComponents(year: year, month: month, day: day))
    }

    @Test(arguments: [
        Calendar.Identifier.gregorian, .buddhist, .japanese, .republicOfChina, .islamicUmmAlQura, .persian, .hebrew,
    ])
    func aBareDateIsTheSameDayOnEveryCalendar(identifier: Calendar.Identifier) throws {
        let parsed = NotionTodoMapper.parseDate("2026-10-14", calendar: Self.calendar(identifier))

        #expect(parsed == Self.midnight(2026, 10, 14), "\(identifier)")
    }

    @Test func aBareDateIsMidnightInTheCalendarsOwnZone() throws {
        let auckland = try #require(TimeZone(identifier: "Pacific/Auckland"))

        let parsed = NotionTodoMapper.parseDate("2026-10-14", calendar: Self.calendar(.buddhist, zone: auckland))

        #expect(parsed == Self.midnight(2026, 10, 14, zone: auckland))
        #expect(parsed != Self.midnight(2026, 10, 14), "not the Los Angeles midnight")
    }

    @Test func aDayThatIsNotRealIsNotADate() {
        #expect(NotionTodoMapper.parseDate("2026-02-30", calendar: Self.calendar(.gregorian)) == nil)
        #expect(NotionTodoMapper.parseDate("2026-13-01", calendar: Self.calendar(.gregorian)) == nil)
    }

    @Test func aTimestampIsTheSameMomentOnEveryCalendar() throws {
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let expected = Self.midnight(2026, 10, 14, zone: utc).map { $0.addingTimeInterval(10 * 3600) }

        for identifier in [Calendar.Identifier.gregorian, .buddhist, .japanese] {
            let parsed = NotionTodoMapper.parseDate("2026-10-14T10:00:00Z", calendar: Self.calendar(identifier))
            #expect(parsed == expected, "\(identifier)")
        }
    }

    @Test func theRowsOfAPageUseTheSameDay() throws {
        // The page reader goes through the same parse, with the Mac's calendar.
        let day = NotionTodoMapper.parseDate("2026-10-14")
        let expected = NookTodoDay.date(from: DateComponents(year: 2026, month: 10, day: 14), calendar: .current)

        #expect(day == expected)
    }
}
