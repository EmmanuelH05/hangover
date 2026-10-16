import Foundation
import Testing
@testable import OpenIslandApp

/// Stands in for the Notes app (D70). Records what it was asked and keeps
/// notes of its own so ids make sense. It never reaches the real Notes app.
final class FakeAppleNotesBridge: NookAppleNotesBridge, @unchecked Sendable {
    enum Call: Equatable {
        case create(html: String)
        case update(id: String, html: String)
        case delete(id: String)
        case find(title: String)
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private var failure: NookAppleNotesError?
    private var isSlow = false
    private var running = 0
    private var peak = 0
    private var made = 0
    private var gone: Set<String> = []
    private var isHeld = false
    private var held: [CheckedContinuation<Void, Never>] = []
    /// The notes the Hangover folder holds, oldest first.
    private var folder: [(id: String, html: String)] = []
    /// Whether the next create times out, and whether the note lands anyway.
    private var nextCreateTimesOut: Bool?

    var calls: [Call] { lock.withLock { recorded } }
    /// The most calls that were ever in flight together.
    var mostAtOnce: Int { lock.withLock { peak } }
    var createCount: Int { calls.filter { if case .create = $0 { true } else { false } }.count }

    func fail(with error: NookAppleNotesError?) {
        lock.withLock { failure = error }
    }

    func slowDown() {
        lock.withLock { isSlow = true }
    }

    /// Every call from now on waits, after it is recorded, until the test lets it go.
    func hold() {
        lock.withLock { isHeld = true }
    }

    /// Calls that are recorded and waiting to be let go.
    var heldCount: Int { lock.withLock { held.count } }

    /// Lets the oldest waiting call go on.
    func releaseNext() {
        let next = lock.withLock { held.isEmpty ? nil : held.removeFirst() }
        next?.resume()
    }

    /// Lets every waiting call go on, and every call after them.
    func releaseAll() {
        let all = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isHeld = false
            defer { held = [] }
            return held
        }
        for continuation in all { continuation.resume() }
    }

    /// The user deleted this note in the Notes app.
    func forget(_ id: String) {
        _ = lock.withLock { gone.insert(id) }
    }

    /// The notes in the Hangover folder, not counting the ones forgotten.
    var noteCount: Int { lock.withLock { folder.filter { !gone.contains($0.id) }.count } }

    /// The next create does not answer in time. `landing` says whether the
    /// Apple event reached Notes before the script was ended, which is when
    /// the note is there anyway. The error is the one the real bridge throws.
    func timeOutNextCreate(landing: Bool) {
        lock.withLock { nextCreateTimesOut = landing }
    }

    /// A note already in the Hangover folder, as if an earlier create had made it.
    @discardableResult
    func plant(title: String) -> String {
        lock.withLock {
            made += 1
            let id = "apple-\(made)"
            folder.append((id, "<div><h1>\(NookAppleNotesBody.escape(title))</h1></div>"))
            return id
        }
    }

    func create(bodyHTML: String) async throws -> String {
        let timeout = lock.withLock { () -> Bool? in
            defer { nextCreateTimesOut = nil }
            return nextCreateTimesOut
        }
        let id: String = try await enter(.create(html: bodyHTML)) {
            guard timeout != false else { return "" }
            made += 1
            folder.append(("apple-\(made)", bodyHTML))
            return "apple-\(made)"
        }
        if timeout != nil { throw NookAppleNotesError.failed }
        return id
    }

    func update(id: String, bodyHTML: String) async throws -> Bool {
        try await enter(.update(id: id, html: bodyHTML)) {
            if let index = folder.firstIndex(where: { $0.id == id }) { folder[index].html = bodyHTML }
            return !gone.contains(id)
        }
    }

    func delete(id: String) async throws {
        try await enter(.delete(id: id)) { () -> Void in folder.removeAll { $0.id == id } }
    }

    /// The ids of the notes in the Hangover folder with this title.
    func find(title: String) async throws -> [String] {
        try await enter(.find(title: title)) {
            folder.filter { !gone.contains($0.id) && $0.html.contains("<h1>\(NookAppleNotesBody.escape(title))</h1>") }.map(\.id)
        }
    }

    /// Waits here while the test holds the calls.
    private func passGate() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let mustWait = lock.withLock { () -> Bool in
                guard isHeld else { return false }
                held.append(continuation)
                return true
            }
            if !mustWait { continuation.resume() }
        }
    }

    private func enter<T>(_ call: Call, _ work: () -> T) async throws -> T {
        let (error, slow): (NookAppleNotesError?, Bool) = lock.withLock {
            recorded.append(call)
            running += 1
            peak = max(peak, running)
            return (failure, isSlow)
        }
        if slow { try? await Task.sleep(for: .milliseconds(20)) }
        await passGate()
        defer { lock.withLock { running -= 1 } }
        if let error { throw error }
        return lock.withLock { work() }
    }
}

/// iCloud, as a test has it: the files it says are not downloaded, and the
/// ones it was asked for. It never reaches the real iCloud.
final class FakeICloud: @unchecked Sendable {
    private let lock = NSLock()
    private var missing: Set<String> = []
    private var asked: [String] = []

    /// The files (by name) iCloud has not downloaded.
    func leaveNotDownloaded(_ names: String...) {
        lock.withLock { missing.formUnion(names) }
    }

    /// The file arrived.
    func download(_ name: String) {
        _ = lock.withLock { missing.remove(name) }
    }

