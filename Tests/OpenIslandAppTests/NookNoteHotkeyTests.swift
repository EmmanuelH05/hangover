import AppKit
import Foundation
import Testing
@testable import OpenIslandApp

/// The shortcut that starts a new note from any app (D70). It is registered
/// with a fake; nothing here asks macOS for a key.
@MainActor
@Suite struct NookNoteHotkeyTests {
    private func makeController(
        defaults: UserDefaults = MemoryDefaults(),
        registrar: FakeDesignHotkeyRegistrar? = FakeDesignHotkeyRegistrar(),
        others: [AgentHotkeyCombo] = []
    ) -> (NookNoteHotkeyController, FakeDesignHotkeyRegistrar?) {
        let controller = NookNoteHotkeyController(defaults: defaults)
        controller.otherShortcuts = { others }
        if let registrar { controller.activate(registrar: registrar) }
        return (controller, registrar)
    }

    private let controlOptionJ = AgentHotkeyCombo(keyCode: 38, modifiers: [.control, .option])
    private let controlOptionK = AgentHotkeyCombo(keyCode: 40, modifiers: [.control, .option])

    // MARK: The default

    @Test func theDefaultIsControlOptionJ() {
        let (controller, _) = makeController()

        #expect(controller.combo == controlOptionJ)
        #expect(NookNoteHotkeyRules.defaultCombo == controlOptionJ)
        #expect(controller.displayText == "⌃⌥J")
        #expect(NookNoteHotkeyController.comboKey == "nook.notes.newNoteHotkey")
    }

    @Test func theDefaultIsNotTheAgentsDenyKey() {
        let agents = [AgentHotkeySettings.defaultApprove, AgentHotkeySettings.defaultDeny]

        #expect(!agents.contains(NookNoteHotkeyRules.defaultCombo))
        #expect(NookNoteHotkeyRules.problem(with: NookNoteHotkeyRules.defaultCombo, otherShortcuts: agents) == nil)
        // Control Option N is the Deny key and is taken.
        #expect(NookNoteHotkeyRules.problem(with: AgentHotkeySettings.defaultDeny, otherShortcuts: agents) == .usedByAnotherShortcut)
    }

    // MARK: Registering

    @Test func itIsHeldAsSoonAsTheAppHandsOverItsRegistrarWithoutAWidgetSwitch() {
        let (controller, registrar) = makeController()

        #expect(registrar?.registered == controlOptionJ)
        #expect(controller.status == .ready)
    }

    @Test func aBareControllerNeverRegistersAnything() {
        let (controller, _) = makeController(registrar: nil)

        #expect(controller.status == .inactive)
    }

    @Test func aPressReachesTheApp() {
        let (controller, registrar) = makeController()
        var presses = 0
        controller.onPress = { presses += 1 }

        registrar?.press()

        #expect(presses == 1)
    }

    @Test func aNewShortcutIsSavedRegisteredAndReadBack() {
        let defaults = MemoryDefaults()
        let (controller, registrar) = makeController(defaults: defaults)

        #expect(controller.setCombo(controlOptionK) == nil)

        #expect(registrar?.registered == controlOptionK)
        #expect(defaults.string(forKey: NookNoteHotkeyController.comboKey) == controlOptionK.storageValue)
        #expect(makeController(defaults: defaults).0.combo == controlOptionK)
    }

    @Test func oneModifierIsRefusedAndNothingChanges() {
        let (controller, registrar) = makeController()
        let weak = AgentHotkeyCombo(keyCode: 40, modifiers: [.shift])

        #expect(controller.setCombo(weak) == .needsModifiers)
        #expect(controller.combo == controlOptionJ)
        #expect(registrar?.registered == controlOptionJ)
    }

    @Test func aShortcutAnotherFeatureHoldsIsRefused() {
        let (controller, _) = makeController(others: [controlOptionK])

        #expect(controller.setCombo(controlOptionK) == .usedByAnotherShortcut)
        #expect(controller.combo == controlOptionJ)
    }

    @Test func macOSRefusingTheKeysIsShown() {
        let registrar = FakeDesignHotkeyRegistrar()
        registrar.refusalCode = -9878

        let (controller, _) = makeController(registrar: registrar)

        #expect(controller.status == .failed(code: -9878))
    }

    @Test func aSystemShortcutIsNotTakenOver() {
        let registrar = FakeDesignHotkeyRegistrar()
        registrar.system = [controlOptionJ]

        let (controller, _) = makeController(registrar: registrar)

        #expect(controller.status == .usedBySystem)
        #expect(registrar.registered == nil)
    }

    @Test func aSavedShortcutThatBreaksARuleIsShownAndNotHeld() {
        let defaults = MemoryDefaults()
        defaults.set(AgentHotkeyCombo(keyCode: 40, modifiers: [.shift]).storageValue, forKey: NookNoteHotkeyController.comboKey)

        let (controller, registrar) = makeController(defaults: defaults)

        #expect(controller.status == .invalid(.needsModifiers))
        #expect(registrar?.registered == nil)
    }

