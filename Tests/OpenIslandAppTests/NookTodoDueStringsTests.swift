import Foundation
import Testing
@testable import OpenIslandApp

/// Every line the to-do due dates add, in all three languages (D69).
@Suite struct NookTodoDueStringsTests {
    /// The keys added under `/* To-do due dates (D69) */`.
    private static let newKeys = [
        "nook.todo.due.today", "nook.todo.due.tomorrow", "nook.todo.due.pick", "nook.todo.due.none",
        "nook.todo.due.button", "nook.todo.due.clear", "nook.todo.due.pickColumn", "nook.todo.due.unavailable",
        "nook.todo.due.notice.one", "nook.todo.due.notice.many",
        "nook.todo.due.notice.overdue.one", "nook.todo.due.notice.overdue.many",
        "nook.todo.due.remind", "nook.todo.due.remind.note",
    ]

    /// The to-do line of the features tour, changed in place.
    private static let tourKey = "onboarding.feature.todoDue"

    @Test(arguments: HangoverBrandTests.languages)
    func everyNewLineIsThereAndTheTourLineIsFilledIn(language: String) throws {
        let table = try HangoverBrandTests.table(language)

        for key in Self.newKeys + [Self.tourKey] {
            let value = try #require(table[key], "\(language) is missing \(key)")
            #expect(!value.isEmpty, "\(language) \(key) is empty")
        }
    }

    @Test func theEnglishLinesHaveNoDashAndNoSo() throws {
        let table = try HangoverBrandTests.table("en")

        for key in Self.newKeys + [Self.tourKey] {
            let line = try #require(table[key])
            #expect(!line.contains("\u{2014}") && !line.contains("\u{2013}"), "\(key) has a dash")
            #expect(!line.lowercased().split(whereSeparator: { !$0.isLetter }).contains("so"), "\(key) says so")
        }
    }

    @Test func theTourLineNamesTheCalendarButtonAndTheReminder() throws {
        let line = try #require(try HangoverBrandTests.table("en")[Self.tourKey])

        #expect(line.contains("calendar button"))
        #expect(line.contains("reminds you"))
    }

    @Test func theSwitchAndItsHelpAreWhatTheSpecSays() throws {
        let table = try HangoverBrandTests.table("en")

        #expect(table["nook.todo.due.remind"] == "Remind me on the due day")
        #expect(table["nook.todo.due.pickColumn"] == "Pick a Due column in Settings to add dates.")
    }
}
