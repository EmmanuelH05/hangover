import AppKit
import EventKit
import Foundation
import Testing
@testable import OpenIslandApp

// Edge cases for the open island stepping below a macOS permission prompt
// (D52): the count, the requests that raise it, the first send to Notes, and
// the panel's level when the island opens, closes and pops around a prompt.

// MARK: - Helpers

/// Holds a made-up prompt up until a test lets go of it.
@MainActor
private final class PromptGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false
    private(set) var isOpen = false

    func wait() async {
        if isOpen { return }
        isWaiting = true
        await withCheckedContinuation { continuation = $0 }
        isWaiting = false
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

/// Polls until `condition` holds. False when it never did.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<1_000 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// A stand-in for the Notes app that keeps a send waiting until it is told
/// to go on, and records how many sends came.
private final class GatedNotesWriter: NookAppleNotesWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false
    private var failure: NookAppleNotesError?
    private var calls = 0
    private var finished = 0

    var callCount: Int { lock.withLock { calls } }
    var finishedCount: Int { lock.withLock { finished } }

    func fail(with error: NookAppleNotesError?) {
        lock.withLock { failure = error }
    }

    func append(lineHTML: String, toNoteTitled title: String) async throws {
        lock.withLock { calls += 1 }
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                if isReleased { return true }
                waiting.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
        let error = lock.withLock { () -> NookAppleNotesError? in
            finished += 1
            return failure
        }
        if let error { throw error }
    }

    /// Lets every send go on, now and from here on.
    func release() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isReleased = true
            defer { waiting.removeAll() }
            return waiting
        }
        pending.forEach { $0.resume() }
    }
}

// MARK: - The count

@MainActor
@Suite(.noNewWindows)
struct EdgeCaseSystemPromptCountTests {
    private static func nook() -> NookModel {
        NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
    }

    @Test func answersWithoutQuestionsNeverPushTheCountBelowZero() {
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }

        for _ in 0..<5 { nook.systemPromptEnded() }
        #expect(told.isEmpty)

