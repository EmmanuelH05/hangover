import AppKit
import Foundation
import Observation

/// The notes (D70): a list of notes, one open in the editor, saving by
/// itself. It replaces the one-line Quick Notes. Where the notes are kept is
/// a `NookNoteDestination`; this class owns what does not depend on that:
/// the list, the editor's text, the wait before a save, the queue that sends
/// notes on to Apple Notes, and the notices.
///
/// The editor's text is not observed. The view that types holds the text it
/// shows, and a keystroke must not draw the page again.
@MainActor
@Observable
final class NookNotesStore {
    nonisolated static let saveToKey = "nook.notes.saveTo"
    nonisolated static let folderKey = "nook.notes.folder"
    /// True once the old Quick Notes file was moved in.
    nonisolated static let importedKey = "nook.notes.oldFileImported"
    /// The keys the one-line Quick Notes used. Read once to carry a choice over.
    nonisolated static let legacyDestinationKey = "nook.notes.destination"
    nonisolated static let legacyPathKey = "nook.notes.path"
    /// True once Notes has answered the question macOS asks the first time.
    nonisolated static let answeredKey = "nook.notes.appleNotes.answered"
    /// The folder that was last seen to be there. A folder that was seen and
    /// is not there now is gone, and is not made again without the user.
    nonisolated static let folderSeenKey = "nook.notes.folderSeen"
    /// What Apple Notes last said when it did not take a note: "notPermitted"
    /// or "failed". Kept between launches, and gone when a send works.
    nonisolated static let appleProblemKey = "nook.notes.appleNotes.problem"

    @ObservationIgnored private(set) weak var nook: NookModel?

    /// The shortcut that starts a new note from any app.
    let hotkey: NookNoteHotkeyController

    /// The notes, newest edit first.
    private(set) var notes: [NookNote] = []
    private(set) var saveTo: NookNotesSaveTo
    private(set) var folderURL: URL
    /// How many saves were made since the app started. The welcome tour
    /// watches it to see a note go in.
    private(set) var savedCount = 0

    /// What is wrong with saving, deleting or opening a note, in words the
    /// editor's header and the card can show while the island is open. Set
    /// by every failure and cleared by the next success. The closed island's
    /// notice goes away after a few seconds; this stays.
    private(set) var problem: NookNotesNotice?

    /// Why Apple Notes is not getting the notes, when it is not (N4). It
    /// stays until a send works, through a quit and a launch: the closed
    /// island says it once, and is rarely seen.
    enum AppleNotesProblem: String, Sendable {
        case notPermitted
        case failed
    }

    private(set) var appleNotesProblem: AppleNotesProblem?

    /// The problem the editor's header and the card show: the last thing
    /// that went wrong with a note, else Apple Notes not taking them.
    var shownProblem: NookNotesNotice? {
        problem ?? appleNotesNotice
    }

    /// Apple Notes not taking the notes, as a notice. Nil when notes do not
    /// go there.
    var appleNotesNotice: NookNotesNotice? {
        guard saveTo.usesAppleNotes, let appleNotesProblem else { return nil }
        let place: NookNotesNotice.Place = saveTo == .both ? .folder : .hangover
        return appleNotesProblem == .notPermitted ? .appleNotesOff(keptIn: place) : .appleNotesFailed(keptIn: place)
    }

    // MARK: Editor state

    /// True while a note is open in the editor.
    private(set) var isEditorOpen = false
    /// Changes when the editor is handed new text: a note opened, or the
    /// file changed under an editor with nothing unsaved. The view that
    /// shows the text copies it again when this changes.
    private(set) var editorRevision = 0
    /// Changes when the cursor should go to the editor.
    private(set) var focusRequest = 0

    @ObservationIgnored private(set) var editorText = ""
    @ObservationIgnored private var editorNoteID: String?
    @ObservationIgnored private var editorCreated = Date.distantPast
    /// The text the destination holds for the open note, "" for a new one.
    @ObservationIgnored private var savedText = ""
    @ObservationIgnored private var cancelPendingSave: (@MainActor () -> Void)?
    /// Names the wait that is running. A wait that ends after it was
    /// replaced does nothing.
    @ObservationIgnored private var saveGeneration = 0
    /// True while a save waits for the last key to be a second old.
    @ObservationIgnored private(set) var hasPendingSave = false

    // MARK: Hooks

