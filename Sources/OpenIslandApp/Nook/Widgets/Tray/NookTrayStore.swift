import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let trayLog = NookTrayLog.logger

/// One file held in the tray.
struct NookTrayItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let originalName: String
    let storedName: String
    let addedDate: Date
    /// The path the file came from when it was hard linked into the tray,
    /// such as a recording in Movies/Hangover. Show in Finder goes there.
    var linkedFrom: String? = nil
}

/// Which list the tray card shows.
enum NookTrayTab: String, CaseIterable, Identifiable, Sendable {
    case files
    case clipboard

    var id: String { rawValue }
    var titleKey: String { "nook.tray.tab.\(rawValue)" }

    var symbol: String {
        switch self {
        case .files: "tray.full"
        case .clipboard: "doc.on.clipboard"
        }
    }
}

/// A line the tray card shows for a moment after an action.
struct NookTrayNotice: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The action did what was asked.
        case done
        /// Nothing went wrong, and nothing was done either.
        case info
        case error
    }

    let text: String
    let kind: Kind

    var isError: Bool { kind == .error }
}

/// A conversion that is running for one or more tray files (D68).
struct NookConvertProgress: Sendable {
    /// Tells this job from a later one on the same file.
    let token: UUID
    /// 0 to 1, nil while the amount is not known.
    var fraction: Double?
    let task: Task<Void, Never>
}

/// How reading the tray's index went.
enum NookTrayIndexLoad: Equatable, Sendable {
    /// There is no index yet, as on a first launch.
    case missing
    case loaded
    /// The index could not be read or understood. It has been moved aside as
    /// `index.json.bad`, and the tray starts empty.
    case failed
}

/// Passes a job's progress from the thread doing the work to the main actor
/// without a hop for every tiny step: only a change of a hundredth counts.
final class NookProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1.0
    private let send: @Sendable (Double) -> Void

    init(send: @escaping @Sendable (Double) -> Void) {
        self.send = send
    }

    func report(_ fraction: Double) {
        let changed = lock.withLock { () -> Bool in
            guard abs(fraction - last) >= 0.01 || fraction >= 1 else { return false }
            last = fraction
            return true
        }
        if changed { send(fraction) }
    }
}

/// Keeps copies of dropped files in Application Support and an index of them.
@MainActor
@Observable
final class NookTrayStore {
    nonisolated static let tabKey = "nook.tray.tab"

    @ObservationIgnored private(set) weak var nook: NookModel?

    private(set) var items: [NookTrayItem] = []

    /// True while files are being dragged over the island. The tray card
    /// lights up as the place they will land.
    var isFileDragOverIsland = false

    /// The copies kept beside the files, when the user switched that on.
    let clipboard: NookClipboardMonitor

    var tab: NookTrayTab {
        didSet {
            guard tab != oldValue else { return }
            defaults.set(tab.rawValue, forKey: Self.tabKey)
            // Picking a file means looking at the files.
            if tab == .clipboard { isPickingToConvert = false }
        }
    }

    /// True while the system share picker hangs off a tray file. The
    /// island stays open under it.
    private(set) var isSharePickerOpen = false

    /// The last thing an action had to say, shown in the card for a moment.
    private(set) var notice: NookTrayNotice?

    /// Files a quick action is working on right now.
    private(set) var workingIDs: Set<UUID> = []

    /// The conversions running right now, keyed by the file each one reads.
    /// Joining several files lists the same job under every one of them.
    private(set) var jobs: [UUID: NookConvertProgress] = [:]

    /// The files chosen with Command-click and Shift-click, for Combine.
    private(set) var selection: Set<UUID> = []

    /// The video the GIF options are open for. The options sit in a strip
    /// above the cards (`NookGIFStrip`), which changes the island's height.
    private(set) var gifSourceItem: NookTrayItem? {
        didSet {
            // Only one strip shows at a time.
            if gifSourceItem != nil, convertSourceItem != nil { convertSourceItem = nil }
            if gifSourceItem?.id != oldValue?.id { nook?.onDisplayPreferencesChanged?() }
        }
    }

    /// True while the Convert chip waits for a click on a file. The tiles
    /// that can be converted light up. Changed through the methods in
    /// `NookTrayStore+ConvertPicking.swift`.
    var isPickingToConvert = false

