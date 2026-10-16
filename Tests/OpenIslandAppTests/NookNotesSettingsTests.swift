import Foundation
import Testing
@testable import OpenIslandApp

/// Settings, Nook, Notes (D70): the three places notes can go, the folder
/// picker, the one-way line for Apple Notes and the shortcut recorder.
@MainActor
@Suite struct NookNotesSettingsTests {
    @Test func theChoicesAreTheObsidianFolderAppleNotesAndBoth() throws {
        #expect(NookNotesSaveTo.allCases.map { NookNotesSettings.titleKey(for: $0) } == [
            "nook.notes.saveTo.folder", "nook.notes.saveTo.appleNotes", "nook.notes.saveTo.both",
        ])
        let english = try HangoverBrandTests.table("en")
        #expect(NookNotesSaveTo.allCases.map { english[NookNotesSettings.titleKey(for: $0)] } == [
            "Obsidian folder", "Apple Notes", "Both",
        ])
    }

    @Test func eachChoiceHasItsOwnLineUnderThePicker() throws {
        let english = try HangoverBrandTests.table("en")
        let lines = NookNotesSaveTo.allCases.compactMap { english[NookNotesSettings.noteKey(for: $0)] }

        #expect(lines.count == 3)
        #expect(Set(lines).count == 3)
        // Apple Notes is one way, and the line says what that costs (N19).
        #expect(lines[1].contains("do not come back, and are replaced the next time you edit that note in Hangover"))
    }

    @Test func theFolderRowsShowForTheFolderAndForBothButNotForAppleNotesAlone() {
        #expect(NookNotesSaveTo.folder.usesFolder && !NookNotesSaveTo.folder.usesAppleNotes)
        #expect(!NookNotesSaveTo.appleNotes.usesFolder && NookNotesSaveTo.appleNotes.usesAppleNotes)
        #expect(NookNotesSaveTo.both.usesFolder && NookNotesSaveTo.both.usesAppleNotes)
    }

    @Test func theSettingsOfferTheFolderPickerTheShortcutAndANewFolderPickerStartingInObsidian() throws {
        let source = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Notes/NookNotesSettings.swift")

        #expect(source.contains("ForEach(NookNotesSaveTo.allCases)"))
        // The chooser is shared with the problem lines on the card and in the editor.
        #expect(source.contains("NookNotesFolderChooser.choose(for: store)"))
        let chooser = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Notes/NookNotesFolderChooser.swift")
        #expect(chooser.contains("panel.canChooseDirectories = true"))
        #expect(chooser.contains("panel.canChooseFiles = false"))
        #expect(chooser.contains("NookNoteLocations.pickerStart("))
        #expect(chooser.contains("store.setFolder(url)"))
        #expect(source.contains("nook.notes.hotkey.setCombo(combo)"))
        #expect(source.contains("nook.notes.hotkey.beginRecording()"))
    }

    @Test func theSettingsPaneListsTheNotesSection() throws {
        let source = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Views/NookSettingsPane.swift")
        #expect(source.contains("NookNotesSettings(nook: nook)"))
    }

    @Test func theObsidianFolderTheyPickFromIsTheOneInICloud() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(NookNoteLocations.obsidianDocuments(home: home).path
            == "/Users/someone/Library/Mobile Documents/iCloud~md~obsidian/Documents")
    }

    @Test func aFolderChosenInSettingsMovesNothingAndTheListFollows() throws {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Old place")
        store.closeEditor()
        let elsewhere = harness.home.appendingPathComponent("Elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try "Found there\nbody".write(to: elsewhere.appendingPathComponent("Found there.md"), atomically: true, encoding: .utf8)

        store.setFolder(elsewhere)

        #expect(store.notes.map(\.title) == ["Found there"])
        #expect(harness.fileNames() == ["Old place.md"], "the old note stayed where it was")
    }

    @Test func switchingToAppleNotesAndBackKeepsEachListWhereItBelongs() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("In the folder")
        store.closeEditor()

        store.setSaveTo(.appleNotes)
        #expect(store.notes.isEmpty, "the record of Apple notes starts empty")
        store.beginNewNote()
        store.edit("In Apple Notes")
        store.closeEditor()
        await harness.settle(store)
        #expect(store.notes.map(\.title) == ["In Apple Notes"])

        store.setSaveTo(.folder)
        #expect(store.notes.map(\.title) == ["In the folder"])
    }
}
