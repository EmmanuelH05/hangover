import Foundation
@testable import OpenIslandApp

// Shared by the Link to MP3 tests. Nothing here starts a process, touches
// the network, shows a window, reads the real clipboard or settings, or
// writes outside memory.

/// A runner that records what it was asked to start and lets the test play
/// the program's output and end.
@MainActor
final class FakeLinkAudioRunner: NookLinkAudioRunner {
    struct Failure: Error {}

    @MainActor
    final class Run: NookLinkAudioRun {
        let launch: NookLinkAudioLaunch
        fileprivate let lineHandler: @MainActor @Sendable (String) -> Void
        fileprivate let exitHandler: @MainActor @Sendable (NookLinkAudioExit) -> Void
        private(set) var cancelCount = 0
        private(set) var quitStopCount = 0
        /// The program ends by itself when asked to, the way `yt-dlp`
        /// does on an interrupt.
        var endsWhenCancelled = false

        fileprivate init(
            launch: NookLinkAudioLaunch,
            lineHandler: @escaping @MainActor @Sendable (String) -> Void,
            exitHandler: @escaping @MainActor @Sendable (NookLinkAudioExit) -> Void
        ) {
            self.launch = launch
            self.lineHandler = lineHandler
            self.exitHandler = exitHandler
        }

        func cancel() {
            cancelCount += 1
            if endsWhenCancelled { end(status: 130, wasSignalled: true) }
        }

        /// Runs when the program is stopped for a quit, before the stop returns.
        var whenStoppedForQuit: (() -> Void)?

        func stopForQuit() {
            quitStopCount += 1
            whenStoppedForQuit?()
        }

        func say(_ line: String) {
            lineHandler(line)
        }

        func end(status: Int32 = 0, wasSignalled: Bool = false) {
            exitHandler(NookLinkAudioExit(status: status, wasSignalled: wasSignalled))
        }

        /// The link, which is the last argument.
        var link: String? { launch.arguments.last }
    }

    private(set) var runs: [Run] = []
    /// `run` throws while this is set.
    var failsToStart = false
    /// The program ends at once, before `run` returns.
    var endsAtOnce: NookLinkAudioExit?

    func run(
        _ launch: NookLinkAudioLaunch,
        onLine: @escaping @MainActor @Sendable (String) -> Void,
        onExit: @escaping @MainActor @Sendable (NookLinkAudioExit) -> Void
    ) throws -> any NookLinkAudioRun {
        if failsToStart { throw Failure() }
        let run = Run(launch: launch, lineHandler: onLine, exitHandler: onExit)
        runs.append(run)
        if let endsAtOnce { onExit(endsAtOnce) }
        return run
    }

    var last: Run? { runs.last }
}

/// A folder held in memory.
@MainActor
final class FakeLinkAudioFiles: NookLinkAudioFiles {
    struct Failure: Error {}

    private(set) var madeFolders: [URL] = []
    private(set) var removed: [URL] = []
    /// The files in the folder, by name.
    var entries: [String: Date] = [:]
    var failsToMakeFolder = false
    private(set) var listedFolders: [URL] = []
    /// The paths of the files that exist, for `exists`, `move` and `trash`.
    var present: Set<String> = []
    private(set) var moves: [(from: URL, to: URL)] = []
    private(set) var trashed: [URL] = []
    var failsToMove = false
    var failsToTrash = false

    func makeFolder(_ folder: URL) throws {
        if failsToMakeFolder { throw Failure() }
        madeFolders.append(folder)
    }

    func listing(of folder: URL) -> [NookLinkAudioFileEntry] {
        listedFolders.append(folder)
        return entries.map { NookLinkAudioFileEntry(name: $0.key, modified: $0.value) }
    }

    func remove(_ file: URL) {
        removed.append(file)
        entries[file.lastPathComponent] = nil
    }

    func exists(_ file: URL) -> Bool {
        present.contains(file.path)
    }

