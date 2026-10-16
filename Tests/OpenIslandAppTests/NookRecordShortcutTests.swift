import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import OpenIslandApp

// MARK: - Where the bubble starts (R10)

@Suite struct NookRecordBubblePlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func theBubbleSitsAtTheAreasBottomLeftCornerInset16() {
        // The area is measured from the display's top left, the panel from
        // the screen's bottom left: 900 - (200 + 300) = 400 up from the bottom.
        let area = CGRect(x: 100, y: 200, width: 400, height: 300)
        let frame = NookFaceCamLayout.startFrame(insideArea: area, onScreen: screen)
        #expect(frame.origin == CGPoint(x: 116, y: 416))
        #expect(frame.size == CGSize(width: 160, height: 160))
        // Inside the area, with the inset on its left and bottom.
        #expect(frame.minX - area.minX == 16)
        #expect(frame.maxX < area.maxX && frame.maxY < screen.maxY - area.minY)
    }

    @Test func aDisplayThatIsNotAtTheOriginIsAccountedFor() {
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let area = CGRect(x: 50, y: 100, width: 800, height: 600)
        let frame = NookFaceCamLayout.startFrame(insideArea: area, onScreen: second)
        // Across: 1440 + 50 + 16. Up: the display's top is at -200 + 1080 = 880, the
        // area ends 100 + 600 = 700 below it, so 180 up, and 16 more for the inset.
        let expectedX: CGFloat = 1506
        #expect(frame.origin.x == expectedX)
        let expectedY: CGFloat = 196
        #expect(frame.origin.y == expectedY)
    }

    @Test func aBubbleTooBigForASmallAreaIsMadeToFit() {
        let area = CGRect(x: 0, y: 0, width: 200, height: 150)
        let frame = NookFaceCamLayout.startFrame(insideArea: area, onScreen: screen)
        #expect(frame.width == CGFloat(150 - 32))
        #expect(frame.maxX <= area.maxX - 16)
        // A sliver of an area still gets a bubble, as small as one goes.
        let sliver = NookFaceCamLayout.startFrame(insideArea: CGRect(x: 0, y: 0, width: 40, height: 40), onScreen: screen)
        #expect(sliver.width == NookFaceCamLayout.smallestFitted)
    }

    @Test func aSizeThePersonLeftItAtIsKeptWhereItFits() {
        let frame = NookFaceCamLayout.startFrame(
            insideArea: CGRect(x: 0, y: 0, width: 900, height: 700), onScreen: screen, diameter: 240
        )
        #expect(frame.width == 240)
    }

    @Test func onlyAnAreaTargetStartsInsideAnArea() {
        let rect = CGRect(x: 1, y: 2, width: 300, height: 200)
        #expect(NookFaceCamPlacement.of(.area(3, rect)) == .insideArea(3, rect))
        #expect(NookFaceCamPlacement.of(.display(3)) == .corner)
        #expect(NookFaceCamPlacement.of(.pickedWindow) == .corner)
    }
}

// MARK: - Free space (R12)

@Suite struct NookRecordSpaceWatchTests {
    @Test func spaceUnderTheLimitStopsAndSpaceAboveItDoesNot() {
        var watch = NookRecordSpaceWatch()
        #expect(watch.check(freeBytes: 999_999_999) == .stop)
        #expect(watch.check(freeBytes: 1_000_000_000) == .fine)
    }

    @Test func spaceThatCannotBeReadIsSaidOnceNotEverySecond() {
        var watch = NookRecordSpaceWatch()
        #expect(watch.check(freeBytes: nil) == .unreadable(isFirst: true))
        #expect(watch.check(freeBytes: nil) == .unreadable(isFirst: false))
        #expect(watch.check(freeBytes: nil) == .unreadable(isFirst: false))
        // It never stops a recording: nobody knows the disk is full.
        #expect(watch.check(freeBytes: 5_000_000_000) == .fine)
    }