        // One prompt now needs exactly one answer. A count that had gone
        // negative would still say a prompt was up after it.
        nook.systemPromptBegan()
        #expect(nook.isSystemPromptUp)
        nook.systemPromptEnded()
        #expect(nook.isSystemPromptUp == false)
        #expect(told == [true, false])
    }

    @Test func aThousandPromptsNeedAThousandAnswersAndTheIslandIsToldOnceEachWay() {
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }

        for _ in 0..<1_000 { nook.systemPromptBegan() }
        #expect(told == [true])
        for _ in 0..<999 { nook.systemPromptEnded() }
        #expect(nook.isSystemPromptUp)
        #expect(told == [true])
        nook.systemPromptEnded()
        #expect(nook.isSystemPromptUp == false)
        #expect(told == [true, false])
    }

    /// A long run of begins and ends in a fixed scrambled order. The island is
    /// told when the count crosses zero and at no other time, and what it was
    /// last told is what the model says.
    @Test func theIslandIsToldEveryCrossingOfZeroAndNothingElseInAnyOrder() {
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }

        var seed: UInt64 = 0x2545F4914F6CDD1D
        var depth = 0
        var crossings = 0
        for _ in 0..<2_000 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let isBegin = (seed >> 33) % 5 < 3
            if isBegin {
                if depth == 0 { crossings += 1 }
                depth += 1
                nook.systemPromptBegan()
            } else {
                if depth == 1 { crossings += 1 }
                depth = max(0, depth - 1)
                nook.systemPromptEnded()
            }
            #expect(nook.isSystemPromptUp == (depth > 0))
        }

        #expect(told.count == crossings)
        #expect(told.first == true)
        #expect(zip(told, told.dropFirst()).allSatisfy { $0 != $1 }, "up and down alternate")
        #expect(told.last == nook.isSystemPromptUp)
    }

    // MARK: A hook that does something itself

    @Test func aHookThatEndsThePromptItWasToldAboutLeavesTheCountClean() {
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { isUp in
            told.append(isUp)
            if isUp { nook.systemPromptEnded() }
        }

        nook.systemPromptBegan()
        #expect(nook.isSystemPromptUp == false)
        #expect(told == [true, false])

        // And the next prompt behaves the same.
        nook.systemPromptBegan()
        #expect(told == [true, false, true, false])
    }

    @Test func aHookThatBeginsAnotherPromptWhenToldTheLastOneEndedLeavesItUp() {
        let nook = Self.nook()
        var told: [Bool] = []
        var hasReplied = false
        nook.onSystemPromptChange = { isUp in
            told.append(isUp)
            if !isUp, !hasReplied {
                hasReplied = true
                nook.systemPromptBegan()
            }
        }

        nook.systemPromptBegan()
        nook.systemPromptEnded()

        #expect(told == [true, false, true])
        #expect(nook.isSystemPromptUp, "what the island heard last is what the model says")
        nook.systemPromptEnded()
        #expect(nook.isSystemPromptUp == false)
        #expect(told == [true, false, true, false])
    }

    @Test func aHookThatBeginsAPromptOfItsOwnWhenToldOneWentUpCountsBothAndNeedsBothAnswers() {
        let nook = Self.nook()
        var told: [Bool] = []
        var hasAdded = false
        nook.onSystemPromptChange = { isUp in
            told.append(isUp)
            if isUp, !hasAdded {
                hasAdded = true
                nook.systemPromptBegan()
            }
        }

        nook.systemPromptBegan()
        #expect(told == [true], "the second one went up while a prompt was already up")
        nook.systemPromptEnded()
        #expect(nook.isSystemPromptUp)
        nook.systemPromptEnded()
        #expect(nook.isSystemPromptUp == false)
        #expect(told == [true, false])
    }

    /// A hook installed while a prompt is up never hears that it went up. It
    /// hears only the answer, which the panel treats as already down.
    @Test func aHookReplacedWhileAPromptIsUpHearsOnlyTheEnd() {
        let nook = Self.nook()
        var first: [Bool] = []
        var second: [Bool] = []
        nook.onSystemPromptChange = { first.append($0) }
        nook.systemPromptBegan()

        nook.onSystemPromptChange = { second.append($0) }
        nook.systemPromptEnded()

        #expect(first == [true])
        #expect(second == [false])
    }

    @Test func eachModelCountsItsOwnPrompts() {
        let one = Self.nook()
        let two = Self.nook()
        one.systemPromptBegan()
        #expect(one.isSystemPromptUp)
        #expect(two.isSystemPromptUp == false)
        two.systemPromptEnded()
        #expect(one.isSystemPromptUp, "an answer in another model ends nothing here")
    }
}

// MARK: - The requests

@MainActor
@Suite(.noNewWindows)
struct EdgeCaseSystemPromptRequestTests {
    private static func nook() -> NookModel {
        NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
    }

    // MARK: Calendar and Reminders at once

    /// Both prompts are up, the calendar's is answered first, and the island
    /// must stay below the Reminders prompt that is still up.
    @Test func calendarAndRemindersAskedTogetherKeepTheIslandLoweredUntilTheLastIsAnswered() async {
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }

        let calendarGate = PromptGate()
        let remindersGate = PromptGate()
        let calendarPermission = FakeEventKitPermission(status: .notDetermined, answer: .denied)
        let remindersPermission = FakeEventKitPermission(status: .notDetermined, answer: .denied)
        calendarPermission.whilePromptIsUp = { await calendarGate.wait() }
        remindersPermission.whilePromptIsUp = { await remindersGate.wait() }
        let calendar = NookCalendarService(access: calendarPermission.access, defaults: MemoryDefaults())
        let reminders = NookRemindersService(access: remindersPermission.access, defaults: MemoryDefaults())
        calendar.start(nook: nook)
        reminders.start(nook: nook)

