import Foundation
import Testing
@testable import OpenIslandApp

/// The demo mode with the new editor (D70): a recording types a note key by
/// key, and the note is saved. Nothing here shows a window.
@MainActor
@Suite(.noNewWindows)
struct NookNoteDemoTests {
    private static func doors(_ fixture: DemoFixture, typist: DemoTypist = DemoTypist()) -> AppDemoDoors {
        AppDemoDoors(model: fixture.model, typist: typist, openTour: {}, currentTour: { nil })
    }

    @Test func theTypeNoteStepOpensANewNoteTheWayTheNewNoteButtonDoes() {
        let fixture = DemoFixture(now: Date())
        defer { fixture.remove() }
        fixture.startSampleServices()
        let doors = Self.doors(fixture)
        #expect(!fixture.nook.notes.isEditorOpen)

        doors.perform(.typeNote("Milk"))

        #expect(fixture.nook.notes.isEditorOpen)
        #expect(fixture.nook.notes.editorText.isEmpty, "the keys come after the click")
    }

    @Test func theKeysOfANoteGoToTheTypistsLineOfTheNoteField() {
        let fixture = DemoFixture(now: Date())
        defer { fixture.remove() }
        fixture.startSampleServices()
        let typist = DemoTypist()
        let doors = Self.doors(fixture, typist: typist)

        doors.perform(.typeNote("Milk"))
        for text in ["M", "Mi", "Mil", "Milk"] { doors.type(text, into: .note) }

        #expect(typist.line(.note).text == "Milk")
        #expect(typist.line(.note).keys == 4)
    }

    @Test func aNoteTypedWithNoEditorOnScreenIsSavedAsOneNote() {
        let fixture = DemoFixture(now: Date())
        defer { fixture.remove() }
        fixture.startSampleServices()
        let doors = Self.doors(fixture)
        doors.log = { _ in }
        let before = fixture.nook.notes.notes.count

        doors.perform(.typeNote("Pick up milk\nand eggs"))
        doors.type("Pick up milk\nand eggs", into: .note)
        doors.submit(.note)

        #expect(fixture.nook.notes.notes.count == before + 1)
        #expect(fixture.nook.notes.notes.first?.title == "Pick up milk")
        #expect(fixture.nook.notes.notes.first?.text == "Pick up milk\nand eggs")
        #expect(!fixture.nook.notes.isEditorOpen, "the note was saved and the editor closed")
    }

    @Test func theSaveNoteStepSavesAWholeNoteAtOnce() {
        let fixture = DemoFixture(now: Date())
        defer { fixture.remove() }
        fixture.startSampleServices()
        let doors = Self.doors(fixture)

        doors.perform(.saveNote("Buy stamps"))

        #expect(fixture.nook.notes.notes.first?.title == "Buy stamps")
        #expect(fixture.nook.notes.savedCount == 1)
    }

    @Test func theEditorCarriesTheDemoHookAndTheNewNoteButtonTheTarget() throws {
        let editor = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Notes/NookNoteEditor.swift")
        let card = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Notes/NookNotesCard.swift")

        #expect(editor.contains(".demoTyping(.note, text: $text) { _ = store.flush() }"))
        #expect(card.contains(".demoTarget(.notesField)"))
        #expect(card.contains("withMotion(Motion.reflow) { store.beginNewNote() }"))
    }

    @Test func theSampleNotesAreFilesTheStoreReadsBack() {
        let fixture = DemoFixture(now: Date())
        defer { fixture.remove() }
        fixture.startSampleServices()

        #expect(fixture.nook.notes.notes.map(\.title) == [
            "Read chapter 6", "Send the slides tonight", "Idea: widget presets",
            "Ask about the midterm room", "Try the new cache key",
        ])
        #expect(fixture.nook.notes.notes.first(where: { $0.title == "Idea: widget presets" })?.text.contains("One for studying") == true)
    }
}