    @Test func aNewRecordingStartsWithAFreshWatch() {
        var first = NookRecordSpaceWatch()
        _ = first.check(freeBytes: nil)
        var second = NookRecordSpaceWatch()
        #expect(second.check(freeBytes: nil) == .unreadable(isFirst: true))
    }
}

// MARK: - The shortcuts keep clear of each other (R11)

@MainActor @Suite struct NookRecordShortcutControllerTests {
    let controlOptionR = NookRecordHotkeyRules.defaultCombo
    let controlOptionK = AgentHotkeyCombo(keyCode: 40, modifiers: [.control, .option])

    func recordController(registrar: RecordFakeRegistrar = RecordFakeRegistrar()) -> (NookRecordHotkeyController, RecordFakeRegistrar) {
        let controller = NookRecordHotkeyController(defaults: MemoryDefaults())
        controller.activate(registrar: registrar)
        return (controller, registrar)
    }

    @Test func theRecordControllerSaysWhenItsKeysOrLiveStateChange() {
        let (controller, _) = recordController()
        var told = 0
        controller.onShortcutsChange = { told += 1 }

        controller.setLive(true)
        #expect(told == 1)
        controller.setLive(true)
        #expect(told == 1, "no change, nothing to tell")
        controller.setCombo(controlOptionK)
        #expect(told == 2)
        controller.setCombo(controlOptionK)
        #expect(told == 2)
        controller.resetToDefault()
        #expect(told == 3)
        controller.refresh()
        #expect(told == 3, "a refresh must not start the other side's refresh, or the two would ping-pong")
        #expect(controller.setCombo(AgentHotkeyCombo(keyCode: 40, modifiers: [.shift])) == .needsModifiers)
        #expect(told == 3, "a refused shortcut changes nothing")
        controller.setLive(false)
        #expect(told == 4)
    }

    @Test func aRefreshChecksAgainstTheOthersAsTheyAreNow() {
        let (controller, registrar) = recordController()
        var others: [AgentHotkeyCombo] = [controlOptionR]
        controller.otherShortcuts = { others }
        controller.setLive(true)
        #expect(controller.status == .invalid(.usedByAnotherShortcut))
        #expect(registrar.registered.isEmpty)

        others = []
        #expect(controller.status == .invalid(.usedByAnotherShortcut), "nothing re-ran it yet")
        controller.refresh()
        #expect(controller.status == .ready)
        #expect(registrar.registered == [controlOptionR])
    }

    @Test func theDesignControllerSaysWhenItsKeysOrLiveStateChange() {
        let controller = NookDesignHotkeyController(defaults: MemoryDefaults())
        var told = 0
        controller.onShortcutsChange = { told += 1 }

        controller.setCombo(controlOptionK)
        #expect(told == 1)
        controller.setLive(true)
        #expect(told == 2)
        controller.setLive(true)
        #expect(told == 2)
        controller.refresh()
        #expect(told == 2)
        controller.clear()
        #expect(told == 3)
        controller.clear()
        #expect(told == 3)
    }

    @Test func aRecordShortcutThatBrokeARuleHoldsNothingBack() {
        let (controller, _) = recordController()
        controller.otherShortcuts = { [controlOptionR] }
        controller.setLive(true)
        #expect(controller.status.isInvalid)
        #expect(NookRecordHotkeyStatus.ready.isInvalid == false)
        #expect(NookRecordHotkeyStatus.invalid(.needsModifiers).isInvalid)
    }
}

/// `AppModel.wireRecord` ties the two controllers together. This uses the real
/// app model on a store of its own: no window opens, no key is held, the
/// design kit reads an empty folder of its own.
@MainActor @Suite(.noNewWindows) struct NookRecordShortcutWiringTests {
    let combo = NookRecordHotkeyRules.defaultCombo

    func wired() -> (app: AppModel, record: NookRecordModel, registrar: RecordFakeRegistrar) {
        let app = AppModel(defaults: MemoryDefaults())
        app.wireDesignKit()
        app.wireRecord()
        let record = app.nook.record
        let registrar = RecordFakeRegistrar()
        record.hotkey.activate(registrar: registrar)
        record.start(nook: app.nook)
        return (app, record, registrar)
    }

