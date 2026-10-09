import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let trayLog = Logger(subsystem: "app.openisland", category: "nook.tray")

/// One file held in the tray.
struct NookTrayItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let originalName: String
    let storedName: String
    let addedDate: Date
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
        didSet { if tab != oldValue { defaults.set(tab.rawValue, forKey: Self.tabKey) } }
    }

    /// True while the system share picker hangs off a tray file. The
    /// island stays open under it.
    private(set) var isSharePickerOpen = false

    /// The last thing an action had to say, shown in the card for a moment.
    private(set) var notice: NookTrayNotice?

    /// Files a quick action is working on right now.
    private(set) var workingIDs: Set<UUID> = []

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private var indexURL: URL { folder.appendingPathComponent("index.json") }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
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
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        loadIndex()
        clipboard.start()
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
        try? FileManager.default.removeItem(at: storedURL(for: item).deletingLastPathComponent())
        items.removeAll { $0.id == item.id }
        saveIndex()
    }

    func clear() {
        for item in items {
            try? FileManager.default.removeItem(at: storedURL(for: item).deletingLastPathComponent())
        }
        items = []
        saveIndex()
    }

    func revealInFinder(_ item: NookTrayItem) {
        NSWorkspace.shared.activateFileViewerSelecting([storedURL(for: item)])
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
            from: item,
            named: NookTrayFileActions.zipName(for: item.originalName),
            failureKey: "nook.tray.notice.zipFailed"
        ) { source, destination in
            try NookTrayFileActions.zip(source, to: destination)
        }
    }

    /// Converts a picture and adds the copy to the tray as a new file.
    @discardableResult
    func convert(_ item: NookTrayItem, to format: NookTrayImageFormat) -> Task<Void, Never> {
        addDerived(
            from: item,
            named: NookTrayFileActions.convertedName(for: item.originalName, to: format),
            failureKey: "nook.tray.notice.convertFailed"
        ) { source, destination in
            try NookTrayFileActions.convertImage(at: source, to: destination, format: format)
        }
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
    /// before its work is done.
    private func post(_ key: String, _ kind: NookTrayNotice.Kind) {
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
        }
    }

    /// Makes a new file from a tray file and adds it to the tray. The work
    /// runs off the main thread, and the file it starts from is not
    /// changed.
    private func addDerived(
        from item: NookTrayItem,
        named name: String,
        failureKey: String,
        work: @escaping @Sendable (_ source: URL, _ destination: URL) throws -> Void
    ) -> Task<Void, Never> {
        let source = storedURL(for: item)
        let folder = self.folder
        let id = UUID()
        let derived = NookTrayItem(id: id, originalName: name, storedName: "\(id.uuidString)/\(name)", addedDate: Date())
        workingIDs.insert(item.id)
        return Task.detached(priority: .userInitiated) { [weak self] in
            let fm = FileManager.default
            let subfolder = folder.appendingPathComponent(id.uuidString, isDirectory: true)
            // The notice for a failure, nil when the work went through.
            let failure: String?
            do {
                try fm.createDirectory(at: subfolder, withIntermediateDirectories: true)
                try work(source, folder.appendingPathComponent(derived.storedName))
                failure = nil
            } catch {
                try? fm.removeItem(at: subfolder)
                Self.log(error, for: failureKey)
                failure = (error as? NookTrayFileActionError)?.noticeKey ?? failureKey
            }
            await MainActor.run {
                guard let self else { return }
                self.workingIDs.remove(item.id)
                if let failure {
                    self.post(failure, .error)
                } else {
                    self.register(derived)
                }
            }
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
        } else {
            trayLog.error(
                "Tray action failed (\(failureKey, privacy: .public)): \(error.localizedDescription, privacy: .private)"
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
    @discardableResult
    func add(fileAt source: URL) -> Task<Void, Never>? {
        let folder = self.folder
        guard !Self.isInside(folder, source) else { return nil }
        let id = UUID()
        // Unique stored name: id prefix in its own subfolder keeps the original name intact.
        let storedName = "\(id.uuidString)/\(source.lastPathComponent)"
        let item = NookTrayItem(id: id, originalName: source.lastPathComponent, storedName: storedName, addedDate: Date())
        // Copying a large file must not block the island.
        return Task.detached(priority: .userInitiated) { [weak self] in
            let fm = FileManager.default
            let subfolder = folder.appendingPathComponent(id.uuidString, isDirectory: true)
            do {
                try fm.createDirectory(at: subfolder, withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: folder.appendingPathComponent(storedName))
            } catch {
                try? fm.removeItem(at: subfolder)
                await MainActor.run { self?.reportFailedAdd() }
                return
            }
            await MainActor.run { self?.register(item) }
        }
    }

    private func register(_ item: NookTrayItem) {
        items.insert(item, at: 0)
        saveIndex()
        // A file dropped on the closed notch lands out of sight. The notice
        // is the only sign that it arrived.
        nook?.showTransient(
            symbol: "tray.and.arrow.down.fill",
            text: LanguageManager.shared.t("nook.tray.notice.added"),
            duration: .seconds(3)
        )
    }

    private func reportFailedAdd() {
        post("nook.tray.notice.addFailed", .error)
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([NookTrayItem].self, from: data) else { return }
        // Drop entries whose file vanished.
        items = decoded.filter { FileManager.default.fileExists(atPath: storedURL(for: $0).path) }
    }

    private func saveIndex() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