        let calendarAsk = Task { @MainActor in await calendar.requestAccessIfUndecided() }
        #expect(await eventually { calendarGate.isWaiting })
        let remindersAsk = Task { @MainActor in await reminders.requestAccessIfUndecided() }
        #expect(await eventually { remindersGate.isWaiting })
        #expect(told == [true], "the second prompt is not a second trip down")

        calendarGate.open()
        _ = await calendarAsk.value
        #expect(nook.isSystemPromptUp, "the Reminders prompt is still up")
        #expect(told == [true])

        remindersGate.open()
        _ = await remindersAsk.value
        #expect(nook.isSystemPromptUp == false)
        #expect(told == [true, false])
        #expect(calendarPermission.requestCount == 1)
        #expect(remindersPermission.requestCount == 1)
    }

    @Test func theSecondToAnswerEndingFirstIsTheSameAsTheFirst() async {
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }
        let calendarGate = PromptGate()
        let remindersGate = PromptGate()
        let calendarPermission = FakeEventKitPermission(status: .notDetermined)
        let remindersPermission = FakeEventKitPermission(status: .notDetermined)
        calendarPermission.whilePromptIsUp = { await calendarGate.wait() }
        remindersPermission.whilePromptIsUp = { await remindersGate.wait() }
        let calendar = NookCalendarService(access: calendarPermission.access, defaults: MemoryDefaults())
        let reminders = NookRemindersService(access: remindersPermission.access, defaults: MemoryDefaults())
        calendar.start(nook: nook)
        reminders.start(nook: nook)

        let calendarAsk = Task { @MainActor in await calendar.requestAccessIfUndecided() }
        #expect(await eventually { calendarGate.isWaiting })
        let remindersAsk = Task { @MainActor in await reminders.requestAccessIfUndecided() }
        #expect(await eventually { remindersGate.isWaiting })

        remindersGate.open()
        _ = await remindersAsk.value
        #expect(nook.isSystemPromptUp, "the calendar prompt is still up")
        calendarGate.open()
        _ = await calendarAsk.value
        #expect(nook.isSystemPromptUp == false)
        #expect(told == [true, false])
    }

    // MARK: A second request to the same service

    @Test func aSecondRequestWhileOneIsUpIsNotCountedAndDoesNotEndTheFirstEarly() async {
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }
        let gate = PromptGate()
        let permission = FakeEventKitPermission(status: .notDetermined)
        permission.whilePromptIsUp = { await gate.wait() }
        let reminders = NookRemindersService(access: permission.access, defaults: MemoryDefaults())
        reminders.start(nook: nook)

        let first = Task { @MainActor in await reminders.requestAccessIfUndecided() }
        #expect(await eventually { gate.isWaiting })

        // The tile comes into view again, the button is pressed again, the
        // widget is switched on: five more asks while the prompt is up.
        for _ in 0..<5 {
            let asked = await reminders.requestAccessIfUndecided()
            #expect(asked == false)
        }
        for _ in 0..<3 { reminders.requestAccess() }
        for _ in 0..<5 { await Task.yield() }

        #expect(permission.requestCount == 1, "macOS is asked once")
        #expect(nook.isSystemPromptUp, "the extra asks did not end the prompt")
        #expect(told == [true])

        gate.open()
        let wasAsked = await first.value
        #expect(wasAsked)
        #expect(nook.isSystemPromptUp == false)
        #expect(told == [true, false])
    }

    @Test func aRequestAfterTheAnswerIsNotCountedAtAll() async {
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }
        let permission = FakeEventKitPermission(status: .notDetermined, answer: .denied)
        let calendar = NookCalendarService(access: permission.access, defaults: MemoryDefaults())
        calendar.start(nook: nook)

        #expect(await calendar.requestAccessIfUndecided())
        #expect(await calendar.requestAccessIfUndecided() == false, "denied is an answer")

        #expect(permission.requestCount == 1)
        #expect(told == [true, false])
    }

    // MARK: A service that was never started

    @Test func aServiceNeverStartedAsksItsPermissionAndTellsTheIslandNothing() async {
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }
        let calendarPermission = FakeEventKitPermission(status: .notDetermined)
        let remindersPermission = FakeEventKitPermission(status: .notDetermined)
        let calendar = NookCalendarService(access: calendarPermission.access, defaults: MemoryDefaults())
        let reminders = NookRemindersService(access: remindersPermission.access, defaults: MemoryDefaults())

        _ = await calendar.requestAccessIfUndecided()
        _ = await reminders.requestAccessIfUndecided()

        #expect(calendarPermission.requestCount == 1)
        #expect(remindersPermission.requestCount == 1)
        #expect(told.isEmpty)
        #expect(nook.isSystemPromptUp == false)
    }

    // MARK: Pairing in the source

    /// D52 asks that anything which raises a prompt tells the island before
    /// and after. A site that begins and never ends would lower the island for
    /// good. Each file that counts has as many ends as begins, and no other
    /// file counts.
    @Test func everyFileThatCountsAPromptEndsAsManyAsItBegins() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/OpenIslandApp")
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var counted: [String: (begins: Int, ends: Int)] = [:]
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let begins = text.components(separatedBy: ".systemPromptBegan()").count - 1
            let ends = text.components(separatedBy: ".systemPromptEnded()").count - 1
            if begins > 0 || ends > 0 { counted[url.lastPathComponent] = (begins, ends) }
        }

        let expected: Set<String> = [
            "NookCalendarService.swift", "NookRemindersService.swift", "NookNotesService.swift",
            "AppModel+Onboarding.swift", "AppModel.swift",
            // The designer kit's file dialogs (D53).
            "NookDesignEditorPanel.swift",
            // The designer kit's Paste buttons, when macOS asks before a read.
            "NookDesignKit+Clipboard.swift",
            // Link to MP3: the folder chooser in its Settings section, and
            // the Paste button when macOS asks before a read.
            "NookLinkAudioFolderPicker.swift",
            "NookLinkAudioPaste.swift",
        ]
        #expect(Set(counted.keys) == expected, "a new site that counts a prompt belongs in this list")
        for (file, count) in counted {
            #expect(count.begins == count.ends, "\(file) begins \(count.begins) and ends \(count.ends)")
        }
    }
}