    @Test func theEyedropperCannotTakeRecordsKeysWhileRecordIsOn() {
        let (app, record, _) = wired()
        let kit = app.nook.design
        app.nook.setWidget(.record, enabled: true)
        #expect(record.isLive)

        #expect(kit.hotkey.agentShortcuts().contains(combo))
        #expect(kit.hotkey.setCombo(combo) == .usedByAgentShortcut)
        #expect(kit.hotkey.combo == nil)

        // The agents' shortcuts are still checked as before.
        #expect(kit.hotkey.agentShortcuts().contains(AgentHotkeySettings.defaultApprove))
    }

    @Test func recordsKeysAreFreeToTheEyedropperWhileRecordIsOff() {
        let (app, record, _) = wired()
        #expect(!record.isLive)
        #expect(!app.nook.design.hotkey.agentShortcuts().contains(combo))
        #expect(app.nook.design.hotkey.setCombo(combo) == nil)
    }

    @Test func recordChecksAgainAfterTheEyedropperGoesOff() {
        let (app, record, registrar) = wired()
        let kit = app.nook.design
        // Saved while Record was off, which is allowed.
        #expect(kit.hotkey.setCombo(combo) == nil)
        kit.setLive(true)
        app.nook.setWidget(.record, enabled: true)
        #expect(record.hotkey.status == .invalid(.usedByAnotherShortcut))
        // The first to hold the keys keeps them.
        #expect(!kit.hotkey.status.isInvalid)
        #expect(registrar.registered.isEmpty)

        kit.setLive(false)

        // The widget switch was the only thing that moved, and Record noticed.
        #expect(record.hotkey.status == .ready)
        #expect(registrar.registered == [combo])
    }

    @Test func neitherShortcutGivesWayToTheOtherAndLeavesBothDead() {
        let (app, record, registrar) = wired()
        let kit = app.nook.design
        #expect(kit.hotkey.setCombo(combo) == nil)
        app.nook.setWidget(.record, enabled: true)
        #expect(record.hotkey.status == .ready)

        // The eyedropper comes on later with the keys Record already holds.
        kit.setLive(true)

        #expect(kit.hotkey.status == .invalid(.usedByAgentShortcut))
        #expect(record.hotkey.status == .ready)
        #expect(registrar.registered == [combo])
    }

    // MARK: Whose keys the eyedropper's standing line names (X5 wording)

    @Test func theEyedropperStandingLineNamesRecordWhenRecordHoldsTheKeys() {
        let (app, _, _) = wired()
        let kit = app.nook.design
        kit.start(nook: app.nook)
        let lang = LanguageManager.shared
        #expect(kit.hotkey.setCombo(combo) == nil)
        app.nook.setWidget(.record, enabled: true)

        kit.setLive(true)

        #expect(kit.hotkey.status == .invalid(.usedByAgentShortcut))
        #expect(kit.standingNotice?.text == lang.t("nook.design.standing.record"))
        #expect(kit.standingNotice?.text != lang.t("nook.design.standing.agent"))
        #expect(kit.standingNotice?.opensSettings == true)
        #expect(kit.standingNotice?.text == "Record uses these keys. Open Settings.")
    }

    @Test func theEyedropperStandingLineStillNamesTheAgentsWhenAnAgentHoldsTheKeys() {
        let (app, _, _) = wired()
        let kit = app.nook.design
        kit.start(nook: app.nook)
        let lang = LanguageManager.shared
        let keys = AgentHotkeyCombo(keyCode: 9, modifiers: [.control, .option])
        // Saved while no agent shortcut had these keys, which is allowed.
        #expect(kit.hotkey.setCombo(keys) == nil)
        app.agentHotkeys.setCombo(keys, for: .approve)
        // Record is on, with keys of its own.
        app.nook.setWidget(.record, enabled: true)

        kit.setLive(true)

        #expect(kit.hotkey.status == .invalid(.usedByAgentShortcut))
        #expect(kit.standingNotice?.text == lang.t("nook.design.standing.agent"))
    }

