import Foundation
import Testing
@testable import OpenIslandApp

/// The text on the notes list and how many rows each size shows (D70).
@Suite struct NookNoteListRulesTests {
    private static let calendar = NookNoteFilesTests.calendar
    private static let locale = Locale(identifier: "en_US")
    /// Thursday 2026-10-15 12:00 local.
    private static let now = NookNoteFilesTests.stamp(2026, 10, 15, 12)

    /// The English lines, as the strings file holds them.
    private static func english(_ key: String) -> String {
        switch key {
        case "nook.notes.age.now": "now"
        case "nook.notes.age.minutes": "%lldm ago"
        case "nook.notes.age.hours": "%lldh ago"
        default: key
        }
    }

    private static func text(_ date: Date, now: Date = Self.now) -> String {
        NookNoteListRules.ageText(of: date, now: now, calendar: calendar, locale: locale, string: english)
    }

    @Test func rowsPerSizeAreThreeFourAndSeven() {
        #expect(NookNoteListRules.rowCount(for: .small) == 3)
        #expect(NookNoteListRules.rowCount(for: .medium) == 4)
        #expect(NookNoteListRules.rowCount(for: .large) == 7)
    }

    @Test func aNoteEditedThisMinuteIsNow() {
        #expect(Self.text(Self.now) == "now")
        #expect(Self.text(Self.now.addingTimeInterval(-59)) == "now")
    }

    @Test func minutesCountUpToAnHour() {
        #expect(Self.text(Self.now.addingTimeInterval(-60)) == "1m ago")
        #expect(Self.text(Self.now.addingTimeInterval(-2 * 60)) == "2m ago")
        #expect(Self.text(Self.now.addingTimeInterval(-59 * 60 - 59)) == "59m ago")
    }

    @Test func hoursCountUpToADay() {
        #expect(Self.text(Self.now.addingTimeInterval(-3_600)) == "1h ago")
        #expect(Self.text(Self.now.addingTimeInterval(-5 * 3_600)) == "5h ago")
        #expect(Self.text(Self.now.addingTimeInterval(-23 * 3_600 - 59 * 60)) == "23h ago")
    }

    @Test func aDayOrMoreOldShowsTheDate() {
        #expect(Self.text(NookNoteFilesTests.stamp(2026, 10, 12, 9)) == "Oct 12")
        #expect(Self.text(Self.now.addingTimeInterval(-86_400)) == "Oct 14")
        #expect(Self.text(NookNoteFilesTests.stamp(2026, 1, 3)) == "Jan 3")
    }

    @Test func aDateInAnotherYearCarriesTheYear() {
        #expect(Self.text(NookNoteFilesTests.stamp(2025, 12, 31, 8)) == "Dec 31, 2025")
    }

    @Test func aDateAheadOfTheClockIsNow() {
        // A file synced from a Mac whose clock runs fast.
        #expect(Self.text(Self.now.addingTimeInterval(300)) == "now")
    }

    @Test func theDayFollowsTheCalendarsTimeZone() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        // 2026-10-12 20:00 in Los Angeles is already the 13th in UTC.
        let moment = NookNoteFilesTests.stamp(2026, 10, 12, 20)

        let la = NookNoteListRules.dayText(moment, now: Self.now, calendar: Self.calendar, locale: Self.locale)
        let gmt = NookNoteListRules.dayText(moment, now: Self.now, calendar: utc, locale: Self.locale)

        #expect(la == "Oct 12")
        #expect(gmt == "Oct 13")
    }
}

/// What a row says when a note has no words (D70).
@Suite struct NookNoteRowTitleTests {
    private func note(_ id: String, _ text: String) -> NookNote {
        NookNote(id: id, text: text, created: .distantPast, updated: .distantPast)
    }

    @Test func aNoteWithWordsShowsItsFirstLine() {
        #expect(NookNoteListRules.rowTitle(for: note("Plan.md", "Weekly plan\nmon"), untitled: "Untitled") == "Weekly plan")
    }

    @Test func aFileWithNoWordsShowsItsName() {
        // A file another program made and left empty.
        #expect(NookNoteListRules.rowTitle(for: note("Idea 2.md", ""), untitled: "Untitled") == "Idea 2")
        #expect(NookNoteListRules.rowTitle(for: note("Idea.MD", "  \n"), untitled: "Untitled") == "Idea")
    }

    @Test func aNoteWithNeitherIsUntitled() {
        #expect(NookNoteListRules.rowTitle(for: note("6F9619FF-8B86-D011-B42D-00C04FC964FF", ""), untitled: "Untitled") == "Untitled")
    }
}