// MARK: - Notes

@MainActor
@Suite(.noNewWindows)
struct EdgeCaseSystemPromptNotesTests {
    @MainActor
    private final class Harness {
        let defaults = MemoryDefaults()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EdgeCaseSystemPromptNotes-\(UUID().uuidString)", isDirectory: true)
        var fileURL: URL { folder.appendingPathComponent("notes.md") }

        init(destination: NookNotesDestination = .appleNotes) {
            defaults.set(destination.rawValue, forKey: NookNotesService.destinationDefaultsKey)
        }

        deinit { try? FileManager.default.removeItem(at: folder) }

        func service(writer: any NookAppleNotesWriting) -> NookNotesService {
            NookNotesService(defaults: defaults, appleNotes: writer, fileURL: fileURL)
        }
    }

    private static func nook() -> NookModel {
        NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
    }

    @Test func severalNotesSentBeforeTheFirstAnswerRaiseOnePromptBetweenThem() async {
        let harness = Harness()
        let writer = GatedNotesWriter()
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }
        let notes = harness.service(writer: writer)
        notes.start(nook: nook)

        for text in ["one", "two", "three", "four"] { notes.append(text) }
        #expect(await eventually { writer.callCount == 1 })
        #expect(nook.isSystemPromptUp, "the first send is waiting on macOS")
        #expect(told == [true])
        #expect(writer.callCount == 1, "the others wait their turn")

        writer.release()
        await notes.lastSend?.value