    /// Told when a notice is due. The Nook shows it in the closed island.
    @ObservationIgnored var onNotice: (NookNotesNotice) -> Void = { _ in }
    /// Told when the editor opens or closes, which can change the island's height.
    @ObservationIgnored var onEditorChange: () -> Void = {}
    /// Told whether the editor holds text that is not saved yet (`NookDraft`).
    @ObservationIgnored var onDraftChange: (Bool) -> Void = { _ in }
    /// The system windows an Apple Notes send can put up. Told true when the
    /// first send waits on macOS and false when it is answered.
    @ObservationIgnored var onSystemPrompt: (Bool) -> Void = { _ in }
    /// Opens a page of System Settings. A test passes one that opens nothing.
    @ObservationIgnored var openSettings: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Shows a folder in Finder. A test passes one that shows nothing.
    @ObservationIgnored var revealInFinder: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }

    // MARK: Parts

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let bridge: any NookAppleNotesBridge
    @ObservationIgnored private let recordURL: URL
    @ObservationIgnored private let watcher: any NookNoteFolderWatching
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let schedule: NookNoteSaveSchedule
    @ObservationIgnored private let trash: (URL) throws -> Void
    @ObservationIgnored private let iCloud: NookNoteICloud
    @ObservationIgnored private let backlog: NookNotesBacklog
    @ObservationIgnored private var destination: any NookNoteDestination
    @ObservationIgnored private var started = false
    /// What is being watched (N9): the folder, or the folder it will be made
    /// in while it is not there yet, or nothing because watching failed.
    @ObservationIgnored private var watching = Watching.nothing

    private enum Watching {
        case nothing
        case folder
        case parent
    }
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var didNoticeAppleNotes = false
    /// Names the file the open note's text waits in when it cannot be saved.
    @ObservationIgnored private var stashID = UUID().uuidString
    @ObservationIgnored private var isStashed = false
    /// True while the open note's file has the name of an older title (N16):
    /// the next save that is allowed to rename it will.
    @ObservationIgnored private var needsRename = false
    /// The wait before that rename, started by the save that left the name
    /// behind and dropped when the title changes again.
    @ObservationIgnored private var cancelPendingRename: (@MainActor () -> Void)?
    /// The title the rename wait was started for.
    @ObservationIgnored private var renameTitle = ""
    @ObservationIgnored private var renameGeneration = 0
    /// The wait before a list with a downloading row is read again (N17).
    @ObservationIgnored private var cancelDownloadWait: (@MainActor () -> Void)?
    @ObservationIgnored private var downloadChecks = 0

    /// The newest send to Apple Notes. Each send waits for the one before
    /// it: the script reads the note and then writes it, and two running at
    /// once would make a note twice.
    @ObservationIgnored private(set) var lastSync: Task<Void, Never>?

    /// The sends queued and not over, by the backlog entry each one keeps. A
    /// note saved again while its first send waits has two in line, and its
    /// entry stays until the last of them is over.
    @ObservationIgnored private var inLine: [String: Int] = [:]

    /// True once a send to Notes came back allowed or refused, which is when
    /// macOS has asked its one question. Kept between launches.
    private(set) var hasNotesAnswer: Bool {
        get { defaults.bool(forKey: Self.answeredKey) }
        set { defaults.set(newValue, forKey: Self.answeredKey) }
    }

    /// `home` is where the default folder, the old Quick Notes file and the
    /// record of Apple notes are looked for. A test passes a folder of its
    /// own, and a fake for `appleNotes`, `watcher` and `trash`.
    init(
        defaults: UserDefaults = .standard,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        appleNotes: any NookAppleNotesBridge = NookAppleNotesScriptBridge(),
        recordURL: URL? = nil,
        watcher: any NookNoteFolderWatching = NookNoteFolderWatcher(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() },
        schedule: @escaping NookNoteSaveSchedule = NookNotesStore.timerSchedule,
        trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
        iCloud: NookNoteICloud = .live
    ) {
        self.defaults = defaults
        self.iCloud = iCloud
        backlog = NookNotesBacklog(defaults: defaults)
        appleNotesProblem = defaults.string(forKey: Self.appleProblemKey).flatMap(AppleNotesProblem.init(rawValue:))
        hotkey = NookNoteHotkeyController(defaults: defaults)
        self.home = home
        bridge = appleNotes
        self.recordURL = recordURL ?? NookNoteLocations.appleNotesRecord(home: home)
        self.watcher = watcher
        self.calendar = calendar
        self.now = now
        self.schedule = schedule
        self.trash = trash

        let choice = Self.storedSaveTo(in: defaults)
        let (folder, isSettled) = Self.storedFolderChoice(in: defaults, home: home)
        // A folder chosen by default is kept, which keeps it from moving to
        // another place if an Obsidian vault appears later. Not when the look
        // for a vault failed (N12): the fallback is for this launch, and the
        // next one looks again until a folder is chosen or made.
        if defaults.string(forKey: Self.folderKey) == nil, isSettled { defaults.set(folder.path, forKey: Self.folderKey) }
        saveTo = choice
        folderURL = folder
        destination = Self.makeDestination(
            choice, folder: folder, defaults: defaults, bridge: appleNotes,
            recordURL: self.recordURL, calendar: calendar, now: now, trash: trash, iCloud: iCloud
        )
    }

    isolated deinit {
        cancelSave()
        watcher.stop()
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    // MARK: The wait before a save

    /// Waits `delay`, then runs `action`. Returns what cancels the wait. The
    /// app's wait is a task; a test passes one it fires by hand, which keeps
    /// it from depending on how busy the machine is.
    static let timerSchedule: NookNoteSaveSchedule = { delay, action in
        let task = Task { @MainActor in
            do { try await Task.sleep(for: delay) } catch { return }
            action()
        }
        return { task.cancel() }
    }

    // MARK: Settings read at launch

    nonisolated static func storedSaveTo(in defaults: UserDefaults) -> NookNotesSaveTo {
        if let stored = defaults.string(forKey: saveToKey).flatMap(NookNotesSaveTo.init(rawValue:)) { return stored }
        // A choice made before notes were files: Apple Notes stays Apple Notes.
        return defaults.string(forKey: legacyDestinationKey) == "appleNotes" ? .appleNotes : .folder
    }

    nonisolated static func storedFolder(in defaults: UserDefaults, home: URL) -> URL {
        storedFolderChoice(in: defaults, home: home).folder
    }

    /// The folder, and whether it is a choice that holds: one chosen or
    /// made, or a default that was looked up properly.
    nonisolated static func storedFolderChoice(in defaults: UserDefaults, home: URL) -> (folder: URL, isSettled: Bool) {
        if let path = defaults.string(forKey: folderKey), !path.isEmpty {
            return (URL(fileURLWithPath: NookNoteLocations.expandingHome(path, home: home), isDirectory: true), true)
        }
        let choice = NookNoteLocations.defaultChoice(home: home)
        return (choice.folder, choice.isSettled)
    }

    private static func makeDestination(
        _ choice: NookNotesSaveTo,
        folder: URL,
        defaults: UserDefaults,
        bridge: any NookAppleNotesBridge,
        recordURL: URL,
        calendar: Calendar,
        now: @escaping () -> Date,
        trash: @escaping (URL) throws -> Void,
        iCloud: NookNoteICloud
    ) -> any NookNoteDestination {
        switch choice {
        case .folder:
            return NookFolderDestination(
                folder: folder, calendar: calendar,
                isFolderExpected: { Self.wasSeen(folder, in: defaults) }, iCloud: iCloud, trash: trash
            )
        case .appleNotes:
            let ids = NookAppleNoteIDs(defaults: defaults, scope: "record")
            return NookAppleNotesDestination(
                record: NookAppleNotesRecord(fileURL: recordURL, now: now),
                link: NookAppleNotesLink(bridge: bridge, ids: ids)
            )
        case .both:
            let ids = NookAppleNoteIDs(defaults: defaults, scope: folder.standardizedFileURL.path)
            return NookBothDestination(
                folder: NookFolderDestination(
                    folder: folder, calendar: calendar,
                    isFolderExpected: { Self.wasSeen(folder, in: defaults) }, iCloud: iCloud, trash: trash
                ),
                link: NookAppleNotesLink(bridge: bridge, ids: ids)
            )
        }
    }

    // MARK: Lifecycle

    /// Joins the store to the Nook: its notices, the draft guard and the
    /// island's height. Called once from `NookModel.start`.
    func start(nook: NookModel) {
        self.nook = nook
        onNotice = { [weak nook] notice in
            nook?.showTransient(
                symbol: notice.symbol, text: LanguageManager.shared.t(notice.textKey),
                tint: .orange, duration: .seconds(5)
            )
        }
        onDraftChange = { [weak nook] isUnsaved in nook?.setDraft(.note, isUnsaved: isUnsaved) }
        onSystemPrompt = { [weak nook] isUp in
            if isUp { nook?.systemPromptBegan() } else { nook?.systemPromptEnded() }
        }
        onEditorChange = { [weak nook] in nook?.onDisplayPreferencesChanged?() }
        start()
    }

    /// Reads the notes, moves the old Quick Notes file in the first time,
    /// and starts to watch the folder. A test calls this one.
    func start() {
        guard !started else { return }
        started = true
        reportStandingProblem()
        restoreUnsavedNotes()
        importOldNotesIfNeeded()
        reload()
        watchFolder()
        retryBacklog()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.appWillTerminate() }
        }
    }

    /// The app is quitting. What is typed is saved; text that cannot be saved
    /// is kept in a file of its own, which the next launch puts back. A send
    /// to Apple Notes that is still in line when the app exits is in the
    /// backlog from the moment it was queued, and the next launch makes it.
    func appWillTerminate() {
        if !flush() { stashEditorText() }
    }

    /// True while a send to Apple Notes is queued and not over.
    var hasPendingAppleSync: Bool { !inLine.isEmpty }

    /// Waits until every send in line has been made, including the ones a
    /// send that worked queued behind it. The quit gives this a limit
    /// (`NookQuitWait`) and does not depend on it ending: a send given up on
    /// is in the backlog.
    func waitForAppleNotes() async {
        while let last = lastSync, hasPendingAppleSync {
            await last.value
            if lastSync == last { break }
        }
    }

    // MARK: The list

    /// Reads the destination again. A read that fails keeps the list that was
    /// there, and says why where the user can read it: a folder that cannot
    /// be read is not a folder with no notes in it.
    func reload() {
        let loaded: [NookNote]
        do {
            loaded = try destination.load()
        } catch {
            NookNotesLog.failure("list the notes", path: folderURL.path, error: error)
            // A note that could not be saved says more than a list that could not be read.
            if problem == nil || problem?.isAboutFolder == true { report(readNotice(for: error)) }
            return
        }
        if problem?.isAboutFolder == true { problem = nil }
        markFolderSeen()
        let next = NookNoteFiles.ordered(loaded)
        if next != notes { notes = next }
        reconcileEditor()
        watchDownloads()
    }

    // MARK: Notes still on their way from iCloud (N17)

    /// A row that says downloading is read again in a few seconds, because
    /// the folder watcher may not report a file arriving. It stops after a
    /// while: the next change, or the island opening, reads the list again.
    private func watchDownloads() {
        guard notes.contains(where: { $0.state == .downloading }) else {
            cancelDownloadWait?()
            cancelDownloadWait = nil
            downloadChecks = 0
            return
        }
        guard cancelDownloadWait == nil, downloadChecks < NookNoteSizes.downloadChecks else { return }
        downloadChecks += 1
        cancelDownloadWait = schedule(NookNoteSizes.downloadCheckDelay) { [weak self] in
            guard let self else { return }
            self.cancelDownloadWait = nil
            self.reload()
        }
    }

    private func watchFolder() {
        guard saveTo.usesFolder else {
            watcher.stop()
            watching = .nothing
            return
        }
        let onChange: @MainActor () -> Void = { [weak self] in self?.folderChanged() }
        if FileManager.default.fileExists(atPath: folderURL.path) {
            watching = watcher.watch(folderURL, onChange: onChange) ? .folder : .nothing
            if watching == .nothing {
                NookNotesLog.warning("The notes folder is not watched, so notes changed elsewhere show when the island opens or a note is saved", path: folderURL.path)
            }
            return
        }
        // Nothing is made just to be watched: the folder may be one macOS
        // asks about, and it exists once a note is saved in it. The folder it
        // will be made in is watched, so one made by hand is noticed.
        let parent = folderURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.path), watcher.watch(parent, onChange: onChange) {
            watching = .parent
        } else {
            watcher.stop()
            watching = .nothing
            NookNotesLog.warning("The place the notes folder will be made in is not watched", path: parent.path)
        }
    }

    /// Something in the watched place changed.
    private func folderChanged() {
        reload()
        // The folder was made: it is watched in its own right now.
        if watching == .parent, FileManager.default.fileExists(atPath: folderURL.path) { watchFolder() }
    }

    /// The island opened (N9): a watcher that did not start is tried again,
    /// and the list is read, because it may have missed changes.
    func islandOpened() {
        guard saveTo.usesFolder else { return }
        if watching != .folder {
            watchFolder()
            reload()
        } else if notes.contains(where: { $0.state == .downloading }) {
            // A file that was on its way may be here by now.
            downloadChecks = 0
            reload()
        }
    }

    /// The open note was changed or removed by another program.
    private func reconcileEditor() {
        guard isEditorOpen, let id = editorNoteID else { return }
        // A file that cannot be read now is not known to be gone. The editor
        // keeps what it has, and a save will not write over the file.
        if let listed = notes.first(where: { $0.id == id }), listed.state != .readable { return }
        guard let listed = notes.first(where: { $0.id == id }) else {
            // Gone from the folder. What is typed and not saved is kept and
            // becomes a new note; a note with nothing unsaved is let go.
            if isDirty {
                editorNoteID = nil
                savedText = ""
            } else {
                closeEditorState()
            }
            return
        }
        guard listed.text != savedText, !isDirty else { return }
        editorText = listed.text
        savedText = listed.text
        editorRevision += 1
    }

    // MARK: Editor

    /// Opens a blank note. One already open is saved first.
    func beginNewNote() {
        if isEditorOpen, editorNoteID == nil, !NookNoteFiles.hasContent(editorText) {
            focusRequest += 1
            return
        }
        guard flush() else { return }
        present(text: "", noteID: nil, created: now())
    }

    /// Opens a note from the list. The one open is saved first. The note is
    /// read again from where it is kept: the list may be older than the file,
    /// and what the editor starts from is what a save is compared with.
    func open(_ id: String) {
        guard flush() else { return }
        if notes.first(where: { $0.id == id })?.state == .unreadable {
            report(.noteUnreadable(NookNoteFiles.stem(of: id)))
            return
        }
        let note: NookNote
        do {
            guard let fresh = try destination.read(id: id) else {
                // Gone since the list was read.
                reload()
                return
            }
            note = fresh
        } catch {
            NookNotesLog.failure("open a note", path: folderURL.appendingPathComponent(id).path, error: error)
            // A note on its way from iCloud is not a note that cannot be read.
            if error as? NookNoteStorageError == .notDownloaded {
                report(.noteDownloading(NookNoteFiles.stem(of: id)))
                reload()
            } else {
                report(.noteUnreadable(NookNoteFiles.stem(of: id)))
            }
            return
        }
        notes = NookNoteFiles.ordered(notes.filter { $0.id != id } + [note])
        present(text: note.text, noteID: note.id, created: note.created)
    }

    private func present(text: String, noteID: String?, created: Date, savedText saved: String? = nil) {
        cancelSave()
        // A note about something that happened, such as a copy, was read by now.
        if problem?.isInformation == true { problem = nil }
        // A new editor session has a stash file of its own.
        stashID = UUID().uuidString
        isStashed = false
        cancelRename()
        editorText = text
        editorNoteID = noteID
        editorCreated = created
        savedText = saved ?? text
        let wasOpen = isEditorOpen
        isEditorOpen = true
        editorRevision += 1
        focusRequest += 1
        reportDraft()
        if !wasOpen { onEditorChange() }
    }

    /// The editor's text changed because the user typed. The note is saved
    /// a moment after the last key.
    func edit(_ text: String) {
        guard isEditorOpen, text != editorText else { return }
        editorText = text
        // A new first line starts the wait for a rename over.
        if cancelPendingRename != nil, NookNoteFiles.title(from: text) != renameTitle { dropRenameWait() }
        reportDraft()
        scheduleSave()
    }

    /// Closes the editor and keeps the note. A save that failed keeps the
    /// editor open, with the text in it.
    func closeEditor() {
        guard flush() else { return }
        closeEditorState()
    }

    /// The island closed, or the page it was on went away.
    func islandClosed() {
        closeEditor()
    }

    private func closeEditorState() {
        cancelSave()
        cancelRename()
        let wasOpen = isEditorOpen
        isEditorOpen = false
        editorText = ""
        editorNoteID = nil
        savedText = ""
        reportDraft()
        if wasOpen { onEditorChange() }
    }

    // MARK: Saving

    /// True while the editor holds text the destination does not have. A new
    /// note with nothing in it has nothing to save.
    var isDirty: Bool {
        guard isEditorOpen, editorText != savedText else { return false }
        return editorNoteID != nil || NookNoteFiles.hasContent(editorText)
    }

    /// True while there is text that would be lost: the island stays open.
    var holdsUnsavedDraft: Bool {
        isDirty && NookNoteFiles.hasContent(editorText)
    }

    private func reportDraft() {
        onDraftChange(holdsUnsavedDraft)
    }

    private func scheduleSave() {
        cancelSave()
        guard isDirty else { return }
        let generation = saveGeneration
        hasPendingSave = true
        cancelPendingSave = schedule(NookNoteSizes.saveDelay) { [weak self] in
            guard let self, self.saveGeneration == generation else { return }
            // This wait is over; `flush` has nothing left to cancel.
            self.cancelPendingSave = nil
            self.hasPendingSave = false
            // A save while the user is typing keeps the file's name.
            _ = self.flush(renaming: false)
        }
    }

    /// Drops the wait that is running, if any.
    private func cancelSave() {
        cancelPendingSave?()
        cancelPendingSave = nil
        hasPendingSave = false
        saveGeneration += 1
    }

    /// Saves what is typed now, without waiting. False when the note could not
    /// be written; the text stays in the editor. A file whose name is behind
    /// its title is renamed, unless `renaming` is false: the save that runs a
    /// moment after a key leaves names alone (N16), and every other save, such
    /// as the editor closing, renames.
    @discardableResult
    func flush(renaming: Bool = true) -> Bool {
        cancelSave()
        guard isDirty || (renaming && needsRename) else {
            dropStashIfEmptied()
            return true
        }
        return commit(renaming: renaming)
    }

    private func commit(renaming: Bool) -> Bool {
        let text = editorText
        guard NookNoteFiles.hasContent(text) else {
            // A note emptied by the user is deleted. One that never had
            // anything is not made.
            if let id = editorNoteID {
                guard remove(id, closingEditor: false) else { return false }
                // The editor stays open, blank. What is typed next is a new note.
                editorCreated = now()
            }
            editorNoteID = nil
            savedText = text
            cancelRename()
            clearStash()
            succeeded()
            reportDraft()
            return true
        }
        let previousID = editorNoteID
        do {
            // The file is compared with what the editor started from, so a
            // change made by another program is not written over.
            let result = try destination.save(
                text: text, id: previousID, base: previousID == nil ? nil : savedText,
                created: editorCreated, now: now(), renaming: renaming
            )
            let note = result.note
            editorNoteID = note.id
            editorCreated = note.created
            savedText = text
            // A copy sits beside the note it was made from, which stays.
            let replaced = result.isCopy ? nil : previousID
            if let replaced, replaced != note.id { destination.moved(from: replaced, to: note.id) }
            notes = NookNoteFiles.ordered(notes.filter { $0.id != replaced && $0.id != note.id } + [note])
            if saveTo != .appleNotes { savedCount += 1 }
            clearStash()
            markFolderSeen()
            updateRenameWait(isPending: result.isRenamePending, title: NookNoteFiles.title(from: text))
            if result.isCopy { report(.savedAsCopy(note.id)) } else { succeeded() }
            reportDraft()
            startWatchingAfterFirstSave()
            if let replaced, replaced != note.id {
                backlog.move(noteID: replaced, to: note.id, scope: syncScope)
            }
            // An Apple Notes only destination has no file: the note is saved when Notes has it.
            enqueue(.note(note, replacing: replaced), countsAsSave: saveTo == .appleNotes)
            if result.isCopy { reload() }
            return true
        } catch {
            NookNotesLog.failure("save", path: folderURL.path, error: error)
            stashEditorText()
            report(writeNotice(for: error))
            return false
        }
    }

    // MARK: Renaming a file (N16)

    /// After a save: a name that is behind the title waits for the title to
    /// hold still, and a name that fits needs nothing.
    private func updateRenameWait(isPending: Bool, title: String) {
        guard isPending else {
            cancelRename()
            return
        }
        needsRename = true
        guard cancelPendingRename == nil else { return }
        renameTitle = title
        let generation = renameGeneration
        cancelPendingRename = schedule(NookNoteSizes.renameDelay) { [weak self] in
            guard let self, self.renameGeneration == generation else { return }
            self.cancelPendingRename = nil
            _ = self.flush(renaming: true)
        }
    }

    /// Ends the wait for a rename, and the rename itself.
    private func cancelRename() {
        dropRenameWait()
        needsRename = false
    }

    /// Ends the wait only. The name is still behind the title, and the next
    /// save starts the wait again.
    private func dropRenameWait() {
        cancelPendingRename?()
        cancelPendingRename = nil
        renameGeneration += 1
    }

    // MARK: When a note cannot be saved

    /// Shows a problem in the places the user can read while the island is
    /// open, and tells the closed island the first time. A save that fails
    /// again with the same problem does not tell it again.
    private func report(_ notice: NookNotesNotice) {
        let isNew = problem != notice
        problem = notice
        if isNew { onNotice(notice) }
    }

    /// A save or a delete worked: what a failure said is over. A note about
    /// something that happened, such as a copy, stays until the next note is
    /// opened.
    private func succeeded() {
        if problem?.isInformation != true { problem = nil }
    }

    /// What the destination found wrong with what it keeps, when it opened.
    private func reportStandingProblem() {
        if let standing = destination.standingProblem { report(standing) }
    }

    /// What a list that could not be read is told as.
    private func readNotice(for error: Error) -> NookNotesNotice {
        if let standing = destination.standingProblem, standing == .appleNotesListUnreadable { return standing }
        let name = folderURL.lastPathComponent
        return error as? NookNoteStorageError == .folderGone ? .folderGone(name) : .cantReadFolder(name)
    }

    /// The folder was there: if it is not there later, it is gone and not new.
    private func markFolderSeen() {
        guard saveTo.usesFolder, FileManager.default.fileExists(atPath: folderURL.path) else { return }
        let path = folderURL.standardizedFileURL.path
        if defaults.string(forKey: Self.folderSeenKey) != path { defaults.set(path, forKey: Self.folderSeenKey) }
        // A folder that exists is a folder that was made: a stand-in default is kept now (N12).
        if defaults.string(forKey: Self.folderKey) == nil { defaults.set(folderURL.path, forKey: Self.folderKey) }
    }

    nonisolated static func wasSeen(_ folder: URL, in defaults: UserDefaults) -> Bool {
        defaults.string(forKey: folderSeenKey) == folder.standardizedFileURL.path
    }

    /// Shows the notes folder in Finder (N12). A folder that was there and is
    /// gone is not made again to have something to show: the card and
    /// Settings say it is gone, with a button to make it. A folder never made
    /// is made, so there is something to show.
    func revealFolder() {
        let name = folderURL.lastPathComponent
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            guard !Self.wasSeen(folderURL, in: defaults) else {
                report(.folderGone(name))
                return
            }
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            } catch {
                NookNotesLog.failure("make the notes folder to show it", path: folderURL.path, error: error)
                report(.cantReadFolder(name))
                return
            }
        }
        revealInFinder(folderURL)
    }

    /// Makes the folder again, after the user said to. Notes saved in it
    /// before are not there; whatever is in it now is listed.
    func createFolder() {
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            NookNotesLog.failure("make the notes folder", path: folderURL.path, error: error)
            report(.cantReadFolder(folderURL.lastPathComponent))
            return
        }
        problem = nil
        reload()
        watchFolder()
    }

    /// What a failed write is told as. A folder that cannot be written to is
    /// the likely cause, so the notice offers to choose another.
    private func writeNotice(for error: Error) -> NookNotesNotice {
        if destination.standingProblem == .appleNotesListUnreadable { return .appleNotesListUnreadable }
        if error as? NookNoteStorageError == .notDownloaded {
            return .noteDownloading(editorNoteID.map(NookNoteFiles.stem(of:)) ?? folderURL.lastPathComponent)
        }
        if error as? NookNoteStorageError == .folderGone { return .folderGone(folderURL.lastPathComponent) }
        return saveTo.usesFolder ? .notSavedInFolder(folderURL.lastPathComponent) : .notSaved
    }

    /// Puts the open note's text in a file of its own, so a quit with a note
    /// that cannot be saved does not lose it. The next launch puts it back.
    private func stashEditorText() {
        let text = editorText
        guard NookNoteFiles.hasContent(text) else { return }
        let folder = NookNoteLocations.unsavedFolder(home: home)
        let url = folder.appendingPathComponent("\(stashID).md")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            isStashed = true
        } catch {
            NookNotesLog.failure("stash an unsaved note", path: url.path, error: error)
        }
    }

    /// A note that could not be saved and was then emptied has nothing left
    /// to keep, and nothing left that fails to save.
    private func dropStashIfEmptied() {
        guard isStashed, !NookNoteFiles.hasContent(editorText) else { return }
        clearStash()
        if problem?.isAboutSaving == true { problem = nil }
    }

    /// The note was saved after all, or has nothing in it: its stash goes.
    private func clearStash() {
        guard isStashed else { return }
        isStashed = false
        let url = NookNoteLocations.unsavedFolder(home: home).appendingPathComponent("\(stashID).md")
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            NookNotesLog.failure("remove a stashed note", path: url.path, error: error)
        }
    }

    /// Puts back the notes that could not be saved the last time, as notes
    /// of their own. A note is never written over another: it gets a name
    /// like any new note. A stash that cannot be put back stays for the next
    /// launch.
    private func restoreUnsavedNotes() {
        let folder = NookNoteLocations.unsavedFolder(home: home)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch {
            NookNotesLog.failure("list unsaved notes", path: folder.path, error: error)
            return
        }
        var restored = false
        for name in names.sorted() where name.hasSuffix(".md") {
            let url = folder.appendingPathComponent(name)
            let text: String
            do {
                text = try String(contentsOf: url, encoding: .utf8)
            } catch {
                NookNotesLog.failure("read an unsaved note", path: url.path, error: error)
                continue
            }
            guard NookNoteFiles.hasContent(text) else {
                // Nothing in it to put back.
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    NookNotesLog.failure("remove an empty stash", path: url.path, error: error)
                }
                continue
            }
            let stamp = now()
            do {
                let written = try destination.write(text: text, id: nil, created: stamp, now: stamp)
                enqueue(.note(written, replacing: nil))
                restored = true
            } catch {
                NookNotesLog.failure("restore an unsaved note", path: url.path, error: error)
                report(writeNotice(for: error))
                continue
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                NookNotesLog.failure("remove a restored stash", path: url.path, error: error)
            }
        }
        if restored, problem == nil { report(.restored) }
    }

    /// A folder that did not exist could not be watched. It does now.
    private func startWatchingAfterFirstSave() {
        guard watching != .folder else { return }
        watchFolder()
    }

    // MARK: Deleting

    /// Deletes a note: a file goes to the Trash, an Apple note is deleted.
    func delete(_ id: String) {
        remove(id, closingEditor: true)
    }

    @discardableResult
    private func remove(_ id: String, closingEditor: Bool) -> Bool {
        var erasure: NookNoteErasure
        do {
            erasure = try destination.erase(id: id)
            // The Apple note is only this note's if it was made for a note created as this one was.
            // A note with no `created:` text has only a birth date to give, and that moves (N14).
            if let listed = notes.first(where: { $0.id == id }), let text = listed.createdText {
                erasure.created = listed.created
                erasure.createdText = text
            }
        } catch {
            NookNotesLog.failure("delete", path: folderURL.appendingPathComponent(id).path, error: error)
            report(.notDeleted)
            return false
        }
        succeeded()
        notes.removeAll { $0.id == id }
        if closingEditor, editorNoteID == id { closeEditorState() }
        backlog.remove(noteID: id, scope: syncScope)
        enqueue(.erase(erasure))
        return true
    }

    // MARK: Apple Notes

    /// One send to Apple Notes.
    private enum Send {
        case note(NookNote, replacing: String?)
        case erase(NookNoteErasure)

        static func noteKey(_ id: String, scope: String) -> String {
            "note\n\(scope)\n\(id)"
        }

        /// What the send is kept under in the backlog, with its scope.
        func key(scope: String) -> String {
            switch self {
            case let .note(note, _):
                return Self.noteKey(note.id, scope: scope)
            case let .erase(erasure):
                let created = erasure.created.map { String(NookNoteFiles.seconds($0)) } ?? ""
                return "erase\n\(scope)\n\(erasure.noteID)\n\(created)\n\(erasure.createdText ?? "")"
            }
        }
    }

    /// What the Apple notes of this destination are kept under, as the
    /// mapping of notes to Apple notes keeps them.
    private var syncScope: String {
        saveTo == .appleNotes ? "record" : folderURL.standardizedFileURL.path
    }

    /// Runs a send after every send queued before it. Does nothing for a
    /// destination with no Apple side. `countsAsSave` is for a destination
    /// that has no file: the note is saved when Notes has it.
    private func enqueue(_ send: Send, countsAsSave: Bool = false, isRetry: Bool = false) {
        guard saveTo.usesAppleNotes else { return }
        let destination = destination
        let scope = syncScope
        // Kept from here and not from the first failure: the app may exit
        // before the send's turn comes, and it would be neither made nor failed.
        keep(send, scope: scope)
        let previous = lastSync
        lastSync = Task { [weak self] in
            await previous?.value
            await self?.run(send, on: destination, scope: scope, countsAsSave: countsAsSave, isRetry: isRetry)
        }
    }

    /// Puts the send in the backlog, where it stays until it has been made.
    private func keep(_ send: Send, scope: String) {
        switch send {
        case let .note(note, _): backlog.add(noteID: note.id, scope: scope)
        case let .erase(erasure): backlog.add(erasure, scope: scope)
        }
        inLine[send.key(scope: scope), default: 0] += 1
    }

    /// The send is over, made or not. True when no other send for the same
    /// note is still in line.
    private func leaveLine(_ send: Send, scope: String) -> Bool {
        let key = send.key(scope: scope)
        let left = (inLine[key] ?? 1) - 1
        inLine[key] = left > 0 ? left : nil
        return left <= 0
    }

    private func run(
        _ send: Send, on destination: any NookNoteDestination, scope: String, countsAsSave: Bool, isRetry: Bool
    ) async {
        // macOS asks once whether the app may control Notes, at the first
        // send, and the prompt opens under the island. Until that answer is
        // in, a send counts as a prompt (D52). Later sends do not: the
        // island would dip for every note.
        let asks = !hasNotesAnswer
        if asks { onSystemPrompt(true) }
        defer { if asks { onSystemPrompt(false) } }
        do {
            switch send {
            case let .note(note, previousID): try await destination.sync(note, replacing: previousID)
            case let .erase(erasure): try await destination.sync(erasure)
            }
            hasNotesAnswer = true
            sendSucceeded(send, scope: scope, countsAsSave: countsAsSave, isRetry: isRetry)
        } catch {
            let reason = error as? NookAppleNotesError ?? .failed
            NookNotesLog.failure("send to Apple Notes", error: error)
            // A refusal is an answer too. Any other failure may have come
            // before macOS asked.
            if reason == .notPermitted { hasNotesAnswer = true }
            sendFailed(send, scope: scope, reason: reason, isRetry: isRetry)
        }
    }

    private func sendSucceeded(_ send: Send, scope: String, countsAsSave: Bool, isRetry: Bool) {
        didNoticeAppleNotes = false
        setAppleNotesProblem(nil)
        // A note saved again has another send in line, which is still owed.
        if leaveLine(send, scope: scope) {
            switch send {
            case let .note(note, _): backlog.remove(noteID: note.id, scope: scope)
            case let .erase(erasure): backlog.remove(erasure, scope: scope)
            }
        }
        if countsAsSave { savedCount += 1 }
        // Notes is taking notes again: what it did not take is sent now.
        if !isRetry { retryBacklog() }
    }

    /// The send is kept to be tried again, and the reason stays where the
    /// user can read it. The closed island says it once, until a send works.
    private func sendFailed(_ send: Send, scope: String, reason: NookAppleNotesError, isRetry: Bool) {
        _ = leaveLine(send, scope: scope)
        switch send {
        case let .note(note, _): backlog.add(noteID: note.id, scope: scope)
        case let .erase(erasure): backlog.add(erasure, scope: scope)
        }
        setAppleNotesProblem(reason == .notPermitted ? .notPermitted : .failed)
        guard !isRetry, !didNoticeAppleNotes, let notice = appleNotesNotice else { return }
        didNoticeAppleNotes = true
        onNotice(notice)
    }

    private func setAppleNotesProblem(_ next: AppleNotesProblem?) {
        guard next != appleNotesProblem else { return }
        appleNotesProblem = next
        if let next {
            defaults.set(next.rawValue, forKey: Self.appleProblemKey)
        } else {
            defaults.removeObject(forKey: Self.appleProblemKey)
        }
    }

    /// Sends again what Notes did not take. A note that is gone by now is
    /// let go of.
    private func retryBacklog() {
        guard saveTo.usesAppleNotes else { return }
        let scope = syncScope
        for id in backlog.noteIDs(scope: scope) {
            // A send already in line for it is the retry.
            guard inLine[Send.noteKey(id, scope: scope)] == nil else { continue }
            do {
                guard let note = try destination.read(id: id) else {
                    backlog.remove(noteID: id, scope: scope)
                    continue
                }
                enqueue(.note(note, replacing: nil), isRetry: true)
            } catch {
                NookNotesLog.failure("read a note to send it again", path: folderURL.appendingPathComponent(id).path, error: error)
            }
        }
        for erasure in backlog.erasures(scope: scope) where inLine[Send.erase(erasure).key(scope: scope)] == nil {
            enqueue(.erase(erasure), isRetry: true)
        }
    }

    // MARK: Choosing where notes go

    /// Saves notes somewhere else from now on. The notes already saved stay
    /// where they are.
    func setSaveTo(_ next: NookNotesSaveTo) {
        guard next != saveTo else { return }
        moveDestination {
            saveTo = next
            defaults.set(next.rawValue, forKey: Self.saveToKey)
        }
    }

    /// Keeps notes in another folder. The notes already saved stay where
    /// they are.
    func setFolder(_ url: URL) {
        moveDestination {
            folderURL = url
            defaults.set(url.path, forKey: Self.folderKey)
        }
    }

    /// Changes the place notes are kept. A note being typed is saved in the
    /// old place first; one that cannot be saved there, which is a likely
    /// reason to be changing the place, is carried to the new one.
    private func moveDestination(_ change: () -> Void) {
        let stuck = flush() ? nil : editorText
        // The stash of a note that could not be saved goes with it.
        let carriedStash = stuck == nil ? nil : (id: stashID, isStashed: isStashed)
        closeEditorState()
        problem = nil
        change()
        destination = Self.makeDestination(
            saveTo, folder: folderURL, defaults: defaults, bridge: bridge,
            recordURL: recordURL, calendar: calendar, now: now, trash: trash, iCloud: iCloud
        )
        notes = []
        watching = .nothing
        reportStandingProblem()
        reload()
        watchFolder()
        if let stuck {
            present(text: stuck, noteID: nil, created: now(), savedText: "")
            if let carriedStash {
                stashID = carriedStash.id
                isStashed = carriedStash.isStashed
            }
            _ = flush()
        }
    }

    // MARK: The old Quick Notes file

    /// Moves the old Quick Notes file in as one note, the first time only.
    /// The old file stays where it is.
    private func importOldNotesIfNeeded() {
        guard !defaults.bool(forKey: Self.importedKey) else { return }
        let old = NookNoteLocations.oldNotesFile(storedPath: defaults.string(forKey: Self.legacyPathKey), home: home)
        // An old file already in the notes folder is a note there.
        let isInTheFolder = saveTo.usesFolder
            && old.deletingLastPathComponent().standardizedFileURL.path == folderURL.standardizedFileURL.path
        guard !isInTheFolder else {
            defaults.set(true, forKey: Self.importedKey)
            return
        }
        let raw: String
        switch readOldFile(old) {
        case .missing:
            // There is nothing to move in, and nothing on its way from iCloud.
            defaults.set(true, forKey: Self.importedKey)
            return
        case .unavailable:
            // Not marked done: it is tried again at the next launch.
            report(.notImported)
            return
        case let .text(contents):
            raw = contents
        }
        guard let text = NookNoteFiles.importedText(fromOldFile: raw) else {
            defaults.set(true, forKey: Self.importedKey)
            return
        }
        let modified: Date?
        do {
            modified = try old.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        } catch {
            NookNotesLog.failure("read the date of the old Quick Notes", path: old.path, error: error)
            modified = nil
        }
        let stamp = now()
        do {
            let note = try destination.write(text: text, id: nil, created: modified ?? stamp, now: stamp)
            defaults.set(true, forKey: Self.importedKey)
            enqueue(.note(note, replacing: nil))
        } catch {
            // Tried again at the next launch.
            NookNotesLog.failure("move the old Quick Notes in", path: old.path, error: error)
            report(.notImported)
        }
    }

    private enum OldFile {
        /// No file, and no stand-in for one iCloud has not downloaded.
        case missing
        /// A file that is there and cannot be read now, or is on its way.
        case unavailable
        case text(String)
    }

    /// Reads the old file. Only a file that is not there, and has no iCloud
    /// stand-in, is "missing": any other failure to read is not an empty
    /// file, and the import is not given up on.
    private func readOldFile(_ url: URL) -> OldFile {
        if iCloud.isNotDownloaded(url) {
            askICloudFor(url)
            return .unavailable
        }
        do {
            return .text(try String(contentsOf: url, encoding: .utf8))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            guard FileManager.default.fileExists(atPath: NookNoteICloud.standIn(for: url).path) else { return .missing }
            askICloudFor(url)
            return .unavailable
        } catch let error as CocoaError where [.fileReadInapplicableStringEncoding, .fileReadCorruptFile].contains(error.code) {
            // Not UTF-8: let the system find the encoding the file is in.
            var encoding = String.Encoding.utf8
            do {
                return .text(try String(contentsOf: url, usedEncoding: &encoding))
            } catch {
                NookNotesLog.failure("read the old Quick Notes in any encoding", path: url.path, error: error)
                return .unavailable
            }
        } catch {
            NookNotesLog.failure("read the old Quick Notes", path: url.path, error: error)
            askICloudFor(url)
            return .unavailable
        }
    }

    private func askICloudFor(_ url: URL) {
        do {
            try iCloud.startDownload(url)
        } catch {
            // A file that is not in iCloud has nothing to download.
            NookNotesLog.warning("iCloud was asked for the old Quick Notes and did not take it up", path: url.path)
        }
    }
}