    @Test func theEyedropperStandingLineNamesNotesWhenTheNewNoteShortcutHoldsTheKeys() {
        let (app, _, _) = wired()
        let kit = app.nook.design
        let lang = LanguageManager.shared
        let notesKeys = NookNoteHotkeyRules.defaultCombo
        // Saved before Notes took its keys, which is allowed.
        #expect(kit.hotkey.setCombo(notesKeys) == nil)
        app.wireNotes()
        kit.start(nook: app.nook)

        kit.setLive(true)

        #expect(kit.hotkey.status == .invalid(.usedByAgentShortcut))
        #expect(kit.holder(of: notesKeys) == .notes)
        #expect(kit.standingNotice?.text == lang.t("nook.design.standing.notes"))
        #expect(kit.standingNotice?.text == "Notes uses these keys. Open Settings.")
    }

    @Test func theEyedropperSettingsRowNamesWhoeverHoldsTheKeys() {
        let (app, _, _) = wired()
        app.wireNotes()
        let kit = app.nook.design
        kit.start(nook: app.nook)
        app.nook.setWidget(.record, enabled: true)
        let notesKeys = NookNoteHotkeyRules.defaultCombo
        let agentKeys = AgentHotkeySettings.defaultApprove

        #expect(kit.hotkey.setCombo(combo) == .usedByAgentShortcut)
        #expect(kit.problemMessageKey(.usedByAgentShortcut, combo: combo) == "nook.design.hotkey.problem.record")
        #expect(kit.hotkey.setCombo(notesKeys) == .usedByAgentShortcut)
        #expect(kit.problemMessageKey(.usedByAgentShortcut, combo: notesKeys) == "nook.design.hotkey.problem.notes")
        #expect(kit.hotkey.setCombo(agentKeys) == .usedByAgentShortcut)
        #expect(kit.problemMessageKey(.usedByAgentShortcut, combo: agentKeys) == "nook.design.hotkey.problem.agent")
        // A rule broken by the keys themselves names nobody.
        #expect(kit.problemMessageKey(.needsModifiers, combo: combo) == NookDesignHotkeyProblem.needsModifiers.messageKey)
    }

    @Test func everyHolderHasBothSentencesInEveryLanguageWithNoDash() throws {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let table = try NookRecordStringsTests.table(language)
            for holder in NookTakenKeysHolder.allCases {
                for key in [holder.standingKey, holder.problemKey] {
                    let value = try #require(table[key], "\(language) has no \(key)")
                    #expect(!value.isEmpty)
                    #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"))
                }
            }
        }
    }

    @Test func theRecordSentenceExistsInEveryLanguageAndHasNoDash() throws {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let table = try NookRecordStringsTests.table(language)
            let value = try #require(table["nook.design.standing.record"], "\(language) has no sentence for Record")
            #expect(!value.isEmpty)
            #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"))
            #expect(value != table["nook.design.standing.agent"], "\(language) gives Record the agents' sentence")
        }
    }

    @Test func recordsKeysStopCountingAgainstTheEyedropperWhenRecordGoesOff() {
        let (app, record, _) = wired()
        let kit = app.nook.design
        app.nook.setWidget(.record, enabled: true)
        #expect(kit.hotkey.agentShortcuts().contains(combo))
        app.nook.setWidget(.record, enabled: false)
        #expect(!record.isLive)
        #expect(!kit.hotkey.agentShortcuts().contains(combo))
    }
}

// MARK: - A shortcut macOS refuses (R12)

@MainActor @Suite(.noNewWindows) struct NookRecordHotkeyRefusalTests {
    let combo = NookRecordHotkeyRules.defaultCombo
    let other = AgentHotkeyCombo(keyCode: 40, modifiers: [.control, .option])

    func controller(outcome: AgentHotkeyRegistrationOutcome = .registered, system: Set<AgentHotkeyCombo> = []) -> (NookRecordHotkeyController, RecordFakeRegistrar) {
        let registrar = RecordFakeRegistrar()
        registrar.outcome = outcome
        registrar.system = system
        let controller = NookRecordHotkeyController(defaults: MemoryDefaults())
        controller.activate(registrar: registrar)
        return (controller, registrar)
    }