    /// The names of the files iCloud was asked to download.
    var downloadsAsked: [String] { lock.withLock { asked } }

    var tools: NookNoteICloud {
        NookNoteICloud(
            isNotDownloaded: { [self] url in lock.withLock { missing.contains(url.lastPathComponent) } },
            startDownload: { [self] url in lock.withLock { asked.append(url.lastPathComponent) } }
        )
    }
}

/// A folder watcher that reports only when a test says so.
@MainActor
final class FakeFolderWatcher: NookNoteFolderWatching {
    private(set) var watched: URL?
    private(set) var watchCount = 0
    private var onChange: (@MainActor () -> Void)?
    /// False when the system would not start watching (N9).
    var accepts = true

    func watch(_ folder: URL, onChange: @escaping @MainActor () -> Void) -> Bool {
        watchCount += 1
        guard accepts else {
            watched = nil
            self.onChange = nil
            return false
        }
        watched = folder
        self.onChange = onChange
        return true
    }

    func stop() {
        watched = nil
        onChange = nil
    }

    /// Something in the folder changed.
    func fire() {
        onChange?()
    }
}

/// The wait before a save, held until a test lets it go (D70). Nothing here
/// sleeps or depends on how busy the machine is: a wait ends when the test
/// says it does.
@MainActor
final class ManualScheduler {
    private struct Entry {
        let delay: Duration
        let action: @MainActor () -> Void
        var isCancelled = false
    }

    private var entries: [Entry] = []

    /// Waits that were started and not cancelled.
    var waitingCount: Int { entries.filter { !$0.isCancelled }.count }
    var delays: [Duration] { entries.filter { !$0.isCancelled }.map(\.delay) }

    var schedule: NookNoteSaveSchedule {
        { [weak self] delay, action in
            guard let self else { return {} }
            let index = entries.count
            entries.append(Entry(delay: delay, action: action))
            return { [weak self] in self?.entries[index].isCancelled = true }
        }
    }

    /// The time passes: every wait that was not cancelled ends.
    func fire() {
        for index in entries.indices where !entries[index].isCancelled {
            entries[index].isCancelled = true
            entries[index].action()
        }
    }

    /// A wait that was cancelled wakes up late anyway, as a task can.
    func fireCancelled() {
        for entry in entries where entry.isCancelled { entry.action() }
    }
}

/// Everything a notes test needs, in a temporary folder: a home, a notes
/// folder, a Trash, settings held in memory, a fake Notes app and a clock
/// the test moves.
@MainActor
final class NookNotesHarness {
    let defaults = MemoryDefaults()
    let bridge = FakeAppleNotesBridge()
    let watcher = FakeFolderWatcher()
    let scheduler = ManualScheduler()
    let iCloud = FakeICloud()
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("NookNotesTests-\(UUID().uuidString)", isDirectory: true)
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    private(set) var notices: [NookNotesNotice] = []
    private(set) var drafts: [Bool] = []
    private(set) var prompts: [Bool] = []
    private(set) var editorChanges = 0
    private(set) var openedSettings: [URL] = []

    var folder: URL { home.appendingPathComponent("Notes Folder", isDirectory: true) }
    var trashFolder: URL { home.appendingPathComponent("Trash", isDirectory: true) }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    init(folderIsSet: Bool = true) {
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        if folderIsSet { defaults.set(folder.path, forKey: NookNotesStore.folderKey) }
    }

    deinit {
        try? FileManager.default.removeItem(at: home)
    }

    func makeStore(
        saveTo: NookNotesSaveTo? = nil,
        bridge custom: (any NookAppleNotesBridge)? = nil,
        calendar: Calendar? = nil,
        start: Bool = true
    ) -> NookNotesStore {
        if let saveTo { defaults.set(saveTo.rawValue, forKey: NookNotesStore.saveToKey) }
        let trashFolder = trashFolder
        let store = NookNotesStore(
            defaults: defaults,
            home: home,
            appleNotes: custom ?? bridge,
            watcher: watcher,
            calendar: calendar ?? Self.calendar,
            now: { [weak self] in self?.date ?? Date() },
            schedule: scheduler.schedule,
            trash: { url in
                try FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: url, to: trashFolder.appendingPathComponent(url.lastPathComponent))
            },
            iCloud: iCloud.tools
        )
        store.onNotice = { [weak self] in self?.notices.append($0) }
        store.onDraftChange = { [weak self] in self?.drafts.append($0) }
        store.onSystemPrompt = { [weak self] in self?.prompts.append($0) }
        store.onEditorChange = { [weak self] in self?.editorChanges += 1 }
        store.openSettings = { [weak self] in self?.openedSettings.append($0) }
        if start { store.start() }
        return store
    }

    /// A second passes with no key pressed: the wait before a save ends.
    func letTheSaveHappen() {
        scheduler.fire()
    }

    /// Waits until every send to the Notes app has been made, including the
    /// ones a send that worked queued behind it.
    func settle(_ store: NookNotesStore) async {
        while let last = store.lastSync {
            await last.value
            if store.lastSync == last { break }
        }
    }

    // MARK: Files

    func fileNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    func text(of name: String) -> String? {
        try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
    }

    func trashed() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: trashFolder.path)) ?? []).sorted()
    }

    /// A file as another program leaves it: no front matter, the file's own
    /// modification date set.
    func writeOutside(_ name: String, _ text: String, modified: Date? = nil) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        if let modified { try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
    }

    func removeOutside(_ name: String) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }
}
