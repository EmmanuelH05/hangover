import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

// MARK: - Fakes

/// The engine, without a screen. `startReport` swaps the recording it
/// reports for another phase, and `startGate` holds `start` open until the
/// stream is finished, the way a permission prompt does. `silentStart`
/// returns from `start` having reported nothing, the way a stream does that
/// never sends a picture. A `stop` during `start` cancels it, as the real
/// engine's does.
@MainActor
final class FakeRecorder: NookRecording {
    var onPhaseChange: ((NookRecordPhase) -> Void)?
    var onWarning: ((NookRecordWarning) -> Void)?
    var starts: [(NookRecordOptions, NookRecordTarget, URL, [CGWindowID])] = []
    var stops = 0
    var pauses = 0
    var resumes = 0
    var startReport: NookRecordPhase?
    var startGate: AsyncStream<Void>?
    /// Lets a `stop` during the start open the gate, as a cancelled picker does.
    var releaseStart: (() -> Void)?
    var silentStart = false
    /// An engine with nothing to stop: `stop` returns and reports nothing.
    var ignoresStop = false
    private var isStarting = false
    private var wasCancelled = false

    func start(options: NookRecordOptions, target: NookRecordTarget, fileURL: URL, islandWindows: [CGWindowID]) async {
        starts.append((options, target, fileURL, islandWindows))
        isStarting = true
        if let startGate {
            for await _ in startGate { break }
        }
        isStarting = false
        if wasCancelled {
            wasCancelled = false
            return
        }
        if silentStart { return }
        onPhaseChange?(startReport ?? .recording(startedAt: Date(timeIntervalSince1970: 0), pausedTotal: 0))
    }

    func pause() {
        pauses += 1
        onPhaseChange?(.paused(startedAt: .init(timeIntervalSince1970: 0), pausedAt: .init(timeIntervalSince1970: 5), pausedTotal: 0))
    }

    func resume() {
        resumes += 1
        onPhaseChange?(.recording(startedAt: .init(timeIntervalSince1970: 0), pausedTotal: 1))
    }

    func stop() async {
        stops += 1
        if ignoresStop { return }
        if isStarting {
            wasCancelled = true
            releaseStart?()
            onPhaseChange?(.idle)
            return
        }
        // Up, and no picture yet: a stop here has nothing to keep.
        if silentStart {
            onPhaseChange?(.idle)
            return
        }
        guard let url = starts.last?.2 else { return }
        onPhaseChange?(.saving)
        onPhaseChange?(.finished(url, endedBy: .user))
    }
}

@MainActor
final class RecordFakeBubble: NookFaceCamPresenting {
    private(set) var shows = 0
    private(set) var hides = 0
    private(set) var placements: [NookFaceCamPlacement] = []
    var onProblem: ((NookFaceCamProblem) -> Void)?
    /// A problem the bubble knows at once, such as a camera that is denied: it
    /// closes itself and reports from inside `show`, as the real one does.
    var problemOnShow: NookFaceCamProblem?
    func show(placement: NookFaceCamPlacement) {
        shows += 1
        placements.append(placement)
        if let problemOnShow {
            hide()
            onProblem?(problemOnShow)
        }
    }
    func hide() { hides += 1 }

    /// The camera failing, as the real bubble reports it.
    func report(_ problem: NookFaceCamProblem) { onProblem?(problem) }
}

@MainActor
final class RecordFakeAreaPicker: NookRecordAreaPicking {
    var rect: CGRect?
    private(set) var displays: [CGDirectDisplayID] = []

    init(rect: CGRect?) { self.rect = rect }

    func pick(on displayID: CGDirectDisplayID) async -> CGRect? {
        displays.append(displayID)
        return rect
    }
}

@MainActor
final class RecordFakeRegistrar: NookRecordHotkeyRegistering {
    private(set) var registered: [AgentHotkeyCombo] = []
    private(set) var unregisters = 0
    var outcome: AgentHotkeyRegistrationOutcome = .registered
    var system: Set<AgentHotkeyCombo> = []
    private var onPress: (@MainActor () -> Void)?

    func register(_ combo: AgentHotkeyCombo, onPress: @escaping @MainActor () -> Void) -> AgentHotkeyRegistrationOutcome {
        registered.append(combo)
        self.onPress = onPress
        return outcome
    }

    func unregister() { unregisters += 1 }
    func systemShortcuts() -> Set<AgentHotkeyCombo> { system }
    func keyName(for keyCode: UInt16) -> String? { nil }

    func press() { onPress?() }
}

/// Collects what a `@Sendable` sleep closure saw.
final class RecordSeenLog: @unchecked Sendable {
    private let lock = NSLock()
    private var phases: [NookRecordPhase?] = []
    private var model: NookRecordModel?

    func attach(_ model: NookRecordModel) { lock.withLock { self.model = model } }
    private func attached() -> NookRecordModel? { lock.withLock { model } }
    private func add(_ phase: NookRecordPhase?) { lock.withLock { phases.append(phase) } }
    var seen: [NookRecordPhase?] { lock.withLock { phases } }

    func look() async {
        let phase = await MainActor.run { attached()?.phase }
        add(phase)
    }
}

/// Holds a notice the model asked the Nook to show.
@MainActor
final class RecordNoticeLog {
    private(set) var notices: [(symbol: String, text: String)] = []
    func add(_ symbol: String, _ text: String) { notices.append((symbol, text)) }
}

// MARK: - The model

@MainActor @Suite struct NookRecordModelTests {
    /// Never created: `createFolder` is a no-op and `fileExists` says no.
    static let folder = URL(fileURLWithPath: "/tmp/hangover-record-tests", isDirectory: true)