    func move(_ file: URL, to destination: URL) throws {
        guard !failsToMove, present.contains(file.path), !present.contains(destination.path) else { throw Failure() }
        present.remove(file.path)
        present.insert(destination.path)
        moves.append((file, destination))
    }

    func trash(_ file: URL) throws {
        guard !failsToTrash, present.contains(file.path) else { throw Failure() }
        present.remove(file.path)
        trashed.append(file)
    }
}

/// An analyzer that answers with what the test sets, and can hold its answer
/// back until the test lets it go. It reads no file.
final class FakeLinkAudioAnalyzer: NookLinkAudioAnalyzing, @unchecked Sendable {
    struct Call: Equatable, Sendable {
        var file: URL
        var title: String?
        var description: String?
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private var held: [CheckedContinuation<Void, Never>] = []
    private var answer = NookLinkAudioFindings()
    private var holdsAnswers = false
    private var open = 0
    private var mostOpen = 0
    private var cancelled = 0

    var calls: [Call] { lock.withLock { recorded } }
    var heldCount: Int { lock.withLock { held.count } }
    /// The most calls that were open (called and not yet answered) at one time.
    var mostAtOnce: Int { lock.withLock { mostOpen } }
    /// How many calls were cancelled by the time they answered.
    var cancelledCount: Int { lock.withLock { cancelled } }

    /// What every later call answers.
    func answer(with findings: NookLinkAudioFindings, holding: Bool = false) {
        lock.withLock {
            answer = findings
            holdsAnswers = holding
        }
    }

    /// Lets every held call answer.
    func release() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            holdsAnswers = false
            let all = held
            held = []
            return all
        }
        for continuation in waiting { continuation.resume() }
    }

    func analyze(file: URL, title: String?, description: String?) async -> NookLinkAudioFindings {
        let call = Call(file: file, title: title, description: description)
        let mustWait = lock.withLock { () -> Bool in
            recorded.append(call)
            open += 1
            mostOpen = max(mostOpen, open)
            return holdsAnswers
        }
        if mustWait {
            await withCheckedContinuation { continuation in
                // A `release()` may have come since the check above. A call is
                // held only while answers are still held, and goes on at once
                // when they are not.
                let isHeld = lock.withLock { () -> Bool in
                    guard holdsAnswers else { return false }
                    held.append(continuation)
                    return true
                }
                if !isHeld { continuation.resume() }
            }
        }
        return lock.withLock {
            open -= 1
            if Task.isCancelled { cancelled += 1 }
            return answer
        }
    }
}

@MainActor
final class FakeLinkAudioClipboard: NookLinkAudioClipboard {
    var access: NookClipboardAccess = .allowed
    var text: String?
    private(set) var readCount = 0

    func readText() -> String? {
        readCount += 1
        return text
    }
}

/// One service on fakes, with the programs "installed" in the three usual
/// folders, a clock the test moves and a record of what was shown in Finder.
@MainActor
final class LinkAudioFixture {
    nonisolated static let ytDlp = "/opt/homebrew/bin/yt-dlp"
    nonisolated static let ffmpeg = "/opt/homebrew/bin/ffmpeg"
    nonisolated static let start = Date(timeIntervalSince1970: 1_800_000_000)

    let runner = FakeLinkAudioRunner()
    let files = FakeLinkAudioFiles()
    let clipboard = FakeLinkAudioClipboard()
    let analyzer = FakeLinkAudioAnalyzer()
    let defaults = MemoryDefaults()
    /// What the service listens for a quit on. A test posts to it and never to the real one.
    let notifications = NotificationCenter()
    let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    private let state = State()
    private(set) var service: NookLinkAudioService!

    /// What the closures the service holds can see and change.
    final class State: @unchecked Sendable {
        var executables: Set<String> = [LinkAudioFixture.ytDlp, LinkAudioFixture.ffmpeg]
        var shown: [URL] = []
        var now = LinkAudioFixture.start
    }

