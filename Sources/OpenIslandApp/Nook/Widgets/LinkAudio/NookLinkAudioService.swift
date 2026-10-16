import AppKit
import Foundation
import Observation

/// What the line under the card's field says.
enum NookLinkAudioProblem: Equatable, Sendable {
    case refused(NookLinkAudioLinkRefusal)
    /// One job is running and five are waiting.
    case lineFull
    case toolsMissing
    case pasteNotAllowed
    case pasteNothing
    /// macOS asked about the clipboard and the answer was no.
    case pasteMaybeRefused

    var messageKey: String {
        switch self {
        case let .refused(reason): reason.noticeKey
        case .lineFull: "nook.linkAudio.problem.full"
        case .toolsMissing: "nook.linkAudio.problem.tools"
        case .pasteNotAllowed: "nook.linkAudio.problem.pasteNotAllowed"
        case .pasteNothing: "nook.linkAudio.problem.pasteNothing"
        case .pasteMaybeRefused: "nook.linkAudio.problem.pasteMaybeRefused"
        }
    }
}

/// What handing a link to the widget came to.
enum NookLinkAudioSubmit: Equatable, Sendable {
    /// Running now, or waiting for the job before it.
    case queued(UUID)
    case refused(NookLinkAudioLinkRefusal)
    case lineFull
    case toolsMissing
}

/// The Link to MP3 widget's state: the jobs, the folder and the programs it
/// found. It starts `yt-dlp` through a runner, one job at a time, and does
/// nothing else with a link. Owned by `NookModel`; every outside door (the
/// runner, the disk, the clipboard, Finder) is handed in, which keeps a test
/// off real processes, files and windows.
@MainActor
@Observable
final class NookLinkAudioService {
    @ObservationIgnored private(set) weak var nook: NookModel?

    private(set) var queue = NookLinkAudioQueue()
    private(set) var toolStatus: NookLinkAudioToolStatus
    private(set) var folder: URL
    /// The line under the field, if there is one.
    private(set) var problem: NookLinkAudioProblem?
    /// Why the last folder that was chosen was not used, for Settings.
    private(set) var folderProblem: NookLinkAudioFolderRefusal?
    /// Whether a finished download is looked at for its key and tempo.
    /// On unless the user turned it off.
    private(set) var findsKeyAndTempo: Bool

    @ObservationIgnored let runner: any NookLinkAudioRunner
    @ObservationIgnored let files: any NookLinkAudioFiles
    @ObservationIgnored let clipboard: any NookLinkAudioClipboard
    @ObservationIgnored let analyzer: any NookLinkAudioAnalyzing
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isExecutable: (String) -> Bool
    @ObservationIgnored private let finder: (URL) -> Void
    @ObservationIgnored private let baseEnvironment: [String: String]
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let notifications: NotificationCenter
    @ObservationIgnored private var quitObserver: (any NSObjectProtocol)?
    /// The run that is going, and what it has said until now.
    @ObservationIgnored private var active: ActiveRun?
    /// The analyses that are going or waiting, by job. Each takes itself out
    /// when it ends, and a cancelled one stays until it has stopped.
    @ObservationIgnored private var analyses: [UUID: Task<Void, Never>] = [:]
    /// The analysis started last. The next one waits for it, which makes the
    /// analyses run one after another.
    @ObservationIgnored private var lastAnalysis: Task<Void, Never>?

    private struct ActiveRun {
        let id: UUID
        /// The folder the job was started with. What `yt-dlp` says about its
        /// files is believed only when it names a file directly inside it.
        let folder: URL
        var run: (any NookLinkAudioRun)?
        var file: URL?
        /// Whether `yt-dlp` wrote a file of its own for this job. A progress
        /// line that names one is the sign of it: a download that was skipped
        /// (`--no-overwrites` found the MP3) prints none, and the file it then
        /// names was there before the job.
        var didDownload = false
        /// The video's own title and description, for the key and tempo tags.
        /// The title on the row is cut and this one is not.
        var title: String?
        var description: String?
        var lastError: String?
        var isCancelling = false
    }

    /// A title is cut to this many characters for the row.
    static let maxTitleLength = 200
    /// A progress line that moves the bar less than this is not shown.
    private static let minProgressStep = 0.005