    func makeModel(
        _ recorder: FakeRecorder,
        defaults: UserDefaults = MemoryDefaults(),
        createFolder: @escaping (URL) throws -> Void = { _ in },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in },
        fileExists: @escaping (URL) -> Bool = { _ in false },
        finished: @escaping (URL) -> Void = { _ in }
    ) -> NookRecordModel {
        NookRecordModel(
            recorder: recorder,
            defaults: defaults,
            folder: Self.folder,
            createFolder: createFolder,
            sleep: sleep,
            fileExists: fileExists,
            now: { Date(timeIntervalSince1970: 0) },
            onFinished: finished
        )
    }

    // MARK: Window mode

    final class SleepCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func tick() { lock.withLock { value += 1 } }
    }

    @Test func aWindowRecordingStartsWithNoCountBecauseThePickerClickIsTheStart() async {
        let recorder = FakeRecorder()
        let sleeps = SleepCounter()
        let model = makeModel(recorder, sleep: { _ in sleeps.tick() })
        await model.record(target: .pickedWindow, islandWindows: [])
        #expect(sleeps.count == 0)
        #expect(recorder.starts.count == 1)
    }

    @Test func aScreenRecordingStillCountsThreeTwoOne() async {
        let recorder = FakeRecorder()
        let sleeps = SleepCounter()
        let model = makeModel(recorder, sleep: { _ in sleeps.tick() })
        await model.record(target: .display(1), islandWindows: [])
        #expect(sleeps.count == NookRecordModel.countdownSeconds)
        #expect(recorder.starts.count == 1)
    }

    // MARK: Settings

    @Test func optionsAreSavedAndReadBack() {
        let defaults = MemoryDefaults()
        let first = makeModel(FakeRecorder(), defaults: defaults)
        first.options.voice = true
        first.options.includeIsland = false
        first.options.quality = .high
        first.options.capture = .area
        first.options.faceCam = true
        first.options.macSound = false
        let second = makeModel(FakeRecorder(), defaults: defaults)
        #expect(second.options.voice)
        #expect(!second.options.includeIsland)
        #expect(second.options.quality == .high)
        #expect(second.options.capture == .area)
        #expect(second.options.faceCam)
        #expect(!second.options.macSound)
    }

    @Test func noSavedChoicesMeansTheDefaults() {
        #expect(makeModel(FakeRecorder()).options == NookRecordOptions())
    }

    @Test func aChoiceThatWasNeverWrittenKeepsItsDefault() {
        let defaults = MemoryDefaults()
        defaults.set(false, forKey: NookRecordModel.macSoundKey)
        let loaded = makeModel(FakeRecorder(), defaults: defaults).options
        #expect(!loaded.macSound)
        #expect(loaded.includeIsland)
    }

    @Test func settingsKeysAreTheOnesTheSpecNames() {
        #expect(NookRecordModel.captureKey == "nook.record.capture")
        #expect(NookRecordModel.faceCamKey == "nook.record.faceCam")
        #expect(NookRecordModel.voiceKey == "nook.record.voice")
        #expect(NookRecordModel.macSoundKey == "nook.record.macSound")
        #expect(NookRecordModel.qualityKey == "nook.record.quality")
        #expect(NookRecordModel.includeIslandKey == "nook.record.includeIsland")
        #expect(NookRecordHotkeyController.comboKey == "nook.record.hotkey")
    }

    // MARK: Starting

    @Test func recordCountsDownThenStartsOnce() async {
        let recorder = FakeRecorder()
        let log = RecordSeenLog()
        let model = makeModel(recorder, sleep: { _ in await log.look() })
        log.attach(model)
        await model.record(target: .display(1), islandWindows: [9])
        #expect(log.seen == [.countdown(secondsLeft: 3), .countdown(secondsLeft: 2), .countdown(secondsLeft: 1)])
        #expect(recorder.starts.count == 1)
        #expect(recorder.starts.first?.2.lastPathComponent.hasPrefix("Recording ") == true)
        if case .recording = model.phase {} else { Issue.record("expected recording, got \(model.phase)") }
    }

    @Test func theFileGoesInTheMoviesFolderAndTakesTheNextFreeName() async {
        let recorder = FakeRecorder()
        let first = Self.folder.appendingPathComponent(NookRecordFiles.fileName(for: Date(timeIntervalSince1970: 0)))
        let model = makeModel(recorder, fileExists: { $0 == first })
        await model.record(target: .display(1), islandWindows: [])
        let url = recorder.starts.first?.2
        #expect(url?.deletingLastPathComponent() == Self.folder)
        #expect(url?.lastPathComponent.hasSuffix(" 2.mp4") == true)
    }

    @Test func theFolderIsMadeBeforeTheEngineStarts() async {
        let recorder = FakeRecorder()
        var made: [URL] = []
        let model = makeModel(recorder, createFolder: { made.append($0) })
        await model.record(target: .display(1), islandWindows: [])
        #expect(made == [Self.folder])
    }

    @Test func aFolderThatCannotBeMadeFailsWithoutStartingTheEngine() async {
        struct NoRoom: Error {}
        let recorder = FakeRecorder()
        let model = makeModel(recorder, createFolder: { _ in throw NoRoom() })
        await model.record(target: .display(1), islandWindows: [])
        #expect(recorder.starts.isEmpty)
        #expect(model.phase == .failed(.writeFailed))
    }

    @Test func theIslandSettingReachesTheEngine() async {
        let recorder = FakeRecorder()
        let model = makeModel(recorder)
        model.options.includeIsland = false
        await model.record(target: .display(1), islandWindows: [9])
        #expect(recorder.starts.first?.0.includeIsland == false)
        #expect(recorder.starts.first?.3 == [9])
    }

    @Test func theTargetReachesTheEngine() async {
        let recorder = FakeRecorder()
        let model = makeModel(recorder)
        await model.record(target: .area(2, CGRect(x: 1, y: 2, width: 300, height: 200)), islandWindows: [])
        #expect(recorder.starts.first?.1 == .area(2, CGRect(x: 1, y: 2, width: 300, height: 200)))
    }

    @Test func switchesMovedDuringTheCountAreNotHeard() async {
        let recorder = FakeRecorder()
        let box = RecordSeenLog()
        let model = makeModel(recorder, sleep: { _ in await box.look() })
        box.attach(model)
        model.options.voice = false
        let running = Task { await model.record(target: .display(1), islandWindows: []) }
        while model.phase == .idle { await Task.yield() }
        model.options.voice = true
        await running.value
        #expect(recorder.starts.first?.0.voice == false)
    }

    // MARK: Pressing again (review focus 3)

    @Test func aPressDuringTheCountdownCancelsIt() async {
        let recorder = FakeRecorder()
        let gate = AsyncStream<Void>.makeStream()
        let model = makeModel(recorder, sleep: { _ in for await _ in gate.stream { return } })
        let first = Task { await model.record(target: .display(1), islandWindows: []) }
        while model.phase == .idle { await Task.yield() }
        await model.toggle(target: .display(1), islandWindows: [])
        gate.continuation.finish()
        await first.value
        #expect(recorder.starts.isEmpty)
        #expect(model.phase == .idle)
    }

    @Test func aPressWhileSavingDoesNothing() async {
        let recorder = FakeRecorder()
        let model = makeModel(recorder)
        model.phase = .saving
        await model.toggle(target: .display(1), islandWindows: [])
        #expect(recorder.starts.isEmpty)
        #expect(recorder.stops == 0)
    }

    @Test func aPressWhileRecordingStops() async {
        let recorder = FakeRecorder()
        let model = makeModel(recorder)
        await model.record(target: .display(1), islandWindows: [])
        await model.toggle(target: .display(1), islandWindows: [])
        #expect(recorder.stops == 1)
        #expect(recorder.starts.count == 1)
        if case .finished = model.phase {} else { Issue.record("expected finished, got \(model.phase)") }
    }

    @Test func aPressWhilePausedStops() async {
        let recorder = FakeRecorder()
        let model = makeModel(recorder)
        await model.record(target: .display(1), islandWindows: [])
        model.pause()
        await model.toggle(target: .display(1), islandWindows: [])
        #expect(recorder.stops == 1)
    }

    // MARK: The start gap (R1)

    @Test func aPressWhileTheEngineIsStartingCancelsItAndNeverMakesASecondStream() async {
        let recorder = FakeRecorder()
        let gate = AsyncStream<Void>.makeStream()
        recorder.startGate = gate.stream
        recorder.releaseStart = { gate.continuation.finish() }
        let model = makeModel(recorder)
        let running = Task { await model.record(target: .display(1), islandWindows: []) }
        while recorder.starts.isEmpty { await Task.yield() }
        #expect(model.phase == .countdown(secondsLeft: 0))
        await model.toggle(target: .display(1), islandWindows: [])
        #expect(recorder.stops == 1)
        // Opened whatever happened, so a regression fails here and does not hang.
        gate.continuation.finish()
        await running.value
        #expect(recorder.starts.count == 1)
        #expect(model.phase == .idle)
    }

    @Test func aStartThatReportsNothingCanStillBeStopped() async {
        let recorder = FakeRecorder()
        recorder.silentStart = true
        let model = makeModel(recorder)
        await model.record(target: .display(1), islandWindows: [])
        // The engine returned and said nothing: the card is on "Starting".
        #expect(model.phase == .countdown(secondsLeft: 0))
        await model.stop()
        #expect(recorder.stops == 1)
        #expect(model.phase == .idle)
    }

    @Test func aSecondPressDuringAStartThatReportsNothingCancelsIt() async {
        let recorder = FakeRecorder()
        recorder.silentStart = true
        let model = makeModel(recorder)
        await model.toggleFromUser()
        #expect(model.phase == .countdown(secondsLeft: 0))
        // The notch click, the shortcut and the Record button all come here.
        await model.toggleFromUser()
        #expect(recorder.stops == 1)
        #expect(recorder.starts.count == 1)
        #expect(model.phase == .idle)
    }

    @Test func anEngineWithNothingToStopStillLeavesTheStartGap() async {
        let recorder = FakeRecorder()
        recorder.silentStart = true
        recorder.ignoresStop = true
        let model = makeModel(recorder)
        await model.record(target: .display(1), islandWindows: [])
        await model.stop()
        #expect(recorder.stops == 1)
        #expect(model.phase == .idle)
    }

    @Test func twoStopsDuringTheStartReachTheEngineOnce() async {
        let recorder = FakeRecorder()
        let gate = AsyncStream<Void>.makeStream()
        recorder.startGate = gate.stream
        recorder.releaseStart = { gate.continuation.finish() }
        recorder.silentStart = true
        let model = makeModel(recorder)
        let running = Task { await model.record(target: .display(1), islandWindows: []) }
        while recorder.starts.isEmpty { await Task.yield() }
        async let first: Void = model.stop()
        async let second: Void = model.stop()
        _ = await (first, second)
        #expect(recorder.stops == 1)
        gate.continuation.finish()
        await running.value
    }

    @Test func quittingDuringTheStartGapEndsTheStart() async {
        let recorder = FakeRecorder()
        recorder.silentStart = true
        let model = makeModel(recorder)
        await model.record(target: .display(1), islandWindows: [])
        await model.prepareForQuit()
        #expect(recorder.stops == 1)
        #expect(model.phase == .idle)
    }

    @Test func switchingTheWidgetOffEndsAStartThatReportsNothing() async {
        let recorder = FakeRecorder()
        recorder.silentStart = true
        let defaults = MemoryDefaults()
        let record = NookRecordModel(
            recorder: recorder, defaults: defaults, folder: Self.folder,
            createFolder: { _ in }, sleep: { _ in }, fileExists: { _ in false }
        )
        let nook = NookModel(record: record, defaults: defaults, looksForImportedGIF: false, asksMacOSForAccess: false)
        record.start(nook: nook)
        nook.setWidget(.record, enabled: true)
        await record.record(target: .display(1), islandWindows: [])
        nook.setWidget(.record, enabled: false)
        for _ in 0..<200 where record.phase != .idle { await Task.yield() }
        #expect(recorder.stops == 1)
        #expect(record.phase == .idle)
    }

    @Test func theBubbleGoesWhenAStartIsCancelled() async {
        let recorder = FakeRecorder()
        recorder.silentStart = true
        let (model, bubble) = modelWithBubble(recorder)
        model.options.faceCam = true
        await model.record(target: .display(1), islandWindows: [])
        #expect(model.isFaceCamUp)
        await model.stop()
        #expect(bubble.hides == 1)
        #expect(!model.isFaceCamUp)
    }

    @Test func cancelShowsForTheWholeCountAndTheStartAfterIt() {
        #expect(NookRecordCardLayout.showsCancel(secondsLeft: 3))
        #expect(NookRecordCardLayout.showsCancel(secondsLeft: 1))
        #expect(NookRecordCardLayout.showsCancel(secondsLeft: 0))
    }

    @Test func recordWhileBusyDoesNothing() async {
        let recorder = FakeRecorder()
        let model = makeModel(recorder)
        await model.record(target: .display(1), islandWindows: [])
        await model.record(target: .display(1), islandWindows: [])
        #expect(recorder.starts.count == 1)
    }

    @Test func aStopDuringAStopIsOne() async {
        let recorder = FakeRecorder()
        let model = makeModel(recorder)
        await model.record(target: .display(1), islandWindows: [])
        async let first: Void = model.stop()
        async let second: Void = model.stop()
        _ = await (first, second)
        #expect(recorder.stops == 1)
    }

    @Test func recordingCanStartAgainAfterItFinished() async {
        let recorder = FakeRecorder()
        let model = makeModel(recorder)
        await model.record(target: .display(1), islandWindows: [])
        await model.stop()
        await model.record(target: .display(1), islandWindows: [])
        #expect(recorder.starts.count == 2)
    }

    // MARK: Pause

    @Test func pauseAndResumeReachTheEngineOnlyWhenTheyMeanSomething() async {
        let recorder = FakeRecorder()
        let model = makeModel(recorder)
        model.pause()
        model.resume()
        #expect(recorder.pauses == 0 && recorder.resumes == 0)
        await model.record(target: .display(1), islandWindows: [])
        model.resume()
        #expect(recorder.resumes == 0)
        model.pause()
        model.pause()
        #expect(recorder.pauses == 1)
        model.resume()
        #expect(recorder.resumes == 1)
    }

    // MARK: Finishing

    @Test func stopHandsTheFileToTheTray() async {
        let recorder = FakeRecorder()
        var handed: [URL] = []
        let model = makeModel(recorder, finished: { handed.append($0) })
        await model.record(target: .display(1), islandWindows: [])
        await model.stop()
        #expect(handed.count == 1)
        #expect(handed.first == recorder.starts.first?.2)
    }

    @Test func aFinishedRecordingSaysSoInTheNotch() async {
        let recorder = FakeRecorder()
        let log = RecordNoticeLog()
        let model = makeModel(recorder)
        model.showNotice = { symbol, text, _ in log.add(symbol, text) }
        await model.record(target: .display(1), islandWindows: [])
        await model.stop()
        #expect(log.notices.map(\.text) == [LanguageManager.shared.t("nook.record.notice.saved")])
    }

    @Test func aRecordingThatRanOutOfSpaceSaysThatInstead() async {
        let recorder = FakeRecorder()
        let log = RecordNoticeLog()
        var handed: [URL] = []
        let model = makeModel(recorder, finished: { handed.append($0) })
        model.showNotice = { symbol, text, _ in log.add(symbol, text) }
        await model.record(target: .display(1), islandWindows: [])
        recorder.onPhaseChange?(.finished(recorder.starts[0].2, endedBy: .lowDisk))
        #expect(log.notices.map(\.text) == [LanguageManager.shared.t("nook.record.notice.lowDisk")])
        // What was recorded still goes to the tray.
        #expect(handed.count == 1)
    }

    @Test func aFailureShowsItsSentenceAndHandsNothingToTheTray() async {
        let recorder = FakeRecorder()
        recorder.startReport = .failed(.screenPermissionDenied)
        let log = RecordNoticeLog()
        var handed: [URL] = []
        let model = makeModel(recorder, finished: { handed.append($0) })
        model.showNotice = { symbol, text, _ in log.add(symbol, text) }
        await model.record(target: .display(1), islandWindows: [])
        #expect(model.phase == .failed(.screenPermissionDenied))
        #expect(log.notices.map(\.text) == [LanguageManager.shared.t("nook.record.failure.screenPermission")])
        #expect(handed.isEmpty)
    }

    @Test func aFailedWriterNamesTheTimeInTheNotchAndOnTheCard() async {
        let recorder = FakeRecorder()
        recorder.startReport = .failed(.writerFailed(atSeconds: 760))
        let log = RecordNoticeLog()
        let model = makeModel(recorder)
        model.showNotice = { symbol, text, _ in log.add(symbol, text) }
        await model.record(target: .display(1), islandWindows: [])
        #expect(log.notices.count == 1)
        #expect(log.notices.first?.text.contains("12:40") == true)
        #expect(NookRecordStatusLine.of(model.phase)?.text.contains("12:40") == true)
        #expect(NookRecordStatusLine.of(model.phase)?.isWarning == true)
    }

    @Test func theWriterFailureSentenceFillsInTheTimeInEnglish() throws {
        let en = try NookRecordStringsTests.table("en")
        let format = try #require(en["nook.record.failure.writerFailed"])
        #expect(String(format: format, NookRecordClock.text(760)) == "Recording stopped at 12:40: the file could not be written.")
    }

    // MARK: Sentences that point at the right fix (R4, R5)

    @Test func aRecordingMacOSEndedSaysSoAndKeepsTheFile() async {
        let recorder = FakeRecorder()
        let log = RecordNoticeLog()
        var handed: [URL] = []
        let model = makeModel(recorder, finished: { handed.append($0) })
        model.showNotice = { symbol, text, _ in log.add(symbol, text) }
        await model.record(target: .display(1), islandWindows: [])
        recorder.onPhaseChange?(.finished(recorder.starts[0].2, endedBy: .system))
        #expect(log.notices.map(\.text) == [LanguageManager.shared.t("nook.record.notice.system")])
        #expect(handed.count == 1)
        #expect(NookRecordStatusLine.of(model.phase) == NookRecordStatusLine(text: LanguageManager.shared.t("nook.record.notice.system"), isWarning: true))
    }

    @Test func aPlainStopStaysAPlainSaved() {
        let url = Self.folder
        let line = NookRecordStatusLine.of(.finished(url, endedBy: .user))
        #expect(line == NookRecordStatusLine(text: LanguageManager.shared.t("nook.record.notice.saved"), isWarning: false))
        let space = NookRecordStatusLine.of(.finished(url, endedBy: .lowDisk))
        #expect(space == NookRecordStatusLine(text: LanguageManager.shared.t("nook.record.notice.lowDisk"), isWarning: true))
    }

    @Test func lowDiskAtTheStartHasItsOwnSentenceNotTheMidRecordingOne() async throws {
        let recorder = FakeRecorder()
        recorder.startReport = .failed(.lowDisk)
        let log = RecordNoticeLog()
        let model = makeModel(recorder)
        model.showNotice = { symbol, text, _ in log.add(symbol, text) }
        await model.record(target: .display(1), islandWindows: [])
        let en = try NookRecordStringsTests.table("en")
        #expect(en["nook.record.failure.lowDisk"] == "Less than 1 GB is free. Free up space, then record.")
        #expect(en["nook.record.notice.lowDisk"] == "Recording stopped: less than 1 GB free. What was recorded is saved.")
        #expect(log.notices.map(\.text) == [LanguageManager.shared.t("nook.record.failure.lowDisk")])
        #expect(LanguageManager.shared.t("nook.record.failure.lowDisk") != LanguageManager.shared.t("nook.record.notice.lowDisk"))
    }

    @Test func noTwoFailuresShareASentenceInAnyLanguage() throws {
        let failures: [NookRecordFailure] = [
            .screenPermissionDenied, .micPermissionDenied, .pickerCancelled, .noDisplay, .lowDisk, .writeFailed,
            .noPicture, .couldNotStart, .writerFailed(atSeconds: 5), .noMicrophone, .pickerFailed,
        ]
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let table = try NookRecordStringsTests.table(language)
            let sentences = failures.compactMap { table[$0.noticeKey] }
            #expect(sentences.count == failures.count, "\(language) is missing a failure sentence")
            #expect(Set(sentences).count == failures.count, "\(language) gives two failures the same sentence")
        }
    }

    @Test func theNewFailureSentencesAreTheOnesTheFixListWrote() throws {
        let en = try NookRecordStringsTests.table("en")
        #expect(en["nook.record.failure.noMicrophone"] == "No microphone is connected.")
        #expect(en["nook.record.failure.pickerFailed"] == "The window picker did not open.")
        #expect(en["nook.record.failure.couldNotStart"] == "The recording could not start.")
        #expect(en["nook.record.notice.system"] == "Recording stopped by macOS. What was recorded is saved.")
        #expect(en["nook.record.notice.keptPartial"] == "What was recorded is in Movies/Hangover.")
        #expect(en["nook.record.notice.droppedFrames"] == "Some frames were dropped. Standard quality may be smoother on this Mac.")
        #expect(en["nook.record.notice.droppedFramesPlain"] == "Some frames were dropped.")
        #expect(en["nook.record.notice.noVoice"] == "No voice was recorded.")
        #expect(en["nook.record.warning.voiceLost"] == "Voice stopped: the microphone was disconnected.")
    }

    @Test func everyFailureHasASentence() {
        let failures: [NookRecordFailure] = [
            .screenPermissionDenied, .micPermissionDenied, .pickerCancelled, .noDisplay, .lowDisk, .writeFailed,
            .noPicture, .couldNotStart, .writerFailed(atSeconds: 760), .noMicrophone, .pickerFailed,
        ]
        for failure in failures {
            #expect(LanguageManager.shared.t(failure.noticeKey) != failure.noticeKey)
        }
    }

    // MARK: Quitting (review focus 2)

    @Test func quittingStopsARunningRecording() async {
        let recorder = FakeRecorder()
        let model = makeModel(recorder)
        await model.record(target: .display(1), islandWindows: [])
        await model.prepareForQuit()
        #expect(recorder.stops == 1)
        if case .finished = model.phase {} else { Issue.record("expected finished, got \(model.phase)") }
    }

    @Test func quittingWhileIdleStopsNothing() async {
        let recorder = FakeRecorder()
        await makeModel(recorder).prepareForQuit()
        #expect(recorder.stops == 0)
    }

    @Test func quittingDuringTheCountdownCancelsItWithoutAStream() async {
        let recorder = FakeRecorder()
        let gate = AsyncStream<Void>.makeStream()
        let model = makeModel(recorder, sleep: { _ in for await _ in gate.stream { return } })
        let running = Task { await model.record(target: .display(1), islandWindows: []) }
        while model.phase == .idle { await Task.yield() }
        await model.prepareForQuit()
        gate.continuation.finish()
        await running.value
        #expect(recorder.starts.isEmpty)
        #expect(recorder.stops == 0)
    }

    @Test func quittingWhileSavingWaitsForTheFile() async {
        let recorder = FakeRecorder()
        let model = makeModel(recorder)
        await model.record(target: .display(1), islandWindows: [])
        model.phase = .saving
        let url = recorder.starts[0].2
        let quitting = Task { await model.prepareForQuit() }
        for _ in 0..<5 { await Task.yield() }
        model.phase = .finished(url, endedBy: .user)
        await quitting.value
        #expect(recorder.stops == 0)
        #expect(model.phase == .finished(url, endedBy: .user))
    }

    // MARK: Face cam

    func modelWithBubble(_ recorder: FakeRecorder, sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }) -> (NookRecordModel, RecordFakeBubble) {
        let model = makeModel(recorder, sleep: sleep)
        let bubble = RecordFakeBubble()
        model.activate(NookRecordServices(
            bubble: bubble,
            areaPicker: RecordFakeAreaPicker(rect: nil),
            hotkeyRegistrar: RecordFakeRegistrar()
        ))
        return (model, bubble)
    }

    @Test func theBubbleComesUpWithTheCountAndGoesWithTheFile() async {
        let recorder = FakeRecorder()
        let (model, bubble) = modelWithBubble(recorder)
        model.options.faceCam = true
        await model.record(target: .display(1), islandWindows: [])
        #expect(bubble.shows == 1)
        #expect(model.isFaceCamUp)
        await model.stop()
        #expect(bubble.hides == 1)
        #expect(!model.isFaceCamUp)
    }

    @Test func noBubbleWithoutTheFaceCamSwitch() async {
        let recorder = FakeRecorder()
        let (model, bubble) = modelWithBubble(recorder)
        await model.record(target: .display(1), islandWindows: [])
        #expect(bubble.shows == 0)
        #expect(!model.isFaceCamUp)
    }

    @Test func theBubbleGoesWhenTheCountIsCancelled() async {
        let recorder = FakeRecorder()
        let gate = AsyncStream<Void>.makeStream()
        let (model, bubble) = modelWithBubble(recorder, sleep: { _ in for await _ in gate.stream { return } })
        model.options.faceCam = true
        let running = Task { await model.record(target: .display(1), islandWindows: []) }
        while model.phase == .idle { await Task.yield() }
        #expect(model.isFaceCamUp)
        await model.stop()
        gate.continuation.finish()
        await running.value
        #expect(bubble.hides == 1)
        #expect(!model.isFaceCamUp)
    }

    @Test func theBubbleGoesWhenTheEngineFails() async {
        let recorder = FakeRecorder()
        recorder.startReport = .failed(.micPermissionDenied)
        let (model, bubble) = modelWithBubble(recorder)
        model.options.faceCam = true
        await model.record(target: .display(1), islandWindows: [])
        #expect(bubble.hides == 1)
        #expect(!model.isFaceCamUp)
    }

    @Test func theMirrorIsToldWhenTheBubbleComesUpAndGoes() async {
        let recorder = FakeRecorder()
        let (model, _) = modelWithBubble(recorder)
        model.options.faceCam = true
        var told: [Bool] = []
        model.onFaceCamChange = { told.append($0) }
        await model.record(target: .display(1), islandWindows: [])
        await model.stop()
        #expect(told == [true, false])
    }

    // MARK: Voice and face cam trouble (R6, R7)

    @Test func aVoiceThatStopsIsSaidWhileTheRecordingGoesOn() async {
        let recorder = FakeRecorder()
        let log = RecordNoticeLog()
        let model = makeModel(recorder)
        model.showNotice = { symbol, text, _ in log.add(symbol, text) }
        await model.record(target: .display(1), islandWindows: [])

        recorder.onWarning?(.voiceLost)

        #expect(log.notices.map(\.text) == [LanguageManager.shared.t("nook.record.warning.voiceLost")])
        if case .recording = model.phase {} else { Issue.record("a warning must not end the recording, got \(model.phase)") }
    }

    @Test func aSavedRecordingWithNoVoiceSaysSoAfterTheSavedLine() async {
        let recorder = FakeRecorder()
        let log = RecordNoticeLog()
        var handed: [URL] = []
        let model = makeModel(recorder, finished: { handed.append($0) })
        model.showNotice = { symbol, text, _ in log.add(symbol, text) }
        await model.record(target: .display(1), islandWindows: [])

        recorder.onPhaseChange?(.finished(recorder.starts[0].2, endedBy: .user, notes: [.noVoice]))

        let lang = LanguageManager.shared
        let expected = lang.t("nook.record.notice.saved") + " " + lang.t("nook.record.notice.noVoice")
        #expect(log.notices.map(\.text) == [expected])
        #expect(log.notices.first?.symbol == "exclamationmark.triangle.fill")
        #expect(handed.count == 1)
        #expect(NookRecordStatusLine.of(model.phase) == NookRecordStatusLine(text: expected, isWarning: true))
    }

    @Test func aPartialFileThatPlaysGoesToTheTrayAndSaysWhereItIs() async {
        let recorder = FakeRecorder()
        let log = RecordNoticeLog()
        var handed: [URL] = []
        let model = makeModel(recorder, finished: { handed.append($0) })
        model.showNotice = { symbol, text, _ in log.add(symbol, text) }
        await model.record(target: .display(1), islandWindows: [])

        recorder.onPhaseChange?(.finished(recorder.starts[0].2, endedBy: .writeError(atSeconds: 760)))

        #expect(handed == [recorder.starts[0].2])
        let text = log.notices.first?.text ?? ""
        #expect(text.contains("12:40"))
        #expect(text.hasSuffix(LanguageManager.shared.t("nook.record.notice.keptPartial")))
        #expect(log.notices.first?.symbol == "exclamationmark.triangle.fill")
    }

    @Test func droppedFramesAreSaidAfterTheSavedLine() async {
        let recorder = FakeRecorder()
        let log = RecordNoticeLog()
        let model = makeModel(recorder)
        model.showNotice = { symbol, text, _ in log.add(symbol, text) }
        await model.record(target: .display(1), islandWindows: [])

        recorder.onPhaseChange?(.finished(recorder.starts[0].2, endedBy: .user, notes: [.droppedFrames, .suggestStandard]))

        let lang = LanguageManager.shared
        #expect(log.notices.map(\.text) == [lang.t("nook.record.notice.saved") + " " + lang.t("nook.record.notice.droppedFrames")])
    }

    @Test func droppedFramesAtStandardQualityAreSaidWithoutTheAdvice() async {
        let recorder = FakeRecorder()
        let log = RecordNoticeLog()
        let model = makeModel(recorder)
        model.showNotice = { symbol, text, _ in log.add(symbol, text) }
        await model.record(target: .display(1), islandWindows: [])

        recorder.onPhaseChange?(.finished(recorder.starts[0].2, endedBy: .user, notes: [.droppedFrames]))

        let lang = LanguageManager.shared
        #expect(log.notices.map(\.text) == [lang.t("nook.record.notice.saved") + " " + lang.t("nook.record.notice.droppedFramesPlain")])
    }

    @Test func aFaceCamThatCannotShowClosesTheBubbleAndSaysWhy() async {
        let recorder = FakeRecorder()
        let log = RecordNoticeLog()
        let (model, bubble) = modelWithBubble(recorder)
        model.showNotice = { symbol, text, _ in log.add(symbol, text) }
        model.options.faceCam = true
        await model.record(target: .display(1), islandWindows: [])
        #expect(model.isFaceCamUp)

        bubble.report(.noAccess)

        #expect(!model.isFaceCamUp)
        #expect(bubble.hides >= 1)
        #expect(log.notices.map(\.text) == [LanguageManager.shared.t("nook.record.facecam.problem.noAccess")])
        // The picture and the sound go on without the bubble.
        if case .recording = model.phase {} else { Issue.record("the recording must go on, got \(model.phase)") }
    }

    @Test func theMirrorGetsTheCameraBackWhenTheBubbleFails() async {
        let recorder = FakeRecorder()
        let (model, bubble) = modelWithBubble(recorder)
        model.options.faceCam = true
        var told: [Bool] = []
        model.onFaceCamChange = { told.append($0) }
        await model.record(target: .display(1), islandWindows: [])

        bubble.report(.stopped)
        await model.stop()

        #expect(told == [true, false])
    }

    // MARK: A problem known at once (X2)

    @Test func aFaceCamThatIsDeniedAtOnceLeavesNoBubbleMarkedUp() async {
        let recorder = FakeRecorder()
        let log = RecordNoticeLog()
        let (model, bubble) = modelWithBubble(recorder)
        model.showNotice = { symbol, text, _ in log.add(symbol, text) }
        bubble.problemOnShow = .noAccess
        model.options.faceCam = true
        var told: [Bool] = []
        model.onFaceCamChange = { told.append($0) }

        await model.record(target: .display(1), islandWindows: [])

        #expect(bubble.shows == 1)
        #expect(!model.isFaceCamUp, "the bubble closed itself from inside show; nothing is up")
        #expect(told.last == false, "the Mirror gets the camera back")
        #expect(log.notices.map(\.text) == [LanguageManager.shared.t("nook.record.facecam.problem.noAccess")])
        // The recording goes on without the bubble.
        if case .recording = model.phase {} else { Issue.record("the recording must go on, got \(model.phase)") }
    }

    @Test func eachFaceCamProblemKnownAtOnceClearsTheBubbleToo() async {
        for problem in [NookFaceCamProblem.noAccess, .noCamera, .cameraFailed, .stopped] {
            let (model, bubble) = modelWithBubble(FakeRecorder())
            bubble.problemOnShow = problem
            model.options.faceCam = true
            await model.record(target: .display(1), islandWindows: [])
            #expect(!model.isFaceCamUp, "\(problem)")
        }
    }

    @Test func eachFaceCamProblemSaysItsOwnThing() async {
        for problem in [NookFaceCamProblem.noAccess, .noCamera, .cameraFailed, .stopped] {
            let recorder = FakeRecorder()
            let log = RecordNoticeLog()
            let (model, bubble) = modelWithBubble(recorder)
            model.showNotice = { symbol, text, _ in log.add(symbol, text) }
            model.options.faceCam = true
            await model.record(target: .display(1), islandWindows: [])
            bubble.report(problem)
            #expect(log.notices.map(\.text) == [LanguageManager.shared.t(problem.noticeKey)])
        }
    }

    // MARK: Face cam with Window and Area (R10)

    @Test func aWindowRecordingNeverShowsTheBubbleAndTheEngineIsToldNoFaceCam() async {
        let recorder = FakeRecorder()
        let (model, bubble) = modelWithBubble(recorder)
        model.options.faceCam = true
        await model.record(target: .pickedWindow, islandWindows: [])
        #expect(bubble.shows == 0)
        #expect(!model.isFaceCamUp)
        #expect(recorder.starts.first?.0.faceCam == false)
        // What the person chose is still chosen: the switch comes back with Full screen.
        #expect(model.options.faceCam)
    }

    @Test func fullScreenAndAreaRecordingsShowTheBubble() async {
        for target in [NookRecordTarget.display(1), .area(1, CGRect(x: 0, y: 0, width: 300, height: 200))] {
            let recorder = FakeRecorder()
            let (model, bubble) = modelWithBubble(recorder)
            model.options.faceCam = true
            await model.record(target: target, islandWindows: [])
            #expect(bubble.shows == 1)
            #expect(recorder.starts.first?.0.faceCam == true)
        }
    }

    @Test func theBubbleStartsInTheDrawnAreaAndOtherwiseInTheCorner() async {
        let drawn = CGRect(x: 120, y: 80, width: 500, height: 400)
        let areaRecorder = FakeRecorder()
        let (areaModel, areaBubble) = modelWithBubble(areaRecorder)
        areaModel.options.faceCam = true
        await areaModel.record(target: .area(7, drawn), islandWindows: [])
        #expect(areaBubble.placements == [.insideArea(7, drawn)])

        let screenRecorder = FakeRecorder()
        let (screenModel, screenBubble) = modelWithBubble(screenRecorder)
        screenModel.options.faceCam = true
        await screenModel.record(target: .display(7), islandWindows: [])
        #expect(screenBubble.placements == [.corner])
    }

    @Test func theFaceCamSwitchIsOffAndOutOfReachInWindowMode() {
        let window = NookRecordRules.faceCamSwitch(capture: .window, wanted: true)
        #expect(!window.isOn && !window.isEnabled)
        #expect(window.helpKey == "nook.record.facecam.windowHelp")
        for capture in [NookRecordCapture.fullScreen, .area] {
            let on = NookRecordRules.faceCamSwitch(capture: capture, wanted: true)
            #expect(on.isOn && on.isEnabled && on.helpKey == nil)
            let off = NookRecordRules.faceCamSwitch(capture: capture, wanted: false)
            #expect(!off.isOn && off.isEnabled)
        }
        #expect(!NookRecordRules.faceCamFits(target: .pickedWindow))
        #expect(NookRecordRules.faceCamFits(target: .display(1)))
        #expect(NookRecordRules.faceCamFits(target: .area(1, .zero)))
    }

    @Test func theWindowHelpIsTheSentenceTheFixListWrote() throws {
        let en = try NookRecordStringsTests.table("en")
        #expect(en["nook.record.facecam.windowHelp"] == "The face cam shows in Full screen and Area recordings.")
    }

    // MARK: A failure the small card keeps (R12)

    @Test func theSmallCardKeepsAFailureAndTheMediumAndLargeAlreadyDid() {
        let failure = NookRecordStatusLine.of(.failed(.screenPermissionDenied))
        #expect(NookRecordCardLayout.smallCardShowsStatus(failure))
        let warned = NookRecordStatusLine.of(.finished(Self.folder, endedBy: .system))
        #expect(NookRecordCardLayout.smallCardShowsStatus(warned))
        // A plain saved line has no room on the small card, and the tray says it.
        #expect(!NookRecordCardLayout.smallCardShowsStatus(NookRecordStatusLine.of(.finished(Self.folder, endedBy: .user))))
        #expect(!NookRecordCardLayout.smallCardShowsStatus(nil))
    }

    @Test func aFailureStaysUntilTheNextPressAndATapClearsIt() async {
        let recorder = FakeRecorder()
        recorder.startReport = .failed(.pickerFailed)
        let model = makeModel(recorder)
        await model.record(target: .display(1), islandWindows: [])
        #expect(model.phase == .failed(.pickerFailed))
        // Something else coming up in the closed notch does not touch it.
        #expect(NookRecordStatusLine.of(model.phase)?.isWarning == true)

        model.dismissResult()
        #expect(model.phase == .idle)

        recorder.startReport = nil
        await model.record(target: .display(1), islandWindows: [])
        #expect(NookRecordStatusLine.of(model.phase) == nil)
    }

    @Test func dismissingDoesNothingWhileRecording() async {
        let recorder = FakeRecorder()
        let model = makeModel(recorder)
        await model.record(target: .display(1), islandWindows: [])
        model.dismissResult()
        if case .recording = model.phase {} else { Issue.record("expected recording, got \(model.phase)") }
    }

    // MARK: From a person's press

    func modelWithPicker(_ recorder: FakeRecorder, rect: CGRect?) -> (NookRecordModel, RecordFakeAreaPicker) {
        let model = makeModel(recorder)
        let picker = RecordFakeAreaPicker(rect: rect)
        model.activate(NookRecordServices(bubble: RecordFakeBubble(), areaPicker: picker, hotkeyRegistrar: RecordFakeRegistrar()))
        model.surroundings = NookRecordSurroundings(displayID: { 7 }, islandWindows: { [21, 22] })
        return (model, picker)
    }

    @Test func fullScreenRecordsTheIslandsDisplayAndLeavesTheIslandOutWhenAsked() async {
        let recorder = FakeRecorder()
        let (model, picker) = modelWithPicker(recorder, rect: nil)
        await model.toggleFromUser()
        #expect(recorder.starts.first?.1 == .display(7))
        #expect(recorder.starts.first?.3 == [21, 22])
        #expect(picker.displays.isEmpty)
    }

    @Test func windowAsksTheEngineForItsPicker() async {
        let recorder = FakeRecorder()
        let (model, _) = modelWithPicker(recorder, rect: nil)
        model.options.capture = .window
        await model.toggleFromUser()
        #expect(recorder.starts.first?.1 == .pickedWindow)
    }

    @Test func areaRecordsWhatWasDrawn() async {
        let recorder = FakeRecorder()
        let drawn = CGRect(x: 10, y: 20, width: 400, height: 300)
        let (model, picker) = modelWithPicker(recorder, rect: drawn)
        model.options.capture = .area
        await model.toggleFromUser()
        #expect(recorder.starts.first?.1 == .area(7, drawn))
        #expect(picker.displays == [7])
    }

    @Test func anAreaThatWasNotDrawnStartsNothing() async {
        let recorder = FakeRecorder()
        let (model, _) = modelWithPicker(recorder, rect: nil)
        model.options.capture = .area
        await model.toggleFromUser()
        #expect(recorder.starts.isEmpty)
        #expect(model.phase == .idle)
    }

    @Test func areaWithNoOverlayStartsNothing() async {
        let recorder = FakeRecorder()
        let model = makeModel(recorder)
        model.options.capture = .area
        await model.toggleFromUser()
        #expect(recorder.starts.isEmpty)
    }

    @Test func aPressWhileRecordingStopsWhateverIsChosen() async {
        let recorder = FakeRecorder()
        let (model, _) = modelWithPicker(recorder, rect: nil)
        await model.toggleFromUser()
        model.options.capture = .area
        await model.toggleFromUser()
        #expect(recorder.stops == 1)
        #expect(recorder.starts.count == 1)
    }

    @Test func aBareModelRecordsTheMainDisplay() async {
        let recorder = FakeRecorder()
        await makeModel(recorder).toggleFromUser()
        #expect(recorder.starts.first?.1 == .display(CGMainDisplayID()))
        #expect(recorder.starts.first?.3 == [])
    }

    // MARK: The closed notch's text

    @Test func theClosedNotchShowsTheCountThenTheClockThenPaused() async {
        let recorder = FakeRecorder()
        let model = makeModel(recorder)
        let now = Date(timeIntervalSince1970: 0)
        #expect(model.closedRecording(now: now) == nil)
        model.phase = .countdown(secondsLeft: 2)
        #expect(model.closedRecording(now: now)?.text == "2")
        model.phase = .countdown(secondsLeft: 0)
        #expect(model.closedRecording(now: now)?.text == "0:00")
        model.phase = .recording(startedAt: now, pausedTotal: 5)
        let running = model.closedRecording(now: now.addingTimeInterval(65))
        #expect(running?.text == "1:00")
        #expect(running?.isPaused == false)
        model.phase = .paused(startedAt: now, pausedAt: now.addingTimeInterval(30), pausedTotal: 0)
        let paused = model.closedRecording(now: now.addingTimeInterval(900))
        #expect(paused?.text == "0:30")
        #expect(paused?.isPaused == true)
        model.phase = .saving
        #expect(model.closedRecording(now: now) == nil)
        model.phase = .finished(Self.folder, endedBy: .user)
        #expect(model.closedRecording(now: now) == nil)
    }

    @Test func isRunningMeansCountingRecordingOrPaused() {
        let model = makeModel(FakeRecorder())
        let now = Date(timeIntervalSince1970: 0)
        #expect(!model.isRunning)
        model.phase = .countdown(secondsLeft: 3)
        #expect(model.isRunning)
        model.phase = .recording(startedAt: now, pausedTotal: 0)
        #expect(model.isRunning)
        model.phase = .paused(startedAt: now, pausedAt: now, pausedTotal: 0)
        #expect(model.isRunning)
        model.phase = .saving
        #expect(!model.isRunning)
        model.phase = .failed(.writeFailed)
        #expect(!model.isRunning)
    }
}

