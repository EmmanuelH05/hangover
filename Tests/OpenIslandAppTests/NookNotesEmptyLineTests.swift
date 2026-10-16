import Foundation
import Testing
@testable import OpenIslandApp

/// What the empty Notes card says about the new note shortcut (N11). It named
/// Control Option J whether or not macOS had given Hangover the keys, so a
/// press that did nothing was Hangover's doing. Now the keys are named only
/// when the shortcut is live.
@MainActor
@Suite struct NookNotesEmptyLineTests {
    @Test func onlyAShortcutMacOSHoldsIsNamed() {
        #expect(NookNoteListRules.emptyLine(hotkey: .ready) == .shortcut)
        let notWorking: [NookNoteHotkeyStatus] = [
            .inactive, .failed(code: -9878), .usedBySystem,
            .invalid(.needsModifiers), .invalid(.usedByAnotherShortcut),
        ]
        for status in notWorking {
            #expect(NookNoteListRules.emptyLine(hotkey: status) == .settings, "\(status)")
        }
    }

    @Test func theCardNamesTheKeysWhenTheShortcutWorks() {
        let controller = NookNoteHotkeyController(defaults: MemoryDefaults())
        controller.activate(registrar: FakeDesignHotkeyRegistrar())
        #expect(controller.status == .ready)

        let text = NookNotesList.emptyText(controller, lang: LanguageManager.shared)

        #expect(text.contains(controller.displayText))
        #expect(controller.displayText == "⌃⌥J")
    }

    @Test func theCardPointsToSettingsWhenMacOSRefusedTheKeys() {
        let registrar = FakeDesignHotkeyRegistrar()
        registrar.refusalCode = -9878
        let controller = NookNoteHotkeyController(defaults: MemoryDefaults())
        controller.activate(registrar: registrar)
        #expect(controller.status == .failed(code: -9878))

        let text = NookNotesList.emptyText(controller, lang: LanguageManager.shared)

        #expect(!text.contains("⌃⌥J"), "the line names a shortcut that does nothing: \(text)")
        #expect(!text.contains("%@"))
        #expect(text == LanguageManager.shared.t(NookNoteListRules.EmptyLine.settings.key))
    }

    @Test func theCardPointsToSettingsBeforeTheAppHasAskedMacOS() {
        let controller = NookNoteHotkeyController(defaults: MemoryDefaults())
        #expect(controller.status == .inactive)

        let text = NookNotesList.emptyText(controller, lang: LanguageManager.shared)

        #expect(!text.contains("⌃⌥J"))
    }

    @Test func theSettingsLineHasNoPlaceholderAndPointsToSettingsInEnglish() throws {
        let english = try HangoverBrandTests.table("en")
        let line = try #require(english[NookNoteListRules.EmptyLine.settings.key])
        #expect(!line.contains("%@"))
        #expect(line.contains("Settings"))
        #expect(try #require(english[NookNoteListRules.EmptyLine.shortcut.key]).contains("%@"))
    }
}
