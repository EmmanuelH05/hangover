import CoreGraphics
import Foundation
import Observation
import OSLog
import SwiftUI

private let modelLog = Logger(subsystem: "app.openisland", category: "record")

/// What the record model asks the app about. The app model installs these;
/// a bare model records the main display and leaves no window out.
struct NookRecordSurroundings {
    /// The display the island is on, which "Full screen" records.
    var displayID: () -> CGDirectDisplayID = { CGMainDisplayID() }
    /// The island's own windows, which the engine leaves out of the video
    /// when "Show the notch in recordings" is off.
    var islandWindows: () -> [CGWindowID] = { [] }
}

/// The parts of Record that reach outside the app's own state: the face cam
/// bubble, the area overlay and the shortcut. Only a real launch hands them
/// over. A test, a harness run and a bare model have none, which is what
/// keeps them from opening a window, starting the camera or holding keys.
@MainActor
struct NookRecordServices {
    var bubble: any NookFaceCamPresenting
    var areaPicker: any NookRecordAreaPicking
    var hotkeyRegistrar: any NookRecordHotkeyRegistering

    static func system(screen: @escaping @MainActor () -> NSScreen?) -> NookRecordServices {
        NookRecordServices(
            bubble: NookFaceCamBubble(screen: screen),
            areaPicker: NookRecordAreaPicker(),
            hotkeyRegistrar: NookRecordCarbonHotkey()
        )
    }
}

/// The Record widget's state: what is chosen, where a recording is, the
/// countdown, and the hand-off of the file once it is saved. The engine
/// behind it is `NookRecording`; the real one needs a screen and a person,
/// so tests give this a fake.
@MainActor
@Observable
final class NookRecordModel {
    nonisolated static let captureKey = "nook.record.capture"
    nonisolated static let faceCamKey = "nook.record.faceCam"
    nonisolated static let voiceKey = "nook.record.voice"
    nonisolated static let macSoundKey = "nook.record.macSound"
    nonisolated static let qualityKey = "nook.record.quality"
    nonisolated static let includeIslandKey = "nook.record.includeIsland"

    /// Seconds counted before the first frame.
    nonisolated static let countdownSeconds = 3

    /// What the card and Settings have chosen. Each change is saved.
    var options: NookRecordOptions {
        didSet { saveChanges(from: oldValue) }
    }

    /// Where a recording is. The countdown is the model's alone; every other
    /// phase comes from the engine. `.countdown(secondsLeft: 0)` is the gap
    /// between the last count and the engine's first report, when a press
    /// must not start a second stream.
    var phase: NookRecordPhase = .idle {
        didSet { syncTicker() }
    }

    /// True while the face cam bubble is up. The Mirror gives up the camera
    /// for as long.
    private(set) var isFaceCamUp = false {
        didSet { if isFaceCamUp != oldValue { onFaceCamChange(isFaceCamUp) } }
    }

    /// Changes each second while recording. The closed notch reads it, which
    /// is what makes the timer there move.
    private(set) var tick = Date.distantPast

    /// Whether the widget is switched on.
    private(set) var isLive = false

    let hotkey: NookRecordHotkeyController

    @ObservationIgnored var surroundings = NookRecordSurroundings()
    /// Shows a short notice in the closed notch. The Nook installs it.
    @ObservationIgnored var showNotice: (_ symbol: String, _ text: String, _ tint: Color) -> Void = { _, _, _ in }
    /// Told when the bubble comes up or goes. The Nook turns the Mirror off.
    @ObservationIgnored var onFaceCamChange: (Bool) -> Void = { _ in }