    @Test func aRefusedShortcutIsToldOnceNotOnEveryTry() {
        let (controller, _) = controller(outcome: .failed(code: -9878))
        var refusals: [NookRecordHotkeyStatus] = []
        controller.onRefused = { refusals.append($0) }

        controller.setLive(true)
        #expect(refusals == [.failed(code: -9878)])

        // Tries again on a refresh, and it fails the same way: no second notice.
        controller.refresh()
        controller.refresh()
        #expect(refusals.count == 1)
        #expect(controller.status == .failed(code: -9878))
    }

    @Test func aDifferentRefusedShortcutIsToldAgain() {
        let (controller, _) = controller(outcome: .failed(code: -9878))
        var told = 0
        controller.onRefused = { _ in told += 1 }
        controller.setLive(true)
        controller.setCombo(other)
        #expect(told == 2)
    }

    @Test func switchingTheWidgetOffAndOnIsANewTry() {
        let (controller, _) = controller(outcome: .failed(code: -9878))
        var told = 0
        controller.onRefused = { _ in told += 1 }
        controller.setLive(true)
        controller.setLive(false)
        controller.setLive(true)
        #expect(told == 2)
    }

    @Test func aShortcutMacOSUsesItselfIsToldOnceToo() {
        let (controller, registrar) = controller(system: [combo])
        var refusals: [NookRecordHotkeyStatus] = []
        controller.onRefused = { refusals.append($0) }
        controller.setLive(true)
        controller.refresh()
        #expect(refusals == [.usedBySystem])
        #expect(registrar.registered.isEmpty)
    }

    @Test func aWorkingShortcutIsNeverToldAboutAndAFixedOneToldAgainIfItBreaksLater() {
        let (controller, registrar) = controller()
        var told = 0
        controller.onRefused = { _ in told += 1 }
        controller.setLive(true)
        #expect(told == 0)
        #expect(controller.status == .ready)

        // It breaks later: the keys are taken by an app that started after.
        registrar.outcome = .failed(code: -9878)
        controller.setCombo(other)
        #expect(told == 1)
    }

    @Test func nothingIsToldWhileTheWidgetIsOff() {
        let (controller, _) = controller(outcome: .failed(code: -9878))
        var told = 0
        controller.onRefused = { _ in told += 1 }
        controller.setCombo(other)
        #expect(told == 0)
    }

    @Test func theNookShowsTheRefusalWhereThePersonIsLooking() {
        let registrar = RecordFakeRegistrar()
        registrar.outcome = .failed(code: -9878)
        let defaults = MemoryDefaults()
        let record = NookRecordModel(
            recorder: FakeRecorder(), defaults: defaults, folder: NookRecordModelTests.folder,
            createFolder: { _ in }, sleep: { _ in }, fileExists: { _ in false }
        )
        let nook = NookModel(record: record, defaults: defaults, looksForImportedGIF: false, asksMacOSForAccess: false)
        record.start(nook: nook)
        record.activate(NookRecordServices(
            bubble: RecordFakeBubble(), areaPicker: RecordFakeAreaPicker(rect: nil), hotkeyRegistrar: registrar
        ))

        nook.setWidget(.record, enabled: true)

        #expect(record.hotkey.status == .failed(code: -9878))
        #expect(nook.transient?.text == LanguageManager.shared.t("nook.record.hotkey.refused"))
    }

    @Test func theRefusalSentenceIsInEveryLanguage() throws {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let table = try NookRecordStringsTests.table(language)
            let value = table["nook.record.hotkey.refused"] ?? ""
            #expect(!value.isEmpty, "\(language) has no refusal sentence")
            #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"))
        }
        let en = try NookRecordStringsTests.table("en")
        #expect(!(en["nook.record.hotkey.refused"] ?? "").lowercased().split(separator: " ").contains("so"))
    }
}