    init(
        defaults: UserDefaults = .standard,
        folder: URL? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        runner: any NookLinkAudioRunner = NookLinkAudioProcessRunner(),
        files: any NookLinkAudioFiles = NookLinkAudioSystemFiles(),
        clipboard: any NookLinkAudioClipboard = NookLinkAudioSystemClipboard(),
        analyzer: any NookLinkAudioAnalyzing = NookLinkAudioSystemAnalyzer(),
        isExecutable: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        showInFinder: @escaping (URL) -> Void = NookLinkAudioService.showInSystemFinder,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: @escaping () -> Date = { Date() },
        notifications: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.notifications = notifications
        self.runner = runner
        self.files = files
        self.clipboard = clipboard
        self.analyzer = analyzer
        findsKeyAndTempo = defaults.object(forKey: Self.findsKeyDefaultsKey) as? Bool ?? true
        self.isExecutable = isExecutable
        finder = showInFinder
        baseEnvironment = environment
        self.now = now
        self.folder = folder ?? NookLinkAudioFolderRule.resolve(
            saved: defaults.string(forKey: NookLinkAudioFolderRule.defaultsKey),
            home: home
        )
        toolStatus = NookLinkAudioToolSearch.status(isExecutable: isExecutable)
    }

    func start(nook: NookModel) {
        self.nook = nook
        refreshTools()
        guard quitObserver == nil else { return }
        // A quit in the middle of a download stops the download.
        quitObserver = notifications.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopForQuit() }
        }
    }

    /// A service for a model on a store of its own, a test's or the demo's.
    /// It finds no programs, starts nothing, and keeps its folder under the
    /// one it is given. Nothing it does can reach the user's Mac (D45).
    static func isolated(defaults: UserDefaults, folder: URL? = nil) -> NookLinkAudioService {
        NookLinkAudioService(
            defaults: defaults,
            folder: folder ?? NookLinkAudioFolderRule.isolatedFolder(),
            runner: NookLinkAudioRefusingRunner(),
            files: NookLinkAudioSystemFiles(),
            clipboard: NookLinkAudioEmptyClipboard(),
            analyzer: NookLinkAudioRefusingAnalyzer(),
            isExecutable: { _ in false },
            showInFinder: { _ in }
        )
    }

    // MARK: What the card reads

    var jobs: [NookLinkAudioJob] { queue.all }

    /// The field takes a link only while both programs are there.
    var canSubmit: Bool { toolStatus.tools != nil }

    /// Looks for the programs again. The card does it when it appears and
    /// the Settings section when it does, which picks up a `brew install`
    /// made while the app was running.
    func refreshTools() {
        let found = NookLinkAudioToolSearch.status(isExecutable: isExecutable)
        if found != toolStatus { toolStatus = found }
    }

    func show(_ next: NookLinkAudioProblem?) {
        if problem != next { problem = next }
    }

    func clearProblem() {
        show(nil)
    }

    // MARK: Folder

    /// Takes a folder the user chose, unless the rule refuses it, and says
    /// why when it does. A refused folder leaves the one that was set as it
    /// is, and `folderProblem` holds the reason for Settings.
    @discardableResult
    func setFolder(_ url: URL) -> NookLinkAudioFolderRefusal? {
        if let reason = NookLinkAudioFolderRule.refusal(for: url) {
            folderProblem = reason
            return reason
        }
        folderProblem = nil
        folder = url
        defaults.set(url.path, forKey: NookLinkAudioFolderRule.defaultsKey)
        return nil
    }

    // MARK: Key and tempo setting

    static let findsKeyDefaultsKey = "nook.linkAudio.findsKeyAndTempo"

    /// Turns the search for a key and tempo on or off. It reaches the
    /// downloads that finish after it, not the ones already saved.
    func setFindsKeyAndTempo(_ isOn: Bool) {
        guard isOn != findsKeyAndTempo else { return }
        findsKeyAndTempo = isOn
        defaults.set(isOn, forKey: Self.findsKeyDefaultsKey)
        if !isOn { cancelAnalyses() }
    }

    // MARK: Adding

    /// Puts a link in line, and starts it when nothing is running.
    @discardableResult
    func submit(_ text: String) -> NookLinkAudioSubmit {
        refreshTools()
        guard toolStatus.tools != nil else {
            show(.toolsMissing)
            return .toolsMissing
        }
        let link: NookLinkAudioLink
        switch NookLinkAudioLink.check(text) {
        case let .failure(reason):
            show(.refused(reason))
            return .refused(reason)
        case let .success(checked):
            link = checked
        }
        let job = NookLinkAudioJob(id: UUID(), link: link)
        guard queue.add(job) else {
            show(.lineFull)
            return .lineFull
        }
        show(nil)
        startNextIfIdle()
        return .queued(job.id)
    }

    // MARK: Cancelling

    /// Takes a job in line out of it, or stops the running one: its process
    /// is asked to end, and what it had written is removed once it has.
    func cancel(_ id: UUID) {
        if queue.removeWaiting(id) { return }
        guard queue.running?.id == id, var current = active, current.id == id, !current.isCancelling else { return }
        current.isCancelling = true
        active = current
        queue.updateRunning(id) { $0.phase = .cancelling }
        current.run?.cancel()
    }

    /// The app is about to quit. The line is emptied and the running job is
    /// stopped on the spot, with its process waited for, and what it had
    /// written is removed the way a cancel removes it. Nothing is left to hear
    /// the process end.
    func stopForQuit() {
        queue.removeAllWaiting()
        cancelAnalyses()
        guard let current = active, let job = queue.running, job.id == current.id else { return }
        active = nil
        queue.updateRunning(job.id) { $0.phase = .cancelling }
        current.run?.stopForQuit()
        removeLeftovers(of: job, in: current.folder)
        queue.dropRunning(job.id)
    }

    /// The widget was switched off: nothing keeps running unseen.
    func widgetSwitched(_ isOn: Bool) {
        guard !isOn else { return }
        queue.removeAllWaiting()
        cancelAnalyses()
        queue.clearFinished()
        show(nil)
        if let id = queue.running?.id { cancel(id) }
    }

    // MARK: Finished jobs

    /// Selects a finished job's file in Finder, or the folder when the file
    /// is not known. A path is only ever selected, never opened.
    func showInFinder(_ id: UUID) {
        guard case let .done(file)? = queue.job(id)?.phase else { return }
        finder(file ?? folder)
    }

    nonisolated static func showInSystemFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Running

    /// The environment `yt-dlp` runs with: the app's own with a `PATH` that
    /// holds the folders the programs are found in, and output that is
    /// written as it comes, as UTF-8.
    nonisolated static func environment(from base: [String: String]) -> [String: String] {
        var environment = base
        environment["PATH"] = NookLinkAudioToolSearch.runPath
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONIOENCODING"] = "utf-8"
        return environment
    }

    /// Starts jobs from the front of the line until one is running. A job
    /// that cannot start fails and the next one is tried.
    private func startNextIfIdle() {
        while let job = queue.startNext(now: now()) {
            if launch(job) { return }
        }
    }

    /// True when the process is running. False when it could not start, and
    /// the job is already in the finished list.
    private func launch(_ job: NookLinkAudioJob) -> Bool {
        refreshTools()
        guard let tools = toolStatus.tools else {
            queue.finishRunning(job.id, as: .failed(.couldNotStart))
            return false
        }
        // The folder is fixed for this job: a later choice is for the next one.
        let jobFolder = folder
        guard NookLinkAudioFolderRule.refusal(for: jobFolder) == nil else {
            queue.finishRunning(job.id, as: .failed(.folderHasDollar))
            return false
        }
        do {
            try files.makeFolder(jobFolder)
        } catch {
            queue.finishRunning(job.id, as: .failed(.couldNotMakeFolder))
            return false
        }
        let launch = NookLinkAudioLaunch(
            executable: tools.ytDlp,
            arguments: NookLinkAudioArguments.make(link: job.link, folder: jobFolder, ffmpegDirectory: tools.ffmpegDirectory),
            environment: Self.environment(from: baseEnvironment),
            currentDirectory: jobFolder
        )
        let id = job.id
        active = ActiveRun(id: id, folder: jobFolder)
        do {
            let run = try runner.run(
                launch,
                onLine: { [weak self] line in self?.received(line, for: id) },
                onExit: { [weak self] exit in self?.ended(exit, for: id) }
            )
            // A runner may report the end before it returns.
            if active?.id == id { active?.run = run }
            return true
        } catch {
            active = nil
            queue.finishRunning(id, as: .failed(.couldNotStart))
            return false
        }
    }

    private func received(_ line: String, for id: UUID) {
        guard queue.running?.id == id, let current = active, current.id == id, !current.isCancelling else { return }
        switch NookLinkAudioOutput.parse(line) {
        case let .progress(fraction, isDownloadDone, fileName):
            // The file named is the one a cancel may remove. It has to be a
            // file in the job's folder.
            let written = fileName.flatMap { NookLinkAudioFolderRule.directChild($0, of: current.folder) }
            if written != nil { active?.didDownload = true }
            queue.updateRunning(id) { job in
                if let written { job.writingFileName = written.path }
                guard let next = Self.phase(after: job.phase, fraction: fraction, isDownloadDone: isDownloadDone) else { return }
                job.phase = next
            }
        case let .title(title):
            active?.title = title
            queue.updateRunning(id) { $0.title = String(title.prefix(Self.maxTitleLength)) }
        case let .description(text):
            active?.description = text
        case let .file(path):
            // The finished file is believed only when it is in the job's folder.
            if let file = NookLinkAudioFolderRule.directChild(path, of: current.folder) { active?.file = file }
        case let .error(message):
            active?.lastError = message
        case .other:
            break
        }
    }

    /// The phase a progress line moves a job to, or nil when the bar would
    /// not visibly move.
    private static func phase(
        after current: NookLinkAudioJob.Phase,
        fraction: Double?,
        isDownloadDone: Bool
    ) -> NookLinkAudioJob.Phase? {
        if isDownloadDone { return current == .converting ? nil : .converting }
        // A bar never goes back to unknown, and never leaves converting.
        guard case let .downloading(old) = current, let fraction else { return nil }
        if let old, abs(fraction - old) < minProgressStep { return nil }
        return .downloading(fraction: fraction)
    }

    private func ended(_ exit: NookLinkAudioExit, for id: UUID) {
        guard queue.running?.id == id, let finishedRun = active, finishedRun.id == id else { return }
        active = nil
        if finishedRun.isCancelling {
            if let job = queue.job(id) { removeLeftovers(of: job, in: finishedRun.folder) }
            queue.dropRunning(id)
        } else if exit.isSuccess {
            queue.finishRunning(id, as: .done(finishedRun.file))
            startAnalysis(
                of: id,
                file: finishedRun.file,
                didDownload: finishedRun.didDownload,
                title: finishedRun.title,
                description: finishedRun.description
            )
        } else {
            queue.finishRunning(id, as: .failed(NookLinkAudioFailure.reason(forErrorLine: finishedRun.lastError)))
        }
        startNextIfIdle()
    }

    // MARK: Key and tempo

    /// Starts the search for the key and tempo of a file that was just
    /// saved. The row is already done: the search runs off the main actor,
    /// and its answer comes back to `finishAnalysis`. The searches run one
    /// after another, each waiting for the one started before it, which keeps
    /// two quick finishes from decoding two songs at once. Nothing starts with
    /// the setting off or without a file. `didDownload` is whether this job
    /// wrote the file.
    private func startAnalysis(of id: UUID, file: URL?, didDownload: Bool, title: String?, description: String?) {
        guard findsKeyAndTempo, let file else { return }
        let analyzer = analyzer
        let previous = lastAnalysis
        let task = Task { [weak self] in
            await previous?.value
            var findings: NookLinkAudioFindings?
            // A cancel that came while this one waited leaves nothing to search.
            if !Task.isCancelled {
                findings = await analyzer.analyze(file: file, title: title, description: description)
            }
            guard let self else { return }
            analyses[id] = nil
            // An answer that was cancelled on its way is dropped.
            if let findings, !Task.isCancelled {
                finishAnalysis(of: id, file: file, didDownload: didDownload, findings: findings)
            }
        }
        analyses[id] = task
        lastAnalysis = task
    }

    /// Gives the row its key and tempo and puts them in the file's name, when
    /// this job wrote the file. A file it did not write, because `yt-dlp` found
    /// the MP3 already in the folder and skipped the download, is never moved
    /// or trashed: the row points at the file with the new name when there is
    /// one, and otherwise shows what was found and leaves the name as it is.
    /// For a file the job wrote, when the new name is taken, which is the same
    /// link fetched again (`yt-dlp` no longer finds the renamed file and saved
    /// a second copy), the copy just saved goes to the Trash and the row points
    /// at the file already there. A file that cannot be moved stays where it
    /// is, and the row still shows what was found.
    private func finishAnalysis(of id: UUID, file: URL, didDownload: Bool, findings: NookLinkAudioFindings) {
        guard findsKeyAndTempo, !findings.isEmpty else { return }
        let shown = rename(file, with: findings, didDownload: didDownload)
        queue.updateFinished(id) { job in
            job.findings = findings
            if case .done = job.phase { job.phase = .done(shown) }
        }
    }

    /// Where the file is after the rename: the new name when it was moved or
    /// when the file with that name is already there, and `file` otherwise.
    private func rename(_ file: URL, with findings: NookLinkAudioFindings, didDownload: Bool) -> URL {
        guard let target = NookLinkAudioName.renamed(file, with: findings) else { return file }
        // Only a file this job wrote is moved or trashed. A file that is gone
        // may have been renamed by another job of the same link.
        guard didDownload, files.exists(file) else { return files.exists(target) ? target : file }
        if files.exists(target) {
            return (try? files.trash(file)) != nil ? target : file
        }
        return (try? files.move(file, to: target)) != nil ? target : file
    }

    /// Cancels every search, the ones waiting included. A cancelled search
    /// stays listed until it has stopped, which is what `finishAnalyses`
    /// waits for.
    private func cancelAnalyses() {
        for task in analyses.values { task.cancel() }
    }

    /// Waits for every search that is going, cancelled ones too. For tests,
    /// which have no other way to know the answer has come back.
    func finishAnalyses() async {
        for task in Array(analyses.values) { await task.value }
    }

    /// Removes what a cancelled job wrote into the folder it ran in.
    private func removeLeftovers(of job: NookLinkAudioJob, in folder: URL) {
        guard let start = job.startedAt else { return }
        let names = NookLinkAudioLeftovers.names(
            in: files.listing(of: folder),
            writing: job.writingFileName,
            since: start
        )
        for name in names {
            files.remove(folder.appendingPathComponent(name))
        }
    }
}