// MARK: - In the Nook

@MainActor @Suite(.noNewWindows) struct NookRecordInTheNookTests {
    func makeNook(_ recorder: FakeRecorder) -> (NookModel, NookRecordModel) {
        let defaults = MemoryDefaults()
        let record = NookRecordModel(
            recorder: recorder,
            defaults: defaults,
            folder: NookRecordModelTests.folder,
            createFolder: { _ in },
            sleep: { _ in },
            fileExists: { _ in false }
        )
        let nook = NookModel(record: record, defaults: defaults, looksForImportedGIF: false, asksMacOSForAccess: false)
        record.start(nook: nook)
        return (nook, record)
    }

    @Test func recordIsOffUntilItIsSwitchedOn() {
        #expect(!NookWidgetKind.defaultEnabled.contains(.record))
        #expect(NookWidgetKind.startsOff.contains(.record))
        let (nook, _) = makeNook(FakeRecorder())
        #expect(!nook.isWidgetEnabled(.record))
    }

    @Test func theWidgetHasItsTitleAndSymbol() {
        #expect(NookWidgetKind.record.title == LanguageManager.shared.t("nook.record.title"))
        #expect(NookWidgetKind.record.systemImage == "record.circle")
        // Record sits right after the originals, before the design kit and Link to MP3.
        #expect(NookWidgetKind.allCases.firstIndex(of: .record) == NookWidgetKind.allCases.firstIndex(of: .weather).map { $0 + 1 })
    }