        #expect(writer.callCount == 4)
        #expect(told == [true, false], "one trip down for all four")
        #expect(notes.hasNotesAnswer)
        #expect(notes.savedCount == 4)
    }

    @Test func notesSentBeforeARefusalAreAllCoveredByTheOnePromptAndTheRefusalIsAnAnswer() async {
        let harness = Harness()
        let writer = GatedNotesWriter()
        writer.fail(with: .notPermitted)
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }
        let notes = harness.service(writer: writer)
        notes.start(nook: nook)

        for text in ["one", "two", "three"] { notes.append(text) }
        #expect(await eventually { writer.callCount == 1 })
        writer.release()
        await notes.lastSend?.value

        #expect(told == [true, false])
        #expect(notes.hasNotesAnswer)
        // Each refused note went to the file.
        let file = (try? String(contentsOf: harness.fileURL, encoding: .utf8)) ?? ""
        for text in ["one", "two", "three"] { #expect(file.contains(text), "\(text) was dropped") }
    }

    @Test func sendsThatKeepFailingForAnotherReasonEachRaiseTheirOwnPromptOneAtATime() async {
        let harness = Harness()
        let writer = GatedNotesWriter()
        writer.fail(with: .failed)
        writer.release()
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }
        let notes = harness.service(writer: writer)
        notes.start(nook: nook)

        for text in ["one", "two", "three"] { notes.append(text) }
        await notes.lastSend?.value

        #expect(told == [true, false, true, false, true, false], "one at a time, never merged into a single long prompt")
        #expect(notes.hasNotesAnswer == false)
    }

    @Test func aRefusalThenAnAllowKeepsTheAnswerAndNeverAsksAgain() async {
        let harness = Harness()
        let writer = GatedNotesWriter()
        writer.fail(with: .notPermitted)
        writer.release()
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }
        let notes = harness.service(writer: writer)
        notes.start(nook: nook)

        notes.append("refused")
        await notes.lastSend?.value
        #expect(told == [true, false])

        // The user turned Notes on in System Settings.
        writer.fail(with: nil)
        notes.append("allowed")
        await notes.lastSend?.value
        notes.append("allowed again")
        await notes.lastSend?.value

        #expect(told == [true, false], "macOS asked its one question")
        #expect(notes.hasNotesAnswer)
    }

    @Test func theAnswerSurvivesARelaunchAndAFreshInstallAsksAgain() async {
        let harness = Harness()
        let writer = GatedNotesWriter()
        writer.release()
        let nook = Self.nook()
        let notes = harness.service(writer: writer)
        notes.start(nook: nook)
        notes.append("first")
        await notes.lastSend?.value
        #expect(notes.hasNotesAnswer)

        // A new service on the same store: the app launched again.
        let relaunched = harness.service(writer: writer)
        #expect(relaunched.hasNotesAnswer)
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }
        relaunched.start(nook: nook)
        relaunched.append("second")
        await relaunched.lastSend?.value
        #expect(told.isEmpty)

        // A store that has never been asked.
        let fresh = Harness()
        let freshNotes = fresh.service(writer: writer)
        #expect(freshNotes.hasNotesAnswer == false)
        freshNotes.start(nook: nook)
        freshNotes.append("third")
        await freshNotes.lastSend?.value
        #expect(told == [true, false])
    }

    @Test func aNoteSavedToTheFileNeverTouchesThePromptCountOrTheAnswer() async {
        let harness = Harness(destination: .file)
        let writer = GatedNotesWriter()
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }
        let notes = harness.service(writer: writer)
        notes.start(nook: nook)

        notes.append("kept in the file")

        #expect(told.isEmpty)
        #expect(writer.callCount == 0)
        #expect(notes.hasNotesAnswer == false)
        #expect(notes.lastSend == nil)
    }

    @Test func aNotesServiceNeverStartedStillTakesTheNoteAndTellsTheIslandNothing() async {
        let harness = Harness()
        let writer = GatedNotesWriter()
        writer.release()
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }
        let notes = harness.service(writer: writer)

        notes.append("unstarted")
        await notes.lastSend?.value

        #expect(writer.callCount == 1)
        #expect(notes.savedCount == 1)
        #expect(told.isEmpty)
        #expect(nook.isSystemPromptUp == false)
    }

    /// Every begin has an end that reaches the same model, whatever happens
    /// to the service in between. The service lives as long as the app, which
    /// means this cannot happen there.
    @Test func aNotesServiceThatGoesAwayWhileItsSendWaitsStillEndsThePromptItBegan() async {
        let harness = Harness()
        let writer = GatedNotesWriter()
        let nook = Self.nook()
        var notes: NookNotesService? = harness.service(writer: writer)
        notes?.start(nook: nook)
        notes?.append("going away")
        #expect(await eventually { writer.callCount == 1 })
        #expect(nook.isSystemPromptUp)

        notes = nil
        writer.release()
        _ = await eventually { writer.finishedCount == 1 }
        for _ in 0..<20 { await Task.yield() }

        let isStillUp = nook.isSystemPromptUp
        #expect(isStillUp == false)
    }
}