    @Test func nothingIsHeldWhileANewShortcutIsRecorded() {
        let (controller, registrar) = makeController()
        var told: [Bool] = []
        controller.onRecordingChange = { told.append($0) }

        controller.beginRecording()
        #expect(controller.isRecording)
        #expect(registrar?.registered == nil, "a press meant for the recorder must not start a note")

        controller.endRecording()
        #expect(told == [true, false])
        #expect(registrar?.registered == controlOptionJ)
    }

    @Test func resetGoesBackToTheDefault() {
        let defaults = MemoryDefaults()
        let (controller, _) = makeController(defaults: defaults)
        controller.setCombo(controlOptionK)

        controller.resetToDefault()

        #expect(controller.combo == controlOptionJ)
        #expect(defaults.string(forKey: NookNoteHotkeyController.comboKey) == nil)
    }

    @Test func refreshingAfterAnotherShortcutChangedLetsGoOfAKeyItNowCollidesWith() {
        var others: [AgentHotkeyCombo] = []
        let registrar = FakeDesignHotkeyRegistrar()
        let controller = NookNoteHotkeyController(defaults: MemoryDefaults())
        controller.otherShortcuts = { others }
        controller.activate(registrar: registrar)
        #expect(controller.status == .ready)

        others = [controlOptionJ]
        controller.refresh()

        #expect(controller.status == .invalid(.usedByAnotherShortcut))
        #expect(registrar.registered == nil)
    }

    @Test func eachProblemHasAMessageInEveryLanguage() throws {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let table = try HangoverBrandTests.table(language)
            for problem in [NookNoteHotkeyProblem.needsModifiers, .usedByAnotherShortcut] {
                #expect(!(table[problem.messageKey] ?? "").isEmpty, "\(language) is missing \(problem.messageKey)")
            }
        }
    }
}

/// The shortcut wired into the app (D70): it stays clear of the others and
/// they of it, and a press opens the island on a new note.
@MainActor
@Suite(.noNewWindows)
struct NookNoteHotkeyWiringTests {
    private let notesCombo = NookNoteHotkeyRules.defaultCombo

    private func wiredApp() -> AppModel {
        let app = AppModel(defaults: MemoryDefaults())
        app.wireDesignKit()
        app.wireRecord()
        app.wireNotes()
        return app
    }

    @Test func theNewNoteKeysAreNotTheAgentsToTake() {
        let app = wiredApp()
        // J sits next to the Deny key, which the agents refuse on its own.
        // K is far enough from both of their keys to reach the other check.
        let controlOptionK = AgentHotkeyCombo(keyCode: 40, modifiers: [.control, .option])
        #expect(app.nook.notes.hotkey.setCombo(controlOptionK) == nil)

        #expect(app.agentHotkeys.setCombo(controlOptionK, for: .approve) == .usedByEyedropper)
        #expect(app.agentHotkeys.setCombo(controlOptionK, for: .deny) == .usedByEyedropper)
        #expect(app.agentHotkeys.combo(for: .approve) == AgentHotkeySettings.defaultApprove)
    }

    @Test func theAgentsCannotTakeTheDefaultNewNoteKeysEither() {
        let app = wiredApp()

        // Control Option J is next to Control Option N, and refused either way.
        #expect(app.agentHotkeys.setCombo(notesCombo, for: .approve) != nil)
        #expect(app.agentHotkeys.combo(for: .approve) == AgentHotkeySettings.defaultApprove)
    }

    @Test func theNewNoteShortcutRefusesTheAgentsKeys() {
        let app = wiredApp()
        let hotkey = app.nook.notes.hotkey

        #expect(hotkey.setCombo(app.agentHotkeys.combo(for: .approve)) == .usedByAnotherShortcut)
        #expect(hotkey.setCombo(app.agentHotkeys.combo(for: .deny)) == .usedByAnotherShortcut)
        #expect(hotkey.combo == notesCombo)
    }

    @Test func recordAndTheEyedropperRefuseTheNewNoteKeysToo() {
        let app = wiredApp()

        #expect(app.nook.record.hotkey.setCombo(notesCombo) == .usedByAnotherShortcut)
        #expect(app.nook.design.hotkey.setCombo(notesCombo) == .usedByAgentShortcut)
        // And what they refused before still holds.
        #expect(app.nook.record.hotkey.combo == NookRecordHotkeyRules.defaultCombo)
        #expect(app.nook.design.hotkey.combo == nil)
    }

    @Test func recordsOwnAndTheAgentsRefusalsSurviveTheWiring() {
        let app = wiredApp()

        // Record's check still holds the agents' keys.
        #expect(app.nook.record.hotkey.setCombo(AgentHotkeySettings.defaultApprove) == .usedByAnotherShortcut)
        #expect(app.nook.design.hotkey.setCombo(AgentHotkeySettings.defaultDeny) == .usedByAgentShortcut)
    }