    @Test func theClosedNotchShowsTheRecordingAboveEverythingElse() async {
        let recorder = FakeRecorder()
        let (nook, record) = makeNook(recorder)
        await record.record(target: .display(1), islandWindows: [])
        let activity = nook.closedActivity(for: NookDisplayPreferences(), isHidden: true)
        #expect(activity?.leading == .symbol("record.circle.fill", .red))
        if case .text? = activity?.trailing {} else { Issue.record("expected the clock, got \(String(describing: activity?.trailing))") }
    }

    @Test func theMirrorCannotBeTurnedOnWhileTheBubbleIsUp() async {
        let recorder = FakeRecorder()
        let (nook, record) = makeNook(recorder)
        record.activate(NookRecordServices(
            bubble: RecordFakeBubble(),
            areaPicker: RecordFakeAreaPicker(rect: nil),
            hotkeyRegistrar: RecordFakeRegistrar()
        ))
        record.options.faceCam = true
        await record.record(target: .display(1), islandWindows: [])
        nook.isMirrorOn = true
        #expect(!nook.isMirrorOn)
        await record.stop()
        nook.isMirrorOn = true
        #expect(nook.isMirrorOn)
        nook.isMirrorOn = false
    }

    @Test func theBubbleTurnsAnOpenMirrorOff() async {
        let recorder = FakeRecorder()
        let (nook, record) = makeNook(recorder)
        record.activate(NookRecordServices(
            bubble: RecordFakeBubble(),
            areaPicker: RecordFakeAreaPicker(rect: nil),
            hotkeyRegistrar: RecordFakeRegistrar()
        ))
        nook.isMirrorOn = true
        record.options.faceCam = true
        await record.record(target: .display(1), islandWindows: [])
        #expect(!nook.isMirrorOn)
    }