// MARK: - The panel

@MainActor
@Suite(.serialized, .noNewWindows)
struct EdgeCaseSystemPromptPanelTests {
    private func model() -> AppModel {
        let model = AppModel(defaults: MemoryDefaults())
        model.disablesOverlayEventMonitoringDuringHarness = true
        model.overlay.pointerLocationProvider = { NSPoint(x: -10_000, y: -10_000) }
        model.nook.presentRingLight = { _ in }
        // The same wiring `letSystemPromptsShowOverTheIsland` makes for the
        // Nook, without the camera's hook, which is one shared object that
        // other tests also set.
        model.nook.onSystemPromptChange = { [weak model] isUp in
            model?.overlay.overlayPanelController.setSystemPromptUp(isUp)
        }
        return model
    }

    private func level(_ model: AppModel) -> NSWindow.Level? {
        model.overlay.overlayPanelController.panelLevel
    }

    @Test func aPanelThatDoesNotExistYetHasNoLevelAndAPromptBeforeItDoesNotCrash() {
        let controller = OverlayPanelController()
        controller.setSystemPromptUp(true)
        controller.setSystemPromptUp(false)
        #expect(controller.panelLevel == nil)
        #expect(controller.hasPanel == false)
    }

    @Test func aPromptThatWentUpBeforeThePanelWasMadeLowersTheFirstIslandThatOpens() {
        guard !NSScreen.screens.isEmpty else { return }
        let model = model()
        #expect(level(model) == nil)

        model.nook.systemPromptBegan()
        #expect(level(model) == nil)

        model.notchOpen(reason: .click)
        #expect(level(model) == IslandPanelLevel.underSystemPrompt)

        model.nook.systemPromptEnded()
        #expect(level(model) == IslandPanelLevel.standard)
        model.notchClose()
    }

    @Test func aPanelMadeClosedWhileAPromptIsUpStaysStandardUntilTheIslandOpens() {
        guard !NSScreen.screens.isEmpty else { return }
        let model = model()
        model.nook.systemPromptBegan()
        model.overlay.ensureOverlayPanel()
        #expect(level(model) == IslandPanelLevel.standard)

        model.notchOpen(reason: .hover)
        #expect(level(model) == IslandPanelLevel.underSystemPrompt)
        model.notchClose()
        model.nook.systemPromptEnded()
    }

    @Test func aPromptThatEndsWhileTheIslandIsClosedLeavesItStandardAndTheNextOpenStandard() {
        guard !NSScreen.screens.isEmpty else { return }
        let model = model()
        model.overlay.ensureOverlayPanel()

        model.notchOpen(reason: .click)
        model.nook.systemPromptBegan()
        #expect(level(model) == IslandPanelLevel.underSystemPrompt)

        model.notchClose()
        #expect(level(model) == IslandPanelLevel.standard)
        model.nook.systemPromptEnded()
        #expect(level(model) == IslandPanelLevel.standard)

        model.notchOpen(reason: .click)
        #expect(level(model) == IslandPanelLevel.standard, "nothing is up any more")
        model.notchClose()
    }