    @Test func recordingTheNewNoteShortcutHoldsTheAgentShortcutsBack() {
        let app = wiredApp()
        #expect(!app.agentHotkeys.isRecording)

        app.nook.notes.hotkey.beginRecording()
        #expect(app.agentHotkeys.isRecording)

        app.nook.notes.hotkey.endRecording()
        #expect(!app.agentHotkeys.isRecording)
    }

    @Test func aPressOpensTheIslandOnANewBlankNote() {
        guard !NSScreen.screens.isEmpty else { return }
        let app = wiredApp()
        app.nook.notes.start()

        app.nook.notes.hotkey.onPress?()

        #expect(app.notchStatus == .opened)
        #expect(app.showsNookPage)
        #expect(app.nook.notes.isEditorOpen)
        #expect(app.nook.notes.editorText.isEmpty)
    }

    @Test func aPressWithTheAppsRegistrarReachesTheSameDoor() {
        let app = wiredApp()
        let registrar = FakeDesignHotkeyRegistrar()
        app.nook.notes.hotkey.activate(registrar: registrar)
        #expect(registrar.registered == notesCombo)

        // The press is the same closure the wiring set.
        #expect(app.nook.notes.hotkey.onPress != nil)
    }

    @Test func theAppActivatesTheRealRegistrarOnlyOnARealLaunch() throws {
        let source = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/OpenIslandApp.swift")
        let launch = try #require(source.range(of: "if demo == nil, harnessLaunchConfiguration.scenario == nil {"))
        #expect(source[launch.upperBound...].contains("model.nook.notes.hotkey.activate(registrar: NookNoteCarbonHotkey())"))
    }

    @Test func theAppWiresNotesAfterRecord() throws {
        let source = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/AppModel.swift")
        let record = try #require(source.range(of: "        wireRecord()\n"))
        #expect(source[record.upperBound...].hasPrefix("        wireNotes()\n"))
    }
}

/// Where an open note is edited, and the room it takes (D70).
@MainActor
@Suite(.noNewWindows)
struct NookNoteEditorPlacementTests {
    @Test func aClosedEditorIsNowhere() {
        #expect(NookNoteEditorPlacement.resolve(isOpen: false, notesWidgetOnPage: true) == .hidden)
        #expect(NookNoteEditorPlacement.resolve(isOpen: false, notesWidgetOnPage: false) == .hidden)
    }

    @Test func withTheWidgetOnThePageTheEditorTakesTheCardsPlace() {
        #expect(NookNoteEditorPlacement.resolve(isOpen: true, notesWidgetOnPage: true) == .inCard)
    }

    @Test func withTheWidgetOffThePageTheEditorIsPinnedAboveTheGrid() {
        #expect(NookNoteEditorPlacement.resolve(isOpen: true, notesWidgetOnPage: false) == .pinned)
    }

    @Test func theAppModelPinsTheEditorOnlyWhenTheNotesWidgetIsOffThePage() {
        let app = AppModel(defaults: MemoryDefaults())
        let profile = app.activeAppearanceProfile
        #expect(app.nook.widgetPlacements(for: profile).contains { $0.kind == .notes })

        app.nook.notes.beginNewNote()
        #expect(!app.nookPageExtras.showsNoteEditor, "the card holds it")

        app.nook.hideWidget(.notes, for: profile)
        #expect(app.nookPageExtras.showsNoteEditor)

        app.nook.notes.closeEditor()
        #expect(!app.nookPageExtras.showsNoteEditor)
    }

    @Test func thePinnedEditorAddsItsOwnHeightAndAGapToThePage() {
        let none = NookPageExtras.none
        var pinned = NookPageExtras.none
        pinned.showsNoteEditor = true

        #expect(pinned.pinnedHeight - none.pinnedHeight == NookNoteSizes.pinnedEditorHeight + NookWidgetLayout.rowSpacing)
        #expect(pinned.pinnedHeight - none.pinnedHeight == NookNoteSizes.pinnedEditorPageHeight)
    }

    @Test func theWindowIsAsTallAsThePageWithTheEditorPinned() {
        let placements = [NookWidgetPlacement(kind: .media, size: .medium)]
        var pinned = NookPageExtras.none
        pinned.showsNoteEditor = true

        let without = NookPanelView.preferredHeight(for: placements, calendarStyle: .strip, isEditing: false)
        let with = NookPanelView.preferredHeight(for: placements, calendarStyle: .strip, isEditing: false, extras: pinned)

        #expect(with - without == NookNoteSizes.pinnedEditorPageHeight)
    }

    @Test func anEditorAloneOnAPageWithNoWidgetsNeedsNoEmptyStateLine() {
        var pinned = NookPageExtras.none
        pinned.showsNoteEditor = true

        let empty = NookPanelView.preferredHeight(for: [], calendarStyle: .strip, isEditing: false)
        let alone = NookPanelView.preferredHeight(for: [], calendarStyle: .strip, isEditing: false, extras: pinned)

        #expect(empty == NookPanelView.verticalPadding * 2 + NookPanelView.emptyHeight)
        #expect(alone == NookPanelView.verticalPadding * 2 + NookNoteSizes.pinnedEditorPageHeight)
    }
}