    @Test func switchingTheWidgetOffFinishesARecordingUnderWay() async {
        let recorder = FakeRecorder()
        let (nook, record) = makeNook(recorder)
        nook.setWidget(.record, enabled: true)
        await record.record(target: .display(1), islandWindows: [])
        nook.setWidget(.record, enabled: false)
        for _ in 0..<100 where recorder.stops == 0 { await Task.yield() }
        #expect(recorder.stops == 1)
    }

    @Test func theRecordShortcutIsReservedFromTheAgentsOnlyWhileTheWidgetIsOn() {
        let (nook, record) = makeNook(FakeRecorder())
        #expect(record.reservedShortcuts.isEmpty)
        nook.setWidget(.record, enabled: true)
        #expect(record.reservedShortcuts == [NookRecordHotkeyRules.defaultCombo])
        nook.setWidget(.record, enabled: false)
        #expect(record.reservedShortcuts.isEmpty)
    }

    @Test func noticesGoToTheNookAfterItStarted() async {
        let recorder = FakeRecorder()
        let (nook, record) = makeNook(recorder)
        await record.record(target: .display(1), islandWindows: [])
        await record.stop()
        #expect(nook.transient?.text == LanguageManager.shared.t("nook.record.notice.saved"))
    }
}

// MARK: - The shortcut

