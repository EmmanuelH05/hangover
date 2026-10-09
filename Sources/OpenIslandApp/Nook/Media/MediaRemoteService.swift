import AppKit
import Foundation
import OSLog

private let mediaLog = Logger(subsystem: "app.openisland", category: "nook.media")

/// Reads system Now Playing state through the vendored MediaRemote adapter.
///
/// Apple stopped letting ordinary apps read `MediaRemote` on macOS 15.4, so
/// the adapter runs its code inside `/usr/bin/perl`, which is still allowed.
/// This service keeps one `perl … stream` process alive, merges its diffed
/// JSON lines into a full payload, and publishes `NowPlayingState` values
/// on the main actor. Commands (`play`, `next`, …) are one-shot `perl … send`
/// invocations.
@MainActor
@Observable
final class MediaRemoteService {
    private(set) var state: NowPlayingState?
    private(set) var isAvailable = false
    private(set) var lastError: String?
    /// The scrub bar's seeks: the one the player has not answered yet, and
    /// the tracks whose player ignored one.
    private(set) var seekTracker = NookSeekTracker()

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var reader: StreamReader?
    @ObservationIgnored private var restartAttempts = 0
    @ObservationIgnored private var stopped = true
    @ObservationIgnored private let locator = MediaRemoteAdapterLocator()
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var hasReapedOrphans = false
    @ObservationIgnored private var seekCheck: Task<Void, Never>?
    /// Starts one adapter command and says whether it could be started.
    /// Nil runs the real adapter; tests pass their own.
    @ObservationIgnored private let commandLauncher: (@MainActor ([String]) -> Bool)?

    init(commandLauncher: (@MainActor ([String]) -> Bool)? = nil) {
        self.commandLauncher = commandLauncher
    }

    func start() {
        guard stopped else { return }
        stopped = false
        restartAttempts = 0
        observeAppTermination()
        launchStream()
    }

    /// The perl helper outlives the app unless something stops it, which left
    /// one orphan per quit or crash. Stop it when the app quits normally.
    private func observeAppTermination() {
        guard terminationObserver == nil else { return }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    /// Ends helpers that an earlier run of this same build left behind when it
    /// was force-quit or crashed: the same script path with launchd as parent.
    /// Helpers of a running app keep that app as their parent and are untouched.
    private static func reapOrphanedHelpers(script: URL) {
        let reaper = Process()
        reaper.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        reaper.arguments = ["-P", "1", "-f", NSRegularExpression.escapedPattern(for: script.path)]
        reaper.standardOutput = FileHandle.nullDevice
        reaper.standardError = FileHandle.nullDevice
        do {
            try reaper.run()
            reaper.waitUntilExit()
        } catch {
            mediaLog.warning("could not check for orphaned helpers: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        stopped = true
        reader = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
    }

    // MARK: - Commands

    func send(_ command: MediaRemoteCommand) {
        runOneShot(arguments: ["send", String(command.rawValue)])
    }

    func seek(to seconds: TimeInterval) {
        let micros = Int64((max(0, seconds) * 1_000_000).rounded())
        // A seek that was never sent is not the player's to answer: the
        // track must not be blamed for it.
        guard runOneShot(arguments: ["seek", String(micros)]), let state else { return }
        seekTracker.begin(target: seconds, state: state, now: Date())
        // A player that ignores the seek sends nothing new, which is why
        // the tracker is asked once more when its answer window is over.
        seekCheck?.cancel()
        seekCheck = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NookSeekTracker.answerWindow + 0.2))
            guard !Task.isCancelled, let self else { return }
            self.seekTracker.observe(self.state, now: Date())
        }
    }

    func togglePlayPause() { send(.togglePlayPause) }
    func nextTrack() { send(.nextTrack) }
    func previousTrack() { send(.previousTrack) }

    // MARK: - Stream process