    var executables: Set<String> {
        get { state.executables }
        set { state.executables = newValue }
    }

    var shown: [URL] { state.shown }
    var now: Date {
        get { state.now }
        set { state.now = newValue }
    }

    init(folder: URL? = nil, environment: [String: String] = ["HOME": "/Users/tester", "PATH": "/usr/bin"]) {
        let state = state
        service = NookLinkAudioService(
            defaults: defaults,
            folder: folder,
            home: home,
            runner: runner,
            files: files,
            clipboard: clipboard,
            analyzer: analyzer,
            isExecutable: { state.executables.contains($0) },
            showInFinder: { state.shown.append($0) },
            environment: environment,
            now: { state.now },
            notifications: notifications
        )
    }

    var folder: URL { service.folder }

    /// A link for the n-th job.
    static func link(_ number: Int) -> String { "https://example.com/watch?v=\(number)" }

    /// Submits links 1...count, and returns their ids.
    @discardableResult
    func submit(_ count: Int, from first: Int = 1) -> [UUID] {
        (first..<first + count).compactMap { number in
            if case let .queued(id) = service.submit(Self.link(number)) { return id }
            return nil
        }
    }

    /// The folder the fixture's jobs run in, as a path.
    nonisolated static let mediaFolder = "/Users/tester/Music/Hangover"

    /// A string the way `yt-dlp` prints it for `%(title)j`: a JSON string.
    nonisolated static func json(_ text: String) -> String {
        guard let data = try? JSONEncoder().encode(text), let line = String(data: data, encoding: .utf8) else { return "null" }
        return line
    }

    /// The line `yt-dlp` writes when the title is known.
    nonisolated static func titleLine(_ title: String) -> String {
        "\(NookLinkAudioArguments.titleMarker) \(json(title))"
    }

    /// The line `yt-dlp` writes when the description is known.
    nonisolated static func descriptionLine(_ description: String) -> String {
        "\(NookLinkAudioArguments.descriptionMarker) \(json(description))"
    }

    /// The line `yt-dlp` writes for the finished file.
    nonisolated static func fileLine(_ path: String) -> String {
        "\(NookLinkAudioArguments.fileMarker) \(json(path))"
    }

    /// The progress line `yt-dlp` writes for a download that is part way. `file` is a name in the media folder.
    nonisolated static func progressLine(done: Int, of total: Int?, file: String = "Song [a1b2].webm") -> String {
        "\(NookLinkAudioArguments.progressMarker) downloading \(done) \(total.map(String.init) ?? "NA") NA \(json("\(mediaFolder)/\(file)"))"
    }

    /// The progress line that closes the download.
    nonisolated static func downloadDoneLine(file: String = "Song [a1b2].webm") -> String {
        "\(NookLinkAudioArguments.progressMarker) finished 100 100 NA \(json("\(mediaFolder)/\(file)"))"
    }

    /// Lets the other tasks run until `count` calls to the analyzer are being
    /// held, which is when a search is "out". False when that never came. A test
    /// expects on the answer, which keeps a search that never started from
    /// passing for one that was stopped.
    func waitForHeldAnalysis(_ count: Int = 1) async -> Bool {
        var turns = 0
        while analyzer.heldCount < count, turns < 1_000 {
            await Task.yield()
            turns += 1
        }
        return analyzer.heldCount >= count
    }

    /// Plays a whole good run on the running job: a title, some progress, the end of the download,
    /// the finished file, a clean exit.
    func finishRunningJob(title: String = "Song", file: String? = nil) {
        guard let run = runner.last else { return }
        run.say(Self.titleLine(title))
        run.say(Self.progressLine(done: 50, of: 100, file: "\(title) [a1b2].webm"))
        run.say(Self.downloadDoneLine(file: "\(title) [a1b2].webm"))
        run.say(Self.fileLine(file ?? "\(Self.mediaFolder)/\(title) [a1b2].mp3"))
        run.end()
    }
}