@MainActor @Suite struct NookRecordHotkeyTests {
    func makeController(
        defaults: UserDefaults = MemoryDefaults(),
        registrar: RecordFakeRegistrar? = RecordFakeRegistrar(),
        others: [AgentHotkeyCombo] = []
    ) -> (NookRecordHotkeyController, RecordFakeRegistrar?) {
        let controller = NookRecordHotkeyController(defaults: defaults)
        controller.otherShortcuts = { others }
        if let registrar { controller.activate(registrar: registrar) }
        return (controller, registrar)
    }

    let controlOptionR = AgentHotkeyCombo(keyCode: 15, modifiers: [.control, .option])
    let controlOptionK = AgentHotkeyCombo(keyCode: 40, modifiers: [.control, .option])

    @Test func theDefaultIsControlOptionR() {
        let (controller, _) = makeController()
        #expect(controller.combo == controlOptionR)
        #expect(controller.displayText == "⌃⌥R")
    }

    @Test func nothingIsHeldUntilTheWidgetIsOn() {
        let (controller, registrar) = makeController()
        #expect(registrar?.registered.isEmpty == true)
        #expect(controller.status == .inactive)
        controller.setLive(true)
        #expect(registrar?.registered == [controlOptionR])
        #expect(controller.status == .ready)
        controller.setLive(false)
        #expect(registrar?.unregisters ?? 0 >= 1)
        #expect(controller.status == .inactive)
    }