    private func launchStream() {
        guard !stopped else { return }
        guard let paths = locator.resolve() else {
            isAvailable = false
            lastError = "MediaRemote adapter not found. Run scripts/build-mediaremote-adapter.sh."
            mediaLog.error("adapter not found")
            return
        }

        if !hasReapedOrphans {
            hasReapedOrphans = true
            Self.reapOrphanedHelpers(script: paths.script)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            paths.script.path,
            paths.framework.path,
            "stream",
            "--debounce=60",
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let reader = StreamReader { [weak self] state in
            Task { @MainActor [weak self] in
                self?.apply(state)
            }
        }
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            reader.ingest(data)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            mediaLog.warning("adapter stderr: \(text, privacy: .public)")
        }
        process.terminationHandler = { [weak self] proc in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            let status = proc.terminationStatus
            Task { @MainActor [weak self] in
                self?.handleTermination(status: status)
            }
        }

        do {
            try process.run()
            self.process = process
            self.reader = reader
            isAvailable = true
            lastError = nil
        } catch {
            isAvailable = false
            lastError = error.localizedDescription
            mediaLog.error("adapter launch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleTermination(status: Int32) {
        process = nil
        reader = nil
        guard !stopped else { return }
        restartAttempts += 1
        let delay = min(30, pow(2, Double(min(restartAttempts, 5))))
        mediaLog.warning("adapter exited (\(status)); restarting in \(delay)s")
        state = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.launchStream()
        }
    }

    /// Takes one state from the adapter stream.
    func apply(_ next: NowPlayingState?) {
        restartAttempts = 0
        let previous = state
        if next != state {
            state = next
        }
        // The tracker sees every report, not only those inside an answer
        // window: a late jump is what clears a track it blamed.
        var tracker = seekTracker
        tracker.observe(next, previous: previous, now: Date())
        if tracker != seekTracker { seekTracker = tracker }
    }

    /// Starts one adapter command. False when it could not be started.
    @discardableResult
    private func runOneShot(arguments: [String]) -> Bool {
        if let commandLauncher { return commandLauncher(arguments) }
        guard let paths = locator.resolve() else {
            mediaLog.error("adapter command not sent: adapter not found")
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script.path, paths.framework.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            mediaLog.error("adapter command failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

/// Accumulates stdout bytes, splits them into JSON lines, and keeps the
/// merged "full" payload the adapter's diff mode expects consumers to hold.
/// Runs on whatever thread the pipe delivers data on; the merged payload is
/// turned into a `Sendable` state value before it crosses to the main actor.
private final class StreamReader: @unchecked Sendable {
    private var buffer = Data()
    private var full: [String: Any] = [:]
    private let lock = NSLock()
    private let onState: @Sendable (NowPlayingState?) -> Void

    init(onState: @escaping @Sendable (NowPlayingState?) -> Void) {
        self.onState = onState
    }

    func ingest(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(line: Data(line))
        }
    }

    private func handle(line: Data) {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else {
            return
        }
        let isDiff = (object["diff"] as? Bool) ?? false
        if isDiff {
            for (key, value) in payload {
                if value is NSNull {
                    full.removeValue(forKey: key)
                } else {
                    full[key] = value
                }
            }
        } else {
            full = payload.filter { !($0.value is NSNull) }
        }
        onState(NowPlayingState(payload: full))
    }
}

/// Finds the perl launcher and the adapter framework. In an app bundle the
/// framework lives in `Contents/Frameworks` and the launcher in
/// `Contents/Resources` (packaged) or `Contents/Helpers` (dev); during
/// `swift run` they come from the repo's `.build/mediaremote-adapter`.
struct MediaRemoteAdapterLocator {
    struct Paths {
        let script: URL
        let framework: URL
    }

    /// The app bundle to look in. A test hands in a folder of its own.
    var bundleURL: URL = Bundle.main.bundleURL
    /// Where the override is read from. A test hands in its own.
    var environment: [String: String] = ProcessInfo.processInfo.environment

    func resolve() -> Paths? {
        for candidate in candidates() where exists(candidate) {
            return candidate
        }
        return nil
    }

    private func candidates() -> [Paths] {
        var list: [Paths] = []
        if let override = environment["OPEN_ISLAND_MEDIAREMOTE_DIR"] {
            let dir = URL(fileURLWithPath: override)
            list.append(Paths(
                script: dir.appendingPathComponent("mediaremote-adapter.pl"),
                framework: dir.appendingPathComponent("MediaRemoteAdapter.framework")
            ))
        }
        let contents = bundleURL.appendingPathComponent("Contents")
        let framework = contents.appendingPathComponent("Frameworks/MediaRemoteAdapter.framework")
        // The packaged app keeps the script in Resources, where it is sealed
        // as a plain file. A script in Helpers counts as code and carries
        // its signature in extended attributes, which a plain unzip drops.
        // The dev bundle still keeps it in Helpers.
        for folder in ["Resources", "Helpers"] {
            list.append(Paths(
                script: contents.appendingPathComponent("\(folder)/mediaremote-adapter.pl"),
                framework: framework
            ))
        }
        // Repo-relative fallback for `swift run` and unit tests.
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceFile
            .deletingLastPathComponent() // Media
            .deletingLastPathComponent() // Nook
            .deletingLastPathComponent() // OpenIslandApp
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // repo
        let buildDir = repoRoot.appendingPathComponent(".build/mediaremote-adapter")
        list.append(Paths(
            script: buildDir.appendingPathComponent("mediaremote-adapter.pl"),
            framework: buildDir.appendingPathComponent("MediaRemoteAdapter.framework")
        ))
        return list
    }

    private func exists(_ paths: Paths) -> Bool {
        let fm = FileManager.default
        let binary = paths.framework.appendingPathComponent("MediaRemoteAdapter")
        return fm.fileExists(atPath: paths.script.path) && fm.fileExists(atPath: binary.path)
    }
}
