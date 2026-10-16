import Foundation
import Testing
@testable import OpenIslandApp

/// The pure rules for notes as Markdown files (D70): the title, the file
/// name, the front matter and the order.
@Suite struct NookNoteFilesTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }()

    static func stamp(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)) ?? .distantPast
    }

    // MARK: Title

    @Test func theTitleIsTheFirstLine() {
        #expect(NookNoteFiles.title(from: "Groceries\nmilk\neggs") == "Groceries")
        #expect(NookNoteFiles.title(from: "One line only") == "One line only")
    }

    @Test func blankLinesAndSpacesAboveTheFirstLineDoNotCount() {
        #expect(NookNoteFiles.title(from: "\n\n   \n  Plan the week  \nmore") == "Plan the week")
    }

    @Test func aMarkdownHeadingMarkIsNotPartOfTheTitle() {
        #expect(NookNoteFiles.title(from: "# Quick Notes\n\n- a") == "Quick Notes")
        #expect(NookNoteFiles.title(from: "### Deep") == "Deep")
        // A tag is not a heading.
        #expect(NookNoteFiles.title(from: "#idea for later") == "#idea for later")
    }

    @Test func aLineOfMarksAloneIsSkipped() {
        #expect(NookNoteFiles.title(from: "##\nReal title") == "Real title")
    }

    @Test func textWithNothingInItHasNoTitleAndIsEmpty() {
        #expect(NookNoteFiles.title(from: "") == "")
        #expect(NookNoteFiles.title(from: " \n\t\n ") == "")
        #expect(!NookNoteFiles.hasContent(" \n\t\n "))
        #expect(NookNoteFiles.hasContent(" a "))
    }

    // MARK: File names

    @Test func aNameKeepsWordsAndDropsWhatAFileCannotHold() {
        #expect(NookNoteFiles.cleanName(from: "Q3 plan: budget/hiring?") == "Q3 plan budget hiring")
        #expect(NookNoteFiles.cleanName(from: "a\\b*c\"d<e>f|g") == "a b c d e f g")
        #expect(NookNoteFiles.cleanName(from: "see [[Other note]] #1 ^ref") == "see Other note 1 ref")
    }

    @Test func spacesCollapseAndDotsAndSpacesAtTheEndsGo() {
        #expect(NookNoteFiles.cleanName(from: "  many    spaces  ") == "many spaces")
        #expect(NookNoteFiles.cleanName(from: "..hidden.") == "hidden")
        #expect(NookNoteFiles.cleanName(from: "line one\ttab") == "line one tab")
    }

    @Test func aTitleWithNothingUsableIsUntitled() {
        #expect(NookNoteFiles.cleanName(from: "") == "Untitled")
        #expect(NookNoteFiles.cleanName(from: "///") == "Untitled")
        #expect(NookNoteFiles.fileName(forTitle: "???", taken: []) == "Untitled.md")
    }

    @Test func aNameIsAtMostSixtyCharacters() {
        let long = String(repeating: "abcdefghij ", count: 12)
        let name = NookNoteFiles.cleanName(from: long)

        #expect(name.count <= 60)
        #expect(!name.hasSuffix(" "))
        #expect(NookNoteFiles.fileName(forTitle: long, taken: []).count <= 60 + 3)
    }

    @Test func aClashGetsANumberAndStaysWithinSixty() {
        #expect(NookNoteFiles.fileName(forTitle: "Plan", taken: []) == "Plan.md")
        #expect(NookNoteFiles.fileName(forTitle: "Plan", taken: ["Plan.md"]) == "Plan 2.md")
        #expect(NookNoteFiles.fileName(forTitle: "Plan", taken: ["Plan.md", "Plan 2.md"]) == "Plan 3.md")

        let long = String(repeating: "x", count: 80)
        let first = NookNoteFiles.fileName(forTitle: long, taken: [])
        let second = NookNoteFiles.fileName(forTitle: long, taken: [first])
        #expect(second != first)
        #expect(second.dropLast(3).count <= 60, "the name with its number stays within sixty")
        #expect(second.hasSuffix(" 2.md"))
    }

    @Test func aClashIsFoundWithoutRegardToCase() {
        #expect(NookNoteFiles.fileName(forTitle: "plan", taken: ["PLAN.md"]) == "plan 2.md")
    }

    @Test func aFileIsRenamedOnlyWhenItsTitleChanged() {
        #expect(NookNoteFiles.fileName("Plan.md", stillFits: "Plan"))
        #expect(NookNoteFiles.fileName("plan.md", stillFits: "Plan"), "case alone is not a change")
        #expect(NookNoteFiles.fileName("Plan 2.md", stillFits: "Plan"), "a clash number is not a change")
        #expect(NookNoteFiles.fileName("Chapter 2.md", stillFits: "Chapter 2"))
        #expect(!NookNoteFiles.fileName("Plan.md", stillFits: "Plan the week"))
        #expect(!NookNoteFiles.fileName("Plan 2.md", stillFits: "Plan the week"))
        #expect(NookNoteFiles.fileName("Untitled.md", stillFits: "///"))

        let long = String(repeating: "word ", count: 30)
        let numbered = NookNoteFiles.fileName(forTitle: long, taken: [NookNoteFiles.fileName(forTitle: long, taken: [])])
        #expect(NookNoteFiles.fileName(numbered, stillFits: long), "a cut name with a number still fits its long title")
    }

    @Test func theStemOfAFileNameLosesOnlyItsExtension() {
        #expect(NookNoteFiles.stem(of: "Plan 2.md") == "Plan 2")
        #expect(NookNoteFiles.stem(of: "notes.txt") == "notes.txt")
    }

    // MARK: Front matter

    @Test func aFileCarriesBothDatesAndTheNoteBelow() {
        let created = Self.stamp(2026, 10, 15, 9, 41)
        let updated = Self.stamp(2026, 10, 15, 9, 45, 30)

        let text = NookNoteFiles.render(body: "Groceries\nmilk\n", created: created, updated: updated, calendar: Self.calendar)

        #expect(text == """
        ---
        created: 2026-10-15T09:41:00
        updated: 2026-10-15T09:45:30
        ---
        Groceries
        milk

        """)
        let parsed = NookNoteFiles.parse(text, calendar: Self.calendar)
        #expect(parsed.created == created)
        #expect(parsed.updated == updated)
        #expect(parsed.body == "Groceries\nmilk\n")
        #expect(parsed.otherFrontMatter.isEmpty)
    }

    @Test func otherFrontMatterIsKeptWhenAFileIsWrittenAgain() {
        let text = """
        ---
        tags: [idea, work]
        created: 2026-10-01
        aliases:
          - old name
        ---
        Body
        """
        let parsed = NookNoteFiles.parse(text, calendar: Self.calendar)

        #expect(parsed.otherFrontMatter == ["tags: [idea, work]", "aliases:", "  - old name"])
        #expect(parsed.created == Self.stamp(2026, 10, 1))
        #expect(parsed.updated == nil)

        let again = NookNoteFiles.render(
            body: parsed.body,
            created: parsed.created ?? .distantPast,
            updated: Self.stamp(2026, 10, 2),
            keeping: parsed.frontMatter,
            calendar: Self.calendar
        )
        #expect(again.contains("tags: [idea, work]\ncreated: 2026-10-01\naliases:\n  - old name\nupdated: 2026-10-02T00:00:00\n---\nBody"))
    }

    /// N18: Obsidian's lines come back as they were, in their places, with
    /// the blank lines between them.
    @Test func frontMatterIsKeptLineForLineBlankLinesIncluded() {
        let text = "---\ntags: [a]\n\naliases:\n  - x\n\ncreated: 2026-10-01T08:00:00\nupdated: 2026-10-01T08:00:00\ncssclasses: wide\n---\nBody"
        let parsed = NookNoteFiles.parse(text, calendar: Self.calendar)

        let again = NookNoteFiles.render(
            body: parsed.body, created: .distantPast, updated: Self.stamp(2026, 10, 2, 9),
            keeping: parsed.frontMatter, calendar: Self.calendar
        )

        #expect(again == "---\ntags: [a]\n\naliases:\n  - x\n\ncreated: 2026-10-01T08:00:00\nupdated: 2026-10-02T09:00:00\ncssclasses: wide\n---\nBody")
    }

    /// N18: a creation date Hangover cannot read is not Hangover's to replace.
    @Test func aCreatedLineHangoverCannotReadIsKeptAsItWas() {
        let text = "---\ncreated: last Tuesday\ntags: [a]\n---\nBody"
        let parsed = NookNoteFiles.parse(text, calendar: Self.calendar)
        #expect(parsed.created == nil)

        let again = NookNoteFiles.render(
            body: parsed.body, created: Self.stamp(2026, 10, 5), updated: Self.stamp(2026, 10, 6),
            keeping: parsed.frontMatter, calendar: Self.calendar
        )

        #expect(again.hasPrefix("---\ncreated: last Tuesday\ntags: [a]\nupdated: 2026-10-06T00:00:00\n---\n"))
        #expect(!again.contains("2026-10-05"))
    }

    /// N18: a creation date written as a day only stays a day only.
    @Test func aCreatedLineKeepsItsFormAndQuotes() {
        let text = "---\ncreated: \"2026-10-01\"\n---\nBody"
        let parsed = NookNoteFiles.parse(text, calendar: Self.calendar)

        let again = NookNoteFiles.render(
            body: parsed.body, created: Self.stamp(2026, 10, 1), updated: Self.stamp(2026, 10, 2),
            keeping: parsed.frontMatter, calendar: Self.calendar
        )

        #expect(again.contains("created: \"2026-10-01\"\n"))
    }

    @Test func aFileWithOnlyOtherFrontMatterGetsTheDatesAfterIt() {
        let again = NookNoteFiles.render(
            body: "Body", created: Self.stamp(2026, 10, 1), updated: Self.stamp(2026, 10, 2),
            keeping: ["tags: [a]"], calendar: Self.calendar
        )

        #expect(again == "---\ntags: [a]\ncreated: 2026-10-01T00:00:00\nupdated: 2026-10-02T00:00:00\n---\nBody")
    }

    @Test func aFileWithoutFrontMatterIsAllBody() {
        let parsed = NookNoteFiles.parse("Just text\n---\nnot front matter", calendar: Self.calendar)

        #expect(parsed.body == "Just text\n---\nnot front matter")
        #expect(parsed.created == nil && parsed.updated == nil)
    }

    @Test func frontMatterThatNeverClosesIsAllBody() {
        let text = "---\ncreated: 2026-10-01\nno closing line"
        #expect(NookNoteFiles.parse(text, calendar: Self.calendar).body == text)
    }

    @Test func datesMayBeWrittenInTheFormsAnotherProgramUses() {
        let calendar = Self.calendar
        #expect(NookNoteFiles.date(from: "2026-10-15", calendar: calendar) == Self.stamp(2026, 10, 15))
        #expect(NookNoteFiles.date(from: "2026-10-15 09:41", calendar: calendar) == Self.stamp(2026, 10, 15, 9, 41))
        #expect(NookNoteFiles.date(from: "2026-10-15T09:41", calendar: calendar) == Self.stamp(2026, 10, 15, 9, 41))
        #expect(NookNoteFiles.date(from: "2026-10-15T09:41:07", calendar: calendar) == Self.stamp(2026, 10, 15, 9, 41, 7))
        let quoted = NookNoteFiles.parse("---\ncreated: \"2026-10-15\"\n---\nx", calendar: calendar)
        #expect(quoted.created == Self.stamp(2026, 10, 15))
    }

    @Test func textThatIsNotADateIsNil() {
        let calendar = Self.calendar
        for text in ["", "yesterday", "2026-10", "2026-13-01", "2026-02-31", "2026-10-15T25", "2026-10-15T09:41:00Z", "10/15/2026"] {
            #expect(NookNoteFiles.date(from: text, calendar: calendar) == nil, "\(text) should not read as a date")
        }
    }

    @Test func theTimeZoneOfTheCalendarSetsTheClockOnTheFile() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let moment = Self.stamp(2026, 10, 15, 9, 41)

        let la = NookNoteFiles.dateText(moment, calendar: Self.calendar)
        let gmt = NookNoteFiles.dateText(moment, calendar: utc)

        #expect(la == "2026-10-15T09:41:00")
        #expect(gmt == "2026-10-15T16:41:00")
        #expect(NookNoteFiles.date(from: gmt, calendar: utc) == moment)
    }

    // MARK: Order

    private func note(_ id: String, _ text: String, updated: Date) -> NookNote {
        NookNote(id: id, text: text, created: updated, updated: updated)
    }

    @Test func theNewestEditIsFirst() {
        let notes = [
            note("a.md", "A", updated: Self.stamp(2026, 10, 1)),
            note("c.md", "C", updated: Self.stamp(2026, 10, 3)),
            note("b.md", "B", updated: Self.stamp(2026, 10, 2)),
        ]

        #expect(NookNoteFiles.ordered(notes).map(\.id) == ["c.md", "b.md", "a.md"])
    }

    @Test func notesEditedTogetherKeepASteadyOrder() {
        let same = Self.stamp(2026, 10, 1)
        let notes = [
            note("z.md", "banana", updated: same),
            note("y.md", "Apple", updated: same),
            note("x.md", "apple", updated: same),
        ]

        let once = NookNoteFiles.ordered(notes).map(\.id)
        #expect(once == NookNoteFiles.ordered(notes.reversed()).map(\.id))
        #expect(once.last == "z.md", "banana comes after both apples")
    }

    @Test func aNoteEditedElsewhereRisesEvenWhenItsFrontMatterIsOld() {
        let old = Self.stamp(2026, 10, 1)
        let edited = Self.stamp(2026, 10, 9)

        #expect(NookNoteFiles.lastEdit(frontMatterUpdated: old, fileModified: edited, created: old) == edited)
        #expect(NookNoteFiles.lastEdit(frontMatterUpdated: edited, fileModified: old, created: old) == edited)
        #expect(NookNoteFiles.lastEdit(frontMatterUpdated: nil, fileModified: edited, created: old) == edited)
        #expect(NookNoteFiles.lastEdit(frontMatterUpdated: nil, fileModified: nil, created: old) == old)
        #expect(NookNoteFiles.lastEdit(frontMatterUpdated: nil, fileModified: nil, created: nil) == .distantPast)
    }

    // MARK: The old Quick Notes file

    @Test func theOldFileBecomesOneNoteTitledQuickNotes() throws {
        let old = "# Quick Notes\n\n- **2026-10-12 09:41** Call mom\n- **2026-10-12 10:02** Buy milk\n"

        let text = try #require(NookNoteFiles.importedText(fromOldFile: old))

        #expect(NookNoteFiles.title(from: text) == "Quick Notes")
        #expect(text == "# Quick Notes\n\n- **2026-10-12 09:41** Call mom\n- **2026-10-12 10:02** Buy milk\n")
    }

    @Test func aPickedFileWithNoHeadingGetsTheTitleOnTop() throws {
        let text = try #require(NookNoteFiles.importedText(fromOldFile: "- **2026-10-12 09:41** only line\n"))

        #expect(text == "# Quick Notes\n\n- **2026-10-12 09:41** only line\n")
    }

    @Test func anOldFileWithNothingButItsHeadingIsNotImported() {
        #expect(NookNoteFiles.importedText(fromOldFile: "# Quick Notes\n\n") == nil)
        #expect(NookNoteFiles.importedText(fromOldFile: "") == nil)
        #expect(NookNoteFiles.importedText(fromOldFile: "  \n\n") == nil)
    }
}