    @Test func aBareControllerNeverRegistersAnything() {
        let (controller, _) = makeController(registrar: nil)
        controller.setLive(true)
        #expect(controller.status == .inactive)
    }

    @Test func aPressReachesTheModel() {
        let (controller, registrar) = makeController()
        var presses = 0
        controller.onPress = { presses += 1 }
        controller.setLive(true)
        registrar?.press()
        #expect(presses == 1)
    }

    @Test func aNewShortcutIsSavedRegisteredAndReadBack() {
        let defaults = MemoryDefaults()
        let (controller, registrar) = makeController(defaults: defaults)
        controller.setLive(true)
        #expect(controller.setCombo(controlOptionK) == nil)
        #expect(registrar?.registered.last == controlOptionK)
        let (again, _) = self.makeController(defaults: defaults)
        #expect(again.combo == controlOptionK)
    }

    @Test func oneModifierIsRefusedAndNothingChanges() {
        let (controller, registrar) = makeController()
        controller.setLive(true)
        let weak = AgentHotkeyCombo(keyCode: 40, modifiers: [.shift])
        #expect(controller.setCombo(weak) == .needsModifiers)
        #expect(controller.combo == controlOptionR)
        #expect(registrar?.registered == [controlOptionR])
    }

    @Test func aShortcutAnotherHangoverFeatureHoldsIsRefused() {
        let (controller, _) = makeController(others: [controlOptionK])
        #expect(controller.setCombo(controlOptionK) == .usedByAnotherShortcut)
        #expect(controller.combo == controlOptionR)
    }