    @ObservationIgnored private weak var nook: NookModel?
    @ObservationIgnored private let recorder: any NookRecording
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let createFolder: (URL) throws -> Void
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let fileExists: (URL) -> Bool
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let onFinished: (URL) -> Void
    @ObservationIgnored private var bubble: (any NookFaceCamPresenting)?
    @ObservationIgnored private var areaPicker: (any NookRecordAreaPicking)?
    /// Names the countdown that is running. A press clears it, and a count
    /// that wakes up to another name stops without touching anything.
    @ObservationIgnored private var countdownToken: UUID?
    /// True while the person is drawing an area, before any countdown.
    @ObservationIgnored private var isChoosingTarget = false
    /// True from a Stop until the engine has closed the file.
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    /// The app passes the defaults, the real folder and `onFinished` that
    /// hands the file to the tray. Tests pass a fake engine, settings held in
    /// memory, a `sleep` that returns at once, and a `createFolder` that
    /// touches no disk.
    init(
        recorder: any NookRecording,
        defaults: UserDefaults,
        folder: URL = NookRecordFiles.folder(),
        createFolder: @escaping (URL) throws -> Void = {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        now: @escaping () -> Date = Date.init,
        onFinished: @escaping (URL) -> Void = { _ in }
    ) {
        self.recorder = recorder
        self.defaults = defaults
        self.folder = folder
        self.createFolder = createFolder
        self.sleep = sleep
        self.fileExists = fileExists
        self.now = now
        self.onFinished = onFinished
        options = Self.loadOptions(from: defaults)
        hotkey = NookRecordHotkeyController(defaults: defaults)
        recorder.onPhaseChange = { [weak self] phase in self?.recorderReported(phase) }
        recorder.onWarning = { [weak self] warning in self?.recorderWarned(warning) }
        hotkey.onPress = { [weak self] in
            Task { @MainActor in await self?.toggleFromUser() }
        }
        hotkey.onRefused = { [weak self] _ in self?.hotkeyRefused() }
    }

    isolated deinit {
        tickTask?.cancel()
    }

    // MARK: Settings

    private static func loadOptions(from defaults: UserDefaults) -> NookRecordOptions {
        var options = NookRecordOptions()
        options.capture = defaults.string(forKey: captureKey).flatMap(NookRecordCapture.init(rawValue:)) ?? options.capture
        options.faceCam = defaults.object(forKey: faceCamKey) as? Bool ?? options.faceCam
        options.voice = defaults.object(forKey: voiceKey) as? Bool ?? options.voice
        options.macSound = defaults.object(forKey: macSoundKey) as? Bool ?? options.macSound
        options.quality = defaults.string(forKey: qualityKey).flatMap(NookRecordQuality.init(rawValue:)) ?? options.quality
        options.includeIsland = defaults.object(forKey: includeIslandKey) as? Bool ?? options.includeIsland
        return options
    }

    private func saveChanges(from old: NookRecordOptions) {
        if options.capture != old.capture { defaults.set(options.capture.rawValue, forKey: Self.captureKey) }
        if options.faceCam != old.faceCam { defaults.set(options.faceCam, forKey: Self.faceCamKey) }
        if options.voice != old.voice { defaults.set(options.voice, forKey: Self.voiceKey) }
        if options.macSound != old.macSound { defaults.set(options.macSound, forKey: Self.macSoundKey) }
        if options.quality != old.quality { defaults.set(options.quality.rawValue, forKey: Self.qualityKey) }
        if options.includeIsland != old.includeIsland { defaults.set(options.includeIsland, forKey: Self.includeIslandKey) }
    }

    // MARK: Lifecycle

    /// Joins the model to the Nook: its notices, and the Mirror that gives up
    /// the camera. Called once from `NookModel.start`.
    func start(nook: NookModel) {
        self.nook = nook
        showNotice = { [weak nook] symbol, text, tint in
            nook?.showTransient(symbol: symbol, text: text, tint: tint, duration: .seconds(6))
        }
        onFaceCamChange = { [weak nook] isUp in
            if isUp { nook?.isMirrorOn = false }
        }
        setLive(nook.isWidgetEnabled(.record))
    }

    /// Hands over the services that reach outside the app. Called once, on a
    /// real launch.
    func activate(_ services: NookRecordServices) {
        bubble = services.bubble
        bubble?.onProblem = { [weak self] problem in self?.faceCamProblem(problem) }
        areaPicker = services.areaPicker
        hotkey.activate(registrar: services.hotkeyRegistrar)
    }

    /// The widget's switch in the Nook tab moved. A model that was never
    /// started ignores it, which keeps a bare model in a test from holding keys.
    func widgetSwitched(_ isOn: Bool) {
        guard nook != nil else { return }
        setLive(isOn)
    }

    private func setLive(_ live: Bool) {
        guard live != isLive else { return }
        isLive = live
        hotkey.setLive(live)
        // A widget switched off takes its recording with it: the shortcut
        // that would stop it is gone, and the card with the button too.
        if !live { Task { await stop() } }
    }

    /// The Record shortcut as long as it is held, for the agent shortcuts and the
    /// eyedropper's to stay clear of. One that broke a rule holds nothing.
    var reservedShortcuts: [AgentHotkeyCombo] {
        isLive && !hotkey.status.isInvalid ? [hotkey.combo] : []
    }

    // MARK: Pressing

    /// What the Record button, the shortcut and a click on the closed notch
    /// mean. Idle starts a recording on what `options.capture` says, and the
    /// rest is `toggle`.
    func toggleFromUser() async {
        if phase.isBusy {
            await stop()
            return
        }
        guard !isChoosingTarget else { return }
        isChoosingTarget = true
        let target = await resolveTarget(for: options.capture)
        isChoosingTarget = false
        guard let target else { return }
        await record(target: target, islandWindows: surroundings.islandWindows())
    }

    /// Where `capture` points. Nil when nothing was chosen: the area was not
    /// drawn, or the app has no overlay to draw it with.
    private func resolveTarget(for capture: NookRecordCapture) async -> NookRecordTarget? {
        let displayID = surroundings.displayID()
        switch capture {
        case .fullScreen:
            return .display(displayID)
        case .window:
            return .pickedWindow
        case .area:
            guard let areaPicker, let rect = await areaPicker.pick(on: displayID) else { return nil }
            return .area(displayID, rect)
        }
    }

    /// A press with a target in hand. In the countdown it cancels, while
    /// recording or paused it stops, while saving it does nothing, and
    /// otherwise it records.
    func toggle(target: NookRecordTarget, islandWindows: [CGWindowID]) async {
        if phase.isBusy {
            await stop()
        } else {
            await record(target: target, islandWindows: islandWindows)
        }
    }

    // MARK: Recording

    /// Counts 3, 2, 1 and starts the engine. Returns once the engine's
    /// `start` returns, or at once when the countdown was cancelled.
    func record(target: NookRecordTarget, islandWindows: [CGWindowID]) async {
        guard !phase.isBusy else { return }
        // What was chosen when the button was pressed is what is recorded,
        // however the switches move during the count.
        var chosen = options
        // A recording of one window cannot hold the bubble, whatever the switch says.
        chosen.faceCam = chosen.faceCam && NookRecordRules.faceCamFits(target: target)
        let token = UUID()
        countdownToken = token
        // The camera warms up while the count runs, which keeps the bubble's
        // first second from being black.
        if chosen.faceCam { showFaceCam(placement: .of(target)) }

        // A window is picked in Apple's picker after this, and that click is
        // the start: counting before the picker even shows only gets in the way.
        let countsDown = target != .pickedWindow
        for secondsLeft in stride(from: Self.countdownSeconds, through: 1, by: -1) where countsDown {
            phase = .countdown(secondsLeft: secondsLeft)
            do {
                try await sleep(.seconds(1))
            } catch {
                if countdownToken == token { cancelCountdown() }
                return
            }
            guard countdownToken == token else { return }
        }
        countdownToken = nil
        phase = .countdown(secondsLeft: 0)

        let fileURL: URL
        do {
            try createFolder(folder)
            fileURL = NookRecordFiles.uniqueURL(
                in: folder,
                name: NookRecordFiles.fileName(for: now()),
                exists: fileExists
            )
        } catch {
            modelLog.error("record: could not make the recordings folder: \(NookRecordRules.describe(error), privacy: .public)")
            recorderReported(.failed(.writeFailed))
            return
        }
        await recorder.start(options: chosen, target: target, fileURL: fileURL, islandWindows: islandWindows)
    }

    func pause() {
        guard case .recording = phase else { return }
        recorder.pause()
    }

    func resume() {
        guard case .paused = phase else { return }
        recorder.resume()
    }

    /// Ends the countdown, cancels an engine that is still starting, or
    /// finishes the file of a recording. While saving, or with nothing under
    /// way, it does nothing.
    func stop() async {
        switch phase {
        case let .countdown(secondsLeft):
            if secondsLeft > 0 {
                cancelCountdown()
            } else if await stopEngine() {
                // An engine with nothing to stop reports nothing, and a card
                // that says "Starting" for good is the bug this guards.
                if phase == .countdown(secondsLeft: 0) {
                    hideFaceCam()
                    phase = .idle
                }
            }
        case .recording, .paused:
            await stopEngine()
        case .idle, .saving, .finished, .failed:
            break
        }
    }

    /// One stop at a time reaches the engine. False when one is already on its way.
    @discardableResult
    private func stopEngine() async -> Bool {
        guard !isStopping else { return false }
        isStopping = true
        await recorder.stop()
        isStopping = false
        return true
    }

    /// Clears a failure, or a result, the card has been keeping. The next press of
    /// Record clears it too.
    func dismissResult() {
        switch phase {
        case .failed, .finished: phase = .idle
        case .idle, .countdown, .recording, .paused, .saving: break
        }
    }

    private func cancelCountdown() {
        countdownToken = nil
        hideFaceCam()
        phase = .idle
    }

    /// Finishes a recording that is under way before the app quits. Returns
    /// once the file is closed. The caller puts its own limit on the wait.
    func prepareForQuit() async {
        guard phase.isBusy else { return }
        await stop()
        // A stop that was already under way, a file still being closed, or a
        // start that is still unwinding.
        while !Task.isCancelled, isStopping || phase == .saving || phase == .countdown(secondsLeft: 0) {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: Engine reports

    private func recorderReported(_ new: NookRecordPhase) {
        phase = new
        switch new {
        case let .finished(url, endedBy, notes):
            hideFaceCam()
            onFinished(url)
            let notice = NookRecordNotice.saved(endedBy: endedBy, notes: notes, lang: LanguageManager.shared)
            showNotice(notice.symbol, notice.text, notice.isWarning ? .orange : .white)
        case let .failed(failure):
            hideFaceCam()
            let notice = NookRecordNotice.failed(failure, lang: LanguageManager.shared)
            showNotice(notice.symbol, notice.text, .orange)
        case .idle:
            // A start that was cancelled took the bubble up with it.
            hideFaceCam()
        case .countdown, .recording, .paused, .saving:
            break
        }
    }

    /// Something went wrong that the recording goes on through: said once, in the
    /// closed notch, while it is still happening.
    private func recorderWarned(_ warning: NookRecordWarning) {
        showNotice("mic.slash.fill", LanguageManager.shared.t(warning.noticeKey), .orange)
    }

    /// macOS would not give the shortcut, or already uses it: said once, where the
    /// person is looking. Settings shows it too, but they are not in Settings.
    private func hotkeyRefused() {
        showNotice("exclamationmark.triangle.fill", LanguageManager.shared.t("nook.record.hotkey.refused"), .orange)
    }

    // MARK: Face cam

    private func showFaceCam(placement: NookFaceCamPlacement) {
        guard let bubble else { return }
        // Marked up before the bubble is asked to show. A camera that is denied
        // or missing says so from inside `show`, and `hideFaceCam` only clears
        // a bubble that is marked up. Marked after, the problem would find
        // nothing to clear and the bubble would be taken for up all recording.
        isFaceCamUp = true
        bubble.show(placement: placement)
    }

    /// The bubble could not show a picture and has closed itself. The recording
    /// goes on without it, and the island says why. The camera is free again, so
    /// the Mirror may have it back.
    private func faceCamProblem(_ problem: NookFaceCamProblem) {
        hideFaceCam()
        showNotice("video.slash.fill", LanguageManager.shared.t(problem.noticeKey), .orange)
    }

    private func hideFaceCam() {
        guard isFaceCamUp else { return }
        bubble?.hide()
        isFaceCamUp = false
    }

    // MARK: Closed notch

    /// True from the first count to the stop. A click on the closed notch
    /// means "stop" for as long.
    var isRunning: Bool {
        switch phase {
        case .countdown, .recording, .paused: true
        case .idle, .saving, .finished, .failed: false
        }
    }

    /// What the closed notch shows: the count, then the elapsed time. Nil
    /// when nothing is being recorded.
    func closedRecording(now: Date) -> (text: String, isPaused: Bool)? {
        // Read so the closed notch is told when a second has passed.
        _ = tick
        switch phase {
        case let .countdown(secondsLeft):
            return (secondsLeft > 0 ? "\(secondsLeft)" : NookRecordClock.text(0), false)
        case .recording:
            return (NookRecordClock.text(NookRecordClock.elapsed(phase, now: now)), false)
        case .paused:
            return (NookRecordClock.text(NookRecordClock.elapsed(phase, now: now)), true)
        case .idle, .saving, .finished, .failed:
            return nil
        }
    }

    /// Runs a one-second timer while recording, and not otherwise.
    private func syncTicker() {
        let isRecording: Bool
        if case .recording = phase { isRecording = true } else { isRecording = false }
        guard isRecording else {
            tickTask?.cancel()
            tickTask = nil
            return
        }
        guard tickTask == nil else { return }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                tick = now()
            }
        }
    }
}