    @Test func theIslandOpenedAndClosedManyTimesDuringOnePromptFollowsItsStatusEachTime() {
        guard !NSScreen.screens.isEmpty else { return }
        let model = model()
        model.overlay.ensureOverlayPanel()
        model.nook.systemPromptBegan()

        for _ in 0..<10 {
            model.notchOpen(reason: .hover)
            #expect(level(model) == IslandPanelLevel.underSystemPrompt)
            model.notchClose()
            #expect(level(model) == IslandPanelLevel.standard)
        }

        model.nook.systemPromptEnded()
        model.notchOpen(reason: .hover)
        #expect(level(model) == IslandPanelLevel.standard)
        model.notchClose()
    }

    @Test func twoPromptsKeepTheIslandLoweredUntilBothAreAnswered() {
        guard !NSScreen.screens.isEmpty else { return }
        let model = model()
        model.overlay.ensureOverlayPanel()
        model.notchOpen(reason: .click)

        model.nook.systemPromptBegan()
        model.nook.systemPromptBegan()
        #expect(level(model) == IslandPanelLevel.underSystemPrompt)
        model.nook.systemPromptEnded()
        #expect(level(model) == IslandPanelLevel.underSystemPrompt, "one prompt is still up")
        model.nook.systemPromptEnded()
        #expect(level(model) == IslandPanelLevel.standard)
        model.notchClose()
    }

    @Test func anIslandThatPopsDuringAPromptStaysStandardAndAnOpenOverAPopGoesBelow() {
        guard !NSScreen.screens.isEmpty else { return }
        let model = model()
        model.overlay.ensureOverlayPanel()
        model.nook.systemPromptBegan()

        model.notchPop()
        #expect(model.notchStatus == .popping)
        #expect(level(model) == IslandPanelLevel.standard, "a popping pill covers nothing")

        model.notchOpen(reason: .click)
        #expect(model.notchStatus == .opened)
        #expect(level(model) == IslandPanelLevel.underSystemPrompt)
        model.notchClose()
        model.nook.systemPromptEnded()
    }

    @Test func aCardOpeningOverAnOpenIslandWhileAPromptIsUpKeepsItBelow() {
        guard !NSScreen.screens.isEmpty else { return }
        let model = model()
        model.overlay.ensureOverlayPanel()
        model.notchOpen(reason: .hover)
        model.nook.systemPromptBegan()
        #expect(level(model) == IslandPanelLevel.underSystemPrompt)

        model.notchOpen(reason: .notification, surface: .sessionList())
        #expect(level(model) == IslandPanelLevel.underSystemPrompt)

        model.notchClose()
        #expect(level(model) == IslandPanelLevel.standard)
        model.nook.systemPromptEnded()
    }

    /// The tour's case: it holds the island open and asks for the permission.
    @Test func theToursHeldIslandStepsBelowAPromptAndBackWhenTheHoldLetsGo() {
        guard !NSScreen.screens.isEmpty else { return }
        let model = model()
        model.setTourHoldsIslandOpen(true)
        #expect(model.notchStatus == .opened)
        #expect(level(model) == IslandPanelLevel.standard)

        model.nook.systemPromptBegan()
        #expect(level(model) == IslandPanelLevel.underSystemPrompt)
        // The hold is released with the prompt still up: the island closes
        // and goes back to its own level.
        model.setTourHoldsIslandOpen(false)
        #expect(model.notchStatus == .closed)
        #expect(level(model) == IslandPanelLevel.standard)
        model.nook.systemPromptEnded()
    }

    @Test func aPlacementRefreshWhileAPromptIsUpLeavesTheLevelAlone() {
        guard !NSScreen.screens.isEmpty else { return }
        let model = model()
        model.overlay.ensureOverlayPanel()
        model.notchOpen(reason: .click)
        model.nook.systemPromptBegan()

        model.refreshOverlayPlacement()
        #expect(level(model) == IslandPanelLevel.underSystemPrompt)
        model.refreshOverlayDisplayConfiguration()
        #expect(level(model) == IslandPanelLevel.underSystemPrompt)

        model.nook.systemPromptEnded()
        model.notchClose()
    }
}