    @Test func macOSRefusingTheKeysIsShown() {
        let registrar = RecordFakeRegistrar()
        registrar.outcome = .failed(code: -9878)
        let (controller, _) = makeController(registrar: registrar)
        controller.setLive(true)
        #expect(controller.status == .failed(code: -9878))
    }

    @Test func aSystemShortcutIsNotTakenOver() {
        let registrar = RecordFakeRegistrar()
        registrar.system = [controlOptionR]
        let (controller, _) = makeController(registrar: registrar)
        controller.setLive(true)
        #expect(controller.status == .usedBySystem)
        #expect(registrar.registered.isEmpty)
    }

    @Test func nothingIsHeldWhileANewShortcutIsRecorded() {
        let (controller, registrar) = makeController()
        controller.setLive(true)
        var told: [Bool] = []
        controller.onRecordingChange = { told.append($0) }
        controller.beginRecording()
        #expect(controller.isRecording)
        #expect((registrar?.unregisters ?? 0) >= 1)
        controller.endRecording()
        #expect(told == [true, false])
        #expect(registrar?.registered.count == 2)
    }

    @Test func resetGoesBackToTheDefault() {
        let defaults = MemoryDefaults()
        let (controller, _) = makeController(defaults: defaults)
        controller.setCombo(controlOptionK)
        controller.resetToDefault()
        #expect(controller.combo == controlOptionR)
        let (again, _) = self.makeController(defaults: defaults)
        #expect(again.combo == controlOptionR)
    }
}

// MARK: - Strings

@Suite struct NookRecordStringsTests {
    /// `Tests/OpenIslandAppTests/<this file>` sits three levels below the root.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static let languages = ["en", "zh-Hans", "zh-Hant"]

    static func table(_ language: String) throws -> [String: String] {
        let url = repoRoot.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")
    }

    /// Every "nook.record." key written out in the Record source files, the
    /// Mirror card and the Nook model, plus the ones built from an enum.
    private static func usedKeys() throws -> Set<String> {
        let sources = repoRoot.appendingPathComponent("Sources/OpenIslandApp/Nook")
        let record = try FileManager.default.contentsOfDirectory(
            at: sources.appendingPathComponent("Widgets/Record"), includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        let files = record + [
            sources.appendingPathComponent("Widgets/Mirror/NookMirrorCard.swift"),
            sources.appendingPathComponent("NookModel.swift"),
        ]
        let pattern = try NSRegularExpression(pattern: "\"(nook\\.record\\.[A-Za-z0-9.]+)\"")
        var keys = Set<String>()
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in pattern.matches(in: source, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
                keys.insert(String(source[keyRange]))
            }
        }
        // Settings keys are not strings to show.
        keys.subtract([
            NookRecordModel.captureKey, NookRecordModel.faceCamKey, NookRecordModel.voiceKey,
            NookRecordModel.macSoundKey, NookRecordModel.qualityKey, NookRecordModel.includeIslandKey,
            NookRecordHotkeyController.comboKey,
        ])
        keys.formUnion(NookRecordCapture.allCases.map(\.titleKey))
        keys.formUnion(NookRecordQuality.allCases.map(\.titleKey))
        keys.formUnion(NookFaceCamSize.allCases.map(\.titleKey))
        keys.formUnion([
            NookRecordFailure.screenPermissionDenied, .micPermissionDenied, .pickerCancelled,
            .noDisplay, .lowDisk, .writeFailed, .noPicture, .couldNotStart, .writerFailed(atSeconds: 0),
            .noMicrophone, .pickerFailed,
        ].map(\.noticeKey))
        keys.formUnion(["nook.record.notice.system", "nook.record.notice.keptPartial"])
        keys.formUnion([NookRecordHotkeyProblem.needsModifiers, .usedByAnotherShortcut].map(\.messageKey))
        return keys
    }

    @Test func everyRecordStringExistsInEveryLanguageAndHasNoDash() throws {
        let keys = try Self.usedKeys()
        #expect(keys.count > 30)

        for language in Self.languages {
            let table = try Self.table(language)
            for key in keys.sorted() {
                let value = table[key] ?? ""
                #expect(!value.isEmpty, "\(language) has no \(key)")
                #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(language) \(key) has a dash")
            }
        }
    }

    @Test func nothingThePersonReadsSaysOpenIslandOrNook() throws {
        for language in Self.languages {
            let table = try Self.table(language)
            for key in try Self.usedKeys().sorted() {
                let value = table[key] ?? ""
                #expect(!value.contains("Open Island") && !value.contains("OpenIsland"), "\(language) \(key) names the code")
            }
        }
    }

    @Test func theFailureSentencesAreTheOnesTheSpecWrote() throws {
        let en = try Self.table("en")
        #expect(en["nook.record.failure.screenPermission"] == "Hangover needs Screen Recording. Turn it on in System Settings, Privacy & Security.")
        #expect(en["nook.record.failure.micPermission"] == "Turn on the microphone for Hangover in System Settings to record your voice.")
        #expect(en["nook.record.failure.pickerCancelled"] == "No window was picked.")
        #expect(en["nook.record.failure.noDisplay"] == "That screen is not connected anymore.")
        #expect(en["nook.record.failure.lowDisk"] == "Less than 1 GB is free. Free up space, then record.")
        #expect(en["nook.record.failure.writeFailed"] == "The recording could not be saved.")
        #expect(en["nook.record.notice.saved"] == "Recording saved to Movies/Hangover")
        #expect(en["nook.record.failure.noPicture"] == "The screen sent no picture. Nothing was recorded.")
        #expect(en["nook.record.failure.couldNotStart"] == "The recording could not start.")
        #expect(en["nook.record.failure.writerFailed"] == "Recording stopped at %@: the file could not be written.")
    }
}