    /// The file the Convert strip is open for, with the same effect on the
    /// island's height as `gifSourceItem`. Changed through the methods in
    /// `NookTrayStore+ConvertPicking.swift`.
    var convertSourceItem: NookTrayItem? {
        didSet {
            // Only one strip shows at a time.
            if convertSourceItem != nil, gifSourceItem != nil { gifSourceItem = nil }
            if convertSourceItem?.id != oldValue?.id { nook?.onDisplayPreferencesChanged?() }
        }
    }

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private var indexURL: URL { folder.appendingPathComponent("index.json") }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    /// The last video or GIF job started. The next one waits for it.
    @ObservationIgnored private var queueTail: Task<Void, Never>?
    /// Where a Shift-click range starts.
    @ObservationIgnored private var selectionAnchor: UUID?
    /// True when the index on disk could not be read and could not be moved
    /// aside. Saving would write over it, so nothing is saved.
    @ObservationIgnored private var isIndexWriteBlocked = false
    @ObservationIgnored private lazy var sharePresenter: NookTraySharePresenter = {
        let presenter = NookTraySharePresenter()
        presenter.onOpenChange = { [weak self] isOpen in self?.isSharePickerOpen = isOpen }
        return presenter
    }()

    /// The app uses the defaults. Tests pass a folder of their own, a
    /// clipboard that reads a fake pasteboard, and a private defaults suite.
    init(folder: URL? = nil, clipboard: NookClipboardMonitor? = nil, defaults: UserDefaults = .standard) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.folder = folder ?? base.appendingPathComponent("OpenIsland/Tray", isDirectory: true)
        self.clipboard = clipboard ?? NookClipboardMonitor(defaults: defaults)
        self.defaults = defaults
        tab = defaults.string(forKey: Self.tabKey).flatMap(NookTrayTab.init(rawValue:)) ?? .files
    }

    func start(nook: NookModel) {
        self.nook = nook
        loadFromDisk()
        clipboard.start()
    }

    /// Makes sure the tray folder exists, reads the index, and clears out
    /// what a quit left half done. Returns how the index read went.
    @discardableResult
    func loadFromDisk() -> NookTrayIndexLoad {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            trayLog.error("Tray folder could not be made (\(NookTrayLog.cause(error), privacy: .public))")
        }
        let load = loadIndex()
        // Only folders marked as unfinished are swept, and only on a launch
        // that read a good index. A launch without one has nothing to say
        // about which work is leftover.
        if load == .loaded { removeOrphanedFolders() }
        return load
    }

    var folderURL: URL { folder }

    func storedURL(for item: NookTrayItem) -> URL {
        folder.appendingPathComponent(item.storedName)
    }

    /// Called when files are dropped on the closed notch or the Nook page.
    /// Returns true when the drop was taken.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        // The files land in the file list. Show it.
        tab = .files
        for provider in fileProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = item as? URL {
                    url = direct
                }
                guard let url, url.isFileURL else { return }
                Task { @MainActor [weak self] in
                    self?.add(fileAt: url)
                }
            }
        }
        return true
    }

    func remove(_ item: NookTrayItem) {
        // Its conversions stop first, so they find the file gone with
        // nothing left to say about it.
        cancelJob(for: item)
        if gifSourceItem?.id == item.id { gifSourceItem = nil }
        selection.remove(item.id)
        try? FileManager.default.removeItem(at: storedURL(for: item).deletingLastPathComponent())
        items.removeAll { $0.id == item.id }
        convertModeDidRemove(item)
        saveIndex()
    }

    func clear() {
        for item in items {
            cancelJob(for: item)
        }
        gifSourceItem = nil
        endConvertMode()
        clearSelection()
        for item in items {
            try? FileManager.default.removeItem(at: storedURL(for: item).deletingLastPathComponent())
        }
        items = []
        saveIndex()
    }

    func revealInFinder(_ item: NookTrayItem) {
        NSWorkspace.shared.activateFileViewerSelecting([revealTarget(for: item)])
    }

    /// Where Show in Finder goes: the place a linked file came from, such as
    /// a recording in Movies/Hangover, while it is still there. Otherwise
    /// the tray's own copy.
    func revealTarget(for item: NookTrayItem) -> URL {
        if let linkedFrom = item.linkedFrom, FileManager.default.fileExists(atPath: linkedFrom) {
            return URL(fileURLWithPath: linkedFrom)
        }
        return storedURL(for: item)
    }

    func revealFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    // MARK: - Sharing

    /// Opens the system share picker for a file, hung off the tile's view.
    func share(_ item: NookTrayItem, from anchor: NSView?) {
        guard hasFile(item) else { return post("nook.tray.notice.fileMissing", .error) }
        if !sharePresenter.showPicker(for: storedURL(for: item), from: anchor) {
            post("nook.tray.notice.shareFailed", .error)
        }
    }

    func airDrop(_ item: NookTrayItem) {
        guard hasFile(item) else { return post("nook.tray.notice.fileMissing", .error) }
        if !sharePresenter.airDrop(storedURL(for: item)) {
            post("nook.tray.notice.airDropUnavailable", .error)
        }
    }

    /// Opens the share picker for a file that is not in the tray, such as
    /// a photo booth strip. The same picker, with the same hold on the
    /// island while it is up. False when it could not open.
    func share(fileAt url: URL, from anchor: NSView?) -> Bool {
        sharePresenter.showPicker(for: url, from: anchor)
    }

    /// The picker is down, or must be treated as down: the card went away,
    /// or a press landed on the island, which closes any picker.
    func sharePickerDidClose() {
        if isSharePickerOpen { isSharePickerOpen = false }
    }

    // MARK: - Quick actions

    /// Zips a file and adds the zip to the tray as a new file.
    @discardableResult
    func compress(_ item: NookTrayItem) -> Task<Void, Never> {
        addDerived(
            from: [item],
            named: NookTrayFileActions.zipName(for: item.originalName),
            kind: .quickAction,
            noticeKey: { ($0 as? NookTrayFileActionError)?.noticeKey ?? "nook.tray.notice.zipFailed" }
        ) { sources, destination, _ in
            try NookTrayFileActions.zip(sources[0], to: destination)
        }
    }

    // MARK: - Converting

    /// Turns a file into something else and adds the result to the tray
    /// beside it. The file it starts from is not changed. Nil when nothing
    /// was started: the file is already being converted, the menu does not
    /// offer that action for it, or the action was Make GIF, which only
    /// opens the options.
    @discardableResult
    func convert(_ item: NookTrayItem, action: NookConvertAction) -> Task<Void, Never>? {
        guard jobs[item.id] == nil,
              NookConvertRules.actions(forFileNamed: item.originalName, at: storedURL(for: item)).contains(action) else {
            return nil
        }
        if action == .makeGIF {
            gifSourceItem = item
            return nil
        }
        let name = NookConvertRules.resultName(for: item.originalName, action: action, taken: takenNames)
        return addDerived(
            from: [item],
            named: name,
            kind: action.isQueued ? .queued : .immediate,
            noticeKey: { NookConvertRules.noticeKey(for: $0, action: action) }
        ) { sources, destination, progress in
            try await Self.run(action, from: sources[0], to: destination, progress: progress)
        }
    }

    /// Starts the GIF the options asked for. The video that was waiting
    /// for them is the one it reads.
    @discardableResult
    func startGIF(options: NookGIFOptions) -> Task<Void, Never>? {
        guard let item = gifSourceItem else { return nil }
        // The options stay open while the video is busy, and the Make
        // button says what it is waiting for (`gifBlocker`).
        guard jobs[item.id] == nil else { return nil }
        gifSourceItem = nil
        let name = NookConvertRules.resultName(for: item.originalName, action: .makeGIF, taken: takenNames)
        return addDerived(
            from: [item],
            named: name,
            kind: .queued,
            noticeKey: { NookConvertRules.noticeKey(for: $0, action: .makeGIF) }
        ) { sources, destination, progress in
            try await NookGIFMaker.make(from: sources[0], to: destination, options: options, progress: progress)
        }
    }

    /// Closes the GIF options without making anything.
    func cancelGIF() {
        gifSourceItem = nil
    }

    /// The first of `items` that a conversion is still reading, nil when
    /// none is.
    func busyItem(among items: [NookTrayItem]) -> NookTrayItem? {
        items.first { jobs[$0.id] != nil }
    }

    /// The chosen file that keeps Combine from starting, nil when it can.
    /// The bar stays up with its buttons off and names this file.
    var combineBlocker: NookTrayItem? {
        busyItem(among: selectedItems)
    }

    /// The video that keeps Make from starting while the GIF options are
    /// open, nil when it can.
    var gifBlocker: NookTrayItem? {
        gifSourceItem.flatMap { busyItem(among: [$0]) }
    }

    /// Stops the conversion reading this file, if there is one. It leaves
    /// no result and no notice.
    func cancelJob(for item: NookTrayItem) {
        guard let job = jobs[item.id] else { return }
        job.task.cancel()
        jobs = jobs.filter { $0.value.token != job.token }
    }

    /// Makes one PDF of the chosen files, which `items` lists in the order
    /// they sit in the tray. Nil when nothing was started.
    @discardableResult
    func combine(_ items: [NookTrayItem], action: NookCombineAction) -> Task<Void, Never>? {
        guard NookConvertRules.combineActions(forFilesNamed: items.map(\.originalName)).contains(action),
              items.allSatisfy({ jobs[$0.id] == nil }) else {
            return nil
        }
        let name = NookConvertRules.combinedName(for: action, taken: takenNames)
        clearSelection()
        return addDerived(
            from: items,
            named: name,
            kind: .immediate,
            noticeKey: { NookConvertRules.noticeKey(forCombineFailure: $0) }
        ) { sources, destination, _ in
            switch action {
            case .picturesToPDF: try NookConvertJobs.picturesToPDF(sources, to: destination)
            case .joinPDFs: try NookConvertJobs.joinPDFs(sources, to: destination)
            }
        }
    }

    // MARK: - Selection

    /// The chosen files, in the order they sit in the tray.
    var selectedItems: [NookTrayItem] {
        items.filter { selection.contains($0.id) }
    }

    /// What the chosen files can be made into together.
    var combineActions: [NookCombineAction] {
        NookConvertRules.combineActions(forFilesNamed: selectedItems.map(\.originalName))
    }

    /// Command-click: adds the file, or takes it out if it is chosen.
    func toggleSelection(of item: NookTrayItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
        selectionAnchor = item.id
    }

    /// Shift-click: chooses every file from the last one clicked to this
    /// one. Without a last one, it chooses this file alone.
    func extendSelection(to item: NookTrayItem) {
        guard let anchor = selectionAnchor,
              let from = items.firstIndex(where: { $0.id == anchor }),
              let to = items.firstIndex(where: { $0.id == item.id }) else {
            toggleSelection(of: item)
            return
        }
        selection.formUnion(items[min(from, to)...max(from, to)].map(\.id))
    }

    func clearSelection() {
        selection = []
        selectionAnchor = nil
    }

    func copyPath(of item: NookTrayItem) {
        if clipboard.copy(text: storedURL(for: item).path) {
            post("nook.tray.notice.pathCopied", .done)
        } else {
            post("nook.tray.notice.copyFailed", .error)
        }
    }

    // MARK: - Clipboard

    func copyAgain(_ entry: NookClipboardEntry) {
        if !clipboard.copyAgain(entry) {
            post("nook.tray.notice.copyFailed", .error)
        }
    }

    /// Reads the pasteboard once because the user asked, and says why when
    /// nothing was added.
    func captureClipboardNow() {
        switch clipboard.captureNow() {
        case .added: break
        case .skipped: post("nook.tray.clipboard.notice.skipped", .info)
        case .nothing: post("nook.tray.clipboard.notice.nothing", .info)
        }
    }

    func openPasteSettings() {
        guard let url = NookClipboardMonitor.pasteSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private func hasFile(_ item: NookTrayItem) -> Bool {
        FileManager.default.fileExists(atPath: storedURL(for: item).path)
    }

    /// Shows a line in the card for a moment. An error also goes to the
    /// closed island, because a menu action can leave the island closed
    /// before its work is done. So does an `info` line when `surfacing`,
    /// for the answer to a conversion that was started and then finished
    /// with nothing to show.
    private func post(_ key: String, _ kind: NookTrayNotice.Kind, surfacing: Bool = false) {
        let text = LanguageManager.shared.t(key)
        notice = NookTrayNotice(text: text, kind: kind)
        noticeTask?.cancel()
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
        if kind == .error {
            nook?.showTransient(symbol: "exclamationmark.triangle", text: text, tint: .orange)
        } else if kind == .info, surfacing {
            nook?.showTransient(symbol: "info.circle", text: text)
        }
    }

    /// How a derived file's work is scheduled.
    private enum JobKind {
        /// A quick action, like a zip. The file shows a spinner.
        case quickAction
        /// A conversion that starts at once, like a picture or a PDF.
        case immediate
        /// A conversion that waits for the video and GIF jobs before it.
        case queued
    }

    private typealias DerivedWork = @Sendable (
        _ sources: [URL],
        _ destination: URL,
        _ progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Void

    /// What a conversion action does with the file it reads.
    private nonisolated static func run(
        _ action: NookConvertAction,
        from source: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        switch action {
        case .image(let target):
            try NookConvertJobs.convertImage(at: source, to: destination, target: target)
        case .resize(let resize):
            try NookConvertJobs.resize(at: source, to: destination, resize: resize)
        case .smallerImage:
            try NookConvertJobs.smallerImage(at: source, to: destination)
            try NookConvertJobs.requireSmaller(destination, than: source)
        case .video, .soundOnly:
            try await NookConvertJobs.exportVideo(at: source, to: destination, action: action, progress: progress)
        case .smallerVideo:
            try await NookConvertJobs.exportVideo(at: source, to: destination, action: action, progress: progress)
            try NookConvertJobs.requireSmaller(destination, than: source)
        case .pdfPages(let format):
            try NookConvertJobs.pdfPages(at: source, to: destination, format: format)
        case .makeGIF:
            // The options come first, so a GIF never arrives here.
            throw NookTrayFileActionError.unreadable
        }
    }

    /// The names the tray shows now, which a new result must not repeat.
    private var takenNames: Set<String> {
        Set(items.map(\.originalName))
    }

    /// Makes a new file from one or more tray files and adds it to the
    /// tray, beside the first of them. The work runs off the main thread,
    /// and the files it starts from are not changed. A job that is
    /// cancelled, which removing its files does, adds nothing and says
    /// nothing. `noticeKey` picks the sentence for a failure.
    private func addDerived(
        from sources: [NookTrayItem],
        named name: String,
        kind: JobKind,
        noticeKey: @escaping @Sendable (Error) -> String,
        work: @escaping DerivedWork
    ) -> Task<Void, Never> {
        let urls = sources.map { storedURL(for: $0) }
        let sourceIDs = sources.map(\.id)
        let folder = self.folder
        let id = UUID()
        let token = UUID()
        let derived = NookTrayItem(id: id, originalName: name, storedName: "\(id.uuidString)/\(name)", addedDate: Date())
        let previous = kind == .queued ? queueTail : nil
        if kind == .quickAction { workingIDs.formUnion(sourceIDs) }
        let reporter = NookProgressReporter { [weak self] fraction in
            Task { @MainActor in self?.setFraction(fraction, for: token) }
        }
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            // A video waits for the one before it. A cancel that comes in
            // the meantime is seen as soon as the wait ends.
            await previous?.value
            let fm = FileManager.default
            let subfolder = folder.appendingPathComponent(id.uuidString, isDirectory: true)
            // The notice for a failure, nil when the work went through.
            var failure: (key: String, kind: NookTrayNotice.Kind)?
            if !Task.isCancelled {
                do {
                    try fm.createDirectory(at: subfolder, withIntermediateDirectories: true)
                    // Marked before the work starts, so a quit in the middle
                    // leaves a folder the next launch knows to clear out.
                    NookTrayPartialMarker.write(in: subfolder)
                    try await work(urls, folder.appendingPathComponent(derived.storedName)) { reporter.report($0) }
                } catch {
                    // A stop asked for is not a failure, whatever the
                    // work threw on its way out.
                    if !Task.isCancelled, !(error is CancellationError), (error as? NookGIFError) != .cancelled {
                        let key = noticeKey(error)
                        failure = (key, NookConvertRules.noticeKind(for: error))
                        Self.log(error, for: key)
                    }
                }
            }
            if Task.isCancelled || failure != nil { try? fm.removeItem(at: subfolder) }
            let noticeForFailure = failure
            await MainActor.run {
                guard let self else { return }
                self.finishJob(token: token, sourceIDs: sourceIDs, kind: kind)
                if Task.isCancelled {
                    // Stopped just as it finished. Nothing it made is kept.
                    try? fm.removeItem(at: subfolder)
                    return
                }
                if let noticeForFailure {
                    self.post(noticeForFailure.key, noticeForFailure.kind, surfacing: true)
                } else {
                    if kind == .quickAction {
                        self.register(derived)
                    } else {
                        self.register(derived, beside: sourceIDs.first)
                        self.post("nook.tray.convert.notice.done", .done)
                    }
                }
            }
        }
        if kind != .quickAction {
            for sid in sourceIDs { jobs[sid] = NookConvertProgress(token: token, fraction: nil, task: task) }
        }
        if kind == .queued { queueTail = task }
        return task
    }

    private func setFraction(_ fraction: Double, for token: UUID) {
        for (sid, job) in jobs where job.token == token {
            jobs[sid]?.fraction = min(1, max(0, fraction))
        }
    }

    private func finishJob(token: UUID, sourceIDs: [UUID], kind: JobKind) {
        if kind == .quickAction {
            workingIDs.subtract(sourceIDs)
        } else if jobs.values.contains(where: { $0.token == token }) {
            jobs = jobs.filter { $0.value.token != token }
        }
    }

    /// Writes why a quick action failed to the log. The user only sees a
    /// short notice. The tool's own words can name files, which keeps
    /// them in the private part of the line.
    private nonisolated static func log(_ error: Error, for failureKey: String) {
        if let known = error as? NookTrayFileActionError {
            trayLog.error(
                "Tray action failed (\(failureKey, privacy: .public)): \(known.logSummary, privacy: .public) \(known.logDetail, privacy: .private)"
            )
        } else if let gif = error as? NookGIFError {
            // The case's name is a fixed word, safe to keep in the open.
            trayLog.error(
                "Tray action failed (\(failureKey, privacy: .public)): GIF \(String(describing: gif), privacy: .public)"
            )
        } else {
            // The domain and code say what kind of failure it was. The
            // error's own words can name files, so they stay private.
            trayLog.error(
                "Tray action failed (\(failureKey, privacy: .public)): \(NookTrayLog.cause(error), privacy: .public) \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    /// True for a file that already lives in the tray folder. Dragging a
    /// tray file out and letting go over the island must not copy it in
    /// again.
    nonisolated static func isInside(_ folder: URL, _ file: URL) -> Bool {
        let folderPath = folder.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        return filePath.hasPrefix(folderPath.hasSuffix("/") ? folderPath : folderPath + "/")
    }

    /// Copies a file into the tray. Nil when the file already lives there.
    /// `linking` hard links the file instead when it can, for a recording
    /// that can be gigabytes: a link on the same disk costs no space, and a
    /// copy is the way back when no link can be made.
    @discardableResult
    func add(fileAt source: URL, linking: Bool = false) -> Task<Void, Never>? {
        let folder = self.folder
        guard !Self.isInside(folder, source) else { return nil }
        let id = UUID()
        // Unique stored name: id prefix in its own subfolder keeps the original name intact.
        let storedName = "\(id.uuidString)/\(source.lastPathComponent)"
        let item = NookTrayItem(
            id: id,
            originalName: source.lastPathComponent,
            storedName: storedName,
            addedDate: Date(),
            linkedFrom: linking ? source.path : nil
        )
        // Copying a large file must not block the island.
        return Task.detached(priority: .userInitiated) { [weak self] in
            let fm = FileManager.default
            let subfolder = folder.appendingPathComponent(id.uuidString, isDirectory: true)
            do {
                try fm.createDirectory(at: subfolder, withIntermediateDirectories: true)
                // Marked before the copy starts, as a conversion's folder is.
                NookTrayPartialMarker.write(in: subfolder)
                let destination = folder.appendingPathComponent(storedName)
                var isLinked = false
                if linking {
                    do {
                        try fm.linkItem(at: source, to: destination)
                        isLinked = true
                    } catch {
                        trayLog.notice("Tray: a hard link could not be made, copying instead (\(NookTrayLog.cause(error), privacy: .public))")
                    }
                }
                if !isLinked { try fm.copyItem(at: source, to: destination) }
            } catch {
                trayLog.error("Tray: a file could not be added (\(NookTrayLog.cause(error), privacy: .public))")
                try? fm.removeItem(at: subfolder)
                await MainActor.run { self?.reportFailedAdd(wasLinked: linking) }
                return
            }
            await MainActor.run { self?.register(item) }
        }
    }

    /// Puts a file at the front of the list, or in the place of `sourceID`,
    /// which keeps a result beside the file it came from.
    private func register(_ item: NookTrayItem, beside sourceID: UUID? = nil) {
        let index = sourceID.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        items.insert(item, at: index)
        saveIndex()
        // The file is finished and listed. Whether or not the index reached the
        // disk, the folder is no longer one a launch may clear out: a file the
        // person saw in the tray is not removed behind their back.
        NookTrayPartialMarker.clear(in: storedURL(for: item).deletingLastPathComponent())
        // A file dropped on the closed notch lands out of sight. The notice
        // is the only sign that it arrived.
        nook?.showTransient(
            symbol: "tray.and.arrow.down.fill",
            text: LanguageManager.shared.t("nook.tray.notice.added"),
            duration: .seconds(3)
        )
    }

    /// A recording that is safe in Movies/Hangover but did not reach the tray
    /// says so, because the usual "File not added" would leave the person
    /// wondering whether the recording itself was lost.
    private func reportFailedAdd(wasLinked: Bool) {
        post(wasLinked ? "nook.tray.notice.recordingNotAdded" : "nook.tray.notice.addFailed", .error)
    }

    // MARK: - Index

    /// The name an index that could not be read is moved to.
    nonisolated static let badIndexName = "index.json.bad"

    private var badIndexURL: URL { folder.appendingPathComponent(Self.badIndexName) }

    /// Reads the index. One that cannot be read or understood is logged and
    /// moved aside as `index.json.bad` before anything else can save over
    /// it, and the tray starts empty.
    private func loadIndex() -> NookTrayIndexLoad {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return .missing }
        let decoded: [NookTrayItem]
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoded = try decoder.decode([NookTrayItem].self, from: Data(contentsOf: indexURL))
        } catch {
            trayLog.error("Tray index could not be read (\(NookTrayLog.cause(error), privacy: .public))")
            setBadIndexAside()
            return .failed
        }
        // Drop entries whose file vanished.
        items = decoded.filter { FileManager.default.fileExists(atPath: storedURL(for: $0).path) }
        return .loaded
    }

    /// Keeps the index that failed to load, for someone to look at. If it
    /// cannot be moved, nothing is saved this session, because a save would
    /// write over it.
    private func setBadIndexAside() {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: badIndexURL.path) { try fm.removeItem(at: badIndexURL) }
            try fm.moveItem(at: indexURL, to: badIndexURL)
        } catch {
            trayLog.error("Tray index could not be moved aside, so it will not be saved over (\(NookTrayLog.cause(error), privacy: .public))")
            isIndexWriteBlocked = true
        }
    }

    /// Writes the index. False when it could not be written, which loses
    /// the files added since the last good save the next time Hangover opens.
    @discardableResult
    func saveIndex() -> Bool {
        guard !isIndexWriteBlocked else {
            trayLog.error("Tray index not saved: the one on disk could not be read or moved aside")
            return false
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(items).write(to: indexURL, options: .atomic)
            return true
        } catch {
            trayLog.error("Tray index could not be saved (\(NookTrayLog.cause(error), privacy: .public))")
            return false
        }
    }

    /// Removes the folders left by a quit in the middle of a copy or a
    /// conversion, which hold a partly written result. A folder is removed only
    /// when all of this is true:
    /// - it carries the `.partial` marker (`NookTrayPartialMarker`),
    /// - no file in the index lives in it,
    /// - no other running copy of the app is the one making it,
    /// - there is no `index.json.bad`.
    /// A folder that looks like an orphan and has no marker is left alone, and
    /// so are files in the tray folder itself. Returns the names removed.
    @discardableResult
    func removeOrphanedFolders() -> [String] {
        let fm = FileManager.default
        // An index that failed to read was moved aside, and the folders it
        // named are not in the one that replaced it. Until someone has dealt
        // with the bad copy, nothing here may be taken for leftover work.
        guard !fm.fileExists(atPath: badIndexURL.path) else {
            trayLog.notice("Tray: leftover folders were not cleared out, an unreadable index is kept as \(Self.badIndexName, privacy: .public)")
            return []
        }
        let kept = Set(items.compactMap { $0.storedName.split(separator: "/").first.map(String.init) })
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])
        } catch {
            trayLog.error("Tray folder could not be listed (\(NookTrayLog.cause(error), privacy: .public))")
            return []
        }
        var removed: [String] = []
        for entry in entries where !kept.contains(entry.lastPathComponent) {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard NookTrayPartialMarker.mayRemove(entry) else { continue }
            do {
                try fm.removeItem(at: entry)
                removed.append(entry.lastPathComponent)
            } catch {
                trayLog.error("Tray: leftover folder could not be removed (\(NookTrayLog.cause(error), privacy: .public))")
            }
        }
        if !removed.isEmpty { trayLog.notice("Tray: removed \(removed.count, privacy: .public) leftover folders") }
        return removed
    }
}
